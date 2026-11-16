# Oculus

An eye assembled entirely from language. Concentric rings of words revolve at different rates, and
the eye follows your pointer or, with a camera, your face. It runs in a browser as a single HTML
file and on a Mac as live wallpaper and screensaver.

Nothing leaves your machine. Face detection runs locally and no frame is uploaded.

## Two plates

- `i-see-you.html` speaks plain English about being looked at.
- `oculus.html` speaks Latin, Greek, Hebrew and Sanskrit.

Double-click either file to run it. The camera needs `http://localhost` or https, so serve the
folder first:

```bash
python3 -m http.server 8000
```

Then open `http://localhost:8000/i-see-you.html`.

## Mac app

A menu-bar app renders the piece behind your desktop icons and raises it as a screensaver when you
walk away. Download the DMG from Releases, or build from source:

```bash
cd mac && ./build.sh && ./install.sh
```

Apple Silicon only, macOS 13 or later. The app is not notarized, so macOS blocks the first launch
of a downloaded copy. [mac/INSTALL.md](mac/INSTALL.md) has the one-time fix.

## Documentation

- [OCULUS.md](OCULUS.md): controls, face tracking, how the renderer works.
- [TEMPERAMENT.md](TEMPERAMENT.md): light reflex, sleep, speech, lexicons, circadian plates, poster export.
- [TOGGLE-README.md](TOGGLE-README.md): every panel control in detail.
- [mac/README.md](mac/README.md): why the Mac app is built the way it is.

## Third-party

Face detection uses [MediaPipe Tasks Vision](https://github.com/google-ai-edge/mediapipe) 1.0.1 and
its BlazeFace and Face Landmarker models, vendored in `mac/Resources/web/vendor`. MediaPipe is
licensed under Apache 2.0.
