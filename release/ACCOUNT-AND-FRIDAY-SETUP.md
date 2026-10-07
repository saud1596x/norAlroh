# Accounts and Friday release gates

The current account release uses Apple authentication through Firebase Auth and private, opt-in reading and memorization synchronization through Firestore. On 2026-10-07 the live Firebase console showed Apple enabled; Google remains disabled. The iOS application is registered in `noor-alruh` as `com.saud1596x.nooralruh`. The default project does not enable account SDKs; `ios/project-accounts.yml` builds the Screen Time and account integration. Actual sign-in, two-device sync and deletion acceptance still require the signed build and real devices.

## Required configuration

1. Register iOS bundle `com.saud1596x.nooralruh` in a Firebase project controlled by the app owner. Disable optional Analytics; no Analytics SDK is linked.
2. Apple provider setup is saved. Sign in with Apple must remain enabled on the Apple App ID and the distribution profile. Apple credentials belong in the provider console, never in the repository. Google is outside the current release.
3. The original `GoogleService-Info.plist` is deferred by the owner. Store its base64 in protected Codemagic `noor_release` variable `NOOR_FIREBASE_IOS_PLIST_BASE64`; the installer verifies project, bundle and app IDs. Apple-only setup requires no Google OAuth client or reversed client ID.
4. Current `backend/firestore.rules` were published in the live Firebase console on 2026-10-07. Only the authenticated owner can access private readingState and memorization documents. A deletion marker prevents stale sessions recreating a deleted account's data. This is not device acceptance.
5. `prepare-publishing.py --accounts` generates the account policy and app-owned privacy declarations together; `--accounts --check` and the IPA gate reject a stale local manifest. Reconcile App Store privacy answers and the publicly served account policy with the final signed build and its SDK manifests before submission.
6. On real iPhones, test Apple sign-in, cancellation, provider outage, restored session, sign-out, identity separation, missing backup, offline backup, invalid backup, and account deletion with recent reauthentication. Do not automatically link identities by email.
7. Verify deletion removes the account and its cloud backup. Local guest data has an independent deletion control.

## Friday behavior

- The home menu appears only on civil Friday in the selected city's timezone. Its settings remain available all week so a user can prepare in advance.
- Counters and checklist entries are saved per Friday. The personal salawat target is user-defined and carries no claimed prescribed reward for that number.
- Notification plans cover the upcoming Friday, include at most 14 requests, and pause salawat reminders around the user's mosque time. The chosen mosque time is not a computed or confirmed khutbah time.
- AlarmKit wake alarms require iOS 26+ and separate user authorization. No countdown Live Activity is used. Older systems offer notifications with clear limitations.
- Prayer dates vary weekly; upcoming alarms and notifications refresh when the app opens. Do not promise indefinite recurrence without reopening the app.
- On hardware, verify silent/Focus behavior, denial/revocation, cancellation, expired IDs, timezone/clock changes, city changes, and app termination. These checks are pending.

## Publishing remains blocked

On 2026-10-07 Asia/Riyadh, the owner explicitly accepted the displayed Family Controls terms. Apple confirmed the distribution request submission and said it will review the request and contact the owner. Approval is pending. Screen Time distribution, provisioning for three extensions, real-device ward blocking, actual speech accuracy benchmarks, account service activation, and updated privacy documents remain prerequisites. No new version has been submitted for App Store publication.
