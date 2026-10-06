# Accounts and Friday release gates

The source includes Apple and Google authentication through Firebase Auth and private, opt-in memorization backups through Firestore. No Firebase project or provider has been activated yet. The default project does not enable account SDKs; `ios/project-accounts.yml` builds the complete Screen Time + account integration. Neither build may be described as offering working cloud accounts before the gates below pass.

## Required configuration

1. Register iOS bundle `com.saud1596x.nooralruh` in a Firebase project controlled by the app owner. Disable optional Analytics; no Analytics SDK is linked.
2. Enable Google and Apple identity providers. Enable Sign in with Apple on the Apple App ID and regenerate provisioning profiles. Apple credentials belong in the provider console, never in the repository.
3. Add the real `GoogleService-Info.plist` to `ios/Athar/` and its `REVERSED_CLIENT_ID` to the app's `CFBundleURLTypes`. Account UI stays unavailable without configuration.
4. Deploy `backend/firestore.rules` before activating cloud backups. Only the authenticated UID can read/write its private memorization document. All other database paths are denied.
5. Update the public privacy policy, the generated in-app policy, and App Store privacy answers for authentication identity and optional cloud memorization backups. Current policy still describes local-only operation and blocks account release.
6. On real iPhones, test both identity providers, cancellation, provider outage, restored session, sign-out, identity separation, missing backup, offline backup, invalid backup, and account deletion with recent reauthentication. Do not automatically link Google and Apple identities by email.
7. Verify deletion removes the account and its cloud backup. Local guest data has an independent deletion control.

## Friday behavior

- The home menu appears only on civil Friday in the selected city's timezone. Its settings remain available all week so a user can prepare in advance.
- Counters and checklist entries are saved per Friday. The personal salawat target is user-defined and carries no claimed prescribed reward for that number.
- Notification plans cover the upcoming Friday, include at most 14 requests, and pause salawat reminders around the user's mosque time. The chosen mosque time is not a computed or confirmed khutbah time.
- AlarmKit wake alarms require iOS 26+ and separate user authorization. No countdown Live Activity is used. Older systems offer notifications with clear limitations.
- Prayer dates vary weekly; upcoming alarms and notifications refresh when the app opens. Do not promise indefinite recurrence without reopening the app.
- On hardware, verify silent/Focus behavior, denial/revocation, cancellation, expired IDs, timezone/clock changes, city changes, and app termination. These checks are pending.

## Publishing remains blocked

Family Controls terms must be explicitly accepted by the owner before requesting the distribution entitlement. Screen Time distribution, provisioning for three extensions, real-device ward blocking, actual speech accuracy benchmarks, account service activation, and updated privacy documents remain prerequisites. No new version has been submitted for App Store publication.
