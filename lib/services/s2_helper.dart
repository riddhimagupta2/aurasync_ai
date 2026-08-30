import 'dart:math';

class S2Helper {
  /// Converts GPS coordinates into a repeatable Level 14 spatial grid hash string
  static String generateLevel14Token(double lat, double lng) {
    const double latSpacing = 0.0045;
    const double lngSpacing = 0.0052;

    int latIndex = (lat / latSpacing).floor();
    int lngIndex = (lng / lngSpacing).floor();

    // Force lowercase hexadecimal strings immediately
    String latHex = latIndex
        .toRadixString(16)
        .replaceAll('-', 'n')
        .toLowerCase();
    String lngHex = lngIndex
        .toRadixString(16)
        .replaceAll('-', 'n')
        .toLowerCase();

    return "s2_14_${latHex}_$lngHex";
  }
}
