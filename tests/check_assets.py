"""Validate every StarDict offset, level record, license and packaged resource."""
import hashlib
import json
import struct
import unittest
import zipfile
import sys
import csv
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PLUGIN = ROOT / "wordwise.koplugin"
sys.path.insert(0, str(ROOT / "tools"))
from build_package import short_gloss, read_exam, grade_word, read_database, add_contractions, VERSION


class Assets(unittest.TestCase):
    def test_forward_dictionary_inflections_supply_missing_lemma(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)/"dictionary.csv"
            with path.open("w", newline="") as stream:
                writer = csv.DictWriter(stream,fieldnames=["word","translation","exchange"])
                writer.writeheader()
                writer.writerows([
                    {"word":"be","translation":"是","exchange":"p:was"},
                    {"word":"was","translation":"过去式","exchange":""},
                    {"word":"see","translation":"看见","exchange":"p:saw"},
                    {"word":"saw","translation":"锯","exchange":""},
                ])
            data, rejected = read_database(path)
            self.assertFalse(rejected)
            self.assertEqual(grade_word("was", data["was"]["lemma"], {"be":0}), 0)
            self.assertEqual(grade_word("saw",data["saw"]["lemma"],{"see":0,"saw":2}),0)

    def test_contractions_have_complete_expansions_and_component_based_levels(self):
        data = {"what":{"gloss":"什么","lemma":None}}
        cefr = {"what":0,"is":0,"has":0}
        add_contractions(data,cefr,ROOT / "sources/grammar-contractions.tsv")
        self.assertEqual(cefr["what's"],0)
        self.assertEqual(data["what's"]["gloss"],"what is／what has 的缩写")
        self.assertNotIn("…", data["what's"]["gloss"])

    def test_one_exam_stage_with_explicit_inflection_membership(self):
        grades = read_exam(ROOT / "sources/exam")
        self.assertEqual(grades["apple"],0)
        for word in ('the','and','be','am','is','are','has','I'.lower()):self.assertEqual(grades[word],0)
        self.assertEqual(grades["nomenclature"],5)
        self.assertEqual(grade_word("hurried", "hurry", grades),0)
        self.assertEqual(grade_word("unmatched-word", None, grades), 5)
        self.assertEqual(grade_word("form", "base", {"form":4,"base":2}), 2)
        self.assertEqual(grade_word("inflection", "base", {"base":2}),2)

    def test_reported_words_are_present_without_invented_grades(self):
        records = {}
        for line in (PLUGIN / "data/levels.tsv").read_text().splitlines():
            if not line.startswith("#"):
                word, level, rank = line.split("\t")
                records[word] = int(level)
        expected = {"hurried":0,"hurry":0,"was":0,"were":0,"shoulder":1,"shoulders":1}
        self.assertEqual(len(records),30_000)
        for word, level in expected.items():
            self.assertEqual(records[word], level, word)

    def test_ecdict_markers_are_parsed_from_original_not_truncated_text(self):
        self.assertEqual(short_gloss("n. <美>飞机( airplane的复数形式 )"), "飞机")
        self.assertEqual(short_gloss("n. <物>（粒子）加速器( accelerator的复数形式 )"), "（粒子）加速器")
        self.assertEqual(short_gloss("a. 宝贵的, 珍贵的, 珍爱的"), "宝贵的")
        self.assertEqual(short_gloss("n. (大学)研究生助教奖学金"), "(大学)研究生助教奖学金")
        self.assertEqual(short_gloss("n. 荷马史诗<<奥德赛>>中的女魔, 妖精似地引诱男子的女人"), "荷马史诗《奥德赛》中的女魔")
        self.assertEqual(short_gloss("n. [复数，动词用单数]；美学"), "美学")
        self.assertEqual(short_gloss("n. 恩格尔（恩格尔 \t德国的统计学家）"), "恩格尔（恩格尔 德国的统计…")

    def test_stardict_and_level_index_match_for_every_word(self):
        levels = {}
        for line in (PLUGIN / "data/levels.tsv").read_text().splitlines():
            if line.startswith("#"):
                continue
            word, level, rank = line.split("\t")
            self.assertIn(int(level), range(6))
            self.assertGreater(int(rank), 0)
            self.assertNotIn(word,levels)
            levels[word] = (level, rank)
        self.assertEqual({int(rank) for _,rank in levels.values()},set(range(1,30_001)))
        base = PLUGIN / "data/dict/readassist-short/readassist-short"
        index = base.with_suffix(".idx").read_bytes()
        definitions = base.with_suffix(".dict").read_bytes()
        position, words, end_offset = 0, [], 0
        while position < len(index):
            end = index.index(0, position)
            word = index[position:end].decode("ascii")
            offset, length = struct.unpack_from(">II", index, end + 1)
            position = end + 9
            self.assertEqual(offset, end_offset)
            self.assertGreater(length, 0)
            gloss = definitions[offset:offset + length].decode("utf-8")
            self.assertTrue(gloss)
            self.assertNotIn("\n", gloss)
            words.append(word)
            end_offset = offset + length
        self.assertEqual(end_offset, len(definitions))
        self.assertTrue(set(levels).issubset(words))
        self.assertEqual(len(words), json.loads((PLUGIN / "manifest.json").read_text())["dictionary_records"])
        self.assertEqual(words, sorted(words, key=str.lower))
        ifo = base.with_suffix(".ifo").read_text()
        self.assertIn(f"wordcount={len(words)}\n", ifo)
        self.assertIn(f"idxfilesize={len(index)}\n", ifo)

    def test_model_digest_matches_manifest(self):
        manifest = json.loads((PLUGIN / "manifest.json").read_text())
        model = PLUGIN / "models/eng.traineddata"
        self.assertEqual(hashlib.sha256(model.read_bytes()).hexdigest(), manifest["model_sha256"])
        for name,digest in manifest['pos_model_sha256'].items():
            self.assertEqual(hashlib.sha256((PLUGIN/'models/pos'/name).read_bytes()).hexdigest(),digest)
        self.assertEqual(hashlib.sha256((ROOT/'sources/exam/additional-evidence.json').read_bytes()).hexdigest(),manifest['additional_evidence_sha256'])
        rows=json.loads((ROOT/'sources/exam/additional-evidence.json').read_text())['records']
        for word,source,level in [('hurry','moe-senior-2020',1),('heave','neea-cet-2016',4),('help','neea-cet-2016',3),('intact','neea-cet-2016',3)]:
            self.assertTrue(any(r['word']==word and r['source']==source and r['level']==level for r in rows))

    def test_licenses_are_present_and_complete(self):
        expected = {"AGPL-3.0.txt": 30000, "TESSDATA_LICENSE": 10000,
                    "ECDICT_LICENSE": 900, "ECDICT_UPSTREAM_LICENSE": 900,"POS_TAGGER_MIT.txt":900,
                    "WORD_FREQUENCY_CC_BY_SA_4.0.txt":19000,
                    "WORD_FREQUENCY_NOTICE.md":2000}
        for name, minimum_size in expected.items():
            self.assertGreater((PLUGIN / "licenses" / name).stat().st_size, minimum_size)
        attribution = (PLUGIN / "licenses/CEFR_J_ATTRIBUTION.md").read_text()
        self.assertIn("Tono Laboratory at TUFS", attribution)
        self.assertIn("Attribution-ShareAlike 4.0", attribution)

    def test_zip_installs_only_plugin_and_docs(self):
        archive = ROOT / f"dist/WordWise-Kindle-Scribe-v{VERSION}.zip"
        with zipfile.ZipFile(archive) as package:
            names = package.namelist()
            self.assertIsNone(package.testzip())
            self.assertTrue(all(name.startswith(("koreader/plugins/wordwise.koplugin/", "WordWise-docs/")) for name in names))
            self.assertTrue(any(name.endswith("models/eng.traineddata") for name in names))
            self.assertFalse(any("tests/fixtures" in name for name in names))
            self.assertFalse(any(name.endswith(".idx.oft") for name in names))
            for name in ("main.lua", "wordwise_core.lua", "wordwise_ocr.lua", "wordwise_text.lua",
                         "wordwise_label.lua", "wordwise_controls.lua", "wordwise_names.lua", "wordwise_prefetch.lua"):
                self.assertEqual(package.read("koreader/plugins/wordwise.koplugin/"+name),
                                 (PLUGIN / name).read_bytes())

    def test_every_index_entry_has_audited_unique_stage(self):
        audit=json.loads((PLUGIN/'data/level-audit.json').read_text())
        self.assertEqual(len(audit),30000)
        self.assertEqual(len({row['word'] for row in audit}),30000)
        manifest=json.loads((PLUGIN/'manifest.json').read_text())
        self.assertEqual(sum(manifest['group_counts'].values()),30000)
        self.assertEqual(manifest['graded_records']+manifest['extension_records'],30000)
        for row in audit:
            if row['evidence']:
                self.assertEqual(row['level'],min(x['level'] for x in row['evidence']),row['word'])
        hurried=next(r for r in audit if r['word']=='hurried')
        self.assertEqual(hurried['origin'],'lemma:hurry')


if __name__ == "__main__":
    unittest.main()
