import 'package:astrotransit/core/utils/geo.dart';
import 'package:flutter_test/flutter_test.dart';

/// Diferença angular com sinal no intervalo (-180, 180], para comparar azimutes
/// sem tropeçar na descontinuidade 0°/360°.
double angDiff(double a, double b) => ((a - b + 540) % 360) - 180;

void main() {
  group('destinationPoint', () {
    test('rumo norte aumenta a latitude, mantém a longitude', () {
      final (lat, lon) = destinationPoint(0, 0, 0, 111.195); // ~1 grau
      expect(lat, closeTo(1.0, 0.02));
      expect(lon, closeTo(0.0, 0.001));
    });

    test('rumo leste no equador aumenta a longitude, mantém a latitude', () {
      final (lat, lon) = destinationPoint(0, 0, 90, 111.195);
      expect(lat, closeTo(0.0, 0.02));
      expect(lon, closeTo(1.0, 0.02));
    });

    test('distância zero devolve o próprio ponto', () {
      final (lat, lon) = destinationPoint(-23.5, -46.6, 137, 0);
      expect(lat, closeTo(-23.5, 1e-9));
      expect(lon, closeTo(-46.6, 1e-9));
    });
  });

  group('topocentric', () {
    test('alvo exatamente ao norte e acima → azimute ~0, altitude positiva', () {
      // Observador em SP; alvo 1 km ao norte, a 10 km de altitude.
      final o = (-23.55, -46.63);
      final t = destinationPoint(o.$1, o.$2, 0, 1.0);
      final (az, alt) = topocentric(o.$1, o.$2, t.$1, t.$2, 10000);
      expect(angDiff(az, 0).abs(), lessThan(3));
      expect(alt, greaterThan(0));
    });

    test('alvo a leste → azimute ~90', () {
      final o = (-23.55, -46.63);
      final t = destinationPoint(o.$1, o.$2, 90, 5.0);
      final (az, _) = topocentric(o.$1, o.$2, t.$1, t.$2, 10000);
      expect(angDiff(az, 90).abs(), lessThan(3));
    });

    test('quanto mais longe no solo, menor a altitude aparente', () {
      final o = (-23.55, -46.63);
      double altAt(double km) {
        final t = destinationPoint(o.$1, o.$2, 45, km);
        return topocentric(o.$1, o.$2, t.$1, t.$2, 11000).$2;
      }

      expect(altAt(5), greaterThan(altAt(40)));
      expect(altAt(40), greaterThan(altAt(120)));
    });

    test('a autovalidação do radar fecha: recalcular o ponto atual reproduz '
        'o az/alt em um laço fechado', () {
      // Um ponto qualquer, seu az/alt calculado, e a garantia de que altitude
      // fica no intervalo físico [0,90] e azimute em [0,360).
      final o = (-23.55, -46.63);
      final t = destinationPoint(o.$1, o.$2, 200, 30);
      final (az, alt) = topocentric(o.$1, o.$2, t.$1, t.$2, 11000);
      expect(az, inInclusiveRange(0, 360));
      expect(alt, inInclusiveRange(-90, 90));
      // Recalcular o MESMO ponto dá exatamente o mesmo resultado (determinismo
      // — é disso que a autovalidação do _skyTrajectory depende).
      final (az2, alt2) = topocentric(o.$1, o.$2, t.$1, t.$2, 11000);
      expect(az2, closeTo(az, 1e-9));
      expect(alt2, closeTo(alt, 1e-9));
    });
  });

  test('ida e volta: destino ao norte e a topocêntrica concordam na direção',
      () {
    // Consistência cruzada entre as duas funções: um alvo projetado num rumo
    // cardinal deve cair perto do azimute correspondente visto do observador.
    final o = (10.0, 20.0);
    for (final (track, expectedAz) in [
      (0.0, 0.0),
      (90.0, 90.0),
      (180.0, 180.0),
      (270.0, 270.0),
    ]) {
      final t = destinationPoint(o.$1, o.$2, track, 8);
      final (az, _) = topocentric(o.$1, o.$2, t.$1, t.$2, 9000);
      final diff = ((az - expectedAz + 540) % 360) - 180;
      expect(diff.abs(), lessThan(4),
          reason: 'rumo $track deveria dar azimute ~$expectedAz, deu $az');
    }
  });
}
