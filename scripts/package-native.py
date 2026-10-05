from pathlib import Path
import argparse,zipfile,json
p=argparse.ArgumentParser();p.add_argument('--github-upload',action='store_true',help='Place codemagic.yaml at the ZIP root for extraction into a cloned repository.');args=p.parse_args()
ROOT=Path(__file__).resolve().parents[1];out=ROOT/'release'/('noor-alroh-github-upload.zip'if args.github_upload else'noor-alruh-ios-source.zip');prefix=''if args.github_upload else'noor-alruh-ios/';files=[]
for name in ['ios','scripts','content-sources','docs','support-site','.github']:
 for p in (ROOT/name).rglob('*'):
  if not p.is_file()or'__pycache__'in p.parts or'Fonts'in p.parts or any(x.endswith(('.xcresult','.xcodeproj'))for x in p.parts):continue
  if p.suffix in ['.woff2','.p8','.p12','.mobileprovision']:continue
  if name=='docs' and p.suffix in ['.png','.json']:continue
  if name=='scripts' and p.name in ['package-noor.py','bundle-preview.py','sync-preview-content.py']:continue
  files.append(p)
for p in (ROOT/'release').iterdir():
 if p.is_file()and p.suffix in ['.json','.md']and p.name not in ['delivery-report.json','source-package-report.json']:files.append(p)
files.extend([ROOT/'README-NOOR.md',ROOT/'codemagic.yaml',ROOT/'.gitignore'])
with zipfile.ZipFile(out,'w',zipfile.ZIP_DEFLATED,compresslevel=9)as archive:
 for p in files:archive.write(p,prefix+str(p.relative_to(ROOT)))
with zipfile.ZipFile(out)as archive:
 assert archive.testzip()is None
 assert all('/prototype/'not in n and '/design/'not in n and '/Fonts/'not in n for n in archive.namelist())
 assert prefix+'.github/workflows/ios-checks.yml'in archive.namelist()
 assert prefix+'codemagic.yaml'in archive.namelist()
print(json.dumps({'file':str(out),'bytes':out.stat().st_size,'files':len(files),'nativeSource':True,'signedIPA':False,'githubUploadRoot':args.github_upload},ensure_ascii=False))
