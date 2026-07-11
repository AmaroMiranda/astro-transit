/// Home screen (SPEC section 16.2 / 16.3).
///
/// Headlines the next opportunity when one exists; otherwise shows the
/// "no transit likely" state with useful next actions, never a bare
/// technical panel. Location is requested automatically on first open
/// (RF-001) and the search is triggered by an explicit primary button.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/design_system/app_theme.dart';
import '../../../core/network/friendly_error.dart';
import '../../../core/providers.dart';
import '../../../core/utils/compass.dart';
import '../../../shared/models/celestial_position.dart';
import '../../../shared/models/observer_location.dart';
import '../../../shared/models/transit_prediction.dart';
import '../../predictions/domain/prediction_providers.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  bool _locating = false;
  String? _locationError;

  @override
  void initState() {
    super.initState();
    // Fetch location on open — prompting for permission if needed — instead
    // of waiting for the user to discover a retry button (RF-001).
    WidgetsBinding.instance.addPostFrameCallback((_) => _search());
  }

  Future<void> _search() async {
    if (_locating) return;
    setState(() => _locating = true);
    final error =
        await ref.read(observerLocationProvider.notifier).tryRefresh();
    if (!mounted) return;
    setState(() {
      _locationError = error;
      _locating = false;
    });
    if (error == null) {
      ref.invalidate(predictionProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final observer = ref.watch(observerLocationProvider);
    final predictionAsync = ref.watch(predictionProvider);
    final busy = _locating || predictionAsync.isLoading;

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _search,
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            _Header(observer: observer),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: FilledButton.icon(
                      onPressed: busy ? null : _search,
                      icon: busy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.travel_explore),
                      label: Text(busy ? 'Buscando…' : 'Buscar trânsitos'),
                    ),
                  ),
                  const SizedBox(height: 20),
                  ..._predictionSection(observer, predictionAsync),
                  const SizedBox(height: 28),
                  const _SectionLabel('CÉU AGORA'),
                  const SizedBox(height: 12),
                  _SkyRow(bodies: predictionAsync.valueOrNull?.bodies),
                  const SizedBox(height: 28),
                  const _SectionLabel('EXPLORAR'),
                  const SizedBox(height: 12),
                  const _ExploreGrid(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _predictionSection(
    ObserverLocation? observer,
    AsyncValue<PredictionResponse?> predictionAsync,
  ) {
    if (_locationError != null) {
      return [
        _MessageCard(
          icon: Icons.location_off_outlined,
          iconColor: AstroColors.warning,
          title: 'Localização indisponível',
          message: _locationError!,
          actionLabel: 'Tentar novamente',
          onAction: _search,
        ),
      ];
    }
    if (observer == null) {
      return [
        _MessageCard(
          icon: Icons.my_location,
          iconColor: AstroColors.info,
          title: _locating ? 'Obtendo sua localização…' : 'Pronto para buscar',
          message: _locating
              ? 'Aguardando o GPS do aparelho.'
              : 'Toque em "Buscar trânsitos" para localizar você e '
                  'verificar os aviões na região.',
          showProgress: _locating,
        ),
      ];
    }
    return [
      predictionAsync.when(
        loading: () => const _MessageCard(
          icon: Icons.connecting_airports,
          iconColor: AstroColors.info,
          title: 'Consultando aeronaves…',
          message: 'Cruzando posições de aviões com o Sol e a Lua no seu céu. '
              'Isso pode levar alguns segundos.',
          showProgress: true,
        ),
        error: (err, _) => _MessageCard(
          icon: Icons.cloud_off_outlined,
          iconColor: AstroColors.error,
          title: 'Falha na busca',
          message: friendlyErrorMessage(err),
          actionLabel: 'Tentar novamente',
          onAction: _search,
        ),
        data: (response) {
          if (response == null || response.predictions.isEmpty) {
            return _NoEventCard(response: response);
          }
          return _NextOpportunityCard(
            prediction: response.predictions.first,
            dataDegraded: response.dataDegraded,
          );
        },
      ),
    ];
  }
}

// --------------------------------------------------------------------------
// Header
// --------------------------------------------------------------------------

class _Header extends StatelessWidget {
  final ObserverLocation? observer;

  const _Header({required this.observer});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF1B2440), Color(0xFF0E1528), Color(0xFF05070F)],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 8, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: RichText(
                      text: const TextSpan(
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.5,
                        ),
                        children: [
                          TextSpan(
                            text: 'Astro',
                            style: TextStyle(color: Color(0xFFEAF0FF)),
                          ),
                          TextSpan(
                            text: 'Transit',
                            style: TextStyle(color: Color(0xFF5EC2FF)),
                          ),
                        ],
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.camera_alt_outlined,
                        color: Color(0xFFB9C6E4)),
                    tooltip: 'Câmera',
                    onPressed: () => context.push('/camera'),
                  ),
                  IconButton(
                    icon: const Icon(Icons.settings_outlined,
                        color: Color(0xFFB9C6E4)),
                    tooltip: 'Configurações',
                    onPressed: () => context.push('/settings'),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Text(
                  'Aviões cruzando o Sol e a Lua, previstos para o seu céu.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: const Color(0xFF8DA0C8)),
                ),
              ),
              const SizedBox(height: 14),
              _StatusChip(observer: observer),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final ObserverLocation? observer;

  const _StatusChip({required this.observer});

  @override
  Widget build(BuildContext context) {
    final hasLocation = observer != null;
    final color = hasLocation ? AstroColors.success : AstroColors.warning;
    final accuracy = observer?.horizontalAccuracyM;
    final label = hasLocation
        ? 'Localização ativa${accuracy != null ? ' (±${accuracy.toStringAsFixed(0)} m)' : ''}'
        : 'Aguardando localização';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        border: Border.all(color: color.withValues(alpha: 0.35)),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(hasLocation ? Icons.gps_fixed : Icons.gps_not_fixed,
              size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

// --------------------------------------------------------------------------
// Prediction cards
// --------------------------------------------------------------------------

class _MessageCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool showProgress;

  const _MessageCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.showProgress = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: iconColor.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: iconColor, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(title, style: theme.textTheme.titleMedium),
                ),
                if (showProgress)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              message,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            if (actionLabel != null) ...[
              const SizedBox(height: 16),
              OutlinedButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}

class _NextOpportunityCard extends StatelessWidget {
  final TransitPrediction prediction;
  final bool dataDegraded;

  const _NextOpportunityCard({
    required this.prediction,
    required this.dataDegraded,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = prediction.candidate;
    final isMoon = c.body == CelestialBody.moon;
    final bodyLabel = isMoon ? 'Lua' : 'Sol';
    final bodyColor = isMoon ? AstroColors.moon : AstroColors.sun;
    final minutes = (c.timeToTransitS / 60).floor();
    final seconds = (c.timeToTransitS % 60).round();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'PRÓXIMA OPORTUNIDADE',
              style: theme.textTheme.labelSmall?.copyWith(
                letterSpacing: 1.5,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Icon(
                  isMoon ? Icons.nightlight_round : Icons.wb_sunny,
                  color: bodyColor,
                  size: 28,
                ),
                const SizedBox(width: 10),
                Text(bodyLabel, style: theme.textTheme.headlineSmall),
                const Spacer(),
                Text(
                  '${minutes}m ${seconds.toString().padLeft(2, '0')}s',
                  style: AppTheme.countdownStyle(context,
                          color: theme.colorScheme.onSurface)
                      .copyWith(fontSize: 32),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(transitClassLabel(c.transitClass),
                style: theme.textTheme.bodyLarge),
            if (prediction.callsign != null)
              Text(prediction.callsign!, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 12),
            _ConfidenceChip(confidence: prediction.confidence),
            const SizedBox(height: 4),
            Text(
              'Aeronave a ${(prediction.aircraftDistanceM / 1000).toStringAsFixed(1)} km · '
              'atualizado há ${prediction.dataAgeS.toStringAsFixed(0)}s',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            if (dataDegraded) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.warning_amber_rounded,
                      size: 14, color: AstroColors.warning),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Dados aeronáuticos possivelmente desatualizados.',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: AstroColors.warning),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => context.push('/live-tracking'),
                    icon: const Icon(Icons.timer_outlined),
                    label: const Text('Acompanhar'),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: () => context.push('/radar'),
                  icon: const Icon(Icons.radar),
                  label: const Text('Radar'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ConfidenceChip extends StatelessWidget {
  final Confidence confidence;

  const _ConfidenceChip({required this.confidence});

  Color get _color {
    switch (confidence.category) {
      case ConfidenceCategory.veryLow:
      case ConfidenceCategory.low:
        return AstroColors.error;
      case ConfidenceCategory.moderate:
        return AstroColors.warning;
      case ConfidenceCategory.high:
      case ConfidenceCategory.veryHigh:
        return AstroColors.success;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: _color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        'Confiança ${confidenceCategoryLabel(confidence.category).toLowerCase()} '
        '· ${confidence.score.toStringAsFixed(0)}%',
        style:
            TextStyle(color: _color, fontWeight: FontWeight.w600, fontSize: 12),
      ),
    );
  }
}

class _NoEventCard extends StatelessWidget {
  final PredictionResponse? response;

  const _NoEventCard({required this.response});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final considered = response?.aircraftConsidered ?? 0;
    final degraded = response?.dataDegraded ?? false;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AstroColors.info.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.flight_takeoff,
                      color: AstroColors.info, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Nenhum trânsito provável agora',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              considered > 0
                  ? 'Monitoramos $considered aeronave(s) candidata(s), mas '
                      'nenhuma deve cruzar o Sol ou a Lua nos próximos minutos.'
                  : 'Nenhuma aeronave na região está em rota de cruzar o Sol '
                      'ou a Lua nos próximos minutos. Busque de novo em '
                      'alguns instantes.',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            if (degraded) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.warning_amber_rounded,
                      size: 14, color: AstroColors.warning),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Cobertura aeronáutica reduzida no momento — alguns '
                      'voos podem não aparecer.',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: AstroColors.warning),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () => context.push('/radar'),
                  icon: const Icon(Icons.radar),
                  label: const Text('Abrir radar'),
                ),
                OutlinedButton.icon(
                  onPressed: () => context.push('/settings'),
                  icon: const Icon(Icons.tune),
                  label: const Text('Aumentar raio'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// --------------------------------------------------------------------------
// Sky section
// --------------------------------------------------------------------------

class _SkyRow extends StatelessWidget {
  final List<CelestialPosition>? bodies;

  const _SkyRow({required this.bodies});

  CelestialPosition? _find(CelestialBody target) {
    final list = bodies;
    if (list == null) return null;
    for (final b in list) {
      if (b.target == target) return b;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _BodyTile(
            body: CelestialBody.sun,
            position: _find(CelestialBody.sun),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _BodyTile(
            body: CelestialBody.moon,
            position: _find(CelestialBody.moon),
          ),
        ),
      ],
    );
  }
}

class _BodyTile extends StatelessWidget {
  final CelestialBody body;
  final CelestialPosition? position;

  const _BodyTile({required this.body, required this.position});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isMoon = body == CelestialBody.moon;
    final visible = position?.isVisible ?? false;

    final gradient = isMoon
        ? const [Color(0xFFF4EEDA), Color(0xFFB6AC8C)]
        : const [Color(0xFFFFD489), Color(0xFFE8933A)];
    final iconColor = isMoon ? const Color(0xFF4A4433) : const Color(0xFF4A2E00);

    final String statusLine;
    if (position == null) {
      statusLine = 'Aguardando busca';
    } else if (!visible) {
      statusLine = 'Abaixo do horizonte';
    } else {
      statusLine = 'Visível agora';
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Opacity(
                  opacity: visible ? 1.0 : 0.45,
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: gradient,
                      ),
                    ),
                    child: Icon(
                      isMoon ? Icons.nightlight_round : Icons.wb_sunny,
                      color: iconColor,
                      size: 22,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(isMoon ? 'Lua' : 'Sol',
                          style: theme.textTheme.titleSmall),
                      Text(
                        statusLine,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: visible
                              ? AstroColors.success
                              : theme.colorScheme.onSurfaceVariant,
                          fontSize: 11,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (position != null && visible) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _MiniStat(
                    label: 'Altura',
                    value: '${position!.altitudeDeg.toStringAsFixed(0)}°',
                  ),
                  _MiniStat(
                    label: 'Direção',
                    value: '${compassLabel(position!.azimuthDeg)} · '
                        '${position!.azimuthDeg.toStringAsFixed(0)}°',
                  ),
                  if (isMoon && position!.illumination != null)
                    _MiniStat(
                      label: 'Iluminação',
                      value:
                          '${(position!.illumination! * 100).toStringAsFixed(0)}%',
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;

  const _MiniStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.onSurface.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              fontSize: 9,
              letterSpacing: 0.5,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          Text(
            value,
            style: theme.textTheme.bodySmall?.copyWith(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

// --------------------------------------------------------------------------
// Explore grid
// --------------------------------------------------------------------------

class _SectionLabel extends StatelessWidget {
  final String text;

  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      text,
      style: theme.textTheme.labelSmall?.copyWith(
        letterSpacing: 2,
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}

class _ExploreGrid extends StatelessWidget {
  const _ExploreGrid();

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      padding: EdgeInsets.zero,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.45,
      children: const [
        _ExploreTile(
          icon: Icons.radar,
          color: Color(0xFF5EC2FF),
          label: 'Radar',
          subtitle: 'Céu em tempo real',
          route: '/radar',
        ),
        _ExploreTile(
          icon: Icons.map_outlined,
          color: Color(0xFF3DDC84),
          label: 'Mapa',
          subtitle: 'Faixa do trânsito',
          route: '/map',
        ),
        _ExploreTile(
          icon: Icons.camera_alt_outlined,
          color: Color(0xFFFFC169),
          label: 'Câmera',
          subtitle: 'Overlay e gravação',
          route: '/camera',
        ),
        _ExploreTile(
          icon: Icons.history,
          color: Color(0xFF9FB0D6),
          label: 'Histórico',
          subtitle: 'Eventos registrados',
          route: '/history',
        ),
      ],
    );
  }
}

class _ExploreTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String subtitle;
  final String route;

  const _ExploreTile({
    required this.icon,
    required this.color,
    required this.label,
    required this.subtitle,
    required this.route,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => context.push(route),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 11,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
