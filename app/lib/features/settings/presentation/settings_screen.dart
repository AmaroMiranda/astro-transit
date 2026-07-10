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
          Text('Tema', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          SegmentedButton<AppThemeMode>(
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
          const SizedBox(height: 24),
          Text('Astros a monitorar', style: Theme.of(context).textTheme.titleSmall),
          SwitchListTile(
            title: const Text('Sol'),
            value: targets.contains('sun'),
            onChanged: (v) {
              final next = {...targets};
              v ? next.add('sun') : next.remove('sun');
              ref.read(selectedTargetsProvider.notifier).state = next;
            },
          ),
          SwitchListTile(
            title: const Text('Lua'),
            value: targets.contains('moon'),
            onChanged: (v) {
              final next = {...targets};
              v ? next.add('moon') : next.remove('moon');
              ref.read(selectedTargetsProvider.notifier).state = next;
            },
          ),
          const SizedBox(height: 24),
          Text(
            'Raio de busca: ${radiusKm.toStringAsFixed(0)} km',
            style: Theme.of(context).textTheme.titleSmall,
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
    );
  }
}
