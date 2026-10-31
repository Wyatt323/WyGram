#!/usr/bin/env python3
"""Prepare a re-signable update and publish only to Wyatt323/WyGram Releases.

No signing certificates, provisioning profiles or Telegram API secrets belong in
this release. User certificates are imported inside the installed application.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request
import zipfile

REPOSITORY = 'Wyatt323/WyGram'
SOURCE = Path(__file__).resolve().parents[1]


def run(*args, **kwargs):
    return subprocess.run(list(map(str, args)), check=True, capture_output=True, **kwargs).stdout


def hash_file(path):
    digest = hashlib.sha256()
    with path.open('rb') as file:
        for chunk in iter(lambda: file.read(1024 * 1024), b''): digest.update(chunk)
    return digest.hexdigest()


def source_patch(destination):
    patch = run('git', 'diff', '--binary', 'HEAD', cwd=SOURCE)
    files = run('git', 'ls-files', '--others', '--exclude-standard', '-z', cwd=SOURCE).decode().split('\0')
    for relative in files:
        file = SOURCE / relative
        if not relative or file.is_symlink() or not file.is_file(): continue
        if relative.startswith(('build-input/', 'build-system/local-xcode/')) or relative == 'build-system/wygram.local.json': continue
        if relative.split('/')[0] not in ('Swiftgram', 'Telegram', 'Tests', 'submodules', 'scripts', 'docs', 'build-system', 'WYGRAM.md'): continue
        if file.suffix.lower() in ('.p12', '.pfx', '.mobileprovision', '.pem', '.key', '.ipa'): raise ValueError('Signing material in source tree; refusing publication')
        result = subprocess.run(['git', 'diff', '--binary', '--no-index', '--', '/dev/null', relative], cwd=SOURCE, capture_output=True)
        if result.returncode not in (0, 1): raise ValueError('Cannot collect source changes')
        patch += result.stdout
    # Never print or publish local API credentials if they entered a source diff.
    local = SOURCE / 'build-system/wygram.local.json'
    if local.exists():
        config = json.loads(local.read_text())
        def secrets(value):
            if isinstance(value, dict):
                for key, item in value.items():
                    if any(name in key.lower() for name in ('api_id', 'api_hash', 'password', 'token', 'private_key')) and isinstance(item, (str, int)) and len(str(item)) >= 6: yield str(item).encode()
                    else: yield from secrets(item)
            elif isinstance(value, list):
                for item in value: yield from secrets(item)
        if any(secret in patch for secret in secrets(config)): raise ValueError('Local credentials found in source patch; refusing publication')
    if re.search(rb'(?m)^\+-----BEGIN (?:RSA |EC |ENCRYPTED )?PRIVATE KEY-----\r?$', patch): raise ValueError('Private key found in source patch')
    destination.write_bytes(patch)
    return run('git', 'rev-parse', 'HEAD', cwd=SOURCE).decode().strip()


def prepare(ipa, output, notes, source_commit=None):
    if source_commit is not None and not re.fullmatch(r'[0-9a-f]{40}', source_commit): raise ValueError('Expected a full source commit SHA')
    if output.exists(): raise ValueError('Refusing to overwrite a prepared release directory')
    requested_output = output
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='wygram-release-', dir=output.parent) as temporary:
        root = Path(temporary)
        output = root / 'delivery'
        with zipfile.ZipFile(ipa) as archive:
            total = 0
            for entry in archive.infolist():
                path = Path(entry.filename)
                if path.is_absolute() or '..' in path.parts or '\\' in entry.filename or (entry.external_attr >> 16) & 0o170000 == 0o120000: raise ValueError('Unsafe archive path')
                total += entry.file_size
                if total > 1500 * 1024 * 1024: raise ValueError('Archive exceeds update limits')
            archive.extractall(root)
        apps = [path for path in (root / 'Payload').glob('*.app') if path.is_dir() and not path.name.startswith('.')]
        if len(apps) != 1: raise ValueError('Exactly one application is required')
        app = apps[0]
        info = plistlib.loads((app / 'Info.plist').read_bytes())
        version, build = info['CFBundleShortVersionString'], str(info['CFBundleVersion'])
        if not re.fullmatch(r'[0-9]+(?:\.[0-9]+){1,3}', version) or not re.fullmatch(r'[1-9][0-9]*', build): raise ValueError('Invalid version')
        if info['CFBundleIdentifier'] != 'app.wygram.ios': raise ValueError('Unexpected application bundle ID')
        bundles = [app] + list(app.glob('PlugIns/*.appex'))
        for bundle in bundles:
            value = plistlib.loads((bundle / 'Info.plist').read_bytes())
            if value['CFBundleShortVersionString'] != version or str(value['CFBundleVersion']) != build: raise ValueError('Extension versions do not match')
        for file in root.rglob('*'):
            if file.suffix.lower() in ('.p12', '.pfx', '.key', '.pem'): raise ValueError('Signing key in archive')
            if file.name == 'embedded.mobileprovision': file.unlink()
        # Keep load-command signature space for the embedded signer. This is an
        # ad-hoc reference package, not a personal certificate-signed release.
        frameworks = list(app.rglob('*.framework'))
        for bundle in sorted(frameworks + bundles, key=lambda x: len(x.parts), reverse=True):
            value = plistlib.loads((bundle / 'Info.plist').read_bytes())
            executable = bundle / value['CFBundleExecutable']
            executable.chmod(executable.stat().st_mode | 0o111)
            run('codesign', '--force', '--sign', '-', '--timestamp=none', bundle)
            run('codesign', '--verify', '--strict', bundle)
        output.mkdir(parents=True)
        artifact = output / f'WyGram {version}.ipa'
        run('ditto', '-c', '-k', '--norsrc', '--noextattr', '--noacl', '--keepParent', root / 'Payload', artifact)
        if not 0 < artifact.stat().st_size <= 256 * 1024 * 1024: raise ValueError('IPA exceeds client update size limit')
        tag = f'v{version}-b{build}'
        source = output / f'WyGram-{version}-b{build}-source.patch'
        base = source_patch(source)
        provenance = f'Full source: https://github.com/{REPOSITORY}/tree/{source_commit}\n' if source_commit else ''
        (output / 'release-notes.md').write_text(notes.read_text() + f'\n\n{provenance}\nSupplemental patch base: `Swiftgram/Telegram-iOS@{base}`.\n\nIPA filename: `WyGram {version}.ipa`. GitHub automatically replaces spaces with periods in stored asset names; the display label retains the requested filename.\n')
        digest = hash_file(artifact)
        remote_name = artifact.name.replace(' ', '.')
        (output / 'SHA256SUMS.txt').write_text(f'{digest}  {remote_name}\n{hash_file(source)}  {source.name}\n')
        record = {'repository': REPOSITORY, 'tag': tag, 'version': version, 'build': int(build), 'asset': artifact.name, 'github_asset': remote_name, 'sha256': digest, 'size': artifact.stat().st_size, 'source': source.name, 'source_base': base, 'source_commit': source_commit}
        (output / 'release.json').write_text(json.dumps(record, indent=2) + '\n')
        output.rename(requested_output)
        print(json.dumps(record))


def credential():
    token = os.environ.get('GH_TOKEN') or os.environ.get('GITHUB_TOKEN')
    if not token:
        result = subprocess.run(['git', 'credential', 'fill'], input='protocol=https\nhost=github.com\n\n', text=True, capture_output=True, timeout=15, env=dict(os.environ, GIT_TERMINAL_PROMPT='0'))
        if result.returncode == 0: token = dict(line.split('=', 1) for line in result.stdout.splitlines() if '=' in line).get('password')
    if not token: raise ValueError('Sign in to GitHub on this Mac before publishing; no publishing credential is available')
    return token


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs): return None


def publish(directory):
    record = json.loads((directory / 'release.json').read_text())
    if record['repository'] != REPOSITORY: raise ValueError('Unexpected release repository')
    artifact = directory / record['asset']
    if artifact.name != f"WyGram {record['version']}.ipa" or record['github_asset'] != artifact.name.replace(' ', '.') or record['tag'] != f"v{record['version']}-b{record['build']}" or hash_file(artifact) != record['sha256']: raise ValueError('Prepared release changed')
    source_commit = record.get('source_commit')
    if source_commit is not None and not re.fullmatch(r'[0-9a-f]{40}', source_commit): raise ValueError('Invalid source commit')
    token = credential()
    opener = urllib.request.build_opener(NoRedirect)
    def request(path, method='GET', value=None, content_type='application/json'):
        url = path if path.startswith('https://') else 'https://api.github.com' + path
        if urllib.parse.urlparse(url).hostname not in ('api.github.com', 'uploads.github.com'): raise ValueError('Untrusted GitHub endpoint')
        data = json.dumps(value).encode() if value is not None and not isinstance(value, bytes) else value
        req = urllib.request.Request(url, data=data, method=method, headers={'Authorization': 'Bearer ' + token, 'Accept': 'application/vnd.github+json', 'Content-Type': content_type, 'User-Agent': 'WyGram-Release-Publisher'})
        with opener.open(req, timeout=180) as response: return json.load(response)
    repo = request('/repos/' + REPOSITORY)
    if not repo.get('permissions', {}).get('push'): raise ValueError('GitHub login has no release publishing permission for Wyatt323/WyGram')
    if source_commit and request('/repos/' + REPOSITORY + '/commits/' + source_commit).get('sha') != source_commit: raise ValueError('Source commit is not available on GitHub')
    try:
        request('/repos/' + REPOSITORY + '/releases/tags/' + record['tag'])
    except urllib.error.HTTPError as error:
        if error.code != 404: raise
    else: raise ValueError('Release tag already exists; old releases are never overwritten')
    release = request('/repos/' + REPOSITORY + '/releases', 'POST', {'tag_name': record['tag'], 'target_commitish': source_commit or repo.get('default_branch', 'main'), 'name': f"WyGram {record['version']}", 'body': (directory / 'release-notes.md').read_text(), 'draft': True, 'prerelease': False})
    # Remains a draft if any upload or validation fails.
    expected = {}
    for file in [artifact, directory / record['source'], directory / 'SHA256SUMS.txt']:
        remote_name = file.name.replace(' ', '.')
        url = release['upload_url'].split('{', 1)[0] + '?' + urllib.parse.urlencode({'name': remote_name, 'label': file.name})
        request(url, 'POST', file.read_bytes(), 'application/octet-stream')
        expected[remote_name] = (hash_file(file), file.stat().st_size)
        print('Uploaded', file.name, flush=True)
    for attempt in range(10):
        assets = request('/repos/' + REPOSITORY + f"/releases/{release['id']}/assets")
        by_name = {asset['name']: asset for asset in assets}
        if all(by_name.get(name, {}).get('digest') == 'sha256:' + digest and by_name.get(name, {}).get('size') == size for name, (digest, size) in expected.items()): break
        time.sleep(2)
    else: raise ValueError('GitHub digest does not match; release remains a draft')
    result = request('/repos/' + REPOSITORY + f"/releases/{release['id']}", 'PATCH', {'draft': False, 'make_latest': 'true'})
    print('Published', result['html_url'])


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='command', required=True)
    p = sub.add_parser('prepare'); p.add_argument('--ipa', type=Path, required=True); p.add_argument('--output', type=Path, required=True); p.add_argument('--notes', type=Path, required=True); p.add_argument('--source-commit')
    p = sub.add_parser('publish'); p.add_argument('directory', type=Path)
    args = parser.parse_args()
    try:
        if args.command == 'prepare': prepare(args.ipa, args.output, args.notes, args.source_commit)
        else: publish(args.directory)
    except Exception as error:
        # Never dump a Request, headers, credentials or private configuration.
        print('Release failed:', str(error) if isinstance(error, (ValueError, urllib.error.HTTPError)) else type(error).__name__)
        raise SystemExit(1)
