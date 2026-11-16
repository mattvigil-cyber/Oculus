# OCVLVS — Speculum Verborum

An iris assembled entirely from language. Concentric rings of esoteric vocabulary revolve at
differing rates and directions; the eye tracks your pointer, or — with a camera — your face.

Single self-contained HTML file. No build step, no dependencies for the base piece.
The optional face tracking pulls one model from a CDN at runtime.

| | |
|---|---|
| **File** | `oculus.html` — about 1,950 lines, 80 KB |
| **Renderer** | HTML5 Canvas 2D |
| **Glyphs drawn** | ~25,000, individually placed and coloured |
| **Lexicon** | 487 terms across 7 depth bands |
| **Dependencies** | none (face tracking adds MediaPipe `tasks-vision` 1.0.1) |

---

## Quick start

Double-click `oculus.html`. That is enough for everything except the camera.

For face tracking you need a secure origin — https or `http://localhost`. Nothing leaves the
browser either way: BlazeFace runs locally on the canvas, and no frame is ever uploaded.

Serve the folder yourself on a stable port:

```bash
python3 -m http.server 8000
```

Then open `http://localhost:8000/oculus.html`.

See [Face tracking](#face-tracking) below for the permission gates.

---

## Controls

The panel sits bottom-left at 30% opacity and comes up to full on hover.

On touch devices and windows narrower than 720px it starts stowed instead, behind a 44px eye button
in the bottom-left corner — tap to summon, tap to put away. See
[TOGGLE-README.md](TOGGLE-README.md) for the details.

### Sliders

Summarised here; see [TOGGLE-README.md](TOGGLE-README.md) for the details and the gotchas.

| Control | Default | Effect | Live? |
|---|---|---|---|
| **Spin** | 1.0 | Global multiplier on every ring's rotation. Changes speed smoothly. 0 holds the rings still while the eye keeps moving. | yes |
| **Wash** | 0.42 | Opacity of the colour bed under the letters. Low = letters float on black; high = a painted iris. | yes |
| **Bloom** | 0.45 | Halation on the lit glyphs. Thresholded, so it lifts highlights without fogging the plate. | yes |
| **Grain** | 0.34 | Film grain, re-offset every frame. | yes |
| **Density** | 1.0 | Type size, and therefore ring count. Lower = more, finer rings. | **rebuilds** |
| **Reach** | 1.7 | How far a given head movement throws the gaze under camera tracking. | yes |

`Density` triggers a full re-inscription on release, not on drag.

### Toggles

Summarised here; see [TOGGLE-README.md](TOGGLE-README.md) for what each one actually does, including
how they override each other.

| Button | Default | Effect |
|---|---|---|
| **Gaze** | on | Master switch for tracking. Off = the eye wanders on its own. |
| **Blink** | on | Occasional blink, every 3–11 s. |
| **Stroma** | on | Composites the baked underpainting at full `Wash` rather than half. Off flattens the iris. It does not remove the fibres — they stay baked in. |
| **Halt** | off | Freezes `TIME`: rotation, micro-saccades, hippus and blink scheduling all stop. Gaze still tracks. |
| **Face ◉** | off | Starts the camera and hands gaze control to face tracking. |
| **Mirror** | on | Flips the horizontal mapping. A webcam faces you, so left is right. |
| **Feed** | off | Camera preview with a crosshair on the tracked point. |
| **Transmute ⟳** | — | New random seed. Rebuilds with a different lexicon arrangement and palette drift. |

### Keys

| Key | Action |
|---|---|
| `space` | halt / resume rotation |
| `r` | transmute (new seed) |
| `h` | hide all chrome — titles, panel, motto |
| `f` | fullscreen |

Click anywhere to flare the pupil.

With reduced motion turned on in the system settings, the piece opens with **Spin** at 0.3 and
**Blink** off. Both stay on the panel.

---

## Face tracking

### The three gates

**1. Secure context.** `getUserMedia` is blocked on `file://`. Opening the file by double-clicking
will never reach the camera, no matter what permissions you grant. Serve it over `http://localhost`
(localhost counts as secure — no certificate needed) or https.

Use a **stable port**. The camera grant is bound to the origin, so a changing port means
re-approving every time.

**2. macOS permission.** System Settings → Privacy & Security → Camera → enable for your browser.
This is the OS gate and is separate from the page prompt. If it is off, the browser prompt still
appears but the stream fails with `NotReadableError`.

**3. Browser permission.** The page prompts on first use.

Chrome is the safest bet. Then press **Face ◉**.

### How it maps

Detection is **MediaPipe BlazeFace short-range** via `@mediapipe/tasks-vision`, GPU-delegated with
automatic CPU fallback if the WebGL delegate is refused. This uses the lightweight `FaceDetector`
rather than the 478-point landmarker, since face position and size are all that is needed —
230 KB model, ~2 ms per frame, throttled to 30 Hz.

- **Face centre** in the video frame drives the gaze vector, scaled by `Reach`, clamped to the unit disc.
- **Mirror** flips X, and flips the preview in lockstep so what you see matches what the eye does.
- **Face width** as a fraction of frame width drives pupil dilation — lean toward the lens and the
  aperture opens. This replaces the pointer-proximity response while the camera is live.
- Raw BlazeFace output jitters several pixels frame to frame, so the signal is exponentially
  smoothed (0.30 position, 0.14 size) before it reaches the eye. Without this, the existing
  micro-saccades compound into a visible tremor.
- Lose the face for ~900 ms and it falls back to autonomous wandering, not to the mouse. Single
  dropped detections inside that window are ignored, so the gaze holds steady through them.
- Hide the tab and the camera is released, so the light goes off. Come back and it resumes.

Turn on **Feed** for the first run. If the eye moves opposite to you, toggle **Mirror**.

### Running offline

Assets come from a CDN on first run and are HTTP-cached after. To go fully offline, download these
into one directory:

```
https://cdn.jsdelivr.net/npm/@mediapipe/tasks-vision@1.0.1/vision_bundle.mjs
https://cdn.jsdelivr.net/npm/@mediapipe/tasks-vision@1.0.1/wasm/          (directory)
https://storage.googleapis.com/mediapipe-models/face_detector/blaze_face_short_range/float16/1/blaze_face_short_range.tflite
```

…then point the piece at it, with no source edit required:

```
i-see-you.html?assets=/vendor
```

A host embedding the piece can set `window.OCULUS_ASSETS` before the module runs instead — which is
what the macOS app in [`mac/`](mac/README.md) does. With neither, the CDN is used exactly as before.
`MP_VERSION` remains a named constant near the bottom of the file if the package moves again.

---

## How it works

### The core trick

Drawing 25,000 rotated glyphs every frame would not hold 60 fps. Instead the whole plate is
**inscribed once** into offscreen canvases during a chunked build, and each frame only does a
handful of `drawImage` calls with a rotation. Build cost is paid once; runtime is nearly free.

The build runs in a generator pumped at 22 ms per frame, so the page stays responsive and the
loader can report progress. Roughly 1–2 s on a real display.

### Layer stack

| Layer | Count | Radius | Motion |
|---|---|---|---|
| `irisBase` | 1 | ≤ 1.005 R | slow counter-rotation |
| `ringLayers` | 5 | ≤ 1.005 R | alternating directions, 5 distinct rates |
| `scleraLayer` | 1 | ≤ 1.40 R | very slow counter-rotation |
| `fieldLayer` | 1 | full canvas | static (it is the face, not the eye) |

Rings are dealt **round-robin** into the 5 rotating layers, so adjacent rings land on different
layers and shear against each other. Each layer's rate is further modulated by a slow sine, so the
shimmer never settles into a visible period.

`fieldLayer` has a soft radial hole punched through it (`destination-out`, fading 1.09 R → 1.40 R)
so the eyeball can rove beneath the flesh without a hard edge.

Layer resolution is capped at 2× DPR and auto-trimmed above ~3.2 megapixels to bound memory.

### Text on an arc

Each ring generates tokens until they overflow its circumference, then every character advance is
scaled by `circumference / total` so the run closes exactly — no seam. Characters are placed
individually with `textAlign:center` / `textBaseline:middle`, rotated tangentially, with ~42% of
rings flipped so the text reads the other way round.

Rings whose circumference is under ~11 character widths switch to single glyphs instead of words,
which is what keeps the innermost pupil rings legible.

Ring spacing is `fontSize × 0.94` — slightly overlapping, which is what produces the density of the
source plate.

### Colour

One 27-stop HSL table spans the whole radius: pupil → iris → limbal ring → sclera → flesh.
Sampled colour is then broken up by summed-sine angular pseudo-noise (four incommensurate
frequencies) into organic sectors, plus a fine striation term and a coarse sector term. Amplitude
peaks mid-iris and falls to nothing at the pupil and limbus, which is what keeps those zones
reading as solid.

Per token: ±jitter on H/S/L, then

- 4.4% chance of a vivid **accent** from a 9-colour palette (cyan, magenta, violet, lime, gold, red, azure)
- 12% chance of a lightness lift — the word that catches the light
- 11% chance of a drop — the word that recedes
- 20% of tokens colour per-character rather than per-word

Seven font stacks are weighted-sampled per ring (Arial Narrow bold dominant, Impact, Helvetica
heavy, Futura, Georgia, monospace), which is what stops the plate reading as one typeface.

### Anatomy beneath the text

Baked into `irisBase`: a wash of 96 angular sectors × 46 radial bands (built at ⅓ scale and
upsampled for free smoothing); ~1,500 radial trabecular fibres as curved tapered strokes; ~80
crypts of Fuchs as blurred dark ellipses; a ragged collarette at 0.335 R modulated by noise; a
limbal ring darkening to near-black at the rim.

Elsewhere: conjunctival vessels as branching strokes on the sclera; a lash fringe along the top and
bottom margins; lid shading; radial "spoke" words in the flesh that break the concentric spell.

### The gaze

The eye is at `(W/2, H×0.475)`, iris radius `R = min(W×0.315, H×0.395)`.

```
shift  = R × 0.195 × gaze          translate the iris toward the target
squash = 1 − 0.265 × gaze          then compress ALONG the axis of displacement
```

The squash is the whole trick. Rotating into the gaze axis, scaling X, and rotating back
foreshortens the iris exactly as a sphere would when it turns — without it, the iris reads as a
disc sliding across a backdrop. The eyeball itself rolls a third as far, so a cream sclera crescent
opens on the opposite side.

Motion is exponentially eased with **micro-saccades** layered on (±0.03 every 55–330 ms), because a
perfectly smooth eye reads as dead. The pupil has **hippus** — three summed sines of autonomic
drift — constricts as the pointer nears, and flares on click. Idle for ~3 s and it begins wandering.

### The lexicon

487 terms, banded by depth. The conceptual spine is that the eye speaks differently at different
strata:

| Band | Terms | Register | Examples |
|---|---|---|---|
| `PUPIL` | 65 | negation, void | AIN SOPH, KENOMA, TOHU, DOCTA IGNORANTIA |
| `INNER` | 71 | mind, breath | NOUS, PNEUMA, BARBELO, EPINOIA, ANAMNESIS |
| `MID` | 69 | fire, transmutation | AZOTH, SOLVE ET COAGULA, CITRINITAS, TAJALLI |
| `OUTER` | 75 | law, structure | YALDABAOTH, HEIMARMENE, QLIPHOTH, HEBDOMAD |
| `LIMBUS` | 50 | threshold | PAROKHET, BARDO, JANUA COELI, METAXY |
| `SCLERA` | 39 | light, disclosure | ALETHEIA, APOKALYPSIS, DIAPHANE |
| `FIELD` | 118 | world, appearance, seeing | PAREIDOLIA, CAMERA OBSCURA, MUSCAE VOLITANTES |

Woven through at ~17% frequency are garbled letter-clusters and Greek glyphs — the illegible
connective tissue of the source plate.

---

## Variants

### `i-see-you.html` — the English plate

Same renderer, same anatomy, same performance work; a different tongue. Where `oculus.html` speaks
in Latin, Greek, Hebrew and Sanskrit, this one speaks in plain English about being looked at.

488 terms across the same 7 bands, drawn from 195 unique words — the repetition across bands is
deliberate, and is what holds the density at the level of the source plate. The bands read outward
as: void → soul → intensity → the verbs of looking → threshold → light → direct address.

| Band | Terms | Register | Examples |
|---|---|---|---|
| `PUPIL` | 65 | void, blindness | VOID, ABYSS, HOLLOW, SIGHT UNSEEN, WHAT LIES WITHIN |
| `INNER` | 72 | soul, self | PSYCHE, CONSCIOUSNESS, VULNERABILITY, UNDERSTAND ME |
| `MID` | 69 | intensity | PIERCING, MESMERIZING, TRANSFIXING, UNBROKEN GAZE |
| `OUTER` | 75 | the act of looking | BEHOLD, SCAN, PERCEIVE, POINT OF VIEW, FIELD OF VIEW |
| `LIMBUS` | 50 | threshold | PORTAL, THE SPACE BETWEEN EYES, WINDOW TO THE SOUL |
| `SCLERA` | 39 | disclosure | RADIANCE, LUCIDITY, I SEE YOU, WHAT DO YOU SEE? |
| `FIELD` | 118 | direct address | LOOK AT ME, DON'T LOOK AWAY, EYES NEVER LIE |

Two departures from the original worth knowing about:

- **No borrowed alphabet.** The original wove in random letter-clusters, digits and Greek glyphs as
  illegible connective tissue. Here that tissue is cut from the lexicon itself — `glyphNoise()`
  returns fragments of the band's own words, and single-glyph rings draw a letter from a real word.
  Every mark on the plate traces back to a word in the list.
- **`FLIP_RATE` matters more than it used to.** 42% of rings are inscribed against the direction of
  reading. Reversed Latin still looks cryptic; reversed English reads as plainly backwards. Lower it
  toward 0.15 for a legible plate, raise it toward 0.5 for an encrypted one.

## Customising

Everything worth changing sits near the top of the script, in labelled sections:

| Want to change | Where |
|---|---|
| Vocabulary | `const LEX = {…}` — add to any band |
| Reversed-text share | `FLIP_RATE` (`i-see-you.html`) |
| Palette | `const STOPS = […]` — 27 `[t, h, s, l]` rows spanning pupil → flesh |
| Accent colours | `const ACCENTS = […]` |
| Typefaces | `const FACES = […]` and `FACE_W` weights |
| Ring density / sizes | `fontSizeFor(t)` |
| Rotation rates | the `ringLayers` loop in `construct()` |
| Eye size / position | `layout()` — `EX`, `EY`, `R`, `SR` |
| Gaze throw | `shift` and `squash` in `render()` |
| Camera mapping | `window.OCULUS.face()` |
| Vignette, catchlights, cornea | `mkGradients()` — baked once per resize, not per frame |
| Grain size / tile | `mkGrain()`, `GRAIN_NOISE`, `GRAIN_TILE` |
| Max plate resolution | `PX_BUDGET` in `layout()` |

The seed is `SEED`; the same seed reproduces the same plate exactly.

### Pinning a plate

Both files accept a `?seed=` parameter, so a plate worth keeping can be bookmarked or handed to
someone else rather than lost to the next rebuild:

```
i-see-you.html?seed=4242
```

With no parameter the seed is random per load, as before. Either way the live seed is written back
into the address bar via `replaceState` and logged to the console, so **Transmute** never loses a
plate — the URL always describes what is on screen. `file://` forbids `replaceState`, so the console
line is the fallback there.

One limit worth knowing: the same seed does **not** produce the same arrangement across the two
files. The generative stream diverges as soon as token generation starts, because `oculus.html` and
`i-see-you.html` draw a different number of values from the PRNG per token. Within one file the seed
is exact; across the two it is not.

### Kiosk mode

For an unattended plate — wallpaper, screensaver, a display in a room — `?kiosk=1` strips the panel,
the dock button, the title and the motto, hides the cursor, and starts the camera without anyone
pressing **Face**:

```
i-see-you.html?kiosk=1
i-see-you.html?kiosk=1&face=0        chrome gone, but the eye wanders on its own
i-see-you.html?kiosk=1&blink=0       never blink
```

`&blink=0` drives the panel's own **Blink** toggle, so the flag and the button stay in agreement.
Worth using for anything ambient: a blink every 3–11 seconds reads as life in a window you are
looking at, and as distracting movement in the corner of your eye when you are working.

Without the parameter the block does nothing whatsoever, so a bookmarked kiosk URL and an ordinary
one can live side by side.

Separately — and regardless of the parameter — the camera module exposes `window.OCULUS_HOST`:
`start()`, `stop()`, `isRunning()`. **Face** now goes through it, and so can an embedding host. That
is what lets the macOS app hand the camera back the moment the piece is covered, rather than holding
it open all day.

---

## Performance

- Build: ~1–2 s on a real display, chunked so nothing blocks.
- Runtime: every per-frame operation is now a `drawImage` of something pre-baked. Comfortably 60 fps.
- Memory: ~50 MB of canvas at 1080p, plus a half-resolution vignette plate and a 660 px grain tile,
  auto-trimmed on larger displays.

If you profile it in a background or hidden tab, note that `requestAnimationFrame` is throttled to
near-zero there — the build will appear to take 20+ s. That is the tab, not the code.

### The rule that matters

**Never fill the whole plate per frame — blit it.** Canvas 2D falls off the GPU path for
full-surface gradient fills, pattern fills, and `ctx.filter` blurs, and once it does the cost scales
with every device pixel. On a 16" retina display that is 7.7 megapixels, and the difference is
between 60 fps and 16.

Measured per frame at 7.7 megapixels, before and after:

| Pass | Was | Now | How |
|---|---|---|---|
| Grain | 1.2 ms **or 36.4 ms** | 0.7 ms | pattern fill → pre-baked tile, blitted ~12× |
| Vignette | 20.9 ms | 0.6 ms | radial gradient fill → baked half-res plate |
| Bloom | 2.1 ms | 0.8 ms | `blur(6px)` at plate scale → `blur(1.6px)` at 0.26 scale |
| All 7 rotated ring layers | 1.3 ms | 1.3 ms | already a blit; never the problem |
| Field layer | 0.7 ms | 0.7 ms | already a blit |
| **Total** | **~61 ms → 16 fps** | **~4 ms** | |

The grain figure was **bimodal**: fast while the canvas stayed GPU-resident, ~30× slower the moment
memory pressure evicted it. That is what made the slowness feel intermittent and unattributable. A
pre-baked tile is uniformly fast, which matters more than the best case being marginally quicker.

Two details worth preserving if you touch this code:

- `GRAIN_TILE` must stay an exact multiple of `GRAIN_NOISE` (220), or the tile edges stop lining up
  with their neighbours and the plate picks up a faint seam grid.
- The grain tile is baked at device resolution so one noise cell remains one CSS pixel. Bake it at
  plate resolution instead and the grain gets finer as the display gets denser.

The ring compositing is *not* the expensive part, despite being the visually impressive part — seven
rotated `drawImage` calls covering ~23 megapixels of texture cost 1.3 ms total. Optimising it would
be wasted effort.

---

## Troubleshooting

| Symptom | Cause |
|---|---|
| Camera button does nothing, status says "not a secure context" | Opened via `file://`. Serve over localhost. |
| "permission denied" | Browser prompt declined, or macOS Camera privacy toggle is off for the browser. |
| "camera busy" | Zoom, Photo Booth, or similar is holding the device. |
| "could not load MediaPipe" | Offline, or the package version moved. Edit `MP_VERSION`. |
| Eye moves opposite to you | Toggle **Mirror**. |
| Gaze too twitchy | Lower **Reach**. |
| Build feels slow | Check the tab is visible and focused. |
| Frame rate below 60 | Lower `PX_BUDGET` in `layout()` to shrink the plate. Check first that no per-frame full-canvas fill has crept back in — see [Performance](#performance). |
| Blank canvas after load | Resize the window once — forces a rebuild at the correct size. |

---

## Notes

End-to-end face tracking is confirmed working against a live camera, in a browser over https and
in the macOS app.

Still unconfirmed: the **mirror handedness** default. `Mirror` ships on, which should be correct for
a user-facing webcam, but this has not been checked against a deliberate left/right movement. Use
**Feed** on first run — if the eye moves opposite to you, toggle **Mirror**.

> VISITA INTERIORA TERRAE · RECTIFICANDO INVENIES · OCCVLTVM LAPIDEM
