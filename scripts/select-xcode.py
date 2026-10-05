"""Choose a real installed Xcode >=26; fail instead of silently using an old SDK."""
from pathlib import Path
import subprocess,re,os
choices=[]
for p in Path('/Applications').glob('Xcode*.app'):
 developer=p/'Contents/Developer'
 if not developer.is_dir():continue
 env={**os.environ,'DEVELOPER_DIR':str(developer)}
 try:version=subprocess.check_output([str(developer/'usr/bin/xcodebuild'),'-version'],text=True,env=env,stderr=subprocess.DEVNULL).splitlines()[0]
 except (OSError,subprocess.CalledProcessError):continue
 numbers=tuple(map(int,re.findall(r'\d+',version)))
 if numbers and numbers[0]>=26:choices.append((numbers,str(developer)))
if not choices:raise SystemExit('The macOS runner has no Xcode 26+. Select an updated runner image before building.')
print('DEVELOPER_DIR='+max(choices)[1])
