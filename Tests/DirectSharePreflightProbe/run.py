from pathlib import Path
import argparse,json,subprocess,tempfile
HERE=Path(__file__).resolve().parent
SOURCE=HERE.parents[1]
p=argparse.ArgumentParser()
p.add_argument('--output',type=Path)
p.add_argument('--platform',choices=['macos','simulator'],default='macos')
p.add_argument('--baseline-directory',type=Path)
a=p.parse_args()
out=a.output.resolve() if a.output else Path(tempfile.mkdtemp(prefix='wygram-direct-share-'))
out.mkdir(parents=True,exist_ok=True)
swift='/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc'
common=[swift,'-swift-version','5','-warnings-as-errors','-module-cache-path',str(out/'module-cache')]
if a.baseline_directory:common+=['-D','BASELINE']
if a.platform=='simulator':common+=['-sdk','/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator.sdk','-target','arm64-apple-ios15.0-simulator']
commands=[common+['-parse-as-library','-emit-module','-emit-library','-static','-module-name','SGAppGroupIdentifier',*[str((a.baseline_directory/f.name) if a.baseline_directory and (a.baseline_directory/f.name).exists() else f) for f in (SOURCE/'Swiftgram/SGAppGroupIdentifier/Sources').glob('*.swift')],'-emit-module-path',str(out/'SGAppGroupIdentifier.swiftmodule'),'-o',str(out/'libSGAppGroupIdentifier.a')],common+['-parse-as-library','-I',str(out),'-L',str(out),'-lSGAppGroupIdentifier',str(HERE/'Probe.swift'),'-o',str(out/'DirectShareStorageProbe')]]
for i,cmd in enumerate(commands):
 r=subprocess.run(cmd,capture_output=True,text=True);(out/('compile-'+str(i)+'.log')).write_text(r.stdout+r.stderr)
 if r.returncode:print(r.stderr);raise SystemExit(r.returncode)
targets=[(None,'macos')] if a.platform=='macos' else [('451E6ACC-A19F-4FDB-8F3E-0D341CB8CD65','18promax'),('6DC4A68B-8997-4231-9078-9458E498C013','15pro')]
reports=[]
for device,label in targets:
 target=out/(label+'-results.json');cmd=[str(out/'DirectShareStorageProbe'),str(target)]
 if device:cmd=['/Library/Developer/PrivateFrameworks/CoreSimulator.framework/Versions/A/Resources/bin/simctl','spawn',device]+cmd
 r=subprocess.run(cmd,capture_output=True,text=True);(out/(label+'-run.log')).write_text(r.stdout+r.stderr)
 if not target.exists():print(r.stderr);raise SystemExit(r.returncode or 1)
 report=json.loads(target.read_text());report['platform']=label;failed=[c['name'] for c in report['checks'] if not c['passed']]
 if a.baseline_directory:assert failed==['trusted-container-root-alias-can-be-prepared','writable-namespace-works-with-readonly-container-root'],failed
 else:assert r.returncode==0 and report['passed'],failed
 reports.append(report);print(label,len(report['checks']),'checks:',report['passed'],'failed:',failed,flush=True)
(out/'validation.json').write_text(json.dumps({'passed':all(r['passed'] for r in reports),'expected_baseline_failure':bool(a.baseline_directory),'reports':reports},ensure_ascii=False,indent=2)+'\n')
print('Evidence:',out)
