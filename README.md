<p align="center"><img height="96" src="./assets/icon.png"></p>

<h1 align="center">Dew Player</h1>
<p align="center">A modern, subtitle-first video player for <b>Windows</b> and <b>Android</b>.</p>

## Downloads

Get the latest build from [Releases](https://github.com/nurulislamtask/Dew-Player/releases/latest):

| Platform | File |
|---|---|
| Windows 10/11 (x64) | `DewPlayer-win-Setup.exe` (installer, auto-updates) |
| Android (most phones) | `DewPlayer-android-arm64.apk` |
| Android (old 32-bit phones) | `DewPlayer-android-armv7.apk` |

## Auto update

- **Windows:** installed with the Setup.exe, the app checks GitHub Releases in the background, downloads the update and asks to restart. Toggle in *Settings > About*.
- **Android:** the app checks GitHub Releases when it opens, then downloads and installs the new APK. Toggle in *Settings*. Android will ask once to allow "install unknown apps".

## Features

**Windows** (based on [LLPlayer](https://github.com/umlx5h/LLPlayer), new Dew theme and floating control bar): dual subtitles, AI subtitles (Whisper), real-time translation, OCR for bitmap subtitles, subtitle sidebar, word lookup, yt-dlp online video, subtitle downloader, custom shortcuts.

**Android** (new Flutter app, hardware decoding through libmpv/media_kit, kept light): local files and network streams, dual subtitles (embedded track or .srt/.vtt/.ass file), automatic translation as a second subtitle line, tap a subtitle to look up words, subtitle list with tap-to-seek, double-tap seek, long-press 2x speed, swipe volume, speed control, recent list.
Not in the mobile app yet: Whisper AI subtitles and OCR (too heavy for phones).

## Releasing a new version

```
git tag v0.1.0
git push origin v0.1.0
```

GitHub Actions builds everything and publishes the release. Versions must increase (v0.1.1, v0.2.0 ...) for auto update to trigger.

### Optional: use your own Android signing key

The repo contains a ready-made key so the first build works. For better security create your own and add these repository secrets: `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`. (Changing the key later means users must uninstall once and reinstall.)

## Repo layout

- `windows/` PC app (C#/WPF, .NET 10)
- `mobile/` Android app (Flutter)
- `.github/workflows/release.yml` build and release

## License

GPL-3.0. The Windows app is a modified version of [LLPlayer](https://github.com/umlx5h/LLPlayer) by umlx5h (GPL-3.0); see `LICENSE`.
