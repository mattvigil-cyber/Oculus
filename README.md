# Oculus.app — the piece as a Mac desktop

A menu-bar agent that renders `i-see-you.html` (or `oculus.html`) as **live wallpaper** behind your
icons, or as an **idle-triggered screensaver**, with face tracking intact.

> Installing it, on this Mac or another one → **[INSTALL.md](INSTALL.md)**. This file is the design
> rationale: why it works the way it does.

| | |
|---|---|
| **Build** | `./build.sh` — Command Line Tools only, no Xcode project |
| **Size** | ~23 MB, almost all of it the vendored detector |
| **Runs as** | menu-bar agent (`LSUIElement`), no Dock icon |
| **Network** | none — everything is served from inside the bundle |

```bash
./build.sh && ./install.sh
```

`install.sh` puts it in `~/Applications` and launches it from there — a resident process should not
live in a Google Drive folder that re-syncs it and can swap files underneath it. An eye appears in
the menu bar. macOS asks for camera permission the first time; see below if it asks more than once.

---

## Why not a real screensaver

macOS 14 moved third-party `.saver` bundles into Apple's sandboxed `legacyScreenSaver` host process.
Camera requests from inside it are attributed to that host — which carries no camera usage
description and is not a bundle you can amend — so face tracking there is unreliable at best, and at
the login window it is impossible outright.

So this is a normal app that *behaves* like a screensaver: it watches the idle timer and throws a
full-screen window up at `screenSaverWindow` level when you have been away long enough. Camera
permission is then the ordinary kind, which simply works. The one thing given up is the lock screen,
which no third-party code with a camera can have anyway.

## Modes

| Mode | Window level | Camera |
|---|---|---|
| **Wallpaper, then screensaver** | behind the icons, rising over everything once idle | on while it can see out |
| **Wallpaper only** | just under the desktop icons | on while the desktop is exposed |
| **Screensaver only** | hidden until idle, then above everything | on only while it is up |
| **Off** | hidden | off |

**Wallpaper, then screensaver** is the default and the one to run on a plugged-in desktop: the eye
lives behind your icons, and when you walk away it comes forward over everything instead of
disappearing. Any input sinks it back behind the icons — it never leaves.

**Screensaver only** suits a laptop, since the camera then draws power solely while you are away.

If you use a rising mode, turn the built-in screensaver off — System Settings → Lock Screen →
*Start Screen Saver when inactive: Never* — or the two will race each other.

### The occlusion rule

In wallpaper mode the camera follows `NSWindow.occlusionState`. Cover the desktop with a full-screen
window and the eye stops rendering *and* releases the camera; expose the desktop and it wakes. Two
things fall out of that for free: a video call never has to contend for the webcam, and the green
camera light is on only when the eye is genuinely able to see you.

`Let it watch me` in the menu is the hard switch — off means the eye wanders on its own and the
camera is never opened at all.

## Menu

- **Start screensaver now** — raise it deliberately and walk away, without waiting out the idle timer
- **Mode** — see the table above
- **Piece** — I See You / Ocvlvs · Speculum Verborum
- **Display** — which screen it occupies (one screen only, deliberately)
- **Rises after** — idle delay, for the modes that rise
- **Frame rate** — see below
- **Let it watch me** — master camera switch
- **Let it blink** — off by default; see below
- **Reload piece**, **Open at Login**, **Quit**

### Blink

The eye blinks every 3–11 seconds. In a window you are looking at that reads as life; behind the
work you are actually doing it reads as movement in your peripheral vision, so it is **off by
default** here. The toggle is live — no reload.

It works by driving the panel's own `Blink` button rather than reaching into the engine, so the
internal flag and the button state cannot drift apart. With the flag off the engine pins the blink
amount to zero and never enters the lid-drawing path at all.

### Frame rate

An ambient wallpaper on a 144 Hz display will repaint 144 times a second forever, which buys nothing
on a piece that turns this slowly. The default caps it at 30.

The cap works by batching every `requestAnimationFrame` callback and releasing them together, so the
plate, the build and the detector stay in lockstep instead of beating against each other. A
consequence worth knowing: an rAF throttle can only deliver divisors of the refresh rate, so "60" on
a 144 Hz panel really means 48. The menu labels say what you will actually get.

## How it fits together

```
AppController   modes, idle polling, occlusion gating, menu, preferences
LocalServer     loopback-only static file server (Network.framework)
Piece           WKWebView, camera bridge, injected scripts
PieceWindow     one window, reconfigured between wallpaper and screensaver roles
```

**Why a server at all.** `getUserMedia` refuses to run outside a secure context, and `file://` is not
one — nor is a custom URL scheme. `127.0.0.1` *is*, so the cheapest honest answer is to actually
serve the folder. It binds to loopback, refuses paths that escape the web root, and serves `.wasm`
as `application/wasm` so streaming compilation works.

**Why the assets are vendored.** The piece normally pulls MediaPipe from jsdelivr. For something
that runs all day and wakes constantly, a CDN round-trip on every wake is a dependency worth
deleting, so `build.sh` bakes the detector and model into the bundle and the app points the piece at
them via `window.OCULUS_ASSETS`.

**One window, two roles.** Wallpaper and screensaver differ only in window level, whether they
swallow input, and when they are on screen — so a single window is reconfigured between them. That
keeps the WKWebView alive across a mode switch instead of rebuilding the plate.

## Editing the piece

`build.sh` copies `../i-see-you.html` and `../oculus.html` into the bundle, so edit those and rebuild.
The HTML is served with `no-store`, so **Reload piece** picks up changes without a relaunch — as long
as you have rebuilt.

## Camera permission, and why it kept asking

macOS keys a camera grant to the app's **designated requirement**. Signed with a real identity that
is `identifier + certificate`, which survives a rebuild. Signed ad-hoc it is the raw hash of the
binary:

```
# designated => cdhash H"332a31e7458abdd81af5b5546b07a2c768b1b0a7"
```

Change one byte of the app and that hash changes, so macOS sees software it has never met and asks
again. That is why an app under active development re-prompts on every single rebuild — the
permission was never lost, the app's identity was.

**If you are not rebuilding, there is nothing to do.** Grant it once and it sticks.

**If you are**, run this once:

```bash
./make-signing-identity.sh
```

It creates a self-signed, local-only code-signing certificate and trusts it for code signing alone —
not for TLS, and not system-wide. macOS will ask for your login password to change keychain trust.
After that, `build.sh` picks the identity up automatically, the designated requirement becomes
identity-based, and the camera grant survives every future rebuild. The script tells you how to undo
it.

There is no way to skip the OS camera prompt itself, and it would not be worth wanting — it is the
thing that guarantees nothing opens your webcam without you agreeing to it once.

## Known limits

- **One display.** Two eyes staring from adjacent monitors is a worse piece than one, and each extra
  screen is another full canvas.
- **No lock screen.** See above.
- **Idle detection** takes the minimum across the input event types a person actually generates,
  because `kCGAnyInputEventType` does not survive the Swift enum import.

## Contact

Matt Vigil — [mattvigil@gmail.com](mailto:mattvigil@gmail.com)
