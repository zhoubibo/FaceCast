# FaceCast Packaging

## Build a local-install app

```bash
./scripts/package-mac.sh --app-only
```

Output:

- `dist/FaceCast.app`

This is enough for local installation on a Mac. Drag `dist/FaceCast.app` into `Applications`.

## Build a drag-install dmg

```bash
./scripts/package-mac.sh
```

Output:

- `dist/FaceCast.app`
- `dist/FaceCast.dmg`

Open the dmg and drag `FaceCast.app` into `Applications`.

## Notes

- The Xcode project currently uses automatic signing in `FaceCast.xcodeproj/project.pbxproj`.
- The dmg builder renders a branded background and uses Finder automation to set icon positions and the install window layout.
- The styled dmg flow is intended to run in a logged-in macOS desktop session because it uses `osascript` to configure the mounted Finder window.
- If Xcode is not configured with a `Developer ID Application` certificate, the app is signed for local use only.
- For distribution to other Macs without Gatekeeper warnings, sign with `Developer ID Application` and notarize the app before shipping the dmg.
