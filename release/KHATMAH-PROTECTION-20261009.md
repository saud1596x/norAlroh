# Khatmah-linked ward protection

The protection card is above the Quran resume card on Home and at the beginning of the khatmah screen. Setup explains the active khatmah, selected applications/domains, the optional Screen Time permission, and activation. The protected range is the unconfirmed part of the fixed schedule as of activation, in the khatmah time zone. It does not use Hifz results or speech matching as reading proof.

Only a successful persisted khatmah confirmation for the same plan UUID can advance the protected boundary. Partial reading retains the remaining pages; confirmed completion releases the shield. A future reading day does not shield applications early. An overdue range remains due. Confirming all 604 pages ends shielding. Editing or pausing the reading plan does not silently change the protected contract; the user can stop protection explicitly to adopt a different schedule. Relaunch and the extension use the same shared Codable state. Old Hifz-linked protection is stopped on first app opening, with an explanation to link the new protection to the khatmah.

Native acceptance: source batch 13c37b4, GitHub run 37862436381. Result pending when recorded. The gate compiles the real Screen Time extensions, then tests fixed schedules, partial/full completion, Riyadh midnight, other plan IDs, backwards/invalid progress, persistence and an actual revised reading plan. Actual UI tests exercise Home protection → setup → khatmah, together with existing launch/khatmah checks, on compact and large iPhone simulators.

Physical acceptance is still required: Family Controls distribution entitlement approval and provisioning; optional device authorization; selected app/domain blocking; partial/full page confirmation; scheduled rest days and midnight; revoke permission; explicit stop; relaunch/reboot/background. Simulator compilation and contract tests cannot certify these behaviors.

# Immediate offline reading audit

Bundled: canonical Quran text and basmalas, adhkar, cities, app legal pages, QCF V2 page fonts (verified at native build), original row metadata, local recognition resources, khatmah/counters/prayer calculation. The original QCF V2 reader still needs a first validated Content Sync glyph snapshot. Subsequent snapshots are cached, with refresh obligations. Tafsir is fetched per verse and cached; optional reciter audio is streamed or explicitly downloaded.

Quran Foundation Developer Terms section 3.1 (reviewed 2026-10-09) does not authorize a build-time bundled database of its Content Sync content. The font exception alone is insufficient to bundle the glyph snapshot. No such prohibited snapshot was added or disguised as a local resource. Independent QUL/mirror candidates were inspected; a resource-specific redistribution grant for the selected exact glyph/word mapping remains unresolved. The original glyph drawing has not been replaced.

QuranEnc's official page permits redistribution under conditions including unchanged content, source/publisher/version notices, and current editions. Its Arabic Moyassar listing is V1.0.0 dated 2017-02-15. Its download UI says downloading accepts its terms. No download agreement has been accepted in this increment and no complete tafsir bundle is claimed.

Final actual screenshot/video review is still blocked by the previously observed browser artifact download policy. No alternate transport was used to obtain the blocked app artifacts. No current publication or physical-device acceptance is claimed.
