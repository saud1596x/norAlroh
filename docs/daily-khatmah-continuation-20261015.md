# One daily khatmah action

Home uses one «أكمل ختمتك» action when a plan has pages left today. It resumes the saved verse/page inside the remaining daily allocation. The separate stop/resume action is removed. Settings remain available separately.

The reading route is bounded to the selected daily amount, less pages explicitly confirmed today. Reopening, reading ahead and missing days cannot silently create another allocation. The final Quran allocation ends at page 604. Turning pages saves position only; confirming completed pages records progress. A stale plan/day or an out-of-range confirmation is rejected.

Native evidence before this change: source 509a7ca, Codemagic 6ad1373b3ffd2c7f0ad3b78c, Release iOS 26.2 iPhone 17 Pro, 32 unit tests and one morning/evening reading UI test passed. Screenshots were inspected. This evidence does not cover the new khatmah route.

The next daily-ease check adds khatmah allocation/persistence unit tests, reader viewport tests and the real UI route: adopt 20 pages, open through Home, stop at page 20, reopen through the same action, confirm, and see today's completed state. No fabricated completion or pre-seeded progress is used. This is targeted verification, not full Release acceptance or real-device microphone verification.
