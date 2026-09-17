import 'package:flutter/material.dart';
import '../domain/models.dart';

class LoadScreen extends StatelessWidget {
  final List<DeliveryPackage> packages;
  const LoadScreen({super.key, required this.packages});

  bool _active(DeliveryPackage p) =>
      p.status == DeliveryStatus.pending ||
      p.status == DeliveryStatus.current ||
      p.status == DeliveryStatus.absent ||
      p.status == DeliveryStatus.addressProblem;

  @override
  Widget build(BuildContext context) {
    final route = packages.where(_active).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Ordem dos pacotes')),
      body: route.isEmpty
          ? const Center(child: Text('Nenhum pacote ativo na rota.'))
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${route.length} pacotes',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Esta é a ordem da rota. Organize os pacotes no veículo usando esta sequência como referência.',
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
                    itemCount: route.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final p = route[i];
                      final address = p.address.formatted.isEmpty
                          ? p.address.raw
                          : p.address.formatted;
                      final local = p.physicalZone?.trim().isNotEmpty == true
                          ? 'Local ${p.physicalZone} • '
                          : '';

                      return ListTile(
                        leading: CircleAvatar(child: Text('${i + 1}')),
                        title: Text(
                          p.label,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(
                          '${local}Entrega #${i + 1}\n$address',
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}
