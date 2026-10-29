# 固定在线数据快照

当前0.4.0采用sources/exam的国内六阶段词表，本目录仅ECDICT与wordfreq是构建输入；下文CEFR资料为旧版来源记录。派生索引不再包含现行CEFR分级。

下载与核对日期：2026-10-26。后续构建复用这些本地文件，不重复联网。

- ECDICT：`https://github.com/skywind3000/ECDICT/blob/master/ecdict.csv`，MIT；官方 Git blob SHA-1 `0e527e22e0e0d22f012b0ed251a8dddd5891773b` 已按 Git blob 算法核对。
- wordfreq 英语词频：`https://github.com/rspeer/wordfreq/blob/master/wordfreq/data/large_en.msgpack.gz`；Git blob SHA-1 `c754e8ecf6ae76ad2f7c9a47c69be26a26fa8c29` 已核对。作者 Robyn Speer，数据 CC BY-SA 4.0，代码 Apache-2.0。完整署名和 SUBTLEX 等来源见原 NOTICE。词频语料约截至 2021 年，不是实时英语词频。
- CEFR-J Vocabulary Profile 1.5：`https://github.com/openlanguageprofiles/olp-en-cefrj/blob/master/cefrj-vocabulary-profile-1.5.csv`。Yukio Tono / Tono Laboratory at TUFS，注明来源后可按原条款使用。
- Octanove Vocabulary Profile C1/C2 1.0：`https://github.com/openlanguageprofiles/olp-en-cefrj/blob/master/octanove-vocabulary-profile-c1c2-1.0.csv`，Octanove Labs，CC BY-SA 4.0。

以上 CSV 和压缩文件通过 GitHub 官方 contents API 的 raw 媒体类型取得；raw 域名超时时切换同源接口，没有换未知数据源。每个实际输入的 SHA-256 已写入插件 manifest.json。

筛选规则：在 wordfreq 的降频顺序中，选取 ECDICT 有有效中文短释义的 30,000 个标准小写英文拼写。CEFR-J 与 Octanove 同属 CEFR 框架，每词多项记录取最低学习等级；ECDICT exchange 字段明确的原型关系可继承。没有源等级或不在三万范围的词按用户要求进入专八／扩展组，不推断或假造官方难度。

中文短释义的原始无效条目不修补，完整审计位于插件 data/source-audit.json。派生 levels.tsv 含词频与 C1/C2 分级数据，按 CC BY-SA 4.0 分发，须保留署名与修改说明。原始数据快照不自动加入安装包，插件只携带派生资源、必要许可和英文 OCR 模型。
