"""Inspect release prerequisites. This cannot certify legal rights or Apple acceptance."""
import argparse,json,plistlib,sys,hashlib,platform,subprocess,re
from pathlib import Path
from urllib.parse import urlparse
from release_evidence import ios_source_hashes
ROOT=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser();p.add_argument('--target',choices=['app-store','testflight'],default='app-store');args=p.parse_args()
config=json.loads((ROOT/'release/config.json').read_text());checks={};blockers=[]
def check(name,result,message):
 checks[name]=bool(result)
 if not result:blockers.append(message)
corpus=json.loads((ROOT/'ios/Athar/quran.json').read_text());m=json.loads((ROOT/'ios/Athar/mushaf.json').read_text());adhkar=json.loads((ROOT/'ios/Athar/adhkar.json').read_text());info=plistlib.loads((ROOT/'ios/Athar/Info.plist').read_bytes());privacy=plistlib.loads((ROOT/'ios/Athar/PrivacyInfo.xcprivacy').read_bytes());hashes=json.loads((ROOT/'ios/Athar/quran-resource-hashes.json').read_text())
expected=[f"{s['number']}:{a['number']}"for s in corpus for a in s['ayahs']];ends=[w['key']for p in m['pages']for w in p['words']if w['kind']=='end']
check('completeQuran',len(corpus)==114 and len(expected)==6236 and len(m['pages'])==604 and ends==expected,'بيانات المصحف غير مكتملة أو ترتيبها غير صحيح.')
textAudit=subprocess.run([sys.executable,str(ROOT/'scripts/verify-quran-text.py')],capture_output=True,text=True)
check('exactTanzilSourceCopy',textAudit.returncode==0,'النص القرآني أو البسملات لا تطابق ملف Tanzil الأصلي حرفيًا.')
check('quranSourceAttribution',all((ROOT/path).is_file()for path in ['ios/Athar/Tanzil-LICENSE.txt','docs/TANZIL-LICENSE.txt']),'نسبة النص القرآني وشروط مصدر Tanzil ناقصة.')
notices=[('QCF-DATA-AND-FONTS-LICENSE.md','QCF-DATA-AND-FONTS-LICENSE.md'),('ADHAN-SWIFT-LICENSE.txt','ADHAN-SWIFT-LICENSE.txt'),('Amiri-OFL.txt','AMIRI-OFL.txt'),('WHISPERKIT-LICENSE.txt','WHISPERKIT-LICENSE.txt'),('WHISPER-MODEL-LICENSE.txt','WHISPER-MODEL-LICENSE.txt'),('WHISPERKIT-THIRD-PARTY.txt','WHISPERKIT-THIRD-PARTY.txt')]
check('bundledThirdPartyNotices',all((ROOT/'ios/Athar'/app).is_file()and(ROOT/'docs'/doc).is_file()and(ROOT/'ios/Athar'/app).read_bytes()==(ROOT/'docs'/doc).read_bytes()for app,doc in notices),'نصوص تراخيص بيانات QCF وأميري ومكتبة Adhan غير مكتملة أو تختلف عن النسخ المراجعة.')
bundle=config.get('bundleIdentifier','')
project=(ROOT/'ios/project.yml').read_text();workflow=(ROOT/'codemagic.yaml').read_text()
check('consistentBundleIdentifier',bool(re.fullmatch(r'[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+',bundle))and re.findall(r'^\s*PRODUCT_BUNDLE_IDENTIFIER:\s*(\S+)\s*$',project,re.M)==[bundle]and re.findall(r'^\s*bundle_identifier:\s*(\S+)\s*$',workflow,re.M)==[bundle]and info.get('CFBundleIdentifier')=='$(PRODUCT_BUNDLE_IDENTIFIER)','معرف التطبيق لا يطابق إعدادات المشروع والتوقيع وInfo.plist.')
check('completeHisnAndSourceReferences',len(adhkar['groups'])==132 and len(adhkar['entries'])==267 and all(e['reference']and e['sourceURL'].startswith('https://www.hisnmuslim.com/')for e in adhkar['entries']),'محتوى حصن المسلم يحتاج استكمالًا أو مصادر.')
check('resourceHashes',all(hashlib.sha256((ROOT/'ios/Athar'/n).read_bytes()).hexdigest()==hashes[n]for n in ['quran.json','quran-basmalas.json','mushaf.json','mushaf-headers.json','adhkar.json','saudi-cities.json','AmiriQuran.ttf']),'أحد موارد المحتوى يختلف عن البصمة المراجعة.')
check('permissionPurposeStrings',bool(info.get('NSMicrophoneUsageDescription'))and'NSLocationWhenInUseUsageDescription'not in info,'راجع وصف الميكروفون وإزالة إذن الموقع غير المستخدم.')
check('reviewedInfoPlist',info.get('CFBundleDisplayName')=='نور الروح'and info.get('CFBundleVersion')=='$(CURRENT_PROJECT_VERSION)'and info.get('ITSAppUsesNonExemptEncryption')is False,'راجع الاسم ورقم البناء وإقرار التشفير في Info.plist.')
check('privacyManifest',privacy.get('NSPrivacyTracking')is False and any(x['NSPrivacyAccessedAPIType']=='NSPrivacyAccessedAPICategoryUserDefaults'and'CA92.1'in x['NSPrivacyAccessedAPITypeReasons']for x in privacy['NSPrivacyAccessedAPITypes']),'راجع Privacy Manifest.')
check('speechDownloadFileMetadataReason',any(x['NSPrivacyAccessedAPIType']=='NSPrivacyAccessedAPICategoryFileTimestamp'and'C617.1'in x['NSPrivacyAccessedAPITypeReasons']for x in privacy['NSPrivacyAccessedAPITypes']),'أضف سبب C617.1 لقراءة بيانات ملفات التنزيل داخل مساحة التطبيق عبر مكتبة الصوت.')
check('publisherName',bool(config.get('publisherName')),'اسم الناشر ناقص.')
publishingCheck=subprocess.run([sys.executable,str(ROOT/'scripts/prepare-publishing.py'),'--check'],capture_output=True,text=True)
check('legalPagesMatchPublisherConfiguration',publishingCheck.returncode==0,'سياسة الخصوصية والشروط وصفحات الدعم لا تطابق إعدادات الناشر الحالية؛ شغّل prepare-publishing.py بعد تحديث config.json.')
legalPath=ROOT/'ios/Athar/app-legal.json';legal={}
if legalPath.is_file():
 try:legal=json.loads(legalPath.read_text())
 except ValueError:pass
check('localOnlyAccountModel',config.get('userAccountMode')=='local-only'and legal.get('accountMode')=='local-only','نموذج الحساب والخصوصية غير متطابق؛ لا توجد مصادقة أو مزامنة أو حذف حساب خادم في هذا الإصدار.')
check('offlinePrivacyTermsAndSupport',len(legal.get('documents',[]))==3 and{d.get('id')for d in legal.get('documents',[])}=={'privacy','terms','support'}and all(d.get('sections')for d in legal.get('documents',[])),'صفحات الخصوصية والشروط والدعم غير مكتملة داخل التطبيق.')
check('noTrackingOrCollectedDataManifest',privacy.get('NSPrivacyTrackingDomains')==[]and privacy.get('NSPrivacyCollectedDataTypes')==[],'راجع بيان الخصوصية إذا أضيف جمع بيانات أو تتبع إلى الإصدار المحلي الحالي.')
metadataPath=ROOT/'release/app-store-connect-draft.json';metadata={}
if metadataPath.is_file():
 try:metadata=json.loads(metadataPath.read_text())
 except ValueError:pass
check('storeMetadataLimits',bool(metadata.get('name'))and len(metadata['name'])<=30 and isinstance(metadata.get('subtitle'),str)and len(metadata['subtitle'])<=30 and isinstance(metadata.get('keywords'),str)and len(metadata['keywords'])<=100,'راجع أطوال الاسم والعنوان الفرعي والكلمات المفتاحية في مسودة App Store.')
check('metadataMatchesLocalAccountAndPublisher',metadata.get('name')==config.get('displayName')and metadata.get('reviewSignInRequired')is False and metadata.get('supportEmail')==config.get('supportEmail'),'مسودة المتجر لا تطابق اسم التطبيق وبريد الدعم ووضع تسجيل الدخول المحلي.')
rights=config.get('fontDistributionRightsDocument');check('fontDistributionRightsDocument',isinstance(rights,str)and(ROOT/rights).is_file(),'توثيق حقوق توزيع الخطوط وتضمينها لم يكتمل.')
fontManifest=json.loads((ROOT/'release/qcf-v2-manifest.json').read_text())
required={font['file']:font['sha256'] for font in fontManifest['fonts']}
check('qcfV2FontInventory',fontManifest.get('mushafID')==1 and len(required)==604 and [font['page']for font in fontManifest['fonts']]==list(range(1,605)),'فهرس خطوط QCF V2 لا يغطي الصفحات الـ604.')
missing=[];different=[]
for name,digest in required.items():
 path=ROOT/'ios/Athar/Fonts'/name
 if not path.is_file():missing.append(name)
 elif hashlib.sha256(path.read_bytes()).hexdigest()!=digest:different.append(name)
check('licensedBundledMushafFonts',not missing and not different,'موارد خطوط QCF V2 للصفحات الـ604 غير مكتملة أو لا تطابق النسخة المدققة.')
nativePath=ROOT/'release/native-build-report.json';native={}
if nativePath.is_file():
 try:native=json.loads(nativePath.read_text())
 except ValueError:pass
source=native.get('sourceHashes',{});current=ios_source_hashes(ROOT)
check('nativeTestsPassedOnCurrentSource',native.get('status')=='NATIVE_TESTS_PASSED'and source==current and all(native.get('tests',{}).get(k,{}).get('result')=='Passed'and native.get('tests',{}).get(k,{}).get('failedTests',1)==0 and native.get('tests',{}).get(k,{}).get('passedTests',0)>0 for k in ['unit','ui']),'لا توجد نتيجة Xcode ناجحة للمصدر الحالي.')
check('nativeFontLayoutTestsExecuted',native.get('tests',{}).get('unit',{}).get('skippedTests',1)==0,'اختبار حدود الحروف على iOS لم يُنفذ كاملًا بخطوط المصحف.')
check('releaseConfigurationTested',native.get('testConfiguration')=='Release','لم تُشغّل الاختبارات على إعداد Release النهائي.')
icon=(ROOT/'ios/Athar/Assets.xcassets/AppIcon.appiconset/AppIcon.png').read_bytes()
import struct
check('opaque1024Icon',struct.unpack('>II',icon[16:24])==(1024,1024)and icon[25]==2,'الأيقونة يجب أن تكون 1024×1024 دون شفافية.')
toolchain=False
if platform.system()=='Darwin':
 try:
  version=subprocess.check_output(['xcodebuild','-version'],text=True);sdk=subprocess.check_output(['xcrun','--sdk','iphoneos','--show-sdk-version'],text=True)
  toolchain=int(re.search(r'Xcode (\d+)',version)[1])>=26 and int(sdk.split('.')[0])>=26
 except Exception:pass
elif native:
 try:toolchain=int(re.search(r'Xcode (\d+)',native['xcode'])[1])>=26 and int(native['sdk'].split('.')[0])>=26
 except Exception:pass
check('uploadToolchainVerified',toolchain,'لم تُثبت نتيجة تشغيل Xcode 26+/SDK iOS 26+ في السحابة أو محليًا.')
if args.target=='app-store':
 check('supportEmail',bool(re.fullmatch(r'[^\s@]+@[^\s@]+\.[^\s@]+',config.get('supportEmail')or'')),'بريد الدعم ناقص أو ليس عنوانًا صالحًا.')
 def validPublicURL(value):
  if not isinstance(value,str):return False
  try:
   parsed=urlparse(value)
   return parsed.scheme=='https'and bool(parsed.hostname)and '.'in parsed.hostname and parsed.hostname not in ['example.com','example.org','localhost']and not parsed.username and not parsed.password and not any(c.isspace()for c in value)
  except ValueError:return False
 check('publicPrivacyAndSupportURLs',all(validPublicURL(config.get(k))for k in ['privacyURL','supportURL']),'روابط الخصوصية والدعم العامة ناقصة أو غير صالحة؛ يجب نشرها ومراجعتها فعليًا.')
 check('appleTeam',bool(re.fullmatch(r'[A-Z0-9]{10}',config.get('appleTeamID')or'')),'هوية Apple Team المكونة من عشرة أحرف لم تُسجل في ملف الإصدار.')
 for key,label in [('religiousContentReviewDocument','المراجعة المتخصصة للمصحف والأذكار لم تكتمل.'),('nativeDeviceTestReport','اختبار نسخة Release على iPhone/iPad لم يُثبت.'),('speechRecognitionValidationDocument','دقة المتابعة الصوتية والفروق المحتملة لم تُختبر بتلاوات مرجعية على أجهزة فعلية.')]:
  relative=config.get(key);check(key,isinstance(relative,str)and(ROOT/relative).is_file(),label)
report={'status':('INTERNAL_TESTFLIGHT_PRECONDITIONS_MET'if args.target=='testflight'else'PRECONDITIONS_MET_REQUIRES_HUMAN_REVIEW')if not blockers else'NOT_READY_FOR_'+args.target.upper().replace('-','_'),'target':args.target,'scope':'Preflight only; not signing verification, religious/legal certification or Apple acceptance','checks':checks,'blockers':blockers,'missingFontResourceCount':len(missing),'differentFontHashes':different,'quranSHA256':hashlib.sha256((ROOT/'ios/Athar/quran.json').read_bytes()).hexdigest()}
(ROOT/'release/preflight-report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2));print(json.dumps(report,ensure_ascii=False,indent=2));sys.exit(1 if blockers else 0)
