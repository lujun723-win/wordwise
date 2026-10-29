"""Host smoke test of the actual bundled English model (not a Kindle test)."""
import csv
import io
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]


class EnglishModel(unittest.TestCase):
    def test_single_word_with_actual_offline_model(self):
        font = ImageFont.truetype("/System/Library/Fonts/Supplemental/Arial.ttf", 72)
        image = Image.new("L", (480, 140), 255)
        ImageDraw.Draw(image).text((35, 20), "precious", fill=0, font=font)
        with tempfile.TemporaryDirectory(prefix="wordwise-model-") as directory:
            fixture = Path(directory) / "word.png"
            image.save(fixture)
            executable = shutil.which("tesseract")
            self.assertIsNotNone(executable)
            result = subprocess.run(
                [executable, str(fixture), "stdout", "--tessdata-dir",
                 str(ROOT / "wordwise.koplugin/models"), "-l", "eng", "--psm", "8",
                 "-c", "tessedit_create_tsv=1"],
                capture_output=True, text=True, check=True, timeout=30,
            )
        rows = list(csv.DictReader(io.StringIO(result.stdout), delimiter="\t"))
        words = [row for row in rows if row["level"] == "5" and row["text"].strip()]
        self.assertEqual([row["text"].lower() for row in words], ["precious"],
                         msg=f"stdout={result.stdout!r}, stderr={result.stderr!r}")
        self.assertGreater(int(words[0]["width"]), 0)
        self.assertGreater(int(words[0]["height"]), 0)


if __name__ == "__main__":
    unittest.main()
