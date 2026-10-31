import hashlib, json, os, shutil, subprocess, time, uuid
from pathlib import Path
import argparse, tempfile
HERE=Path(__file__).resolve().parent
SOURCE=HERE.parents[1]
parser=argparse.ArgumentParser(description="Compare WyGram direct-share settings actions with occupied fixture directories.")
parser.add_argument('--output', type=Path, default=None)
parser.add_argument('--baseline', type=Path)
args=parser.parse_args()
OUT=args.output.resolve() if args.output else Path(tempfile.mkdtemp(prefix='wygram-share-handoff-'))
OUT.mkdir(parents=True, exist_ok=True)
(OUT/'ShareProbe.app').mkdir(exist_ok=True)
shutil.copy2(HERE/'Info.plist', OUT/'ShareProbe.app/Info.plist')
SWIFTC='/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc'
SDK='/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator.sdk'
SIMCTL='/Library/Developer/PrivateFrameworks/CoreSimulator.framework/Versions/A/Resources/bin/simctl'
BUNDLE='app.wygram.shareprobe'
def run(*args, check=True, **kwargs):
 return subprocess.run([str(a) for a in args], capture_output=True, text=True, check=check, **kwargs)
common=[SWIFTC,'-swift-version','5','-sdk',SDK,'-target','arm64-apple-ios15.0-simulator','-module-cache-path',OUT/'module-cache']
r=run(*common,'-parse-as-library','-emit-module','-emit-library','-static','-module-name','SGAppGroupIdentifier',SOURCE/'Swiftgram/SGAppGroupIdentifier/Sources/WyGramPushSupport.swift',SOURCE/'Swiftgram/SGAppGroupIdentifier/Sources/WyGramShareInbox.swift',SOURCE/'Swiftgram/SGAppGroupIdentifier/Sources/WyGramDirectShare.swift','-emit-module-path',OUT/'SGAppGroupIdentifier.swiftmodule','-o',OUT/'libSGAppGroupIdentifier.a',check=False)
(OUT/'compile-support.log').write_text(r.stdout+r.stderr)
assert r.returncode==0, r.stderr
settings=(args.baseline or SOURCE/'Swiftgram/SGSettingsUI/Sources/WyGramDirectShareController.swift').read_text()
settings=settings[settings.index('private final class WyGramDirectShareSettings:'):]
substitutions={'WyGramDirectShare.availableGroups()':'probeGroups','UserDefaults.standard':'probeDefaults','WyGramDirectShare.sharedAccountGroup()':'WyGramDirectShare.sharedAccountGroup(groups: probeGroups, bundleIdentifier: probeBundle)','WyGramShareInbox.current()':'probeInboxes()','WyGramDirectShare.cancelRequest()':'WyGramDirectShare.cancelRequest(defaults: probeDefaults)'}
for old,new in substitutions.items(): settings=settings.replace(old,new)
combined=(HERE/'Probe.swift').read_text().replace('// PRODUCTION_SETTINGS_CLASS',settings)
(OUT/'SettingsProbe.swift').write_text(combined)
r=run(*common,'-parse-as-library','-I',OUT,'-L',OUT,'-lSGAppGroupIdentifier','-module-name','ShareProbe',OUT/'SettingsProbe.swift','-o',OUT/'ShareProbe.app/ShareProbe',check=False)
(OUT/'compile.log').write_text(r.stdout+r.stderr)
assert r.returncode==0,r.stderr
reports = []
for device, label in [('451E6ACC-A19F-4FDB-8F3E-0D341CB8CD65', '18promax'), ('6DC4A68B-8997-4231-9078-9458E498C013', '15pro')]:
    run(SIMCTL, 'boot', device, check=False)
    run(SIMCTL, 'bootstatus', device, '-b')
    run(SIMCTL, 'install', device, OUT / 'ShareProbe.app')
    container = Path(run(SIMCTL, 'get_app_container', device, BUNDLE, 'data').stdout.strip())
    run_id = str(uuid.uuid4())
    env = dict(os.environ, SIMCTL_CHILD_WYGRAM_SHARE_PROBE_RUN_ID=run_id)
    run(SIMCTL, 'launch', '--terminate-running-process', device, BUNDLE, env=env)
    deadline = time.monotonic() + 45
    result = None
    while time.monotonic() < deadline:
        try:
            candidate = json.loads((container / 'Documents/results.json').read_text())
            if candidate.get('runID') == run_id:
                result = candidate
                break
        except (OSError, json.JSONDecodeError):
            pass
        time.sleep(.25)
    assert result is not None, label + ': test did not finish'
    result['device'] = label
    (OUT / (label + '-results.json')).write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
    run(SIMCTL, 'io', device, 'screenshot', OUT / (label + '-results.png'))
    reports.append(result)
    print(label, len(result['checks']), 'checks:', 'PASS' if result['passed'] else 'FAIL', [c['name'] for c in result['checks'] if not c['passed']], flush=True)
summary={'passed': all(r['passed'] for r in reports), 'checks':sum(len(r['checks']) for r in reports), 'reports':reports,'ipa_generated':False,'app_version_changed':False}
(OUT/'validation.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2)+'\n')
print('Evidence:', OUT, flush=True)
if args.baseline:
 expected={'enable-row-interactive-when-all-roots-occupied','tap-opens-enable-confirmation','cancel-clears-group-and-relative-location','missing-permission-row-is-actionable','missing-permission-explains-reason'}
 for report in reports: assert {c['name'] for c in report['checks'] if not c['passed']} == expected
else: assert summary['passed'], 'Unexpected validation result'
