/// Mirrors `ObserverIn` from the backend (RF-001).
class ObserverLocation {
  final double latitude;
  final double longitude;
  final double altitudeM;
  final double? horizontalAccuracyM;

  const ObserverLocation({
    required this.latitude,
    required this.longitude,
    this.altitudeM = 0.0,
    this.horizontalAccuracyM,
  });

  Map<String, dynamic> toJson() => {
        'latitude': latitude,
        'longitude': longitude,
        'altitude_m': altitudeM,
        if (horizontalAccuracyM != null)
          'horizontal_accuracy_m': horizontalAccuracyM,
      };
}
