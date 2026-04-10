/// lib/widgets/ui_polish.dart
///
/// Shared UI polish components used across ProTPO panels.
///
/// Contents:
///   - SectionDot       — green/amber/gray completion indicator for left panel headers
///   - AppSnackbar      — consistent success/error/info feedback
///   - BomEmptyState    — context-aware empty state for BOM tab
///   - BlockerBanner    — red banner for REQUIRED messages
///   - WarningBanner    — amber banner for WARNING messages
///   - UnsavedDot       — small indicator that project has unsaved changes
///   - SkeletonRow      — shimmer-style placeholder row for loading states
///   - CompletionSummary — small progress bar showing section fill

import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// SECTION COMPLETION DOT
// ═══════════════════════════════════════════════════════════════════════════════

enum DotStatus { complete, partial, empty }

/// Small colored dot shown in the left panel section header.
/// Green = complete, Amber = partially filled, Gray = untouched.
class SectionDot extends StatelessWidget {
  final DotStatus status;
  final double size;

  const SectionDot({super.key, required this.status, this.size = 8});

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      DotStatus.complete => AppTheme.accent,
      DotStatus.partial  => AppTheme.warning,
      DotStatus.empty    => AppTheme.border,
    };
    return Container(
      width:  size,
      height: size,
      margin: const EdgeInsets.only(right: 8),
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

/// Computes dot status from a list of field "filled" booleans.
/// complete = all true, partial = some true, empty = none true.
DotStatus dotStatus(List<bool> fields) {
  if (fields.isEmpty) return DotStatus.empty;
  final filled = fields.where((f) => f).length;
  if (filled == fields.length) return DotStatus.complete;
  if (filled > 0) return DotStatus.partial;
  return DotStatus.empty;
}

// ═══════════════════════════════════════════════════════════════════════════════
// APP SNACKBAR
// ═══════════════════════════════════════════════════════════════════════════════

class AppSnackbar {
  AppSnackbar._();

  static void success(BuildContext context, String message) {
    _show(context, message, AppTheme.accent, Icons.check_circle_outline);
  }

  static void error(BuildContext context, String message) {
    _show(context, message, AppTheme.error, Icons.error_outline);
  }

  static void info(BuildContext context, String message) {
    _show(context, message, AppTheme.primary, Icons.info_outline);
  }

  static void warning(BuildContext context, String message) {
    _show(context, message, AppTheme.warning, Icons.warning_amber_outlined);
  }

  static void _show(
    BuildContext context,
    String message,
    Color color,
    IconData icon,
  ) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        behavior:         SnackBarBehavior.floating,
        backgroundColor:  color,
        duration:         const Duration(seconds: 3),
        margin:           const EdgeInsets.all(16),
        shape:            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        content: Row(children: [
          Icon(icon, color: Colors.white, size: 18),
          const SizedBox(width: 10),
          Expanded(child: Text(message,
              style: const TextStyle(color: Colors.white, fontSize: 13))),
        ]),
      ));
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// BOM EMPTY STATE — context-aware
// ═══════════════════════════════════════════════════════════════════════════════

/// Shows a helpful, specific message based on what's actually missing.
/// Pass the list of warning/blocker strings from BomResult.
class BomEmptyState extends StatelessWidget {
  final List<String> blockers;
  final VoidCallback? onGoToGeometry;

  const BomEmptyState({
    super.key,
    required this.blockers,
    this.onGoToGeometry,
  });

  @override
  Widget build(BuildContext context) {
    // Parse the most actionable blocker
    final needsArea    = blockers.any((w) => w.contains('dimensions'));
    final needsDeck    = blockers.any((w) => w.contains('Deck type'));
    final needsZip     = blockers.any((w) => w.contains('ZIP'));
    final needsZones   = blockers.any((w) => w.contains('Wind zone') || w.contains('zone widths'));

    final String title;
    final String subtitle;
    final IconData icon;

    if (needsArea) {
      title    = 'Enter roof dimensions';
      subtitle = 'Open Project Geometry and add edge lengths for at least one shape.';
      icon     = Icons.crop_square;
    } else if (needsDeck) {
      title    = 'Select deck type';
      subtitle = 'Open System Specs and choose the structural deck type to unlock fastener selection.';
      icon     = Icons.hardware;
    } else if (needsZip) {
      title    = 'Enter ZIP code';
      subtitle = 'Open Project Info and enter the 5-digit ZIP to determine climate zone, wind speed, and R-value requirements.';
      icon     = Icons.location_on_outlined;
    } else if (needsZones) {
      title    = 'Set wind zone widths';
      subtitle = 'Enter perimeter and corner zone widths in the Project Geometry section, or enter building height and ZIP to auto-calculate.';
      icon     = Icons.wind_power;
    } else {
      title    = 'Ready to calculate';
      subtitle = 'Fill in the project inputs on the left to generate your materials takeoff.';
      icon     = Icons.calculate_outlined;
    }

    return Container(
      padding: const EdgeInsets.all(36),
      decoration: BoxDecoration(
        color: AppTheme.surfaceAlt,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppTheme.primary.withValues(alpha:0.08),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 32, color: AppTheme.primary.withValues(alpha:0.6)),
        ),
        const SizedBox(height: 14),
        Text(title,
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600,
                color: AppTheme.textSecondary)),
        const SizedBox(height: 6),
        Text(subtitle,
            style: TextStyle(fontSize: 12, color: AppTheme.textMuted, height: 1.5),
            textAlign: TextAlign.center),
        if (needsArea && onGoToGeometry != null) ...[
          const SizedBox(height: 16),
          TextButton.icon(
            onPressed: onGoToGeometry,
            icon: Icon(Icons.arrow_back, size: 14, color: AppTheme.primary),
            label: Text('Go to Geometry', style: TextStyle(
                color: AppTheme.primary, fontSize: 12, fontWeight: FontWeight.w600)),
          ),
        ],
      ]),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// REQUIRED & WARNING BANNERS
// ═══════════════════════════════════════════════════════════════════════════════

/// Renders a list of BOM warnings with correct visual hierarchy:
///   BLOCKER → red
///   WARNING → amber
///   info    → blue
class BomWarningList extends StatefulWidget {
  final List<String> warnings;

  const BomWarningList({super.key, required this.warnings});

  @override
  State<BomWarningList> createState() => _BomWarningListState();
}

class _BomWarningListState extends State<BomWarningList> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final blockers = widget.warnings.where((w) => w.startsWith('BLOCKER')).toList();
    final warnings = widget.warnings.where((w) => w.startsWith('WARNING')).toList();
    final others   = widget.warnings
        .where((w) => !w.startsWith('BLOCKER') && !w.startsWith('WARNING'))
        .toList();

    // Always show blockers. Collapse warnings/others behind a toggle when > 2 total.
    final totalCount = blockers.length + warnings.length + others.length;
    final showToggle = totalCount > 2;
    final showAll    = !showToggle || _expanded;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      ...blockers.map((b) => _Banner(
        message: b.replaceFirst('BLOCKER: ', ''),
        color:   AppTheme.error,
        icon:    Icons.block,
        prefix:  'REQUIRED',
      )),
      if (showAll) ...[
        ...warnings.map((w) => _Banner(
          message: w.replaceFirst('WARNING: ', ''),
          color:   AppTheme.warning,
          icon:    Icons.warning_amber_outlined,
          prefix:  'WARNING',
        )),
        ...others.map((o) => _Banner(
          message: o,
          color:   AppTheme.primary,
          icon:    Icons.info_outline,
          prefix:  'INFO',
        )),
      ] else if (warnings.isNotEmpty || others.isNotEmpty) ...[
        GestureDetector(
          onTap: () => setState(() => _expanded = true),
          child: Container(
            margin: const EdgeInsets.only(top: 4),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppTheme.warning.withValues(alpha:0.08),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: AppTheme.warning.withValues(alpha:0.25)),
            ),
            child: Row(children: [
              Icon(Icons.warning_amber_outlined, size: 14, color: AppTheme.warning),
              const SizedBox(width: 8),
              Text(
                '${warnings.length + others.length} additional notice${warnings.length + others.length > 1 ? "s" : ""}',
                style: TextStyle(fontSize: 12, color: AppTheme.warning,
                    fontWeight: FontWeight.w500),
              ),
              const Spacer(),
              Icon(Icons.expand_more, size: 14, color: AppTheme.warning),
            ]),
          ),
        ),
      ],
    ]);
  }
}

class _Banner extends StatelessWidget {
  final String  message;
  final Color   color;
  final IconData icon;
  final String  prefix;

  const _Banner({required this.message, required this.color,
      required this.icon, required this.prefix});

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 6),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
    decoration: BoxDecoration(
      color: color.withValues(alpha:0.07),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: color.withValues(alpha:0.3)),
    ),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, size: 15, color: color),
      const SizedBox(width: 10),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(prefix,
            style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800,
                color: color, letterSpacing: 0.8)),
        const SizedBox(height: 2),
        Text(message,
            style: TextStyle(fontSize: 12, color: AppTheme.textPrimary, height: 1.4)),
      ])),
    ]),
  );
}

// ═══════════════════════════════════════════════════════════════════════════════
// UNSAVED CHANGES DOT
// ═══════════════════════════════════════════════════════════════════════════════

/// Small pulsing amber dot shown next to project name when there are unsaved changes.
class UnsavedDot extends StatefulWidget {
  final bool visible;
  const UnsavedDot({super.key, required this.visible});

  @override
  State<UnsavedDot> createState() => _UnsavedDotState();
}

class _UnsavedDotState extends State<UnsavedDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double>   _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this,
        duration: const Duration(milliseconds: 1200))..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.4, end: 1.0).animate(
        CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    if (!widget.visible) return const SizedBox.shrink();
    return FadeTransition(
      opacity: _anim,
      child: Container(
        width: 8, height: 8,
        margin: const EdgeInsets.only(left: 6, top: 2),
        decoration: const BoxDecoration(
            color: AppTheme.warning, shape: BoxShape.circle),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SKELETON LOADING ROW
// ═══════════════════════════════════════════════════════════════════════════════

/// A single placeholder row that animates opacity to simulate loading.
class SkeletonRow extends StatefulWidget {
  final double width;
  final double height;
  final EdgeInsets margin;

  const SkeletonRow({
    super.key,
    this.width = double.infinity,
    this.height = 14,
    this.margin = const EdgeInsets.symmetric(vertical: 4),
  });

  @override
  State<SkeletonRow> createState() => _SkeletonRowState();
}

class _SkeletonRowState extends State<SkeletonRow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double>   _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this,
        duration: const Duration(milliseconds: 900))..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.3, end: 0.7).animate(
        CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: _anim,
    child: Container(
      width:  widget.width,
      height: widget.height,
      margin: widget.margin,
      decoration: BoxDecoration(
        color: AppTheme.border,
        borderRadius: BorderRadius.circular(4),
      ),
    ),
  );
}

/// Stacked skeleton rows to represent a loading table or section.
class SkeletonBlock extends StatelessWidget {
  final int rows;
  const SkeletonBlock({super.key, this.rows = 4});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: List.generate(rows, (i) => SkeletonRow(
      width: i % 3 == 0 ? double.infinity : (i % 3 == 1 ? 200 : 280),
      height: 13,
    )),
  );
}

// ═══════════════════════════════════════════════════════════════════════════════
// SECTION COMPLETION PROGRESS BAR
// ═══════════════════════════════════════════════════════════════════════════════

/// Small horizontal progress bar showing how many of N sections are complete.
/// Used at the top of the left panel below the header.
class InputProgressBar extends StatelessWidget {
  /// Number of sections with DotStatus.complete
  final int complete;
  /// Total number of sections
  final int total;

  const InputProgressBar({super.key, required this.complete, required this.total});

  @override
  Widget build(BuildContext context) {
    final pct = total > 0 ? complete / total : 0.0;
    final label = complete == total
        ? 'All sections complete'
        : '$complete of $total sections filled';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: pct,
                minHeight: 4,
                backgroundColor: AppTheme.border,
                valueColor: AlwaysStoppedAnimation<Color>(
                  complete == total ? AppTheme.accent : AppTheme.primary,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(label,
              style: TextStyle(fontSize: 10, color: AppTheme.textMuted)),
        ]),
      ]),
    );
  }
}
