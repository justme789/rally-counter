# Rally Counter

An iPhone app that listens while you play Egyptian racket and counts each time the ball hits a racket. It also tracks rallies: a pause in hits ends a rally.

## Build (no Mac needed)
1. Push this folder to a GitHub repo. The **Build IPA** workflow runs on GitHub's macOS runner. It uses XcodeGen to generate the Xcode project, builds the app unsigned, and packages it as an `.ipa`.
2. Open the run under **Actions** and download the `RallyCounter-ipa` artifact. Unzip it to get `RallyCounter.ipa`.

## Sideload
Use **Sideloadly** (Windows) or **AltStore**. Both sign the app with your Apple ID.
- If you use a free Apple ID, the app expires after 7 days and you have to re-sideload it.
- On iOS 16 and later, turn on Settings → Privacy & Security → **Developer Mode**.
- After installing, trust the profile under Settings → General → VPN & Device Management.

## Using it
- Put the phone near where you're playing, tap **Start listening**, and play.
- The meter shows the live sound level. Set **Sensitivity** so that hits push the bar past the white line and normal background noise stays below it.
- Use **−/+** to fix a miscount by hand.
- The app keeps listening with the screen locked (background audio mode).

## How detection works
See `HitDetector.swift`. The signal goes through a 1.5 kHz high-pass filter. It is then split into short ~2.7 ms chunks and the energy of each chunk is measured. A chunk counts as a hit when all of these hold:
- its energy is well above an adaptive noise floor and above an absolute minimum level,
- it jumps by at least 9 dB compared with about 10 ms earlier,
- it falls outside a 150 ms lockout after the previous hit.
