# 离线专名保护

模型：NLTK averaged_perceptron_tagger_eng（MIT），原始包：https://raw.githubusercontent.com/nltk/nltk_data/gh-pages/packages/taggers/averaged_perceptron_tagger_eng.zip 。原始推理源码：https://github.com/nltk/nltk/blob/develop/nltk/tag/perceptron.py 。作者Matthew Honnibal，NLTK移植Long Duong；许可保留于MIT-LICENSE及随包licenses/POS_TAGGER_MIT.txt。

Lua推理保持上游特征、权重及同分按标签字母顺序取大的规则。tests/test_names.py直接执行保存的上游原始方法，与Lua每个输出标签比对；不要求安装Python NLTK，Kindle也不运行Python。

在大小写折叠、去重、分级和查词之前，略过NNP／NNPS专有名词。包含人名、地名等，并非PERSON专用实体模型。已验证Harry Potter、Hermione Granger、John Smith、姓名所有格和大写姓名；普通potter及句首After保留。同页姓名Potter不占用后面普通potter的查词位置。全小写姓名、OCR错字、小说新造姓名及歧义仍可能误判，不按整本书屏蔽同一拼写。

未使用许可元数据不明的ACE实体模型；sources/nlp-audit仅为调研资料，不进入插件包。默认模型约5.7MB JSON，复用KOReader JSON与LuaJIT，无新平台二进制依赖；首次加载后只保留当前阅读实例。
