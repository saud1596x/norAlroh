// Reproducible, offline verification against the app's immutable display Quran.
// Run without arguments to verify, or --write after reviewing the curated spans.
import fs from 'node:fs';
import crypto from 'node:crypto';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const source = fs.readFileSync(path.join(root, 'ios/Athar/quran.json'));
const quran = JSON.parse(source);
// Matching representation only: Quran display text is never normalized.
const normalize = s => s.replace(/وٰ/g, 'ا').replace(/[ئؤ]/g, 'ء').normalize('NFD').replace(/[\u0610-\u061a\u064b-\u065f\u0670\u06d6-\u06ed]/gu, '').replace(/ٱ/g, 'ا').replace(/[اءـ]/g, '').replace(/ى/g, 'ي').normalize('NFC');
const spans = [
 [1,6,'اهدنا الصراط المستقيم'],
 [2,127,'ربنا تقبل منا إنك أنت السميع العليم'],
 [2,128,'ربنا واجعلنا مسلمين لك ومن ذريتنا أمة مسلمة لك'],
 [2,201,'ربنا آتنا في الدنيا حسنة وفي الآخرة حسنة وقنا عذاب النار'],
 [2,250,'ربنا أفرغ علينا صبرا وثبت أقدامنا وانصرنا على القوم الكافرين'],
 [2,286,'واعف عنا واغفر لنا وارحمنا'],
 [3,8,'ربنا لا تزغ قلوبنا بعد إذ هديتنا وهب لنا من لدنك رحمة'],
 [3,9,'ربنا إنك جامع الناس ليوم لا ريب فيه'],
 [3,16,'ربنا إننا آمنا فاغفر لنا ذنوبنا وقنا عذاب النار'],
 [3,38,'رب هب لي من لدنك ذرية طيبة إنك سميع الدعاء'],
 [3,53,'ربنا آمنا بما أنزلت واتبعنا الرسول فاكتبنا مع الشاهدين'],
 [3,147,'ربنا اغفر لنا ذنوبنا وإسرافنا في أمرنا وثبت أقدامنا'],
 [3,193,'ربنا فاغفر لنا ذنوبنا وكفر عنا سيئاتنا وتوفنا مع الأبرار'],
 [5,83,'ربنا آمنا فاكتبنا مع الشاهدين'],
 [7,23,'ربنا ظلمنا أنفسنا وإن لم تغفر لنا وترحمنا لنكونن من الخاسرين'],
 [7,89,'ربنا افتح بيننا وبين قومنا بالحق وأنت خير الفاتحين'],
 [7,126,'ربنا أفرغ علينا صبرا وتوفنا مسلمين'],
 [10,85,'ربنا لا تجعلنا فتنة للقوم الظالمين'],
 [10,86,'ونجنا برحمتك من القوم الكافرين'],
 [12,101,'توفني مسلما وألحقني بالصالحين'],
 [14,40,'رب اجعلني مقيم الصلاة ومن ذريتي ربنا وتقبل دعاء'],
 [14,41,'ربنا اغفر لي ولوالدي وللمؤمنين يوم يقوم الحساب'],
 [17,24,'رب ارحمهما كما ربياني صغيرا'],
 [18,10,'ربنا آتنا من لدنك رحمة وهيئ لنا من أمرنا رشدا'],
 [20,25,'رب اشرح لي صدري'],
 [20,26,'ويسر لي أمري'],
 [20,114,'رب زدني علما'],
 [21,87,'لا إله إلا أنت سبحانك إني كنت من الظالمين'],
 [23,29,'رب أنزلني منزلا مباركا وأنت خير المنزلين'],
 [23,97,'رب أعوذ بك من همزات الشياطين'],
 [23,98,'وأعوذ بك رب أن يحضرون'],
 [23,109,'ربنا آمنا فاغفر لنا وارحمنا وأنت خير الراحمين'],
 [23,118,'رب اغفر وارحم وأنت خير الراحمين'],
 [25,65,'ربنا اصرف عنا عذاب جهنم إن عذابها كان غراما'],
 [25,74,'ربنا هب لنا من أزواجنا وذرياتنا قرة أعين واجعلنا للمتقين إماما'],
 [26,83,'رب هب لي حكما وألحقني بالصالحين'],
 [26,84,'واجعل لي لسان صدق في الآخرين'],
 [26,85,'واجعلني من ورثة جنة النعيم'],
 [28,16,'رب إني ظلمت نفسي فاغفر لي'],
 [28,21,'رب نجني من القوم الظالمين'],
 [28,24,'رب إني لما أنزلت إلي من خير فقير'],
 [29,30,'رب انصرني على القوم المفسدين'],
 [37,100,'رب هب لي من الصالحين'],
 [59,10,'ربنا اغفر لنا ولإخواننا الذين سبقونا بالإيمان'],
 [60,4,'ربنا عليك توكلنا وإليك أنبنا وإليك المصير'],
 [66,8,'ربنا أتمم لنا نورنا واغفر لنا إنك على كل شيء قدير'],
 [66,11,'رب ابن لي عندك بيتا في الجنة'],
 [71,28,'رب اغفر لي ولوالدي ولمن دخل بيتي مؤمنا وللمؤمنين والمؤمنات'],
 [3,194,'ربنا وآتنا ما وعدتنا على رسلك'],
 [7,151,'رب اغفر لي ولأخي وأدخلنا في رحمتك وأنت أرحم الراحمين'],
 [20,27,'واحلل عقدة من لساني'],
 [27,19,'وأدخلني برحمتك في عبادك الصالحين'],
 [46,15,'وأصلح لي في ذريتي إني تبت إليك وإني من المسلمين'],
];
function extract([chapter, ayah, requested]) {
 const original = quran.find(c => c.number === chapter).ayahs.find(a => a.number === ayah).text;
 const originalWords = original.split(' ');
 const positions = originalWords.map((w,i)=>normalize(w).length ? i : -1).filter(i=>i>=0);
 const words = positions.map(i=>originalWords[i]), wanted = requested.split(' ');
 const start = words.findIndex((_, i) => normalize(words.slice(i,i+wanted.length).join(' ')) === normalize(requested));
 if (start < 0) throw Error(`Unverified Quran span ${chapter}:${ayah}: ${requested}`);
 return { id: `quran-${chapter}-${ayah}-${start+1}-${start+wanted.length}`, category: 'quran', chapter, ayah,
  firstWord: start+1, lastWord: start+wanted.length, text: originalWords.slice(positions[start],positions[start+wanted.length-1]+1).join(' '), verificationVersion: 1 };
}
const entries = spans.map(extract);
if (entries.length !== 53 || new Set(entries.map(e=>e.text)).size !== 53) throw Error('Expected 53 distinct verified prayers');
const locks = [[1,2,'الحمد لله رب العالمين'],[20,114,'رب زدني علما'],[20,25,'رب اشرح لي صدري'],[23,118,'رب اغفر وارحم وأنت خير الراحمين'],[37,100,'رب هب لي من الصالحين'],[20,26,'ويسر لي أمري'],[26,85,'واجعلني من ورثة جنة النعيم']].map(extract);
const small = entries.filter(e=>[...e.text].length <= 95).slice(0,31);
if(small.length!==31) throw Error('Small-family pool needs 31 complete short texts');
const provenance = JSON.stringify({version:1,source:'ios/Athar/quran.json',sourceSHA256:crypto.createHash('sha256').update(source).digest('hex'),policy:'Exact contiguous Quran word spans, diacritics unchanged; no virtue/repetition claims. Curated selection order is immutable within version 1.',entries,smallIDs:small.map(e=>e.id),lockEntries:locks},null,2)+'\n';
const row = e => `        .init(id: "${e.id}", text: "${e.text}"),`;
const swift = `// Generated by scripts/build-widget-dua-catalog.mjs; do not edit Quran text here.\nimport Foundation\n\nstruct NoorDua: Equatable, Codable, Identifiable {\n    let id: String\n    let text: String\n}\n\nenum NoorDuaCatalog {\n    static let version = 1\n    static let home: [NoorDua] = [\n${entries.map(row).join('\n')}\n    ]\n    static let smallIDs: Set<String> = [\n${small.map(e=>'        "'+e.id+'",').join('\n')}\n    ]\n    static let lock: [NoorDua] = [\n${locks.map(row).join('\n')}\n    ]\n    static func find(_ id: String) -> NoorDua? { (home + lock).first { $0.id == id } }\n}\n`;
for (const [name,content] of [['ios/NoorWidgetShared/DuaCatalog.swift',swift],['content-sources/widget-dua-verification.json',provenance]]) {
 const destination=path.join(root,name);
 if(process.argv.includes('--write')) fs.writeFileSync(destination,content);
 else if(fs.readFileSync(destination,'utf8')!==content) throw Error(`Catalog mismatch: ${name}`);
}
console.log(JSON.stringify({verified:entries.length,small:small.length,lock:locks.length,catalogBytes:Buffer.byteLength(swift),sourceSHA256:crypto.createHash('sha256').update(source).digest('hex')}));
