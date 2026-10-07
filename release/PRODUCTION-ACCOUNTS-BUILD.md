# Account-enabled distribution build

The TestFlight workflow now generates `ios/project-accounts.yml`. It must not silently distribute the local-only target when account configuration is unavailable. This preparation is not evidence of signed archive success, real sign-in, device acceptance, or publication.

## Protected build configuration

Download the existing configuration for the registered iOS app in project `noor-alruh`. Store its base64 encoding in the protected Codemagic `noor_release` group as `NOOR_FIREBASE_IOS_PLIST_BASE64`. Never commit the plist or its encoding. `install-production-firebase.py` verifies the project, app, bundle identifiers using the existing validator, preserves existing deep links, and saves a rollback of Info.plist.

## Distribution profiles

Upload matching App Store profiles in Codemagic's code signing identities using these reference names. The main profile must include Sign in with Apple, Family Controls and the shared App Group. Focus profiles require Apple's distribution entitlement approval. Compilation does not establish approval.

| Reference | Bundle identifier |
| --- | --- |
| `noor-alruh-appstore` | `com.saud1596x.nooralruh` |
| `noor-alruh-widgets-appstore` | `com.saud1596x.nooralruh.widgets` |
| `noor-alruh-focus-monitor-appstore` | `com.saud1596x.nooralruh.focus-monitor` |
| `noor-alruh-focus-shield-appstore` | `com.saud1596x.nooralruh.focus-shield` |
| `noor-alruh-focus-action-appstore` | `com.saud1596x.nooralruh.focus-action` |

All use team `4SY7K26FCX` and App Group `group.com.saud1596x.nooralruh`. The distribution certificate reference remains `noor-alruh-distribution`. These are required names, not a claim that all corresponding profiles already exist in the cloud service.

## Payload and privacy checks

The workflow queries the latest TestFlight build for app `6819365625`, rejects missing/non-numeric results and uses the next number for every target. No new number has been assigned until the signed workflow actually runs.

`verify-release-ipa.py` checks the production bundle, real Firebase identity, four extension registrations, matching app/extension versions and presence of embedded profiles. Xcode performs signing; the Python payload gate does not independently authenticate a provisioning profile or prove device behavior. The existing 604-font hash gate remains enabled.

`prepare-publishing.py --accounts` generates the separate version-2 `firebase-opt-in` policy. It describes the currently implemented optional login and manual memorization backup, not automatic sync. Ordinary local builds retain the version-1 local policy. The offline viewer accepts only these known schema/mode pairs. The account policy and matching public support pages must be reviewed and actually deployed before release. Generating files does not deploy them.

## Evidence from this change

Eight Python tests passed, including rejection of missing extensions, stale extension versions, foreign Firebase configuration and a stale local-only policy in an account payload. Fixtures are synthetic and are never installed in the application. Temporary generation/check of the account policy passed, with the approved support address. YAML structure checks passed. Native policy decoding tests were added and await the next macOS CI run.

## External account setup

The user explicitly canceled Google sign-in on 2026-10-07. The UI, Google SDK dependencies and Google OAuth configuration requirement have been removed. Firebase still uses its vendor-standard filename `GoogleService-Info.plist`; this filename does not imply Google sign-in. Public support remains `noralrohsupport@gmail.com`. There is no need to grant the support Gmail account project access solely for Google branding.

After the user's explicit region approval, production Firestore `(default)` was created in permanent region `me-central2`, Standard, on Spark without a paid upgrade. After the separate action-time confirmation, owner-only rules matching `backend/firestore.rules` were published on 2026-10-07 at 02:06UTC. The console showed a new active version and no unpublished changes. Console simulations confirmed owner GET allowed, foreign UID and unauthenticated GET denied. This is rule deployment, not a real Apple login or two-device synchronization test.

Apple provider/token-revocation configuration and production credentials remain incomplete. On 2026-10-07 the user signed into Apple Developer and separately approved Apple sign-in and the Noor-only shared App Group. Main App ID `com.saud1596x.nooralruh` now has saved, server-verified Sign in with Apple (primary App ID) and App Groups (one assignment). `group.com.saud1596x.nooralruh` was registered as Noor Alruh Shared. Widget App ID `com.saud1596x.nooralruh.widgets` was registered and its one App Group assignment was saved and verified. Existing affected provisioning profiles must be regenerated after these capability changes. Family Controls distribution approval has not been requested or granted. Full automatic synchronization, device conflict resolution and deletion tombstones remain implementation tasks. Unsigned Release compilation of the Apple-only account target and four extensions passed in CI148; real sign-in and signed distribution are not thereby tested.

CI148 failed one of 79 unit tests (one additional test skipped): Foundation/Compression decoding accepted appended bytes despite checking remaining input. UI tests therefore did not run. The decoder now uses bounded raw-DEFLATE zlib inflation with exact unused-input checks, preserving the existing Foundation archive format; regression coverage retains legacy Arabic roundtrip, output bounds, truncation and adds single-byte tails and concatenated streams. Local Python configuration/payload tests: 8 passed. CI150 on `245de1b1de6fb87a7484d425003940d9cc0b5df5` was observed in progress; no native success is claimed until completion. This is not a signed TestFlight build.
