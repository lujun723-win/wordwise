"""Extract literal electronic PDF rows; reject unsupported notation, never OCR repair."""
import csv, hashlib, json, re
from pathlib import Path
from pypdf import PdfReader

ROOT=Path(__file__).resolve().parents[1]
DIR=ROOT/'sources/exam'
def digest(path):return hashlib.sha256(path.read_bytes()).hexdigest()
rows=[]; omitted=[]
senior=PdfReader(DIR/'senior-official-2020.pdf')
for i in range(128,184):
    text=senior.pages[i].extract_text()
    if i==128:text=text.split('\nA\n',1)[1]
    if i==183:text=text.split('主要国家名称',1)[0]
    for raw in text.splitlines():
        row=raw.strip()
        m=re.fullmatch(r"([A-Za-z][A-Za-z'-]*)(?:\s*\((?:pl\.\s*)?([A-Za-z][A-Za-z'-]*)\))?(\*{0,2})",row)
        if m and len(m[1])>1:
            for word in (m[1],m[2]):
                if word:rows.append(dict(word=word.lower(),level=2 if m[3] else 1,source='moe-senior-2020',page=i+1,row=row))
        elif row and not row.isdigit() and not any('\u3400'<=c<='\u9fff' for c in row):omitted.append(dict(source='moe-senior-2020',page=i+1,row=row))
cet=PdfReader(DIR/'cet-official-2016.pdf')
for i in range(20,149):
    for raw in cet.pages[i].extract_text().splitlines():
        row=raw.strip()
        if re.fullmatch(r"★?\s*[A-Za-z][A-Za-z' /-]*",row):
            for word in re.split(r'[ /]+',row.lstrip('★').strip()):
                if len(word)>1:rows.append(dict(word=word.lower(),level=4 if row.startswith('★') else 3,source='neea-cet-2016',page=i+1,row=row))
        elif re.search('[A-Za-z]',row):omitted.append(dict(source='neea-cet-2016',page=i+1,row=row))
tags={'zk':1,'gk':2,'cet4':3,'cet6':4}
with (ROOT/'sources/online/ecdict.csv').open(newline='') as f:
    for row in csv.DictReader(f):
        if re.fullmatch("[a-z][a-z'-]+",row['word']):
            for tag in row['tag'].split():
                if tag in tags:rows.append(dict(word=row['word'],level=tags[tag],source='ecdict-tag-'+tag))
sources={
    'moe-senior-2020':dict(url='https://www.ictr.edu.cn/Uploads/File/2025/02/07/4.%E6%99%AE%E9%80%9A%E9%AB%98%E4%B8%AD%E8%8B%B1%E8%AF%AD%E8%AF%BE%E7%A8%8B%E6%A0%87%E5%87%86%EF%BC%882017%E5%B9%B4%E7%89%882020%E5%B9%B4%E4%BF%AE%E8%AE%A2%EF%BC%89.20250207211247.pdf',sha256=digest(DIR/'senior-official-2020.pdf'),pages=[129,184],rule='Unstarred compulsory-education words => junior; * and ** => senior. Full explicit parenthetical spellings only.'),
    'neea-cet-2016':dict(url='https://cet.neea.edu.cn/res/Home/1704/55b02330ac17274664f06d9d3db8249d.pdf',sha256=digest(DIR/'cet-official-2016.pdf'),pages=[21,149],rule='Literal plain electronic text rows: unstarred CET4, starred CET6; unsupported shortened/parenthetical spellings excluded, not guessed.'),
    'ecdict-tags':dict(url='https://github.com/skywind3000/ECDICT',sha256=digest(ROOT/'sources/online/ecdict.csv'),rule='zk/gk/cet4/cet6 are community dictionary evidence, not official certification.')}
output=dict(sources=sources,records=rows,unsupported_rows=omitted)
(DIR/'additional-evidence.json').write_text(json.dumps(output,ensure_ascii=False,indent=2)+'\n')
print({source:len({r['word'] for r in rows if r['source']==source}) for source in {r['source'] for r in rows}})
print('Unsupported rows retained for audit:',len(omitted))
