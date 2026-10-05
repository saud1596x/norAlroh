"""Generate evidence only from successful actual Xcode result bundles, never a local flag."""
import json,hashlib,subprocess,platform,datetime,os
from pathlib import Path
from release_evidence import ios_source_hashes
ROOT=Path(__file__).resolve().parents[1]
if platform.system()!='Darwin':raise SystemExit('Native report requires macOS Xcode execution.')
results={}
for key,file in [('unit','native-unit.xcresult'),('ui','native-ui.xcresult')]:
 path=ROOT/'release'/file
 if not path.is_dir():raise SystemExit('Missing actual test result bundle: '+file)
 summary=json.loads(subprocess.check_output(['xcrun','xcresulttool','get','test-results','summary','--path',str(path)],text=True))
 if summary.get('result')!='Passed' or summary.get('failedTests',0)!=0 or summary.get('passedTests',0)<1:raise SystemExit('Native tests did not pass or no tests executed: '+file)
 results[key]=summary
source=ios_source_hashes(ROOT)
report={'status':'NATIVE_TESTS_PASSED','testedAt':datetime.datetime.now(datetime.timezone.utc).isoformat(),'xcode':subprocess.check_output(['xcodebuild','-version'],text=True).strip(),'sdk':subprocess.check_output(['xcrun','--sdk','iphoneos','--show-sdk-version'],text=True).strip(),'testConfiguration':os.environ.get('NOOR_TEST_CONFIGURATION','Debug'),'tests':results,'sourceHashes':source,'deviceTesting':'NOT_COMPLETED','signedIPA':'NOT_CREATED','appStoreAcceptance':'NOT_SUBMITTED'}
(ROOT/'release/native-build-report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2))
print('Actual native test report saved; simulator testing does not certify release or devices.')
