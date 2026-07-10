# SPEC — AstroTransit v1.0 (resumo canônico)

> Documento de referência condensado. Rastreamento e previsão de trânsitos de
> aeronaves diante do Sol e da Lua.

## Produto
Detectar e prever quando uma aeronave próxima cruzará visualmente o disco do Sol ou da
Lua para um observador em uma localização específica, transformando dados técnicos
(ADS-B, efemérides, geometria 3D) em uma experiência simples: **qual astro, qual avião,
em quanto tempo, para onde apontar, e com qual confiança.**

## Princípios
1. **Precisão acima de excesso.** Toda previsão exibe nível de confiança, idade do dado,
   margens de erro (angular/espacial/temporal) e qualidade de GPS/cobertura.
2. **Interface limpa em eventos críticos.** Nos segundos finais: contagem, astro,
   direção, distância do centro, status, captura.
3. **Desempenho previsível** (60 FPS, cálculos fora da thread de UI).
4. **Operação segura** (avisos de observação solar).

## Fluxo de processamento
1. Localização → 2. Precisão/horário → 3. Posição Sol/Lua → 4. Aeronaves próximas →
5. Normalização → 6. Filtro de inválidos → 7. Pré-filtro geográfico → 8. Projeção →
9. Coordenadas do observador → 10. Separação angular → 11. Candidatos →
12. Refinamento temporal → 13. Faixa do trânsito → 14. Margem de erro →
15. Confiança → 16. Previsão → 17. WebSocket → 18. Notificar.

## Requisitos-chave implementados no núcleo matemático (Fase 1)
- **RF-003** posição aparente topocêntrica do Sol/Lua (Skyfield, efeméride local).
- **RF-007** projeção de trajetória (velocidade constante no MVP).
- **RF-008** conversão geodésico → ECEF → ENU → azimute/altitude/distância.
- **RF-009** separação angular via `arccos(clamp(A·B, -1, 1))`.
- **RF-010** raio angular aparente do astro (calculado, não fixo).
- **RF-011** tamanho angular da aeronave (`2·atan(tam/2·dist)`), por categoria.
- **RF-012** detecção de trânsito: `sep ≤ raioAstro + raioAeronave + margem`.
- **RF-013** refinamento temporal (busca por seção áurea, tol. 100 ms).

Classificação de evento: `central`, `near_central`, `partial`, `graze`, `approach`,
`none`.

## Decisões arquiteturais obrigatórias
- Não acoplar o domínio a uma única API aeronáutica (camada `AircraftDataProvider`).
- Nenhuma chave de API no Flutter — apenas no backend.
- Não fazer cálculos pesados na UI; não bloquear a interface.
- Não tratar posição ADS-B como exata; nunca prometer previsão absoluta.
- Bússola não é fonte principal da geometria.
- Overlay da câmera calculado sobre a área útil real do preview (círculos perfeitos).

## Roadmap
| Fase | Entrega |
|------|---------|
| 1 | Núcleo matemático (posição solar/lunar, ECEF/ENU, projeção, separação, testes) |
| 2 | Backend (OpenSky, ADSB.lol, normalização, cache, previsão, WebSocket, confiança) |
| 3 | Flutter MVP (onboarding, localização, radar, previsão, contagem, histórico) |
| 4 | Mapa e faixa geográfica (linha central, deslocamento, favoritos) |
| 5 | Câmera (preview, overlay, calibração, FOV, gravação) |
| 6 | Validação de campo (coleta de erros, ajuste de margens e confiança) |
| 7 | Produto avançado (rede própria de receptores, automação, comunidade) |

## API interna (contratos-alvo)
- `GET  /v1/astronomy/position` — az/alt/raio angular/iluminação do Sol/Lua.
- `GET  /v1/aircraft/nearby` — vetores de estado normalizados numa área.
- `POST /v1/transits/predict` — previsão de trânsitos para um observador.
- `GET  /v1/transits/live` — WebSocket (aircraft_update, candidate_detected, …).

---
*A spec completa v1.0 (todos os RF/RNF, design system, UX, testes e riscos) é a fonte
de verdade do produto; este arquivo é o resumo operacional para o desenvolvimento.*
