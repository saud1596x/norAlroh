# Noor TestFlight signing on saud

The user explicitly approved five new Noor profiles using the existing
`masar_distribution` certificate. No new key or certificate was created, and
existing Masar profiles were not modified. Apple team: `4SY7K26FCX`.

| Codemagic reference / Apple name | Apple profile ID | Bundle suffix |
| --- | --- | --- |
| noor-saud-appstore-20261015 | RP53952WA6 | com.saud1596x.nooralruh |
| noor-saud-widgets-20261015 | PU7SUK9UW3 | .widgets |
| noor-saud-focus-monitor-20261015 | 2NY85PC5YV | .focus-monitor |
| noor-saud-focus-shield-20261015 | JF78359DZW | .focus-shield |
| noor-saud-focus-action-20261015 | K77UL2S87X | .focus-action |

All five were created in Apple Developer, expire October 10, 2027, and were
imported into Codemagic team `6aca6f8ea472ecaef9ac5f5e`. The UI explicitly
reports for each: `Uploaded certificate matching the profile is masar_distribution`.
Local evidence: `outputs/noor-saud-signing-matches.json` and
`outputs/noor-saud-signing-matched.png` (workspace output directory).

`ios-testflight-saud` inherits every script, artifact verification step and
TestFlight-only publishing setting from `ios-testflight`. It selects the
existing `masar-apple` integration and the five new profiles. Its 15-minute
limit is a budget bound, not evidence that a build will finish in that time.
It has no automatic trigger. Check the budget before every manual dispatch;
the workflow cap does not enforce the cumulative USD10 account allowance.

## Protected build configuration

The user subsequently explicitly approved adding the existing Noor Firebase
client plist to `noor_release`, restricted to the `norAlroh` application.
The group was created with only that application selected. The downloaded
plist passed the existing project, app and bundle validation again, and was
saved as the secret variable `NOOR_FIREBASE_IOS_PLIST_BASE64`. The resulting
UI displays the variable name with a secured value. No value was printed,
no new key was created, and no Firebase project/provider settings changed.
Evidence: `outputs/noor-firebase-protected-saved.png`. Runtime account sign-in
is still unverified; storing build configuration does not establish it.

## Remaining blockers

- Current TestFlight publication evidence still describes an older native
  run. The source-hash gate remains unchanged and must pass with actual
  matching evidence before dispatch. Narrow Debug preservation tests are
  not full Release or microphone/playback acceptance.
- Actual Simulator audio playback remains unresolved even in the separate
  UIKit host. No real-device microphone or general recognition accuracy is
  established, and no new TestFlight build has been uploaded.

Imported older Noor profiles that lack a matching certificate remain unused.
Do not delete them or use them in this workflow.
