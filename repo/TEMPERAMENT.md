# Temperament

Thirteen behaviours layered on both pieces. They live in one block at the top of each HTML file,
between `<!-- TEMPERAMENT:BEGIN -->` and `<!-- TEMPERAMENT:END -->`. The engine calls the block once,
before its first build. Delete the block and both pieces run exactly as they did before.

The block has one source: `src/temperament.js`. Edit that file, then run
`python3 tools/sync-temperament.py` to copy it into both pieces. Add `--check` to see whether the
pieces have drifted from the source without changing anything.

## Switches

Add any of these to the URL. `1` turns a behaviour on, `0` turns it off.

| Parameter | Default | What it does |
|---|---|---|
| `light` | on | Pupil answers room brightness, read from the camera frame. Turn on a lamp and it tightens. |
| `sleep` | on | Camera running and no face for `sleepafter` seconds (600): lids droop, rings slow. 45 seconds more and it sleeps. A face wakes it with a pupil flare. |
| `duo` | on | Two faces in frame: it darts between them for about four seconds, then settles on the closer one. |
| `contest` | on in a browser, off in the Mac app | Staring contest. Hold its gaze without blinking for `contestsecs` (30). It looks away, concedes, then transmutes. Loads a second model. |
| `speak` | on | One word lifts and glows, then the next, each on its own ring, until the line stands across the iris. |
| `micro` | on | Fine text appears when you lean in, or hover the iris with no camera. |
| `circadian` | on | Colour grade and vocabulary follow the hour. `hour=23` previews a time. |
| `lex=name` | none | Loads `lexicons/name.json` over the built-in vocabulary. |
| `eye=left` or `eye=right` | none | One half of a pair across two machines. Each eye turns inward. |
| `seed=today` | none | One plate per calendar day, identical on every machine. |
| `poster=24x36` | none | Print render in inches. `dpi=150` by default, up to 300. |

Press `p` in a browser to open the current plate as a 24 by 36 poster. Use the Save PNG button there.

## What it says

| Moment | English | Latin |
|---|---|---|
| You return after 6 seconds away | I SEE YOU | VIDEO TE |
| You turn your head, or leave the frame | DON'T LOOK AWAY | NOLI ABIRE |
| It wakes | THERE YOU ARE | VIGILO |
| It dozes | REST NOW | QVIESCO |
| You win the contest | YOU WIN | VICISTI |
| You blink after 8 seconds | YOU BLINKED | NICTAVISTI |
| You lean in close | CLOSER | PROPIVS |

Every couple of minutes it also speaks one multi-word phrase from the lexicon.

## Custom lexicons

Put a JSON file in `lexicons/`. Seven bands, any subset. Missing bands keep the built-in words.

```json
{
  "PUPIL": ["LOW TIDE", "UNDERTOW"],
  "FIELD": ["WATCH THE HORIZON"],
  "SPEAK": { "see": "I SEE THE SHORE" },
  "MICRO": "ONE LONG SENTENCE FOR THE FINE TEXT"
}
```

`SPEAK` and `MICRO` are optional. Plain text works too: `[PUPIL]` style headers, then terms one per
line or comma-separated. In a browser, drag a file onto the page to try it.

`build.sh` copies the folder into the app. Each file appears under **Lexicon** in the menu.

Vocabularies you want on your own Mac and out of the repository go in `lexicons-private/`, which git
ignores. They reach the app only when you build with `OCULUS_PRIVATE_LEXICONS=1 ./build.sh`.

## Circadian

| Hours | Grade | Vocabulary |
|---|---|---|
| 21 to 5 | darker, cooler | 30% of words borrowed from PUPIL |
| 5 to 9 | pale, slightly warm | 28% borrowed from SCLERA |
| 9 to 17 | none | as written |
| 17 to 21 | warm | 20% borrowed from LIMBUS |

The plate rebuilds when the vocabulary changes, four times a day. The seed still fixes the layout
within a period. Across periods the same seed gives a different mix of words.

## In the Mac app

New menu items: **Lexicon**, **Eye**, **Temperament**, **Staring contest**, **Plate of the day**.
Each one reloads the piece.

Two behaviours come from the app itself:

- **Glance.** When another app comes forward, the eye flicks toward the pointer. macOS gives a
  third-party app no view of notification banners, so app activation stands in for them.
- **Eyelid rise.** The screensaver fades in over the desktop while the lid lifts.

## Console

`window.OCULUS_T` exposes `say("TEXT")`, `sleep()`, `wake()`, `glance(x, y, ms)`, `open(ms)`,
`set("speak", false)` and `loadLex("name")`.

## Tested, and not

Tested in headless Chromium against both pieces: speech, fine text, sleep and wake, glance, lid
rise, paired-eye bias, two-face selection, light sampling, landmark model loading, the contest win
path with stubbed blink scores, lexicon loading and fallback, circadian grade, daily seed, and a
2400 by 3600 poster export.

Not tested: anything with a real face in front of a real camera, and the Swift changes. No compiler
was available where this was written.
