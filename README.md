# App Rotas Entregas

Aplicativo cross-platform para triagem de pacotes, leitura de etiquetas, organização física e otimização de rotas de entrega.

## V1
**Escanear etiqueta → extrair endereço → validar → numerar pacote → organizar rota → navegar → concluir entrega.**

### Blocos
- [x] Estrutura inicial
- [x] Modelo de pacote/endereço
- [x] Parser brasileiro + CEP
- [x] Confiança e revisão
- [x] Numeração e duplicidade
- [x] Sessão de triagem
- [x] Persistência local
- [x] Estrutura OCR/scanner
- [x] Importação de texto
- [x] Estrutura de rota
- [x] Otimizador inicial
- [x] Reordenação e paradas fixadas
- [x] Status de entrega
- [x] Integração Waze
- [ ] Geocodificação real
- [ ] Matriz viária
- [ ] Mapa completo
- [ ] Validar OCR com etiquetas reais
- [ ] Painel transportadora/backend

Arquitetura Flutter/Dart, local-first e preparada para Android/iOS. Serviços externos ficam atrás de interfaces para permitir troca de fornecedor.

> Privacidade: dados de destinatários/endereço devem ser usados somente para a operação da entrega e protegidos conforme a LGPD. Evitar persistir imagens de etiquetas sem necessidade.
