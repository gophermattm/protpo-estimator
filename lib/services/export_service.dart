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
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/estimator_state.dart';
import '../services/bom_calculator.dart';
import '../services/r_value_calculator.dart';

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
  static Future<void> downloadPdf(
    EstimatorState state,
    BomResult bom, {
    RValueResult? rValue,
  }) async {
    final bytes = await _buildPdf(state, bom, rValue: rValue);
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
    final blob = html.Blob([Uint8List.fromList(bytes)], mimeType);
    final url  = html.Url.createObjectUrlFromBlob(blob);
    final anchor = html.AnchorElement(href: url)
      ..setAttribute('download', filename)
      ..click();
    html.Url.revokeObjectUrl(url);
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// CSV
// ═══════════════════════════════════════════════════════════════════════════════

String _buildCsv(EstimatorState state, BomResult bom) {
  final info = state.projectInfo;
  final buf  = StringBuffer();

  // ── Header block ─────────────────────────────────────────────────────────
  buf.writeln('ProTPO Estimator — Materials Takeoff');
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
        ',—'
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
}) async {
  final doc  = pw.Document(
    title: state.projectInfo.projectName,
    author: state.projectInfo.estimatorName,
  );

  // Page format: US Letter
  final fmt = PdfPageFormat.letter;

  // ── Page 1 — Cover ───────────────────────────────────────────────────────
  doc.addPage(pw.Page(
    pageFormat: fmt,
    margin: const pw.EdgeInsets.all(0),
    build: (ctx) => _coverPage(state, bom, rValue),
  ));

  // ── Page 2+ — Materials Takeoff ───────────────────────────────────────────
  final bomPages = _bomPages(bom);
  for (final pageContent in bomPages) {
    doc.addPage(pw.Page(
      pageFormat: fmt,
      margin: pw.EdgeInsets.fromLTRB(40, 40, 40, 50),
      build: (ctx) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _pageHeader('Materials Takeoff', state),
          pw.SizedBox(height: 16),
          ...pageContent,
          pw.Spacer(),
          _pageFooter(ctx),
        ],
      ),
    ));
  }

  // ── Final page — Thermal, Compliance & Scope ─────────────────────────────
  doc.addPage(pw.Page(
    pageFormat: fmt,
    margin: pw.EdgeInsets.fromLTRB(40, 40, 40, 50),
    build: (ctx) => pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _pageHeader('Thermal & Scope of Work', state),
        pw.SizedBox(height: 16),
        _thermalSection(state, rValue),
        pw.SizedBox(height: 16),
        _scopeSection(state),
        pw.Spacer(),
        _pageFooter(ctx),
      ],
    ),
  ));

  return doc.save();
}

// ─── COVER PAGE ───────────────────────────────────────────────────────────────

pw.Widget _coverPage(EstimatorState state, BomResult bom, RValueResult? rv) {
  final info = state.projectInfo;
  final totalArea = state.buildings
      .fold(0.0, (s, b) => s + b.roofGeometry.totalArea);
  final totalSq = totalArea > 0 ? (totalArea / 100) : 0.0;

  return pw.Stack(children: [
    // Gradient header band
    pw.Positioned(
      top: 0, left: 0, right: 0,
      child: pw.Container(
        height: 200,
        decoration: const pw.BoxDecoration(
          gradient: pw.LinearGradient(
            begin: pw.Alignment.topLeft,
            end: pw.Alignment.bottomRight,
            colors: [_kBlueDark, _kBlue],
          ),
        ),
      ),
    ),

    pw.Padding(
      padding: const pw.EdgeInsets.all(48),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          // Logo area
          pw.Row(children: [
            pw.Container(
              width: 36, height: 36,
              decoration: pw.BoxDecoration(
                color: _pdfAlpha(_kWhite, 0.15),
                borderRadius: pw.BorderRadius.circular(8),
              ),
            ),
            pw.SizedBox(width: 12),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('ProTPO',
                    style: pw.TextStyle(color: _kWhite, fontSize: 22,
                        fontWeight: pw.FontWeight.bold)),
                pw.Text('Commercial Roofing Estimator',
                    style: pw.TextStyle(color: _pdfAlpha(_kWhite, 0.75), fontSize: 11)),
              ],
            ),
          ]),
          pw.SizedBox(height: 24),

          // Project title
          pw.Text(
            info.projectName.isNotEmpty ? info.projectName : 'Untitled Project',
            style: pw.TextStyle(color: _kWhite, fontSize: 28,
                fontWeight: pw.FontWeight.bold),
          ),
          if (info.projectAddress.isNotEmpty) ...[
            pw.SizedBox(height: 6),
            pw.Text(info.projectAddress,
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
                        _metaRow('Customer',  info.customerName.isNotEmpty ? info.customerName : '—'),
                        _metaRow('Estimator', info.estimatorName.isNotEmpty ? info.estimatorName : '—'),
                        _metaRow('Date',      DateFormat('MMMM d, yyyy').format(info.estimateDate)),
                        _metaRow('Warranty',  '${info.warrantyYears}-Year NDL'),
                      ],
                    )),
                    pw.Expanded(child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        _metaRow('ZIP Code',      info.zipCode.isNotEmpty ? info.zipCode : '—'),
                        _metaRow('Climate Zone',  info.climateZone ?? '—'),
                        _metaRow('Wind Speed',    info.designWindSpeed ?? '—'),
                        _metaRow('Required R',    info.requiredRValue != null
                            ? 'R-${info.requiredRValue?.toStringAsFixed(0) ?? '?'}' : '—'),
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
            _statBox('Total Area',   totalArea > 0 ? '${_fmtNum(totalArea)} sf' : '—',    _kBlue),
            pw.SizedBox(width: 12),
            _statBox('Squares',      totalSq   > 0 ? '${totalSq.toStringAsFixed(1)} sq' : '—', _kBlue),
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
                      : '—',
                  _kSlate700),
              pw.SizedBox(width: 12),
              _statBox('System', state.buildings.isNotEmpty
                  ? '${state.buildings.first.membraneSystem.thickness} ${state.buildings.first.membraneSystem.membraneType}'
                  : '—', _kSlate700),
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
                  ...bom.warnings.map((w) => pw.Text('• $w',
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
List<List<pw.Widget>> _bomPages(BomResult bom) {
  final pages = <List<pw.Widget>>[];
  List<pw.Widget> current = [];

  int rowCount = 0;
  const rowsPerPage = 30; // approximate

  for (final entry in bom.byCategory.entries) {
    final items = entry.value.where((i) => i.hasQuantity).toList();
    if (items.isEmpty) continue;

    // Category header counts as 2 rows
    if (rowCount + items.length + 2 > rowsPerPage && current.isNotEmpty) {
      pages.add(current);
      current = [];
      rowCount = 0;
    }

    current.add(_categoryHeader(entry.key));
    current.add(pw.SizedBox(height: 6));
    current.add(_categoryTable(items));
    current.add(pw.SizedBox(height: 14));
    rowCount += items.length + 2;
  }

  if (current.isNotEmpty) pages.add(current);
  if (pages.isEmpty) {
    pages.add([pw.Text('No BOM items — enter roof dimensions to calculate.',
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

pw.Widget _categoryTable(List<BomLineItem> items) {
  const colWidths = [
    pw.FlexColumnWidth(4),  // Item
    pw.FlexColumnWidth(1),  // Qty
    pw.FlexColumnWidth(1),  // Unit
    pw.FlexColumnWidth(3),  // Formula
    pw.FlexColumnWidth(2),  // Notes
  ];

  final headerStyle = pw.TextStyle(
      fontSize: 8, fontWeight: pw.FontWeight.bold, color: _kSlate500);
  final cellStyle   = pw.TextStyle(fontSize: 9, color: _kSlate900);
  final mutedStyle  = pw.TextStyle(fontSize: 8, color: _kSlate500);
  final boldStyle   = pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold,
      color: _kBlue);

  pw.Widget cell(String text, pw.TextStyle style, {bool right = false}) =>
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        child: pw.Text(text, style: style,
            textAlign: right ? pw.TextAlign.right : pw.TextAlign.left),
      );

  return pw.Table(
    columnWidths: {
      0: colWidths[0], 1: colWidths[1],
      2: colWidths[2], 3: colWidths[3], 4: colWidths[4],
    },
    border: pw.TableBorder(
      horizontalInside: pw.BorderSide(color: _kSlate200, width: 0.5),
    ),
    children: [
      // Header row
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: _kSlate100),
        children: [
          cell('ITEM',    headerStyle),
          cell('QTY',     headerStyle, right: true),
          cell('UNIT',    headerStyle),
          cell('FORMULA', headerStyle),
          cell('NOTES',   headerStyle),
        ],
      ),
      // Data rows
      ...items.asMap().entries.map((e) {
        final item = e.value;
        final even = e.key % 2 == 0;
        final t    = item.trace;
        final formula = '${t.baseDescription} + ${(t.wastePercent * 100).toStringAsFixed(0)}% waste';
        return pw.TableRow(
          decoration: pw.BoxDecoration(color: even ? _kWhite : _kSlate50),
          children: [
            cell(item.name,   cellStyle),
            cell(_fmtQty(item.orderQty), boldStyle, right: true),
            cell(item.unit,   mutedStyle),
            cell(formula,     mutedStyle),
            cell(item.notes,  mutedStyle),
          ],
        );
      }),
    ],
  );
}

// ─── THERMAL & SCOPE ─────────────────────────────────────────────────────────

pw.Widget _thermalSection(EstimatorState state, RValueResult? rv) {
  if (rv == null) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(14),
      decoration: pw.BoxDecoration(
          color: _kSlate100, borderRadius: pw.BorderRadius.circular(8)),
      child: pw.Text('Thermal data unavailable — enter ZIP code to load climate zone.',
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
                      : 'Below IECC/ASHRAE 90.1 minimum of R-${info.requiredRValue?.toStringAsFixed(0) ?? '?'} — additional insulation required',
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
  result.add(['Layer 1 — \${rv.layer1.materialType} \${rv.layer1.thickness}"',
      rv.layer1.rValue.toString()]);
  if (rv.layer2 != null) {
    result.add(['Layer 2 — \${rv.layer2!.materialType} \${rv.layer2!.thickness}"',
        rv.layer2!.rValue.toString()]);
  }
  if (rv.tapered != null) {
    result.add(['Tapered — \${rv.tapered!.materialType}',
        rv.tapered!.averageRValue.toString()]);
  }
  if (rv.coverBoard != null) {
    result.add(['Cover Board — \${rv.coverBoard!.materialType} \${rv.coverBoard!.thickness}"',
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

pw.Widget _pageHeader(String section, EstimatorState state) => pw.Column(
  crossAxisAlignment: pw.CrossAxisAlignment.start,
  children: [
    pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text('ProTPO Estimator',
            style: pw.TextStyle(fontSize: 9, color: _kSlate500)),
        pw.Text(DateFormat('MMM d, yyyy').format(DateTime.now()),
            style: pw.TextStyle(fontSize: 9, color: _kSlate500)),
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

// ─── HELPERS ─────────────────────────────────────────────────────────────────

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
