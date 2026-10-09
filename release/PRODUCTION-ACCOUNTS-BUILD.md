# Account-enabled distribution build

The TestFlight workflow now generates `ios/project-accounts.yml`. It must not silently distribute the local-only target when account configuration is unavailable. This preparation is not evidence of signed archive success, real sign-in, device acceptance, or publication.

## Protected build configuration

Download the existing configuration for the registered iOS app in project `noor-alruh`. Store its base64 encoding in the protected Codemagic `noor_release` group as `NOOR_FIREBASE_IOS_PLIST_BASE64`. Never commit the plist or its encoding. `install-production-firebase.py` verifies the project, app, bundle identifiers using the existing validator, preserves existing deep links, and saves a rollback of Info.plist.

## Distribution profiles

Upload matching App Store profiles in Codemagic's code signing identities using these reference names. The main profile must include Sign in with Apple, Family Controls and the shared App Group. Focus profiles require Apple's distribution entitlement approval. Compilation does not establish approval.

| Reference | Bundle identifier |
| --- | --- |
| `noor-alruh-appstore-accounts` | `com.saud1596x.nooralruh` |
| `noor-alruh-widgets-appstore-verified` | `com.saud1596x.nooralruh.widgets` |
| `noor-alruh-focus-monitor-appstore` | `com.saud1596x.nooralruh.focus-monitor` |
| `noor-alruh-focus-shield-appstore` | `com.saud1596x.nooralruh.focus-shield` |
| `noor-alruh-focus-action-appstore` | `com.saud1596x.nooralruh.focus-action` |

All use team `4SY7K26FCX` and App Group `group.com.saud1596x.nooralruh`. The distribution certificate reference remains `noor-alruh-distribution`. These are required names, not a claim that all corresponding profiles already exist in the cloud service.

## Payload and privacy checks

The workflow queries the latest TestFlight build for app `6819365625`, rejects missing/non-numeric results and uses the next number for every target. No new number has been assigned until the signed workflow actually runs.

`verify-release-ipa.py` checks the production bundle, real Firebase identity, four extension registrations, matching app/extension versions and presence of embedded profiles. Xcode performs signing; the Python payload gate does not independently authenticate a provisioning profile or prove device behavior. The existing 604-font hash gate remains enabled.

`prepare-publishing.py --accounts` generates the separate version-2 `firebase-opt-in` policy. It describes optional Apple login and opt-in automatic reading/memorization synchronization, including durable bookmark and excluded-note deletion records. Source implementation is not proof of production or two-device acceptance. Ordinary local builds retain the version-1 local policy. The offline viewer accepts only these known schema/mode pairs. The account policy and matching public support pages must be reviewed and actually deployed before release. Generating files does not deploy them.

## Evidence from this change

Eight Python tests passed, including rejection of missing extensions, stale extension versions, foreign Firebase configuration and a stale local-only policy in an account payload. Fixtures are synthetic and are never installed in the application. Temporary generation/check of the account policy passed, with the approved support address. YAML structure checks passed. Native policy decoding tests were added and await the next macOS CI run.

## External account setup (chronological checkpoints; latest follow-up below)

The user explicitly canceled Google sign-in on 2026-10-07. The UI, Google SDK dependencies and Google OAuth configuration requirement have been removed. Firebase still uses its vendor-standard filename `GoogleService-Info.plist`; this filename does not imply Google sign-in. Public support remains `noralrohsupport@gmail.com`. There is no need to grant the support Gmail account project access solely for Google branding.

After the user's explicit region approval, production Firestore `(default)` was created in permanent region `me-central2`, Standard, on Spark without a paid upgrade. After the separate action-time confirmation, owner-only rules matching `backend/firestore.rules` were published on 2026-10-07 at 02:06UTC. The console showed a new active version and no unpublished changes. Console simulations confirmed owner GET allowed, foreign UID and unauthenticated GET denied. This is rule deployment, not a real Apple login or two-device synchronization test.

Apple provider/token-revocation configuration and production credentials remain incomplete. On 2026-10-07 the user signed into Apple Developer and separately approved Apple sign-in and the Noor-only shared App Group. Main App ID `com.saud1596x.nooralruh` now has saved, server-verified Sign in with Apple (primary App ID) and App Groups (one assignment). `group.com.saud1596x.nooralruh` was registered as Noor Alruh Shared. Widget App ID `com.saud1596x.nooralruh.widgets` was registered and its one App Group assignment was saved and verified. Existing affected provisioning profiles must be regenerated after these capability changes. Family Controls distribution approval has not been requested or granted. At that historical checkpoint, automatic synchronization, device conflict resolution and deletion tombstones remained implementation tasks. Their October 7 source implementation and pending/native test evidence are tracked in EXECUTION-CHECKPOINT-20261007.md; this older paragraph does not supersede it. Unsigned Release compilation of the Apple-only account target and four extensions passed in CI148; real sign-in and signed distribution are not thereby tested.

CI148 failed one of 79 unit tests (one additional test skipped): Foundation/Compression decoding accepted appended bytes despite checking remaining input. UI tests therefore did not run. The decoder now uses bounded raw-DEFLATE zlib inflation with exact unused-input checks, preserving the existing Foundation archive format; regression coverage retains legacy Arabic roundtrip, output bounds, truncation and adds single-byte tails and concatenated streams. Local Python configuration/payload tests: 8 passed. CI150 on `245de1b1de6fb87a7484d425003940d9cc0b5df5` was observed in progress; no native success is claimed until completion. This is not a signed TestFlight build.

The three Focus App IDs (`com.saud1596x.nooralruh.focus-monitor`, `.focus-shield`, `.focus-action`) were subsequently registered; each saved App Group assignment was verified by reopening its configuration (Save disabled, Enabled App Groups 1). No Family Controls capability was enabled. CI150's `focus-build` passed in 3m58s, including the updated decoder and Apple-only account target with all four extensions. Native unit/UI execution remained in progress at that observation. These identifiers and unsigned compilation do not establish signed entitlement approval or device behavior.

Live Apple portal follow-up: Profiles lists only the old Noor Alruh App Store profile (Invalid) and an unrelated app profile; no Noor extension profiles are present. Keys shows Getting Started with Keys (no existing keys). The new-key form was opened read-only, with all services unchecked; no key was created or transmitted. Creating a Noor-only Sign in with Apple key and transmitting it to Firebase requires a separate explicit security-scope confirmation and protected handling, not public source or chat. Family Controls activation/distribution request likewise remains outside the Apple-sign-in/App-Group confirmation already used.

### Follow-up after the user's specific confirmation, 2026-10-07

The user approved the specifically described Family Controls activation/distribution request and creation of a Noor-only Apple sign-in key for Firebase. `Noor Alruh Apple Authentication` was created with only Sign in with Apple, associated with the single primary App ID `com.saud1596x.nooralruh`. The portal shows Download Your Key. The private key has not been downloaded, entered into Firebase, committed or exposed in chat. The existing Family Controls contact-request tab already shows Thank you for your submission; it does not expose the requested bundle IDs or an approval decision. No duplicate request was submitted. Main and all three Focus App ID Family Controls Development and Distribution checkboxes were saved and verified checked on reopening (Save disabled). App and Website Usage remains unchecked (not requested or needed). This portal configuration is not a signed-profile or device acceptance test. Firebase's Apple-provider form was opened, Enable turned on in the unsaved draft and OAuth fields expanded; no new credential was entered or submitted. Credential entry requires secure user handoff. Signing preparation continues independently.

The existing Noor Alruh App Store profile was regenerated with its already selected certificate `C79962XMHC`; four extension App Store profiles were created using that same certificate. All five were downloaded through the normal Apple portal. Local CMS signature-integrity checks and payload inspection confirmed matching team/application identifiers, exactly the Noor App Group, App Store distribution (`get-task-allow` false, `beta-reports-active` true, no provisioned device list), unexpired profiles, one identical distribution certificate, Apple sign-in on the main profile and Family Controls on main/three Focus profiles. This did not independently verify the Apple certificate trust chain or a signed app archive. The main profile was saved in Codemagic under `noor-alruh-appstore-accounts`; the four extensions were successfully fetched through the existing Apple integration. Each stored entry shows app_store, the expected bundle ID, expiry October 05 2027 and certificate match `noor-alruh-distribution`. Widget uses `noor-alruh-widgets-appstore-verified` because an earlier upload produced an incomplete metadata entry; that entry and older main profiles were preserved, not deleted. Workflow references match the verified entries. No signed archive or TestFlight upload has run yet.

CI150 finished: unsigned account/extension Release build passed; native execution failed in the all-screen UI walkthrough at `sources.whispercomponents`. The normal GitHub log shows a fully visible row ending at y=902, within the actual window/collection ending at y=956; the helper's fixed 60-point window inset ended at y=896 and falsely rejected the row. The shared visibility helper now uses the actual viewport and checks visible navigation/tab-bar obstruction, without dropping the test or creating a page-specific exception. A new native run is required to verify this change. The run exported 63 screenshots with `INCOMPLETE_CAPTURE`, missing `35-whisper-components`. These app captures have not been retrieved/viewed; visual Quran acceptance remains open. Direct CI log evidence confirms all five CloudPayloadTests and four AudioDownloadTests passed, including rejection of appended/truncated archives and live-server cancellation/retry/offline restart. Those are simulator/unit results, not real-device sign-in, speech accuracy or publication.

### Automatic-sync follow-up, 2026-10-07

Source now includes opt-in automatic reading/bookmark/plan/progress sync, durable deletion tombstones and excluded-note merge protection. All 11 isolated emulator rule tests passed on CI37612234523. Direct Firebase Console inspection confirms `(default)` exists in `me-central2` on Spark, but its published rules still only cover `private/memorization`; the new readingState/accountDeletions rules have NOT been deployed. The Apple-provider draft remains unsaved with blank OAuth credential fields. Do not recreate the database, republish old rules, or describe source-only sync as production-tested. Current native testing is tracked in EXECUTION-CHECKPOINT-20261007.md.


### Current live configuration check, 2026-10-09

Read-only Firebase Console inspection now confirms Apple Enabled. The current published Firestore Rules tab (selected starred current version) includes accountDeletions, private memorization/readingState, owner checks, supported documents, deletion guards, exact allowed fields, version1, bytes payload up to750000 and request.time timestamps. These visible rules match backend/firestore.rules except source-only comments. The older checkpoint saying these rules were not deployed is historical. No rules, provider, credential or access permission was changed during this check. Production sign-in, token revocation/deletion and two-device sync remain untested on hardware.
