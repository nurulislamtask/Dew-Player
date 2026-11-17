<p align="center"><img height="96" src="./assets/icon.png"></p>

<h1 align="center">Dew Player</h1>
<p align="center">A clean, smooth video player for <b>Android</b> and <b>Windows</b> with automatic subtitles in any language.</p>

## Downloads

Get the latest build from [Releases](https://github.com/nurulislamtask/Dew-Player/releases/latest):

| Platform | File |
|---|---|
| Windows 10/11 (x64) | `DewPlayer-win-Setup.exe` (installer, auto-updates) or `DewPlayer-win-Portable.zip` |
| Android (most phones) | `DewPlayer-android-arm64.apk` |
| Android (old 32-bit phones) | `DewPlayer-android-armv7.apk` |

## Features

- Plays almost every video and audio format (libmpv / FFmpeg, hardware decoding)
- Folder-wise video library (like MX Player), network streams (http, HLS, DASH, rtsp, rtmp)
- Automatic subtitles: if a video has no subtitles, AI (Whisper, offline) creates them in the spoken language, then translates them to the language you choose (100+ languages)
- Embedded tracks, external `.srt` / `.vtt` / `.ass` (also picked up automatically when next to the video)
- Gestures: swipe for volume / brightness / seek, double tap to skip 10s, hold for 2x speed, lock screen
- Resume where you stopped, audio track switch, speed, aspect ratio, rotation
- Settings: theme (system / dark / light / AMOLED black), accent color, subtitle language and size, AI quality
- Auto update from GitHub Releases

## Releasing a new version

```
git tag v0.2.0
git push origin v0.2.0
```

GitHub Actions builds everything and publishes the release. Versions must increase for auto update to trigger.

### Optional: use your own Android signing key

The repo contains a ready-made key so the first build works. For better security create your own and add these repository secrets: `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`. (Changing the key later means users must uninstall once and reinstall.)

## Repo layout

- `app/` Flutter app (Android + Windows)
- `.github/workflows/release.yml` build and release

## License

GPL-3.0. See `LICENSE`.
