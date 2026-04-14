# Job Record Phase 8 — New Job Flow + Cutover Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the New Job creation flow (customer picker → job form → create + load into estimator) and perform the cutover: replace the old Open button with the Job List, remove the legacy `protpo_projects` save path, and delete `project_list_screen.dart`.

**Architecture:** The New Job flow is a two-step modal chain inside `job_list_sheet.dart`: first a `_CustomerPickerDialog` (search existing customers or create new inline), then a `_NewJobFormDialog` (job name, site address, site zip). On submit, the flow creates the customer (if new), job, first estimate, and system activity, then loads the empty estimate into the estimator. The cutover in `estimator_screen.dart` swaps the Open button handler from `showProjectList` to `showJobList`, removes the `GestureDetector` long-press wrapper, removes the `_currentProjectId` field, removes the legacy save branch, and deletes the import of `project_list_screen.dart`. The file `project_list_screen.dart` itself is deleted.

**Tech Stack:** Flutter 3.35+, Riverpod, cloud_firestore (existing). No new dependencies.

**This is the cutover milestone (M1).** After this phase, the old project list is gone. The job system is the only way to save and load work.

---

## File Structure

### Files to modify

| Path | Change |
|---|---|
| `lib/screens/job_list_sheet.dart` | Replace the "+ New Job" placeholder button with the real flow. Add `_CustomerPickerDialog` and `_NewJobFormDialog` widgets. Add imports for customer model, customer provider, and activity model. |
| `lib/screens/estimator_screen.dart` | Remove `import 'project_list_screen.dart'`. Remove `_openProject()` method. Remove `_currentProjectId` field and all references. Replace Open button handler with `_openJobList` (remove `GestureDetector` long-press wrapper). Remove the legacy save branch from `_saveProject()` and `_maybeAutosave()`. |

### Files to delete

| Path | Reason |
|---|---|
| `lib/screens/project_list_screen.dart` | Replaced by `job_list_sheet.dart`. No longer imported anywhere after cutover. |

### Files NOT touched

- All model, provider, service, and widget files from Phases 1-7

---

## Task 1: Build the New Job flow in job_list_sheet.dart

**Files:**
- Modify: `lib/screens/job_list_sheet.dart`

### Step 1.1 — Add imports

- [ ] **Add** these imports at the top of `lib/screens/job_list_sheet.dart` (after the existing imports):

```dart
import 'package:uuid/uuid.dart';
import '../models/customer.dart';
import '../models/estimate.dart';
import '../models/activity.dart';
import '../providers/estimator_providers.dart';
```

Verify that `../providers/job_providers.dart` and `../services/firestore_service.dart` are already imported (they should be from Phase 4).

### Step 1.2 — Replace the placeholder New Job button with the real flow

- [ ] **Find** the placeholder "+ New Job" `TextButton.icon` (around line 68-76):

```dart
            TextButton.icon(
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('New Job flow coming in Phase 8')),
                );
              },
              icon: const Icon(Icons.add, size: 18),
              label: const Text('New Job', style: TextStyle(fontSize: 13)),
            ),
```

**Replace** with:

```dart
            TextButton.icon(
              onPressed: () => _startNewJobFlow(context, ref),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('New Job', style: TextStyle(fontSize: 13)),
            ),
```

### Step 1.3 — Add the _startNewJobFlow method to _JobListSheetState

- [ ] **Add** this method to `_JobListSheetState`, after the `_deleteJob` method:

```dart
  Future<void> _startNewJobFlow(BuildContext context, WidgetRef ref) async {
    // Step 1: Pick or create a customer
    final customer = await showDialog<Customer>(
      context: context,
      builder: (_) => const _CustomerPickerDialog(),
    );
    if (customer == null || !mounted) return;

    // Step 2: Fill in job details
    final jobData = await showDialog<_NewJobData>(
      context: context,
      builder: (_) => _NewJobFormDialog(customerName: customer.name),
    );
    if (jobData == null || !mounted) return;

    // Step 3: Create everything in Firestore
    try {
      final fs = FirestoreService.instance;

      // Create the job
      final job = Job(
        id: '',
        customerId: customer.id,
        customerName: customer.name,
        jobName: jobData.jobName,
        siteAddress: jobData.siteAddress,
        siteZip: jobData.siteZip,
      );
      final jobId = await fs.createJob(job);

      // Create the first estimate
      final estimate = Estimate(id: '', name: 'Initial Estimate');
      final estId = await fs.createEstimate(jobId, estimate);

      // Set as active estimate
      await fs.updateJob(Job(
        id: jobId,
        customerId: customer.id,
        customerName: customer.name,
        jobName: jobData.jobName,
        siteAddress: jobData.siteAddress,
        siteZip: jobData.siteZip,
        activeEstimateId: estId,
      ));

      // Log system activity
      await fs.createActivity(jobId, Activity(
        id: '',
        type: ActivityType.system,
        timestamp: DateTime.now(),
        author: 'system',
        body: 'Job created: ${jobData.jobName}',
        systemEventKind: 'job_created',
        systemEventData: {
          'jobId': jobId,
          'customerId': customer.id,
          'customerName': customer.name,
        },
      ));

      // Set active context IDs (new estimate has empty state —
      // don't try to deserialize, just set IDs so saves go to the right place)
      ref.read(activeJobIdProvider.notifier).state = jobId;
      ref.read(activeEstimateIdProvider.notifier).state = estId;
      ref.read(activeJobNameProvider.notifier).state = jobData.jobName;
      ref.read(activeCustomerNameProvider.notifier).state = customer.name;
      ref.read(activeEstimateNameProvider.notifier).state = 'Initial Estimate';

      // Persist session
      await fs.saveLastSession(jobId: jobId, estimateId: estId);

      // Close the job list sheet → back to estimator
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to create job: $e')),
        );
      }
    }
  }
```

### Step 1.4 — Add the _NewJobData class

- [ ] **Add** this simple data class at the bottom of the file:

```dart
class _NewJobData {
  final String jobName;
  final String siteAddress;
  final String siteZip;
  const _NewJobData({
    required this.jobName,
    required this.siteAddress,
    required this.siteZip,
  });
}
```

### Step 1.5 — Add the _CustomerPickerDialog widget

- [ ] **Add** this widget at the bottom of the file (before `_NewJobData`):

```dart
// ══════════════════════════════════════════════════════════════════════════════
// NEW JOB FLOW — Step 1: Customer Picker
// ══════════════════════════════════════════════════════════════════════════════

class _CustomerPickerDialog extends ConsumerStatefulWidget {
  const _CustomerPickerDialog();

  @override
  ConsumerState<_CustomerPickerDialog> createState() =>
      _CustomerPickerDialogState();
}

class _CustomerPickerDialogState
    extends ConsumerState<_CustomerPickerDialog> {
  String _search = '';
  bool _showNewForm = false;

  // New customer inline form
  final _nameCtrl = TextEditingController();
  final _contactCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  CustomerType _type = CustomerType.Company;
  bool _creating = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _contactCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _createAndSelect() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;

    setState(() => _creating = true);
    try {
      final customer = Customer(
        id: const Uuid().v4(),
        name: name,
        customerType: _type,
        primaryContactName: _contactCtrl.text.trim(),
        phone: _phoneCtrl.text.trim(),
      );
      await FirestoreService.instance.createCustomer(customer);
      if (mounted) Navigator.pop(context, customer);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to create customer: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final customersAsync = ref.watch(customersListProvider);

    return AlertDialog(
      title: Row(children: [
        Icon(Icons.person_search, size: 20, color: AppTheme.primary),
        const SizedBox(width: 8),
        const Text('Select Customer',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
      ]),
      content: SizedBox(
        width: 460,
        height: 400,
        child: _showNewForm
            ? _buildNewCustomerForm()
            : _buildCustomerList(customersAsync),
      ),
      actions: _showNewForm
          ? [
              TextButton(
                onPressed: () => setState(() => _showNewForm = false),
                child: const Text('Back to list'),
              ),
              ElevatedButton.icon(
                onPressed: _creating ? null : _createAndSelect,
                icon: _creating
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child:
                            CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.add, size: 16),
                label: const Text('Create & Select'),
              ),
            ]
          : [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
            ],
    );
  }

  Widget _buildCustomerList(AsyncValue<List<Customer>> customersAsync) {
    return Column(children: [
      // Search
      TextField(
        decoration: InputDecoration(
          hintText: 'Search customers...',
          prefixIcon: const Icon(Icons.search, size: 18),
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8)),
          suffixIcon: IconButton(
            icon: const Icon(Icons.person_add, size: 18),
            tooltip: 'New Customer',
            onPressed: () => setState(() => _showNewForm = true),
          ),
        ),
        onChanged: (v) => setState(() => _search = v.toLowerCase()),
      ),
      const SizedBox(height: 8),
      Expanded(
        child: customersAsync.when(
          loading: () =>
              const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(
              child: Text('Error: $e',
                  style: TextStyle(color: AppTheme.error))),
          data: (customers) {
            final filtered = _search.isEmpty
                ? customers
                : customers
                    .where((c) =>
                        c.name.toLowerCase().contains(_search) ||
                        c.primaryContactName
                            .toLowerCase()
                            .contains(_search))
                    .toList();

            if (filtered.isEmpty) {
              return Center(
                child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                  Icon(Icons.person_off,
                      size: 32, color: AppTheme.textMuted),
                  const SizedBox(height: 8),
                  Text(
                      customers.isEmpty
                          ? 'No customers yet'
                          : 'No match',
                      style: TextStyle(color: AppTheme.textMuted)),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: () =>
                        setState(() => _showNewForm = true),
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('New Customer'),
                  ),
                ]),
              );
            }

            return ListView.separated(
              itemCount: filtered.length,
              separatorBuilder: (_, __) =>
                  const Divider(height: 1),
              itemBuilder: (_, i) {
                final c = filtered[i];
                return ListTile(
                  dense: true,
                  leading: CircleAvatar(
                    radius: 16,
                    backgroundColor:
                        AppTheme.primary.withValues(alpha: 0.1),
                    child: Text(
                        c.name.isNotEmpty
                            ? c.name[0].toUpperCase()
                            : '?',
                        style: TextStyle(
                            color: AppTheme.primary,
                            fontWeight: FontWeight.w600,
                            fontSize: 13)),
                  ),
                  title: Text(c.name,
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600)),
                  subtitle: c.primaryContactName.isNotEmpty
                      ? Text(c.primaryContactName,
                          style: TextStyle(
                              fontSize: 11,
                              color: AppTheme.textMuted))
                      : null,
                  onTap: () => Navigator.pop(context, c),
                );
              },
            );
          },
        ),
      ),
    ]);
  }

  Widget _buildNewCustomerForm() {
    return SingleChildScrollView(
      child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
        Text('New Customer',
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppTheme.textSecondary)),
        const SizedBox(height: 10),
        TextField(
          controller: _nameCtrl,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Customer Name *',
            isDense: true,
            prefixIcon: Icon(Icons.business, size: 18),
          ),
        ),
        const SizedBox(height: 10),
        DropdownButtonFormField<CustomerType>(
          value: _type,
          decoration: const InputDecoration(
            labelText: 'Type',
            isDense: true,
            prefixIcon: Icon(Icons.category, size: 18),
          ),
          items: const [
            DropdownMenuItem(
                value: CustomerType.Company,
                child: Text('Company')),
            DropdownMenuItem(
                value: CustomerType.InsuranceCarrier,
                child: Text('Insurance Carrier')),
            DropdownMenuItem(
                value: CustomerType.PropertyManager,
                child: Text('Property Manager')),
            DropdownMenuItem(
                value: CustomerType.GeneralContractor,
                child: Text('General Contractor')),
            DropdownMenuItem(
                value: CustomerType.Individual,
                child: Text('Individual')),
          ],
          onChanged: (v) {
            if (v != null) setState(() => _type = v);
          },
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _contactCtrl,
          decoration: const InputDecoration(
            labelText: 'Primary Contact',
            isDense: true,
            prefixIcon: Icon(Icons.person, size: 18),
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _phoneCtrl,
          decoration: const InputDecoration(
            labelText: 'Phone',
            isDense: true,
            prefixIcon: Icon(Icons.phone, size: 18),
          ),
        ),
      ]),
    );
  }
}
```

### Step 1.6 — Add the _NewJobFormDialog widget

- [ ] **Add** this widget after `_CustomerPickerDialog` (and before `_NewJobData`):

```dart
// ══════════════════════════════════════════════════════════════════════════════
// NEW JOB FLOW — Step 2: Job Details Form
// ══════════════════════════════════════════════════════════════════════════════

class _NewJobFormDialog extends StatefulWidget {
  final String customerName;
  const _NewJobFormDialog({required this.customerName});

  @override
  State<_NewJobFormDialog> createState() => _NewJobFormDialogState();
}

class _NewJobFormDialogState extends State<_NewJobFormDialog> {
  final _jobNameCtrl = TextEditingController();
  final _siteAddressCtrl = TextEditingController();
  final _siteZipCtrl = TextEditingController();

  @override
  void dispose() {
    _jobNameCtrl.dispose();
    _siteAddressCtrl.dispose();
    _siteZipCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(children: [
        Icon(Icons.work, size: 20, color: AppTheme.primary),
        const SizedBox(width: 8),
        const Text('New Job',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
      ]),
      content: SizedBox(
        width: 460,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          // Customer (read-only)
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppTheme.border),
            ),
            child: Row(children: [
              Icon(Icons.person, size: 16, color: AppTheme.textMuted),
              const SizedBox(width: 8),
              Text('Customer: ',
                  style: TextStyle(
                      fontSize: 12, color: AppTheme.textSecondary)),
              Text(widget.customerName,
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600)),
            ]),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _jobNameCtrl,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Job Name *',
              isDense: true,
              hintText: 'e.g. Building A TPO Replacement',
              prefixIcon: Icon(Icons.work_outline, size: 18),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _siteAddressCtrl,
            decoration: const InputDecoration(
              labelText: 'Site Address',
              isDense: true,
              hintText: 'Address of the roof',
              prefixIcon: Icon(Icons.location_on, size: 18),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _siteZipCtrl,
            decoration: const InputDecoration(
              labelText: 'Site ZIP Code',
              isDense: true,
              hintText: '5-digit ZIP',
              prefixIcon: Icon(Icons.pin_drop, size: 18),
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
          onPressed: () {
            final name = _jobNameCtrl.text.trim();
            if (name.isEmpty) return;
            Navigator.pop(
              context,
              _NewJobData(
                jobName: name,
                siteAddress: _siteAddressCtrl.text.trim(),
                siteZip: _siteZipCtrl.text.trim(),
              ),
            );
          },
          icon: const Icon(Icons.add, size: 16),
          label: const Text('Create Job'),
        ),
      ],
    );
  }
}
```

### Step 1.7 — Update the file header comment

- [ ] **Find** the comment at line 4:

```dart
/// after Phase 8 cutover. Until then, reachable via long-press on Open.
```

**Replace** with:

```dart
/// Primary entry point for browsing and creating jobs.
```

### Step 1.8 — Verify it compiles

- [ ] **Run:** `flutter analyze lib/screens/job_list_sheet.dart`

Expected: No errors.

### Step 1.9 — Commit

- [ ] **Run:**

```bash
git add lib/screens/job_list_sheet.dart
git commit -m "feat(ui): build New Job flow with customer picker + job form

Replaces the placeholder '+ New Job' button with a two-step modal
chain:
1. Customer Picker: search existing customers or create a new one
   inline (name, type, contact, phone)
2. Job Form: job name, site address, site ZIP

On submit: creates customer (if new), job, first estimate, system
activity ('job_created'), sets active context IDs, persists session,
pops back to estimator.

Part of Phase 8 — the cutover milestone.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: Perform the cutover in estimator_screen.dart + delete project_list_screen.dart

**Files:**
- Modify: `lib/screens/estimator_screen.dart`
- Delete: `lib/screens/project_list_screen.dart`

This is the cutover. After this task, the old project list is gone and the job system is the only way to work.

### Step 2.1 — Remove the project_list_screen import

- [ ] **Find** and **delete** this line from `lib/screens/estimator_screen.dart`:

```dart
import 'project_list_screen.dart';
```

### Step 2.2 — Remove _currentProjectId field and _openProject method

- [ ] **Find** and **delete** the `_currentProjectId` field declaration:

```dart
  String? _currentProjectId; // null = unsaved
```

- [ ] **Find** and **delete** the entire `_openProject()` method:

```dart
  Future<void> _openProject() async {
    final id = await showProjectList(context);
    if (id != null) {
      setState(() {
        _currentProjectId   = id;
        _hasUnsavedChanges  = false;
        _lastSavedState     = ref.read(estimatorProvider).hashCode;
      });
    }
  }
```

### Step 2.3 — Replace the Open buttons (remove GestureDetector long-press wrapper)

- [ ] **Find** the mobile Open button (with `GestureDetector` + `onLongPress`):

```dart
          GestureDetector(
            onLongPress: _openJobList,
            child: IconButton(
              onPressed: _openProject,
              icon: const Icon(Icons.folder_open, size: 20),
              color: AppTheme.textSecondary,
              tooltip: 'Open Project (long-press for Jobs)',
            ),
          ),
```

**Replace** with:

```dart
          IconButton(
            onPressed: _openJobList,
            icon: const Icon(Icons.work_outline, size: 20),
            color: AppTheme.textSecondary,
            tooltip: 'Jobs',
          ),
```

- [ ] **Find** the desktop Open button (with `GestureDetector` + `onLongPress`):

```dart
          GestureDetector(
            onLongPress: _openJobList,
            child: TextButton.icon(
              onPressed: _openProject,
              icon: const Icon(Icons.folder_open, size: 18),
              label: const Text('Open'),
              style: TextButton.styleFrom(foregroundColor: AppTheme.textSecondary),
            ),
          ),
```

**Replace** with:

```dart
          TextButton.icon(
            onPressed: _openJobList,
            icon: const Icon(Icons.work_outline, size: 18),
            label: const Text('Jobs'),
            style: TextButton.styleFrom(foregroundColor: AppTheme.textSecondary),
          ),
```

### Step 2.4 — Remove legacy save path from _saveProject

- [ ] **Find** the `_saveProject()` method. Remove the entire `} else {` legacy branch. The method should now look like:

```dart
  Future<void> _saveProject() async {
    if (_isSaving) return;

    final hasActiveEst = ref.read(hasActiveEstimateProvider);
    if (!hasActiveEst) {
      // No job loaded — prompt user to create one first
      AppSnackbar.info(context, 'Create or open a job first — tap "Jobs" in the toolbar.');
      return;
    }

    setState(() { _isSaving = true; _saveSuccess = false; });

    try {
      final jobId = ref.read(activeJobIdProvider)!;
      final estId = ref.read(activeEstimateIdProvider)!;
      final estName = ref.read(activeEstimateNameProvider);
      final state = ref.read(estimatorProvider);
      final serialized = stateToJson(state, estId);

      final totalArea = state.buildings
          .fold(0.0, (sum, b) => sum + b.roofGeometry.totalArea);

      final draft = Estimate(
        id: estId,
        name: estName,
        estimatorState: serialized,
        totalArea: totalArea,
        totalValue: 0,
        buildingCount: state.buildings.length,
      );
      await FirestoreService.instance.updateEstimate(jobId, draft);

      setState(() {
        _isSaving = false;
        _saveSuccess = true;
        _hasUnsavedChanges = false;
        _lastSavedState = state.hashCode;
      });
      if (mounted) {
        AppSnackbar.success(context, 'Saved estimate "$estName"');
      }

      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) setState(() => _saveSuccess = false);
      });
    } catch (e, stack) {
      debugPrint('[SAVE] Save failed: $e');
      debugPrint('[SAVE] Stack: $stack');
      setState(() => _isSaving = false);
      if (mounted) {
        AppSnackbar.error(context, 'Save failed: $e');
      }
    }
  }
```

### Step 2.5 — Remove legacy autosave path from _maybeAutosave

- [ ] **Replace** the entire `_maybeAutosave()` method with:

```dart
  Future<void> _maybeAutosave(EstimatorState state) async {
    if (!mounted || _autoSaveDone) return;

    final hasActiveEst = ref.read(hasActiveEstimateProvider);
    if (!hasActiveEst) return; // No job loaded — nothing to autosave to

    final hasData = state.projectInfo.projectName.isNotEmpty ||
        (state.buildings.isNotEmpty &&
         state.buildings.first.roofGeometry.totalArea > 0);
    if (!hasData) return;

    _autoSaveDone = true;
    try {
      final jobId = ref.read(activeJobIdProvider)!;
      final estId = ref.read(activeEstimateIdProvider)!;
      final estName = ref.read(activeEstimateNameProvider);
      final serialized = stateToJson(state, estId);
      final totalArea = state.buildings
          .fold(0.0, (sum, b) => sum + b.roofGeometry.totalArea);

      final draft = Estimate(
        id: estId,
        name: estName,
        estimatorState: serialized,
        totalArea: totalArea,
        totalValue: 0,
        buildingCount: state.buildings.length,
      );
      await FirestoreService.instance.updateEstimate(jobId, draft);
      if (mounted) {
        setState(() {
          _hasUnsavedChanges = false;
          _lastSavedState    = state.hashCode;
        });
      }
    } catch (e) {
      _autoSaveDone = false;
    }
  }
```

### Step 2.6 — Fix remaining _currentProjectId references

- [ ] **Search** for any remaining references to `_currentProjectId` in `estimator_screen.dart`. If the `ref.listen` block in `build()` references it:

Find:
```dart
      if (prev != next && _currentProjectId == null) {
        _maybeAutosave(next);
      }
```

Replace with:
```dart
      if (prev != next) {
        _maybeAutosave(next);
      }
```

### Step 2.7 — Delete project_list_screen.dart

- [ ] **Run:**

```bash
rm lib/screens/project_list_screen.dart
```

### Step 2.8 — Verify it compiles

- [ ] **Run:** `flutter analyze lib/screens/`

Expected: No errors. The deleted file should not be referenced anywhere.

If you get an error about `showProjectList` being undefined, search for any remaining reference and remove it.

### Step 2.9 — Verify tests still pass

- [ ] **Run:** `flutter test test/models/ test/providers/`

Expected: All 63 tests pass.

### Step 2.10 — Commit

- [ ] **Run:**

```bash
git add lib/screens/estimator_screen.dart
git rm lib/screens/project_list_screen.dart
git commit -m "feat(cutover): replace Open button with Jobs, remove legacy save path

CUTOVER MILESTONE — the old project system is gone.

estimator_screen.dart:
- Open button now opens Job List Sheet (was: Project List)
- Icon changed from folder_open to work_outline, label 'Jobs'
- Removed GestureDetector long-press debug wrapper
- Removed _openProject() method and _currentProjectId field
- _saveProject(): removed the 'else' branch that saved to
  protpo_projects. When no job is loaded, shows an info snackbar
  prompting the user to create or open a job first.
- _maybeAutosave(): removed the legacy branch. Now a no-op when
  no active estimate is set.

Deleted: lib/screens/project_list_screen.dart (340 lines, replaced
by job_list_sheet.dart from Phase 4).

After this commit, the only way to save and load work is through
the job record system (Customer → Job → Estimate).

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: Final verification and push

**Files:** none modified

### Step 3.1 — Run all tests

- [ ] **Run:** `flutter test test/models/ test/providers/`

Expected: All 63 tests pass.

### Step 3.2 — Run flutter analyze on all screens

- [ ] **Run:** `flutter analyze lib/screens/`

Expected: No errors. `project_list_screen.dart` no longer exists. The three remaining screen files (`estimator_screen.dart`, `job_list_sheet.dart`, `job_detail_screen.dart`) compile cleanly.

### Step 3.3 — Verify no dangling imports

- [ ] **Run:** `grep -r "project_list_screen" lib/ 2>&1`

Expected: No matches. If any file still imports `project_list_screen.dart`, fix it.

### Step 3.4 — Push to GitHub

- [ ] **Run:** `git push origin main`

### Step 3.5 — Phase 8 complete checkpoint (M1 CUTOVER)

Phase 8 is done — and with it, the entire M1 milestone — when all of the following are true:

- [ ] The "Open" button in the estimator AppBar is now labeled "Jobs" with a `work_outline` icon and opens the Job List Sheet
- [ ] The "+ New Job" button in the Job List Sheet opens the customer picker → job form flow
- [ ] Creating a new job writes: customer (if new) + job + first estimate + system activity → loads into estimator
- [ ] `project_list_screen.dart` is deleted — `grep -r "project_list_screen" lib/` returns nothing
- [ ] The legacy `protpo_projects` save path is removed — Save button shows "Create or open a job first" when no job is loaded
- [ ] Autosave is a no-op when no active estimate (no orphan protpo_projects docs created)
- [ ] The `_currentProjectId` field no longer exists
- [ ] All 63 tests pass, no new analyzer errors
- [ ] Pushed to `origin/main`

**The M1 cutover milestone is complete.** The job record system is the primary and only way to work in ProTPO.

---

## Notes for the implementing engineer

- **This is the most risk-bearing phase.** It removes the old save path. If something is wrong, edits can't be saved until the bug is fixed. Test the full flow before pushing: create a customer → create a job → edit the estimate → save → reload the page → verify the data persists.
- **`_currentProjectId` is removed entirely.** All references to it (`setState` calls, `_openProject`, `_maybeAutosave`) must be cleaned up or the build will fail. Search for `_currentProjectId` after making changes.
- **The `_autoSaveDone` flag still exists** and still prevents repeat autosave attempts in a single session. The logic is the same — just the legacy branch is removed.
- **Customer picker has inline creation.** The user can toggle between searching existing customers and filling in a new-customer form within the same dialog. The "+ New Customer" icon is in the search field's suffix, and a "New Customer" button appears in the empty state.
- **The new job form shows the selected customer as a read-only header** so the user knows which customer they're creating a job for.
- **After job creation, the estimator has a fresh (empty) state.** The first autosave will write this empty state to the estimate doc. The user fills in the left panel as usual — the context ribbon shows the job/customer/estimate names so they know they're working on a real job.
