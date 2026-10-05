import subprocess,re
xcode=subprocess.check_output(['xcodebuild','-version'],text=True)
sdk=subprocess.check_output(['xcrun','--sdk','iphoneos','--show-sdk-version'],text=True).strip()
if int(re.search(r'Xcode (\d+)',xcode)[1])<26 or int(sdk.split('.')[0])<26:raise SystemExit('App Store upload requires Xcode 26+ and iOS SDK 26+.')
print(xcode.strip());print('iOS SDK:',sdk)
