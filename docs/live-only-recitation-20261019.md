# Live recitation in the Mushaf

The user explicitly requested permanent removal of recordings and the scope
picker, then requested professional and consented learner recordings for engine
evaluation. Evaluation fixtures are separate from private app recordings.

This change removes the unused scope, setup, recording browser, recording list
and legacy recording-controls views. The microphone remains in the original
Mushaf. It does not add a replacement workspace, score screen or history route.

Actual capture still writes protected temporary PCM for the current attempt.
Pause/background keeps that open reader's attempt resumable. Finish or closing
the reader drains capture, invalidates late recognition and deletes the session
under the journal's write lock. Late analysis must load an existing session and
therefore cannot recreate deleted files. A fresh launch starts a fresh attempt.
Previously shown ayahs remain visible during the same attempt, without becoming
permanent correctness evidence.

On upgrade/start, only the two legacy learner-recording roots and expired
live-recitation workspaces are removed. Bookmarks, khatmah, account data, Quran
resources and cached professional-reciter audio are outside these roots. This
code runs on the device after installation; it has not remotely deleted files
from an already installed TestFlight build. Files exported outside the app are
outside its control. Privacy text and export controls follow this retention.

Four native regression cases cover scoped migration, deletion against late
analysis, actual reference PCM teardown, and permission completion after close.
They have been written and parsed locally, not executed on Windows. The new
bounded GitHub workflow runs current-source Release checks on a standard public
repository runner, with separate result bundles for unit, microphone and privacy
journeys. No paid Codemagic run is authorized by this change.

The preceding09c1bae native run6ad531b77550aed8108ff045 failed:
twenty-page khatmah passed73.304s, walkthrough exceeded300s; background test never
reached capture because it expected an unmaterialized List row112; one-tap lost
the app connection at the elapsed assertion. That lost connection's cause is
unconfirmed. The helper now uses the actual public surah search. The preceding
failure is retained and cannot certify this new app source.

No claims of comparison superiority, natural-learner accuracy, Tajweed acoustic
assessment, full20-reciter word timing or full Release acceptance follow from
these changes. TestFlight24 is still the installed earlier app source.
