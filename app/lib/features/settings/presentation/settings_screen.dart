/// Settings: theme mode, search radius, tracked bodies (RF-002, RF-004).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design_system/app_theme.dart';
import '../../../core/providers.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final radiusKm = ref.watch(searchRadiusKmProvider);
    final targets = ref.watch(selectedTargetsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Configurações')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _SettingsCard(
            title: 'Tema',
            subtitle: 'O modo vermelho preserva a adaptação noturna dos olhos.',
            child: SizedBox(
              width: double.infinity,
              child: SegmentedButton<AppThemeMode>(
                segments: const [
                  ButtonSegment(
                    value: AppThemeMode.dark,
                    icon: Icon(Icons.dark_mode_outlined),
                    label: Text('Escuro'),
                  ),
                  ButtonSegment(
                    value: AppThemeMode.light,
                    icon: Icon(Icons.light_mode_outlined),
                    label: Text('Claro'),
                  ),
                  ButtonSegment(
                    value: AppThemeMode.red,
                    icon: Icon(Icons.nightlight_outlined),
                    label: Text('Vermelho'),
                  ),
                ],
                selected: {themeMode},
                onSelectionChanged: (s) =>
                    ref.read(themeModeProvider.notifier).state = s.first,
              ),
            ),
          ),
          const SizedBox(height: 12),
          _SettingsCard(
            title: 'Astros a monitorar',
            subtitle: 'Trânsitos solares exigem filtro apropriado para '
                'observação e fotografia.',
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text('Sol'),
                  secondary:
                      const Icon(Icons.wb_sunny, color: AstroColors.sun),
                  contentPadding: EdgeInsets.zero,
                  value: targets.contains('sun'),
                  onChanged: (v) {
                    final next = {...targets};
                    v ? next.add('sun') : next.remove('sun');
                    ref.read(selectedTargetsProvider.notifier).state = next;
                  },
                ),
                SwitchListTile(
                  title: const Text('Lua'),
                  secondary: const Icon(Icons.nightlight_round,
                      color: AstroColors.moon),
                  contentPadding: EdgeInsets.zero,
                  value: targets.contains('moon'),
                  onChanged: (v) {
                    final next = {...targets};
                    v ? next.add('moon') : next.remove('moon');
                    ref.read(selectedTargetsProvider.notifier).state = next;
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _SettingsCard(
            title: 'Raio de busca',
            subtitle: 'Raios maiores encontram mais aviões, mas a busca '
                'demora um pouco mais.',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${radiusKm.toStringAsFixed(0)} km',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                ),
                Slider(
                  value: radiusKm,
                  min: 20,
                  max: 250,
                  divisions: 23,
                  label: '${radiusKm.toStringAsFixed(0)} km',
                  onChanged: (v) =>
                      ref.read(searchRadiusKmProvider.notifier).state = v,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget child;

  const _SettingsCard({
    required this.title,
    required this.child,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w600)),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(
                subtitle!,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}
