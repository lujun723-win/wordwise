# 开发、构建与测试

## 技术栈

目标为 Kindle Scribe / KOReader 2026.07.1。使用 LuaJIT 2.1 / Lua 5.1、KOReader随包CREngine、MuPDF、KOPTContext、sdcv和字体接口，不修改阅读器核心。无需Android Studio、JDK、APK签名或在阅读器安装Python。

文字版读原文与坐标；扫描页才离线OCR。OCR使用随包模型和PSM_SINGLE_WORD，关闭std_proc拼写后处理。词典使用独立data_dir批量精确查询，不改变用户词典设置。

ReaderView提示层按实际字形裁空白，字号不变；中文与横括号共同碰撞检查。按钮只接管自身区域，状态栏对象为ReaderView.footer。滑块复用原生点击／拖动；自动识别延迟0.5秒，翻页、排版、关闭及休眠作废旧结果。

## 分级、专名与行距

0.4.1的wordwise_prefetch.lua在KOReader已有fork子进程中取相邻页原文、查词并返回提示坐标，不触发主ReaderUI翻页事件。主进程通过管道取结果，读取前确认有输出；关闭、休眠、布局变化取消并回收子进程。只缓存当前／前／后三页的文字结果；绘图前检查原生布局hash、尺寸、偏移、难度、字号、上限和按钮配置。命中缓存时在ReaderView同帧绘制，不再setDirty另刷一次。native_reader.lua覆盖真实相邻页首帧与主进程阅读位置，native_prefetch.lua覆盖大管道传输、错误上报、取消及进程组创建竞争；不新增平台运行时。

- sources/exam保留国内六阶段词表与固定来源。课标转录经过逐页目视核对，不猜修正PDF的OCR文本。
- 每词和明确屈折关系取最早来源阶段，不再让独立词条较高等级覆盖基础原型；读取ECDICT的0原型与p/d/i/3/r/t/s正向关系，不猜词尾。无来源及范围外进入专八显示档，与实际收录分开。
- tools/compare_official_levels.py使用pypdf读取官方高中课标、CET大纲的指定词表页，结合ECDICT标签，生成additional-evidence.json。原始PDF文件名、来源和范围见脚本；摘要与页码随生成数据保留。只支持明确电子文本行，排除并记录缩略或不支持的行，不运行OCR或拼写修补。
- MIT averaged perceptron模型的NNP/NNPS过滤先于小写和去重。Lua推理复用KOReader JSON，无新平台二进制。tests/test_names.py与保存的上游方法对照，不安装NLTK。
- EPUB用ui.font:onSetLineSpace(200)，原值存每书doc_settings。关闭时若仍为200则恢复，主动改过则保留；固定PDF不调用该接口。

## 直接重打包

仓库包含已生成的完整插件资源。只改Lua或说明时不必重建词典：

```sh
python3 - <<'PY'
import json, sys
from pathlib import Path
sys.path.insert(0, 'tools')
from build_package import package
print(package(json.loads(Path('wordwise.koplugin/manifest.json').read_text())))
PY
python3 tests/check_assets.py
```

版本号同时维护tools/build_package.py的VERSION、manifest.json和主界面关于说明。打包排除.idx.oft缓存，不含本机配置或阅读文件。

## 重建数据

大型原始数据不纳入Git。按sources/online/README.md固定来源下载ECDICT与wordfreq，核对manifest.json中的SHA-256后放到相应路径。国内词表及课标转录已纳入仓库；sources/nlp包含MIT模型及上游推理源码，插件models包含英文OCR模型。

```sh
python3 -m pip install --no-deps --target .build-deps -r tools/build-requirements.txt
python3 tools/build_package.py \
  --model wordwise.koplugin/models/eng.traineddata \
  --ecdict-csv sources/online/ecdict.csv \
  --frequency sources/online/large_en.msgpack.gz \
  --exam-dir sources/exam
python3 tests/check_assets.py
```

msgpack==1.1.2仅供构建；已有.build-deps时复用。普通重打包无需它。旧CEFR仅为本地历史资料，当前不读取，也不使用已删除的--cefr参数。

## 测试

```sh
luajit tests/run.lua
python3 tests/check_assets.py
python3 tests/test_names.py
python3 tests/test_native_sdcv.py --koreader-dir /Applications/KOReader.app/Contents/koreader
python3 tests/test_model_ocr.py
```

原生集成依赖官方Mac KOReader；OCR模型测试使用已有Tesseract与Pillow。测试脚本默认官方Mac安装路径，其它平台需调整启动路径；这些都不是插件运行依赖。

原生测试从官方KOReader包目录启动，使用独立KO_HOME，以及SDL_VIDEODRIVER=dummy、SDL_RENDER_DRIVER=software、EMULATE_READER_W=1200、EMULATE_READER_H=1600。native_controls.lua、native_text.lua、native_pdf.lua参数为项目绝对目录、输出前缀。native_page.lua另需1200×1656页面测试截图，该用户截图未公开上传。

native_reader.lua验证完整ReaderUI、按钮触摸、实际翻页和关闭停止。运行前在独立KO_HOME/plugins下链接项目插件，设置WORDWISE_PROJECT为项目绝对路径，并创建输出目录。夹具为tests/fixtures内的测试文本。须恢复起始页与按钮状态，不能依赖上次设置；不使用用户真实KO_HOME。

先结束读取词典的测试，再重建数据，最后检查最终ZIP，不并行读写词典。部署前正常退出并备份旧插件，完整替换后重启检查。Kindle结果单独记录，不能用Mac测试代替。
