import 'package:material_ui/material_ui.dart';

import '../models/models.dart';
import '../widgets/common.dart';
import 'documents_screen.dart';
import '../core/i18n.dart';

Map<OrderStatus, String> get _statusLabel => {
  OrderStatus.pending: tr('Pendiente'),
  OrderStatus.inProgress: tr('En curso'),
  OrderStatus.done: tr('Completado'),
};

/// Work orders: documents the user marked as "pedido", with a status.
class OrdersScreen extends StatelessWidget {
  const OrdersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: services.dataVersion,
      builder: (context, _, _) => FutureBuilder<List<VsDocument>>(
        future: services.documents.list(category: DocCategory.order),
        builder: (context, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final orders = snap.data!;
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: Row(children: [
                Expanded(child: Text(tr('Pedidos y órdenes de trabajo'), style: Theme.of(context).textTheme.headlineSmall)),
                FilledButton.icon(onPressed: () => importDocumentsFlow(context), icon: const Icon(Icons.add), label: Text(tr('Importar'))),
              ]),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(20, 6, 20, 0),
              child: Text(tr('Importa un documento y márcalo como pedido desde su menú (⋮) para gestionarlo aquí.')),
            ),
            Expanded(
              child: orders.isEmpty
                  ? EmptyState(icon: Icons.assignment_outlined, title: tr('No hay pedidos'), message: tr('Marca un documento como pedido para verlo aquí.'))
                  : ListView(padding: const EdgeInsets.all(12), children: [
                      for (final status in OrderStatus.values) ...[
                        SectionHeader('${_statusLabel[status]} (${orders.where((o) => o.orderStatus == status).length})'),
                        for (final o in orders.where((o) => o.orderStatus == status))
                          Card(
                            child: Row(children: [
                              Expanded(child: DocumentTile(doc: o)),
                              Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: DropdownButton<OrderStatus>(
                                  value: o.orderStatus,
                                  underline: const SizedBox.shrink(),
                                  items: [
                                    for (final s in OrderStatus.values) DropdownMenuItem(value: s, child: Text(_statusLabel[s]!)),
                                  ],
                                  onChanged: (s) async {
                                    if (s == null) return;
                                    o.orderStatus = s;
                                    await services.documents.update(o);
                                    services.refresh();
                                  },
                                ),
                              ),
                            ]),
                          ),
                      ],
                    ]),
            ),
          ]);
        },
      ),
    );
  }
}
