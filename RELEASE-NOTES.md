# Oculus 1.1

An eye assembled from language. It lives behind your desktop icons, follows your face, and comes
forward as a screensaver when you walk away.

## Requirements

- Apple Silicon Mac. The app does not run on Intel.
- macOS 13 or later.
- A camera, if you want it to follow you. It works without one.

## Install

1. Download `Oculus-1.1.dmg` below and open it.
2. Drag **Oculus** onto the **Applications** shortcut.
3. The app is not notarized, so macOS blocks the first launch. Run this once in Terminal:

   ```
   xattr -d com.apple.quarantine /Applications/Oculus.app
   ```

   Or double-click the app, let macOS block it, then open System Settings, Privacy & Security, and
   click **Open Anyway**.
4. Allow the camera when asked. Frames are processed on your Mac and never leave it.

Everything lives under the eye in the menu bar.

## New in 1.1

- The screensaver now drops for input from Screen Sharing and other remote sessions.
- The app goes dormant when the Mac sleeps, the display sleeps, or the screen locks. The camera
  closes and the screensaver stays down on wake.
- Temperament: the pupil answers room light, the eye dozes when nobody is there, and short lines
  lift out of the rings.
- Fine text appears when you lean in.
- Colour and vocabulary shift across the day.
- Custom lexicons, a paired-eye mode for two Macs, plate of the day, and poster export.
- The screensaver fades in with the eyelid lifting.

Details are in TEMPERAMENT.md.
