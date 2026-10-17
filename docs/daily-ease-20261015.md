# Automatic setup and separate daily adhkar

The source Quran and original Hisn JSON remain unchanged. Morning and evening
are separate presentation groups and daily counter namespaces. Period-only
items and explicitly documented evening variants come from Hisn chapter 27;
canonical Quran rendering continues to use the original entry identifiers.
Notification links select the corresponding period directly.

First-use notifications request system consent after entering the app. Only
fresh installations with no prior notification choices receive the requested
defaults after consent. Rejection, prior preferences, edits during the prompt,
and later disabling are preserved. After-prayer messages remain silent and
fixed at 20 minutes after prayer time; salawat repeats silently every 300s.
Local notification scheduling remains subject to system permission/capacity.

Manual download controls are removed from reciter lists and storage settings.
Playback streams immediately and the existing verified-file cache saves heard
recordings automatically; first playback still requires network access.
Wi-Fi-only preference is retained. Listening again retries a failed pending
save. Bundled Quran, fonts, adhkar and recognition model need no user download.

Source 509a7ca passed 32 unit tests and one real morning/evening UI journey
on Codemagic build 6ad1373b3ffd2c7f0ad3b78c (Release, iOS 26.2,
iPhone 17 Pro, 7m43s). Native reading screenshots were inspected. The later
khatmah changes require their own result. The separate c2df1f4
selection run passed 12 tests (original fonts, adjacent ayah exclusion and
viewport geometry). The unchanged recognition source 90e3090 passed 14 narrow
tests including a real public reference recording. Its edited omission sample
produced zero omission candidates: general error detection and tajweed
accuracy are not established. Neither result represents full app acceptance.
