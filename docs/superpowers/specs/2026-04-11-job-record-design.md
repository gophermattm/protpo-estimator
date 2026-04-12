# ProTPO Job Record — Design Spec

**Date:** 2026-04-11
**Status:** Approved (pending spec review)
**Author:** Matt Moore + Claude

---

## Summary

Extend ProTPO from a single-estimate tool into a lightweight CRM where customer, job, estimate, and version data are first-class entities. Today, every saved "project" is a single Firestore document containing an EstimatorState. This design layers a three-level hierarchy on top — Customer → Job → Estimate → Version — plus an activity timeline per job.

The goal is to capture the real shape of Matt's work: one customer may have several jobs, one job may have multiple estimate alternatives (TPO bid vs PVC alternate vs reduced scope), and each estimate accumulates a history of revisions sent to the customer. Activity records (notes, tasks, logged calls, system events) give each job a running timeline.

## Goals

1. Store customer information as a reusable entity, not a free-text field buried inside a project.
2. Let one job carry multiple estimate alternatives without re-typing customer/site data.
3. Preserve a frozen historical snapshot of every estimate state sent to a customer (auto on PDF export) plus user-initiated milestones.
4. Provide a running activity timeline per job: notes, tasks with due dates, simple call log entries, and auto-logged system events.
5. Keep the existing 3-panel Estimator screen, BOM engine, and export pipeline untouched. The feature extends the app *around* the working core.
6. Ship incrementally in nine phases. Each phase leaves the app in a usable state.

## Non-goals

- Multi-user collaboration, authentication, role-based access. The app remains single-user with permissive Firestore rules capped by payload size.
- Configurable status workflows, custom fields, or template customization. Ship a fixed workflow.
- File attachments (photos, signed PDFs), full email threading, or SMS integration. Activity timeline covers notes, tasks, calls, and system events only.
- Migration of existing `protpo_projects` data. Those docs remain in Firestore as a read-only backup but the app no longer reads them (cutover).
- Customer deduplication, fuzzy matching, or CRM-style lead scoring.
- A dashboard entry screen with metrics and cards. The estimator remains the app's main surface.

## User decisions (traceability)

These five decisions anchor the design. Any change to them should trigger a spec revision.

| # | Decision | Chosen | Implication |
|---|---|---|---|
| 1 | Hierarchy shape | **Both alternatives and versioning (C)** | Three levels: Job → Estimates → Versions |
| 2 | Customer reuse | **Separate entity (B)** | `protpo_customers` collection; jobs reference by ID |
| 3 | Version triggers | **Auto on export + manual (B)** | Snapshot written before every PDF export; manual button in estimator |
| 4 | Status + activity | **Simple workflow + Standard activity (A+2)** | 6-state linear workflow; notes + tasks + calls + system events |
| 5 | Existing data | **Cutover (C)** | No migration; `protpo_projects` left untouched |

## Data Model

### Firestore layout

```
protpo_customers/{customerId}
protpo_jobs/{jobId}
protpo_jobs/{jobId}/estimates/{estimateId}
protpo_jobs/{jobId}/estimates/{estimateId}/versions/{versionId}
protpo_jobs/{jobId}/activities/{activityId}
protpo_settings/{...}         (unchanged — company profile, logo)
protpo_projects/{...}         (frozen backup — app no longer reads)
```

Customers and jobs live at the top level because they are queried as lists. Estimates and versions are subcollections of their parent job because they are only ever accessed in that context. Activities are a subcollection of the job because the timeline is job-scoped.

### `protpo_customers/{customerId}`

| Field | Type | Notes |
|---|---|---|
| `name` | string | Company name or individual name. Required. |
| `customerType` | enum | One of: `Company`, `Insurance Carrier`, `Property Manager`, `General Contractor`, `Individual`. Required. |
| `primaryContactName` | string | Optional |
| `phone` | string | Optional |
| `email` | string | Optional |
| `mailingAddress` | string | Optional. Separate from job site address. |
| `notes` | string | Optional free text (preferred POC, payment terms). |
| `createdAt` | timestamp | Server-set on create |
| `updatedAt` | timestamp | Server-set on every write |

Document ID: UUID v4 generated client-side.

### `protpo_jobs/{jobId}`

| Field | Type | Notes |
|---|---|---|
| `customerId` | string | FK → `protpo_customers`. Required. |
| `customerName` | string | Denormalized for list-view render without a cross-doc lookup. |
| `jobName` | string | Short label, e.g., "Building A TPO Replacement". Required. |
| `siteAddress` | string | Address of the roof. Separate from customer mailing address. |
| `siteZip` | string | Drives climate zone lookup (existing logic in `project_info.dart`). |
| `status` | enum | One of: `Lead`, `Quoted`, `Won`, `InProgress`, `Complete`, `Lost`. Default `Lead`. |
| `activeEstimateId` | string \| null | Which estimate is the default "current bid". Null until first estimate is created. |
| `tags` | list\<string\> | Optional, empty by default. Reserved for later use. |
| `createdAt` | timestamp | Server-set |
| `updatedAt` | timestamp | Server-set |

Document ID: UUID v4 generated client-side.

### `protpo_jobs/{jobId}/estimates/{estimateId}`

| Field | Type | Notes |
|---|---|---|
| `name` | string | Estimate label, e.g., "TPO Original Bid", "PVC Alternate". Required. |
| `estimatorState` | map | The **mutable draft** — full serialized EstimatorState, same shape as today's `protpo_projects` documents. |
| `activeVersionId` | string \| null | The last version this draft was snapshotted from, for "has the draft diverged from the last snapshot" UI cues. |
| `totalArea` | number | Denormalized sum of building areas for the Estimates tab list. |
| `totalValue` | number | Denormalized total project value (materials + labor) for the Estimates tab list. |
| `buildingCount` | int | Denormalized building count for the Estimates tab list. |
| `createdAt` | timestamp | Server-set |
| `updatedAt` | timestamp | Server-set on every draft edit (autosave) |

Document ID: UUID v4 generated client-side.

**Key design decision:** the estimate document holds the mutable draft inline. The versions subcollection holds frozen historical snapshots. When the estimator autosaves, it writes to the estimate's `estimatorState` field. When the user takes a snapshot (manual or on export), a copy is written to `versions/{versionId}`.

### `protpo_jobs/{jobId}/estimates/{estimateId}/versions/{versionId}`

| Field | Type | Notes |
|---|---|---|
| `label` | string | Human-readable identifier: "v1 — initial walkthrough", "Export 2026-04-15 14:32" |
| `source` | enum | `manual` (save-as-version button) or `export` (auto-snapshotted before a PDF export) |
| `estimatorState` | map | **Frozen** serialized EstimatorState at the moment of snapshot. Immutable. |
| `createdAt` | timestamp | Server-set |
| `createdBy` | string | Estimator name read from the company profile in `protpo_settings` |

Document ID: UUID v4 generated client-side. Versions are immutable — Firestore rules reject updates.

### `protpo_jobs/{jobId}/activities/{activityId}`

| Field | Type | Notes |
|---|---|---|
| `type` | enum | `note`, `task`, `call`, `system` |
| `timestamp` | timestamp | When the event occurred. User-settable for backdated entries; defaults to now. |
| `author` | string | Estimator name from company profile |
| `body` | string | Free text. Notes: body is the content. Tasks: body is the task description. Calls: body is the call summary. System: body is a human-readable event description. |
| `taskDueDate` | timestamp? | Tasks only |
| `taskCompleted` | bool? | Tasks only |
| `taskCompletedAt` | timestamp? | Tasks only |
| `callDirection` | enum? | Calls only: `in` or `out` |
| `callDurationMinutes` | int? | Calls only, optional |
| `systemEventKind` | string? | System only: `status_changed`, `version_saved`, `export_created`, `job_created`, `estimate_created` |
| `systemEventData` | map? | System only: structured payload, e.g., `{ "from": "Lead", "to": "Quoted" }` |

Activities are append-only. The only mutable path is a task's `taskCompleted` (and the corresponding `taskCompletedAt`) toggle. Firestore rules enforce this.

### Relationships

```
Customer 1 ─── *  Job  1 ─── *  Estimate  1 ─── *  Version
                   └───────── *  Activity
```

## UI & Navigation

### Screen inventory

| Screen | Status | Purpose |
|---|---|---|
| Estimator Screen | Modified (small) | Same 3-panel layout plus a new job context ribbon at top |
| Job List Sheet | Replaces `project_list_screen.dart` | Modal bottom sheet listing all jobs |
| Job Detail Screen | New, full-screen | Tabs: Overview / Estimates / Activity |
| New Job Flow | New, modal chain | Customer picker → job form → empty estimator |
| Settings Dialog | Extended | New "Customers" tab added to existing dialog |

Customers are managed inside the existing Settings Dialog rather than a new top-level screen. They are rare-input entities (same cadence as the company profile), so a settings tab is sufficient.

### Primary flows

**Open an existing job** (replaces today's Open Project action):

```
AppBar "Open" button
    ↓
Job List Sheet (modal bottom sheet)
    ├── Tap a job card → push Job Detail Screen
    └── "+ New Job" button → New Job Flow
```

**Work on an estimate:**

```
Job Detail Screen → Estimates tab
    ├── Tap "Load into estimator" on an estimate →
    │     hydrate EstimatorState from estimate.estimatorState →
    │     pop back to Estimator Screen with job context set
    └── "+ New Estimate" → creates new estimate with empty state → loads it
```

**Load a historical version** (explicit, destructive action with confirmation):

```
Job Detail Screen → Estimates tab → expand estimate → versions list
    └── Tap "Restore this version" →
          confirmation dialog ("will overwrite current draft — continue?") →
          copy version.estimatorState into estimate.estimatorState →
          load into estimator
```

**Save a version** (two paths):

- **Auto:** PDF export path calls `FirestoreService.saveVersion(jobId, estimateId, source: 'export', label: 'Export YYYY-MM-DD HH:MM')` before writing the PDF. The resulting snapshot is tied to the exact state the customer received.
- **Manual:** A "Save as version" button in the estimator AppBar prompts for a label and writes a snapshot on demand. If the user leaves the label empty and confirms, the label defaults to `Manual snapshot YYYY-MM-DD HH:MM`.

**Change job status:**

```
Job Detail → Overview tab → status chip → tap → status picker
    → on change, FirestoreService writes an activity record of type
      'system' with eventKind='status_changed' and data {from, to}
```

### Screen layouts (described)

**Job List Sheet**

- Rounded-top modal bottom sheet matching the current project list visual language
- Row content: job name (bold), customer name, status chip, site address (small), last-activity timestamp
- Sort: most-recently-active first
- Filter chips: All / Active (`Lead`+`Quoted`+`Won`+`InProgress`) / Archived (`Complete`+`Lost`)
- Search box filters by job name or customer name
- "+ New Job" FAB in corner

**Job Detail Screen** (full screen, push navigation, AppBar has back button)

- AppBar: job name + customer subtitle + status chip + overflow menu (duplicate, archive, delete)
- TabBar: Overview / Estimates / Activity

*Overview tab:*
- Customer card (name, contact, phone, email, tap-to-call / tap-to-email) with "Change customer" action
- Job details card (job name, site address, site zip, created/updated dates)
- Status + status picker
- Key metrics: total area, total value, estimate count, activity count

*Estimates tab:*
- List of estimate cards. Each card shows:
  - Estimate name (editable via pencil icon)
  - Area / total value / last modified
  - "Active" badge if this is the job's `activeEstimateId`
  - Expand arrow revealing version history (list of frozen snapshots with labels, dates, and "Restore" buttons)
  - Action buttons: Load into estimator / Duplicate / Delete / Save as version
- "+ New Estimate" button at bottom

*Activity tab:*
- Vertical timeline, newest first
- FAB with menu: Add Note / Add Task / Log Call
- Note cards: author, timestamp, body, edit/delete on owned entries
- Task cards: checkbox (toggles completed), body, due date, overdue highlight
- Call cards: direction arrow, contact, duration, summary
- System cards: muted style, icon per event kind, auto-generated

**New Job Flow** (modal chain, not full screens — keeps context on the job list)

1. *Customer picker modal:* search existing customers, tap to pick, or "+ New Customer" opens an inline form
2. *New job form modal:* job name, site address, site zip (climate zone auto-populates), initial status (defaults to `Lead`)
3. *Create:* writes customer (if new) + job + first estimate with empty state + system activity `job_created` → loads estimator with job context set

**Settings Dialog "Customers" tab**

- List of customers; add / edit / delete operations
- Deleting a customer with jobs attached is blocked — the dialog shows which jobs reference this customer and requires the user to reassign or delete those jobs first

### Estimator screen modifications (small but visible)

The only change to the working estimator screen is a new **job context ribbon** above the existing AppBar:

```
[Customer Name] ▸ [Job Name] ▸ [Estimate Name] (v3 draft)   [Save as version]
```

- Tap the ribbon to navigate to Job Detail for the active job
- Save-as-version button lives next to it
- When no job is loaded (fresh state), the ribbon shows "No job loaded — tap to open"

The existing **Save** button keeps working but now writes to `protpo_jobs/{id}/estimates/{id}.estimatorState`. The existing **Open** button becomes the entry point to the Job List Sheet. No other changes to the estimator UI, BOM rendering, left panel, center panel, or right panel.

### Responsive behavior

Job List Sheet and Job Detail Screen use the existing `isDesktop` / `isTablet` / `isMobile` breakpoints from `estimator_screen.dart`. On mobile:

- Job List Sheet takes full height
- Job Detail tabs stack cards vertically
- The job context ribbon shrinks to `[Job] ▸ [Estimate]` (customer drops off)

## State Management (Riverpod)

The existing `estimatorProvider` is unchanged in structure — it remains the mutable draft that the three estimator panels read from. New providers sit alongside it:

| Provider | Kind | Purpose |
|---|---|---|
| `customersListProvider` | `StreamProvider<List<Customer>>` | Live list for Settings Customers tab and new-job customer picker |
| `customerProvider.family(id)` | `FutureProvider<Customer?>` | Single customer lookup |
| `jobsListProvider` | `StreamProvider<List<JobSummary>>` | Live list for Job List Sheet |
| `jobProvider.family(jobId)` | `StreamProvider<Job?>` | Job Detail header + overview |
| `activeJobIdProvider` | `StateProvider<String?>` | Which job is currently loaded into the estimator |
| `activeEstimateIdProvider` | `StateProvider<String?>` | Which estimate within the active job |
| `estimatesForJobProvider.family(jobId)` | `StreamProvider<List<Estimate>>` | Estimates tab list |
| `versionsForEstimateProvider.family((jobId, estId))` | `FutureProvider<List<EstimateVersion>>` | Version history under each estimate card |
| `activitiesForJobProvider.family(jobId)` | `StreamProvider<List<Activity>>` | Activity tab timeline |

**Save path change:** today's autosave writes to `protpo_projects/{id}`. New autosave writes to `protpo_jobs/{activeJobId}/estimates/{activeEstimateId}.estimatorState`. The `_maybeAutosave()` method in `estimator_screen.dart` is rerouted through the active-estimate IDs. **Autosave is a no-op when either `activeJobId` or `activeEstimateId` is null** — this happens on fresh app launches before any job is opened, and on the cutover transition. The estimator's existing `_hasUnsavedChanges` flag remains, but for a null-active state the user is expected to open or create a job first. The context ribbon surfaces this state ("No job loaded — tap to open").

**Load path change:** "Load into estimator" on an estimate reads `estimate.estimatorState`, calls `estimatorProvider.notifier.loadState(...)` (the existing method), and sets `activeJobId` + `activeEstimateId`. The existing `_syncFromState()` in `left_panel.dart` fires through the `ref.listen` hooks added in the April 8 session.

## Security Rules

Add the following to `firestore.rules`. Same philosophy as the existing rules: the client is unauthenticated, so writes are gated by required-fields and payload size, with default-deny elsewhere.

```
match /protpo_customers/{docId} {
  allow read: if true;
  allow create, update: if
    request.resource.data.keys().hasAny(['name', 'customerType']) &&
    request.resource.size() < 50 * 1024;
  allow delete: if true;
}

match /protpo_jobs/{jobId} {
  allow read: if true;
  allow create, update: if
    request.resource.data.keys().hasAny(['jobName', 'customerId']) &&
    request.resource.size() < 100 * 1024;
  allow delete: if true;

  match /estimates/{estimateId} {
    allow read: if true;
    // Estimates carry full EstimatorState — same 900KB cap as today's protpo_projects
    allow create, update: if request.resource.size() < 900 * 1024;
    allow delete: if true;

    match /versions/{versionId} {
      allow read: if true;
      allow create: if request.resource.size() < 900 * 1024;
      // Versions are immutable — no updates permitted
      allow update: if false;
      allow delete: if true;
    }
  }

  match /activities/{activityId} {
    allow read: if true;
    allow create: if request.resource.size() < 50 * 1024;
    // Only task activities can be updated (completion toggle)
    allow update: if request.resource.data.type == 'task' &&
                     request.resource.size() < 50 * 1024;
    allow delete: if true;
  }
}
```

Existing `qxo_auth` and `qxo_price_cache` rules stay fully denied to clients. Existing `protpo_projects` and `protpo_settings` rules are unchanged.

## Implementation Phases

Nine phases. Each phase ends in a shippable, tested state, but note that *user-visible change* only happens at the cutover bundle and beyond — see "User-visible milestones" below.

| # | Phase | What ships | Stopping point rationale |
|---|---|---|---|
| 1 | Data layer foundation | Models (Customer, Job, Estimate, EstimateVersion, Activity), serializers, `FirestoreService` CRUD, rules deployed | No UI; fully tested in isolation |
| 2 | State management | New Riverpod providers; estimator load/save rerouted through active estimate (wired but not invoked from UI yet) | Verified by unit test that creates a job + estimate + loads into estimator state |
| 3 | Customer management | Settings dialog Customers tab with full CRUD | You can manage customers; jobs still use old screens |
| 4 | Job list + job detail shell | New `JobListSheet` and `JobDetailScreen` with Overview tab exist alongside the old `ProjectListScreen` (not yet replacing it). No cutover yet — existing Open button still opens the old project list. | Internal milestone; new screens can be tested in isolation by opening them from a debug route or inline menu |
| 5 | Estimates tab + load/save | Estimates tab working; new estimate creation; load-into-estimator wiring; estimator job-context ribbon. Still no user-facing cutover — this is still reachable only via Phase 4's debug entry. | Internal milestone; full load/save path exercisable |
| 6 | Versions | Manual save-as-version button; auto on export; version list; restore with confirmation | Internal milestone |
| 7 | Activity timeline | Activity tab; add note / task / call; auto system events | Internal milestone |
| 8 | New job flow + cutover | Customer picker modal chain. This phase performs the cutover: the AppBar "Open" button now opens `JobListSheet`, `project_list_screen.dart` is deleted, and the old save path to `protpo_projects/{id}` is removed. | **Cutover point. Phases 4-8 must ship to production as a bundle** — this is the first phase that changes what the user sees |
| 9 | Polish | Empty states; offline handling; delete/archive cascades; mobile responsive tweaks | Production-ready |

### User-visible milestones

Not every phase corresponds to a user-visible change. The phases above are optimized for TDD and review granularity. Actual user-visible moments:

| Milestone | Phase bundle | What the user sees |
|---|---|---|
| **M0 — Silent groundwork** | Phases 1-3 | No change. Customers tab in Settings may ship early as it doesn't depend on the cutover. |
| **M1 — Cutover to job system** | Phases 4-8 shipped together | Open button now opens Jobs, can create customers + jobs + estimates, load into estimator, save versions manually, auto-snapshot on export, activity timeline works. This is the minimum viable first release to production. |
| **M2 — Polish** | Phase 9 | Empty states, offline, mobile tweaks |

**Phases 4-7 are not individually shippable to production** because the old Open button still works in parallel and the new flow can't be reached by normal navigation. They are internal stopping points for code review and testing, reachable only via a debug route until Phase 8 performs the cutover.

## Error Handling

- **Firestore writes:** try/catch around service calls, user-facing `AppSnackbar.error(...)`. Matches the existing pattern in `estimator_screen.dart`. The Firestore SDK's built-in offline queue handles transient network failures.
- **Load failures:** if a job or estimate cannot be loaded (corrupt doc, missing reference), show an empty-state card with a "Retry" button. Do not crash the screen. Log to debug console.
- **Version restore (destructive):** confirmation dialog required. Wording: *"Restoring 'v2 — before parapet change' will overwrite your current draft. This cannot be undone. Continue?"*
- **Customer delete with jobs attached:** blocked. The dialog lists the referencing jobs. User must reassign or delete those jobs first.
- **Concurrent edit of the same estimate from two tabs:** Firestore's last-write-wins is acceptable for a single-user app. The existing `_hasUnsavedChanges` + `beforeunload` warning still applies.
- **New job flow partial failure:** if the customer is created but the job write fails, the customer stays. User can retry the job without re-entering customer data. No cross-doc transaction wrapping; the tradeoff is intentional for simpler code.

## Testing

- **Unit tests (`test/models/`)**: JSON round-trip for Customer, Job, Estimate, EstimateVersion, Activity. Enum parsing, nullable field handling, default values.
- **Unit tests (`test/services/firestore_service_test.dart`)**: CRUD for each entity. Cover create → read → update → delete, list queries, subcollection scoping, denormalized field writes.
- **Unit tests (`test/providers/`)**: `activeJobProvider` loads correctly when `activeJobIdProvider` changes; `estimatorProvider.loadState` from `estimate.estimatorState` round-trips without data loss.
- **Widget tests (`test/widgets/`)**: `JobDetailScreen` renders each tab correctly with mock data; status picker updates state; new job flow reaches the estimator.
- **Integration test**: full flow — create customer → create job → add estimate → edit state → save as version → export PDF (verifies auto-snapshot) → load a second estimate → restore the first version → verify state matches.

The `tdd-guide` skill referenced in `CLAUDE.md` should drive Phase 1 (data layer) especially, since it underpins every later phase.

## Risks and Open Decisions

- **Estimate document size:** serialized `estimatorState` is roughly 50-200KB. Ten versions per estimate puts each estimate hierarchy in the 1-4MB range, well under Firestore's per-document and subcollection limits but worth watching as customers accumulate history.
- **Active job persistence across sessions:** the last-opened job should auto-reopen on app launch. Store `lastJobId` and `lastEstimateId` in `protpo_settings`. Low cost, high UX value. Included in Phase 5.
- **Archiving vs deleting jobs:** both are supported. Deleting cascades to estimates, versions, and activities — Firestore does not cascade automatically, so `FirestoreService.deleteJob()` performs the cascade via a helper. Archiving is simply `status = Complete` or `status = Lost`, filtered out of the default job list view.
- **Cutover ambiguity:** the spec calls for a clean cutover, but the running app on `tpo-pro-245d1.web.app` currently reads from `protpo_projects`. Shipping Phase 4 switches the read path. Users of the production app (just Matt) will need to re-create any in-progress jobs in the new system. Acceptable given the single-user context; surfaced here for awareness.

## Appendix — Summary of what does not change

- Estimator screen 3-panel layout (left/center/right)
- BOM calculator, fastening schedules, R-value engine
- QXO pricing integration and confidence scoring
- PDF export pipeline (export_service + sub_instructions_builder + platform_utils)
- Tapered insulation drain distance / board schedule / watershed rendering
- Labor system, margin system, validation engine
- Company profile + logo in `protpo_settings`
- `qxo_auth` and `qxo_price_cache` Firestore collections and their locked-down rules
- `firebase.json`, `.firebaserc`, `main.dart` Firebase initialization
