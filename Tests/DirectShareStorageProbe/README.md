# Direct-share storage and startup-cleanup probe

```sh
python3 Tests/DirectShareStorageProbe/run.py --output /tmp/wygram-direct-share-macos
python3 Tests/DirectShareStorageProbe/run.py --platform simulator --output /tmp/wygram-direct-share-ios
```

The simulator command uses the local iPhone 15 Pro and iPhone 18 Pro Max IDs in
`run.py`. Both commands compile the real storage-transition and
`ApplicationDataStorage` code. The unchanged startup cleanup function body is
extracted from production `AccountManager.swift` for isolated compilation.

Fixtures contain fabricated keys, a real SQLite database and relative retained
photo filenames. Checks cover explicit opt-in, exclusive atomic rename, exact
directory identity and bytes, SQLite reopening, occupied/racing destinations,
denied moves, pre/post-move interruption, unavailable permission after a move,
malformed journals, symlink rejection, storage selection and bridge preservation
during startup cleanup. `--cleanup-baseline` can point to an older production
file to reproduce deletion of the two active bridge directories.

The probes are Foundation executables and do not use actual Telegram accounts,
signing permissions, an authenticated share picker or a physical device. They
do not execute a migration of user data, sign a release or create an IPA.

Constructed Mach-O entitlement sections also check that a common group must be
present in both executable signatures. A profile capability alone, missing or
malformed signature, or mismatched/invalid group names cannot enable setup.
These parser fixtures are not cryptographically valid signing or OS permission
tests.
