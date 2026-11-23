import 'package:flutter/material.dart';
import '../app_state.dart';
import '../domain/models.dart';
import 'address_editor_dialog.dart';

class UnlocatedAddressesScreen extends StatelessWidget {
  final AppState state;
  const UnlocatedAddressesScreen({super.key, required this.state});

  bool _active(DeliveryPackage p) => p.status != DeliveryStatus.delivered;
  bool _needsAttention(DeliveryPackage p) =>
      _active(p) &&
      (p.address.validation != ValidationStatus.confirmed ||
       p.address.latitude == null || p.address.longitude == null);

  Future<void> _edit(BuildContext context, DeliveryPackage package) async {
    final index = state.packages.indexWhere((p) => p.id == package.id);
    if (index < 0) return;
    final result = await showAddressEditor(
      context,
      title: 'Corrigir endereço • ${package.label}',
      initial: package.address,
    );
    if (result == null || result.raw.trim().isEmpty || !context.mounted) return;
    await state.updateAddress(index, result.toAddress());
    if (!context.mounted) return;
    final updated = state.packages.firstWhere((p) => p.id == package.id);
    final found = updated.address.latitude != null && updated.address.longitude != null;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(found
        ? '${package.label} localizado com sucesso!'
        : 'Endereço salvo. Ainda não foi possível localizar; confira os dados e tente novamente.'),
    ));
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: state,
    builder: (context, _) {
      final pending = state.packages.where(_needsAttention).toList();
      final located = state.packages.where((p) => _active(p) && p.address.latitude != null && p.address.longitude != null).length;
      final total = state.packages.where(_active).length;
      final retryable = pending.where((p) => p.address.validation == ValidationStatus.confirmed && (p.address.latitude == null || p.address.longitude == null)).length;
      return Scaffold(
        appBar: AppBar(
          title: const Text('Corrigir endereços'),
          leading: IconButton(
            tooltip: 'Voltar para preparar rota',
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${pending.length} endereço(s) precisam de atenção', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 6),
                Text('$located de $total pacotes localizados no mapa'),
                const SizedBox(height: 10),
                LinearProgressIndicator(value: total == 0 ? 0 : located / total),
                const SizedBox(height: 8),
                const Text('Toque no pacote com problema, corrija rua, número, bairro, cidade ou CEP e confirme. O aplicativo tentará localizar novamente automaticamente.'),
              ]),
            )),
            const SizedBox(height: 12),
            if (pending.isEmpty)
              Card(child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(children: [
                  const Icon(Icons.check_circle, color: Colors.green, size: 48),
                  const SizedBox(height: 8),
                  const Text('Todos os endereços foram localizados!', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  const Text('Volte para a preparação da rota para otimizar e conferir o mapa.', textAlign: TextAlign.center),
                ]),
              ))
            else
              for (final p in pending)
                Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Theme.of(context).colorScheme.errorContainer,
                      child: Text('${p.scanNumber}', style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer)),
                    ),
                    title: Text(p.label),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(p.address.formatted.isEmpty ? p.address.raw : p.address.formatted),
                    ),
                    trailing: const Icon(Icons.edit_location_alt),
                    onTap: () => _edit(context, p),
                  ),
                ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: state.locating || retryable == 0 ? null : () async {
                await state.locateConfirmed();
              },
              icon: const Icon(Icons.location_searching),
              label: Text(retryable == 0 ? 'CORRIJA OS DADOS PARA TENTAR' : 'TENTAR LOCALIZAR NOVAMENTE ($retryable)'),
            ),
            if (retryable == 0 && pending.isNotEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text('Os endereços com alerta precisam ser corrigidos e confirmados antes de uma nova busca.', textAlign: TextAlign.center),
              ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.arrow_back),
              label: const Text('VOLTAR PARA PREPARAR ROTA'),
            ),
          ],
        ),
      );
    },
  );
}
