import 'package:equatable/equatable.dart';

/// Optional icon + color for a user Envelope (U1 slice 2, #95).
///
/// Serialized as a JSON object inside the `meta` column under the key
/// `"appearance"`, independent of [FundingTarget]. System envelopes
/// (`role != none`) must never carry an appearance.
///
/// [iconId] keys into the app's curated Material Icons subset; [colorIndex]
/// indexes into the app's fixed color palette. Both are optional so a partial
/// choice (e.g. icon only) round-trips without inventing a default.
class EnvelopeAppearance extends Equatable {
  final String? iconId;
  final int? colorIndex;

  const EnvelopeAppearance({this.iconId, this.colorIndex});

  static const none = EnvelopeAppearance();

  /// Deserializes from the `"appearance"` sub-object stored in `meta`.
  factory EnvelopeAppearance.fromJson(Map<String, dynamic> json) {
    return EnvelopeAppearance(
      iconId: json['icon_id'] as String?,
      colorIndex: json['color_index'] as int?,
    );
  }

  Map<String, dynamic> toJson() => {
    if (iconId != null) 'icon_id': iconId,
    if (colorIndex != null) 'color_index': colorIndex,
  };

  bool get isEmpty => iconId == null && colorIndex == null;

  @override
  List<Object?> get props => [iconId, colorIndex];
}
