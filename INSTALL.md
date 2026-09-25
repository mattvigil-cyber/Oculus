# Installing Oculus

The piece as a Mac desktop: an eye assembled from language that lives behind your icons and follows
your face, and comes forward when you walk away.

It is a menu-bar app — no Dock icon, no window. Everything is the eye in the menu bar.

For *why* it is built this way, see [README.md](README.md). This file is just how to get it running.

---

## On this Mac (the Mac Studio)

Already installed at `~/Applications/Oculus.app`. To rebuild after editing the piece:

```bash
cd mac && ./build.sh && ./install.sh
```

---

## On another Mac (the laptop)

Two routes. **Building from source is the smoother one** — an app compiled on the machine it runs on
carries no quarantine flag, so macOS never blocks it.

### Route A — build it there (recommended)

The whole project is in Google Drive, so it is already on the laptop.

```bash
cd ~/"Google Drive/My Drive/Claude Projects/Experiments/Oculus/mac"
./build.sh && ./install.sh
```

If `swiftc` is missing, install the Command Line Tools first — a few minutes, no Xcode needed:

```bash
xcode-select --install
```

### Route B — the disk image

`dist/Oculus-1.0.dmg` (9 MB) is in the Drive folder, so it syncs to the laptop on its own. Open it
and drag **Oculus.app** onto the **Applications** shortcut.

**macOS will refuse to open it the first time.** The app is signed, but not *notarized* — notarizing
means submitting it to Apple, which needs a paid developer account. macOS treats anything arriving
from another machine as untrusted until told otherwise. This is one-time, per machine:

```bash
xattr -d com.apple.quarantine /Applications/Oculus.app
```

That removes the "came from elsewhere" flag and it opens normally from then on. If you would rather
not use the terminal: double-click it, let it be blocked, then go to **System Settings → Privacy &
Security**, scroll to Security, and click **Open Anyway** next to the message about Oculus.

> The binary is **arm64 only**. Fine for any Apple Silicon Mac; it will not run on an Intel one.

---

## First run, either route

1. **Camera.** macOS asks once. Allow it — the eye cannot track you otherwise, and nothing leaves
   the machine: the detector runs locally and no frame is uploaded anywhere.
2. **Pick a mode** from the menu-bar eye. See below.
3. **Turn off the built-in screensaver** if you use a mode that rises, or the two will race:
   System Settings → Lock Screen → *Start Screen Saver when inactive: **Never***.

### What to set on each machine

| | Mac Studio | MacBook Pro |
|---|---|---|
| **Mode** | Wallpaper, then screensaver | Screensaver only |
| **Frame rate** | Up to 30 fps | Up to 30 fps |
| **Why** | plugged in, so it can live behind the icons all day | on battery the camera should only run while you are away |

If the laptop is driving the 4K external, keep the frame cap at 30 — a base-tier chip has roughly an
eighth of the Ultra's memory bandwidth.

---

## Using it

Everything is under the menu-bar eye.

| Item | What it does |
|---|---|
| **Start screensaver now** | raise it deliberately and walk away, without waiting out the idle timer |
| **Mode** | Off / Wallpaper only / Screensaver only / Wallpaper, then screensaver |
| **Piece** | *I See You* (English) or *Ocvlvs · Speculum Verborum* (Latin, esoteric) |
| **Display** | which screen it occupies |
| **Rises after** | idle delay before the screensaver comes up |
| **Frame rate** | see README — a cap, and it tells you what you will really get |
| **Let it watch me** | master camera switch; off means the eye wanders on its own |
| **Let it blink** | off by default — the twitch is distracting on a desktop |
| **Open at Login** | start it automatically |
| **Quit Oculus** | stop everything and release the camera |

Once the screensaver is up it covers the menu bar. Any keypress or mouse move sinks it — in the
combined mode it drops back behind your icons rather than disappearing.

---

## Turning it off, and removing it

| | |
|---|---|
| Stop it now | menu → **Quit Oculus** |
| Keep it running but hide the eye | menu → **Mode → Off** |
| Keep the eye, stop the camera | untick **Let it watch me** |
| Stop it relaunching at login | untick **Open at Login** |
| Kill it if the menu is unreachable | `pkill -f "Oculus.app/Contents/MacOS/Oculus"` |

To remove it completely: quit, delete `~/Applications/Oculus.app`, then clear its settings with

```bash
defaults delete com.mattvigil.oculus
```

Nothing else is installed anywhere — no launch agents, no system settings changed, no files outside
the app bundle. If you turned off the built-in macOS screensaver, turn it back on.

---

## If something is wrong

**It asks for the camera every time.** It is being rebuilt between launches, and an ad-hoc signature
changes identity with every build. Run `./make-signing-identity.sh` once. Full explanation in
[README.md](README.md#camera-permission-and-why-it-kept-asking).

**The eye is there but never tracks.** Check **Let it watch me** is ticked, and that nothing else is
holding the camera. It retries every 30 seconds on its own, so a call that ends will free it without
your intervention.

**Nothing appears at all.** In *Screensaver only* mode nothing shows until the idle delay passes —
use **Start screensaver now** to check it works. Otherwise confirm **Display** points at the screen
you are looking at.

**It vanished when I opened a full-screen app.** Working as intended. The eye stops rendering and
releases the camera whenever it cannot see out, and comes back when the desktop is exposed.
