"""Compile actual Foundation-only app blocks with Swift and Adhan 1.5.0.
This is deliberately NOT an iOS build. Reactive wrappers/resources are Linux adapters.
"""
import argparse,datetime,hashlib,json,os,subprocess,tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser();p.add_argument('--swiftc',required=True,type=Path);p.add_argument('--adhan-sources',required=True,type=Path);args=p.parse_args()
base=ROOT/'ios/Athar';inputs={}
def read(name):
 path=base/name;raw=path.read_bytes();inputs[str(path.relative_to(ROOT))]=hashlib.sha256(raw).hexdigest();return raw.decode()
def section(name,start,end):
 s=read(name);assert s.count(start)==1 and s.count(end)==1,(name,start,end)
 return s[s.index(start):s.index(end)]
manifest=json.loads((base/'quran-resource-hashes.json').read_text())
for name in ['quran.json','quran-basmalas.json','mushaf.json','mushaf-headers.json','adhkar.json','saudi-cities.json']:
 raw=(base/name).read_bytes();assert hashlib.sha256(raw).hexdigest()==manifest[name];inputs['ios/Athar/'+name]=manifest[name]
parts=[section('Store.swift','struct Ayah:','struct ExportDocument:'),section('Store.swift','enum QuranText {','struct NoorPrivacyExport'),section('Services.swift','struct PrayerRow:','private final class PrayerNotificationPresenter'),read('PrayerNotificationPlan.swift'),section('AdhkarViews.swift','struct DhikrEntry:','struct AdhkarView:'),section('MemorizationViews.swift','struct MemorizationPlan:','struct MemorizationView:'),read('NoorMotion.swift').split('enum ArabicSearch {')[1],section('MushafReader.swift','struct MushafWord:','// Release builds')]
parts[-2]='enum ArabicSearch {'+parts[-2]
parts.extend([read('DhikrReadingContent.swift'),read('RecitationComparison.swift')])
parts.append(section('NoorLegalContent.swift','struct NoorLegalSection:','struct NoorLegalDocumentView:'))
inputs['ios/Athar/app-legal.json']=hashlib.sha256((base/'app-legal.json').read_bytes()).hexdigest()
parts=[s.replace('import Foundation\n','')for s in parts]
support='''import Foundation
import Adhan
protocol ObservableObject {}
@propertyWrapper struct Published<Value> { var wrappedValue: Value }
// The input files are SHA-verified by the runner. Bundle/UIKit/Combine are not exercised.
enum QuranResources {
 static func data(_ name: String) -> Data? { try? Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent(name + ".json")) }
 static let corpus: [Surah]? = data("quran").flatMap { try? JSONDecoder().decode([Surah].self, from: $0) }
}
'''
tests=r'''
@main struct DomainRun {
 @MainActor static func main() throws {
  var checks:[String:Bool]=[:]
  func verify(_ name:String,_ condition:Bool) throws {
   checks[name]=condition
   guard condition else {throw NSError(domain:"NoorDomainTest",code:1,userInfo:[NSLocalizedDescriptionKey:name])}
  }
  let corpus=QuranResources.corpus!
  let legalData=try Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[1]).appendingPathComponent("app-legal.json")),legal=NoorLegalContent.decode(legalData)!
  try verify("offlinePrivacyTermsAndSupportDecode",legal.documents.count==3 && legal.accountMode=="local-only" && !legal.publisherName.isEmpty)
  try verify("configuredSupportMailtoIsValid",legal.contact.emailURL?.scheme=="mailto" && legal.contact.emailURL?.path==legal.contact.supportEmail)
  var badPolicy=try JSONSerialization.jsonObject(with:legalData)as![String:Any]
  badPolicy["accountMode"]="server-backed"
  try verify("accountBackedPolicyCannotUseLocalOnlyModel",NoorLegalContent.decode(try JSONSerialization.data(withJSONObject:badPolicy))==nil)
  try verify("all114Surahs6236Verses",corpus.count==114 && corpus.reduce(0){$0+$1.ayahs.count}==6236)
  try verify("all112SeparateBasmalas",QuranText.separateBasmalas.count==112 && QuranText.separateBasmalas["9"]==nil)
  try verify("ikhlasAndNasNoInjectedBasmala",corpus[111].ayahs[0].text=="قُلْ هُوَ ٱللَّهُ أَحَدٌ" && corpus[113].ayahs[0].text=="قُلْ أَعُوذُ بِرَبِّ ٱلنَّاسِ")
  try verify("all604MushafPagesPassAppValidator",MushafDatabase.shared?.isValid(corpus:corpus)==true)
  try verify("93SaudiCities13Regions",City.all.count==93 && Set(City.all.compactMap(\.region)).count==13 && City.all.allSatisfy{$0.countryCode=="SA" && $0.timeZone=="Asia/Riyadh"})
  let foreign=City(id:"dubai",name:"دبي",latitude:25,longitude:55,timeZone:"Asia/Dubai",region:nil,countryCode:"AE",sourceID:nil)
  try verify("foreignCityMigratesToMakkah",City.normalized(foreign).id=="makkah")
  try verify("ArabicSearchAndNumbers",ArabicSearch.integer("١١٤")==114 && ArabicSearch.integer("۱۱۲")==112 && ArabicSearch.integer("12x")==nil && ArabicSearch.normalize("الإخْلاص")==ArabicSearch.normalize("الاخلاص"))
  let formatter=ISO8601DateFormatter()
  var days=0,plans=0
  for city in City.all {
   var data=DeviceData();data.city=city
   for month in 1...12 {
    let date=formatter.date(from:String(format:"2026-%02d-15T10:00:00Z",month))!,rows=PrayerCalculator.rows(data:data,date:date)
    try verify("prayerOrder93Cities12Months",rows.count==6 && rows.map(\.date)==rows.map(\.date).sorted())
    let late=rows.last!.date.addingTimeInterval(1),next=PrayerCalculator.next(data:data,now:late)
    try verify("nextPrayerAcrossIsha93Cities12Months",next?.id=="fajr" && next!.date>late)
    var hanafi=data;hanafi.hanafi=true
    try verify("hanafiAsrNotBeforeShafi",PrayerCalculator.rows(data:hanafi,date:date)[3].date>=rows[3].date)
    var hijri=Calendar(identifier:.islamicUmmAlQura);hijri.timeZone=TimeZone(identifier:"Asia/Riyadh")!
    let expected:Double=hijri.component(.month,from:date)==9 ? 7200:5400
    try verify("automaticRamadanIshaInterval",abs(rows[5].date.timeIntervalSince(rows[4].date)-expected)<61)
    days+=1
   }
   for advance in [0,5,10,15] {
    var prefs=PrayerNotificationPreferences();prefs.advanceMinutes=advance
    let plan=PrayerNotificationPlan.make(data:data,preferences:prefs,now:before)
    try verify("notificationLimitsAndOrder",!plan.isEmpty && plan.count<=50 && Set(plan.map(\.id)).count==plan.count && plan.map(\.fireDate)==plan.map(\.fireDate).sorted())
    try verify("notificationsExcludeSunriseAndPast",plan.allSatisfy{!$0.prayer.sunrise && $0.fireDate>before && abs($0.prayer.date.timeIntervalSince($0.fireDate)-Double(advance*60))<0.1})
    plans+=1
   }
  }
  var selected=PrayerNotificationPreferences();selected.prayers=["fajr":true];selected.soundEnabled=false
  try verify("onlySelectedPrayersNoSound",PrayerNotificationPlan.make(data:DeviceData(),preferences:selected,now:before).allSatisfy{$0.prayer.id=="fajr" && !$0.soundEnabled})
  selected.prayers=[:];try verify("allPrayersDisabledNoRequests",PrayerNotificationPlan.make(data:DeviceData(),preferences:selected,now:before).isEmpty)
  let content=AdhkarContent.shared!
  try verify("132HisnChapters267Entries",content.groups.count==132 && content.entries.count==267 && Set(content.groups.flatMap(\.items)).count==267)
  let readings=content.entries.map { DhikrReadingContent(entry:$0) }
  try verify("all267DhikrSourceSpansReassembleExactly",readings.allSatisfy{$0.originalReassembled==$0.source.text})
  let morning=content.entries(in:content.groups.first{$0.id=="hisn-27"}!)
  let kursi=DhikrReadingContent(entry:morning[0])
  try verify("morningStartsWithSeparateCanonicalAyatKursi",kursi.title=="آية الكرسي" && kursi.blocks.compactMap(\.quran).first?.chapter==2 && kursi.blocks.compactMap(\.quran).first?.from==255)
  let shortSurahs=DhikrReadingContent(entry:morning[1]).blocks.compactMap(\.quran)
  try verify("dhikrThreeSurahsSeparateAndComplete",shortSurahs.map(\.chapter)==[112,113,114] && shortSurahs.map{$0.to-$0.from+1}==[4,5,6])
  let seven=readings.first{$0.source.id=="hisn-27-83"}!
  try verify("hasbiyallahCounterSevenPreservesRawSource",seven.source.target==1 && seven.counterEntry.target==7 && seven.source.id==seven.counterEntry.id)
  let words=RecitationComparison.words(chapter:corpus[111],from:1,to:4)
  let exact=RecitationComparison.align(expected:words,heard:"قل هو الله أحد")
  try verify("partialSpeechNoFalseUnspokenSuffixOmission",exact.reliableAlignment && exact.endIndex==4 && exact.possibleDifferences.isEmpty)
  let difference=RecitationComparison.align(expected:words,heard:"قل هو الله واحد")
  try verify("wordSubstitutionReportedAsPotentialDifference",difference.reliableAlignment && difference.possibleDifferences.first?.wordIndex==3)
  let omitted=RecitationComparison.align(expected:words,heard:"هو الله أحد")
  try verify("skippedFirstWordReportedWithoutSkippingSilently",omitted.reliableAlignment && omitted.possibleDifferences.first?.wordIndex==0 && omitted.possibleDifferences.first?.heard==nil)
  let continuation=RecitationComparison.align(expected:words,heard:"الله الصمد لم يلد",anchor:4)
  try verify("nextAyahContinuesAfterPreviousAnchor",continuation.reliableAlignment && continuation.endIndex==8 && continuation.possibleDifferences.isEmpty)
  try verify("unrelatedOrShortTranscriptDoesNotAdvance",!RecitationComparison.align(expected:words,heard:"مرحبا كيف حالك").reliableAlignment && !RecitationComparison.align(expected:words,heard:"قل هو").reliableAlignment)
  try verify("UthmaniSmallWawAndYaAreComparisonAnnotations",RecitationComparison.normalize("مَالَهُۥ")=="ماله" && RecitationComparison.normalize("بِهِۦ")=="به")
  let fatihaWords=RecitationComparison.words(chapter:corpus[0],from:2,to:2),ordinary=RecitationComparison.align(expected:RecitationComparison.words(chapter:corpus[0],from:2,to:2),heard:"الحمد لله رب العالمين")
  try verify("daggerAlifOrdinaryArabicMatchesWithoutEditingQuran",ordinary.reliableAlignment && ordinary.possibleDifferences.isEmpty && fatihaWords.map(\.text).joined(separator:" ")==corpus[0].ayahs[1].text)
  let buffer=RecitationAudioBuffer();buffer.append(Array(repeating:0.1,count:40*16000))
  try verify("speechBufferBoundedThirtySeconds",buffer.snapshot().count==30*16000)
  buffer.erase();buffer.append([1,2,3]);try verify("lateMicrophoneSamplesRejectedAfterErase",buffer.snapshot().isEmpty)
  let diskFolder=FileManager.default.temporaryDirectory.appendingPathComponent("NoorDomain."+UUID().uuidString)
  defer {try? FileManager.default.removeItem(at:diskFolder)}
  let disk=AtharStore(directory:diskFolder)
  try verify("deviceDataWriteAndReopen",disk.update{$0.lowMotion=true;$0.notes.append(JournalNote(text:"test local note"))} && AtharStore(directory:diskFolder).data.lowMotion)
  let diskFile=diskFolder.appendingPathComponent("Athar/device-data.json"),broken=Data("{unreadable original".utf8)
  try broken.write(to:diskFile)
  let badDisk=AtharStore(directory:diskFolder)
  try verify("corruptDeviceDataNotOverwritten",badDisk.unreadableDeviceData==broken && !badDisk.update{$0.lowMotion=false} && (try? Data(contentsOf:diskFile))==broken)
  try verify("deviceDataExplicitEraseAndRecovery",badDisk.erase() && badDisk.update{$0.largeQuran=true} && AtharStore(directory:diskFolder).data.largeQuran)
  let suite="NoorDomain."+UUID().uuidString,defaults=UserDefaults(suiteName:suite)!
  defer { defaults.removePersistentDomain(forName:suite) }
  let group=content.groups.first{$0.id=="hisn-27"}!,entry=content.entries(in:group)[0],counter=DhikrCounterStore(defaults:defaults)
  counter.update(Int.max,entry:entry,group:group,city:.defaultCity,date:before)
  counter.toggleFavorite(group.id)
  try verify("dhikrCounterClampedToSource",counter.count(entry:entry,group:group,city:.defaultCity,date:before)==entry.target)
  try verify("dhikrSaudiDayRollover",counter.count(entry:entry,group:group,city:.defaultCity,date:after)==0)
  counter.refreshDay(date:after);try verify("dailyCountersResetKeepFavorite",counter.counts.isEmpty && DhikrCounterStore(defaults:defaults).favorites.contains(group.id))
  counter.update(-1,entry:entry,group:group,city:.defaultCity,date:after);try verify("dhikrCounterCannotBeNegative",counter.count(entry:entry,group:group,city:.defaultCity,date:after)==0)
  counter.erase();try verify("dhikrDataErase",DhikrCounterStore(defaults:defaults).favorites.isEmpty)
  let memory=MemorizationStore(defaults:defaults)
  try verify("memoryRejectsInvalidRanges",!memory.configure(.init(chapter:114,from:1,to:7,daily:3),corpus:corpus) && !memory.configure(.init(chapter:2,from:286,to:285,daily:3),corpus:corpus))
  try verify("memoryAcceptsValidPlan",memory.configure(.init(chapter:112,from:1,to:4,daily:4),corpus:corpus))
  try verify("memoryRejectsDuplicateAnswers",!memory.finish(chapter:112,answers:[.init(ayah:1,assessment:"remembered",revealed:false,hints:0),.init(ayah:1,assessment:"review",revealed:true,hints:1)]))
  try verify("memorySavesValidResult",memory.finish(chapter:112,answers:[.init(ayah:1,assessment:"review",revealed:true,hints:2)]))
  let reopened=MemorizationStore(defaults:defaults)
  try verify("memoryReopensWithinProcess",reopened.plan.chapter==112 && reopened.history.first?.answers.first?.hints==2)
  memory.erase();try verify("memoryErase",MemorizationStore(defaults:defaults).history.isEmpty)
  let damaged=Data("broken previous history".utf8);defaults.set(damaged,forKey:"noor.memorization.history")
  let recovery=MemorizationStore(defaults:defaults)
  try verify("corruptHistoryPreservedAndOverwriteBlocked",recovery.unreadableHistory==damaged && !recovery.finish(chapter:112,answers:[.init(ayah:1,assessment:"remembered",revealed:false,hints:0)]) && defaults.data(forKey:"noor.memorization.history")==damaged)
  let result:[String:Any] = ["checks":checks,"prayerCityDates":days,"notificationPlans":plans,"status":"FOUNDATION_LOGIC_PASSED"]
  let raw=try JSONSerialization.data(withJSONObject:result,options:[.prettyPrinted,.sortedKeys]);print(String(data:raw,encoding:.utf8)!)
 }
}
'''.replace(chr(92)*2,chr(92))
sources=sorted(args.adhan_sources.rglob('*.swift'));assert sources and all(p.is_file()for p in sources)
adhanHashes={str(p.relative_to(args.adhan_sources)):hashlib.sha256(p.read_bytes()).hexdigest()for p in sources}
with tempfile.TemporaryDirectory(prefix='noor-foundation-',dir=ROOT/'review')as temporary:
 work=Path(temporary);code=work/'AppLogic.swift';code.write_text(support+'\n'.join(parts));test=work/'DomainTests.swift';test.write_text('import Foundation\n'+tests)
 def run(cmd):return subprocess.run([str(x)for x in cmd],check=True,capture_output=True,text=True)
 try:
  run([args.swiftc,'-module-cache-path',work/'module-cache','-swift-version','6','-emit-module','-emit-library','-module-name','Adhan','-o',work/'libAdhan.so',*sources])
  run([args.swiftc,'-module-cache-path',work/'module-cache','-swift-version','5','-I',work,'-L',work,'-lAdhan','-o',work/'domain-tests',code,test])
  result=subprocess.run([str(work/'domain-tests'),str(base)],check=True,capture_output=True,text=True,env={**os.environ,'LD_LIBRARY_PATH':str(work)})
  report=json.loads(result.stdout)
 except subprocess.CalledProcessError as failure:
  failed={'status':'FOUNDATION_LOGIC_FAILED','testedAt':datetime.datetime.now(datetime.timezone.utc).isoformat(),'sourceHashes':inputs,'adhanSourceHashes':adhanHashes,'exitCode':failure.returncode,'nativeIOSBuild':'NOT_RUN','scope':'Foundation compile or execution failed; a previous successful report has been superseded.'}
  (ROOT/'release/foundation-logic-report.json').write_text(json.dumps(failed,ensure_ascii=False,indent=2))
  print(failure.stdout[-6000:]);print(failure.stderr[-6000:]);raise SystemExit('Foundation compile/execution failed; failed report written.')
 report.update(testedAt=datetime.datetime.now(datetime.timezone.utc).isoformat(),swiftCompiler=run([args.swiftc,'--version']).stdout.strip(),sourceHashes=inputs,adhanSourceHashes=adhanHashes,testRunnerSHA256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),scope='Compiled actual app Foundation blocks against Adhan 1.5.0. Linux adapters replace Bundle access and Combine wrappers; resource hashes checked separately. Reopening stores is within one process, not an iOS persistence/device test.',nativeIOSBuild='NOT_RUN',UIKitSwiftUICoreText='NOT_TESTED',microphoneAndSystemNotifications='NOT_TESTED')
 (ROOT/'release/foundation-logic-report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2));print(json.dumps({k:v for k,v in report.items()if k not in ['sourceHashes','adhanSourceHashes']},ensure_ascii=False,indent=2))
