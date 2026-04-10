/// lib/services/export_service.dart
///
/// Generates CSV and PDF exports from the current estimator state.
///
/// Both formats are built entirely in Dart — no server round-trip required.
///
/// PDF uses the `pdf` package (pub.dev/packages/pdf).
/// CSV uses dart:convert — no additional package needed.
///
/// Web download uses dart:html AnchorElement (primary target).
/// On mobile/desktop the caller receives the raw bytes to save via
/// path_provider or share_plus.
///
/// ── pubspec.yaml additions required ────────────────────────────────────────
///   pdf: ^3.10.8
///   printing: ^5.12.0     (optional — for print dialog; not required for download)
///
/// ── Usage ──────────────────────────────────────────────────────────────────
///   // CSV
///   await ExportService.downloadCsv(state, bomResult);
///
///   // PDF
///   await ExportService.downloadPdf(state, bomResult, rValueResult);

// ignore_for_file: depend_on_referenced_packages
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'dart:math' as math;

import '../models/building_state.dart';
import 'platform_utils.dart';
import 'sub_instructions_builder.dart';
import '../models/estimator_state.dart';
import '../models/roof_geometry.dart';
import '../services/bom_calculator.dart';
import '../services/r_value_calculator.dart';
import '../services/qxo_pricing_service.dart';
import '../models/labor_models.dart';
import '../providers/estimator_providers.dart';
import '../services/board_schedule_calculator.dart';
import '../services/watershed_calculator.dart';
import '../services/drain_distance_calculator.dart';
import '../data/board_schedules.dart';
import '../models/insulation_system.dart';
import '../models/drainage_zone.dart';
import 'dart:ui' show Offset;

// ─── PDF SECTION TOGGLES ─────────────────────────────────────────────────────

/// Which optional pages to include in the PDF export. Cover page and Roof
/// Plan pages are always included; the toggles below control the remaining
/// content sections. All default to true.
class PdfSections {
  final bool materialsTakeoff;
  final bool fasteningSchedule;
  final bool thermalCode;
  final bool scopeOfWork;
  final bool installInstructions;

  const PdfSections({
    this.materialsTakeoff = true,
    this.fasteningSchedule = true,
    this.thermalCode = true,
    this.scopeOfWork = true,
    this.installInstructions = true,
  });

  static const all = PdfSections();
}

// ─── PUBLIC API ───────────────────────────────────────────────────────────────

class ExportService {
  ExportService._();

  /// Generates and downloads a CSV file in the browser.
  static Future<void> downloadCsv(
    EstimatorState state,
    BomResult bom,
  ) async {
    final csv = _buildCsv(state, bom);
    final bytes = utf8.encode(csv);
    final filename = _filename(state, 'csv');
    _downloadBytes(bytes, filename, 'text/csv;charset=utf-8;');
  }

  /// Generates and downloads a PDF report in the browser.
  /// [viewType] controls column visibility: 'contractor' shows cost+margin,
  /// 'customer' shows only sell price and line totals.
  /// [sections] controls which optional pages to include (defaults to all).
  static Future<void> downloadPdf(
    EstimatorState state,
    BomResult bom, {
    RValueResult? rValue,
    List<int>? logoBytes,
    Map<String, QxoPricedItem>? pricedItems,
    double globalMargin = 0.30,
    Map<String, double> itemMarginOverrides = const {},
    String viewType = 'contractor',
    List<LaborLineItem>? laborItems,
    CompanyProfile? companyProfile,
    Map<String, BomLineEdit> bomEdits = const {},
    Set<String> bomDeleted = const {},
    List<ManualBomItem> bomManualItems = const [],
    PdfSections sections = PdfSections.all,
  }) async {
    final bytes = await _buildPdf(state, bom, rValue: rValue, logoBytes: logoBytes,
        pricedItems: pricedItems, globalMargin: globalMargin,
        itemMarginOverrides: itemMarginOverrides, viewType: viewType,
        laborItems: laborItems, companyProfile: companyProfile,
        bomEdits: bomEdits, bomDeleted: bomDeleted, bomManualItems: bomManualItems,
        sections: sections);
    final filename = _filename(state, 'pdf');
    _downloadBytes(bytes, filename, 'application/pdf');
  }

  /// Returns raw PDF bytes (useful for mobile share_plus integration).
  static Future<Uint8List> buildPdfBytes(
    EstimatorState state,
    BomResult bom, {
    RValueResult? rValue,
  }) =>
      _buildPdf(state, bom, rValue: rValue);
}

// ─── FILE NAMING ──────────────────────────────────────────────────────────────

String _filename(EstimatorState state, String ext) {
  final name = state.projectInfo.projectName.isNotEmpty
      ? state.projectInfo.projectName
      : 'ProTPO_Estimate';
  final safe = name.replaceAll(RegExp(r'[^\w\s-]'), '').trim().replaceAll(' ', '_');
  final date = DateFormat('yyyy-MM-dd').format(DateTime.now());
  return '${safe}_$date.$ext';
}

// ─── WEB DOWNLOAD ─────────────────────────────────────────────────────────────

void _downloadBytes(List<int> bytes, String filename, String mimeType) {
  if (kIsWeb) {
    downloadBytes(bytes, filename, mimeType: mimeType);
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// CSV
// ═══════════════════════════════════════════════════════════════════════════════

String _buildCsv(EstimatorState state, BomResult bom) {
  final info = state.projectInfo;
  final buf  = StringBuffer();

  // ── Header block ─────────────────────────────────────────────────────────
  buf.writeln('ProTPO Estimator - Materials Takeoff');
  buf.writeln('Generated,${DateFormat('MMMM d yyyy').format(DateTime.now())}');
  buf.writeln('Project,${_q(info.projectName)}');
  buf.writeln('Customer,${_q(info.customerName)}');
  buf.writeln('Address,${_q(info.projectAddress)}');
  buf.writeln('Estimator,${_q(info.estimatorName)}');
  buf.writeln('Warranty,${info.warrantyYears} years');
  if (info.climateZone != null) {
    buf.writeln('Climate Zone,${info.climateZone}');
  }
  buf.writeln();

  // ── Building summary ──────────────────────────────────────────────────────
  buf.writeln('BUILDING SUMMARY');
  buf.writeln('Building,Area (sf),Perimeter (LF),R-Value,Attachment');
  for (final b in state.buildings) {
    final geo = b.roofGeometry;
    final mem = b.membraneSystem;
    buf.writeln('${_q(b.buildingName)},${geo.totalArea.toStringAsFixed(0)}'
        ',${geo.totalPerimeter.toStringAsFixed(0)}'
        ',-'
        ',${mem.fieldAttachment}');
  }
  buf.writeln();

  // ── BOM ───────────────────────────────────────────────────────────────────
  buf.writeln('MATERIALS TAKEOFF');
  buf.writeln('Category,Item,Order Qty,Unit,Notes,Base Qty,Waste %,Formula');

  String lastCat = '';
  for (final item in bom.activeItems) {
    final cat = item.category != lastCat ? item.category : '';
    lastCat = item.category;
    final t = item.trace;
    buf.writeln('${_q(cat)},${_q(item.name)}'
        ',${item.orderQty.toStringAsFixed(item.orderQty == item.orderQty.roundToDouble() ? 0 : 1)}'
        ',${item.unit}'
        ',${_q(item.notes)}'
        ',${t.baseQty.toStringAsFixed(2)}'
        ',${(t.wastePercent * 100).toStringAsFixed(0)}%'
        ',${_q(t.baseDescription)}');
  }
  buf.writeln();

  // ── Warnings ─────────────────────────────────────────────────────────────
  if (bom.warnings.isNotEmpty) {
    buf.writeln('NOTICES');
    for (final w in bom.warnings) buf.writeln(',${_q(w)}');
  }

  return buf.toString();
}

/// CSV-quote a value (wraps in quotes if it contains comma, quote, or newline).
String _q(String v) {
  if (v.isEmpty) return '';
  if (v.contains(',') || v.contains('"') || v.contains('\n')) {
    return '"${v.replaceAll('"', '""')}"';
  }
  return v;
}

// ═══════════════════════════════════════════════════════════════════════════════
// PDF
// ═══════════════════════════════════════════════════════════════════════════════

// ── Brand colours (matching AppTheme) ────────────────────────────────────────
const _kBlue      = PdfColor.fromInt(0xFF2563EB);
const _kBlueDark  = PdfColor.fromInt(0xFF1E40AF);
const _kGreen     = PdfColor.fromInt(0xFF10B981);
const _kAmber     = PdfColor.fromInt(0xFFF59E0B);
const _kRed       = PdfColor.fromInt(0xFFEF4444);
const _kSlate50   = PdfColor.fromInt(0xFFF8FAFC);
const _kSlate100  = PdfColor.fromInt(0xFFF1F5F9);
const _kSlate200  = PdfColor.fromInt(0xFFE2E8F0);
const _kSlate500  = PdfColor.fromInt(0xFF64748B);
const _kSlate700  = PdfColor.fromInt(0xFF334155);
const _kSlate900  = PdfColor.fromInt(0xFF0F172A);
const _kWhite     = PdfColors.white;
// PdfColor doesn't have .withOpacity() — use this helper instead.
// Blends the color with white at the given opacity (0.0–1.0).
PdfColor _pdfAlpha(PdfColor base, double opacity) {
  // PdfColor channels are 0.0–1.0
  final r = base.red   + (1.0 - base.red)   * (1.0 - opacity);
  final g = base.green + (1.0 - base.green) * (1.0 - opacity);
  final b = base.blue  + (1.0 - base.blue)  * (1.0 - opacity);
  return PdfColor(r, g, b);
}

Future<Uint8List> _buildPdf(
  EstimatorState state,
  BomResult bom, {
  RValueResult? rValue,
  List<int>? logoBytes,
  Map<String, QxoPricedItem>? pricedItems,
  double globalMargin = 0.30,
  Map<String, double> itemMarginOverrides = const {},
  String viewType = 'contractor',
  CompanyProfile? companyProfile,
  Map<String, BomLineEdit> bomEdits = const {},
  Set<String> bomDeleted = const {},
  List<ManualBomItem> bomManualItems = const [],
  List<LaborLineItem>? laborItems,
  PdfSections sections = PdfSections.all,
}) async {
  final doc  = pw.Document(
    title: state.projectInfo.projectName,
    author: state.projectInfo.estimatorName,
  );

  // Decode logo bytes into pw.MemoryImage if provided
  pw.ImageProvider? logoImg;
  if (logoBytes != null && logoBytes.isNotEmpty) {
    logoImg = pw.MemoryImage(Uint8List.fromList(logoBytes));
  }

  // Page format: US Letter
  final fmt = PdfPageFormat.letter;

  // ── Page 1 — Cover ───────────────────────────────────────────────────────
  doc.addPage(pw.Page(
    pageFormat: fmt,
    margin: const pw.EdgeInsets.all(0),
    build: (ctx) => _coverPage(state, bom, rValue, logoImg, companyProfile),
  ));

  // ── Page 2 — Roof Plan Diagram ──────────────────────────────────────────
  for (final building in state.buildings) {
    final roofPage = _roofDiagramPage(building, state, logoImg);
    if (roofPage != null) {
      doc.addPage(pw.Page(
        pageFormat: fmt,
        margin: pw.EdgeInsets.fromLTRB(40, 40, 40, 50),
        build: (ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            _pageHeader('Roof Plan - ${building.buildingName}', state, logo: logoImg, profile: companyProfile),
            pw.SizedBox(height: 16),
            roofPage,
            pw.Spacer(),
            _pageFooter(ctx),
          ],
        ),
      ));
    }

    // Board schedule page (only when tapered insulation is configured
    // and drains/scuppers are placed)
    final boardSchedule = _computeBoardScheduleForExport(
        building.roofGeometry, building.insulationSystem);
    if (boardSchedule != null && boardSchedule.rows.isNotEmpty) {
      doc.addPage(pw.Page(
        pageFormat: fmt,
        margin: pw.EdgeInsets.fromLTRB(40, 40, 40, 50),
        build: (ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            _pageHeader('Tapered Board Schedule - ${building.buildingName}',
                state, logo: logoImg, profile: companyProfile),
            pw.SizedBox(height: 16),
            ..._boardSchedulePageContent(building, boardSchedule),
            pw.Spacer(),
            _pageFooter(ctx),
          ],
        ),
      ));
    }
  }

  // ── Page 2+ -- Materials Takeoff (gated by sections.materialsTakeoff) ─────
  if (sections.materialsTakeoff) {
    final bomPages = _bomPages(bom, pricedItems: pricedItems,
        globalMargin: globalMargin, itemMarginOverrides: itemMarginOverrides,
        viewType: viewType,
        bomEdits: bomEdits, bomDeleted: bomDeleted, bomManualItems: bomManualItems,
        includeFasteners: sections.fasteningSchedule);
    for (final pageContent in bomPages) {
      doc.addPage(pw.Page(
        pageFormat: fmt,
        margin: pw.EdgeInsets.fromLTRB(40, 40, 40, 50),
        build: (ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            _pageHeader('Materials Takeoff', state, logo: logoImg, profile: companyProfile),
            pw.SizedBox(height: 16),
            ...pageContent,
            pw.Spacer(),
            _pageFooter(ctx),
          ],
        ),
      ));
    }
  }

  // ── Labor page (if items exist) ────────────────────────────────────────────
  if (laborItems != null && laborItems.isNotEmpty) {
    final isCustomer = viewType == 'customer';
    doc.addPage(pw.Page(
      pageFormat: fmt,
      margin: pw.EdgeInsets.fromLTRB(40, 40, 40, 50),
      build: (ctx) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _pageHeader('Labor Estimate', state, logo: logoImg, profile: companyProfile),
          pw.SizedBox(height: 16),
          _laborTable(laborItems, isCustomer: isCustomer),
          pw.Spacer(),
          _pageFooter(ctx),
        ],
      ),
    ));
  }

  // ── Enhanced Customer Scope of Work (gated by sections.scopeOfWork) ──────
  if (sections.scopeOfWork) {
    final scopeWidgets = buildEnhancedScope(state, bom, rValue: rValue);
    for (var i = 0; i < scopeWidgets.length; i += 30) {
      final chunk = scopeWidgets.sublist(i, math.min(i + 30, scopeWidgets.length));
      doc.addPage(pw.Page(
        pageFormat: fmt,
        margin: pw.EdgeInsets.fromLTRB(40, 40, 40, 50),
        build: (ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            _pageHeader(i == 0 ? 'Scope of Work' : 'Scope of Work (cont.)', state,
                logo: logoImg, profile: companyProfile),
            pw.SizedBox(height: 12),
            ...chunk,
            pw.Spacer(),
            _pageFooter(ctx),
          ],
        ),
      ));
    }
  }

  // ── Subcontractor Installation Instructions (gated) ──────────────────────
  if (sections.installInstructions) {
    final subWidgets = buildSubInstructions(state, bom, rValue: rValue);
    for (var i = 0; i < subWidgets.length; i += 28) {
      final chunk = subWidgets.sublist(i, math.min(i + 28, subWidgets.length));
      doc.addPage(pw.Page(
        pageFormat: fmt,
        margin: pw.EdgeInsets.fromLTRB(40, 40, 40, 50),
        build: (ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            _pageHeader(i == 0 ? 'Installation Instructions' : 'Installation Instructions (cont.)', state,
                logo: logoImg, profile: companyProfile),
            pw.SizedBox(height: 12),
            ...chunk,
            pw.Spacer(),
            _pageFooter(ctx),
          ],
        ),
      ));
    }
  }

  // ── Final page — Thermal & Compliance (gated) ──────────────────────────
  if (sections.thermalCode) {
    doc.addPage(pw.Page(
      pageFormat: fmt,
      margin: pw.EdgeInsets.fromLTRB(40, 40, 40, 50),
      build: (ctx) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _pageHeader('Thermal & Compliance', state, logo: logoImg, profile: companyProfile),
          pw.SizedBox(height: 16),
          _thermalSection(state, rValue),
          pw.Spacer(),
          _pageFooter(ctx),
        ],
      ),
    ));
  }

  return doc.save();
}

// ─── COVER PAGE ───────────────────────────────────────────────────────────────

pw.Widget _coverPage(EstimatorState state, BomResult bom, RValueResult? rv,
    pw.ImageProvider? logo, CompanyProfile? profile) {
  final info = state.projectInfo;
  final totalArea = state.buildings
      .fold(0.0, (s, b) => s + b.roofGeometry.totalArea);
  final totalSq = totalArea > 0 ? (totalArea / 100) : 0.0;
  final hasProfile = profile != null && profile.hasName;

  // Use brand color if available
  PdfColor brandDark = _kBlueDark;
  PdfColor brandLight = _kBlue;
  if (profile != null && profile.brandColorValue != 0xFF1E3A5F) {
    final c = profile.brandColorValue;
    brandLight = PdfColor(
      ((c >> 16) & 0xFF) / 255.0,
      ((c >> 8) & 0xFF) / 255.0,
      (c & 0xFF) / 255.0,
    );
    // Darken for gradient start
    brandDark = PdfColor(
      brandLight.red * 0.6,
      brandLight.green * 0.6,
      brandLight.blue * 0.6,
    );
  }

  return pw.Stack(children: [
    // Gradient header band
    pw.Positioned(
      top: 0, left: 0, right: 0,
      child: pw.Container(
        height: 200,
        decoration: pw.BoxDecoration(
          gradient: pw.LinearGradient(
            begin: pw.Alignment.topLeft,
            end: pw.Alignment.bottomRight,
            colors: [brandDark, brandLight],
          ),
        ),
      ),
    ),

    pw.Padding(
      padding: const pw.EdgeInsets.all(48),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          // Company header row — logo + name on left, contact on right
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Left: Logo + Company name
              pw.Expanded(
                flex: 3,
                child: pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    if (logo != null) ...[
                      pw.Container(
                        height: 40,
                        constraints: const pw.BoxConstraints(maxWidth: 140),
                        padding: const pw.EdgeInsets.all(3),
                        decoration: pw.BoxDecoration(
                          color: _pdfAlpha(_kWhite, 0.15),
                          borderRadius: pw.BorderRadius.circular(6),
                        ),
                        child: pw.Image(logo, fit: pw.BoxFit.contain),
                      ),
                      pw.SizedBox(width: 10),
                    ],
                    pw.Expanded(child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(_sanitize(hasProfile ? profile!.companyName : 'ProTPO'),
                            style: pw.TextStyle(color: _kWhite, fontSize: 20,
                                fontWeight: pw.FontWeight.bold)),
                        pw.Text(_sanitize(hasProfile && profile!.tagline.isNotEmpty
                            ? profile.tagline : 'Commercial Roofing Estimator'),
                            style: pw.TextStyle(color: _pdfAlpha(_kWhite, 0.75), fontSize: 10)),
                      ],
                    )),
                  ],
                ),
              ),
              // Right: Contact info
              if (hasProfile)
                pw.Expanded(
                  flex: 2,
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      if (profile!.phone.isNotEmpty)
                        pw.Text(_sanitize(profile.phone),
                            style: pw.TextStyle(color: _pdfAlpha(_kWhite, 0.9), fontSize: 9)),
                      if (profile.email.isNotEmpty)
                        pw.Text(_sanitize(profile.email),
                            style: pw.TextStyle(color: _pdfAlpha(_kWhite, 0.9), fontSize: 9)),
                      if (profile.website.isNotEmpty)
                        pw.Text(_sanitize(profile.website),
                            style: pw.TextStyle(color: _pdfAlpha(_kWhite, 0.9), fontSize: 9,
                                fontWeight: pw.FontWeight.bold)),
                      if (profile.address.isNotEmpty)
                        pw.Text(_sanitize(profile.address),
                            style: pw.TextStyle(color: _pdfAlpha(_kWhite, 0.75), fontSize: 8)),
                    ],
                  ),
                ),
            ],
          ),
          pw.SizedBox(height: 24),

          // Project title
          pw.Text(
            _sanitize(info.projectName.isNotEmpty ? info.projectName : 'Untitled Project'),
            style: pw.TextStyle(color: _kWhite, fontSize: 28,
                fontWeight: pw.FontWeight.bold),
          ),
          if (info.projectAddress.isNotEmpty) ...[
            pw.SizedBox(height: 6),
            pw.Text(_sanitize(info.projectAddress),
                style: pw.TextStyle(color: _pdfAlpha(_kWhite, 0.8), fontSize: 13)),
          ],

          pw.SizedBox(height: 48),

          // Project metadata grid
          pw.Container(
            padding: const pw.EdgeInsets.all(24),
            decoration: pw.BoxDecoration(
              color: _kWhite,
              borderRadius: pw.BorderRadius.circular(12),
              boxShadow: [pw.BoxShadow(
                color: _pdfAlpha(PdfColors.black, 0.08),
                blurRadius: 12, offset: const PdfPoint(0, 4),
              )],
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('PROJECT DETAILS',
                    style: pw.TextStyle(fontSize: 10, color: _kSlate500,
                        fontWeight: pw.FontWeight.bold, letterSpacing: 1.2)),
                pw.SizedBox(height: 16),
                pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Expanded(child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        _metaRow('Customer',  info.customerName.isNotEmpty ? info.customerName : '-'),
                        _metaRow('Estimator', info.estimatorName.isNotEmpty ? info.estimatorName : '-'),
                        _metaRow('Date',      DateFormat('MMMM d, yyyy').format(info.estimateDate)),
                        _metaRow('Warranty',  '${info.warrantyYears}-Year NDL'),
                      ],
                    )),
                    pw.Expanded(child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        _metaRow('ZIP Code',      info.zipCode.isNotEmpty ? info.zipCode : '-'),
                        _metaRow('Climate Zone',  info.climateZone ?? '-'),
                        _metaRow('Wind Speed',    info.designWindSpeed ?? '-'),
                        _metaRow('Required R',    info.requiredRValue != null
                            ? 'R-${info.requiredRValue?.toStringAsFixed(0) ?? '?'}' : '-'),
                      ],
                    )),
                  ],
                ),
              ],
            ),
          ),

          pw.SizedBox(height: 24),

          // Summary stat boxes
          pw.Row(children: [
            _statBox('Total Area',   totalArea > 0 ? '${_fmtNum(totalArea)} sf' : '-',    _kBlue),
            pw.SizedBox(width: 12),
            _statBox('Squares',      totalSq   > 0 ? '${totalSq.toStringAsFixed(1)} sq' : '-', _kBlue),
            pw.SizedBox(width: 12),
            _statBox('Buildings',    '${state.buildings.length}', _kBlue),
            pw.SizedBox(width: 12),
            _statBox('BOM Items',    '${bom.activeItems.length}', _kBlue),
          ]),

          if (rv != null) ...[
            pw.SizedBox(height: 12),
            pw.Row(children: [
              _statBox('R-Value',   'R-${rv.totalRValue.toStringAsFixed(1)}',
                  rv.meetsCodeRequirement == true ? _kGreen : _kRed),
              pw.SizedBox(width: 12),
              _statBox('Code Status', rv.meetsCodeRequirement == true ? 'COMPLIANT' : 'BELOW CODE',
                  rv.meetsCodeRequirement == true ? _kGreen : _kRed),
              pw.SizedBox(width: 12),
              _statBox('Attachment',
                  state.buildings.isNotEmpty
                      ? state.buildings.first.membraneSystem.fieldAttachment
                      : '-',
                  _kSlate700),
              pw.SizedBox(width: 12),
              _statBox('System', state.buildings.isNotEmpty
                  ? '${state.buildings.first.membraneSystem.thickness} ${state.buildings.first.membraneSystem.membraneType}'
                  : '-', _kSlate700),
            ]),
          ],

          if (bom.warnings.isNotEmpty) ...[
            pw.SizedBox(height: 16),
            pw.Container(
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                color: _pdfAlpha(_kAmber, 0.1),
                borderRadius: pw.BorderRadius.circular(8),
                border: pw.Border.all(color: _pdfAlpha(_kAmber, 0.4)),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('NOTICES', style: pw.TextStyle(
                      fontSize: 9, fontWeight: pw.FontWeight.bold,
                      color: _kAmber)),
                  pw.SizedBox(height: 6),
                  ...bom.warnings.map((w) => pw.Text('- $w',
                      style: pw.TextStyle(fontSize: 9, color: _kSlate700))),
                ],
              ),
            ),
          ],
        ],
      ),
    ),
  ]);
}

// ─── BOM PAGES (split into page-sized chunks) ─────────────────────────────────

/// Returns a list of "pages", each a list of pdf widgets that fit one page.
List<List<pw.Widget>> _bomPages(BomResult bom, {
  Map<String, QxoPricedItem>? pricedItems,
  double globalMargin = 0.30,
  Map<String, double> itemMarginOverrides = const {},
  String viewType = 'contractor',
  Map<String, BomLineEdit> bomEdits = const {},
  Set<String> bomDeleted = const {},
  List<ManualBomItem> bomManualItems = const [],
  bool includeFasteners = true,
}) {
  final pages = <List<pw.Widget>>[];
  List<pw.Widget> current = [];

  int rowCount = 0;
  const rowsPerPage = 30; // approximate

  for (final entry in bom.byCategory.entries) {
    // Skip the Fasteners & Plates category when fastening schedule is disabled
    if (!includeFasteners &&
        entry.key.toLowerCase().contains('fastener')) {
      continue;
    }
    // Filter out deleted items
    final items = entry.value.where((i) =>
        i.hasQuantity && !bomDeleted.contains('${i.category}:${i.name}')).toList();
    // Add manual items for this category
    final manualForCat = bomManualItems.where((m) => m.category == entry.key).toList();
    if (items.isEmpty && manualForCat.isEmpty) continue;

    // Category header counts as 2 rows
    final totalRows = items.length + manualForCat.length;
    if (rowCount + totalRows + 2 > rowsPerPage && current.isNotEmpty) {
      pages.add(current);
      current = [];
      rowCount = 0;
    }

    current.add(_categoryHeader(entry.key));
    current.add(pw.SizedBox(height: 6));
    current.add(_categoryTable(items, pricedItems: pricedItems,
        globalMargin: globalMargin, itemMarginOverrides: itemMarginOverrides,
        viewType: viewType, bomEdits: bomEdits, manualItems: manualForCat));
    current.add(pw.SizedBox(height: 14));
    rowCount += totalRows + 2;
  }

  // ── Project Total summary ────────────────────────────────────────────────
  if (pricedItems != null && pricedItems.isNotEmpty) {
    double grandCost = 0;
    double grandValue = 0;
    int unpricedCount = 0;
    for (final item in pricedItems.values) {
      final cost = item.totalCost;
      if (cost != null && cost > 0) {
        grandCost += cost;
        final margin = itemMarginOverrides[item.bomName] ?? globalMargin;
        grandValue += margin < 1.0 ? cost / (1 - margin) : cost;
      } else {
        unpricedCount++;
      }
    }
    final isCustomer = viewType == 'customer';
    final totalWidget = pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: pw.BoxDecoration(
        color: _pdfAlpha(_kBlue, 0.06),
        borderRadius: pw.BorderRadius.circular(8),
        border: pw.Border.all(color: _pdfAlpha(_kBlue, 0.3)),
      ),
      child: pw.Column(children: [
        if (!isCustomer) pw.Row(children: [
          pw.Expanded(child: pw.Text('TOTAL MATERIAL COST',
              style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold,
                  color: _kSlate500, letterSpacing: 0.8))),
          pw.Text('\$${grandCost.toStringAsFixed(2)}',
              style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold,
                  color: _kSlate700)),
        ]),
        if (!isCustomer) pw.SizedBox(height: 6),
        pw.Row(children: [
          pw.Expanded(child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(isCustomer ? 'TOTAL PROJECT VALUE' : 'TOTAL PROJECT VALUE (WITH MARGIN)',
                  style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold,
                      color: _kBlueDark, letterSpacing: 0.8)),
              if (unpricedCount > 0)
                pw.Text('$unpricedCount of ${pricedItems.length} items not yet priced',
                    style: pw.TextStyle(fontSize: 8, color: _kSlate500)),
            ],
          )),
          pw.Text('\$${grandValue.toStringAsFixed(2)}',
              style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold,
                  color: _kBlueDark)),
        ]),
      ]),
    );
    // Add to last page or start new page
    if (rowCount + 3 > rowsPerPage && current.isNotEmpty) {
      pages.add(current);
      current = [totalWidget];
    } else {
      current.add(totalWidget);
    }
  }

  if (current.isNotEmpty) pages.add(current);
  if (pages.isEmpty) {
    pages.add([pw.Text('No BOM items - enter roof dimensions to calculate.',
        style: pw.TextStyle(color: _kSlate500))]);
  }

  return pages;
}

pw.Widget _categoryHeader(String title) => pw.Container(
  padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 7),
  decoration: pw.BoxDecoration(
    color: _pdfAlpha(_kBlue, 0.07),
    borderRadius: pw.BorderRadius.circular(6),
  ),
  child: pw.Text(title.toUpperCase(),
      style: pw.TextStyle(fontSize: 9, color: _kBlueDark,
          fontWeight: pw.FontWeight.bold, letterSpacing: 0.8)),
);

pw.Widget _categoryTable(List<BomLineItem> items, {
  Map<String, QxoPricedItem>? pricedItems,
  double globalMargin = 0.30,
  Map<String, double> itemMarginOverrides = const {},
  String viewType = 'contractor',
  Map<String, BomLineEdit> bomEdits = const {},
  List<ManualBomItem> manualItems = const [],
}) {
  final hasPricing = pricedItems != null && pricedItems.isNotEmpty;
  final isCustomer = viewType == 'customer';

  final headerStyle = pw.TextStyle(
      fontSize: 8, fontWeight: pw.FontWeight.bold, color: _kSlate500);
  final cellStyle   = pw.TextStyle(fontSize: 9, color: _kSlate900);
  final mutedStyle  = pw.TextStyle(fontSize: 8, color: _kSlate500);
  final boldStyle   = pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold,
      color: _kBlue);
  final priceStyle  = pw.TextStyle(fontSize: 8, color: _kSlate700);
  final totalStyle  = pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold,
      color: _kGreen);

  pw.Widget cell(String text, pw.TextStyle style, {bool right = false}) =>
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
        child: pw.Text(_sanitize(text), style: style,
            textAlign: right ? pw.TextAlign.right : pw.TextAlign.left),
      );

  // Column widths depend on pricing + view type
  final Map<int, pw.TableColumnWidth> colWidths;
  final headerChildren = <pw.Widget>[];

  if (hasPricing && isCustomer) {
    // Customer: Item, QXO Desc, Qty, Unit, Unit Price (sell), Line Total
    colWidths = {
      0: const pw.FlexColumnWidth(3),
      1: const pw.FlexColumnWidth(3),
      2: const pw.FlexColumnWidth(0.8),
      3: const pw.FlexColumnWidth(0.8),
      4: const pw.FlexColumnWidth(1.2),
      5: const pw.FlexColumnWidth(1.2),
    };
    headerChildren.addAll([
      cell('ITEM', headerStyle),
      cell('DESCRIPTION', headerStyle),
      cell('QTY', headerStyle, right: true),
      cell('UNIT', headerStyle),
      cell('UNIT PRICE', headerStyle, right: true),
      cell('LINE TOTAL', headerStyle, right: true),
    ]);
  } else if (hasPricing) {
    // Contractor: Item, Qty, Unit, QXO Desc, Cost, Margin, Sell Price, Line Total
    colWidths = {
      0: const pw.FlexColumnWidth(2.5),
      1: const pw.FlexColumnWidth(0.7),
      2: const pw.FlexColumnWidth(0.7),
      3: const pw.FlexColumnWidth(2.5),
      4: const pw.FlexColumnWidth(1),
      5: const pw.FlexColumnWidth(0.6),
      6: const pw.FlexColumnWidth(1),
      7: const pw.FlexColumnWidth(1),
    };
    headerChildren.addAll([
      cell('ITEM', headerStyle),
      cell('QTY', headerStyle, right: true),
      cell('UNIT', headerStyle),
      cell('QXO DESCRIPTION', headerStyle),
      cell('COST', headerStyle, right: true),
      cell('MARGIN', headerStyle, right: true),
      cell('SELL PRICE', headerStyle, right: true),
      cell('LINE TOTAL', headerStyle, right: true),
    ]);
  } else {
    colWidths = {
      0: const pw.FlexColumnWidth(4),
      1: const pw.FlexColumnWidth(1),
      2: const pw.FlexColumnWidth(1),
      3: const pw.FlexColumnWidth(3),
      4: const pw.FlexColumnWidth(2),
    };
    headerChildren.addAll([
      cell('ITEM', headerStyle),
      cell('QTY', headerStyle, right: true),
      cell('UNIT', headerStyle),
      cell('FORMULA', headerStyle),
      cell('NOTES', headerStyle),
    ]);
  }

  return pw.Table(
    columnWidths: colWidths,
    border: pw.TableBorder(
      horizontalInside: pw.BorderSide(color: _kSlate200, width: 0.5),
    ),
    children: [
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: _kSlate100),
        children: headerChildren,
      ),
      // Build combined row list: calculated items + manual items
      ...[...items.asMap().entries.map((e) {
        final item = e.value;
        final itemKey = '${item.category}:${item.name}';
        final edit = bomEdits[itemKey];
        return _BomRowData(
          name: edit?.description ?? item.name,
          orderQty: edit?.qty ?? item.orderQty,
          unit: item.unit,
          priced: hasPricing ? pricedItems[item.name] : null,
          unitPriceOverride: edit?.unitPrice,
          partOverride: edit?.partNumber,
          marginKey: item.name,
        );
      }),
      ...manualItems.map((m) => _BomRowData(
        name: m.description,
        orderQty: m.qty,
        unit: m.unit,
        priced: null,
        unitPriceOverride: m.unitPrice,
        partOverride: m.partNumber.isNotEmpty ? m.partNumber : null,
        marginKey: m.description,
        isManual: true,
      ))].asMap().entries.map((e) {
        final rd = e.value;
        final even = e.key % 2 == 0;
        final priced = rd.priced;

        final rowChildren = <pw.Widget>[];

        // Effective price: override > QXO priced
        final effectiveCost = rd.unitPriceOverride ?? priced?.unitPrice;

        if (hasPricing && isCustomer) {
          // Customer view: Item, Desc, Qty, Unit, Sell Price, Line Total
          final desc = priced != null ? priced.qxoProductName : (rd.partOverride ?? '-');
          final margin = itemMarginOverrides[rd.marginKey] ?? globalMargin;
          final sellPrice = effectiveCost != null && margin < 1.0
              ? effectiveCost / (1 - margin) : effectiveCost;
          final lineTotal = sellPrice != null ? sellPrice * rd.orderQty : null;

          rowChildren.addAll([
            cell(rd.name, cellStyle),
            cell(desc, priceStyle),
            cell(_fmtQty(rd.orderQty), boldStyle, right: true),
            cell(rd.unit, mutedStyle),
            cell(sellPrice != null ? '\$${sellPrice.toStringAsFixed(2)}' : '-', priceStyle, right: true),
            cell(lineTotal != null ? '\$${lineTotal.toStringAsFixed(2)}' : '-', totalStyle, right: true),
          ]);
        } else if (hasPricing) {
          // Contractor view: Item, Qty, Unit, QXO Desc, Cost, Margin, Sell, Line Total
          final desc = priced != null
              ? '${priced.qxoProductName}\n${priced.qxoBrand} #${priced.qxoItemNumber}'
              : (rd.partOverride != null ? '#${rd.partOverride}' : '-');
          final margin = itemMarginOverrides[rd.marginKey] ?? globalMargin;
          final sellPrice = effectiveCost != null && margin < 1.0
              ? effectiveCost / (1 - margin) : effectiveCost;
          final lineTotal = sellPrice != null ? sellPrice * rd.orderQty : null;

          String costStr = '-';
          if (effectiveCost != null) {
            costStr = '\$${effectiveCost.toStringAsFixed(2)}';
            if (priced?.packQty != null && priced!.packQty! > 1) {
              costStr += ' /${priced.packQty}pk';
            }
          }

          rowChildren.addAll([
            cell(rd.name, cellStyle),
            cell(_fmtQty(rd.orderQty), boldStyle, right: true),
            cell(rd.unit, mutedStyle),
            cell(desc, priceStyle),
            cell(costStr, priceStyle, right: true),
            cell('${(margin * 100).round()}%', mutedStyle, right: true),
            cell(sellPrice != null ? '\$${sellPrice.toStringAsFixed(2)}' : '-', priceStyle, right: true),
            cell(lineTotal != null ? '\$${lineTotal.toStringAsFixed(2)}' : '-', totalStyle, right: true),
          ]);
        } else {
          rowChildren.addAll([
            cell(rd.name, cellStyle),
            cell(_fmtQty(rd.orderQty), boldStyle, right: true),
            cell(rd.unit, mutedStyle),
            cell('-', mutedStyle),
            cell('-', mutedStyle),
          ]);
        }

        return pw.TableRow(
          decoration: pw.BoxDecoration(color: even ? _kWhite : _kSlate50),
          children: rowChildren,
        );
      }),
    ],
  );
}

// ─── LABOR TABLE ─────────────────────────────────────────────────────────────

pw.Widget _laborTable(List<LaborLineItem> items, {bool isCustomer = false}) {
  final headerStyle = pw.TextStyle(
      fontSize: 8, fontWeight: pw.FontWeight.bold, color: _kSlate500);
  final cellStyle = pw.TextStyle(fontSize: 9, color: _kSlate900);
  final mutedStyle = pw.TextStyle(fontSize: 8, color: _kSlate500);
  final boldStyle = pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: _kBlue);
  final totalStyle = pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: _kGreen);

  pw.Widget cell(String text, pw.TextStyle style, {bool right = false}) =>
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
        child: pw.Text(_sanitize(text), style: style,
            textAlign: right ? pw.TextAlign.right : pw.TextAlign.left),
      );

  final colWidths = isCustomer
      ? {0: const pw.FlexColumnWidth(4), 1: const pw.FlexColumnWidth(1),
         2: const pw.FlexColumnWidth(1), 3: const pw.FlexColumnWidth(1.5)}
      : {0: const pw.FlexColumnWidth(4), 1: const pw.FlexColumnWidth(1),
         2: const pw.FlexColumnWidth(1), 3: const pw.FlexColumnWidth(1),
         4: const pw.FlexColumnWidth(1.5)};

  final headerRow = isCustomer
      ? [cell('ITEM', headerStyle), cell('QTY', headerStyle, right: true),
         cell('UNIT', headerStyle), cell('TOTAL', headerStyle, right: true)]
      : [cell('ITEM', headerStyle), cell('QTY', headerStyle, right: true),
         cell('UNIT', headerStyle), cell('RATE', headerStyle, right: true),
         cell('TOTAL', headerStyle, right: true)];

  double grandTotal = 0;
  for (final i in items) grandTotal += i.total;

  return pw.Column(children: [
    pw.Table(
      columnWidths: colWidths,
      border: pw.TableBorder(horizontalInside: pw.BorderSide(color: _kSlate200, width: 0.5)),
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: _kSlate100),
          children: headerRow,
        ),
        ...items.where((i) => i.hasQuantity).toList().asMap().entries.map((e) {
          final item = e.value;
          final even = e.key % 2 == 0;
          final qtyStr = item.quantity == item.quantity.roundToDouble()
              ? item.quantity.toInt().toString() : item.quantity.toStringAsFixed(1);
          final row = isCustomer
              ? [cell(item.name, cellStyle), cell(qtyStr, boldStyle, right: true),
                 cell(item.unit, mutedStyle), cell('\$${item.total.toStringAsFixed(2)}', totalStyle, right: true)]
              : [cell(item.name, cellStyle), cell(qtyStr, boldStyle, right: true),
                 cell(item.unit, mutedStyle), cell('\$${item.rate.toStringAsFixed(2)}', mutedStyle, right: true),
                 cell('\$${item.total.toStringAsFixed(2)}', totalStyle, right: true)];
          return pw.TableRow(
            decoration: pw.BoxDecoration(color: even ? _kWhite : _kSlate50),
            children: row,
          );
        }),
      ],
    ),
    pw.SizedBox(height: 10),
    pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: pw.BoxDecoration(
        color: _pdfAlpha(_kBlue, 0.06),
        borderRadius: pw.BorderRadius.circular(8),
        border: pw.Border.all(color: _pdfAlpha(_kBlue, 0.3)),
      ),
      child: pw.Row(children: [
        pw.Expanded(child: pw.Text('TOTAL LABOR',
            style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold,
                color: _kBlueDark, letterSpacing: 0.8))),
        pw.Text('\$${grandTotal.toStringAsFixed(2)}',
            style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold,
                color: _kBlueDark)),
      ]),
    ),
  ]);
}

// ─── THERMAL & SCOPE ─────────────────────────────────────────────────────────

pw.Widget _thermalSection(EstimatorState state, RValueResult? rv) {
  if (rv == null) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(14),
      decoration: pw.BoxDecoration(
          color: _kSlate100, borderRadius: pw.BorderRadius.circular(8)),
      child: pw.Text('Thermal data unavailable - enter ZIP code to load climate zone.',
          style: pw.TextStyle(color: _kSlate500, fontSize: 10)),
    );
  }

  final info   = state.projectInfo;
  final meetsCode = rv.meetsCodeRequirement == true;

  return pw.Container(
    padding: const pw.EdgeInsets.all(20),
    decoration: pw.BoxDecoration(
      color: _kWhite,
      borderRadius: pw.BorderRadius.circular(10),
      border: pw.Border.all(color: _kSlate200),
    ),
    child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      pw.Text('THERMAL & CODE COMPLIANCE',
          style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold,
              color: _kSlate500, letterSpacing: 1)),
      pw.SizedBox(height: 14),

      pw.Row(children: [
        // R-value hero
        pw.Container(
          width: 140, padding: const pw.EdgeInsets.all(16),
          decoration: pw.BoxDecoration(
            gradient: pw.LinearGradient(colors: [_kBlueDark, _kBlue],
                begin: pw.Alignment.topLeft, end: pw.Alignment.bottomRight),
            borderRadius: pw.BorderRadius.circular(10),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('Total R-Value', style: pw.TextStyle(
                  color: _pdfAlpha(_kWhite, 0.8), fontSize: 10)),
              pw.SizedBox(height: 6),
              pw.Text('R-${rv.totalRValue.toStringAsFixed(1)}',
                  style: pw.TextStyle(color: _kWhite, fontSize: 30,
                      fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 8),
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: pw.BoxDecoration(
                    color: meetsCode ? _kGreen : _kRed,
                    borderRadius: pw.BorderRadius.circular(10)),
                child: pw.Text(meetsCode ? 'COMPLIANT' : 'BELOW CODE',
                    style: pw.TextStyle(color: _kWhite, fontSize: 9,
                        fontWeight: pw.FontWeight.bold)),
              ),
            ],
          ),
        ),
        pw.SizedBox(width: 20),

        // Breakdown table
        pw.Expanded(child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('R-Value Breakdown',
                style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold,
                    color: _kSlate700)),
            pw.SizedBox(height: 8),
            ...(_rvComponents(rv)).map((c) => pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 4),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(c[0], style: pw.TextStyle(fontSize: 9, color: _kSlate700)),
                  pw.Text('R-${double.parse(c[1]).toStringAsFixed(1)}',
                      style: pw.TextStyle(fontSize: 9,
                          fontWeight: pw.FontWeight.bold, color: _kSlate900)),
                ],
              ),
            )),
            pw.Divider(color: _kSlate200, thickness: 0.5),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('Total', style: pw.TextStyle(
                    fontSize: 10, fontWeight: pw.FontWeight.bold, color: _kSlate900)),
                pw.Text('R-${rv.totalRValue.toStringAsFixed(1)}',
                    style: pw.TextStyle(fontSize: 10,
                        fontWeight: pw.FontWeight.bold, color: _kBlue)),
              ],
            ),
            if (info.requiredRValue != null) ...[
              pw.SizedBox(height: 10),
              pw.Container(
                padding: const pw.EdgeInsets.all(8),
                decoration: pw.BoxDecoration(
                  color: _pdfAlpha(meetsCode ? _kGreen : _kRed, 0.08),
                  borderRadius: pw.BorderRadius.circular(6),
                  border: pw.Border.all(
                      color: _pdfAlpha(meetsCode ? _kGreen : _kRed, 0.4)),
                ),
                child: pw.Text(
                  meetsCode
                      ? 'Meets IECC/ASHRAE 90.1 minimum of R-${info.requiredRValue?.toStringAsFixed(0) ?? '?'} for ${info.climateZone ?? "climate zone"}'
                      : 'Below IECC/ASHRAE 90.1 minimum of R-${info.requiredRValue?.toStringAsFixed(0) ?? '?'} - additional insulation required',
                  style: pw.TextStyle(fontSize: 9,
                      color: meetsCode ? _kGreen : _kRed),
                ),
              ),
            ],
          ],
        )),
      ]),
    ]),
  );
}


/// Build a flat list of [label, rValue-string] pairs from RValueResult.
List<List<String>> _rvComponents(RValueResult rv) {
  final result = <List<String>>[];
  result.add(['Layer 1 - \${rv.layer1.materialType} \${rv.layer1.thickness}"',
      rv.layer1.rValue.toString()]);
  if (rv.layer2 != null) {
    result.add(['Layer 2 - \${rv.layer2!.materialType} \${rv.layer2!.thickness}"',
        rv.layer2!.rValue.toString()]);
  }
  if (rv.tapered != null) {
    result.add(['Tapered - \${rv.tapered!.materialType}',
        rv.tapered!.averageRValue.toString()]);
  }
  if (rv.coverBoard != null) {
    result.add(['Cover Board - \${rv.coverBoard!.materialType} \${rv.coverBoard!.thickness}"',
        rv.coverBoard!.rValue.toString()]);
  }
  result.add(['Membrane', rv.membraneContribution.toString()]);
  return result;
}

pw.Widget _scopeSection(EstimatorState state) {
  final info  = state.projectInfo;
  final b     = state.buildings.isNotEmpty ? state.buildings.first : null;
  if (b == null) return pw.SizedBox.shrink();

  final specs = b.systemSpecs;
  final ins   = b.insulationSystem;
  final mem   = b.membraneSystem;
  final par   = b.parapetWalls;
  final met   = b.metalScope;

  final isRecover   = specs.projectType.contains('Recover');
  final isTearOff   = specs.projectType.contains('Tear-off');
  final hasParapet  = par.hasParapetWalls;

  final sections = <_ScopeEntry>[
    _ScopeEntry('General',
        'Furnish all labor, materials, equipment, and supervision to complete the '
        'commercial roofing system as specified. '
        '${state.buildings.length > 1 ? "Work encompasses ${state.buildings.length} buildings." : ""}'
        ' Total roof area: ${_fmtNum(state.buildings.fold(0.0, (s, bld) => s + bld.roofGeometry.totalArea))} square feet.'),
    if (isTearOff) _ScopeEntry('Tear-Off',
        'Remove existing ${specs.existingRoofType.isNotEmpty ? specs.existingRoofType : "roof"} '
        'system down to structural deck. Dispose of all debris per local regulations. '
        'Inspect deck for damage prior to installation.'),
    if (isRecover) _ScopeEntry('Preparation',
        'Prepare existing roof surface to receive new system. Clean, fasten any loose areas, '
        'and ensure existing system is structurally sound.'),
    _ScopeEntry('Deck Preparation',
        'Clean and prepare ${specs.deckType} deck surface. '
        '${specs.vaporRetarder != "None" ? "Install ${specs.vaporRetarder} vapor retarder." : "No vapor retarder required."}'),
    _ScopeEntry('Insulation',
        'Install ${ins.numberOfLayers}-layer insulation system: '
        '${ins.layer1.type} ${ins.layer1.thickness}" '
        '(${ins.layer1.attachmentMethod.toLowerCase()})'
        '${ins.layer2 != null && ins.layer2!.thickness > 0 ? " + ${ins.layer2!.type} ${ins.layer2!.thickness}\" (${ins.layer2!.attachmentMethod.toLowerCase()})" : ""}. '
        '${ins.hasCoverBoard && ins.coverBoard != null ? "Cover board: ${ins.coverBoard!.type} ${ins.coverBoard!.thickness}\" (${ins.coverBoard!.attachmentMethod.toLowerCase()})." : ""}'
        ' Total R-value target per thermal analysis.'),
    _ScopeEntry('Membrane',
        'Install Versico ${mem.thickness} ${mem.membraneType} membrane, ${mem.fieldAttachment.toLowerCase()}, '
        '${mem.rollWidth}×100\' rolls. All seams hot-air welded minimum 1.5" width. '
        'Color: ${mem.color}.'),
    if (hasParapet) _ScopeEntry('Parapet & Flashings',
        'Install TPO wall flashing at all parapet walls '
        '(${par.parapetHeight.toStringAsFixed(0)}" height, ${par.parapetTotalLF.toStringAsFixed(0)} LF). '
        'Terminate with ${par.terminationType.toLowerCase()} at top. '
        'All penetration flashings per Versico detail drawings.'),
    _ScopeEntry('Sheet Metal',
        '${met.copingLF > 0 ? "Install ${met.copingWidth} coping cap, ${met.copingLF.toStringAsFixed(0)} LF. " : ""}'
        '${met.edgeMetalLF > 0 ? "Install ${met.edgeMetalType} edge metal, ${met.edgeMetalLF.toStringAsFixed(0)} LF. " : ""}'
        '${met.gutterLF > 0 ? "Install ${met.gutterSize} gutter, ${met.gutterLF.toStringAsFixed(0)} LF with ${met.downspoutCount} downspouts. " : ""}'
        'All metal 24-gauge minimum.'),
    _ScopeEntry('Warranty',
        'Provide Versico ${info.warrantyYears}-year NDL manufacturer warranty upon completion. '
        'Contractor to provide 2-year workmanship warranty.'),
  ];

  return pw.Container(
    padding: const pw.EdgeInsets.all(20),
    decoration: pw.BoxDecoration(
      color: _kWhite,
      borderRadius: pw.BorderRadius.circular(10),
      border: pw.Border.all(color: _kSlate200),
    ),
    child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      pw.Text('SCOPE OF WORK',
          style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold,
              color: _kSlate500, letterSpacing: 1)),
      pw.SizedBox(height: 14),
      ...sections.where((s) => s.body.trim().isNotEmpty && s.body.trim() != '.').map(
        (s) => pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 10),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(s.title.toUpperCase(),
                  style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold,
                      color: _kBlue, letterSpacing: 0.8)),
              pw.SizedBox(height: 3),
              pw.Text(s.body,
                  style: pw.TextStyle(fontSize: 9, color: _kSlate700, lineSpacing: 1.4)),
            ],
          ),
        ),
      ),
    ]),
  );
}

// ─── SHARED WIDGETS ───────────────────────────────────────────────────────────

pw.Widget _pageHeader(String section, EstimatorState state,
    {pw.ImageProvider? logo, CompanyProfile? profile}) =>
  pw.Column(
  crossAxisAlignment: pw.CrossAxisAlignment.start,
  children: [
    pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        // Left: Company name or ProTPO
        pw.Row(children: [
          if (logo != null) ...[
            pw.Container(
              height: 28,
              constraints: const pw.BoxConstraints(maxWidth: 120),
              child: pw.Image(logo, fit: pw.BoxFit.contain),
            ),
            pw.SizedBox(width: 8),
          ],
          pw.Text(
            _sanitize(profile != null && profile.hasName ? profile.companyName : 'ProTPO Estimator'),
            style: pw.TextStyle(fontSize: 9, color: _kSlate500, fontWeight: pw.FontWeight.bold)),
        ]),
        // Right: Contact + Date
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            if (profile != null && profile.phone.isNotEmpty)
              pw.Text(profile.phone, style: pw.TextStyle(fontSize: 8, color: _kSlate500)),
            pw.Text(DateFormat('MMM d, yyyy').format(DateTime.now()),
                style: pw.TextStyle(fontSize: 8, color: _kSlate500)),
          ],
        ),
      ],
    ),
    pw.SizedBox(height: 4),
    pw.Row(children: [
      pw.Text(
        state.projectInfo.projectName.isNotEmpty
            ? state.projectInfo.projectName : 'Untitled Project',
        style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold,
            color: _kSlate900),
      ),
      pw.SizedBox(width: 12),
      pw.Text(section,
          style: pw.TextStyle(fontSize: 12, color: _kSlate500)),
    ]),
    pw.SizedBox(height: 6),
    pw.Divider(color: _kSlate200, thickness: 0.5),
  ],
);

pw.Widget _pageFooter(pw.Context ctx) => pw.Column(children: [
  pw.Divider(color: _kSlate200, thickness: 0.5),
  pw.SizedBox(height: 4),
  pw.Row(
    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
    children: [
      pw.Text('Generated by ProTPO Estimator',
          style: pw.TextStyle(fontSize: 8, color: _kSlate500)),
      pw.Text('Page ${ctx.pageNumber} of ${ctx.pagesCount}',
          style: pw.TextStyle(fontSize: 8, color: _kSlate500)),
    ],
  ),
]);

pw.Widget _metaRow(String label, String value) => pw.Padding(
  padding: const pw.EdgeInsets.only(bottom: 8),
  child: pw.Row(children: [
    pw.SizedBox(
      width: 90,
      child: pw.Text(label,
          style: pw.TextStyle(fontSize: 10, color: _kSlate500,
              fontWeight: pw.FontWeight.bold)),
    ),
    pw.Expanded(child: pw.Text(value,
        style: pw.TextStyle(fontSize: 10, color: _kSlate900))),
  ]),
);

pw.Widget _statBox(String label, String value, PdfColor color) =>
    pw.Expanded(child: pw.Container(
  padding: const pw.EdgeInsets.all(14),
  decoration: pw.BoxDecoration(
    color: _pdfAlpha(color, 0.07),
    borderRadius: pw.BorderRadius.circular(8),
    border: pw.Border.all(color: _pdfAlpha(color, 0.25)),
  ),
  child: pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text(label,
          style: pw.TextStyle(fontSize: 8, color: color,
              fontWeight: pw.FontWeight.bold)),
      pw.SizedBox(height: 4),
      pw.Text(value,
          style: pw.TextStyle(fontSize: 13, color: color,
              fontWeight: pw.FontWeight.bold)),
    ],
  ),
));

// ─── ROOF PLAN DIAGRAM ──────────────────────────────────────────────────────

/// Edge type colors matching the Flutter UI renderer
const _kEdgeColors = <String, PdfColor>{
  'Eave':    PdfColor.fromInt(0xFF10B981),
  'Ridge':   PdfColor.fromInt(0xFFEF4444),
  'Hip':     PdfColor.fromInt(0xFFF59E0B),
  'Valley':  PdfColor.fromInt(0xFF8B5CF6),
  'Rake':    PdfColor.fromInt(0xFF3B82F6),
  'Parapet': PdfColor.fromInt(0xFF6366F1),
  'Wall':    PdfColor.fromInt(0xFF64748B),
};

PdfColor _pdfEdgeColor(String type) =>
    _kEdgeColors[type] ?? const PdfColor.fromInt(0xFF374151);

/// Polygon walk - same algorithm as roof_renderer.dart
const _kPdfTurns = <String, List<int>>{
  'Rectangle': [1, 1, 1, 1],
  'Square':    [1, 1, 1, 1],
  'L-Shape':   [1, 1, 1, -1, 1],
  'T-Shape':   [1, 1, -1, 1, 1, -1, 1],
  'U-Shape':   [1, 1, 1, -1, -1, 1, 1],
};

List<List<double>>? _pdfBuildPolygon(RoofShape shape) {
  final edges = shape.edgeLengths;
  if (edges.length < 4 || edges.every((e) => e <= 0)) return null;
  final turns = _kPdfTurns[shape.shapeType] ?? List.filled(edges.length, 1);
  const ddx = [1.0, 0.0, -1.0, 0.0];
  const ddy = [0.0, -1.0, 0.0, 1.0];
  final pts = <List<double>>[[0.0, 0.0]];
  var x = 0.0, y = 0.0, dir = 0;
  for (int i = 0; i < edges.length; i++) {
    x += ddx[dir % 4] * edges[i];
    y += ddy[dir % 4] * edges[i];
    pts.add([x, y]);
    if (i < turns.length) dir = (dir + (turns[i] == 1 ? 1 : 3)) % 4;
  }
  pts.removeLast();
  return pts;
}

pw.Widget? _roofDiagramPage(BuildingState building, EstimatorState state,
    pw.ImageProvider? logo) {
  final geo = building.roofGeometry;
  if (geo.shapes.isEmpty || geo.totalArea <= 0) return null;

  // Build all polygons
  final allPolygons = <List<List<double>>>[];
  final allShapes = <RoofShape>[];
  for (final shape in geo.shapes) {
    final pts = _pdfBuildPolygon(shape);
    if (pts != null) {
      allPolygons.add(pts);
      allShapes.add(shape);
    }
  }
  if (allPolygons.isEmpty) return null;

  // Compute bounds
  double minX = double.infinity, maxX = double.negativeInfinity;
  double minY = double.infinity, maxY = double.negativeInfinity;
  for (final pts in allPolygons) {
    for (final p in pts) {
      minX = math.min(minX, p[0]); maxX = math.max(maxX, p[0]);
      minY = math.min(minY, p[1]); maxY = math.max(maxY, p[1]);
    }
  }
  final roofW = maxX - minX;
  final roofH = maxY - minY;
  if (roofW <= 0 || roofH <= 0) return null;

  // Scale to fit Letter page (612x792 pt, ~702 usable with margins).
  // Page content stack (all values approximate):
  //   header 60 + sp 16 + building-info 50 + sp 12 + taper-banner 50
  //   + sp 8 + DIAGRAM + sp 10 + edge-legend 20 + taper-key 20 + footer 30
  //   = ~276 + DIAGRAM
  // Safe diagram height: 702 - 276 - 30 (buffer) = ~396.
  const maxW = 525.0;
  const maxH = 380.0;
  const pad = 40.0;
  final scaleX = (maxW - pad * 2) / roofW;
  final scaleY = (maxH - pad * 2) / roofH;
  final scale = math.min(scaleX, scaleY);

  double tx(double rx) => pad + (rx - minX) * scale;
  double ty(double ry) => pad + (ry - minY) * scale;

  // ── Compute low points, watershed, and panel sequence for taper overlay ──
  final insulation = building.insulationSystem;
  final hasTaper = insulation.hasTaper &&
      insulation.taperDefaults != null &&
      (geo.drainLocations.isNotEmpty || geo.scupperLocations.isNotEmpty) &&
      allPolygons.isNotEmpty;

  final List<List<double>> primaryPts =
      allPolygons.isNotEmpty ? allPolygons.first : const <List<double>>[];
  final lowPoints = <Offset>[];
  if (hasTaper) {
    for (final d in geo.drainLocations) {
      lowPoints.add(Offset(d.x, d.y));
    }
    for (final s in geo.scupperLocations) {
      if (s.edgeIndex >= primaryPts.length) continue;
      final a = primaryPts[s.edgeIndex];
      final b = primaryPts[(s.edgeIndex + 1) % primaryPts.length];
      lowPoints.add(Offset(
        a[0] + (b[0] - a[0]) * s.position,
        a[1] + (b[1] - a[1]) * s.position,
      ));
    }
  }

  List<ZoneWatershed> zones = const [];
  PanelSequence? panelSeq;
  if (hasTaper && lowPoints.isNotEmpty) {
    zones = WatershedCalculator.computeZones(
      polygonVertices: primaryPts.map((p) => Offset(p[0], p[1])).toList(),
      lowPoints: lowPoints,
      totalPolygonArea: geo.totalArea,
    );
    final d = insulation.taperDefaults!;
    panelSeq = lookupPanelSequence(
      manufacturer: d.manufacturer,
      taperRate: d.taperRate,
      profileType: d.profileType,
    );
  }

  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      // Building info
      pw.Container(
        padding: const pw.EdgeInsets.all(12),
        decoration: pw.BoxDecoration(
          color: _kSlate100,
          borderRadius: pw.BorderRadius.circular(8),
        ),
        child: pw.Row(children: [
          pw.Expanded(child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('Total Area: ${_fmtNum(geo.totalArea)} sf',
                  style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold,
                      color: _kSlate900)),
              pw.Text('Perimeter: ${geo.totalPerimeter.toStringAsFixed(0)} LF | '
                  '${geo.shapes.length} shape(s)',
                  style: pw.TextStyle(fontSize: 9, color: _kSlate500)),
            ],
          )),
          if (geo.windZones.perimeterZoneWidth > 0)
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text('Wind Zone Width: ${geo.windZones.perimeterZoneWidth.toStringAsFixed(1)}\'',
                    style: pw.TextStyle(fontSize: 9, color: _kSlate500)),
                pw.Text('Field: ${geo.windZones.fieldZoneArea.toStringAsFixed(0)} sf | '
                    'Perim: ${geo.windZones.perimeterZoneArea.toStringAsFixed(0)} sf | '
                    'Corner: ${geo.windZones.cornerZoneArea.toStringAsFixed(0)} sf',
                    style: pw.TextStyle(fontSize: 8, color: _kSlate500)),
              ],
            ),
        ]),
      ),
      pw.SizedBox(height: 12),

      // Taper info banner (only if tapered insulation is active)
      if (hasTaper) ...[
        pw.Container(
          padding: const pw.EdgeInsets.all(8),
          decoration: pw.BoxDecoration(
            color: const PdfColor.fromInt(0xFFEFF6FF),
            border: pw.Border.all(color: const PdfColor.fromInt(0xFFBFDBFE)),
            borderRadius: pw.BorderRadius.circular(6),
          ),
          child: pw.Row(children: [
            pw.Expanded(child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'Tapered Polyiso: ${insulation.taperDefaults!.manufacturer} '
                  '${insulation.taperDefaults!.taperRate} '
                  '(${insulation.taperDefaults!.profileType}) - '
                  'min ${_fmtIn(insulation.taperDefaults!.minThickness)} at drain',
                  style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold,
                      color: const PdfColor.fromInt(0xFF1E3A8A)),
                ),
                pw.Text(
                  '${lowPoints.length} low point${lowPoints.length == 1 ? "" : "s"}'
                  '${geo.drainLocations.isNotEmpty ? " (${geo.drainLocations.length} drain${geo.drainLocations.length == 1 ? "" : "s"})" : ""}'
                  '${geo.scupperLocations.isNotEmpty ? " (${geo.scupperLocations.length} scupper${geo.scupperLocations.length == 1 ? "" : "s"})" : ""}'
                  ' | ${zones.length} drainage zone${zones.length == 1 ? "" : "s"}',
                  style: pw.TextStyle(fontSize: 8, color: _kSlate500),
                ),
              ],
            )),
          ]),
        ),
        pw.SizedBox(height: 8),
      ],

      // Roof drawing - use positioned widgets for a clean diagram
      pw.Container(
        width: maxW,
        height: maxH,
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: _kSlate200),
          borderRadius: pw.BorderRadius.circular(8),
          color: _kWhite,
        ),
        child: pw.Stack(children: [
          // Single unified CustomPaint draws everything on the canvas:
          // polygon fill (watershed bands or solid), edges, drains, scuppers,
          // and flow arrows. Text labels layered on top as Positioned widgets.
          pw.Positioned.fill(
            child: pw.CustomPaint(
              size: PdfPoint(0, 0),
              painter: (PdfGraphics canvas, PdfPoint size) {
                for (int pi = 0; pi < allPolygons.length; pi++) {
                  final pts = allPolygons[pi];
                  final shape = allShapes[pi];
                  final n = pts.length;

                  // Fill polygon: watershed bands if active, else solid blue
                  if (pi == 0 && hasTaper && zones.isNotEmpty) {
                    _pdfDrawWatershed(canvas, pts, lowPoints, zones,
                        panelSeq, tx, ty, maxH);
                  } else {
                    final fillColor = shape.operation == 'Subtract'
                        ? const PdfColor(0.945, 0.961, 0.976)
                        : const PdfColor(0.859, 0.918, 0.996);
                    canvas.setFillColor(fillColor);
                    canvas.moveTo(tx(pts.first[0]), maxH - ty(pts.first[1]));
                    for (final p in pts.skip(1)) {
                      canvas.lineTo(tx(p[0]), maxH - ty(p[1]));
                    }
                    canvas.closePath();
                    canvas.fillPath();
                  }

                  // Draw edges on top
                  for (int i = 0; i < n; i++) {
                    final a = pts[i];
                    final b = pts[(i + 1) % n];
                    final edgeType = i < shape.edgeTypes.length
                        ? shape.edgeTypes[i] : 'Eave';
                    canvas.setStrokeColor(_pdfEdgeColor(edgeType));
                    canvas.setLineWidth(2.0);
                    canvas.drawLine(
                      tx(a[0]), maxH - ty(a[1]),
                      tx(b[0]), maxH - ty(b[1]),
                    );
                    canvas.strokePath();
                  }

                  // Draw drains (circles)
                  if (pi == 0) {
                    for (final d in geo.drainLocations) {
                      canvas.setFillColor(const PdfColor(1, 1, 1));
                      canvas.drawEllipse(tx(d.x), maxH - ty(d.y), 6, 6);
                      canvas.fillPath();
                      canvas.setStrokeColor(const PdfColor(0.055, 0.647, 0.914));
                      canvas.setLineWidth(1.8);
                      canvas.drawEllipse(tx(d.x), maxH - ty(d.y), 6, 6);
                      canvas.strokePath();
                      canvas.setFillColor(const PdfColor(0.055, 0.647, 0.914));
                      canvas.drawEllipse(tx(d.x), maxH - ty(d.y), 2.5, 2.5);
                      canvas.fillPath();
                    }
                  }
                }

                // Scuppers — drawn once for the primary polygon
                if (hasTaper && geo.scupperLocations.isNotEmpty) {
                  _pdfDrawScuppers(canvas, primaryPts, geo.scupperLocations,
                      tx, ty, maxH);
                }
              },
            ),
          ),
          // Measurement labels (positioned text widgets)
          for (int pi = 0; pi < allPolygons.length; pi++)
            ..._pdfDrawMeasurementLabels(
                allPolygons[pi], allShapes[pi], tx, ty),
          // Panel letter labels per band (positioned text widgets)
          if (hasTaper && panelSeq != null && lowPoints.isNotEmpty)
            ..._pdfDrawBandLabels(primaryPts, lowPoints, panelSeq, tx, ty),
        ]),
      ),

      pw.SizedBox(height: 10),

      // Edge type legend
      pw.Wrap(spacing: 16, runSpacing: 6, children: [
        for (final entry in _kEdgeColors.entries)
          pw.Row(mainAxisSize: pw.MainAxisSize.min, children: [
            pw.Container(width: 20, height: 3,
                decoration: pw.BoxDecoration(color: entry.value)),
            pw.SizedBox(width: 4),
            pw.Text(entry.key,
                style: pw.TextStyle(fontSize: 8, color: _kSlate500)),
          ]),
      ]),

      if (hasTaper) ...[
        pw.SizedBox(height: 6),
        pw.Row(children: [
          pw.Container(width: 12, height: 12,
              decoration: pw.BoxDecoration(
                  color: const PdfColor.fromInt(0xFF3B82F6))),
          pw.SizedBox(width: 4),
          pw.Text('Drain', style: pw.TextStyle(fontSize: 8, color: _kSlate500)),
          pw.SizedBox(width: 12),
          pw.Container(width: 12, height: 8,
              decoration: pw.BoxDecoration(
                  color: const PdfColor.fromInt(0xFF8B5CF6))),
          pw.SizedBox(width: 4),
          pw.Text('Scupper', style: pw.TextStyle(fontSize: 8, color: _kSlate500)),
          pw.SizedBox(width: 12),
          pw.Text('Shaded bands show where each panel letter installs (X to ZZ from drain outward).',
              style: pw.TextStyle(fontSize: 7, color: _kSlate500,
                  fontStyle: pw.FontStyle.italic)),
        ]),
      ],
    ],
  );
}

/// Draws watershed zones as colored bands on the PDF canvas. Each cell is
/// colored by the row index within its zone, creating concentric bands.
///
/// PDF alpha compositing for fill colors is unreliable across viewers — we
/// use pre-blended solid colors instead (white-blended tints).
void _pdfDrawWatershed(
  PdfGraphics canvas,
  List<List<double>> primaryPts,
  List<Offset> lowPoints,
  List<ZoneWatershed> zones,
  PanelSequence? panelSeq,
  double Function(double) tx,
  double Function(double) ty,
  double maxH,
) {
  if (primaryPts.length < 3 || lowPoints.isEmpty) return;

  // Pre-blended zone colors: light (near drain) to darker (at ridge).
  // Each sub-array is [lightR, lightG, lightB, darkR, darkG, darkB].
  const zoneColors = [
    [0.88, 0.93, 1.00, 0.58, 0.73, 0.96], // blue
    [0.92, 0.88, 1.00, 0.72, 0.60, 0.96], // purple
    [0.87, 0.97, 0.92, 0.46, 0.84, 0.70], // green
    [1.00, 0.94, 0.80, 0.98, 0.78, 0.40], // orange
    [0.99, 0.87, 0.94, 0.95, 0.52, 0.74], // pink
    [0.86, 0.96, 0.98, 0.40, 0.82, 0.90], // cyan
  ];

  // Compute bounds of primary polygon
  double minX = primaryPts.first[0], maxX = minX;
  double minY = primaryPts.first[1], maxY = minY;
  for (final p in primaryPts) {
    if (p[0] < minX) minX = p[0];
    if (p[0] > maxX) maxX = p[0];
    if (p[1] < minY) minY = p[1];
    if (p[1] > maxY) maxY = p[1];
  }
  final w = maxX - minX;
  final h = maxY - minY;
  if (w <= 0 || h <= 0) return;

  // Clip to primary polygon
  canvas.saveContext();
  canvas.moveTo(tx(primaryPts.first[0]), maxH - ty(primaryPts.first[1]));
  for (final p in primaryPts.skip(1)) {
    canvas.lineTo(tx(p[0]), maxH - ty(p[1]));
  }
  canvas.closePath();
  canvas.clipPath();

  const gridN = 50;
  const panelWidthFt = 4.0;
  final stepX = w / gridN;
  final stepY = h / gridN;
  // Screen-space cell dimensions: tx(x+stepX) - tx(x) = stepX * scale
  // where scale is the tx's internal scale factor
  final cellWPts = (tx(minX + stepX) - tx(minX)).abs() + 0.5;
  final cellHPts = (ty(minY + stepY) - ty(minY)).abs() + 0.5;

  // First pass: determine per-zone max row for banding normalization
  final zoneMaxRow = List<int>.filled(lowPoints.length, 0);
  final cellNearest = List<List<int>>.generate(
      gridN, (_) => List<int>.filled(gridN, 0));
  final cellRow = List<List<int>>.generate(
      gridN, (_) => List<int>.filled(gridN, 0));
  for (int ix = 0; ix < gridN; ix++) {
    for (int iy = 0; iy < gridN; iy++) {
      final cx = minX + (ix + 0.5) * stepX;
      final cy = minY + (iy + 0.5) * stepY;
      int nearestIdx = 0;
      double nearestDist = _pdfDist(cx, cy, lowPoints[0].dx, lowPoints[0].dy);
      for (int i = 1; i < lowPoints.length; i++) {
        final d = _pdfDist(cx, cy, lowPoints[i].dx, lowPoints[i].dy);
        if (d < nearestDist) {
          nearestDist = d;
          nearestIdx = i;
        }
      }
      final row = (nearestDist / panelWidthFt).floor();
      cellNearest[ix][iy] = nearestIdx;
      cellRow[ix][iy] = row;
      if (row > zoneMaxRow[nearestIdx]) zoneMaxRow[nearestIdx] = row;
    }
  }

  // Second pass: draw cells with interpolated solid colors (no alpha)
  for (int ix = 0; ix < gridN; ix++) {
    for (int iy = 0; iy < gridN; iy++) {
      final nearestIdx = cellNearest[ix][iy];
      final row = cellRow[ix][iy];
      final maxRow = zoneMaxRow[nearestIdx];
      final t = maxRow > 0 ? (row / maxRow).clamp(0.0, 1.0) : 0.0;
      final palette = zoneColors[nearestIdx % zoneColors.length];
      // Interpolate light (t=0, near drain) to dark (t=1, at ridge)
      final r = palette[0] + (palette[3] - palette[0]) * t;
      final g = palette[1] + (palette[4] - palette[1]) * t;
      final b = palette[2] + (palette[5] - palette[2]) * t;

      final cellMinXr = minX + ix * stepX;
      final cellMinYr = minY + iy * stepY;
      final sx = tx(cellMinXr);
      final sy = maxH - ty(cellMinYr);

      canvas.setFillColor(PdfColor(r, g, b));
      canvas.drawRect(sx, sy - cellHPts, cellWPts, cellHPts);
      canvas.fillPath();
    }
  }

  canvas.restoreContext();

  // Third pass (after unclipping): flow arrows from each polygon vertex
  // toward its nearest low point, showing drainage direction.
  canvas.setStrokeColor(const PdfColor(0.12, 0.25, 0.67)); // dark blue
  canvas.setLineWidth(1.0);
  for (final v in primaryPts) {
    int nearestIdx = 0;
    double nearestDist = _pdfDist(v[0], v[1], lowPoints[0].dx, lowPoints[0].dy);
    for (int i = 1; i < lowPoints.length; i++) {
      final d = _pdfDist(v[0], v[1], lowPoints[i].dx, lowPoints[i].dy);
      if (d < nearestDist) {
        nearestDist = d;
        nearestIdx = i;
      }
    }

    final target = lowPoints[nearestIdx];
    final dx = target.dx - v[0];
    final dy = target.dy - v[1];
    final len = math.sqrt(dx * dx + dy * dy);
    if (len < 1e-6) continue;
    final ux = dx / len;
    final uy = dy / len;

    final startR = [v[0] + ux * len * 0.18, v[1] + uy * len * 0.18];
    final endR = [v[0] + ux * len * 0.55, v[1] + uy * len * 0.55];
    final sx = tx(startR[0]);
    final sy = maxH - ty(startR[1]);
    final ex = tx(endR[0]);
    final ey = maxH - ty(endR[1]);

    canvas.drawLine(sx, sy, ex, ey);
    canvas.strokePath();

    const headLen = 5.0;
    final ang = math.atan2(ey - sy, ex - sx);
    final h1x = ex - headLen * math.cos(ang - 0.5);
    final h1y = ey - headLen * math.sin(ang - 0.5);
    final h2x = ex - headLen * math.cos(ang + 0.5);
    final h2y = ey - headLen * math.sin(ang + 0.5);
    canvas.drawLine(ex, ey, h1x, h1y);
    canvas.strokePath();
    canvas.drawLine(ex, ey, h2x, h2y);
    canvas.strokePath();
  }
}

double _pdfDist(double x1, double y1, double x2, double y2) {
  final dx = x1 - x2;
  final dy = y1 - y2;
  return math.sqrt(dx * dx + dy * dy);
}

/// Draws only the polygon edges (no fill, no labels) — used to re-draw
/// edges on top of the watershed fill so they remain visible.
void _pdfDrawEdgesOnly(
  PdfGraphics canvas,
  List<List<double>> pts,
  RoofShape shape,
  double Function(double) tx,
  double Function(double) ty,
  double maxH,
) {
  final n = pts.length;
  for (int i = 0; i < n; i++) {
    final a = pts[i];
    final b = pts[(i + 1) % n];
    final edgeType = i < shape.edgeTypes.length ? shape.edgeTypes[i] : 'Eave';
    canvas.setStrokeColor(_pdfEdgeColor(edgeType));
    canvas.setLineWidth(2.0);
    canvas.drawLine(tx(a[0]), maxH - ty(a[1]), tx(b[0]), maxH - ty(b[1]));
    canvas.strokePath();
  }
  // Drains (re-draw on top of watershed)
  canvas.setFillColor(const PdfColor(0.055, 0.647, 0.914));
}

/// Draws scupper markers as purple rectangles on polygon edges with arrows
/// pointing outward (showing water flow direction).
void _pdfDrawScuppers(
  PdfGraphics canvas,
  List<List<double>> primaryPts,
  List<ScupperLocation> scuppers,
  double Function(double) tx,
  double Function(double) ty,
  double maxH,
) {
  if (primaryPts.length < 3) return;
  const scupperColor = PdfColor(0.55, 0.36, 0.96); // purple

  // Polygon centroid for outward normal
  final cx = primaryPts.fold(0.0, (s, p) => s + p[0]) / primaryPts.length;
  final cy = primaryPts.fold(0.0, (s, p) => s + p[1]) / primaryPts.length;

  for (final s in scuppers) {
    if (s.edgeIndex >= primaryPts.length) continue;
    final a = primaryPts[s.edgeIndex];
    final b = primaryPts[(s.edgeIndex + 1) % primaryPts.length];
    final rx = a[0] + (b[0] - a[0]) * s.position;
    final ry = a[1] + (b[1] - a[1]) * s.position;
    final sx = tx(rx);
    final sy = maxH - ty(ry);

    // Outward normal (in canvas Y-up since we flipped sy)
    final dx = b[0] - a[0];
    final dy = b[1] - a[1];
    final len = math.sqrt(dx * dx + dy * dy);
    if (len < 1e-6) continue;
    double nx = -dy / len;
    double ny = dx / len;
    if (nx * (cx - rx) + ny * (cy - ry) > 0) { nx = -nx; ny = -ny; }
    // In PDF canvas Y is up, flip ny
    ny = -ny;

    const halfW = 6.0;
    const depth = 7.0;
    final tanX = -ny;
    final tanY = nx;
    final p1x = sx + tanX * halfW;
    final p1y = sy + tanY * halfW;
    final p2x = sx - tanX * halfW;
    final p2y = sy - tanY * halfW;
    final p3x = p2x + nx * depth;
    final p3y = p2y + ny * depth;
    final p4x = p1x + nx * depth;
    final p4y = p1y + ny * depth;

    canvas.setFillColor(PdfColors.white);
    canvas.moveTo(p1x, p1y);
    canvas.lineTo(p2x, p2y);
    canvas.lineTo(p3x, p3y);
    canvas.lineTo(p4x, p4y);
    canvas.closePath();
    canvas.fillPath();

    canvas.setStrokeColor(scupperColor);
    canvas.setLineWidth(1.5);
    canvas.moveTo(p1x, p1y);
    canvas.lineTo(p2x, p2y);
    canvas.lineTo(p3x, p3y);
    canvas.lineTo(p4x, p4y);
    canvas.closePath();
    canvas.strokePath();

    // Flow arrow through scupper pointing outward
    canvas.setStrokeColor(scupperColor);
    canvas.setLineWidth(1.5);
    canvas.drawLine(sx, sy, sx + nx * (depth + 4), sy + ny * (depth + 4));
    canvas.strokePath();
  }
}

/// Returns positioned text widgets for panel letter labels along the primary
/// taper axis for each low point's zone.
List<pw.Widget> _pdfDrawBandLabels(
  List<List<double>> primaryPts,
  List<Offset> lowPoints,
  PanelSequence panelSeq,
  double Function(double) tx,
  double Function(double) ty,
) {
  final widgets = <pw.Widget>[];
  const panelWidthFt = 4.0;
  final vertices = primaryPts.map((p) => Offset(p[0], p[1])).toList();

  for (int i = 0; i < lowPoints.length; i++) {
    final lp = lowPoints[i];

    // Find farthest vertex in this zone
    double farDist = 0;
    Offset farVertex = lp;
    for (final v in vertices) {
      int nearestIdx = 0;
      double nearestDist = _pdfDist(v.dx, v.dy, lowPoints[0].dx, lowPoints[0].dy);
      for (int j = 1; j < lowPoints.length; j++) {
        final d = _pdfDist(v.dx, v.dy, lowPoints[j].dx, lowPoints[j].dy);
        if (d < nearestDist) {
          nearestDist = d;
          nearestIdx = j;
        }
      }
      if (nearestIdx == i && nearestDist > farDist) {
        farDist = nearestDist;
        farVertex = v;
      }
    }

    if (farDist < panelWidthFt) continue;

    final numRows = (farDist / panelWidthFt).ceil();
    final dx = farVertex.dx - lp.dx;
    final dy = farVertex.dy - lp.dy;
    final len = math.sqrt(dx * dx + dy * dy);
    if (len < 1e-6) continue;
    final ux = dx / len;
    final uy = dy / len;

    for (int r = 0; r < numRows; r++) {
      final seqIdx = r % panelSeq.panels.length;
      final cycle = r ~/ panelSeq.panels.length;
      final panel = panelSeq.panels[seqIdx];

      final bandDist = (r + 0.5) * panelWidthFt;
      final lx = lp.dx + ux * bandDist;
      final ly = lp.dy + uy * bandDist;

      final label = cycle > 0 ? '${panel.letter}*' : panel.letter;
      widgets.add(pw.Positioned(
        left: tx(lx) - 6,
        top: ty(ly) - 5,
        child: pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 2, vertical: 1),
          decoration: pw.BoxDecoration(
            color: const PdfColor.fromInt(0xEEFFFFFF),
            borderRadius: pw.BorderRadius.circular(2),
          ),
          child: pw.Text(label,
              style: pw.TextStyle(
                fontSize: 7,
                fontWeight: pw.FontWeight.bold,
                color: const PdfColor.fromInt(0xFF1E3A8A),
              )),
        ),
      ));
    }
  }

  return widgets;
}

String _fmtIn(double v) =>
    v == v.roundToDouble() ? '${v.toInt()}"' : '$v"';

/// Returns just the measurement text labels (length + edge type) for a shape,
/// as positioned pw widgets. Canvas drawing of edges/fill happens elsewhere.
List<pw.Widget> _pdfDrawMeasurementLabels(
  List<List<double>> pts,
  RoofShape shape,
  double Function(double) tx,
  double Function(double) ty,
) {
  final widgets = <pw.Widget>[];
  final n = pts.length;
  final edges = shape.edgeLengths;

  // Centroid in canvas coords
  final cx = pts.fold(0.0, (s, p) => s + tx(p[0])) / n;
  final cy = pts.fold(0.0, (s, p) => s + ty(p[1])) / n;

  for (int i = 0; i < n && i < edges.length; i++) {
    final len = edges[i];
    if (len <= 0) continue;

    final ax = tx(pts[i][0]), ay = ty(pts[i][1]);
    final bx = tx(pts[(i + 1) % n][0]), by = ty(pts[(i + 1) % n][1]);
    final mx = (ax + bx) / 2, my = (ay + by) / 2;

    final edgeType = i < shape.edgeTypes.length ? shape.edgeTypes[i] : 'Eave';
    final color = _pdfEdgeColor(edgeType);

    // Outward normal for label placement
    final dx = bx - ax, dy = by - ay;
    final dist = math.sqrt(dx * dx + dy * dy);
    if (dist < 1) continue;
    var nx = -dy / dist, ny = dx / dist;
    if (nx * (cx - mx) + ny * (cy - my) > 0) { nx = -nx; ny = -ny; }

    final labelX = mx + nx * 18;
    final labelY = my + ny * 18;

    final labelStr =
        '${len.toStringAsFixed(len == len.roundToDouble() ? 0 : 1)}\'';
    widgets.add(pw.Positioned(
      left: labelX - 15,
      top: labelY - 5,
      child: pw.Text(labelStr,
          style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold,
              color: _kSlate700)),
    ));
    widgets.add(pw.Positioned(
      left: labelX - 15,
      top: labelY + 5,
      child: pw.Text(edgeType.length > 5 ? edgeType.substring(0, 5) : edgeType,
          style: pw.TextStyle(fontSize: 7, color: color)),
    ));
  }

  return widgets;
}

/// Renders a single roof shape as a list of positioned pw widgets.
/// Uses edge-by-edge lines and positioned text labels.
/// When [skipFill] is true, the polygon fill is omitted (used when watershed
/// zones will be drawn on top).
List<pw.Widget> _pdfDrawShape(
    List<List<double>> pts, RoofShape shape, RoofGeometry geo,
    double Function(double) tx, double Function(double) ty, double maxH,
    {bool skipFill = false}) {
  final widgets = <pw.Widget>[];
  final n = pts.length;
  final edges = shape.edgeLengths;

  // Compute centroid for outward normal direction
  final cx = pts.fold(0.0, (s, p) => s + tx(p[0])) / n;
  final cy = pts.fold(0.0, (s, p) => s + ty(p[1])) / n;

  for (int i = 0; i < n && i < edges.length; i++) {
    final len = edges[i];
    if (len <= 0) continue;

    final ax = tx(pts[i][0]), ay = ty(pts[i][1]);
    final bx = tx(pts[(i + 1) % n][0]), by = ty(pts[(i + 1) % n][1]);
    final mx = (ax + bx) / 2, my = (ay + by) / 2;

    final edgeType = i < shape.edgeTypes.length ? shape.edgeTypes[i] : 'Eave';
    final color = _pdfEdgeColor(edgeType);

    // Calculate outward normal for label placement
    final dx = bx - ax, dy = by - ay;
    final dist = math.sqrt(dx * dx + dy * dy);
    if (dist < 1) continue;
    var nx = -dy / dist, ny = dx / dist;
    if (nx * (cx - mx) + ny * (cy - my) > 0) { nx = -nx; ny = -ny; }

    final labelX = mx + nx * 18;
    final labelY = my + ny * 18;

    // Measurement label
    final labelStr =
        '${len.toStringAsFixed(len == len.roundToDouble() ? 0 : 1)}\'';
    widgets.add(pw.Positioned(
      left: labelX - 15,
      top: labelY - 5,
      child: pw.Text(labelStr,
          style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold,
              color: _kSlate700)),
    ));

    // Edge type abbreviation below measurement
    widgets.add(pw.Positioned(
      left: labelX - 15,
      top: labelY + 5,
      child: pw.Text(edgeType.length > 5 ? edgeType.substring(0, 5) : edgeType,
          style: pw.TextStyle(fontSize: 7, color: color)),
    ));
  }

  // Draw edge lines using CustomPaint (only lines, no text)
  widgets.insert(0, pw.Positioned.fill(
    child: pw.CustomPaint(
      size: PdfPoint(0, 0),
      painter: (PdfGraphics canvas, PdfPoint size) {
        // Fill polygon (skip if watershed will draw on top)
        if (!skipFill) {
          final fillColor = shape.operation == 'Subtract'
              ? const PdfColor(0.945, 0.961, 0.976)
              : const PdfColor(0.859, 0.918, 0.996);
          canvas.setFillColor(fillColor);
          canvas.moveTo(tx(pts.first[0]), maxH - ty(pts.first[1]));
          for (final p in pts.skip(1)) {
            canvas.lineTo(tx(p[0]), maxH - ty(p[1]));
          }
          canvas.closePath();
          canvas.fillPath();
        }

        // Draw edges
        for (int i = 0; i < n; i++) {
          final a = pts[i];
          final b = pts[(i + 1) % n];
          final edgeType = i < shape.edgeTypes.length
              ? shape.edgeTypes[i] : 'Eave';
          final color = _pdfEdgeColor(edgeType);
          canvas.setStrokeColor(color);
          canvas.setLineWidth(2.0);
          canvas.drawLine(
            tx(a[0]), maxH - ty(a[1]),
            tx(b[0]), maxH - ty(b[1]),
          );
          canvas.strokePath();
        }

        // Drains
        for (final d in geo.drainLocations) {
          canvas.setFillColor(const PdfColor(0.055, 0.647, 0.914));
          canvas.drawEllipse(tx(d.x), maxH - ty(d.y), 5, 5);
          canvas.fillPath();
        }
      },
    ),
  ));

  return widgets;
}

/// Unified row data for PDF table — covers both calculated and manual items.
class _BomRowData {
  final String name;
  final double orderQty;
  final String unit;
  final QxoPricedItem? priced;
  final double? unitPriceOverride;
  final String? partOverride;
  final String marginKey;
  final bool isManual;

  const _BomRowData({
    required this.name,
    required this.orderQty,
    required this.unit,
    required this.priced,
    this.unitPriceOverride,
    this.partOverride,
    required this.marginKey,
    this.isManual = false,
  });
}

// ─── HELPERS ─────────────────────────────────────────────────────────────────

/// Replace Unicode characters unsupported by the default PDF font (Helvetica/Latin-1).
/// Em/en dashes, smart quotes, multiplication sign, bullet, degree, etc.
String _sanitize(String v) => v
    .replaceAll('\u2014', '-')    // em dash
    .replaceAll('\u2013', '-')    // en dash
    .replaceAll('\u2018', "'")    // left single quote
    .replaceAll('\u2019', "'")    // right single quote
    .replaceAll('\u201C', '"')    // left double quote
    .replaceAll('\u201D', '"')    // right double quote
    .replaceAll('\u00D7', 'x')   // multiplication sign
    .replaceAll('\u2022', '-')    // bullet
    .replaceAll('\u2026', '...')  // ellipsis
    .replaceAll('\u00AE', '(R)') // registered trademark
    .replaceAll('\u2122', '(TM)')// trademark
    .replaceAll('\u00A0', ' ')   // non-breaking space
    .replaceAll(RegExp(r'[^\x00-\xFF]'), ''); // strip anything else outside Latin-1

String _fmtNum(double v) {
  if (v >= 10000) return '${(v / 1000).toStringAsFixed(1)}k';
  return v.toStringAsFixed(0);
}

String _fmtQty(double v) =>
    v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

class _ScopeEntry {
  final String title;
  final String body;
  const _ScopeEntry(this.title, this.body);
}

// ─── TAPERED BOARD SCHEDULE PAGE ──────────────────────────────────────────────

/// Computes a board schedule for the PDF export (duplicates logic from
/// estimator_providers to avoid provider dependencies in export code).
BoardScheduleResult? _computeBoardScheduleForExport(
    RoofGeometry geo, InsulationSystem insulation) {
  if (!insulation.hasTaper || insulation.taperDefaults == null) return null;
  if (geo.drainLocations.isEmpty && geo.scupperLocations.isEmpty) return null;

  final primaryShape = geo.shapes.isNotEmpty ? geo.shapes.first : null;
  if (primaryShape == null) return null;
  final ptsRaw = _pdfBuildPolygon(primaryShape);
  if (ptsRaw == null || ptsRaw.isEmpty) return null;
  final vertices = ptsRaw.map((p) => Offset(p[0], p[1])).toList();

  final lowPoints = <Offset>[
    ...geo.drainLocations.map((d) => Offset(d.x, d.y)),
    ...geo.scupperLocations.map((s) {
      if (s.edgeIndex >= vertices.length) return Offset.zero;
      final a = vertices[s.edgeIndex];
      final b = vertices[(s.edgeIndex + 1) % vertices.length];
      return Offset(
        a.dx + (b.dx - a.dx) * s.position,
        a.dy + (b.dy - a.dy) * s.position,
      );
    }),
  ];
  if (lowPoints.isEmpty) return null;

  final totalArea = geo.totalArea;
  if (totalArea <= 0) return null;

  final defaults = insulation.taperDefaults!;

  final zones = WatershedCalculator.computeZones(
    polygonVertices: vertices,
    lowPoints: lowPoints,
    totalPolygonArea: totalArea,
  );

  if (zones.isEmpty || zones.every((z) => z.maxDistance <= 0)) {
    final distance = DrainDistanceCalculator.bestTaperDistance(
      polygonVertices: vertices,
      drainXs: lowPoints.map((p) => p.dx).toList(),
      drainYs: lowPoints.map((p) => p.dy).toList(),
    );
    if (distance <= 0) return null;
    final roofWidth = DrainDistanceCalculator.roofWidthPerpendicular(vertices);
    if (roofWidth <= 0) return null;
    return BoardScheduleCalculator.compute(BoardScheduleInput(
      distance: distance,
      taperRate: defaults.taperRate,
      minThickness: defaults.minThickness,
      manufacturer: defaults.manufacturer,
      profileType: defaults.profileType,
      roofWidthFt: roofWidth,
    ));
  }

  // Aggregate per-zone schedules
  final zoneResults = <BoardScheduleResult>[];
  for (final zone in zones) {
    if (zone.maxDistance <= 0 || zone.effectiveWidth <= 0) continue;
    final result = BoardScheduleCalculator.compute(BoardScheduleInput(
      distance: zone.maxDistance,
      taperRate: defaults.taperRate,
      minThickness: defaults.minThickness,
      manufacturer: defaults.manufacturer,
      profileType: defaults.profileType,
      roofWidthFt: zone.effectiveWidth,
    ));
    zoneResults.add(result);
  }
  if (zoneResults.isEmpty) return null;
  if (zoneResults.length == 1) return zoneResults.first;

  // Merge results
  final taperedCounts = <String, int>{};
  final flatFillCounts = <double, int>{};
  int totalTapered = 0;
  int totalFlatFill = 0;
  double totalTaperedSF = 0;
  double totalFlatFillSF = 0;
  double maxThickness = 0;
  double minThickness = double.infinity;
  double weightedAvgSum = 0;
  double totalArea2 = 0;
  final warnings = <String>{};
  for (int i = 0; i < zoneResults.length; i++) {
    final r = zoneResults[i];
    final zone = zones[i];
    r.taperedPanelCounts.forEach((k, v) {
      taperedCounts[k] = (taperedCounts[k] ?? 0) + v;
    });
    r.flatFillCounts.forEach((k, v) {
      flatFillCounts[k] = (flatFillCounts[k] ?? 0) + v;
    });
    totalTapered += r.totalTaperedPanels;
    totalFlatFill += r.totalFlatFillPanels;
    totalTaperedSF += r.totalTaperedSF;
    totalFlatFillSF += r.totalFlatFillSF;
    if (r.maxThicknessAtRidge > maxThickness) maxThickness = r.maxThicknessAtRidge;
    if (r.minThicknessAtDrain < minThickness) minThickness = r.minThicknessAtDrain;
    weightedAvgSum += r.avgTaperThickness * zone.area;
    totalArea2 += zone.area;
    for (final w in r.warnings) warnings.add(w);
  }
  final totalPanels = totalTapered + totalFlatFill;
  return BoardScheduleResult(
    rows: zoneResults.expand((r) => r.rows).toList(),
    maxThickness: maxThickness,
    taperedPanelCounts: taperedCounts,
    flatFillCounts: flatFillCounts,
    totalTaperedPanels: totalTapered,
    totalFlatFillPanels: totalFlatFill,
    totalPanels: totalPanels,
    totalPanelsWithWaste: (totalPanels * 1.10).ceil(),
    totalTaperedSF: totalTaperedSF,
    totalFlatFillSF: totalFlatFillSF,
    minThicknessAtDrain: minThickness == double.infinity ? 0 : minThickness,
    avgTaperThickness: totalArea2 > 0 ? weightedAvgSum / totalArea2 : 0,
    maxThicknessAtRidge: maxThickness,
    warnings: warnings.toList(),
  );
}

/// Builds the content for the tapered board schedule page.
List<pw.Widget> _boardSchedulePageContent(
    BuildingState building, BoardScheduleResult schedule) {
  final insul = building.insulationSystem;
  final d = insul.taperDefaults!;
  final geo = building.roofGeometry;

  final sortedPanels = schedule.taperedPanelCounts.entries.toList()
    ..sort((a, b) => a.key.compareTo(b.key));
  final sortedFill = schedule.flatFillCounts.entries.toList()
    ..sort((a, b) => a.key.compareTo(b.key));

  const rPerInch = 5.7;
  final minR = schedule.minThicknessAtDrain * rPerInch;
  final avgR = schedule.avgTaperThickness * rPerInch;
  final maxR = schedule.maxThicknessAtRidge * rPerInch;

  return [
    // Configuration summary
    pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: const PdfColor.fromInt(0xFFEFF6FF),
        border: pw.Border.all(color: const PdfColor.fromInt(0xFFBFDBFE)),
        borderRadius: pw.BorderRadius.circular(6),
      ),
      child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Text('Tapered Insulation Configuration',
            style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold,
                color: const PdfColor.fromInt(0xFF1E3A8A))),
        pw.SizedBox(height: 6),
        pw.Row(children: [
          _cfgCell('Manufacturer', d.manufacturer),
          _cfgCell('Profile', d.profileType),
          _cfgCell('Taper Rate', d.taperRate),
          _cfgCell('Min Thickness', _fmtIn(d.minThickness)),
        ]),
        pw.SizedBox(height: 4),
        pw.Row(children: [
          _cfgCell('Attachment', d.attachmentMethod),
          _cfgCell('Drains', '${geo.drainLocations.length}'),
          _cfgCell('Scuppers', '${geo.scupperLocations.length}'),
          _cfgCell('Max Thickness', _fmtIn(schedule.maxThicknessAtRidge)),
        ]),
      ]),
    ),
    pw.SizedBox(height: 14),

    // Panel counts table
    pw.Text('Tapered Panel Counts (${d.manufacturer} ${d.taperRate})',
        style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold,
            color: _kSlate900)),
    pw.SizedBox(height: 6),
    pw.Table(
      border: pw.TableBorder.all(color: _kSlate200, width: 0.5),
      columnWidths: const {
        0: pw.FlexColumnWidth(2),
        1: pw.FlexColumnWidth(3),
        2: pw.FlexColumnWidth(2),
        3: pw.FlexColumnWidth(2),
      },
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: _kSlate100),
          children: [
            _tableHeader('Panel'),
            _tableHeader('Thin - Thick'),
            _tableHeader('Count'),
            _tableHeader('Area (sf)'),
          ],
        ),
        for (final entry in sortedPanels)
          pw.TableRow(children: [
            _tableCell(entry.key, bold: true),
            _tableCell(_panelThicknessLabel(entry.key, d)),
            _tableCell('${entry.value}'),
            _tableCell('${(entry.value * 16).toStringAsFixed(0)}'),
          ]),
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: _kSlate50),
          children: [
            _tableCell('Total', bold: true),
            _tableCell(''),
            _tableCell('${schedule.totalTaperedPanels}', bold: true),
            _tableCell('${schedule.totalTaperedSF.toStringAsFixed(0)}', bold: true),
          ],
        ),
      ],
    ),
    pw.SizedBox(height: 12),

    // Flat fill table
    if (sortedFill.isNotEmpty) ...[
      pw.Text('Flat Fill Polyiso (${d.manufacturer})',
          style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold,
              color: _kSlate900)),
      pw.SizedBox(height: 6),
      pw.Table(
        border: pw.TableBorder.all(color: _kSlate200, width: 0.5),
        columnWidths: const {
          0: pw.FlexColumnWidth(3),
          1: pw.FlexColumnWidth(2),
          2: pw.FlexColumnWidth(2),
        },
        children: [
          pw.TableRow(
            decoration: const pw.BoxDecoration(color: _kSlate100),
            children: [
              _tableHeader('Thickness'),
              _tableHeader('Count'),
              _tableHeader('Area (sf)'),
            ],
          ),
          for (final e in sortedFill)
            pw.TableRow(children: [
              _tableCell(_fmtIn(e.key), bold: true),
              _tableCell('${e.value}'),
              _tableCell('${(e.value * 16).toStringAsFixed(0)}'),
            ]),
          pw.TableRow(
            decoration: const pw.BoxDecoration(color: _kSlate50),
            children: [
              _tableCell('Total', bold: true),
              _tableCell('${schedule.totalFlatFillPanels}', bold: true),
              _tableCell('${schedule.totalFlatFillSF.toStringAsFixed(0)}', bold: true),
            ],
          ),
        ],
      ),
      pw.SizedBox(height: 12),
    ],

    // Totals and R-value
    pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: _kSlate50,
        border: pw.Border.all(color: _kSlate200),
        borderRadius: pw.BorderRadius.circular(6),
      ),
      child: pw.Row(children: [
        pw.Expanded(child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('Order Totals',
                style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold,
                    color: _kSlate900)),
            pw.SizedBox(height: 4),
            _kvRow('Tapered panels', '${schedule.totalTaperedPanels}'),
            _kvRow('Flat fill boards', '${schedule.totalFlatFillPanels}'),
            _kvRow('With 10% waste', '${schedule.totalPanelsWithWaste} boards'),
          ],
        )),
        pw.SizedBox(width: 20),
        pw.Expanded(child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('Taper R-Value Range (Polyiso)',
                style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold,
                    color: _kSlate900)),
            pw.SizedBox(height: 4),
            _kvRow('Min (at drain)', 'R-${minR.toStringAsFixed(1)}'),
            _kvRow('Average', 'R-${avgR.toStringAsFixed(1)}'),
            _kvRow('Max (at ridge)', 'R-${maxR.toStringAsFixed(1)}'),
          ],
        )),
      ]),
    ),
    pw.SizedBox(height: 12),

    // Installer notes
    pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: const PdfColor.fromInt(0xFFFEF3C7),
        border: pw.Border.all(color: const PdfColor.fromInt(0xFFFCD34D)),
        borderRadius: pw.BorderRadius.circular(6),
      ),
      child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Text('Installation Notes',
            style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold,
                color: const PdfColor.fromInt(0xFF92400E))),
        pw.SizedBox(height: 4),
        pw.Text(
          '- Install tapered panels starting at each drain/scupper, working outward toward the ridge.',
          style: pw.TextStyle(fontSize: 9, color: const PdfColor.fromInt(0xFF78350F)),
        ),
        pw.Text(
          '- Panel sequence for each zone: see roof plan - labels show X, Y, Z, ZZ (or similar) '
          'in order from each low point.',
          style: pw.TextStyle(fontSize: 9, color: const PdfColor.fromInt(0xFF78350F)),
        ),
        pw.Text(
          '- Panels marked with * (e.g., X*) require flat fill underneath - see Flat Fill table above.',
          style: pw.TextStyle(fontSize: 9, color: const PdfColor.fromInt(0xFF78350F)),
        ),
        pw.Text(
          '- Stagger panel joints. Mechanically fasten per manufacturer spec '
          '(fastener length calculated in Materials Takeoff).',
          style: pw.TextStyle(fontSize: 9, color: const PdfColor.fromInt(0xFF78350F)),
        ),
        if (schedule.warnings.isNotEmpty) ...[
          pw.SizedBox(height: 4),
          for (final w in schedule.warnings)
            pw.Text('- WARNING: $w',
                style: pw.TextStyle(fontSize: 9,
                    color: const PdfColor.fromInt(0xFFB45309),
                    fontWeight: pw.FontWeight.bold)),
        ],
      ]),
    ),
  ];
}

pw.Widget _cfgCell(String label, String value) => pw.Expanded(
      child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Text(label,
            style: pw.TextStyle(fontSize: 8, color: _kSlate500)),
        pw.Text(value,
            style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold,
                color: _kSlate900)),
      ]),
    );

pw.Widget _tableHeader(String text) => pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: pw.Text(text,
          style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold,
              color: _kSlate700)),
    );

pw.Widget _tableCell(String text, {bool bold = false}) => pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      child: pw.Text(text,
          style: pw.TextStyle(fontSize: 9,
              fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
              color: _kSlate900)),
    );

pw.Widget _kvRow(String label, String value) => pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 2),
      child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
        pw.Text(label,
            style: pw.TextStyle(fontSize: 9, color: _kSlate500)),
        pw.Text(value,
            style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold,
                color: _kSlate900)),
      ]),
    );

/// Returns a human-readable thin→thick label for a panel letter.
String _panelThicknessLabel(String letter, TaperDefaults d) {
  final seq = lookupPanelSequence(
    manufacturer: d.manufacturer,
    taperRate: d.taperRate,
    profileType: d.profileType,
  );
  if (seq == null) return '';
  for (final p in seq.panels) {
    if (p.letter == letter) {
      return '${_fmtIn(p.thinEdge)} - ${_fmtIn(p.thickEdge)}';
    }
  }
  return '';
}
