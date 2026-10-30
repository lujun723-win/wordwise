#!/usr/bin/env python3
"""Build offline hints from downloaded ECDICT and wordfreq snapshots."""
from __future__ import annotations
import argparse
import csv
import gzip
import hashlib
import json
import re
import shutil
import struct
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PLUGIN = ROOT / "wordwise.koplugin"
BOOKNAME = "ReadAssist ECDICT Short"
VERSION = "0.4.4-preview"
COMMON_COUNT = 30_000
WORD = re.compile(r"^[a-z][a-z'-]{1,29}$")
EXAM_FILES = ("primary", "junior", "senior", "cet4", "cet6")


def read_exam(directory: Path) -> dict[str, int]:
    levels = {}
    for row in (directory/'primary-curriculum-2022.tsv').read_text().splitlines():
        if not row.startswith('#'):
            _,words=row.split('\t')
            for word in words.split():
                for variant in word.lower().split('/'):
                    if re.fullmatch(r"[a-z][a-z'-]{0,29}",variant):levels[variant]=0
    for row in (directory/'primary-curriculum-aliases.tsv').read_text().splitlines():
        if not row.startswith('#'):
            _,words=row.split('\t')
            for word in words.lower().split():
                if re.fullmatch(r"[a-z][a-z'-]{0,29}",word):levels[word]=0
    for level, name in enumerate(EXAM_FILES):
        for word in (directory / (name + ".txt")).read_text().splitlines():
            if re.fullmatch(r"[a-z][a-z'-]{0,29}", word):
                levels.setdefault(word, level)
    for row in json.loads((directory/'additional-evidence.json').read_text())['records']:
        levels[row['word']]=min(levels.get(row['word'],5),row['level'])
    return levels


def source_lemma(lemma: str | tuple | None, grades: dict[str, int]) -> str | None:
    candidates = (lemma,) if isinstance(lemma, str) else (lemma or ())
    matches = [base for base in candidates if base in grades]
    return min(matches, key=lambda base: (grades[base], base)) if matches else None


def grade_word(word: str, lemma: str | tuple | None, grades: dict[str, int]) -> int:
    base = source_lemma(lemma, grades)
    # A spelling can also be a basic inflection: use the earliest attested
    # learning stage across the spelling and its explicitly recorded lemmas.
    return min(grades.get(word,5),grades[base] if base is not None else 5)


def add_contractions(database: dict, grades: dict, path: Path) -> dict:
    """Explicit grammar entries, not OCR correction or suffix inference.

    A full-form phrase needs every component's level (max); a contraction with
    alternatives uses the earliest complete phrase (min), like other senses.
    """
    entries = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        if not line or line.startswith("#"):
            continue
        word, forms = line.split("\t")
        assert word not in entries and WORD.fullmatch(word)
        alternatives = forms.split("|")
        levels = []
        for form in alternatives:
            components = [grade_word(part, database.get(part, {}).get("lemma"), grades)
                          for part in form.split()]
            levels.append(max(components))
        # Keep the explanation complete, including both is/has alternatives.
        database[word] = {"lemma": None, "gloss": "／".join(alternatives) + " 的缩写"}
        grades[word]=min(grades.get(word,5),min(levels))
        entries[word] = {"forms": alternatives, "level": grades[word]}
    return entries


def short_gloss(definition: str) -> str | None:
    for line in definition.splitlines():
        line = line.strip()
        if not line or line.startswith(("*", "[原型]", "[时态]")):
            continue
        if re.fullmatch(r"\([中高四六研雅托宝\s\d/\-]+\)", line):
            continue
        if not re.search(r"[\u3400-\u9fff]", line):
            continue
        line = re.sub(r"^(?:[a-z]{1,6}\.)+\s*", "", line, flags=re.I)
        line = re.sub(r"<<([^<>]+)>>", r"《\1》", line)
        line = re.sub(r"<[^<>]+>", "", line)
        line = re.sub(r"^[\[【][^\]】]+[\]】]\s*", "", line)
        line = re.sub(r"\(\s*[A-Za-z][A-Za-z' -]*的[^)]*\)", "", line)
        line = line.lstrip(" ,，;；")
        depth, end = 0, len(line)
        for i, char in enumerate(line):
            if char in "([（【":
                depth += 1
            elif char in ")]）】":
                depth = max(0, depth - 1)
            elif char in ",，;；" and depth == 0:
                end = i
                break
        line = " ".join(line[:end].split())
        if line:
            return line if len(line) <= 14 else line[:13] + "…"
    return None


def read_database(path: Path) -> tuple[dict, list]:
    records, rejected, inflections = {}, [], {}
    with path.open(encoding="utf-8", newline="") as stream:
        for row in csv.DictReader(stream):
            word = row["word"]
            if not WORD.fullmatch(word):
                continue
            exchanges = dict(part.split(":", 1) for part in row["exchange"].split("/") if ":" in part)
            # ECDICT stores both base->form and form->base. Read the explicit
            # forward relationships too; e.g. was lacks 0:be, but be has p:was.
            for kind, form in exchanges.items():
                if kind in {"p", "d", "i", "3", "r", "t", "s"} and WORD.fullmatch(form):
                    inflections.setdefault(form, set()).add(word)
            gloss = short_gloss(row["translation"].replace("\\\\n", "\n").replace("\\n", "\n"))
            if not gloss:
                continue
            if any(char in gloss for char in "\r\n\t<>"):
                rejected.append({"word": word, "gloss": gloss, "reason": "invalid source text; not repaired"})
                continue
            assert word not in records, f"Duplicate headword: {word}"
            records[word] = {"lemma": exchanges.get("0"), "gloss": gloss}
    for word, record in records.items():
        bases=set(inflections.get(word,()))
        if record['lemma']:bases.add(record['lemma'])
        bases.discard(word)
        record['lemma']=tuple(sorted(bases))
    return records, rejected


def common_words(path: Path, database: dict) -> list[str]:
    sys.path.insert(0, str(ROOT / ".build-deps"))
    import msgpack
    with gzip.open(path, "rb") as stream:
        bins = msgpack.unpackb(stream.read(), raw=False)
    assert bins[0] == {"format": "cB", "version": 1}, "Unsupported wordfreq format"
    words, seen = [], set()
    # cB bins are in descending frequency order, as defined upstream.
    for bucket in bins[1:]:
        for word in bucket:
            if word in database and word not in seen:
                seen.add(word)
                words.append(word)
                if len(words) == COMMON_COUNT:
                    return words
    raise ValueError("Fewer than 30,000 matching English dictionary words")


def build_assets(model: Path, ecdict_csv: Path, frequency: Path, exam_dir: Path) -> dict:
    database, rejected = read_database(ecdict_csv)
    grades = read_exam(exam_dir)
    source_grades = dict(grades)
    evidence={}
    for name in EXAM_FILES:
        for word in (exam_dir/(name+'.txt')).read_text().splitlines():
            evidence.setdefault(word,[]).append({'source':'textbook-'+name,'level':EXAM_FILES.index(name)})
    for word,level in grades.items():
        if level==0:evidence.setdefault(word,[]).append({'source':'primary-curriculum-or-textbook','level':0})
    extra=json.loads((exam_dir/'additional-evidence.json').read_text())
    for row in extra['records']:evidence.setdefault(row['word'],[]).append(row)
    contractions_path = ROOT / "sources/grammar-contractions.tsv"
    contractions = add_contractions(database, grades, contractions_path)
    common = common_words(frequency, database)
    levels = []
    for rank, word in enumerate(common, 1):
        level = grade_word(word, database[word]["lemma"], grades)
        levels.append((word, level, rank))
    data = PLUGIN / "data"
    dictionary_dir = data / "dict" / "readassist-short"
    dictionary_dir.mkdir(parents=True, exist_ok=True)
    with (data / "levels.tsv").open("w", encoding="utf-8", newline="\n") as stream:
        stream.write("# common word\t0=primary 1=junior 2=senior 3=CET4 4=CET6 5=unclassified\tfrequency rank\n")
        for word, level, rank in sorted(levels):
            stream.write(f"{word}\t{level}\t{rank}\n")
    index, definitions = bytearray(), bytearray()
    for word in sorted(database):
        value = database[word]["gloss"].encode("utf-8")
        index.extend(word.encode("ascii") + b"\0")
        index.extend(struct.pack(">II", len(definitions), len(value)))
        definitions.extend(value)
    prefix = dictionary_dir / "readassist-short"
    # sdcv derives this offset cache from .idx. Never ship stale build/test caches.
    Path(str(prefix) + ".idx.oft").unlink(missing_ok=True)
    prefix.with_suffix(".idx").write_bytes(index)
    prefix.with_suffix(".dict").write_bytes(definitions)
    prefix.with_suffix(".ifo").write_text(
        "StarDict's dict ifo file\nversion=2.4.2\n"
        f"wordcount={len(database)}\nidxfilesize={len(index)}\nbookname={BOOKNAME}\n"
        "sametypesequence=m\nlang=en-zh\n"
        "description=ECDICT short Chinese definitions; MIT. A separate index assigns one Chinese learning-stage group per spelling.\n", encoding="utf-8")
    audit=[]
    for word,level,rank in sorted(levels):
        lemma=database[word]["lemma"]
        base=source_lemma(lemma,source_grades)
        if base is not None and source_grades[base]<source_grades.get(word,6): origin="lemma:"+base
        elif word in contractions and grades[word]<source_grades.get(word,6): origin="grammar:"+word
        elif word in source_grades: origin="source:"+word
        elif word in contractions: origin="grammar:"+word
        elif source_lemma(lemma, source_grades) is not None: origin="lemma:"+source_lemma(lemma, source_grades)
        else: origin="extension-policy"
        comparisons=[]
        if word in contractions:
            comparisons.append({'word':word,'source':'explicit-grammar-expansion','level':contractions[word]['level']})
        for term in (word,*(lemma or ())):
            for item in evidence.get(term,[]):
                comparisons.append({'word':term,'source':item['source'],'level':item['level'],**({'page':item['page']} if 'page' in item else {})})
        audit.append({"word":word,"level":level,"rank":rank,"origin":origin,
            "evidence":comparisons,"multiple_stage_memberships":len({item['level'] for item in comparisons})>1})
    (data/"level-audit.json").write_text(json.dumps(audit,ensure_ascii=False,separators=(",",":"))+"\n")
    counts={str(i):sum(level==i for _,level,_ in levels) for i in range(6)}
    source_count=sum(r["origin"].startswith(("source:","lemma:")) for r in audit)
    grammar_count=sum(r["origin"].startswith("grammar:") for r in audit)
    extension_count=sum(r["origin"]=="extension-policy" for r in audit)
    (data / "source-audit.json").write_text(json.dumps({
        "invalid_source_entries": rejected,
        "source_exam_common_words": source_count,
        "grammar_derived_common_words": grammar_count,
        "extension_common_words": extension_count,
        "group_counts":counts,
        "grammar_contractions": contractions,
        "extension_policy": "No primary-through-CET6 match or outside 30k index: unclassified; not an exam level",
    }, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    target = PLUGIN / "models/eng.traineddata"
    target.parent.mkdir(exist_ok=True)
    assert model.stat().st_size > 10_000_000
    if model.resolve() != target.resolve():
        shutil.copyfile(model, target)
    nlp_source=ROOT/"sources/nlp/averaged_perceptron_tagger_eng"
    nlp_target=PLUGIN/"models/pos"
    nlp_target.mkdir(exist_ok=True)
    pos_hashes={}
    for path in nlp_source.glob("*.json"):
        shutil.copyfile(path,nlp_target/path.name)
        pos_hashes[path.name]=hashlib.sha256(path.read_bytes()).hexdigest()
    assert len(pos_hashes)==3
    shutil.copyfile(ROOT/"sources/nlp/MIT-LICENSE",PLUGIN/"licenses/POS_TAGGER_MIT.txt")
    shutil.copyfile(exam_dir/"sources.json",PLUGIN/"data/exam-sources.json")
    (PLUGIN/'data/additional-sources.json').write_text(json.dumps(extra['sources'],ensure_ascii=False,indent=2)+'\n')
    return {
        "version": VERSION, "target": "Kindle Scribe / KOReader 2026.07.1",
        "records": len(levels), "dictionary_records": len(database),
        "graded_records": source_count+grammar_count,
        "source_exam_records": source_count,
        "grammar_derived_records": grammar_count,
        "extension_records": extension_count,
        "unclassified_records": extension_count,
        "group_counts":counts,
        "invalid_source_records": len(rejected),
        "source_sha256": hashlib.sha256(ecdict_csv.read_bytes()).hexdigest(),
        "frequency_sha256": hashlib.sha256(frequency.read_bytes()).hexdigest(),
        "exam_sources": {name: hashlib.sha256((exam_dir/(name+'.txt')).read_bytes()).hexdigest() for name in EXAM_FILES},
        "curriculum_sources": {name: hashlib.sha256((exam_dir/name).read_bytes()).hexdigest() for name in ('primary-curriculum-2022.tsv','primary-curriculum-aliases.tsv')},
        "pos_model_sha256":pos_hashes,
        "grammar_contractions_sha256": hashlib.sha256(contractions_path.read_bytes()).hexdigest(),
        "classification": "Primary through CET6 only; earliest attested spelling or explicit inflection stage; all other words unclassified. Legacy TEM8 list is not used for classification.",
        "additional_evidence_sha256":hashlib.sha256((exam_dir/'additional-evidence.json').read_bytes()).hexdigest(),
        "proper_noun_backend":"MIT averaged perceptron POS model; NNP/NNPS protection before case folding and deduplication; not a PERSON-only NER model",
        "model_sha256": hashlib.sha256(model.read_bytes()).hexdigest(),
        "model_source": "https://github.com/tesseract-ocr/tessdata/blob/4.1.0/eng.traineddata",
        "ocr_backend": "KOReader KOPTContext: native word boxes + PSM_SINGLE_WORD",
        "text_backend": "CREngine original XPointers; PDF original MuPDF text boxes; OCR only when visible pages have no source text",
    }


def package(manifest: dict) -> Path:
    (PLUGIN / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    (ROOT / "dist").mkdir(exist_ok=True)
    target = ROOT / f"dist/WordWise-Kindle-Scribe-v{VERSION}.zip"
    with zipfile.ZipFile(target, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for path in sorted(PLUGIN.rglob("*")):
            if path.is_file() and not path.name.endswith(".idx.oft"):
                archive.write(path, Path("koreader/plugins/wordwise.koplugin") / path.relative_to(PLUGIN))
        for name in ("README.md", "docs/BUILD_AND_TEST.md", "docs/VALIDATION.md"):
            archive.write(ROOT / name, Path("WordWise-docs") / name)
    return target


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--model", type=Path, required=True)
    parser.add_argument("--ecdict-csv", type=Path, required=True)
    parser.add_argument("--frequency", type=Path, required=True)
    parser.add_argument("--exam-dir", type=Path, required=True)
    args = parser.parse_args()
    manifest = build_assets(args.model, args.ecdict_csv, args.frequency, args.exam_dir)
    target = package(manifest)
    print(json.dumps({"package": str(target), "bytes": target.stat().st_size, **manifest}, ensure_ascii=False))


if __name__ == "__main__":
    main()
