/// Geometria esférica compartilhada: extrapolação de rumo e conversão
/// topocêntrica (posição no solo → azimute/altitude vistos do observador).
///
/// Fica fora das telas para poder ser TESTADA no host — a projeção do radar
/// depende disto estar certo, e um erro aqui desenha uma trajetória enganosa.
library;

import 'dart:math' as math;

const double _earthKm = 6371.0;
const double _earthM = 6371000.0;

/// Destino a [km] de [(lat,lon)] seguindo o rumo [trackDeg] (0=N, horário),
/// em graus. Navegação por círculo máximo numa Terra esférica.
(double lat, double lon) destinationPoint(
    double lat, double lon, double trackDeg, double km) {
  final brng = trackDeg * math.pi / 180;
  final lat1 = lat * math.pi / 180;
  final lon1 = lon * math.pi / 180;
  final d = km / _earthKm;
  final lat2 = math.asin(math.sin(lat1) * math.cos(d) +
      math.cos(lat1) * math.sin(d) * math.cos(brng));
  final lon2 = lon1 +
      math.atan2(math.sin(brng) * math.sin(d) * math.cos(lat1),
          math.cos(d) - math.sin(lat1) * math.sin(lat2));
  return (lat2 * 180 / math.pi, lon2 * 180 / math.pi);
}

/// Azimute e altitude (graus) de um alvo a [altM] metros sobre [(tLat,tLon)],
/// visto de um observador ao nível do solo em [(oLat,oLon)]. Base ENU numa
/// Terra esférica — exata o bastante para as dezenas de km de um avião.
(double azimuthDeg, double altitudeDeg) topocentric(
    double oLat, double oLon, double tLat, double tLon, double altM) {
  final orLat = oLat * math.pi / 180, orLon = oLon * math.pi / 180;
  final trLat = tLat * math.pi / 180, trLon = tLon * math.pi / 180;
  List<double> ecef(double la, double lo, double r) => [
        r * math.cos(la) * math.cos(lo),
        r * math.cos(la) * math.sin(lo),
        r * math.sin(la),
      ];
  final o = ecef(orLat, orLon, _earthM);
  final t = ecef(trLat, trLon, _earthM + altM);
  final d = [t[0] - o[0], t[1] - o[1], t[2] - o[2]];
  final e = [-math.sin(orLon), math.cos(orLon), 0.0];
  final n = [
    -math.sin(orLat) * math.cos(orLon),
    -math.sin(orLat) * math.sin(orLon),
    math.cos(orLat),
  ];
  final u = [
    math.cos(orLat) * math.cos(orLon),
    math.cos(orLat) * math.sin(orLon),
    math.sin(orLat),
  ];
  double dot(List<double> a, List<double> b) =>
      a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
  final de = dot(d, e), dn = dot(d, n), du = dot(d, u);
  var az = math.atan2(de, dn) * 180 / math.pi;
  if (az < 0) az += 360;
  final alt = math.atan2(du, math.sqrt(de * de + dn * dn)) * 180 / math.pi;
  return (az, alt);
}
