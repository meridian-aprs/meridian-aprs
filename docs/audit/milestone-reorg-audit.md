# Milestone & Issue Reorganization Audit

> **Status: Executed 2026-04-25.** This audit drove the reorganization completed in the milestone-reorg PR. Retained as historical record.

Generated: 2026-04-25
Source data: `gh api repos/.../milestones?state=all`, `gh issue list --state open`, individual `gh issue view` per open issue, `docs/ROADMAP.md`, `docs/FUTURE_FEATURES.md`.

## Summary

GitHub milestones and `docs/ROADMAP.md` have drifted significantly. The repository currently carries **19 GitHub milestones** (10 closed, 9 open). Of the 9 open milestones, **6 are stale empty containers** that were renamed in subsequent reorderings — the work they once tracked has shipped under different milestone records. Only three open milestones contain live issues: **#18 v0.15 — Battery & Performance** (14 open), **#19 v0.16 — Bug Triage** (5 open), and **#6 v1.0 — Launch** (2 open). All 21 open issues were filed in a single audit sweep (commit 9fe5479) and **every single one still carries the `needs-triage` label** despite being placed into a milestone — a systematic anomaly that suggests the triage step was skipped after batch-filing.

The substantive content of the open issues clusters strongly around four themes: **dependency upgrades** (3), **testing gaps** (4), **CI/devops gaps** (4 including the two v1.0 ship-blockers), and **architecture/Flutter rebuild hygiene** (7). Only 1 of 21 issues is a true "feature" (the feature-flags scaffold), and the two `bug`-labeled issues (#46, #47) are really release-infrastructure / external-portal blockers, not behaviour bugs. Milestone #19 (v0.16 — Bug Triage) is named for triaging bugs, but currently holds 5 polish/cleanup enhancement issues and **zero confirmed bugs**, which makes its name misleading.

The "v0.15 GitHub milestone is being treated as v0.18 in planning" observation in the task brief tracks: the GitHub `v0.15 — Battery & Performance` milestone has become a 14-issue grab-bag of perf, deps, testing, architecture, and devops work, and would benefit from being either renamed to reflect that scope or split. Nothing in the open-issue inventory cleanly maps to "battery profiling" specifically — the eponymous work for v0.15 (background drain profiling, memory audit, SQLite migration) has **no issues filed**, which is the most significant gap surfaced by this audit.

---

## Current State

### GitHub Milestones

| # | Title | State | Open / Closed issues | Notes |
|---|---|---|---|---|
| 1 | v0.1 — Foundation | closed | 0 / 2 | Shipped |
| 2 | v0.2 — Packets | closed | 0 / 0 | Shipped, never had issues filed |
| 3 | v0.3 — TNC | closed | 0 / 0 | Shipped, never had issues filed |
| 4 | v0.4 — BLE | closed | 0 / 1 | Shipped |
| 5 | v0.5 — Beaconing & Messaging | closed | 0 / 0 | Shipped, no issues |
| 6 | **v1.0 — Launch** | **open** | **2 / 1** | Two ship-blockers (#46, #47) |
| 7 | v0.6 — Connection UI | closed | 0 / 0 | Shipped, no issues |
| 8 | v0.7 — Android Background | closed | 0 / 0 | Shipped, no issues |
| 9 | v0.8 — Platform Parity | closed | 0 / 2 | Shipped |
| 10 | v0.10 — Map Experience | **open** | **0 / 0** | **Stale — work shipped, milestone never closed** |
| 11 | v0.9 — iOS Background | **open** | **0 / 0** | **Stale — work shipped, milestone never closed** |
| 12 | v0.11 — Map Filters & Stations | **open** | **0 / 0** | **Stale — title clashes with #15 (also "v0.11"); no work tracked here** |
| 13 | v0.12 — Map Enhancement | **open** | **0 / 0** | **Stale — title doesn't match shipped v0.12 (Onboarding); no work tracked here** |
| 14 | v0.13 — Onboarding (stale) | closed | 0 / 0 | Already explicitly marked stale in description |
| 15 | v0.11 — Notifications | **open** | **0 / 0** | **Stale — Notifications shipped under this number; milestone never closed** |
| 16 | v0.13 — Security & connectivity | **open** | **0 / 5** | **Stale — Security shipped; should be closed** |
| 17 | v0.14 — Base-Callsign Message Matching | **open** | **0 / 0** | **Stale — work shipped, milestone never closed** |
| 18 | **v0.15 — Battery & Performance** | **open** | **14 / 1** | Live, but scope has expanded well beyond "battery & performance" |
| 19 | **v0.16 — Bug Triage** | **open** | **5 / 1** | Live, but currently holds 5 enhancements and 0 bugs |
| 20 | v0.17 — Groups & Bulletins | closed | 0 / 2 | Shipped |

### Roadmap Milestones (from `docs/ROADMAP.md`)

Sequence per `docs/ROADMAP.md` (last updated 2026-04-22), in shipped/planned order:

`v0.1 → v0.2 → v0.3 → v0.4 → v0.5 → v0.6 → v0.7 → v0.8 → v0.9 → v0.10 → v0.11 (Notifications) → v0.12 (Onboarding) → v0.13 (Security) → v0.14 (Base-Callsign Matching) → v0.17 (Groups & Bulletins)` — all complete.

`v0.15 — Battery & Performance → v0.16 — Bug Triage → v1.0 — Launch` — pending.

`docs/FUTURE_FEATURES.md` tracks ~30 deferred features, none currently scheduled.

### Drift / Mismatches

1. **Six open GitHub milestones with zero issues are stale:** #10, #11, #12, #13, #15, #17 all describe work that has either shipped under a different milestone record or never had issues opened. Plus **#16 (v0.13 — Security & connectivity)** is open with 0 open / 5 closed — work is done but the milestone itself was never closed.
2. **Title clash:** `v0.11` appears as both #12 (`v0.11 — Map Filters & Stations`) and #15 (`v0.11 — Notifications`). Per roadmap, v0.11 = Notifications; the Map Filters & Stations content was never scheduled and effectively dissolved into v0.10 + later work.
3. **Title clash (resolved):** `v0.13` appears in both #14 (closed, marked stale) and #16 (open). Only #16 needs disposition (close).
4. **Milestone description for #18 (v0.15)** lists scope including SQLite migration evaluation, but no issue covers that work — see Gap Analysis.
5. **CLAUDE.md says "v0.17 in progress" but it's already merged** — that's a CLAUDE.md drift, out of scope for this audit but worth noting.
6. **`needs-triage` is on every single open issue (21/21)** despite milestone assignment — the label is no longer informative and should be removed batch-wise after this reorg.

---

## Issue Inventory

> Every entry below carries `needs-triage` despite being in a milestone (universal anomaly — only called out per-issue when paired with another anomaly).

### v1.0 — Launch (#6) — 2 open

#### #46 — `[F-PLT-001]` Android release signing config still on debug keystore
- **Milestone:** v1.0 — Launch
- **Labels:** bug, android, p1-critical, needs-triage, area:devops
- **Summary:** Replace debug keystore in `android/app/build.gradle.kts` release block with a real release keystore + gitignored `key.properties` before any Play Store submission.
- **Theme:** ci-devops
- **Dependencies:** Pairs with #63 (release-build CI) — once signing exists, CI release-build job needs the signing secrets.
- **Anomalies:** Labeled `bug` but is really a build-config / release-prep task. v1.0 placement correct.

#### #47 — `[F-PLT-002]` iOS Live Activity App Group not created in Apple Developer portal
- **Milestone:** v1.0 — Launch
- **Labels:** bug, ios, p1-critical, needs-triage, area:devops, blocker:external
- **Summary:** Create App Group `group.com.meridianaprs.meridianAprs` in the Apple Developer portal and enable on both Runner and MeridianLiveActivity bundle IDs; portal task only, code is already correct.
- **Theme:** ci-devops
- **Dependencies:** External (Apple portal); references ADR-031 and the `v0.9` milestone disclaimer in `docs/ROADMAP.md`.
- **Anomalies:** Labeled `bug` but is purely an external-portal setup. Correctly carries `blocker:external`. v1.0 placement correct.

### v0.15 — Battery & Performance (#18) — 14 open

#### #43 — `[F-META-002]` Inject Clock abstraction — make time-dependent logic deterministic
- **Milestone:** v0.15
- **Labels:** enhancement, ui, p2-high, needs-triage, area:architecture, testing
- **Summary:** Add `typedef Clock = DateTime Function();` and inject across services that use `DateTime.now()` (BeaconingService, MessageService retry, StationService pruning, AprsParser receivedAt) to enable deterministic testing.
- **Theme:** architecture (also enables testing)
- **Dependencies:** Foundational for #52 (BeaconingService tests) and #60 (TxService routing tests). Cross-cuts F-ARCH-006, F-EXT-002, F-FLT-009 from the original audit.
- **Anomalies:** `ui` label seems wrong — this is a core service-layer change; should drop `ui`.

#### #49 — `[F-EXT-004]` Add `lib/config/feature_flags.dart` for staged features
- **Milestone:** v0.15
- **Labels:** enhancement, p3-normal, needs-triage, area:config
- **Summary:** Add a typed feature-flag bag fed by `--dart-define`, mirrored on `AppConfig.stadiaMapsApiKey`'s pattern; needed for upcoming staged/experimental features.
- **Theme:** architecture (extensibility scaffolding)
- **Dependencies:** None.
- **Anomalies:** Pure scaffolding for *future* work (Contacts, Digipeater, Weather, Directed Queries) — no current consumer. May be premature for v0.15; could defer until first staged feature actually exists.

#### #50 — `[F-PLT-004]` CI builds Linux-debug only — add Android/iOS/macOS/Windows matrix
- **Milestone:** v0.15
- **Labels:** enhancement, p2-high, needs-triage, area:devops
- **Summary:** Expand `.github/workflows/ci.yml` into a per-platform matrix that runs `flutter build` for each native target so manifest/entitlement/build-config drift is caught at PR time.
- **Theme:** ci-devops
- **Dependencies:** Pairs with #63 (release-build CI).
- **Anomalies:** Scope mismatch with milestone — this is CI infrastructure, not battery/performance.

#### #51 — `[F-FLT-001]` `MapScreen.build()` watches StationService — entire scaffold rebuilds on every packet
- **Milestone:** v0.15
- **Labels:** enhancement, ui, p2-high, needs-triage
- **Summary:** Replace `context.watch<StationService>()` in `lib/screens/map_screen.dart:548` with narrow `Selector` calls so the scaffold doesn't rebuild on every packet ingestion.
- **Theme:** performance
- **Dependencies:** Direct precursor / sibling of #57 (Selector convention).
- **Anomalies:** Genuinely on-theme for v0.15 (perf).

#### #52 — `[F-EXT-001]` No service-level test for BeaconingService
- **Milestone:** v0.15
- **Labels:** enhancement, p2-high, needs-triage, testing
- **Summary:** Write `test/services/beaconing_service_test.dart` using `fake_async` + fake Geolocator adapter to cover mode transitions, smart rescheduling, last-beacon persistence, and `BeaconError.locationUnsupported`.
- **Theme:** testing
- **Dependencies:** Easier with #43 (Clock injection) landed first.
- **Anomalies:** Off-theme for v0.15 (testing, not battery/perf), though benefits perf work indirectly.

#### #53 — `[F-EXT-003]` Zero widget tests beyond smoke test
- **Milestone:** v0.15
- **Labels:** enhancement, ui, p2-high, needs-triage, testing
- **Summary:** Build out widget tests for BeaconFAB (priority — guards a known regression), then PacketLogScreen, ConnectionScreen, and one-test-per-screen by v1.0.
- **Theme:** testing
- **Dependencies:** None.
- **Anomalies:** Off-theme for v0.15. Estimate "L overall, M for targeted v0.15 pass" suggests the issue should be split.

#### #54 — `[F-PLT-003]` `flutter_local_notifications` 3 majors behind (18 → 21)
- **Milestone:** v0.15
- **Labels:** enhancement, ios, android, p2-high, needs-triage, dependencies
- **Summary:** Plan migration from v18 → v21; init API, RemoteInput action wiring, and Darwin UNTextInputAction setup all need re-verification.
- **Theme:** dependencies
- **Dependencies:** Pair with #66 (desugar_jdk_libs refresh) — same upgrade window.
- **Anomalies:** Off-theme for v0.15 (dependencies, not battery/perf).

#### #55 — `[F-PLT-005]` `flutter_blue_plus` 1 major behind (1.x → 2.x)
- **Milestone:** v0.15
- **Labels:** enhancement, ble, ios, android, p2-high, needs-triage, dependencies
- **Summary:** Migrate to flutter_blue_plus v2 — review MTU API, characteristic notify subscription shape, scan filter builder; re-run BLE tests against `FakeBleDeviceAdapter`.
- **Theme:** dependencies
- **Dependencies:** None.
- **Anomalies:** Off-theme for v0.15.

#### #56 — `[F-ARCH-004]` Double subscription to `conn.lines` in main.dart + ConnectionRegistry
- **Milestone:** v0.15
- **Labels:** enhancement, p3-normal, needs-triage, area:architecture
- **Summary:** Resolve duplicate listener wiring — either move ingestLine onto `registry.lines` (preferred) or delete unused `registry.lines` if no consumer planned.
- **Theme:** architecture
- **Dependencies:** F-ARCH-005 mentioned in body but not filed as a separate issue (no #44 / #45 / #48 in open list — they were closed).
- **Anomalies:** Off-theme for v0.15 (architecture cleanup, not perf).

#### #57 — `[F-FLT-003]` Selector used only in one place — establish codebase convention
- **Milestone:** v0.15
- **Labels:** enhancement, ui, p3-normal, needs-triage
- **Summary:** Establish `Selector<T, ...>` as the standard for high-frequency notifiers (StationService, MessageService, ConnectionRegistry); document in ARCHITECTURE.md; apply retroactively to the top 5 offenders.
- **Theme:** performance / architecture
- **Dependencies:** Strong overlap with #51 — #51 is the surgical fix for the worst offender, this is the codebase-wide pattern.
- **Anomalies:** **Possible partial duplicate of #51.** Could absorb #51 into this, or keep #51 as the v0.15 quick win and defer #57 codebase-wide pass to v1.0.

#### #58 — `[F-FLT-004]` Two non-builder `ListView` in scrolling content surfaces
- **Milestone:** v0.15
- **Labels:** enhancement, ui, p3-normal, needs-triage
- **Summary:** Convert two `ListView(children:[...])` sites in SettingsScreen and PacketDetailSheet to builder/separated variants for consistency and inflation hygiene.
- **Theme:** performance (cosmetic)
- **Dependencies:** Pairs with #64 (third site, lower priority).
- **Anomalies:** **Possible partial duplicate of #64** — both flag non-builder ListViews; could be one issue.

#### #59 — `[F-EXT-005]` No `CallsignDisplay` seam — shotgun risk for Contacts feature
- **Milestone:** v0.15
- **Labels:** enhancement, ui, p3-normal, needs-triage, area:extensibility
- **Summary:** Introduce `lib/ui/utils/callsign_display.dart` and migrate all 8 callsign-rendering sites at once so a future ContactsService is a one-file change.
- **Theme:** architecture (extensibility scaffolding)
- **Dependencies:** Pre-emptive for FUTURE_FEATURES "QRZ / HamDB Callsign Lookup" and a Contacts feature.
- **Anomalies:** Off-theme for v0.15. Pre-emptive seam work without an immediate consumer — could be deferred until a Contacts/QRZ feature is scheduled.

#### #60 — `[F-EXT-007]` No test for TxService hierarchy routing (Serial > BLE > APRS-IS)
- **Milestone:** v0.15
- **Labels:** enhancement, p3-normal, needs-triage, testing
- **Summary:** Add `tx_service_routing_test.dart` covering the hierarchy resolution, `forceVia` override, and beacon fan-out across `FakeMeridianConnection` instances.
- **Theme:** testing
- **Dependencies:** None directly; #43 (Clock) helps but isn't required.
- **Anomalies:** Off-theme for v0.15.

#### #66 — `[F-PLT-010]` `desugar_jdk_libs` version drift — refresh when bumping notifications
- **Milestone:** v0.15
- **Labels:** enhancement, android, p4-low, needs-triage, dependencies
- **Summary:** Refresh `desugar_jdk_libs` 2.1.4 → current per `flutter_local_notifications` v21 README guidance.
- **Theme:** dependencies
- **Dependencies:** Should land in same PR as #54.
- **Anomalies:** Off-theme for v0.15. Could be merged into #54.

### v0.16 — Bug Triage (#19) — 5 open

#### #61 — `[F-FLT-006]` Only 3 Semantics annotations in the codebase — a11y audit pass
- **Milestone:** v0.16
- **Labels:** enhancement, ui, p3-normal, needs-triage, accessibility
- **Summary:** A11y audit — add `Semantics` to BeaconFAB, AprsSymbolWidget map markers, ConnectionNavIcon, MeridianStatusPill, and active-filter / not-connected nudge chips.
- **Theme:** feature (accessibility)
- **Dependencies:** None.
- **Anomalies:** Misplaced — this is an accessibility feature pass, not bug triage.

#### #62 — `[F-PLT-007]` Adaptive widget usage inconsistent — risks non-native iOS feel
- **Milestone:** v0.16
- **Labels:** enhancement, ios, p3-normal, needs-triage, area:cross-platform
- **Summary:** Convert mixed `SwitchListTile`/`CircularProgressIndicator`/`Slider`/`Checkbox` sites to `.adaptive` constructors for iOS polish.
- **Theme:** tech-debt (iOS polish)
- **Dependencies:** None; relates to v0.8 iOS Cupertino audit work.
- **Anomalies:** Misplaced — polish task, not bug triage. Could defer to v1.0 polish pass alongside iOS simulator validation already pending in `MEMORY.md`.

#### #63 — `[F-PLT-008]` No release-build CI — no ProGuard/R8/archive validation
- **Milestone:** v0.16
- **Labels:** enhancement, p3-normal, needs-triage, area:devops
- **Summary:** Add release-build CI workflow (`workflow_dispatch` + RC tags) running `flutter build apk --release`, `ios --no-codesign`, `linux --release` to catch ProGuard/R8/archive issues before submission.
- **Theme:** ci-devops
- **Dependencies:** Pairs with #50 (matrix CI), #46 (signing config); blocks pre-v1.0 confidence.
- **Anomalies:** Misplaced — devops infrastructure, not bug triage.

#### #64 — `[F-FLT-005]` Filter bar in PacketLogScreen uses non-builder ListView
- **Milestone:** v0.16
- **Labels:** enhancement, ui, p4-low, needs-triage
- **Summary:** Convert horizontal ChoiceChip ListView in `packet_log_screen.dart:203-220` to `ListView.builder` or `SingleChildScrollView`+`Row` for consistency with #58.
- **Theme:** tech-debt (cosmetic)
- **Dependencies:** Sibling of #58.
- **Anomalies:** Misplaced — tiny cleanup, not a bug. **Possible partial duplicate of #58.**

#### #65 — `[F-FLT-008]` `MapScreen.build()` is ~380 lines — extract helpers
- **Milestone:** v0.16
- **Labels:** enhancement, ui, p4-low, needs-triage
- **Summary:** Extract `_buildMarkersLayer()`, `_buildActiveFilterChip()` from `MapScreen.build()` for readability; not a correctness issue.
- **Theme:** tech-debt
- **Dependencies:** None.
- **Anomalies:** Misplaced — refactor, not a bug.

---

## Theme Clusters

| Theme | Count | Issues |
|---|---|---|
| ci-devops | 4 | #46, #47, #50, #63 |
| dependencies | 3 | #54, #55, #66 |
| testing | 3 | #52, #53, #60 |
| performance | 3 | #51, #57, #58 |
| architecture | 3 | #43, #56, #59 |
| tech-debt | 3 | #62, #64, #65 |
| feature | 2 | #49 (feature-flags scaffold), #61 (a11y) |
| bug | 0 | — |
| docs | 0 | — |
| unclear | 0 | — |

Notes:
- `#43` (Clock) is dual-coded architecture/testing — placed in architecture because that's the surface change; testing is the payoff.
- `#46` and `#47` carry the `bug` label but the actual work is release-infrastructure, not behaviour fixes — counted under ci-devops.
- **Zero confirmed bugs are filed**, despite v0.16 being titled "Bug Triage". The triage milestone currently holds 5 enhancement/polish issues.

---

## Orphans

**None.** Every open issue is assigned to a milestone (#6, #18, or #19).

---

## Possible Duplicates

| Issues | Overlap |
|---|---|
| **#51** + **#57** | #51 is the targeted fix for `MapScreen.build()`'s `context.watch<StationService>`; #57 is the codebase-wide convention pass that would also fix #51. **Suggest:** keep both, but make #51 explicitly "first application of the convention from #57", or close #51 once #57 lands. |
| **#58** + **#64** | Both flag non-builder `ListView` usage; #58 covers SettingsScreen + PacketDetailSheet, #64 covers PacketLogScreen. **Suggest:** consolidate into a single "convert remaining non-builder ListViews" issue. |
| **#46** + **#50** + **#63** | All three are release-pipeline CI/build gaps. Not duplicates — distinct surfaces (signing, matrix coverage, release archive validation) — but should ship as a coherent CI hardening epic, not three independent PRs. |
| **#54** + **#66** | `flutter_local_notifications` v21 upgrade and `desugar_jdk_libs` refresh — same PR per Android docs. **Suggest:** close #66 in favor of a checkbox inside #54. |

---

## Gap Analysis (Missing Issues)

These are work items that the codebase, ROADMAP, ADRs, or MEMORY clearly imply are needed, but for which no GitHub issue exists.

1. **SQLite/`drift` migration evaluation** — explicitly named in milestone #18 description and `docs/ROADMAP.md` v0.15 section ("Evaluate migrating station/packet persistence from SharedPreferences JSON blobs to SQLite … indexed bounding-box queries"); also referenced as a prereq for "Group message search" in `FUTURE_FEATURES.md`. **Suggest:** file as a v0.15 spike issue or split into (a) evaluation/spike, (b) actual migration if green-lit.
2. **Background service battery profiling** — the eponymous v0.15 work; no issue captures the actual measurement methodology, instrumentation, or acceptance threshold. The 14 issues in #18 are all secondary tech-debt; the headline scope has no work item.
3. **Memory usage audit for large station counts** — also in milestone #18 description; no issue.
4. **Packet processing efficiency review** — also in milestone #18 description; no issue. Worth at least an investigation issue with a perf budget.
5. **`BulletinService` SQLite-backed persistence** — implied by ADR-057 and the v0.17 retention sweeper; current implementation reads/writes the full `OutgoingBulletin` list from SharedPreferences each tick. Will become a perf concern once subscriber lists grow. Not currently filed.
6. **`MeridianConnectionTask` background-isolate `ScheduleWakeup`-style coordination** — current 30-second tick reads prefs each cycle (per CLAUDE.md/MEMORY); no issue tracks whether this is the intended permanent design or a v0.17 stopgap.
7. **`bug` label has no open issues** — either Meridian genuinely has no known bugs (unlikely for an APRS app at this maturity), or bugs are being filed and immediately fixed without the `bug` label, or no triage process is feeding this label. Worth a meta-process check: if there's a pile of behavioural bugs that should drive v0.16, they aren't visible here.
8. **iPhone 16 Pro physical-device validation pass** — listed in MEMORY ("Physical iPhone 16 Pro validation still needed for v0.8 iOS Cupertino audit") but not filed.
9. **Real-world Smart Beaconing drive test** — listed in MEMORY but not filed; v0.5 deliverable.
10. **Tracking issue for the `needs-triage` label cleanup itself** — see Proposals.

---

## Proposals (For Human Review)

### Suggested Milestone Renames

| Current title | Proposed title | Reasoning |
|---|---|---|
| **#18 — v0.15 — Battery & Performance** | **v0.18 — Tech-Debt & Hardening** *(or* v0.15 — Hardening Pass*)* | Of the 14 issues here, **3 are perf** and **11 are something else** (deps, testing, architecture, devops). Either rename to match the actual content, or split (see reassignments below) and let v0.15 keep its narrow battery/perf scope. The user task brief noted v0.15 is being treated as v0.18 in planning — formalize that. |
| **#19 — v0.16 — Bug Triage** | **v0.19 — Polish & A11y Pass** *(if Bug Triage milestone is moved)* | Currently holds 5 polish/a11y/refactor enhancements and 0 bugs. Either move the work elsewhere and keep "Bug Triage" as a future container for genuine bugs, or rename to match what's actually in it. |

### Suggested Issue Reassignments

The cleanest cut is to (a) shrink #18 to genuine perf work, (b) create new milestone(s) by theme, (c) put release-blocker CI work close to v1.0. Concrete proposal:

| Issue | Current | Suggested | Why |
|---|---|---|---|
| #51 (Selector for MapScreen) | v0.15 | **keep in v0.15** | Genuine perf win |
| #57 (Selector convention) | v0.15 | **keep in v0.15** | Genuine perf, finishes #51's work |
| #58 (non-builder ListView) | v0.15 | merge into #57 or move to v0.19/polish | Cosmetic |
| #66 (desugar refresh) | v0.15 | merge into #54 | Same PR |
| #43 (Clock injection) | v0.15 | new "v0.18 / Architecture & Testing" milestone, or keep as foundational pre-req for #52/#60 | Architecture, not perf |
| #49 (feature flags) | v0.15 | **defer** — close until first staged feature actually exists, or move to v1.1 backlog | No current consumer |
| #50 (CI matrix) | v0.15 | **move to v1.0** alongside #46/#63 | Release-pipeline hardening |
| #52 (BeaconingService tests) | v0.15 | new "v0.18 / Architecture & Testing" milestone | Testing, not perf |
| #53 (widget tests) | v0.15 | split: small targeted v0.15/v0.18 pass + remainder to v1.0 polish | Two-tier scope per body |
| #54 (notifications upgrade) | v0.15 | new "v0.X / Dependency Refresh" milestone or keep | Deps, not perf |
| #55 (BLE upgrade) | v0.15 | same as #54 | Deps, not perf |
| #56 (double subscription) | v0.15 | new "v0.18 / Architecture & Testing" milestone | Architecture |
| #59 (CallsignDisplay seam) | v0.15 | **defer** — move to v1.1 backlog or block on Contacts feature scoping | Pre-emptive scaffolding |
| #60 (TxService routing tests) | v0.15 | new "v0.18 / Architecture & Testing" milestone | Testing |
| #61 (a11y) | v0.16 | dedicated v0.19 polish/a11y milestone or v1.0 | A11y, not bug triage |
| #62 (adaptive widgets) | v0.16 | v1.0 polish pass alongside iPhone validation | iOS polish |
| #63 (release-build CI) | v0.16 | **move to v1.0** alongside #46/#50 | Release-pipeline hardening |
| #64 (filter ListView) | v0.16 | merge into #58/#57 | Cosmetic, consolidate |
| #65 (MapScreen extract) | v0.16 | v0.18 architecture milestone or close as won't-fix | Refactor, low ROI |
| #46 (Android signing) | v1.0 | **keep** | Genuine v1.0 ship-blocker |
| #47 (iOS App Group) | v1.0 | **keep** | Genuine v1.0 ship-blocker (external) |

### Suggested Milestone Closures / Deletions

Close (with comment "shipped under different milestone record"):
- **#10** — v0.10 — Map Experience (work shipped)
- **#11** — v0.9 — iOS Background (work shipped)
- **#12** — v0.11 — Map Filters & Stations (never had issues; work absorbed elsewhere)
- **#13** — v0.12 — Map Enhancement (never had issues; v0.12 actually shipped as Onboarding)
- **#15** — v0.11 — Notifications (work shipped)
- **#16** — v0.13 — Security & connectivity (work shipped, 5 closed issues)
- **#17** — v0.14 — Base-Callsign Message Matching (work shipped)

After closures, only #6 (v1.0), #18 (v0.15), #19 (v0.16) remain open — plus any new milestones from the proposals above.

### Suggested New Issues

1. **`[v0.15] Profile background-service battery drain — establish baseline + acceptance threshold`** — captures the eponymous v0.15 work. No code changes; investigation issue with deliverable = profiling report + go/no-go on optimization tasks.
2. **`[v0.15] SQLite/drift migration spike — evaluate vs SharedPreferences for station + packet persistence`** — explicit issue for the work named in milestone #18 description.
3. **`[v0.15] Memory audit — large station count (target: 5k stations stable)`** — explicit issue for milestone scope.
4. **`[v0.15] Packet processing throughput review — establish baseline at ≥5 pkt/s`** — explicit issue for milestone scope.
5. **`[v0.16 / process] Triage existing bug reports and re-label`** — meta-task to populate v0.16 with actual bugs (or close v0.16 if there are none).
6. **`[chore] Drop blanket needs-triage label from milestone-assigned issues`** — 21 issues; one batch operation.
7. **`[v0.X / future-prep] BulletinService persistence — consider SQLite once outgoing list grows`** — captures the v0.17 follow-up implied by ADR-057.
8. **`[v0.5 follow-up] Real-world Smart Beaconing drive test`** — surface the long-standing MEMORY note as a tracked issue.
9. **`[v1.0] Physical iPhone 16 Pro validation pass for Cupertino tier`** — surface the MEMORY note.

### Suggested ROADMAP.md Updates

1. **Add a v0.18 row** if the rename proposal is accepted, or **rewrite the v0.15 row** to acknowledge expanded scope.
2. **Update v0.15 description** to either drop the SQLite line (if deferred) or commit to filing the spike issue (if kept). Currently the description promises work that has no issue.
3. **Rewrite the v0.16 description** if the milestone is repurposed away from "Bug Triage" — currently the description ("Triage all open `bug` issues") is incorrect because no `bug`-labeled enhancement issues exist there.
4. **Add a "Backlog / Deferred" section** between v1.0 and Pending Items, naming #49 (feature flags) and #59 (CallsignDisplay seam) if they're deferred — keeps the deferral visible without losing the context.
5. **Add a "Tooling / CI" sub-section under v1.0** naming #46, #47, #50, #63 as the release-pipeline hardening epic so the ship-blocker work is grouped.

---

## Appendix

### Raw `gh api .../milestones?state=all` output

```json
{"closed_issues":2,"description":"Flutter scaffold, map rendering, APRS-IS connection, basic station display","due_on":null,"number":1,"open_issues":0,"state":"closed","title":"v0.1 — Foundation"}
{"closed_issues":0,"description":"AX.25/APRS parser, packet log view, symbol rendering","due_on":null,"number":2,"open_issues":0,"state":"closed","title":"v0.2 — Packets"}
{"closed_issues":0,"description":"KISS over USB serial, desktop platforms first","due_on":null,"number":3,"open_issues":0,"state":"closed","title":"v0.3 — TNC"}
{"closed_issues":1,"description":"KISS over BLE, mobile platforms","due_on":null,"number":4,"open_issues":0,"state":"closed","title":"v0.4 — BLE"}
{"closed_issues":0,"description":"Transmit path, position beaconing, message send/receive","due_on":null,"number":5,"open_issues":0,"state":"closed","title":"v0.5 — Beaconing & Messaging"}
{"closed_issues":1,"description":"Final polish, onboarding basics, all-platform store prep","due_on":null,"number":6,"open_issues":2,"state":"open","title":"v1.0 — Launch"}
{"closed_issues":0,"description":"Message threads UI, ACK read receipts","due_on":null,"number":7,"open_issues":0,"state":"closed","title":"v0.6 — Connection UI"}
{"closed_issues":0,"description":"Smart filtering, station profiles","due_on":null,"number":8,"open_issues":0,"state":"closed","title":"v0.7 — Android Background"}
{"closed_issues":2,"description":"iOS Cupertino polish, cross-platform parity pass","due_on":null,"number":9,"open_issues":0,"state":"closed","title":"v0.8 — Platform Parity"}
{"closed_issues":0,"description":"Viewport-adaptive APRS-IS server-side filter ... 50km minimum floor ... track history per station as map polylines, bounded by the time filter window. Map filters UI ... accessible from the map screen.","due_on":null,"number":10,"open_issues":0,"state":"open","title":"v0.10 — Map Experience"}
{"closed_issues":0,"description":"iOS background beaconing — background location + Live Activity","due_on":null,"number":11,"open_issues":0,"state":"open","title":"v0.9 — iOS Background"}
{"closed_issues":0,"description":"Filter by station type, symbol, distance and more. Named filter presets. Station profile view ...","due_on":null,"number":12,"open_issues":0,"state":"open","title":"v0.11 — Map Filters & Stations"}
{"closed_issues":0,"description":"Track history polylines, cluster markers at low zoom, object/item packet display, altitude in outgoing position packets.","due_on":null,"number":13,"open_issues":0,"state":"open","title":"v0.12 — Map Enhancement"}
{"closed_issues":0,"description":"Closed: onboarding work completed and merged as v0.12 (#38). Stale title retained. No issues filed here.","due_on":null,"number":14,"open_issues":0,"state":"closed","title":"v0.13 — Onboarding (stale)"}
{"closed_issues":0,"description":"Background notifications for incoming APRS messages, inline reply on Android and iOS, in-app banner overlay, per-channel notification preferences.","due_on":null,"number":15,"open_issues":0,"state":"open","title":"v0.11 — Notifications"}
{"closed_issues":5,"description":"Passcode stored in platform secure storage (Keychain/Keystore). APRS-IS server-side filter configuration UI.","due_on":null,"number":16,"open_issues":0,"state":"open","title":"v0.13 — Security & connectivity"}
{"closed_issues":0,"description":"Capture-always storage of cross-SSID messages. Addressee badges in thread view. Conversation-list grouping by base callsign. Per-SSID display and notification preferences.","due_on":null,"number":17,"open_issues":0,"state":"open","title":"v0.14 — Base-Callsign Message Matching"}
{"closed_issues":1,"description":"Profile and reduce background service battery drain. Packet processing efficiency review. Memory usage audit for large station counts. Evaluate SQLite/drift for station persistence.","due_on":null,"number":18,"open_issues":14,"state":"open","title":"v0.15 — Battery & Performance"}
{"closed_issues":1,"description":"Triage all open bug issues. Fix confirmed bugs prioritized by severity. Regression test pass across platforms.","due_on":null,"number":19,"open_issues":5,"state":"open","title":"v0.16 — Bug Triage"}
{"closed_issues":2,"description":"APRS group messages (CQ/QST/ALL/custom) and bulletins (BLN0-9 + named). Matcher precedence (ADR-055), group architecture (ADR-056), bulletin transmission model (ADR-057). Messaging tab restructured to Direct / Groups / Bulletins.","due_on":null,"number":20,"open_issues":0,"state":"closed","title":"v0.17 — Groups & Bulletins"}
```

### Raw `gh issue list --state open` index

| # | Title | Milestone |
|---|---|---|
| 43 | [F-META-002] Inject Clock abstraction — make time-dependent logic deterministic | v0.15 |
| 46 | [F-PLT-001] Android release signing config still on debug keystore | v1.0 |
| 47 | [F-PLT-002] iOS Live Activity App Group not created in Apple Developer portal | v1.0 |
| 49 | [F-EXT-004] Add lib/config/feature_flags.dart for staged features | v0.15 |
| 50 | [F-PLT-004] CI builds Linux-debug only — add Android/iOS/macOS/Windows matrix | v0.15 |
| 51 | [F-FLT-001] MapScreen.build() watches StationService — entire scaffold rebuilds on every packet | v0.15 |
| 52 | [F-EXT-001] No service-level test for BeaconingService | v0.15 |
| 53 | [F-EXT-003] Zero widget tests beyond smoke test | v0.15 |
| 54 | [F-PLT-003] flutter_local_notifications 3 majors behind (18 → 21) | v0.15 |
| 55 | [F-PLT-005] flutter_blue_plus 1 major behind (1.x → 2.x) | v0.15 |
| 56 | [F-ARCH-004] Double subscription to conn.lines in main.dart + ConnectionRegistry | v0.15 |
| 57 | [F-FLT-003] Selector used only in one place — establish codebase convention | v0.15 |
| 58 | [F-FLT-004] Two non-builder ListView in scrolling content surfaces | v0.15 |
| 59 | [F-EXT-005] No CallsignDisplay seam — shotgun risk for Contacts feature | v0.15 |
| 60 | [F-EXT-007] No test for TxService hierarchy routing (Serial > BLE > APRS-IS) | v0.15 |
| 61 | [F-FLT-006] Only 3 Semantics annotations in the codebase — a11y audit pass | v0.16 |
| 62 | [F-PLT-007] Adaptive widget usage inconsistent — risks non-native iOS feel | v0.16 |
| 63 | [F-PLT-008] No release-build CI — no ProGuard/R8/archive validation | v0.16 |
| 64 | [F-FLT-005] Filter bar in PacketLogScreen uses non-builder ListView | v0.16 |
| 65 | [F-FLT-008] MapScreen.build() is ~380 lines — extract helpers | v0.16 |
| 66 | [F-PLT-010] desugar_jdk_libs version drift — refresh when bumping notifications | v0.15 |
