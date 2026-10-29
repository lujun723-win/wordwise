# 第三方资源与署名

- KOReader 2026.07.1：https://github.com/koreader/koreader/tree/v2026.07.1 ，AGPL-3.0-or-later。本插件使用其 API，未分发修改后的核心二进制。
- 0.4.0 国内阶段词形：教育部《义务教育英语课程标准（2022年版）》附录3二级词表、PEP教材与对应备考词表；数据来源、固定提交与摘要见data/exam-sources.json。只提取词形及所属阶段，不分发词书释义、例句、图片、音频；生成一词一级的事实索引，不冒充官方统一考试标准。
- 离线专名保护：NLTK averaged_perceptron_tagger_eng，Matthew Honnibal / NLTK，MIT。源码 https://github.com/nltk/nltk/blob/develop/nltk/tag/perceptron.py ，模型 https://github.com/nltk/nltk_data/tree/gh-pages/packages/taggers ，保留licenses/POS_TAGGER_MIT.txt。Lua推理移植保留原特征与权重，未使用ACE实体模型。
- libk2pdfopt：https://github.com/koreader/libk2pdfopt ，AGPL-3.0-or-later。由用户已安装的 KOReader 提供。
- Tesseract tessdata 4.1.0 英文模型：https://github.com/tesseract-ocr/tessdata/blob/4.1.0/eng.traineddata ，Apache-2.0，见 licenses/TESSDATA_LICENSE。
- ECDICT：https://github.com/skywind3000/ECDICT ，MIT。0.2.0 直接使用下载的 ecdict.csv 快照生成短释义与明确词形关系，不再用旧 vocabulary_hints.dat 的词频估级。保留 ECDICT_LICENSE 和 ECDICT_UPSTREAM_LICENSE。
- 历史0.2–0.3版本使用CEFR-J与Octanove；0.4.0已按用户选择改为国内阶段索引，旧署名文件保留，不声称现有国内等级由CEFR等值换算。
- wordfreq：Robyn Speer，https://github.com/rspeer/wordfreq 。用英语词频数据库筛选三万常用词。数据 CC BY-SA 4.0；保留 WORD_FREQUENCY_NOTICE.md、CC BY-SA 4.0 完整文本及代码许可。保留对 SUBTLEX 作者 Marc Brysbaert 等人的致谢；SUBTLEX 是可自由获取的数据。相关语料来源与完整署名见原作者 NOTICE。
- 派生 data/levels.tsv 采用 CC BY-SA 4.0，三万词、一词一级、明确词形继承，未匹配词按用户规则进入专八显示档。ECDICT 中文短释义词典仍按 MIT 许可分发。
- James Zhu 的 ReadAssist：https://github.com/James-Zhu-CA/ReadAssist ，MIT。Supernote 数据资产由该项目的二次开发工作衍生；本插件的 Lua 实现独立编写，非官方版本。
- 常用缩写的完整展开形式为独立整理的语言事实，参考 Cambridge English Grammar Today：https://dictionary.cambridge.org/grammar/british-grammar/contractions 。没有复制其释义或例句；缩写分级由展开成分计算，单独审计，不声称 Cambridge 提供 CEFR 等级。来源表、派生索引按本项目数据 CC BY-SA 4.0 分发。

完整构建资源的摘要与词条数见 manifest.json。词典为 ECDICT 的短释义衍生版本，不冒充完整词典。
