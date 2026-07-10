/// History list (RF-028).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../data/history_repository.dart';
import '../domain/history_entry.dart';

final historyRepositoryProvider = Provider((ref) => HistoryRepository());

final historyEntriesProvider = FutureProvider<List<HistoryEntry>>((ref) {
  return ref.watch(historyRepositoryProvider).loadAll();
});

class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entriesAsync = ref.watch(historyEntriesProvider);
    final dateFormat = DateFormat('dd/MM/yyyy HH:mm');

    return Scaffold(
      appBar: AppBar(title: const Text('Histórico')),
      body: entriesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Erro: $e')),
        data: (entries) {
          if (entries.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'Nenhum evento registrado ainda. Eventos observados '
                  'aparecerão aqui.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: entries.length,
            separatorBuilder: (context, index) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final e = entries[i];
              final isMoon = e.body == 'moon';
              return Card(
                child: ListTile(
                  leading: Icon(
                    isMoon ? Icons.nightlight_round : Icons.wb_sunny,
                  ),
                  title: Text(e.callsign ?? e.icao24 ?? 'Aeronave desconhecida'),
                  subtitle: Text(
                    '${dateFormat.format(e.dateTimeUtc.toLocal())} · '
                    'separação ${e.minSeparationDeg.toStringAsFixed(3)}° · '
                    'confiança ${e.confidenceScore.toStringAsFixed(0)}%',
                  ),
                  trailing: Chip(label: Text(historyStatusLabel(e.status))),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
