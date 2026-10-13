/// Appearance facts, separate from render lighting. No material-to-color guess
/// and no evidence-observed factory without a future surface-association contract.
enum AppearanceProvenance { mapDerived, evidenceObserved, unknownNeutral }

class SurfaceAppearance {
  const SurfaceAppearance._(this.sourceValue, this.argb, this.provider);
  final String? sourceValue;
  final int? argb;
  final String provider;
  AppearanceProvenance get provenance => argb == null
      ? AppearanceProvenance.unknownNeutral
      : AppearanceProvenance.mapDerived;
  String get label => argb == null
      ? 'Not established — neutral visualization'
      : 'Map-derived color ($provider)';
  factory SurfaceAppearance.fromSource(String? value, String provider) =>
      SurfaceAppearance._(value, parseMapColor(value), provider);
  Map<String, Object?> toJson() => {
    'sourceValue': sourceValue,
    'baseArgb': argb,
    'provider': provider,
    'provenance': provenance.name,
  };
}

/// Deliberately bounded CSS/OSM names and opaque #RGB/#RRGGBB only. Reject
/// gradients, alpha, lists, material names and ambiguous free-form descriptions.
int? parseMapColor(String? source) {
  final value = source?.trim().toLowerCase();
  if (value == null || value.length > 32) return null;
  const names = {
    'black': 0xff000000,
    'white': 0xffffffff,
    'gray': 0xff808080,
    'grey': 0xff808080,
    'silver': 0xffc0c0c0,
    'red': 0xffff0000,
    'maroon': 0xff800000,
    'yellow': 0xffffff00,
    'olive': 0xff808000,
    'lime': 0xff00ff00,
    'green': 0xff008000,
    'aqua': 0xff00ffff,
    'teal': 0xff008080,
    'blue': 0xff0000ff,
    'navy': 0xff000080,
    'fuchsia': 0xffff00ff,
    'purple': 0xff800080,
    'orange': 0xffffa500,
    'brown': 0xffa52a2a,
    'beige': 0xfff5f5dc,
  };
  if (names.containsKey(value)) return names[value];
  if (!RegExp(r'^#(?:[0-9a-f]{3}|[0-9a-f]{6})$').hasMatch(value)) return null;
  var hex = value.substring(1);
  if (hex.length == 3) hex = hex.split('').map((c) => '$c$c').join();
  return 0xff000000 | int.parse(hex, radix: 16);
}
