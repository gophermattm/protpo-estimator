/// lib/widgets/right_panel.dart
///
/// Right panel — live project summary + AI Project Assistant (VersiBot).
///
/// Two modes accessible via tab toggle in the chat header:
///   1. SPEC mode  — original VersiBot: asks questions about Versico specs.
///   2. ASSIST mode — AI Project Assistant:
///        • Audit: scans full project state for errors/omissions, returns
///          a structured checklist rendered as tappable cards.
///        • Natural-language input: "change membrane to 80 mil" parses the
///          intent and calls the matching EstimatorNotifier method directly.
///
/// The assistant uses the Anthropic API directly (client-side) for ASSIST
/// mode and the Firebase Cloud Function for SPEC mode (unchanged).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../theme/app_theme.dart';
import '../providers/estimator_providers.dart';
import '../models/insulation_system.dart';
import '../models/section_models.dart';
import '../models/roof_geometry.dart';

// ── Mode enum ─────────────────────────────────────────────────────────────────

enum _BotMode { spec, assist }

// ── Message model ─────────────────────────────────────────────────────────────

enum _MsgType { text, audit, action, error }

class _ChatMessage {
  final String        text;
  final bool          isUser;
  final List<String>  sources;
  final _MsgType      type;
  final List<_AuditItem>? auditItems;   // populated when type == audit
  final _ActionResult?    actionResult; // populated when type == action

  const _ChatMessage({
    required this.text,
    required this.isUser,
    this.sources = const [],
    this.type    = _MsgType.text,
    this.auditItems,
    this.actionResult,
  });
}

class _AuditItem {
  final String severity;  // 'BLOCKER' | 'WARNING' | 'OK'
  final String category;
  final String message;
  const _AuditItem(this.severity, this.category, this.message);
}

class _ActionResult {
  final bool   success;
  final String description;
  final String? detail;
  const _ActionResult({required this.success, required this.description, this.detail});
}

// ══════════════════════════════════════════════════════════════════════════════
// RIGHT PANEL WIDGET
// ══════════════════════════════════════════════════════════════════════════════

class RightPanel extends ConsumerStatefulWidget {
  const RightPanel({super.key});

  @override
  ConsumerState<RightPanel> createState() => _RightPanelState();
}

class _RightPanelState extends ConsumerState<RightPanel> {
  final TextEditingController _chatController   = TextEditingController();
  final ScrollController       _scrollController = ScrollController();
  final List<_ChatMessage>     _messages         = [];
  bool     _isLoading = false;
  _BotMode _mode      = _BotMode.spec;

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _addWelcome();
  }

  @override
  void dispose() {
    _chatController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _addWelcome() {
    _messages.add(const _ChatMessage(
      text: "Hi! I'm VersiBot. Ask me anything about Versico specs, or switch to "
            "AI Assist mode to audit your project and update inputs with plain English.",
      isUser: false,
    ));
  }

  // ── Mode switch ────────────────────────────────────────────────────────────

  void _switchMode(_BotMode m) {
    if (m == _mode) return;
    setState(() {
      _mode = m;
      _messages.clear();
      if (m == _BotMode.spec) {
        _messages.add(const _ChatMessage(
          text: "Spec mode. Ask anything about Versico TPO installation, "
                "fastening patterns, flashing details, or warranty requirements.",
          isUser: false,
        ));
      } else {
        _messages.add(const _ChatMessage(
          text: "AI Assist mode. I can:\n\n"
                "• Tap \"Audit Project\" to scan for errors or omissions.\n"
                "• Tell me changes in plain English — \"change the membrane to 80 mil\", "
                "\"set roof area to 12,500 sq ft\", \"add parapet walls at 18 inches\".",
          isUser: false,
        ));
      }
    });
  }

  // ── Project state snapshot for AI ─────────────────────────────────────────

  Map<String, dynamic> _projectSnapshot() {
    final info    = ref.read(projectInfoProvider);
    final geo     = ref.read(roofGeometryProvider);
    final specs   = ref.read(systemSpecsProvider);
    final insul   = ref.read(insulationSystemProvider);
    final mem     = ref.read(membraneSystemProvider);
    final par     = ref.read(parapetWallsProvider);
    final pen     = ref.read(penetrationsProvider);
    final metal   = ref.read(metalScopeProvider);
    final rResult = ref.read(rValueResultProvider);
    final bom     = ref.read(bomProvider);

    return {
      'projectInfo': {
        'name':          info.projectName,
        'address':       info.projectAddress,
        'zipCode':       info.zipCode,
        'climateZone':   info.climateZone,
        'warrantyYears': info.warrantyYears,
        'windSpeed':     info.designWindSpeed,
        'requiredRValue': info.requiredRValue,
      },
      'geometry': {
        'totalArea':      geo.totalArea,
        'totalPerimeter': geo.totalPerimeter,
        'buildingHeight': geo.buildingHeight,
        'roofSlope':      geo.roofSlope,
        'numberOfDrains': geo.numberOfDrains,
        'shapes': geo.shapes.map((s) => {
          'type':      s.shapeType,
          'area':      s.area,
          'edges':     s.edgeLengths,
        }).toList(),
      },
      'systemSpecs': {
        'projectType':  specs.projectType,
        'deckType':     specs.deckType,
        'vaporRetarder': specs.vaporRetarder,
      },
      'insulation': {
        'numberOfLayers':   insul.numberOfLayers,
        'layer1Type':       insul.layer1.type,
        'layer1Thickness':  insul.layer1.thickness,
        'layer1Attachment': insul.layer1.attachmentMethod,
        'layer2':           insul.layer2 != null ? {
          'type':       insul.layer2!.type,
          'thickness':  insul.layer2!.thickness,
          'attachment': insul.layer2!.attachmentMethod,
        } : null,
        'hasTapered':      insul.hasTaperedInsulation,
        'hasCoverBoard':   insul.hasCoverBoard,
        'coverBoardType':  insul.coverBoard?.type,
        'totalRValue':     rResult?.totalRValue,
        'meetsCode':       rResult?.meetsCodeRequirement,
      },
      'membrane': {
        'type':       mem.membraneType,
        'thickness':  mem.thickness,
        'color':      mem.color,
        'attachment': mem.fieldAttachment,
        'rollWidth':  mem.rollWidth,
      },
      'parapetWalls': {
        'enabled':   par.hasParapetWalls,
        'heightIn':  par.parapetHeight,
        'totalLF':   par.parapetTotalLF,
        'wallType':  par.wallType,
        'areasqft':  par.parapetArea,
      },
      'penetrations': {
        'rtuTotalLF':       pen.rtuTotalLF,
        'drainCount':       pen.drainCount,
        'smallPipes':       pen.smallPipeCount,
        'largePipes':       pen.largePipeCount,
        'skylights':        pen.skylightCount,
        'scuppers':         pen.scupperCount,
        'expansionJointLF': pen.expansionJointLF,
        'pitchPans':        pen.pitchPanCount,
      },
      'metalScope': {
        'copingWidth':   metal.copingWidth,
        'copingLF':      metal.copingLF,
        'edgeMetalType': metal.edgeMetalType,
        'edgeMetalLF':   metal.edgeMetalLF,
        'gutterSize':    metal.gutterSize,
        'gutterLF':      metal.gutterLF,
        'downspouts':    metal.downspoutCount,
      },
      'bom': {
        'totalLineItems': bom.activeItems.length,
        'blockers': bom.warnings.where((w) => w.startsWith('BLOCKER')).toList(),
        'warnings': bom.warnings.where((w) => w.startsWith('WARNING')).toList(),
      },
    };
  }

  // ── SPEC mode: call Firebase Cloud Function ────────────────────────────────

  Future<void> _sendSpecMessage(String question) async {
    try {
      final response = await http.post(
        Uri.parse('https://us-central1-tpo-pro-245d1.cloudfunctions.net/askVersico'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'data': {'question': question}}),
      ).timeout(const Duration(seconds: 20));

      if (response.statusCode == 200) {
        final data    = jsonDecode(response.body);
        final result  = data['result'] ?? data;
        final answer  = result['answer'] ?? 'Sorry, I could not process that.';
        final sources = List<String>.from(result['sources'] ?? []);
        setState(() {
          _messages.add(_ChatMessage(text: answer, isUser: false, sources: sources));
          _isLoading = false;
        });
      } else {
        _addError('Server error (${response.statusCode}). Try again.');
      }
    } catch (e) {
      _addError('Connection error. Check your internet connection.');
    }
  }

  // ── ASSIST mode: call Anthropic API for audit ──────────────────────────────

  Future<void> _runAudit() async {
    setState(() {
      _messages.add(const _ChatMessage(
          text: 'Running project audit…', isUser: true));
      _isLoading = true;
    });
    _scrollToBottom();

    final snapshot = _projectSnapshot();
    final prompt = '''
You are ProTPO, an expert commercial roofing estimator AI. Audit the following project data and return a JSON array of issues. Each issue has:
- severity: "BLOCKER" | "WARNING" | "OK"  
- category: short label e.g. "Insulation", "Membrane", "Geometry"
- message: one clear sentence describing the issue or confirming compliance

Rules:
- BLOCKER = will definitely cause a bad estimate or code violation.
- WARNING = potential issue that the estimator should verify.
- OK = explicitly confirm key items that ARE correct (max 3 OKs).
- Focus on: R-value vs code requirement, deck/fastener compatibility, missing required fields, MA membrane with no deck type, parapet area impact on material qty, drain count vs tapered insulation, wind zone logic.

Return ONLY a valid JSON array. No markdown, no explanation.

Project data:
${jsonEncode(snapshot)}
''';

    try {
      final response = await http.post(
        Uri.parse('https://api.anthropic.com/v1/messages'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'model': 'claude-sonnet-4-20250514',
          'max_tokens': 1000,
          'messages': [
            {'role': 'user', 'content': prompt}
          ],
        }),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data    = jsonDecode(response.body);
        final content = (data['content'] as List).firstWhere(
            (c) => c['type'] == 'text', orElse: () => null);
        if (content == null) { _addError('Empty response from AI.'); return; }

        final raw = (content['text'] as String).trim();
        // Strip possible markdown fences
        final clean = raw.replaceAll(RegExp(r'```json|```'), '').trim();
        final List<dynamic> items = jsonDecode(clean);

        final auditItems = items.map((item) => _AuditItem(
          item['severity'] ?? 'WARNING',
          item['category'] ?? 'General',
          item['message']  ?? '',
        )).toList();

        setState(() {
          _messages.add(_ChatMessage(
            text: '${auditItems.length} items found.',
            isUser: false,
            type: _MsgType.audit,
            auditItems: auditItems,
          ));
          _isLoading = false;
        });
      } else {
        _addError('Audit failed (${response.statusCode}). Try again.');
      }
    } catch (e) {
      _addError('Audit error: ${e.toString().split('\n').first}');
    }
    _scrollToBottom();
  }

  // ── ASSIST mode: natural language input → provider update ─────────────────

  Future<void> _sendAssistMessage(String userText) async {
    final snapshot = _projectSnapshot();

    // Build a list of all available actions the AI can invoke
    const actionSchema = '''
Available actions (return exactly one as JSON):
{ "action": "updateMembraneThickness",   "value": "45 mil" | "60 mil" | "80 mil" }
{ "action": "updateMembraneAttachment",  "value": "Mechanically Attached" | "Fully Adhered" | "Rhinobond (Induction Welded)" }
{ "action": "updateMembraneColor",       "value": "White" | "Gray" | "Tan" }
{ "action": "updateRollWidth",           "value": "5'" | "10'" | "12'" }
{ "action": "updateRoofArea",            "value": <number> }
{ "action": "updateRoofPerimeter",       "value": <number> }
{ "action": "updateBuildingHeight",      "value": <number> }
{ "action": "updateWarrantyYears",       "value": 10 | 15 | 20 | 25 | 30 }
{ "action": "updateDeckType",            "value": "Metal" | "Concrete" | "Wood" | "Gypsum" | "Tectum" | "LW Concrete" }
{ "action": "updateProjectType",         "value": "New Construction" | "Recover" | "Tear-off & Replace" }
{ "action": "updateLayer1Type",          "value": "Polyiso" | "EPS" | "XPS" | "Mineral Wool" }
{ "action": "updateLayer1Thickness",     "value": <number in inches, e.g. 2.5> }
{ "action": "updateLayer1Attachment",    "value": "Mechanically Attached" | "Adhered" }
{ "action": "updateLayer2Type",          "value": "Polyiso" | "EPS" | "XPS" | "Mineral Wool" | "None" }
{ "action": "updateLayer2Thickness",     "value": <number> }
{ "action": "enableCoverBoard",          "value": true | false }
{ "action": "updateCoverBoardType",      "value": "HD Polyiso" | "Gypsum" | "DensDeck" | "DensDeck Prime" }
{ "action": "enableParapetWalls",        "value": true | false }
{ "action": "updateParapetHeight",       "value": <number in inches> }
{ "action": "updateParapetLF",           "value": <number> }
{ "action": "updateDrainCount",          "value": <number> }
{ "action": "updateSmallPipeCount",      "value": <number> }
{ "action": "updateLargePipeCount",      "value": <number> }
{ "action": "updateCopingLF",            "value": <number> }
{ "action": "updateEdgeMetalLF",         "value": <number> }
{ "action": "updateGutterLF",            "value": <number> }
{ "action": "updateProjectName",         "value": "<string>" }
{ "action": "unknown",                   "value": null, "reply": "<explain what you cannot do>" }
''';

    final prompt = '''
You are ProTPO's AI input assistant. The user wants to update their roofing project.
Parse their request and return a single JSON action object from the list below.
Return ONLY the JSON. No markdown. No explanation.

$actionSchema

Current project state summary:
- Membrane: ${snapshot['membrane']?['thickness']} ${snapshot['membrane']?['type']}, ${snapshot['membrane']?['attachment']}
- Roof area: ${snapshot['geometry']?['totalArea']} sq ft
- Insulation L1: ${snapshot['insulation']?['layer1Thickness']}" ${snapshot['insulation']?['layer1Type']}
- Deck: ${snapshot['systemSpecs']?['deckType']}
- Warranty: ${snapshot['projectInfo']?['warrantyYears']}yr

User request: "$userText"
''';

    try {
      final response = await http.post(
        Uri.parse('https://api.anthropic.com/v1/messages'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'model': 'claude-sonnet-4-20250514',
          'max_tokens': 200,
          'messages': [
            {'role': 'user', 'content': prompt}
          ],
        }),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        _addError('AI error (${response.statusCode}).');
        return;
      }

      final data    = jsonDecode(response.body);
      final content = (data['content'] as List).firstWhere(
          (c) => c['type'] == 'text', orElse: () => null);
      if (content == null) { _addError('Empty AI response.'); return; }

      final raw   = (content['text'] as String).trim();
      final clean = raw.replaceAll(RegExp(r'```json|```'), '').trim();
      final Map<String, dynamic> parsed = jsonDecode(clean);

      final action = parsed['action'] as String? ?? 'unknown';
      final value  = parsed['value'];

      if (action == 'unknown') {
        setState(() {
          _messages.add(_ChatMessage(
            text: parsed['reply'] ?? "I'm not sure how to do that yet. Try rephrasing.",
            isUser: false,
          ));
          _isLoading = false;
        });
        return;
      }

      final result = _applyAction(action, value);
      setState(() {
        _messages.add(_ChatMessage(
          text: result.description,
          isUser: false,
          type: _MsgType.action,
          actionResult: result,
        ));
        _isLoading = false;
      });
    } catch (e) {
      _addError('Could not parse response. Try rephrasing.');
    }
    _scrollToBottom();
  }

  // ── Apply action to providers ──────────────────────────────────────────────

  _ActionResult _applyAction(String action, dynamic value) {
    final n = ref.read(estimatorProvider.notifier);
    try {
      switch (action) {
        // Membrane
        case 'updateMembraneThickness':
          n.updateMembraneSystem(
              ref.read(membraneSystemProvider).copyWith(thickness: value as String));
          return _ActionResult(success: true,
              description: 'Membrane thickness updated to $value.');

        case 'updateMembraneAttachment':
          n.updateFieldAttachment(value as String);
          return _ActionResult(success: true,
              description: 'Attachment method changed to $value.');

        case 'updateMembraneColor':
          n.updateMembraneSystem(
              ref.read(membraneSystemProvider).copyWith(color: value as String));
          return _ActionResult(success: true,
              description: 'Membrane color set to $value.');

        case 'updateRollWidth':
          n.updateRollWidth(value as String);
          return _ActionResult(success: true,
              description: 'Roll width set to $value.');

        // Geometry
        case 'updateRoofArea':
          n.overrideTotalArea((value as num).toDouble());
          return _ActionResult(success: true,
              description: 'Roof area set to ${value.toStringAsFixed(0)} sq ft.',
              detail: 'This is a manual override — geometry inputs still apply.');

        case 'updateBuildingHeight':
          n.updateBuildingHeight((value as num).toDouble());
          return _ActionResult(success: true,
              description: 'Building height set to ${value}\'.');

        // Project Info
        case 'updateWarrantyYears':
          n.updateWarrantyYears((value as num).toInt());
          return _ActionResult(success: true,
              description: 'Warranty set to $value years.');

        case 'updateProjectName':
          n.updateProjectName(value as String);
          return _ActionResult(success: true,
              description: 'Project name updated to "$value".');

        // System Specs
        case 'updateDeckType':
          n.updateDeckType(value as String);
          return _ActionResult(success: true,
              description: 'Deck type changed to $value.',
              detail: 'Fastener recommendations will update automatically.');

        case 'updateProjectType':
          n.updateProjectType(value as String);
          return _ActionResult(success: true,
              description: 'Project type set to $value.');

        // Insulation
        case 'updateLayer1Type':
          final cur = ref.read(insulationSystemProvider).layer1;
          n.updateLayer1(cur.copyWith(type: value as String));
          return _ActionResult(success: true,
              description: 'Layer 1 insulation type set to $value.');

        case 'updateLayer1Thickness':
          final cur = ref.read(insulationSystemProvider).layer1;
          n.updateLayer1(cur.copyWith(thickness: (value as num).toDouble()));
          return _ActionResult(success: true,
              description: 'Layer 1 thickness set to ${value}".',
              detail: 'R-value will recalculate automatically.');

        case 'updateLayer1Attachment':
          final cur = ref.read(insulationSystemProvider).layer1;
          n.updateLayer1(cur.copyWith(attachmentMethod: value as String));
          return _ActionResult(success: true,
              description: 'Layer 1 attachment set to $value.');

        case 'updateLayer2Type':
          if (value == 'None') {
            n.setNumberOfLayers(1);
            return _ActionResult(success: true,
                description: 'Layer 2 removed. Single-layer insulation.');
          }
          n.setNumberOfLayers(2);
          final cur2 = ref.read(insulationSystemProvider).layer2;
          n.updateLayer2((cur2 ?? InsulationLayer.initial()).copyWith(
              type: value as String));
          return _ActionResult(success: true,
              description: 'Layer 2 set to $value.');

        case 'updateLayer2Thickness':
          final cur2 = ref.read(insulationSystemProvider).layer2;
          if (cur2 == null) {
            return _ActionResult(success: false,
                description: 'No Layer 2 configured yet. Enable 2 layers first.');
          }
          n.updateLayer2(cur2.copyWith(thickness: (value as num).toDouble()));
          return _ActionResult(success: true,
              description: 'Layer 2 thickness set to ${value}".');

        case 'enableCoverBoard':
          n.setCoverBoardEnabled(value as bool);
          return _ActionResult(success: true,
              description: value ? 'Cover board enabled.' : 'Cover board removed.');

        case 'updateCoverBoardType':
          final cur = ref.read(insulationSystemProvider).coverBoard;
          n.updateCoverBoard((cur ?? CoverBoard.initial()).copyWith(
              type: value as String));
          return _ActionResult(success: true,
              description: 'Cover board type set to $value.');

        // Parapet
        case 'enableParapetWalls':
          n.setParapetEnabled(value as bool);
          return _ActionResult(success: true,
              description: value
                  ? 'Parapet walls enabled. Enter height and LF in the Parapet section.'
                  : 'Parapet walls disabled.');

        case 'updateParapetHeight':
          n.updateParapetHeight((value as num).toDouble());
          return _ActionResult(success: true,
              description: 'Parapet height set to ${value}".',
              detail: 'Parapet area will recalculate.');

        case 'updateParapetLF':
          n.updateParapetTotalLF((value as num).toDouble());
          return _ActionResult(success: true,
              description: 'Parapet total LF set to $value\'.');

        // Penetrations
        case 'updateDrainCount':
          final targetCount = (value as num).toInt();
          final curDrains   = ref.read(roofGeometryProvider).drainLocations;
          if (targetCount > curDrains.length) {
            for (var i = curDrains.length; i < targetCount; i++) {
              n.addDrain(const DrainLocation(x: 0.5, y: 0.5));
            }
          } else if (targetCount < curDrains.length) {
            for (var i = curDrains.length - 1; i >= targetCount; i--) {
              n.removeDrain(i);
            }
          }
          return _ActionResult(success: true,
              description: 'Drain count set to $targetCount.',
              detail: 'Positions placed at roof center — drag in roof plan to reposition.');

        case 'updateSmallPipeCount':
          n.updateSmallPipeCount((value as num).toInt());
          return _ActionResult(success: true,
              description: 'Small pipe count set to $value.');

        case 'updateLargePipeCount':
          n.updateLargePipeCount((value as num).toInt());
          return _ActionResult(success: true,
              description: 'Large pipe count set to $value.');

        // Metal Scope
        case 'updateCopingLF':
          n.updateCopingLF((value as num).toDouble());
          return _ActionResult(success: true,
              description: 'Coping set to $value LF.');

        case 'updateEdgeMetalLF':
          n.updateEdgeMetalLF((value as num).toDouble());
          return _ActionResult(success: true,
              description: 'Edge metal set to $value LF.');

        case 'updateGutterLF':
          n.updateGutterLF((value as num).toDouble());
          return _ActionResult(success: true,
              description: 'Gutter set to $value LF.');

        default:
          return _ActionResult(success: false,
              description: 'Unknown action "$action". Try rephrasing.');
      }
    } catch (e) {
      return _ActionResult(success: false,
          description: 'Could not apply change: ${e.toString().split('\n').first}');
    }
  }

  // ── Send dispatcher ────────────────────────────────────────────────────────

  Future<void> _sendMessage() async {
    final text = _chatController.text.trim();
    if (text.isEmpty || _isLoading) return;
    setState(() {
      _messages.add(_ChatMessage(text: text, isUser: true));
      _isLoading = true;
      _chatController.clear();
    });
    _scrollToBottom();

    if (_mode == _BotMode.spec) {
      await _sendSpecMessage(text);
    } else {
      await _sendAssistMessage(text);
    }
    if (_isLoading) setState(() => _isLoading = false);
    _scrollToBottom();
  }

  void _addError(String msg) {
    setState(() {
      _messages.add(_ChatMessage(text: msg, isUser: false, type: _MsgType.error));
      _isLoading = false;
    });
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

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      const _SummarySection(),
      Divider(height: 1, color: AppTheme.border),
      Expanded(child: _buildChatSection()),
    ]);
  }

  // ════════════════════════════════════════════════════════════════════════════
  // CHAT SECTION
  // ════════════════════════════════════════════════════════════════════════════

  Widget _buildChatSection() {
    return Container(
      color: AppTheme.surfaceAlt,
      child: Column(children: [
        _buildChatHeader(),
        if (_mode == _BotMode.assist) _buildAuditButton(),
        Expanded(child: _buildMessageList()),
        _buildInputBar(),
      ]),
    );
  }

  // ── Header with mode toggle ────────────────────────────────────────────────

  Widget _buildChatHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
          color: Colors.white,
          border: Border(bottom: BorderSide(color: AppTheme.border))),
      child: Row(children: [
        // Bot icon
        Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
              gradient: _mode == _BotMode.assist
                  ? LinearGradient(colors: [
                      const Color(0xFF7C3AED),
                      const Color(0xFF4F46E5),
                    ])
                  : LinearGradient(
                      colors: [AppTheme.primary, AppTheme.secondary]),
              borderRadius: BorderRadius.circular(7)),
          child: Icon(
              _mode == _BotMode.assist
                  ? Icons.psychology
                  : Icons.smart_toy,
              color: Colors.white,
              size: 16),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_mode == _BotMode.assist ? 'AI Assist' : 'VersiBot',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13,
                    color: AppTheme.textPrimary)),
            Text(
                _mode == _BotMode.assist
                    ? 'Audit & natural language input'
                    : 'TPO Specification Assistant',
                style: TextStyle(fontSize: 10, color: AppTheme.textSecondary)),
          ]),
        ),
        // Mode toggle
        Container(
          decoration: BoxDecoration(
              color: AppTheme.surfaceAlt,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppTheme.border)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            _modeBtn('Spec', _BotMode.spec),
            _modeBtn('Assist', _BotMode.assist),
          ]),
        ),
      ]),
    );
  }

  Widget _modeBtn(String label, _BotMode m) {
    final active = _mode == m;
    return GestureDetector(
      onTap: () => _switchMode(m),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
            color: active ? AppTheme.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(6)),
        child: Text(label,
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: active ? Colors.white : AppTheme.textSecondary)),
      ),
    );
  }

  // ── Audit button (Assist mode only) ───────────────────────────────────────

  Widget _buildAuditButton() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: const Color(0xFFF5F3FF),
      child: ElevatedButton.icon(
        onPressed: _isLoading ? null : _runAudit,
        icon: const Icon(Icons.fact_check_outlined, size: 16),
        label: const Text('Audit Project', style: TextStyle(fontSize: 13)),
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF7C3AED),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 10),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          elevation: 0,
        ),
      ),
    );
  }

  // ── Message list ───────────────────────────────────────────────────────────

  Widget _buildMessageList() {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(12),
      itemCount: _messages.length + (_isLoading ? 1 : 0),
      itemBuilder: (context, index) {
        if (_isLoading && index == _messages.length) {
          return _buildTypingIndicator();
        }
        final msg = _messages[index];
        if (msg.type == _MsgType.audit) return _buildAuditCard(msg);
        if (msg.type == _MsgType.action) return _buildActionCard(msg);
        return _buildBubble(msg);
      },
    );
  }

  // ── Standard chat bubble ───────────────────────────────────────────────────

  Widget _buildBubble(_ChatMessage msg) {
    final isAssistBot = !msg.isUser && _mode == _BotMode.assist;
    final botColor = isAssistBot
        ? const Color(0xFF7C3AED)
        : AppTheme.primary;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment:
            msg.isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!msg.isUser) ...[
            Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                    color: botColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6)),
                child: Icon(
                    isAssistBot ? Icons.psychology : Icons.smart_toy,
                    color: botColor, size: 14)),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment: msg.isUser
                  ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 13, vertical: 9),
                  decoration: BoxDecoration(
                    color: msg.isUser
                        ? (isAssistBot ? const Color(0xFF7C3AED) : AppTheme.primary)
                        : (msg.type == _MsgType.error
                            ? AppTheme.error.withOpacity(0.08)
                            : Colors.white),
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(14),
                      topRight: const Radius.circular(14),
                      bottomLeft: Radius.circular(msg.isUser ? 14 : 3),
                      bottomRight: Radius.circular(msg.isUser ? 3 : 14),
                    ),
                    border: msg.type == _MsgType.error
                        ? Border.all(color: AppTheme.error.withOpacity(0.3))
                        : null,
                    boxShadow: [BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 4,
                        offset: const Offset(0, 2))],
                  ),
                  child: Text(msg.text,
                      style: TextStyle(
                          color: msg.isUser
                              ? Colors.white
                              : (msg.type == _MsgType.error
                                  ? AppTheme.error : AppTheme.textPrimary),
                          fontSize: 13,
                          height: 1.4)),
                ),
                // Sources (spec mode)
                if (msg.sources.isNotEmpty) ...[
                  const SizedBox(height: 5),
                  Wrap(
                    spacing: 4, runSpacing: 4,
                    children: msg.sources.take(3).map((s) => Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                          color: AppTheme.surfaceAlt,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: AppTheme.border)),
                      child: Text(s,
                          style: TextStyle(fontSize: 9,
                              color: AppTheme.textSecondary)),
                    )).toList(),
                  ),
                ],
              ],
            ),
          ),
          if (msg.isUser) ...[
            const SizedBox(width: 8),
            CircleAvatar(radius: 13,
                backgroundColor: AppTheme.surfaceAlt,
                child: Icon(Icons.person,
                    color: AppTheme.textSecondary, size: 14)),
          ],
        ],
      ),
    );
  }

  // ── Audit result card ──────────────────────────────────────────────────────

  Widget _buildAuditCard(_ChatMessage msg) {
    final items = msg.auditItems ?? [];
    final blockers = items.where((i) => i.severity == 'BLOCKER').toList();
    final warnings = items.where((i) => i.severity == 'WARNING').toList();
    final oks      = items.where((i) => i.severity == 'OK').toList();

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Header
        Row(children: [
          Container(padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                  color: const Color(0xFF7C3AED).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6)),
              child: const Icon(Icons.psychology,
                  color: Color(0xFF7C3AED), size: 14)),
          const SizedBox(width: 8),
          Text('Project Audit',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary)),
          const Spacer(),
          if (blockers.isNotEmpty)
            _auditBadge('${blockers.length} Blocker${blockers.length > 1 ? "s" : ""}',
                AppTheme.error),
          if (warnings.isNotEmpty) ...[
            const SizedBox(width: 4),
            _auditBadge('${warnings.length} Warning${warnings.length > 1 ? "s" : ""}',
                AppTheme.warning),
          ],
        ]),
        const SizedBox(height: 8),

        // Blockers
        if (blockers.isNotEmpty) ...[
          _auditSectionLabel('BLOCKERS', AppTheme.error),
          ...blockers.map((i) => _auditRow(i)),
          const SizedBox(height: 6),
        ],

        // Warnings
        if (warnings.isNotEmpty) ...[
          _auditSectionLabel('WARNINGS', AppTheme.warning),
          ...warnings.map((i) => _auditRow(i)),
          const SizedBox(height: 6),
        ],

        // OKs
        if (oks.isNotEmpty) ...[
          _auditSectionLabel('CONFIRMED OK', AppTheme.accent),
          ...oks.map((i) => _auditRow(i)),
        ],
      ]),
    );
  }

  Widget _auditBadge(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10)),
    child: Text(label,
        style: TextStyle(fontSize: 10, color: color,
            fontWeight: FontWeight.w700)),
  );

  Widget _auditSectionLabel(String label, Color color) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Text(label,
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
            color: color, letterSpacing: 0.5)),
  );

  Widget _auditRow(_AuditItem item) {
    final Color color;
    final IconData icon;
    switch (item.severity) {
      case 'BLOCKER': color = AppTheme.error;   icon = Icons.cancel;         break;
      case 'WARNING': color = AppTheme.warning; icon = Icons.warning_amber;  break;
      default:        color = AppTheme.accent;  icon = Icons.check_circle;   break;
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 5),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
          color: color.withOpacity(0.05),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.2))),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 8),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(item.category,
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                    color: color, letterSpacing: 0.3)),
            const SizedBox(height: 2),
            Text(item.message,
                style: TextStyle(fontSize: 12, color: AppTheme.textPrimary,
                    height: 1.3)),
          ],
        )),
      ]),
    );
  }

  // ── Action result card ─────────────────────────────────────────────────────

  Widget _buildActionCard(_ChatMessage msg) {
    final r = msg.actionResult;
    if (r == null) return _buildBubble(msg);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
                color: (r.success ? AppTheme.accent : AppTheme.error)
                    .withOpacity(0.1),
                borderRadius: BorderRadius.circular(6)),
            child: Icon(
                r.success ? Icons.check_circle : Icons.error_outline,
                color: r.success ? AppTheme.accent : AppTheme.error,
                size: 14)),
        const SizedBox(width: 8),
        Flexible(
          child: Container(
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(3),
                    topRight: Radius.circular(14),
                    bottomLeft: Radius.circular(14),
                    bottomRight: Radius.circular(14)),
                border: Border.all(
                    color: (r.success ? AppTheme.accent : AppTheme.error)
                        .withOpacity(0.25)),
                boxShadow: [BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 4,
                    offset: const Offset(0, 2))]),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(r.description,
                    style: TextStyle(fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary)),
                if (r.detail != null) ...[
                  const SizedBox(height: 4),
                  Text(r.detail!,
                      style: TextStyle(fontSize: 11,
                          color: AppTheme.textSecondary)),
                ],
              ],
            ),
          ),
        ),
      ]),
    );
  }

  // ── Input bar ──────────────────────────────────────────────────────────────

  Widget _buildInputBar() {
    final hint = _mode == _BotMode.assist
        ? 'e.g. "change membrane to 80 mil"…'
        : 'Ask about TPO specs…';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: AppTheme.border))),
      child: Row(children: [
        Expanded(
          child: TextField(
            controller: _chatController,
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(color: AppTheme.textMuted, fontSize: 13),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(22),
                  borderSide: BorderSide(color: AppTheme.border)),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(22),
                  borderSide: BorderSide(color: AppTheme.border)),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(22),
                  borderSide: BorderSide(
                      color: _mode == _BotMode.assist
                          ? const Color(0xFF7C3AED) : AppTheme.primary)),
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 15, vertical: 9),
              filled: true,
              fillColor: AppTheme.surfaceAlt,
            ),
            style: const TextStyle(fontSize: 13),
            onSubmitted: (_) => _sendMessage(),
          ),
        ),
        const SizedBox(width: 8),
        Container(
          decoration: BoxDecoration(
              gradient: LinearGradient(
                  colors: _mode == _BotMode.assist
                      ? [const Color(0xFF7C3AED), const Color(0xFF4F46E5)]
                      : [AppTheme.primary, AppTheme.primaryDark]),
              borderRadius: BorderRadius.circular(22)),
          child: IconButton(
              onPressed: _isLoading ? null : _sendMessage,
              icon: const Icon(Icons.send, color: Colors.white, size: 18),
              padding: const EdgeInsets.all(9),
              constraints: const BoxConstraints()),
        ),
      ]),
    );
  }

  // ── Typing indicator ───────────────────────────────────────────────────────

  Widget _buildTypingIndicator() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
                color: (_mode == _BotMode.assist
                    ? const Color(0xFF7C3AED) : AppTheme.primary)
                    .withOpacity(0.1),
                borderRadius: BorderRadius.circular(6)),
            child: Icon(
                _mode == _BotMode.assist ? Icons.psychology : Icons.smart_toy,
                color: _mode == _BotMode.assist
                    ? const Color(0xFF7C3AED) : AppTheme.primary,
                size: 14)),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 4,
                  offset: const Offset(0, 2))]),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            _dot(0), const SizedBox(width: 4),
            _dot(1), const SizedBox(width: 4),
            _dot(2),
          ]),
        ),
      ]),
    );
  }

  Widget _dot(int i) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0.0, end: 1.0),
    duration: Duration(milliseconds: 500 + i * 150),
    builder: (_, v, __) => Container(
        width: 7, height: 7,
        decoration: BoxDecoration(
            color: (_mode == _BotMode.assist
                ? const Color(0xFF7C3AED) : AppTheme.primary)
                .withOpacity(0.3 + 0.4 * v),
            shape: BoxShape.circle)),
  );
}

// ══════════════════════════════════════════════════════════════════════════════
// SUMMARY SECTION — unchanged, reads live from providers
// ══════════════════════════════════════════════════════════════════════════════

class _SummarySection extends ConsumerWidget {
  const _SummarySection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final info      = ref.watch(projectInfoProvider);
    final geo       = ref.watch(roofGeometryProvider);
    final specs     = ref.watch(systemSpecsProvider);
    final rResult   = ref.watch(rValueResultProvider);
    final rWarnings = ref.watch(rValueValidationProvider);
    final bom       = ref.watch(bomProvider);

    final roofArea  = geo.totalArea;
    final parapetA  = ref.watch(parapetWallsProvider).parapetArea;
    final area      = roofArea + parapetA;
    final perim     = geo.totalPerimeter;
    final totalR    = rResult?.totalRValue ?? 0.0;
    final reqR      = info.requiredRValue;
    final squares   = roofArea > 0 ? roofArea / 100 : 0.0;
    final bomCount  = bom.activeItems.length;

    final warrantyOk         = info.warrantyYears > 0;
    final pullTestRequired    = specs.deckType == 'Concrete' || specs.deckType == 'LW Concrete';
    final moistureScanRequired = specs.projectType == 'Recover' || specs.projectType == 'Tear-off & Replace';
    final rOk   = reqR != null && totalR >= reqR;
    final rFail = reqR != null && totalR > 0 && totalR < reqR;
    final zipEntered  = info.zipCode.length == 5;
    final hasBlockers = bom.warnings.any((w) => w.startsWith('BLOCKER'));

    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        Row(children: [
          Icon(Icons.summarize, color: AppTheme.primary, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text('Project Summary',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16,
                  color: AppTheme.textPrimary))),
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
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (info.projectName.isNotEmpty)
                  Text(info.projectName,
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                          color: AppTheme.textPrimary),
                      overflow: TextOverflow.ellipsis),
                if (info.customerName.isNotEmpty)
                  Text(info.customerName,
                      style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                      overflow: TextOverflow.ellipsis),
              ])),
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

        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
              color: AppTheme.surfaceAlt, borderRadius: BorderRadius.circular(8)),
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

        if (zipEntered) ...[
          _infoRow(Icons.location_on,
              info.climateZone != null
                  ? '${info.climateZone!} · ${info.designWindSpeed ?? ''}'
                  : 'ZIP ${info.zipCode} — looking up climate zone',
              AppTheme.secondary),
          const SizedBox(height: 8),
        ],

        Text('Compliance',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12,
                color: AppTheme.textSecondary, letterSpacing: 0.3)),
        const SizedBox(height: 8),

        _complianceItem(
          label: 'Warranty (${info.warrantyYears}yr)',
          state: warrantyOk ? _CompState.pass : _CompState.missing,
          detail: warrantyOk
              ? 'Versico ${info.warrantyYears}-yr NDL'
              : 'Set warranty years',
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

        Row(children: [
          Expanded(child: OutlinedButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.download, size: 16),
            label: const Text('CSV'),
            style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.textPrimary,
                side: BorderSide(color: AppTheme.border),
                padding: const EdgeInsets.symmetric(vertical: 9),
                textStyle: const TextStyle(fontSize: 13)),
          )),
          const SizedBox(width: 8),
          Expanded(child: OutlinedButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.picture_as_pdf, size: 16),
            label: const Text('PDF'),
            style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.textPrimary,
                side: BorderSide(color: AppTheme.border),
                padding: const EdgeInsets.symmetric(vertical: 9),
                textStyle: const TextStyle(fontSize: 13)),
          )),
        ]),
      ]),
    );
  }

  static Widget _statItem(String label, String value, String unit,
      {Color? valueColor}) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
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

  static Widget _infoRow(IconData icon, String text, Color color) =>
      Row(children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 6),
        Expanded(child: Text(text,
            style: TextStyle(fontSize: 11, color: color,
                fontWeight: FontWeight.w500),
            overflow: TextOverflow.ellipsis)),
      ]);

  static Widget _complianceItem({
    required String label,
    required _CompState state,
    required String detail,
  }) {
    final IconData icon;
    final Color    color;
    switch (state) {
      case _CompState.pass:
        icon  = Icons.check_circle; color = AppTheme.accent;  break;
      case _CompState.fail:
        icon  = Icons.cancel;       color = AppTheme.error;   break;
      case _CompState.required:
        icon  = Icons.warning_amber; color = AppTheme.warning; break;
      case _CompState.missing:
        icon  = Icons.radio_button_unchecked; color = AppTheme.textMuted; break;
      case _CompState.notRequired:
        icon  = Icons.check_box_outline_blank; color = AppTheme.textMuted; break;
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 17, color: color),
        const SizedBox(width: 8),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                  color: state == _CompState.notRequired
                      ? AppTheme.textSecondary : AppTheme.textPrimary)),
          Text(detail,
              style: TextStyle(fontSize: 11, color: color)),
        ])),
      ]),
    );
  }

  static String _fmtArea(double v) =>
      v >= 10000 ? '${(v / 1000).toStringAsFixed(1)}k' : v.toStringAsFixed(0);
}

enum _CompState { pass, fail, required, missing, notRequired }
