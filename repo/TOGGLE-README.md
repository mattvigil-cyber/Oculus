# The Apparatus — Toggle & Slider Reference

What each control in the panel actually does, read off the code rather than the label.

Applies to both plates — `oculus.html` and `i-see-you.html` share the panel verbatim.

The panel sits bottom-left at 30% opacity and comes up to full on hover. Its header carries a live
fps readout. Press `h` to hide it along with all other chrome.

On a phone — and on any touch device, or any window under 720px — there is no hover to lean on and
the panel would cover half the plate, so it rests **stowed**. A 44px eye button in the bottom-left
corner summons it and puts it away again; the button goes gold while the panel is up. The panel
opens above the button, spans the width less a 12px margin, and its body is capped at 52% of the
viewport height so the camera preview can never push it off screen — it scrolls instead. On a
pointer machine nothing changes: no button, and the panel keeps its faint always-there presence.

---

## Quick reference — sliders

| Slider | Range | Default | One line | Rebuilds? |
|---|---|---|---|---|
| **Spin** | 0 – 3.0 | 1.0 | Multiplier on every ring's rotation. 0 holds them still. | no |
| **Wash** | 0 – 1.0 | 0.42 | Opacity of the colour bed under the letters. | no |
| **Bloom** | 0 – 1.0 | 0.45 | Halation on the lit glyphs. | no |
| **Grain** | 0 – 1.0 | 0.34 | Film grain, re-offset every frame. | no |
| **Density** | 0.70 – 1.40 | 1.0 | Type size, and therefore ring count. | **yes** |
| **Reach** | 0.4 – 3.2 | 1.7 | Gain on head movement. **Camera only.** | no |

## Quick reference — toggles

| Button | Default | One line | Rebuilds? |
|---|---|---|---|
| **Gaze** | on | Master switch for tracking. Gates the pointer *and* the camera. | no |
| **Blink** | on | Occasional blink, every 3.2–10.7 s. | no |
| **Stroma** | on | Composites the baked underpainting at full `Wash` instead of half. | no |
| **Halt** | off | Freezes `TIME` — rotation, saccades, hippus, blink scheduling. | no |
| **Face ◉** | off | Starts the camera and hands gaze to face tracking. | no |
| **Mirror** | on | Flips the horizontal camera mapping. **Camera only.** | no |
| **Feed** | off | Camera preview with a crosshair on the tracked point. | no |
| **Transmute ⟳** | — | New random seed. Not a toggle — a momentary re-roll. | **yes** |

Two have keyboard equivalents: `space` for **Halt**, `r` for **Transmute**.

---

## Spin — rotation rate

Range 0–3.0, default **1.0** (**0.3** when the system asks for reduced motion). A global multiplier
on every layer's rotation: the iris base, the five ring layers and the sclera, each of which has its
own rate and direction, further modulated by a slow sine so the shimmer never settles into a visible
period.

Each layer's angle is integrated frame by frame:

```js
L.phase = (L.phase + L.dir * L.rate * mod * dt * P.spin) % TAU;
```

So dragging Spin changes the *speed* smoothly and the plate never jumps. **Spin 0** holds every ring
exactly where it is. The difference from **Halt**: Halt also stops the clock, so micro-saccades,
hippus and blink scheduling freeze with it. Spin 0 stills the rings and leaves the eye alive.

## Wash — the colour bed

Range 0–1.0, default **0.42**. The opacity at which the baked underpainting — colour wash, fibres,
crypts, collarette, limbal ring — is composited beneath the type.

Low, and the letters float on black. High, and they sit on a painted iris. This is the single
strongest lever on whether the piece reads as *typography* or as *an eye*.

Interacts with **Stroma**, which simply halves whatever this is set to.

## Bloom — halation

Range 0–1.0, default **0.45**. Thresholded glow on the lit glyphs: the plate is downscaled to 26%,
its midtones crushed by a multiply pass so only peaks survive, blurred at that small scale, then
composited back with `lighter`.

The slider is scaled by 0.62 internally, so the maximum is a 0.62 alpha rather than full. Values
below 0.01 skip the pass entirely — worth knowing if you are chasing frame rate, though after the
optimisation work this pass costs under a millisecond.

## Grain — film stock

Range 0–1.0, default **0.34**. A pre-baked noise tile blitted across the plate in `overlay`,
re-offset by a random amount every frame so it twinkles rather than sitting still.

Scaled by 0.20 internally, so even at maximum it stays a texture rather than a veil. Below 0.01 the
pass is skipped.

## Density — type size, and therefore everything

Range 0.70–1.40, default **1.0**. Multiplies the font size at every radius. Because rings are spaced
at `fontSize × 0.94`, this inverts into ring count:

- **Lower** Density → finer type → **more** rings → more words, denser plate, longer build
- **Higher** Density → larger type → **fewer** rings → bolder, more legible, sparser

This is the only control that re-inscribes the plate. It is bound to the slider's `change` event
rather than `input`, so the readout updates live as you drag but the ~1–2 s rebuild fires **once, on
release**. That is deliberate — binding it to `input` would trigger a rebuild per pixel of drag.

Note it does not change the eye's size or position, only the granularity of the text within it.

## Reach — camera gain

Range 0.4–3.2, default **1.7**. How far a given head movement throws the gaze under face tracking.
The normalised face offset is multiplied by this, then clamped to the unit disc.

That clamp is the thing to understand: at high Reach you hit full deflection with a small movement
and then *stay* railed, so the eye stops responding until you come back toward centre. Lower it if
the gaze feels twitchy or pinned to the edges.

**Camera only** — like Mirror. Pointer tracking uses its own fixed scaling and ignores this slider
entirely, so dragging it with Face off does nothing.

## Gaze — the master tracking switch

Default **on**. This gates *both* input paths, not just the pointer. `setTargetFromPointer()`
returns immediately when it is off, and the camera's `faceFresh` check also requires it — so turning
Gaze off **overrides Face**. The camera keeps running, the detector keeps detecting, and the eye
simply stops listening.

What is easy to misread: it does not make the eye *still*. It hands the eye to autonomous
wandering — a new random target every 0.7–3.3 s, eased toward. The eye keeps moving. It just stops
moving because of you.

## Blink — the involuntary one

Default **on**. Schedules a blink every `3.2 + rng()*7.5` seconds, so 3.2–10.7 s apart, never on a
period you can anticipate. The lid closes over ~0.085 s and opens over ~0.16 s — deliberately
asymmetric, because a real blink snaps shut and drifts open — with the amplitude following a sine so
there is no hard stop at full closure.

Turning it off zeroes the blink state immediately rather than waiting for an in-progress blink to
finish. Note that **Halt** also suppresses new blinks, since scheduling is keyed to the frozen clock.

## Stroma — half the underpainting

Default **on**. The name oversells it. All the anatomy — ~1,500 trabecular fibres, ~80 crypts of
Fuchs, the collarette, the colour wash — is baked into `irisBase` during the build and **stays baked
in regardless of this toggle**. It changes exactly one thing: the opacity that plate is composited
at. `Wash` when on, `Wash × 0.5` when off.

So read it as a *half the underpainting* switch. It appears to flatten the iris because at half
strength the letters stop sitting **on** a painted eye and start floating on black.

Interacts with the **Wash** slider — Stroma off is equivalent to halving Wash. If you have already
pulled Wash down, this toggle will look like it does almost nothing.

## Halt — freezes the clock, not just the spin

Default **off**. It stops `TIME` from accumulating, and `TIME` is the master clock, so this reaches
considerably further than rotation.

**Stops:**

- all ring, iris and sclera rotation
- micro-saccades — the next-saccade test never fires again, so the current sub-pixel offset freezes
- pupil hippus, the three summed sines of autonomic drift
- blink *scheduling* — though a blink already underway still completes, because its phase advances on
  real frame time rather than on `TIME`

**Keeps running:**

- gaze tracking and easing
- pupil constriction as the pointer nears
- the click flare

`updateGaze()` and `render()` are both called *outside* the paused branch, which is why.

The net effect is more interesting than "pause": the eye keeps following you but loses all its
involuntary life. It tracks with an unnatural smoothness and stops blinking. Genuinely useful for
studying the plate or taking a clean screenshot — which is why `space` is bound to it.

## Face ◉ — hand gaze to the camera

Default **off**. Starts the camera and switches gaze from pointer to face tracking, using MediaPipe
BlazeFace short-range. Face centre drives the gaze vector, scaled by **Reach**; face width as a
fraction of frame width drives pupil dilation, replacing the pointer-proximity response.

Requires a secure origin — https or `http://localhost`, never `file://` — plus OS and browser camera
permission. Lose the face for ~900 ms and it falls back to autonomous wandering, not to the mouse.

Remember that **Gaze** outranks it. With Gaze off, Face does nothing visible.

## Mirror — camera only

Default **on**. It appears in exactly three places, all in the camera path: negating the horizontal
face offset, flipping the preview video, and flipping the crosshair to match.

**It does nothing whatsoever under pointer control.** With Face off, toggling it has no visible
effect — which reliably makes it look broken when you are testing. It exists because a webcam faces
you, so your left is the frame's right.

This remains the one thing in the piece never confirmed against a deliberate left/right movement.
Turn on **Feed** and lean one way; if the eye goes the other, toggle this.

## Feed — see what it sees

Default **off**. Opens the camera preview inside the panel with a crosshair drawn on the tracked
point. The preview is flipped in lockstep with **Mirror**, so what you see matches what the eye does.

Worth turning on for the first run on any new machine — it is the only way to confirm the mapping is
right rather than merely plausible.

## Transmute ⟳ — not a toggle, a re-roll

A momentary button, not a state:

```js
SEED = (Math.random()*1e9)|0;
startBuild();
```

Because everything generative draws from that one seeded PRNG, a re-roll changes which word lands on
which ring, the per-token hue/saturation/lightness jitter, where the vivid accents fall, which font
stack each ring samples, the fibre and crypt placement, and which rings read backwards.

What it does **not** change is layout — eye size, position and ring count come from window size and
the **Density** slider.

Costs a full ~1–2 s re-inscription, chunked so the page stays responsive.

**One catch:** because the seed comes from `Math.random()`, a plate you liked is gone the moment you
press it again. If you land on one worth keeping, read `SEED` from the console and hard-code it.

---

## Gotchas, collected

| If this happens | Because |
|---|---|
| Face does nothing | **Gaze** is off, and it gates the camera too. |
| Mirror seems dead | It only touches the camera path. Turn **Face** on. |
| Stroma barely changes anything | **Wash** is already low; Stroma only halves it. |
| The eye stops blinking | **Halt** freezes blink scheduling along with the clock. |
| The eye still drifts with Gaze off | That is autonomous wandering, not tracking. |
| A plate you liked is unrecoverable | **Transmute** seeds from `Math.random()`. Read `SEED` first. |
| Spin starts at 0.3 and Blink starts off | The system has reduced motion turned on. Both are still adjustable. |
| **Reach** seems dead | Camera only, like Mirror. Pointer tracking ignores it. |
| The gaze pins to the edge and stops | **Reach** too high; the vector is railed against the unit-disc clamp. |
| **Density** does nothing while dragging | It rebuilds on release, not on drag. |
