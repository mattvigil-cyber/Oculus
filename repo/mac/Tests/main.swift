import Foundation

// Exercises AppController.decide — the screensaver rise/dismiss state machine.
// Build with ./run-tests.sh; it links the real source, not a copy.

var failures = 0

func check(_ name: String, _ got: AppController.Pulse, _ want: AppController.Pulse) {
    if got == want {
        print("  ok    \(name)")
    } else {
        failures += 1
        print("  FAIL  \(name) — got .\(got), wanted .\(want)")
    }
}

let riseAfter: TimeInterval = 300  // 5 minutes

print("idle-triggered rise")
check("holds while the machine is in use",
      AppController.decide(showing: false, awaiting: false, idle: 12, held: 0,
                           risesWhenIdle: true, riseAfter: riseAfter), .hold)
check("holds one second short of the threshold",
      AppController.decide(showing: false, awaiting: false, idle: 299, held: 0,
                           risesWhenIdle: true, riseAfter: riseAfter), .hold)
check("rises at the threshold",
      AppController.decide(showing: false, awaiting: false, idle: 300, held: 0,
                           risesWhenIdle: true, riseAfter: riseAfter), .rise)
check("never rises in a mode that does not rise",
      AppController.decide(showing: false, awaiting: false, idle: 9999, held: 0,
                           risesWhenIdle: false, riseAfter: riseAfter), .hold)

print("\nstarted by hand — the click that started it must not dismiss it")
check("holds immediately after the click",
      AppController.decide(showing: true, awaiting: true, idle: 0, held: 0.2,
                           risesWhenIdle: true, riseAfter: riseAfter), .hold)
check("still holds while a hand is still on the mouse",
      AppController.decide(showing: true, awaiting: true, idle: 1.5, held: 1.6,
                           risesWhenIdle: true, riseAfter: riseAfter), .hold)
check("arms once input has settled",
      AppController.decide(showing: true, awaiting: true, idle: 2.0, held: 2.1,
                           risesWhenIdle: true, riseAfter: riseAfter), .arm)

print("\nthe escape hatch — constant input never lets idle settle")
check("arms anyway at the ceiling",
      AppController.decide(showing: true, awaiting: true, idle: 0.1, held: 5.0,
                           risesWhenIdle: true, riseAfter: riseAfter), .arm)
check("holds just below the ceiling",
      AppController.decide(showing: true, awaiting: true, idle: 0.1, held: 4.9,
                           risesWhenIdle: true, riseAfter: riseAfter), .hold)

print("\narmed — any input sinks it")
check("sinks on fresh input",
      AppController.decide(showing: true, awaiting: false, idle: 0.1, held: 30,
                           risesWhenIdle: true, riseAfter: riseAfter), .sink)
check("stays up while nobody touches anything",
      AppController.decide(showing: true, awaiting: false, idle: 60, held: 90,
                           risesWhenIdle: true, riseAfter: riseAfter), .hold)
check("sinks even in a mode that never raises it by itself",
      AppController.decide(showing: true, awaiting: false, idle: 0.1, held: 30,
                           risesWhenIdle: false, riseAfter: riseAfter), .sink)

print("\nthe sink window follows the gap between pulses")
check("misses a tap older than the default window",
      AppController.decide(showing: true, awaiting: false, idle: 1.1, held: 30,
                           risesWhenIdle: true, riseAfter: riseAfter), .hold)
check("catches that tap when the pulse ran late",
      AppController.decide(showing: true, awaiting: false, idle: 1.1, held: 30,
                           risesWhenIdle: true, riseAfter: riseAfter, sinkWithin: 1.35), .sink)
check("a wider window never dismisses a hand-started one early",
      AppController.decide(showing: true, awaiting: true, idle: 0.1, held: 1.0,
                           risesWhenIdle: true, riseAfter: riseAfter, sinkWithin: 5.0), .hold)

print("")
if failures == 0 {
    print("all checks passed")
    exit(0)
} else {
    print("\(failures) failed")
    exit(1)
}
