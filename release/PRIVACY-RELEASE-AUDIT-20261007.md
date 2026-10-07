# Account privacy packaging correction — 2026-10-07

Firebase configuration is deferred by the owner. No production build or App Store submission is claimed.

The account build previously generated the correct account policy but retained an empty app-owned data collection manifest. The release preparation now declares name and email requested from Apple, account UID, the persistent sync-journal UUID carried in merge stamps, user bookmarks/plans/results, and reading/practice interactions. These are linked to the user and used for app functionality, without tracking. Location, microphone recordings and live transcripts are not uploaded by these sync payloads. SDK manifests remain separate and must be reviewed in Xcode's final aggregate report.

The IPA verifier rejects a missing privacy manifest or one that still describes local-only data. Existing permission/API reasons are preserved, and local-only preparation clears account declarations. This modifies release tooling; it does not change the native rendering or account runtime.

Validation: ten Python configuration/distribution regression tests passed, including missing/stale account manifest rejection and account/local policy generation with preserved API reasons. Synthetic IPA fixtures are not signed build evidence. Python compilation and git whitespace checks passed. Current text-engine TestFlight source gate remains independently required.

Apple references reviewed:
- https://developer.apple.com/documentation/technotes/tn3184-adding-data-collection-details-to-your-privacy-manifest
- https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacycollecteddatatypes/nsprivacycollecteddatatype
- https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacycollecteddatatypes/nsprivacycollecteddatatypelinked

Still open: original Firebase iOS file, signed archive/TestFlight upload, actual-device account/offline/audio/notification acceptance, reference visual and remaining content-rights review, Family Controls distribution approval and final App Store privacy/metadata reconciliation. Do not mark these passed from source or emulator tests.
