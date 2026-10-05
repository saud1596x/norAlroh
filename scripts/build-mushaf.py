"""Build glyph pages from the unchanged QCF4 JSON; fonts are private preview inputs."""
import json,collections,hashlib,os
from pathlib import Path
from fontTools.ttLib import TTFont
SOURCE=Path(os.environ.get('MUSHAF_PREVIEW_SOURCE','/tmp/noor-mushaf'));ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'prototype' if (ROOT/'prototype').exists() else ROOT/'design/noor-alruh/step-02-ios'
juz=[1,22,42,62,82,102,121,142,162,182,201,222,242,262,282,302,322,342,362,382,402,422,442,462,482,502,522,542,562,582]
fonts={}
for i in range(1,48):
 f=TTFont(SOURCE/f'qcf4-{i:02}.ttf'); fonts[f'QCF4_Hafs_{i:02}']=(f.getBestCmap(),f['hmtx'].metrics)
result={};versePages={};types=collections.Counter();missing=[];restored=0;unexpected=[];endKeys=[];headers=[];basmala=[]
for page in range(1,605):
 path=SOURCE/'pages'/f'{page:03}.json';data=json.loads(path.read_text());raw=[dict(w,line=l['line'])for l in data['lines']for w in l['words']];words=[];layout={}
 for i,w in enumerate(raw):
  types[w['type']]+=1
  if w['type']=='surah_header':
   # Header chapter id is explicit code mapping from the source QBSML font, not its erroneous text metadata.
   chapter=w['code']-0xf100+1;assert 1<=chapter<=114
   layout[str(w['line'])]={'type':'header','chapter':chapter};headers.append(chapter);continue
  if w['type']=='bismillah':
   layout[str(w['line'])]={'type':'bismillah','code':chr(w['code']),'font':w['font']};basmala.append(page);continue
  assert w['type']in ['word','end','quarter']
  cmap,metrics=fonts[w['font']];code=w['code'];glyph=chr(code)
  if code not in cmap:missing.append([page,w['font'],code])
  if i+1<len(raw):
   n=raw[i+1]
   if n.get('font')==w['font'] and n['type']in['word','end','quarter'] and n['code']>code:
    # Omitted zero or near-zero advance stop marks only (<=1% of 2500 UPM). Reserved unmapped codepoints are never filled.
    for stop in range(code+1,n['code']):
     if stop in cmap:
      if metrics[cmap[stop]][0]<=25:glyph+=chr(stop);restored+=1
      else:unexpected.append([page,hex(stop),metrics[cmap[stop]][0]])
  words.append({'code':glyph,'line':w['line'],'key':w['verse_key'],'kind':w['type'],'position':w.get('position'),'text':w['text'] if w['type']=='word' else ''})
  versePages.setdefault(w['verse_key'],page)
  if w['type']=='end':endKeys.append(w['verse_key'])
 result[str(page)]={'page':page,'font':data['font'],'juz':sum(page>=x for x in juz),'layout':layout,'words':words}
assert not missing,missing[:10]
assert not unexpected,unexpected[:10]
assert len(set(endKeys))==len(endKeys)==6236
assert sorted(headers)==list(range(1,115))
assert len(versePages)==6236
assert '2' not in result['187']['layout'] # no basmala at At-Tawbah
index=json.loads((SOURCE/'qcf4-index.json').read_text())
metadata={'chapterPages':{str(x['id']):versePages[f"{x['id']}:1"] for x in index['chapters']},'versePages':versePages,'juzPages':juz}
(OUT/'mushaf-data.js').write_text('window.NOOR_MUSHAF='+json.dumps(result,ensure_ascii=False,separators=(',',':'))+';\nwindow.NOOR_MUSHAF_INDEX='+json.dumps(metadata,ensure_ascii=False,separators=(',',':'))+';\n')
(ROOT/'ios/Athar/mushaf.json').write_text(json.dumps({'pages':list(result.values()),'chapterPages':metadata['chapterPages'],'juzPages':juz},ensure_ascii=False,separators=(',',':')))
audit={'pages':604,'surahs':114,'verses':6236,'types':dict(types),'restoredStopMarks':restored,'unmappedGlyphs':missing,'unexpectedVisibleOmissions':unexpected,'source':'https://github.com/MohamadHajjRabee/quran-qcf4','verification':'Structural/glyph/verse completeness only. Independent religious proofread and exact Ayah-edition comparison still required.','fontBinaryDistribution':'Private preview only until rights verified','sha256':hashlib.sha256((OUT/'mushaf-data.js').read_bytes()).hexdigest()}
(OUT/'full-mushaf-audit.json').write_text(json.dumps(audit,ensure_ascii=False,indent=2));print(json.dumps(audit,ensure_ascii=False))
