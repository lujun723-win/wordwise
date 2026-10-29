"""Check the real desktop sdcv boundary, not a hand-written lookup mock."""
import argparse
import json
import subprocess
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument("--koreader-dir", type=Path, required=True)
options, unittest_args = parser.parse_known_args()


class NativeDictionary(unittest.TestCase):
    def test_real_sdcv_short_definitions(self):
        words = ["preface", "precious", "someone", "intricate", "management", "what's"]
        result = subprocess.run([
            str(options.koreader_dir / "sdcv"), "--utf8-input", "--utf8-output",
            "--json-output", "--non-interactive", "--only-data-dir",
            "--data-dir", str(ROOT / "wordwise.koplugin/data/dict"),
            "--use-dict", "ReadAssist ECDICT Short", "--exact-search", "--", *words,
        ], cwd=options.koreader_dir, check=True, capture_output=True, text=True)
        entries = [json.loads(line) for line in result.stdout.splitlines()]
        self.assertEqual(len(entries), len(words))
        for word, found in zip(words, entries):
            self.assertEqual(len(found), 1)
            self.assertEqual(found[0]["dict"], "ReadAssist ECDICT Short")
            self.assertEqual(found[0]["word"], word)
            gloss = found[0]["definition"].strip()
            self.assertTrue(gloss)
            self.assertFalse(any(char in gloss for char in "\r\n\t<>"))
        self.assertEqual(entries[0][0]["definition"].strip(), "序")
        self.assertEqual(entries[1][0]["definition"].strip(), "宝贵的")
        self.assertEqual(entries[-1][0]["definition"].strip(), "what is／what has 的缩写")


if __name__ == "__main__":
    unittest.main(argv=[__file__, *unittest_args])
