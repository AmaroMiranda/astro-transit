/// Multi-day satellite pass planner (modelo ISS Transit Finder): upcoming
/// ISS/Tiangong transits of the Sun/Moon for the next 48 h, including events
/// whose ground centerline runs within travel distance of the observer.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design_system/app_theme.dart';
import '../../../core/network/friendly_error.dart';
import '../../../core/providers.dart';
import '../../../core/utils/compass.dart';
import '../../../shared/models/celestial_position.dart';
import '../domain/passes_providers.dart';
import '../domain/satellite_pass.dart';
import '../domain/visible_pass.dart';

class PassesScreen extends ConsumerWidget {
  const PassesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final observer = ref.watch(observerLocationProvider);
    // Mantém as notificações agendadas em sincronia com a lista de trânsitos.
    ref.watch(passAlertsSchedulerProvider);

    if (observer == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Passagens de satélites')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Defina sua localização (GPS ou um ponto no mapa) para '
              'calcular as passagens da ISS e da Tiangong.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    // Duas abas: VISÍVEIS (toda passagem que dá para ver/registrar a olho nu,
    // com as que também são trânsito destacadas) e TRÂNSITOS (o planejador
    // preciso de cruzamentos do Sol/Lua, com alertas).
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Passagens de satélites'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Visíveis'),
              Tab(text: 'Trânsitos'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _VisiblePassesTab(),
            _TransitsTab(),
          ],
        ),
      ),
    );
  }
}

/// Aba de TRÂNSITOS: o planejador preciso já existente (cruzamentos exatos do
/// Sol/Lua no local ou numa faixa próxima), com o banner de alertas.
class _TransitsTab extends ConsumerWidget {
  const _TransitsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final passesAsync = ref.watch(upcomingPassesProvider);
    final alertsEnabled = ref.watch(alertsEnabledProvider);
    return RefreshIndicator(
      onRefresh: () async => ref.refresh(upcomingPassesProvider.future),
      child: passesAsync.when(
                loading: () => const _PassesLoading(),
                error: (e, _) => ListView(
                  padding: const EdgeInsets.all(24),
                  children: [
                    Text(
                      'Falha ao calcular passagens: ${friendlyErrorMessage(e)}',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
                data: (response) {
                  final passes = response?.passes ?? const <SatellitePass>[];
                  if (passes.isEmpty) {
                    return ListView(
                      padding: const EdgeInsets.all(24),
                      children: const [
                        SizedBox(height: 48),
                        Icon(Icons.satellite_alt,
                            size: 48, color: AstroColors.telemetry),
                        SizedBox(height: 16),
                        Text(
                          'Nenhum trânsito de ISS/Tiangong diante do Sol ou '
                          'da Lua nos próximos 2 dias num raio de 30 km.\n\n'
                          'Trânsitos exatos são raros — volte amanhã ou '
                          'escolha outro ponto no mapa.',
                          textAlign: TextAlign.center,
                        ),
                      ],
                    );
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: passes.length + 1,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, i) {
                      if (i == 0) {
                        return _AlertsBanner(enabled: alertsEnabled);
                      }
                      return _PassCard(pass: passes[i - 1]);
                    },
                  );
                },
              ),
    );
  }
}

/// Aba de PASSAGENS VISÍVEIS: toda passagem em que a estação pode ser vista a
/// olho nu (iluminada, observador no escuro) — para registrar/fotografar. As
/// que também são trânsito do Sol/Lua recebem um selo de destaque.
class _VisiblePassesTab extends ConsumerWidget {
  const _VisiblePassesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final passesAsync = ref.watch(visiblePassesProvider);
    return RefreshIndicator(
      onRefresh: () async => ref.refresh(visiblePassesProvider.future),
      child: passesAsync.when(
        loading: () => const _PassesLoading(),
        error: (e, _) => ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              'Falha ao calcular passagens: ${friendlyErrorMessage(e)}',
              textAlign: TextAlign.center,
            ),
          ],
        ),
        data: (response) {
          final passes = response?.passes ?? const <VisiblePass>[];
          if (passes.isEmpty) {
            return ListView(
              padding: const EdgeInsets.all(24),
              children: const [
                SizedBox(height: 48),
                Icon(Icons.visibility_off_outlined,
                    size: 48, color: AstroColors.telemetry),
                SizedBox(height: 16),
                Text(
                  'Nenhuma passagem visível da ISS ou da Tiangong sobre o seu '
                  'local nos próximos 10 dias.\n\nA estação só aparece quando '
                  'está iluminada pelo Sol e o seu céu já escureceu (do fim da '
                  'tarde à noite, ou de madrugada) — e essas temporadas vão e '
                  'voltam a cada 1-2 semanas para cada lugar. Volte em alguns '
                  'dias ou escolha outro ponto no mapa.',
                  textAlign: TextAlign.center,
                ),
              ],
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: passes.length + 1,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              if (i == 0) return const _VisibleHeader();
              return _VisiblePassCard(pass: passes[i - 1]);
            },
          );
        },
      ),
    );
  }
}

/// Loading com texto — a 1ª varredura de 10 dias no servidor gratuito pode
/// levar até ~1 min (calcula posição e iluminação da estação minuto a minuto).
/// Sem esse aviso, o spinner sozinho parece travamento e o usuário lê como
/// "falha no servidor".
class _PassesLoading extends StatelessWidget {
  const _PassesLoading();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 20),
            Text(
              'Calculando as passagens dos próximos 10 dias…',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 6),
            Text(
              'O primeiro cálculo pode levar até 1 minuto. Depois fica '
              'instantâneo.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: AstroColors.telemetry),
            ),
          ],
        ),
      ),
    );
  }
}

class _VisibleHeader extends StatelessWidget {
  const _VisibleHeader();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            const Icon(Icons.photo_camera_outlined,
                size: 20, color: AstroColors.info),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Passagens em que a estação aparece como um ponto brilhante '
                'cruzando o céu. As marcadas com TRÂNSITO também passam na '
                'frente do Sol ou da Lua.',
                style: theme.textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VisiblePassCard extends StatelessWidget {
  final VisiblePass pass;

  const _VisiblePassCard({required this.pass});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final start = pass.startUtc.toLocal();
    final culm = pass.culminationUtc.toLocal();
    final end = pass.endUtc.toLocal();
    final durMin = (pass.durationS / 60).floor();
    final durSec = (pass.durationS % 60).round();
    final transitColor = pass.transitBody == CelestialBody.moon
        ? AstroColors.moon
        : AstroColors.sun;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.satellite_alt,
                    color: AstroColors.satellite, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    pass.satelliteLabel,
                    style: theme.textTheme.titleSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // Selo de destaque para passagens que também são trânsito —
                // o mesmo realce dos aviões candidatos.
                if (pass.isTransit)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: transitColor.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(999),
                      border:
                          Border.all(color: transitColor.withValues(alpha: 0.7)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          pass.transitBody == CelestialBody.moon
                              ? Icons.nightlight_round
                              : Icons.wb_sunny,
                          size: 12,
                          color: transitColor,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          pass.transitBody == CelestialBody.moon
                              ? 'TRÂNSITO · LUA'
                              : 'TRÂNSITO · SOL',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            color: transitColor,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(_formatLocal(culm), style: theme.textTheme.titleMedium),
            const SizedBox(height: 2),
            Text(
              'Começa ${_hm(start)} · auge ${_hm(culm)} · termina ${_hm(end)}',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: AstroColors.telemetry),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                _Fact(
                  icon: Icons.height,
                  text: 'auge ${pass.maxElevationDeg.toStringAsFixed(0)}°',
                  highlight: pass.maxElevationDeg >= 40,
                ),
                _Fact(
                  icon: Icons.brightness_5_outlined,
                  text: 'mag ${pass.approxMagnitude.toStringAsFixed(1)}',
                  highlight: pass.approxMagnitude <= 0.0,
                ),
                _Fact(
                  icon: Icons.timelapse,
                  text: durMin > 0 ? '${durMin}min ${durSec}s' : '${durSec}s',
                ),
                _Fact(
                  icon: Icons.navigation_outlined,
                  text: 'de ${compassLabel(pass.startAzimuthDeg)} para '
                      '${compassLabel(pass.endAzimuthDeg)}',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

String _hm(DateTime local) => '${_two(local.hour)}:${_two(local.minute)}';

class _AlertsBanner extends StatelessWidget {
  final bool enabled;

  const _AlertsBanner({required this.enabled});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Icon(
              enabled
                  ? Icons.notifications_active_outlined
                  : Icons.notifications_off_outlined,
              size: 20,
              color: enabled ? AstroColors.success : AstroColors.telemetry,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                enabled
                    ? 'Alertas ativos: você será avisado antes de cada passagem.'
                    : 'Alertas desativados — ative em Configurações para ser '
                        'avisado antes de cada passagem.',
                style: theme.textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PassCard extends StatelessWidget {
  final SatellitePass pass;

  const _PassCard({required this.pass});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isMoon = pass.body == CelestialBody.moon;
    final bodyColor = isMoon ? AstroColors.moon : AstroColors.sun;
    final local = pass.transitAtUtc.toLocal();
    final when = _formatLocal(local);
    final distanceKm =
        pass.corridor != null ? pass.corridor!.distanceFromObserverM / 1000 : null;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.satellite_alt,
                    color: AstroColors.satellite, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    pass.satelliteLabel,
                    style: theme.textTheme.titleSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: bodyColor.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: bodyColor.withValues(alpha: 0.6)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isMoon ? Icons.nightlight_round : Icons.wb_sunny,
                        size: 12,
                        color: bodyColor,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        isMoon ? 'Lua' : 'Sol',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: bodyColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(when, style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                _Fact(
                  icon: Icons.place_outlined,
                  text: pass.atObserver
                      ? 'Visível do seu local'
                      : distanceKm != null
                          ? 'Faixa a ${distanceKm.toStringAsFixed(1)} km '
                              '(${compassLabel(pass.corridor!.bearingFromObserverDeg)})'
                          : 'Faixa próxima',
                  highlight: pass.atObserver,
                ),
                if (pass.atObserver && pass.durationS > 0)
                  _Fact(
                    icon: Icons.timer_outlined,
                    text: '${pass.durationS.toStringAsFixed(2)} s',
                  ),
                _Fact(
                  icon: Icons.height,
                  text:
                      '${pass.elevationDeg.toStringAsFixed(0)}° · ${compassLabel(pass.azimuthDeg)}',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

const _kWeekdaysPt = ['seg', 'ter', 'qua', 'qui', 'sex', 'sáb', 'dom'];

String _two(int v) => v.toString().padLeft(2, '0');

String _formatLocal(DateTime local) {
  final wd = _kWeekdaysPt[local.weekday - 1];
  return '$wd ${_two(local.day)}/${_two(local.month)} · '
      '${_two(local.hour)}:${_two(local.minute)}:${_two(local.second)}';
}

class _Fact extends StatelessWidget {
  final IconData icon;
  final String text;
  final bool highlight;

  const _Fact({required this.icon, required this.text, this.highlight = false});

  @override
  Widget build(BuildContext context) {
    final color =
        highlight ? AstroColors.success : AstroColors.telemetry;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text(
          text,
          style: TextStyle(
            fontSize: 12.5,
            color: color,
            fontWeight: highlight ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
