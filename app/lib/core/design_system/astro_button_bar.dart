/// Barra de ações padrão do app.
///
/// O problema que ela resolve: botões agrupados na mão ora ficavam em `Row`
/// (um `Expanded` + outro do tamanho do texto → larguras diferentes), ora em
/// `Wrap` (cada um do tamanho do seu rótulo → alturas/larguras irregulares).
/// O resultado dependia do texto e não tinha padrão.
///
/// Aqui todos os botões da barra têm a MESMA largura (cada um `Expanded`), e
/// quando a barra fica estreita demais para caber lado a lado sem espremer os
/// rótulos, eles empilham na vertical em largura cheia. Um único componente,
/// um só comportamento em todo o app.
library;

import 'package:flutter/material.dart';

class AstroButtonBar extends StatelessWidget {
  /// Botões da barra, em ordem de ênfase (o primário costuma vir primeiro).
  /// Passe os botões "crus" (FilledButton/OutlinedButton/TextButton); a barra
  /// cuida da largura.
  final List<Widget> buttons;

  /// Abaixo desta largura por botão, empilha na vertical em vez de espremer.
  final double minButtonWidth;

  /// Espaço entre botões (horizontal e vertical).
  final double gap;

  const AstroButtonBar({
    super.key,
    required this.buttons,
    this.minButtonWidth = 148,
    this.gap = 10,
  });

  @override
  Widget build(BuildContext context) {
    if (buttons.isEmpty) return const SizedBox.shrink();
    if (buttons.length == 1) {
      return SizedBox(width: double.infinity, child: buttons.first);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final totalGap = gap * (buttons.length - 1);
        final perButton = (constraints.maxWidth - totalGap) / buttons.length;

        // Cabem lado a lado sem espremer: uma linha de botões de largura igual.
        if (perButton >= minButtonWidth) {
          return Row(
            children: [
              for (var i = 0; i < buttons.length; i++) ...[
                if (i > 0) SizedBox(width: gap),
                Expanded(child: buttons[i]),
              ],
            ],
          );
        }

        // Estreito demais: empilha em largura cheia.
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < buttons.length; i++) ...[
              if (i > 0) SizedBox(height: gap),
              buttons[i],
            ],
          ],
        );
      },
    );
  }
}
