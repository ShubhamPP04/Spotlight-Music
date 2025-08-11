# Packaging Spotlight Music into a DMG

This guide helps you produce a distributable DMG that works online or offline.

## Prereqs
- Xcode command line tools
- Optional: Apple Developer certs for codesigning/notarization
- Optional: Python runtime you want to bundle (see Bundled Python)

## One-shot build
Run the script to build, (optionally) bundle Python/wheels, codesign, and create a DMG.

```
./PackagingResources/package.sh \
  --scheme "Spotlight Music" \
  --bundle-id com.example.SpotlightMusic \
  --version 1.0.0 \
  --sign "Developer ID Application: Your Name (TEAMID)" \
  --bundle-python /path/to/BundledPython \
  --wheels-dir /path/to/PythonWheels
```

Flags are optional. If you omit `--bundle-python` or `--wheels-dir`, the app will use system Python and/or install packages online at first run.

## Artifacts
- Build: `build/Release/Spotlight Music.app`
- DMG: `dist/Spotlight-Music-<version>.dmg`

## Bundled Python
Provide a folder with a `bin/python3` (and supporting libs) inside. The script copies it to `Spotlight Music.app/Contents/Resources/BundledPython`.

## Bundled Wheels (offline)
Place wheels for `ytmusicapi` and `yt-dlp` in a folder. The script copies it to `Spotlight Music.app/Contents/Resources/PythonWheels`, allowing offline installs on first run.

## Notarization (optional)
After creating the DMG, you can notarize it with `xcrun notarytool` and staple the ticket.
