/// lib/models/drainage_zone.dart
///
/// Immutable data classes for drainage zones, scupper locations, and taper
/// defaults used in the tapered-insulation phase of ProTPO estimating.

// ─── ScupperLocation ──────────────────────────────────────────────────────────

class ScupperLocation {
  /// 0-based index of the roof polygon edge this scupper sits on.
  final int edgeIndex;

  /// Position along that edge, 0.0 (start vertex) to 1.0 (end vertex).
  final double position;

  const ScupperLocation({
    required this.edgeIndex,
    this.position = 0.5,
  });

  ScupperLocation copyWith({
    int? edgeIndex,
    double? position,
  }) {
    return ScupperLocation(
      edgeIndex: edgeIndex ?? this.edgeIndex,
      position: position ?? this.position,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ScupperLocation &&
          edgeIndex == other.edgeIndex &&
          position == other.position;

  @override
  int get hashCode => Object.hash(edgeIndex, position);
}

// ─── TaperDefaults ────────────────────────────────────────────────────────────

class TaperDefaults {
  /// Slope expressed as rise:run string, e.g. '1/4:12'.
  final String taperRate;

  /// Minimum thickness at the low point, in inches.
  final double minThickness;

  /// Manufacturer name, e.g. 'Versico' or 'TRI-BUILT'.
  final String manufacturer;

  /// Taper profile type, e.g. 'extended' or 'standard'.
  final String profileType;

  /// Attachment method for taper panels.
  final String attachmentMethod;

  const TaperDefaults({
    this.taperRate = '1/4:12',
    this.minThickness = 1.0,
    this.manufacturer = 'Versico',
    this.profileType = 'extended',
    this.attachmentMethod = 'Mechanically Attached',
  });

  factory TaperDefaults.initial() => const TaperDefaults();

  TaperDefaults copyWith({
    String? taperRate,
    double? minThickness,
    String? manufacturer,
    String? profileType,
    String? attachmentMethod,
  }) {
    return TaperDefaults(
      taperRate: taperRate ?? this.taperRate,
      minThickness: minThickness ?? this.minThickness,
      manufacturer: manufacturer ?? this.manufacturer,
      profileType: profileType ?? this.profileType,
      attachmentMethod: attachmentMethod ?? this.attachmentMethod,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TaperDefaults &&
          taperRate == other.taperRate &&
          minThickness == other.minThickness &&
          manufacturer == other.manufacturer &&
          profileType == other.profileType &&
          attachmentMethod == other.attachmentMethod;

  @override
  int get hashCode => Object.hash(
        taperRate,
        minThickness,
        manufacturer,
        profileType,
        attachmentMethod,
      );
}

// ─── DrainageZone ─────────────────────────────────────────────────────────────

class DrainageZone {
  final String id;

  /// 'internal_drain' or 'scupper'.
  final String type;

  /// 0-based index of the roof polygon vertex that is the low point for this zone.
  final int lowPointIndex;

  /// Per-zone overrides — null means use TaperDefaults.
  final String? taperRateOverride;
  final double? minThicknessOverride;
  final String? manufacturerOverride;
  final String? profileTypeOverride;

  const DrainageZone({
    required this.id,
    required this.type,
    required this.lowPointIndex,
    this.taperRateOverride,
    this.minThicknessOverride,
    this.manufacturerOverride,
    this.profileTypeOverride,
  });

  DrainageZone copyWith({
    String? id,
    String? type,
    int? lowPointIndex,
    String? taperRateOverride,
    double? minThicknessOverride,
    String? manufacturerOverride,
    String? profileTypeOverride,
  }) {
    return DrainageZone(
      id: id ?? this.id,
      type: type ?? this.type,
      lowPointIndex: lowPointIndex ?? this.lowPointIndex,
      taperRateOverride: taperRateOverride ?? this.taperRateOverride,
      minThicknessOverride: minThicknessOverride ?? this.minThicknessOverride,
      manufacturerOverride: manufacturerOverride ?? this.manufacturerOverride,
      profileTypeOverride: profileTypeOverride ?? this.profileTypeOverride,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DrainageZone &&
          id == other.id &&
          type == other.type &&
          lowPointIndex == other.lowPointIndex &&
          taperRateOverride == other.taperRateOverride &&
          minThicknessOverride == other.minThicknessOverride &&
          manufacturerOverride == other.manufacturerOverride &&
          profileTypeOverride == other.profileTypeOverride;

  @override
  int get hashCode => Object.hash(
        id,
        type,
        lowPointIndex,
        taperRateOverride,
        minThicknessOverride,
        manufacturerOverride,
        profileTypeOverride,
      );
}

// ─── DrainageZoneOverride ─────────────────────────────────────────────────────

/// A sparse override record — used when a user wants to change only specific
/// taper properties for a named zone without replacing the whole DrainageZone.
class DrainageZoneOverride {
  final String zoneId;

  final String? taperRateOverride;
  final double? minThicknessOverride;
  final String? manufacturerOverride;
  final String? profileTypeOverride;

  const DrainageZoneOverride({
    required this.zoneId,
    this.taperRateOverride,
    this.minThicknessOverride,
    this.manufacturerOverride,
    this.profileTypeOverride,
  });

  DrainageZoneOverride copyWith({
    String? zoneId,
    String? taperRateOverride,
    double? minThicknessOverride,
    String? manufacturerOverride,
    String? profileTypeOverride,
  }) {
    return DrainageZoneOverride(
      zoneId: zoneId ?? this.zoneId,
      taperRateOverride: taperRateOverride ?? this.taperRateOverride,
      minThicknessOverride: minThicknessOverride ?? this.minThicknessOverride,
      manufacturerOverride: manufacturerOverride ?? this.manufacturerOverride,
      profileTypeOverride: profileTypeOverride ?? this.profileTypeOverride,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DrainageZoneOverride &&
          zoneId == other.zoneId &&
          taperRateOverride == other.taperRateOverride &&
          minThicknessOverride == other.minThicknessOverride &&
          manufacturerOverride == other.manufacturerOverride &&
          profileTypeOverride == other.profileTypeOverride;

  @override
  int get hashCode => Object.hash(
        zoneId,
        taperRateOverride,
        minThicknessOverride,
        manufacturerOverride,
        profileTypeOverride,
      );
}
