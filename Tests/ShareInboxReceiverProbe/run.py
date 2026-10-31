from pathlib import Path
import argparse, hashlib, json, os, shutil, subprocess, time, uuid

HERE = Path(__file__).resolve().parent
SOURCE = HERE.parents[1]
p = argparse.ArgumentParser()
p.add_argument('--output', type=Path, required=True)
p.add_argument('--baseline-presenter', type=Path, required=True)
a = p.parse_args()
out = a.output.resolve()
out.mkdir(parents=True, exist_ok=True)
swift = '/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc'
sdk = '/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator.sdk'
simctl = '/Library/Developer/PrivateFrameworks/CoreSimulator.framework/Versions/A/Resources/bin/simctl'
common = [swift, '-swift-version', '5', '-warnings-as-errors', '-sdk', sdk, '-target', 'arm64-apple-ios15.0-simulator', '-module-cache-path', str(out/'module-cache')]

def run(cmd, **kwargs):
    return subprocess.run([str(x) for x in cmd], capture_output=True, text=True, **kwargs)

def compile(name, args):
    r = run(common + args)
    (out/(name+'.log')).write_text(r.stdout+r.stderr)
    assert r.returncode == 0, r.stderr

def module(name, files):
    compile(name, ['-parse-as-library', '-emit-module', '-emit-library', '-static', '-module-name', name, *files, '-emit-module-path', out/(name+'.swiftmodule'), '-o', out/('lib'+name+'.a')])

module('SGAppGroupIdentifier', list((SOURCE/'Swiftgram/SGAppGroupIdentifier/Sources').glob('*.swift')))
module('SwiftSignalKit', list((SOURCE/'submodules/SSignalKit/SwiftSignalKit/Source').glob('*.swift')) + list((SOURCE/'Swiftgram/SGSwiftSignalKit/Sources').glob('*.swift')))
hashes = {}
for name, path in [('LegacyReceiver', a.baseline_presenter.resolve()), ('FixedReceiver', SOURCE/'submodules/TelegramUI/Sources/WyGramShareInboxPresenter.swift')]:
    raw = path.read_text()
    hashes[name] = hashlib.sha256(raw.encode()).hexdigest()
    # Compile the production receiver's complete readiness/lifecycle section.
    # Only account shells and final native ShareController construction are
    # replaced; inbox discovery is injected to avoid pretending test signatures
    # grant common App Group rights.
    s = raw[raw.index('final class WyGramShareInboxPresenter'):raw.index('    private func present(')]
    s = s.replace('WyGramShareInboxPresenter', name)
    s = s.replace('WyGramShareInbox.current()', '(self?.testInboxes ?? [])')
    s = s.replace('WyGramShareInboxCoordinator(canPresent:', 'WyGramShareInboxCoordinator(inboxes: { [weak self] in self?.testInboxes ?? [] }, canPresent:')
    if name == 'LegacyReceiver':
        present = '''private func present(context: AuthorizedApplicationContext, inbox: WyGramShareInbox, batch: WyGramShareInbox.Batch) {
            guard let _ = context.rootController.currentWindow else { self.presenting = false; return }
            self.presentations.append(batch.id)
        }'''
    else:
        present = '''private func present(context: AuthorizedApplicationContext, inbox: WyGramShareInbox, batch: WyGramShareInbox.Batch) -> Bool {
            guard UIApplication.shared.applicationState == .active, context.rootController.currentWindow != nil else { return false }
            self.presentations.append(batch.id)
            return true
        }
        func finishForProbe() { self.coordinator?.finished() }'''
    (out/(name+'.swift')).write_text('import Foundation\nimport UIKit\nimport SwiftSignalKit\nimport SGAppGroupIdentifier\n'+s+'var testInboxes: [WyGramShareInbox] = []\nvar presentations: [String] = []\n'+present+'\ndeinit { self.readyDisposable.dispose() }\n}\n')

app = out/'ShareReceiverProbe.app'
app.mkdir(exist_ok=True)
shutil.copy2(HERE/'Info.plist', app/'Info.plist')
compile('probe', ['-parse-as-library', '-I', out, '-L', out, '-lSGAppGroupIdentifier', '-lSwiftSignalKit', SOURCE/'submodules/TelegramUI/Sources/WyGramShareInboxCoordinator.swift', out/'LegacyReceiver.swift', out/'FixedReceiver.swift', HERE/'Probe.swift', '-o', app/'ShareReceiverProbe'])
reports = []
for device, label in [('451E6ACC-A19F-4FDB-8F3E-0D341CB8CD65', '18promax'), ('6DC4A68B-8997-4231-9078-9458E498C013', '15pro')]:
    run([simctl, 'boot', device])
    r = run([simctl, 'bootstatus', device, '-b']); assert r.returncode == 0, r.stderr
    r = run([simctl, 'install', device, app]); assert r.returncode == 0, r.stderr
    r = run([simctl, 'get_app_container', device, 'app.wygram.sharereceiverprobe', 'data']); assert r.returncode == 0, r.stderr
    data = Path(r.stdout.strip())
    run_id = str(uuid.uuid4())
    r = run([simctl, 'launch', '--terminate-running-process', device, 'app.wygram.sharereceiverprobe'], env=dict(os.environ, SIMCTL_CHILD_PROBE_RUN_ID=run_id)); assert r.returncode == 0, r.stderr
    result = None
    deadline = time.monotonic()+50
    while time.monotonic() < deadline:
        try:
            current = json.loads((data/'Documents/results.json').read_text())
            if current.get('runID') == run_id:
                result = current
                break
        except (OSError, json.JSONDecodeError):
            pass
        time.sleep(.2)
    assert result is not None, label+': probe did not finish'
    (out/(label+'-results.json')).write_text(json.dumps(result, ensure_ascii=False, indent=2)+'\n')
    reports.append(result)
    print(label, len(result['checks']), 'checks:', result['passed'], [c['name'] for c in result['checks'] if not c['passed']], flush=True)
    assert result['passed']
(out/'validation.json').write_text(json.dumps({'passed': True, 'reports': reports, 'receiverSourceSHA256': hashes, 'scope': 'Production readiness/lifecycle sections, production coordinator/inboxes, real UIKit window attachment; shell account and recipient-presentation recorder. No signed App Group, logged-in ShareController or real sends.'}, ensure_ascii=False, indent=2)+'\n')
