/// Shared compass helpers (pt-BR wind labels: L = leste, O = oeste).
library;

/// 8-wind compass label for an azimuth in degrees (0 = north, clockwise).
String compassLabel(double azimuthDeg) {
  const labels = ['N', 'NE', 'L', 'SE', 'S', 'SO', 'O', 'NO'];
  final index = (((azimuthDeg % 360) + 22.5) / 45).floor() % 8;
  return labels[index];
}
