"""Audit unchanged local assets. Structural checks cannot certify religious accuracy."""
import argparse,collections,hashlib,json,re,html,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser();p.add_argument('--font-source',type=Path);args=p.parse_args()
base=ROOT/'ios/Athar';report={'scope':'Static asset integrity, source parity and completeness; not iOS execution or religious certification','checks':{},'issues':[]}
def check(key,value):
 report['checks'][key]=bool(value)
 if not value:report['issues'].append(key)
hashes=json.loads((base/'quran-resource-hashes.json').read_text())
for name in ['quran.json','quran-basmalas.json','mushaf.json','mushaf-headers.json','adhkar.json','saudi-cities.json','AmiriQuran.ttf']:
 check('sha256:'+name,hashlib.sha256((base/name).read_bytes()).hexdigest()==hashes[name])
q=json.loads((base/'quran.json').read_text());m=json.loads((base/'mushaf.json').read_text());a=json.loads((base/'adhkar.json').read_text());cities=json.loads((base/'saudi-cities.json').read_text());headers=json.loads((base/'mushaf-headers.json').read_text())
expected=[f"{s['number']}:{a['number']}"for s in q for a in s['ayahs']];order={key:n for n,key in enumerate(expected)}
check('canonicalChapterAndVerseSequence', [s['number']for s in q]==list(range(1,115)) and len(expected)==6236 and all([a['number']for a in s['ayahs']]==list(range(1,len(s['ayahs'])+1))for s in q))
check('604PagesInOrder',[p['page']for p in m['pages']]==list(range(1,605)))
words=[w for p in m['pages']for w in p['words']];ends=[w['key']for w in words if w['kind']=='end']
check('all6236VerseEndsInCanonicalOrder',ends==expected)
check('allWordKeysCanonical',all(w['key']in order for w in words))
check('allWordsInCanonicalOrder',[order[w['key']]for w in words]==sorted(order[w['key']]for w in words))
check('114AuthenticHeaderMappings',len(headers)==114 and len(set(headers))==114 and headers[0]==0xfc45 and headers[13]==0xfc5a)
headings=[];first={};basmala=0;rowOK=True
for page in m['pages']:
 limit=8 if page['page']<=2 else 15
 rowOK &= all(1<=w['line']<=limit and w['kind']in ['word','end','quarter']and all(0xe000<=ord(c)<=0xf8ff for c in w['code'])for w in page['words'])
 rowOK &= [w['line']for w in page['words']]==sorted(w['line']for w in page['words'])
 for w in page['words']:first.setdefault(w['key'],page['page'])
 for line,layout in sorted(page['layout'].items(),key=lambda x:int(x[0])):
  rowOK &= 1<=int(line)<=limit and not any(w['line']==int(line)for w in page['words'])
  if layout['type']=='header':headings.append(layout['chapter'])
  elif layout['type']=='bismillah':basmala+=1
check('sourceLineBreaksAndPUACodes',rowOK)
check('headerChapterSequence',headings==list(range(1,115)))
check('112SeparateBasmalas',basmala==112)
check('tawbahHasNoSeparateBasmala',not any(x['type']=='bismillah'for x in m['pages'][186]['layout'].values()))
check('allChapterStartPages',all(m['chapterPages'][str(s['number'])]==first[f"{s['number']}:1"]for s in q))
check('all30JuzStarts',m['juzPages']==[1,22,42,62,82,102,121,142,162,182,201,222,242,262,282,302,322,342,362,382,402,422,442,462,482,502,522,542,562,582])
ids={e['id']:e for e in a['entries']};assigned=[x for g in a['groups']for x in g['items']]
check('all132HisnChaptersAnd267Entries',len(a['groups'])==132 and len(ids)==len(a['entries'])==267 and len(assigned)==267 and set(assigned)==set(ids))
source=ROOT/'content-sources/hisn';index=json.loads((source/'index.json').read_text(encoding='utf-8-sig'))['العربية'];parity=True
for row in index:
 raw=json.loads((source/f"{row['ID']}.json").read_text(encoding='utf-8-sig'));group=next((x for x in a['groups']if x['id']==f"hisn-{row['ID']}"),None)
 parity &= group is not None and group['name']==row['TITLE']
 for entry in list(raw.values())[0]:
  current=ids.get(f"hisn-{row['ID']}-{entry['ID']}")
  parity &= current is not None and current['text']==entry['ARABIC_TEXT']and current['target']==entry['REPEAT']and current['sourceURL']==row['TEXT'].replace('http:','https:')
check('everyDhikrTextAndRepeatMatchesDownloadedSource',parity)
check('93SaudiCitiesAcross13Regions',len(cities)==93 and len({x['region']for x in cities})==13)
check('onlySaudiCitiesAndTimezone',all(x['countryCode']=='SA'and x['timeZone']=='Asia/Riyadh'and 16<=x['latitude']<=33 and 34<=x['longitude']<=56 for x in cities))
swift='\n'.join(x.read_text()for x in (base).glob('*.swift'))
check('qiblaAndCompassRemoved',not any(x in swift for x in ['Qibla','القبلة','قبلة','startUpdatingHeading']))
import plistlib
info=plistlib.loads((base/'Info.plist').read_bytes())
check('prayerLocationForegroundPurpose', bool(info.get('NSLocationWhenInUseUsageDescription'))
      and not info.get('NSLocationAlwaysAndWhenInUseUsageDescription')
      and 'location' not in info.get('UIBackgroundModes', []))
fontReport={'checked':False,'reason':'Font files are private inputs until distribution rights are documented.'}
if args.font_source:
 from fontTools.ttLib import TTFont
 fonts={};missing=[];bad=[];restored=0
 for i in range(1,48):
  resource=f'QCF4_Hafs_{i:02}_W.ttf';path=args.font_source/f'qcf4-{i:02}.ttf';raw=path.read_bytes()
  if hashlib.sha256(raw).hexdigest()!=hashes[resource]:bad.append(resource)
  font=TTFont(path);fonts[f'QCF4_Hafs_{i:02}']=font.getBestCmap()
 for page in m['pages']:
  cmap=fonts[page['font']]
  for w in page['words']:
   restored+=len(w['code'])-1
   for c in w['code']:
    if ord(c)not in cmap:missing.append([page['page'],hex(ord(c))])
 headerFont=TTFont(args.font_source/'header.ttf');headerCmap=headerFont.getBestCmap()
 check('everyHeaderGlyphExists',all(x in headerCmap for x in headers))
 check('everyBasmalaGlyphExists',all(all(ord(c)in fonts[x.get('font','QCF4_Hafs_01')]for c in x['code'])for page in m['pages']for x in page['layout'].values()if x['type']=='bismillah'))
 check('all47FontFilesMatchPinnedSHA256',not bad)
 check('headerFontMatchesPinnedSHA256',hashlib.sha256((args.font_source/'header.ttf').read_bytes()).hexdigest()==hashes['QCF_SurahHeader_COLOR-Regular.ttf'])
 check('everyRenderedWordAndStopGlyphExists',not missing)
 fontReport={'checked':True,'fonts':48,'restoredStopMarks':restored,'unmapped':missing,'differentHashes':bad}
report['fontAudit']=fontReport;report['coverage']={'pages':604,'surahs':114,'verses':6236,'hisnChapters':132,'adhkarTexts':267,'saudiCities':93};report['nativeCompilation']='NOT_RUN';report['religiousReview']='PENDING'
report['status']='PASS'if not report['issues']else'FAIL'
(ROOT/'release/content-audit.json').write_text(json.dumps(report,ensure_ascii=False,indent=2));print(json.dumps(report,ensure_ascii=False,indent=2));sys.exit(bool(report['issues']))
