# Audio lifecycle review — 15 October 2026

This review is not an assertion that the complete recitation engine or release
has passed. The failing native run was d48cc67, Codemagic
6ad0ed1b3ffd2c7f0ad39f83. Both live process samples completed successfully.

## Confirmed failure and change

The second sample shows MainActor blocked in
`startLoadDeadline -> error.setter -> listenFirst error subscriber ->
cancelGuided -> stop -> saveBookmark -> currentSeconds -> AVPlayerItem.currentTime
-> itemfig_GetCurrentTime -> __psynch_mutexwait`.

Separately, the audio initialization thread waits for CoreAudio's host IPC
(`HALC_ProxyObject::SetPropertyData` while creating an output IOProc). The first
sample's main thread was still responsive. Thus a host playback failure became
an application UI hang specifically during timeout recovery.

The application now uses periodic player timestamps for elapsed time and
asynchronously loaded asset duration. Bookmark saving, diagnostics, and UI no
longer request `currentTime()` or an unloaded item's duration synchronously.
Only a reference that actually started can replace a saved bookmark. Time and
metadata callbacks check the sequence revision and exact player identity;
observers/tasks are removed on replacement and stop. Natural item-end remains
the only completion signal for guided practice.

Capture retains its input node and format for one take and removes its tap
through that retained node during shutdown; it no longer re-queries
`engine.inputNode` during cleanup. This does not claim to cure an OS failure
while initially creating the input node. Guided cancellation detaches the
reference before calling its stop method.

## Other lifecycle paths inspected

- Playback/recording ownership: NoorAudioFocus prevents reference playback
  while a recording lease is held.
- Capture/session setup: category and activation precede microphone creation;
  gain is adjusted only for routes that support it.
- Input loss: route, interruption, configuration and media-service observers
  report once, dispatching controller work away from the engine notification.
- PCM and inference: the writer keeps audio independently of the latest-window
  mailbox; inference cancellation and revision checks reject late results.
- Pause/finish: captured PCM is drained, the take is closed, and the recording
  lease remains held through recognition draining.
- Guided practice: playback itself creates no learner recording/evidence;
  microphone permission is requested only on the explicit learner action.

Code inspection is not device acceptance. Physical input, interruptions,
speaker leakage, long sessions and model accuracy remain to be measured.

## Verification

- Exact bundled text check: 6,236 verses and 112 separate basmalas match their
  pinned source without normalization.
- Local Python regression suite: 35 tests, 1 platform symlink skip, no failures.
- New native regression: stop an actual bundled reference during preparation,
  verify bounded stop, cleared state, and no late/false completion.
- Existing actual reference playback test and all its assertions retained.
- Targeted native run additionally includes microphone lifecycle, recognition
  worker lifecycle, wording assessment, and recognition input conditioning.
- d32a394 native compilation succeeded. Of 29 selected native tests, 28 passed;
  actual guided playback failed two assertions in one test. The stop-during-
  preparation regression passed in 0.346 seconds. The former MainActor freeze
  did not recur: load timeout returned in 15.959 seconds and release in ~1 ms.
- The reference still did not play in Simulator (item unknown, observed time
  zero). Host `afplay` of that same MP3 exited successfully in 4.265 seconds.
  Host playback does not establish Simulator playback. UI checks did not run.
- cc8cca6 adds actual AVPlayer and AVAudioPlayer control tests on the same
  reference, retaining the original guided test. Both controls failed in build
  6ad0f5f93ffd2c7f0ad3a2b3 (9m51s): AVAudioPlayer timed out inside AudioQueuePrime
  and HAL device setup; AVPlayer returned but never made its item ready or
  emitted actual end. The guided reference likewise timed out cleanly. There
  were 28 passing cases and three failing cases (four failure entries); the
  restarted runner's 30-test summary excludes the first timed-out control.
  These controls bypass Noor's verse-range logic but share its test host. This
  isolates a system audio path failure without proving all device audio works.

## Independent ownership defect found during review

`LocalRecitationRecorder.stop()` previously called shared audio session
deactivation even when idle, and the legacy recorder was not registered with
NoorAudioFocus. A disappearing legacy view could therefore affect another
player/capture, and a legacy recording could compete with recognition. It now
tracks its own activation, participates in the shared recording lease, and
registers playback cleanup. Two ownership regressions verify idle cleanup and
rejection before system activation when another recording owns the route.
Both legacy ownership regressions compiled and passed in 424a05b. They are
not asserted to be the cause of the Simulator's reference failure.

Follow-up review found that retaining a failed session-deactivation retry could
let an old recorder deactivate a new recording owner later. NoorAudioFocus now
rotates an ownership epoch after handoff cleanup; both recorder transports only
retry deactivation within their activation epoch. The existing same-owner retry
test is retained, and a new handoff regression requires the next recording's
lease and file bytes to survive old cleanup. This follow-up is not in the
completed 424a05b comparison and needs its own native verification.

The 424a05b Xcode 26.6 comparison failed in build 6ad0fb933ffd2c7f0ad3a47c
after 9m14s. Of 33 selected cases, 30 passed and three failed (four failure
entries). Both raw Apple players and the original guided reference still
failed; the AVAudioPlayer control timed out in the system audio path. The
restarted runner's 30-case summary excludes the two passed legacy tests and
the timed-out raw AVAudioPlayer case. Microphone UI did not run.

Xcode 26.5 and 26.6 both use the iOS 26.5 Simulator runtime. One further
comparison explicitly pins iOS 26.2 on the documented Xcode 26.3 image:
https://docs.codemagic.io/specs-macos/xcode-26-3/
The script fails if that exact runtime is absent and records its identity.
This includes the ownership-epoch repair and retains all real-audio controls,
the original guided assertions, host-daemon recovery and actual afplay check.
The 15-minute cap remains. This comparison is not evidence of a fix until
it runs; no PCM, completion events, tests or Release gates are substituted.
