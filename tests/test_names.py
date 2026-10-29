"""Compare Lua inference with the upstream methods and explicit reading cases."""
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
from probe_pos import reference

class Names(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.cases=[
            ['Harry','Potter','met','Hermione','Granger','.'],
            ['The','potter','made','a','clay','bowl','.'],
            ['After','dinner,','the','boy','walked','home.'],
            ["Harry's",'friend','met',"Potter's",'family','.'],
            ['Harry','Potter','met','a','potter','in','the','village','.'],
            ['HARRY','POTTER','was','at','school','.'],
            ['Alice','said','hello','to','John','Smith','.'],
        ]
        with tempfile.TemporaryDirectory() as tmp:
            input,output=Path(tmp)/'input.json',Path(tmp)/'output.json'
            input.write_text(json.dumps(cls.cases))
            bundle=Path('/Applications/KOReader.app/Contents/koreader')
            subprocess.run([str(bundle/'luajit'),str(ROOT/'tests/native_names.lua'),str(ROOT),str(input),str(output)],
                cwd=bundle,check=True,capture_output=True)
            cls.results=json.loads(output.read_text())

    def test_all_tags_match_original_model_inference(self):
        original=reference()
        for row in self.results:
            self.assertEqual(row['tags'],[tag for _,tag in original.tag(row['tokens'])])

    def test_names_and_possessive_names_are_protected(self):
        self.assertEqual(self.results[0]['protected'],4)
        self.assertEqual(self.results[3]['protected'],2)
        self.assertEqual(self.results[5]['protected'],2)

    def test_common_potter_and_sentence_initial_after_remain(self):
        self.assertIn('potter',[w['text'] for w in self.results[1]['kept']])
        self.assertIn('After',[w['text'] for w in self.results[2]['kept']])

    def test_name_occurrence_does_not_consume_ordinary_word(self):
        kept=[w['text'] for w in self.results[4]['kept']]
        self.assertNotIn('Potter',kept)
        self.assertIn('potter',kept)

if __name__=='__main__':unittest.main()
