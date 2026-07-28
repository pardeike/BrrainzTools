# Release Packaging

This page is for maintainers.

## Build The DMG

```bash
VERSION=v1.1.2 ./Scripts/package-dmg.sh
```

The output is written to:

```text
output/release/RegionShot-v1.1.2/
```

The DMG contains:

- the signed `regionshot` binary
- `Install RegionShot.command`
- the README
- the `docs/` folder
- bundled agent support files

## Notarization

The script uses:

- the first local `Developer ID Application` signing identity, unless
  `CODESIGN_IDENTITY` is set
- the `brrainz-notary` keychain profile, unless `NOTARY_KEYCHAIN_PROFILE` is set

Create the notary profile once:

```bash
xcrun notarytool store-credentials brrainz-notary \
  --apple-id "you@example.com" \
  --team-id "TEAMID" \
  --password "app-specific-password"
```

Override values when needed:

```bash
CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
NOTARY_KEYCHAIN_PROFILE="profile-name" \
VERSION=v1.1.2 \
./Scripts/package-dmg.sh
```

For a local unsigned/not-notarized packaging test:

```bash
NOTARIZE=0 VERSION=v1.1.2 ./Scripts/package-dmg.sh
```

## Checks

The package script verifies the binary signature, signs the DMG, submits it to
Apple notarization, staples the ticket, runs Gatekeeper assessment on the DMG,
and writes a SHA-256 file next to it.

Manual checks:

```bash
xcrun stapler validate output/release/RegionShot-v1.1.2/RegionShot-v1.1.2-macos.dmg
spctl --assess --type open --context context:primary-signature --verbose output/release/RegionShot-v1.1.2/RegionShot-v1.1.2-macos.dmg
shasum -a 256 output/release/RegionShot-v1.1.2/RegionShot-v1.1.2-macos.dmg
```
