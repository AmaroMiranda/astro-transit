/// Onboarding: max four steps (SPEC section 16.7).
/// 1) what the app does, 2) location permission, 3) notification permission,
/// 4) solar observation safety warning (section 17 — mandatory acknowledgement).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  final VoidCallback onDone;

  const OnboardingScreen({super.key, required this.onDone});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _controller = PageController();
  int _page = 0;
  bool _safetyAcknowledged = false;

  static const _steps = [
    _Step(
      icon: Icons.flight_takeoff,
      title: 'Bem-vindo ao AstroTransit',
      body:
          'Detectamos aviões próximos e avisamos quando um deles pode cruzar '
          'o Sol ou a Lua no céu acima de você — com direção, contagem '
          'regressiva e nível de confiança.',
    ),
    _Step(
      icon: Icons.my_location,
      title: 'Sua localização',
      body:
          'Precisamos da sua posição para calcular com precisão onde o Sol, '
          'a Lua e os aviões aparecem no céu a partir de onde você está.',
    ),
    _Step(
      icon: Icons.notifications_active_outlined,
      title: 'Alertas em tempo real',
      body:
          'Ative notificações para ser avisado com antecedência quando um '
          'trânsito estiver prestes a acontecer.',
    ),
    _Step(
      icon: Icons.warning_amber_rounded,
      title: 'Segurança na observação solar',
      body:
          'Nunca observe ou fotografe o Sol com equipamento óptico sem filtro '
          'solar apropriado. Óculos de sol não oferecem proteção suficiente.',
      isSafety: true,
    ),
  ];

  Future<void> _handleNext() async {
    if (_page < _steps.length - 1) {
      await _controller.nextPage(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
      return;
    }
    // Last step: request location permission before entering the app.
    try {
      await ref.read(locationServiceProvider).ensurePermission();
      await ref.read(observerLocationProvider.notifier).refresh();
    } catch (_) {
      // Non-fatal: the dashboard offers a manual-location fallback.
    }
    if (mounted) widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    final step = _steps[_page];
    final canContinue = !step.isSafety || _safetyAcknowledged;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView.builder(
                controller: _controller,
                onPageChanged: (i) => setState(() => _page = i),
                itemCount: _steps.length,
                itemBuilder: (context, i) => _StepView(step: _steps[i]),
              ),
            ),
            if (step.isSafety)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: CheckboxListTile(
                  value: _safetyAcknowledged,
                  onChanged: (v) =>
                      setState(() => _safetyAcknowledged = v ?? false),
                  controlAffinity: ListTileControlAffinity.leading,
                  title: const Text('Estou ciente dos riscos e vou seguir as '
                      'recomendações de segurança.'),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: Row(
                children: [
                  _Dots(count: _steps.length, index: _page),
                  const Spacer(),
                  FilledButton(
                    onPressed: canContinue ? _handleNext : null,
                    child: Text(_page == _steps.length - 1
                        ? 'Começar'
                        : 'Continuar'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Step {
  final IconData icon;
  final String title;
  final String body;
  final bool isSafety;

  const _Step({
    required this.icon,
    required this.title,
    required this.body,
    this.isSafety = false,
  });
}

class _StepView extends StatelessWidget {
  final _Step step;

  const _StepView({required this.step});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            step.icon,
            size: 72,
            color: step.isSafety
                ? theme.colorScheme.error
                : theme.colorScheme.primary,
          ),
          const SizedBox(height: 32),
          Text(
            step.title,
            style: theme.textTheme.headlineSmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Text(
            step.body,
            style: theme.textTheme.bodyLarge
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _Dots extends StatelessWidget {
  final int count;
  final int index;

  const _Dots({required this.count, required this.index});

  @override
  Widget build(BuildContext context) {
    final active = Theme.of(context).colorScheme.primary;
    return Row(
      children: List.generate(count, (i) {
        final isActive = i == index;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.only(right: 6),
          width: isActive ? 20 : 8,
          height: 8,
          decoration: BoxDecoration(
            color: isActive ? active : active.withValues(alpha: 0.25),
            borderRadius: BorderRadius.circular(4),
          ),
        );
      }),
    );
  }
}
