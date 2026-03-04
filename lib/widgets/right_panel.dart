/// lib/widgets/right_panel.dart
///
/// Right panel — live project summary + VersiBot chat.
///
/// Summary section reads from Riverpod providers and updates automatically.
/// Chat section is unchanged — stateful, local to _RightPanelState.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../theme/app_theme.dart';
import '../providers/estimator_providers.dart';

class RightPanel extends ConsumerStatefulWidget {
  const RightPanel({super.key});

  @override
  ConsumerState<RightPanel> createState() => _RightPanelState();
}

class _RightPanelState extends ConsumerState<RightPanel> {
  final TextEditingController _chatController  = TextEditingController();
  final ScrollController       _scrollController = ScrollController();
  final List<_ChatMessage>     _messages = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _messages.add(_ChatMessage(
      text: "Hi! I'm VersiBot, your TPO roofing assistant. Ask me anything about "
            "Versico specifications, installation details, or material requirements.",
      isUser: false,
      sources: [],
    ));
  }

  @override
  void dispose() {
    _chatController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // ── Chat ────────────────────────────────────────────────────────────────────

  Future<void> _sendMessage() async {
    final question = _chatController.text.trim();
    if (question.isEmpty || _isLoading) return;

    setState(() {
      _messages.add(_ChatMessage(text: question, isUser: true, sources: []));
      _isLoading = true;
      _chatController.clear();
    });
    _scrollToBottom();

    try {
      final response = await http.post(
        Uri.parse('https://us-central1-tpo-pro-245d1.cloudfunctions.net/askVersico'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'data': {'question': question}}),
      );
      if (response.statusCode == 200) {
        final data    = jsonDecode(response.body);
        final result  = data['result'] ?? data;
        final answer  = result['answer'] ?? 'Sorry, I could not process that request.';
        final sources = List<String>.from(result['sources'] ?? []);
        setState(() {
          _messages.add(_ChatMessage(text: answer, isUser: false, sources: sources));
          _isLoading = false;
        });
      } else {
        setState(() {
          _messages.add(_ChatMessage(
              text: 'Sorry, there was an error connecting to the server.',
              isUser: false, sources: []));
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _messages.add(_ChatMessage(
            text: 'Connection error. Please check your internet and try again.',
            isUser: false, sources: []));
        _isLoading = false;
      });
    }
    _scrollToBottom();
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut);
      }
    });
  }

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      _SummarySection(),                        // stateless ConsumerWidget — reads providers
      Divider(height: 1, color: AppTheme.border),
      Expanded(child: _buildChatSection()),
    ]);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CHAT SECTION  (unchanged from original)
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildChatSection() {
    return Container(
      color: AppTheme.surfaceAlt,
      child: Column(children: [
        // VersiBot header
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
              color: Colors.white,
              border: Border(bottom: BorderSide(color: AppTheme.border))),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                  gradient: LinearGradient(
                      colors: [AppTheme.primary, AppTheme.secondary]),
                  borderRadius: BorderRadius.circular(8)),
              child: const Icon(Icons.smart_toy, color: Colors.white, size: 18),
            ),
            const SizedBox(width: 10),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('VersiBot',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14,
                      color: AppTheme.textPrimary)),
              Text('TPO Specification Assistant',
                  style: TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
            ]),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                  color: AppTheme.accent.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12)),
              child: Row(children: [
                Container(width: 6, height: 6,
                    decoration: BoxDecoration(
                        color: AppTheme.accent, shape: BoxShape.circle)),
                const SizedBox(width: 4),
                Text('Online', style: TextStyle(
                    fontSize: 11, color: AppTheme.accent,
                    fontWeight: FontWeight.w500)),
              ]),
            ),
          ]),
        ),

        // Messages
        Expanded(
          child: ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.all(12),
            itemCount: _messages.length + (_isLoading ? 1 : 0),
            itemBuilder: (context, index) {
              if (_isLoading && index == _messages.length) {
                return _buildTypingIndicator();
              }
              return _buildMessageBubble(_messages[index]);
            },
          ),
        ),

        // Input bar
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: AppTheme.border))),
          child: Row(children: [
            Expanded(
              child: TextField(
                controller: _chatController,
                decoration: InputDecoration(
                  hintText: 'Ask about TPO specs...',
                  hintStyle:
                      TextStyle(color: AppTheme.textMuted, fontSize: 14),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide(color: AppTheme.border)),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide(color: AppTheme.border)),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide(color: AppTheme.primary)),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 10),
                  filled: true,
                  fillColor: AppTheme.surfaceAlt,
                ),
                style: const TextStyle(fontSize: 14),
                onSubmitted: (_) => _sendMessage(),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              decoration: BoxDecoration(
                  gradient: LinearGradient(
                      colors: [AppTheme.primary, AppTheme.primaryDark]),
                  borderRadius: BorderRadius.circular(24)),
              child: IconButton(
                  onPressed: _sendMessage,
                  icon: const Icon(Icons.send, color: Colors.white, size: 20),
                  padding: const EdgeInsets.all(10),
                  constraints: const BoxConstraints()),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _buildMessageBubble(_ChatMessage message) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment:
            message.isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!message.isUser) ...[
            Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                    color: AppTheme.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6)),
                child: Icon(Icons.smart_toy,
                    color: AppTheme.primary, size: 16)),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment: message.isUser
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: message.isUser ? AppTheme.primary : Colors.white,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(16),
                      topRight: const Radius.circular(16),
                      bottomLeft:
                          Radius.circular(message.isUser ? 16 : 4),
                      bottomRight:
                          Radius.circular(message.isUser ? 4 : 16),
                    ),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 5,
                          offset: const Offset(0, 2))
                    ],
                  ),
                  child: Text(message.text,
                      style: TextStyle(
                          color: message.isUser
                              ? Colors.white
                              : AppTheme.textPrimary,
                          fontSize: 14,
                          height: 1.4)),
                ),
                if (message.sources.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: message.sources.take(3).map((source) {
                      return Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                            color: AppTheme.surfaceAlt,
                            borderRadius: BorderRadius.circular(4),
                            border:
                                Border.all(color: AppTheme.border)),
                        child: Text(source,
                            style: TextStyle(
                                fontSize: 10,
                                color: AppTheme.textSecondary)),
                      );
                    }).toList(),
                  ),
                  if (message.sources.length > 3)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                          '+${message.sources.length - 3} more sources',
                          style: TextStyle(
                              fontSize: 10, color: AppTheme.textMuted)),
                    ),
                ],
              ],
            ),
          ),
          if (message.isUser) ...[
            const SizedBox(width: 8),
            CircleAvatar(
                radius: 14,
                backgroundColor: AppTheme.surfaceAlt,
                child: Icon(Icons.person,
                    color: AppTheme.textSecondary, size: 16)),
          ],
        ],
      ),
    );
  }

  Widget _buildTypingIndicator() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
                color: AppTheme.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(6)),
            child: Icon(Icons.smart_toy,
                color: AppTheme.primary, size: 16)),
        const SizedBox(width: 8),
        Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 5,
                    offset: const Offset(0, 2))
              ]),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            _buildDot(0),
            const SizedBox(width: 4),
            _buildDot(1),
            const SizedBox(width: 4),
            _buildDot(2),
          ]),
        ),
      ]),
    );
  }

  Widget _buildDot(int index) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: Duration(milliseconds: 600 + (index * 200)),
      builder: (context, value, child) {
        return Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
                color: AppTheme.primary
                    .withOpacity(0.3 + (0.4 * value)),
                shape: BoxShape.circle));
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SUMMARY SECTION  — live ConsumerWidget
// ═══════════════════════════════════════════════════════════════════════════════

class _SummarySection extends ConsumerWidget {
  const _SummarySection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final info     = ref.watch(projectInfoProvider);
    final geo      = ref.watch(roofGeometryProvider);
    final specs    = ref.watch(systemSpecsProvider);
    final rResult  = ref.watch(rValueResultProvider);
    final rWarnings= ref.watch(rValueValidationProvider);
    final bom      = ref.watch(bomProvider);

    final area      = geo.totalArea;
    final perim     = geo.totalPerimeter;
    final totalR    = rResult?.totalRValue ?? 0.0;
    final reqR      = info.requiredRValue;
    final squares   = area > 0 ? area / 100 : 0.0;
    final bomCount  = bom.activeItems.length;

    // ── Compliance logic ────────────────────────────────────────────────────
    // Warranty: always met once warrantyYears is set
    final warrantyOk = info.warrantyYears > 0;

    // Pull test: Versico requires pull tests on concrete and LW concrete substrates
    final pullTestRequired = specs.deckType == 'Concrete' ||
        specs.deckType == 'LW Concrete';

    // Moisture scan: required for recover and tear-off projects
    final moistureScanRequired = specs.projectType == 'Recover' ||
        specs.projectType == 'Tear-off & Replace';

    // R-value compliance
    final rOk   = reqR != null && totalR >= reqR;
    final rFail = reqR != null && totalR > 0 && totalR < reqR;

    // ZIP entered
    final zipEntered = info.zipCode.length == 5;

    // Any BOM blockers
    final hasBlockers = bom.warnings.any((w) => w.startsWith('BLOCKER'));

    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        // ── Header ───────────────────────────────────────────────────────────
        Row(children: [
          Icon(Icons.summarize, color: AppTheme.primary, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text('Project Summary',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16,
                  color: AppTheme.textPrimary))),
          // BOM item count badge
          if (bomCount > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                  color: AppTheme.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10)),
              child: Text('$bomCount BOM items',
                  style: TextStyle(fontSize: 11, color: AppTheme.primary,
                      fontWeight: FontWeight.w600)),
            ),
        ]),

        // ── Project name (if set) ────────────────────────────────────────────
        if (info.projectName.isNotEmpty || info.customerName.isNotEmpty) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
                color: AppTheme.surfaceAlt,
                borderRadius: BorderRadius.circular(7),
                border: Border.all(color: AppTheme.border)),
            child: Row(children: [
              Icon(Icons.business, size: 13, color: AppTheme.textMuted),
              const SizedBox(width: 7),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (info.projectName.isNotEmpty)
                    Text(info.projectName,
                        style: TextStyle(fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textPrimary),
                        overflow: TextOverflow.ellipsis),
                  if (info.customerName.isNotEmpty)
                    Text(info.customerName,
                        style: TextStyle(fontSize: 11,
                            color: AppTheme.textSecondary),
                        overflow: TextOverflow.ellipsis),
                ],
              )),
              if (info.warrantyYears > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                      color: AppTheme.accent.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(4)),
                  child: Text('${info.warrantyYears}yr',
                      style: TextStyle(fontSize: 10, color: AppTheme.accent,
                          fontWeight: FontWeight.w700)),
                ),
            ]),
          ),
        ],

        const SizedBox(height: 14),

        // ── Stats grid ───────────────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
              color: AppTheme.surfaceAlt,
              borderRadius: BorderRadius.circular(8)),
          child: Column(children: [
            Row(children: [
              Expanded(child: _statItem('Total Area',
                  area > 0 ? _fmtArea(area) : '—', 'sq ft')),
              Expanded(child: _statItem('Squares',
                  squares > 0 ? squares.toStringAsFixed(1) : '—', 'sq')),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: _statItem('Perimeter',
                  perim > 0 ? perim.toStringAsFixed(0) : '—', 'LF')),
              Expanded(child: _statItem('R-Value',
                  totalR > 0 ? 'R-${totalR.toStringAsFixed(1)}' : '—', '',
                  valueColor: rFail ? AppTheme.error
                      : (rOk ? AppTheme.accent : null))),
            ]),
          ]),
        ),

        const SizedBox(height: 14),

        // ── Climate zone (if ZIP set) ────────────────────────────────────────
        if (zipEntered) ...[
          _infoRow(
            Icons.location_on,
            info.climateZone != null
                ? '${info.climateZone!} · ${info.designWindSpeed ?? ''}'
                : 'ZIP ${info.zipCode} — looking up climate zone',
            AppTheme.secondary,
          ),
          const SizedBox(height: 8),
        ],

        // ── Compliance checklist ─────────────────────────────────────────────
        Text('Compliance',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12,
                color: AppTheme.textSecondary, letterSpacing: 0.3)),
        const SizedBox(height: 8),

        _complianceItem(
          label: 'Warranty (${info.warrantyYears}yr)',
          state: warrantyOk ? _CompState.pass : _CompState.missing,
          detail: warrantyOk ? 'Versico ${info.warrantyYears}-yr NDL' : 'Set warranty years',
        ),
        _complianceItem(
          label: 'R-Value${reqR != null ? " (req. R-${reqR.toStringAsFixed(0)})" : ""}',
          state: reqR == null
              ? _CompState.missing
              : (rOk ? _CompState.pass : _CompState.fail),
          detail: reqR == null
              ? 'Enter ZIP for requirement'
              : (rOk
                  ? 'R-${totalR.toStringAsFixed(1)} ✓ meets code'
                  : totalR > 0
                      ? 'R-${totalR.toStringAsFixed(1)} — short by ${(reqR - totalR).toStringAsFixed(1)}'
                      : 'Add insulation'),
        ),
        _complianceItem(
          label: 'Pull Test',
          state: pullTestRequired ? _CompState.required : _CompState.notRequired,
          detail: pullTestRequired
              ? 'Required — ${specs.deckType} deck'
              : 'Not required for ${specs.deckType.isNotEmpty ? specs.deckType : "this deck"}',
        ),
        _complianceItem(
          label: 'Moisture Survey',
          state: moistureScanRequired ? _CompState.required : _CompState.notRequired,
          detail: moistureScanRequired
              ? 'Required — ${specs.projectType}'
              : 'Not required',
        ),
        if (hasBlockers)
          _complianceItem(
            label: 'BOM Incomplete',
            state: _CompState.fail,
            detail: 'Missing inputs — see Materials Takeoff',
          ),

        const SizedBox(height: 14),

        // ── Export buttons ───────────────────────────────────────────────────
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () {},
              icon: const Icon(Icons.download, size: 16),
              label: const Text('CSV'),
              style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.textPrimary,
                  side: BorderSide(color: AppTheme.border),
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  textStyle: const TextStyle(fontSize: 13)),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () {},
              icon: const Icon(Icons.picture_as_pdf, size: 16),
              label: const Text('PDF'),
              style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.textPrimary,
                  side: BorderSide(color: AppTheme.border),
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  textStyle: const TextStyle(fontSize: 13)),
            ),
          ),
        ]),
      ]),
    );
  }

  // ── Helpers ─────────────────────────────────────────────────────────────────

  Widget _statItem(String label, String value, String unit,
      {Color? valueColor}) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label,
          style: TextStyle(fontSize: 11, color: AppTheme.textMuted,
              fontWeight: FontWeight.w500)),
      const SizedBox(height: 3),
      Row(crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(value,
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700,
                    color: valueColor ?? AppTheme.textPrimary)),
            if (unit.isNotEmpty) ...[
              const SizedBox(width: 4),
              Text(unit,
                  style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
            ],
          ]),
    ]);
  }

  Widget _infoRow(IconData icon, String text, Color color) => Row(children: [
    Icon(icon, size: 13, color: color),
    const SizedBox(width: 6),
    Expanded(child: Text(text,
        style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w500),
        overflow: TextOverflow.ellipsis)),
  ]);

  Widget _complianceItem({
    required String label,
    required _CompState state,
    required String detail,
  }) {
    final IconData icon;
    final Color color;
    switch (state) {
      case _CompState.pass:
        icon  = Icons.check_circle;
        color = AppTheme.accent;
        break;
      case _CompState.fail:
        icon  = Icons.cancel;
        color = AppTheme.error;
        break;
      case _CompState.required:
        icon  = Icons.warning_amber;
        color = AppTheme.warning;
        break;
      case _CompState.missing:
        icon  = Icons.radio_button_unchecked;
        color = AppTheme.textMuted;
        break;
      case _CompState.notRequired:
        icon  = Icons.check_box_outline_blank;
        color = AppTheme.textMuted;
        break;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 17, color: color),
        const SizedBox(width: 8),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: TextStyle(fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: state == _CompState.notRequired
                        ? AppTheme.textSecondary : AppTheme.textPrimary)),
            Text(detail,
                style: TextStyle(fontSize: 11, color: color)),
          ],
        )),
      ]),
    );
  }

  static String _fmtArea(double v) {
    if (v >= 10000) return '${(v / 1000).toStringAsFixed(1)}k';
    return v.toStringAsFixed(0);
  }
}

enum _CompState { pass, fail, required, missing, notRequired }

// ── Chat message model ────────────────────────────────────────────────────────

class _ChatMessage {
  final String       text;
  final bool         isUser;
  final List<String> sources;
  _ChatMessage({required this.text, required this.isUser, required this.sources});
}
