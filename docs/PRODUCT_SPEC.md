# Product Spec — V1

## Autônomo
1. Nova rota.
2. Scanner de etiquetas em sequência.
3. OCR local.
4. Identificação do pacote e duplicidade.
5. Parser de endereço brasileiro.
6. Confiança: aprovado / revisar / inválido.
7. Numeração física sugerida pelo app.
8. Revisão somente das exceções.
9. Geocodificação.
10. Mapa e otimização.
11. Reordenação manual e paradas fixadas.
12. Execução: próximo pacote + endereço + Waze.
13. Entregue / ausente / pular / problema de endereço.
14. Reotimização das pendentes.
15. Resumo da rota.

## Transportadora (arquitetura futura)
Importação em lote → validação → clustering territorial → distribuição por motorista/veículo → otimização por rota → envio ao app do motorista → acompanhamento → relatórios.

## Regras críticas
- Nunca confirmar silenciosamente OCR de baixa confiança.
- Detectar duplicatas.
- Não exigir conexão para triagem básica.
- Não guardar foto da etiqueta por padrão.
- O Waze recebe somente o próximo destino; o app mantém a rota completa.
- Reotimização deve respeitar posições/paradas bloqueadas.
- Identificação física do pacote deve permanecer visível durante a execução.

## Próxima validação de campo
Testar etiquetas reais de diferentes transportadoras, tamanhos, iluminação, etiquetas amassadas e fontes pequenas. Medir tempo por captura, taxa de leitura correta, taxa de revisão e duplicatas detectadas.
