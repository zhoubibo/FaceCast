# FaceCast

FaceCast is a macOS screen recorder that composites your camera feed on top of the screen in real time. It is designed for demos, tutorials, walkthroughs, and bug reproduction videos where a picture-in-picture camera overlay is useful.

## Features

- Record the screen and camera together into a single video
- Move the camera overlay and switch between full-screen and PiP modes
- Capture microphone input and system audio
- Control recording from the main window, settings, and menu bar
- Package the app as a local `.app` bundle or a drag-install `.dmg`

## Requirements

- macOS 13 or later
- Xcode 15 or later

## Project Structure

- `FaceCast/`: SwiftUI app source, capture pipeline, models, utilities, and Metal compositor
- `FaceCast.xcodeproj/`: Xcode project
- `scripts/package-mac.sh`: Packaging script for `.app` and `.dmg`
- `PACKAGING.md`: Notes for local packaging and distribution signing

## Build and Run

1. Open `FaceCast.xcodeproj` in Xcode.
2. Select the `FaceCast` scheme.
3. Build and run the app.
4. Grant Screen Recording, Camera, and Microphone permissions when prompted.

You can also build a local installable app bundle from Terminal:

```bash
./scripts/package-mac.sh --app-only
```

To build a styled DMG for local distribution:

```bash
./scripts/package-mac.sh
```

## Permissions

FaceCast requires these macOS permissions to work correctly:

- Screen Recording
- Camera
- Microphone

System audio capture depends on the ScreenCaptureKit APIs available on modern macOS versions.

## Packaging Notes

- The project currently uses automatic signing in Xcode.
- The packaged `.dmg` flow is intended for a logged-in macOS desktop session because it uses Finder automation.
- If you want to distribute builds outside your own machine, sign with a `Developer ID Application` certificate and notarize the app.

More details are in `PACKAGING.md`.

## Contributing

Issues and pull requests are welcome. Please read `CONTRIBUTING.md` before submitting changes.

## Security

If you find a security issue, please read `SECURITY.md` before reporting it publicly.

## License

This project is released under the Apache License 2.0. See `LICENSE`.
