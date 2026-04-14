# Job Record Phase 7 — Activity Timeline Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the Activity placeholder tab in Job Detail with a working timeline that displays notes, tasks, calls, and system events, plus dialogs for adding notes, tasks, and logging calls.

**Architecture:** A single new `_ActivityTab` widget in `job_detail_screen.dart` replaces the Activity `_PlaceholderTab`. It watches `activitiesForJobProvider(jobId)` for a live stream of activities and renders each by type using private builder methods. A FAB opens a menu for Add Note / Add Task / Log Call, each opening a purpose-built dialog. Task cards have a checkbox for completion toggle via `FirestoreService.updateTaskCompletion`. System events are rendered in a muted style with type-specific icons.

**Tech Stack:** Flutter 3.35+, Riverpod, cloud_firestore (existing). No new dependencies. No new files.

**Internal milestone.** Still reachable via long-press on Open. Phase 8 performs the cutover.

---

## File Structure

### Files to modify

| Path | Change |
|---|---|
| `lib/screens/job_detail_screen.dart` | Replace the Activity `_PlaceholderTab` with `_ActivityTab`. Add `_AddNoteDialog`, `_AddTaskDialog`, `_LogCallDialog` private widget classes. |

### Files NOT touched

- All other files — everything needed already exists from Phases 1-6

---

## Task 1: Build the Activity tab

**Files:**
- Modify: `lib/screens/job_detail_screen.dart`

### Step 1.1 — Replace the Activity placeholder in TabBarView

- [ ] **Find** the TabBarView children in `_JobDetailBodyState.build()`. Replace:

```dart
          _PlaceholderTab(
              icon: Icons.timeline,
              label: 'Activity',
              message: 'Activity timeline coming in Phase 7'),
```

With:

```dart
          _ActivityTab(job: job),
```

### Step 1.2 — Add the _ActivityTab widget and its dialogs

- [ ] **Add** the following widgets to `job_detail_screen.dart`, placing them BEFORE the `_PlaceholderTab` class (which is no longer referenced and can optionally be deleted, but leaving it is harmless):

```dart
// ══════════════════════════════════════════════════════════════════════════════
// ACTIVITY TAB
// ══════════════════════════════════════════════════════════════════════════════

class _ActivityTab extends ConsumerWidget {
  final Job job;
  const _ActivityTab({required this.job});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activitiesAsync = ref.watch(activitiesForJobProvider(job.id));

    return Stack(children: [
      activitiesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Text('Failed to load activities: $e',
              style: TextStyle(color: AppTheme.error)),
        ),
        data: (activities) {
          if (activities.isEmpty) {
            return Center(
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                Icon(Icons.timeline, size: 40, color: AppTheme.textMuted),
                const SizedBox(height: 8),
                Text('No activity yet',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: AppTheme.textMuted)),
                const SizedBox(height: 4),
                Text('Notes, tasks, and calls will appear here.',
                    style: TextStyle(
                        fontSize: 12, color: AppTheme.textMuted)),
              ]),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
            itemCount: activities.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, i) =>
                _buildActivityCard(context, ref, activities[i]),
          );
        },
      ),

      // FAB with menu
      Positioned(
        right: 16,
        bottom: 16,
        child: PopupMenuButton<String>(
          onSelected: (v) {
            if (v == 'note') _showAddNote(context);
            if (v == 'task') _showAddTask(context);
            if (v == 'call') _showLogCall(context);
          },
          itemBuilder: (_) => [
            const PopupMenuItem(
                value: 'note',
                child: Row(children: [
                  Icon(Icons.note_add, size: 18),
                  SizedBox(width: 10),
                  Text('Add Note'),
                ])),
            const PopupMenuItem(
                value: 'task',
                child: Row(children: [
                  Icon(Icons.add_task, size: 18),
                  SizedBox(width: 10),
                  Text('Add Task'),
                ])),
            const PopupMenuItem(
                value: 'call',
                child: Row(children: [
                  Icon(Icons.phone, size: 18),
                  SizedBox(width: 10),
                  Text('Log Call'),
                ])),
          ],
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTheme.primary,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                    color: AppTheme.primary.withValues(alpha: 0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 3)),
              ],
            ),
            child: const Icon(Icons.add, color: Colors.white, size: 22),
          ),
        ),
      ),
    ]);
  }

  Widget _buildActivityCard(
      BuildContext context, WidgetRef ref, Activity activity) {
    switch (activity.type) {
      case ActivityType.note:
        return _buildNoteCard(context, activity);
      case ActivityType.task:
        return _buildTaskCard(context, ref, activity);
      case ActivityType.call:
        return _buildCallCard(context, activity);
      case ActivityType.system:
        return _buildSystemCard(activity);
    }
  }

  // ── Note card ──────────────────────────────────────────────────────────

  Widget _buildNoteCard(BuildContext context, Activity activity) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.sticky_note_2_outlined,
              size: 14, color: const Color(0xFF6366F1)),
          const SizedBox(width: 6),
          Text('Note',
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF6366F1))),
          const Spacer(),
          Text(_timeAgo(activity.timestamp),
              style: TextStyle(fontSize: 10, color: AppTheme.textMuted)),
          const SizedBox(width: 4),
          _deleteButton(context, activity),
        ]),
        const SizedBox(height: 6),
        Text(activity.body, style: const TextStyle(fontSize: 13)),
        if (activity.author.isNotEmpty && activity.author != 'system')
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('— ${activity.author}',
                style: TextStyle(
                    fontSize: 10,
                    fontStyle: FontStyle.italic,
                    color: AppTheme.textMuted)),
          ),
      ]),
    );
  }

  // ── Task card ──────────────────────────────────────────────────────────

  Widget _buildTaskCard(
      BuildContext context, WidgetRef ref, Activity activity) {
    final completed = activity.taskCompleted == true;
    final overdue = !completed &&
        activity.taskDueDate != null &&
        activity.taskDueDate!.isBefore(DateTime.now());

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: overdue
            ? AppTheme.error.withValues(alpha: 0.04)
            : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: overdue
              ? AppTheme.error.withValues(alpha: 0.3)
              : AppTheme.border,
        ),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Checkbox
        GestureDetector(
          onTap: () {
            FirestoreService.instance.updateTaskCompletion(
                job.id, activity.id, !completed);
          },
          child: Container(
            width: 22,
            height: 22,
            margin: const EdgeInsets.only(top: 2, right: 10),
            decoration: BoxDecoration(
              color: completed
                  ? AppTheme.accent.withValues(alpha: 0.1)
                  : Colors.white,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: completed ? AppTheme.accent : AppTheme.border,
                width: 2,
              ),
            ),
            child: completed
                ? Icon(Icons.check, size: 14, color: AppTheme.accent)
                : null,
          ),
        ),
        // Content
        Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            Row(children: [
              Text('Task',
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: overdue
                          ? AppTheme.error
                          : const Color(0xFFF59E0B))),
              const Spacer(),
              if (activity.taskDueDate != null)
                Text(
                  'Due ${_dateFmt.format(activity.taskDueDate!)}',
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                      color: overdue
                          ? AppTheme.error
                          : AppTheme.textMuted),
                ),
              const SizedBox(width: 4),
              _deleteButton(context, activity),
            ]),
            const SizedBox(height: 4),
            Text(
              activity.body,
              style: TextStyle(
                fontSize: 13,
                decoration: completed
                    ? TextDecoration.lineThrough
                    : null,
                color: completed
                    ? AppTheme.textMuted
                    : AppTheme.textPrimary,
              ),
            ),
            if (completed && activity.taskCompletedAt != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                    'Completed ${_dateFmt.format(activity.taskCompletedAt!)}',
                    style: TextStyle(
                        fontSize: 10, color: AppTheme.accent)),
              ),
          ]),
        ),
      ]),
    );
  }

  // ── Call card ──────────────────────────────────────────────────────────

  Widget _buildCallCard(BuildContext context, Activity activity) {
    final isIncoming = activity.callDirection == CallDirection.in_;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(
            isIncoming ? Icons.call_received : Icons.call_made,
            size: 14,
            color: const Color(0xFF10B981),
          ),
          const SizedBox(width: 6),
          Text(isIncoming ? 'Incoming Call' : 'Outgoing Call',
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF10B981))),
          if (activity.callDurationMinutes != null) ...[
            const SizedBox(width: 8),
            Text('${activity.callDurationMinutes} min',
                style: TextStyle(
                    fontSize: 10, color: AppTheme.textMuted)),
          ],
          const Spacer(),
          Text(_timeAgo(activity.timestamp),
              style: TextStyle(fontSize: 10, color: AppTheme.textMuted)),
          const SizedBox(width: 4),
          _deleteButton(context, activity),
        ]),
        if (activity.body.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(activity.body, style: const TextStyle(fontSize: 13)),
        ],
      ]),
    );
  }

  // ── System event card ──────────────────────────────────────────────────

  Widget _buildSystemCard(Activity activity) {
    IconData icon;
    switch (activity.systemEventKind) {
      case 'status_changed':
        icon = Icons.swap_horiz;
        break;
      case 'version_saved':
        icon = Icons.bookmark_added;
        break;
      case 'version_restored':
        icon = Icons.restore;
        break;
      case 'export_created':
        icon = Icons.picture_as_pdf;
        break;
      case 'job_created':
        icon = Icons.work;
        break;
      case 'estimate_created':
        icon = Icons.description;
        break;
      default:
        icon = Icons.info_outline;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(children: [
        Icon(icon, size: 14, color: AppTheme.textMuted),
        const SizedBox(width: 8),
        Expanded(
          child: Text(activity.body,
              style: TextStyle(
                  fontSize: 11, color: AppTheme.textSecondary)),
        ),
        Text(_timeAgo(activity.timestamp),
            style: TextStyle(fontSize: 10, color: AppTheme.textMuted)),
      ]),
    );
  }

  // ── Helpers ─────────────────────────────────────────────────────────────

  Widget _deleteButton(BuildContext context, Activity activity) {
    return GestureDetector(
      onTap: () async {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Delete?', style: TextStyle(fontSize: 16)),
            content: const Text('Delete this activity entry?',
                style: TextStyle(fontSize: 13)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.error),
                child: const Text('Delete'),
              ),
            ],
          ),
        );
        if (confirmed == true) {
          await FirestoreService.instance
              .deleteActivity(job.id, activity.id);
        }
      },
      child: Icon(Icons.close, size: 14, color: AppTheme.textMuted),
    );
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return _dateFmt.format(dt);
  }

  // ── Add dialogs ─────────────────────────────────────────────────────────

  void _showAddNote(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => _AddNoteDialog(jobId: job.id),
    );
  }

  void _showAddTask(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => _AddTaskDialog(jobId: job.id),
    );
  }

  void _showLogCall(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => _LogCallDialog(jobId: job.id),
    );
  }
}

// ── Add Note Dialog ──────────────────────────────────────────────────────────

class _AddNoteDialog extends ConsumerStatefulWidget {
  final String jobId;
  const _AddNoteDialog({required this.jobId});

  @override
  ConsumerState<_AddNoteDialog> createState() => _AddNoteDialogState();
}

class _AddNoteDialogState extends ConsumerState<_AddNoteDialog> {
  final _bodyCtrl = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _bodyCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final body = _bodyCtrl.text.trim();
    if (body.isEmpty) return;

    setState(() => _saving = true);
    try {
      final profile = ref.read(companyProfileProvider);
      final activity = Activity(
        id: '',
        type: ActivityType.note,
        timestamp: DateTime.now(),
        author: profile.companyName.isNotEmpty
            ? profile.companyName
            : 'ProTPO',
        body: body,
      );
      await FirestoreService.instance
          .createActivity(widget.jobId, activity);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to add note: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(children: [
        Icon(Icons.note_add, size: 20, color: AppTheme.primary),
        const SizedBox(width: 8),
        const Text('Add Note', style: TextStyle(fontSize: 16)),
      ]),
      content: SizedBox(
        width: 400,
        child: TextField(
          controller: _bodyCtrl,
          autofocus: true,
          maxLines: 4,
          decoration: const InputDecoration(
            labelText: 'Note',
            isDense: true,
            hintText: 'Enter your note...',
            alignLabelWithHint: true,
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton.icon(
          onPressed: _saving ? null : _save,
          icon: _saving
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.add, size: 16),
          label: const Text('Add Note'),
        ),
      ],
    );
  }
}

// ── Add Task Dialog ──────────────────────────────────────────────────────────

class _AddTaskDialog extends ConsumerStatefulWidget {
  final String jobId;
  const _AddTaskDialog({required this.jobId});

  @override
  ConsumerState<_AddTaskDialog> createState() => _AddTaskDialogState();
}

class _AddTaskDialogState extends ConsumerState<_AddTaskDialog> {
  final _bodyCtrl = TextEditingController();
  DateTime? _dueDate;
  bool _saving = false;

  @override
  void dispose() {
    _bodyCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDueDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 1)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() => _dueDate = picked);
    }
  }

  Future<void> _save() async {
    final body = _bodyCtrl.text.trim();
    if (body.isEmpty) return;

    setState(() => _saving = true);
    try {
      final profile = ref.read(companyProfileProvider);
      final activity = Activity(
        id: '',
        type: ActivityType.task,
        timestamp: DateTime.now(),
        author: profile.companyName.isNotEmpty
            ? profile.companyName
            : 'ProTPO',
        body: body,
        taskDueDate: _dueDate,
        taskCompleted: false,
      );
      await FirestoreService.instance
          .createActivity(widget.jobId, activity);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to add task: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(children: [
        Icon(Icons.add_task, size: 20, color: AppTheme.primary),
        const SizedBox(width: 8),
        const Text('Add Task', style: TextStyle(fontSize: 16)),
      ]),
      content: SizedBox(
        width: 400,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: _bodyCtrl,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Task description',
              isDense: true,
              hintText: 'e.g. Call adjuster, Send revised estimate',
            ),
          ),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: _pickDueDate,
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                border: Border.all(color: AppTheme.border),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(children: [
                Icon(Icons.calendar_today,
                    size: 16, color: AppTheme.textMuted),
                const SizedBox(width: 8),
                Text(
                  _dueDate != null
                      ? 'Due: ${_dateFmt.format(_dueDate!)}'
                      : 'Set due date (optional)',
                  style: TextStyle(
                    fontSize: 13,
                    color: _dueDate != null
                        ? AppTheme.textPrimary
                        : AppTheme.textMuted,
                  ),
                ),
                if (_dueDate != null) ...[
                  const Spacer(),
                  GestureDetector(
                    onTap: () => setState(() => _dueDate = null),
                    child: Icon(Icons.close,
                        size: 14, color: AppTheme.textMuted),
                  ),
                ],
              ]),
            ),
          ),
        ]),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton.icon(
          onPressed: _saving ? null : _save,
          icon: _saving
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.add, size: 16),
          label: const Text('Add Task'),
        ),
      ],
    );
  }
}

// ── Log Call Dialog ──────────────────────────────────────────────────────────

class _LogCallDialog extends ConsumerStatefulWidget {
  final String jobId;
  const _LogCallDialog({required this.jobId});

  @override
  ConsumerState<_LogCallDialog> createState() => _LogCallDialogState();
}

class _LogCallDialogState extends ConsumerState<_LogCallDialog> {
  final _summaryCtrl = TextEditingController();
  final _durationCtrl = TextEditingController();
  CallDirection _direction = CallDirection.out;
  bool _saving = false;

  @override
  void dispose() {
    _summaryCtrl.dispose();
    _durationCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final profile = ref.read(companyProfileProvider);
      final duration = int.tryParse(_durationCtrl.text.trim());
      final activity = Activity(
        id: '',
        type: ActivityType.call,
        timestamp: DateTime.now(),
        author: profile.companyName.isNotEmpty
            ? profile.companyName
            : 'ProTPO',
        body: _summaryCtrl.text.trim(),
        callDirection: _direction,
        callDurationMinutes: duration,
      );
      await FirestoreService.instance
          .createActivity(widget.jobId, activity);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to log call: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(children: [
        Icon(Icons.phone, size: 20, color: AppTheme.primary),
        const SizedBox(width: 8),
        const Text('Log Call', style: TextStyle(fontSize: 16)),
      ]),
      content: SizedBox(
        width: 400,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          // Direction toggle
          Row(children: [
            Text('Direction:',
                style: TextStyle(
                    fontSize: 12, color: AppTheme.textSecondary)),
            const SizedBox(width: 12),
            SegmentedButton<CallDirection>(
              segments: const [
                ButtonSegment(
                    value: CallDirection.out,
                    label: Text('Outgoing', style: TextStyle(fontSize: 12)),
                    icon: Icon(Icons.call_made, size: 14)),
                ButtonSegment(
                    value: CallDirection.in_,
                    label: Text('Incoming', style: TextStyle(fontSize: 12)),
                    icon: Icon(Icons.call_received, size: 14)),
              ],
              selected: {_direction},
              onSelectionChanged: (s) =>
                  setState(() => _direction = s.first),
              style: SegmentedButton.styleFrom(
                visualDensity: VisualDensity.compact,
              ),
            ),
          ]),
          const SizedBox(height: 12),
          TextField(
            controller: _durationCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Duration (minutes)',
              isDense: true,
              hintText: 'Optional',
              prefixIcon: Icon(Icons.timer, size: 18),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _summaryCtrl,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Call summary',
              isDense: true,
              hintText: 'What was discussed?',
              alignLabelWithHint: true,
            ),
          ),
        ]),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton.icon(
          onPressed: _saving ? null : _save,
          icon: _saving
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.phone, size: 16),
          label: const Text('Log Call'),
        ),
      ],
    );
  }
}
```

### Step 1.3 — Verify it compiles

- [ ] **Run:** `flutter analyze lib/screens/job_detail_screen.dart`

Expected: No new errors.

### Step 1.4 — Verify tests still pass

- [ ] **Run:** `flutter test test/models/ test/providers/`

Expected: All 63 tests pass.

### Step 1.5 — Commit

- [ ] **Run:**

```bash
git add lib/screens/job_detail_screen.dart
git commit -m "feat(ui): build Activity tab with notes, tasks, calls, system events

Replaces the Activity placeholder in Job Detail with _ActivityTab.

Timeline:
- Notes: author, body, timestamp, delete
- Tasks: checkbox toggle via updateTaskCompletion, due date with
  overdue highlight, strikethrough on completion
- Calls: direction icon (in/out), duration, summary
- System events: muted style, type-specific icons for status_changed,
  version_saved, version_restored, export_created, job_created,
  estimate_created

FAB with menu: Add Note / Add Task / Log Call, each opening a
purpose-built dialog. Tasks support optional due date via date picker.
Calls support direction toggle (SegmentedButton) and optional duration.

All entries deletable with confirmation. _timeAgo helper shows
relative timestamps (just now, Xm ago, Xh ago, Xd ago, or date).

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: Final verification and push

**Files:** none modified

### Step 2.1 — Run all tests

- [ ] **Run:** `flutter test test/models/ test/providers/`

Expected: All 63 tests pass.

### Step 2.2 — Run flutter analyze

- [ ] **Run:** `flutter analyze lib/screens/job_detail_screen.dart`

Expected: No new errors.

### Step 2.3 — Push to GitHub

- [ ] **Run:** `git push origin main`

### Step 2.4 — Phase 7 complete checkpoint

Phase 7 is done when all of the following are true:

- [ ] Job Detail > Activity tab shows a live timeline from Firestore
- [ ] System events (status changes, version saves, estimate creation from Phases 4-6) appear in muted style with type-specific icons
- [ ] FAB opens a menu with Add Note / Add Task / Log Call
- [ ] Add Note dialog creates a note activity
- [ ] Add Task dialog creates a task with optional due date; task cards have a checkbox that toggles completion
- [ ] Log Call dialog creates a call activity with direction (in/out) and optional duration
- [ ] All entries have a delete button with confirmation
- [ ] Overdue tasks are highlighted in red
- [ ] Completed tasks show strikethrough and completion date
- [ ] All 63 tests pass, no new analyzer errors
- [ ] Pushed to `origin/main`

---

## Notes for the implementing engineer

- **The `_PlaceholderTab` class is now unused** since both Estimates (Phase 5) and Activity (this phase) have real content. You can delete it or leave it — it's harmless dead code that Phase 9 can clean up.
- **`companyProfileProvider`** is imported from `estimator_providers.dart` (already imported in this file). It provides the author name for new activities.
- **`_timeAgo` is a simple relative-time formatter** — not a library dependency. It handles minutes, hours, days, and falls back to `_dateFmt` for older entries.
- **Task completion toggle** calls `FirestoreService.instance.updateTaskCompletion(jobId, activityId, !completed)` directly. The Firestore rules allow updates only on `type == 'task'` activities (set in Phase 1).
- **The FAB is positioned with `Stack` + `Positioned`** rather than `Scaffold.floatingActionButton` because the tab's body is inside a `TabBarView` and the FAB should only appear on the Activity tab, not all tabs.
- **Call direction uses `SegmentedButton<CallDirection>`** which requires Flutter 3.x. The segments show icons for outgoing (call_made) and incoming (call_received).
- **`_dateFmt`** is the `DateFormat('MMM d, yyyy')` instance already declared at the top of `job_detail_screen.dart` from Phase 4.
