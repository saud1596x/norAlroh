"""Cross-source triage only. Never alter either Quran source to make comparisons pass."""
import json,re,html,collections,difflib
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];base=ROOT/'ios/Athar';q=json.loads((base/'quran.json').read_text());m=json.loads((base/'mushaf.json').read_text());groups=collections.defaultdict(list)
for page in m['pages']:
 for w in page['words']:
  if w['kind']=='word':groups[w['key']].append(w['text'])
def prefix(t):
 return re.sub('[\u064B-\u065F\u0670\u06D6-\u06ED\u0640]','',t).translate(str.maketrans({'أ':'ا','إ':'ا','آ':'ا','ٱ':'ا'}))
def normalized(t):
 t=html.unescape(t)
 t=re.sub('ۦ(?=[\u0621-\u064A])','ي',t)
 t=t.translate(str.maketrans({'ٰ':'ا','ٱ':'ا','أ':'ا','إ':'ا','آ':'ا','ى':'ي','ؤ':'و','ئ':'','ء':''}))
 return re.sub('[^\u0621-\u063A\u0641-\u064A]','',t).replace('ا','')
basmala=q[0]['ayahs'][0]['text'].replace('\ufeff','');mismatches=[]
for s in q:
 for a in s['ayahs']:
  text=a['text'].replace('\ufeff','');words=text.split()
  if s['number']>1 and s['number']!=9 and a['number']==1 and prefix(' '.join(words[:4]))==prefix(basmala):text=' '.join(words[4:])
  key=f"{s['number']}:{a['number']}";source=' '.join(groups[key]);left,right=normalized(text),normalized(source)
  if left!=right:
   differences=[{'canonical':left[a:b],'glyphMetadata':right[c:d]}for tag,a,b,c,d in difflib.SequenceMatcher(None,left,right).get_opcodes()if tag!='equal']
   mismatches.append({'verse':key,'canonicalText':text,'glyphSourceMetadata':source,'normalizedDifferences':differences,'status':'REQUIRES_REVIEW_NOT_AUTOMATICALLY_FIXED'})
report={'status':'SCHOLARLY_REVIEW_PENDING','comparedVerses':6236,'differentMetadataSequences':len(mismatches),'normalization':'Aggressive alif/hamza normalization; embedded small ya before another letter expanded; HTML entities decoded for comparison only. This can conceal orthographic differences and is not a correctness certificate.','renderedGlyphs':'Original source glyphs and restored source stop glyphs; metadata strings are not rendered in the fixed-page reader.','mismatches':mismatches}
(ROOT/'release/mushaf-text-review.json').write_text(json.dumps(report,ensure_ascii=False,indent=2));print('Compared 6236 verses; metadata sequences needing review:',len(mismatches));print('Verse keys:',', '.join(x['verse']for x in mismatches))
