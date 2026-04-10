/// lib/models/project_info.dart
///
/// Immutable data class for the Project Info section.
/// All fields exactly match INPUT_SPECIFICATIONS.md section 1.
///
/// Waste percentages live here (project-level) because they apply
/// uniformly across all buildings on the same bid.

class ProjectInfo {
  final String projectName;       // Required, max 100 chars
  final String projectAddress;    // Required
  final String zipCode;           // Required, 5-digit
  final String customerName;      // Optional
  final String estimatorName;     // Optional
  final DateTime estimateDate;    // Auto: set on creation
  final int warrantyYears;        // 10, 15, 20, 25, or 30

  // ZIP-derived fields — populated after lookup, null until then
  final String? climateZone;      // e.g. "Zone 4"
  final String? designWindSpeed;  // e.g. "115 mph"
  final double? requiredRValue;   // e.g. 25.0
  final String? stateCounty;      // e.g. "Johnson County, KS"

  // Waste percentages — project-level, shared across all buildings
  // Stored as fractions: 0.10 = 10%
  final double wasteMaterial;     // TPO membrane + insulation boards (default 10%)
  final double wasteMetal;        // Coping, edge metal, gutter, term bar (default 5%)
  final double wasteAccessory;    // Fasteners, adhesive, sealants (default 5%)

  // VOC compliance region — affects product selection labels
  final String vocRegion;         // 'Standard', 'OTC (<250 gpl)', 'SCAQMD'

  const ProjectInfo({
    this.projectName = '',
    this.projectAddress = '',
    this.zipCode = '',
    this.customerName = '',
    this.estimatorName = '',
    required this.estimateDate,
    this.warrantyYears = 20,
    this.climateZone,
    this.designWindSpeed,
    this.requiredRValue,
    this.stateCounty,
    this.wasteMaterial = 0.10,
    this.wasteMetal = 0.05,
    this.wasteAccessory = 0.05,
    this.vocRegion = 'Standard',
  });

  factory ProjectInfo.initial() => ProjectInfo(
        estimateDate: DateTime.now(),
      );

  bool get isComplete =>
      projectName.isNotEmpty &&
      projectAddress.isNotEmpty &&
      zipCode.length == 5;

  bool get zipLookupComplete => climateZone != null;

  ProjectInfo copyWith({
    String? projectName,
    String? projectAddress,
    String? zipCode,
    String? customerName,
    String? estimatorName,
    DateTime? estimateDate,
    int? warrantyYears,
    String? climateZone,
    String? designWindSpeed,
    double? requiredRValue,
    String? stateCounty,
    double? wasteMaterial,
    double? wasteMetal,
    double? wasteAccessory,
    String? vocRegion,
  }) {
    return ProjectInfo(
      projectName: projectName ?? this.projectName,
      projectAddress: projectAddress ?? this.projectAddress,
      zipCode: zipCode ?? this.zipCode,
      customerName: customerName ?? this.customerName,
      estimatorName: estimatorName ?? this.estimatorName,
      estimateDate: estimateDate ?? this.estimateDate,
      warrantyYears: warrantyYears ?? this.warrantyYears,
      climateZone: climateZone ?? this.climateZone,
      designWindSpeed: designWindSpeed ?? this.designWindSpeed,
      requiredRValue: requiredRValue ?? this.requiredRValue,
      stateCounty: stateCounty ?? this.stateCounty,
      wasteMaterial: wasteMaterial ?? this.wasteMaterial,
      wasteMetal: wasteMetal ?? this.wasteMetal,
      wasteAccessory: wasteAccessory ?? this.wasteAccessory,
      vocRegion: vocRegion ?? this.vocRegion,
    );
  }

  ProjectInfo clearZipLookup() => ProjectInfo(
        projectName: projectName,
        projectAddress: projectAddress,
        zipCode: zipCode,
        customerName: customerName,
        estimatorName: estimatorName,
        estimateDate: estimateDate,
        warrantyYears: warrantyYears,
        climateZone: null,
        designWindSpeed: null,
        requiredRValue: null,
        stateCounty: null,
        wasteMaterial: wasteMaterial,
        wasteMetal: wasteMetal,
        wasteAccessory: wasteAccessory,
        vocRegion: vocRegion,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ProjectInfo &&
          projectName == other.projectName &&
          projectAddress == other.projectAddress &&
          zipCode == other.zipCode &&
          customerName == other.customerName &&
          estimatorName == other.estimatorName &&
          estimateDate == other.estimateDate &&
          warrantyYears == other.warrantyYears &&
          climateZone == other.climateZone &&
          designWindSpeed == other.designWindSpeed &&
          requiredRValue == other.requiredRValue &&
          stateCounty == other.stateCounty &&
          wasteMaterial == other.wasteMaterial &&
          wasteMetal == other.wasteMetal &&
          wasteAccessory == other.wasteAccessory &&
          vocRegion == other.vocRegion;

  @override
  int get hashCode => Object.hash(
        projectName, projectAddress, zipCode,
        customerName, estimatorName, estimateDate,
        warrantyYears, climateZone, designWindSpeed,
        requiredRValue, stateCounty,
        wasteMaterial, wasteMetal, wasteAccessory,
        vocRegion,
      );
}
