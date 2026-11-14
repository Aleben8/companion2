import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../constants.dart';
import '../gyms.dart';
import '../services/item_service.dart';
import '../services/session.dart';
import '../theme.dart';
import 'common.dart';

/// Badge delle palestre: a colori se ottenuti, sbiaditi altrimenti.
class BadgeRow extends StatelessWidget {
  const BadgeRow({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = context.read<Session>().userName!;
    return StreamBuilder<Map<String, dynamic>?>(
      stream: ItemService.watchUser(uid),
      builder: (context, snap) {
        final raw = snap.data?['badges'];
        final badges = raw is Map ? raw : const {};
        final owned = kGyms.where((g) => badges[g.id] != null).length;
        return Column(children: [
          Text('Badge: $owned/${kGyms.length}', style: const TextStyle(color: Pal.sub, fontSize: 14, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            alignment: WrapAlignment.center,
            children: [
              for (final g in kGyms)
                Opacity(
                  opacity: badges[g.id] != null ? 1 : 0.25,
                  child: Tooltip(
                    message: g.name,
                    child: Container(
                      width: 44,
                      height: 44,
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(colors: kTypeGradients[g.type] ?? kTypeGradients['Normale']!),
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: TypeIcon(g.type, size: 26),
                    ),
                  ),
                ),
            ],
          ),
        ]);
      },
    );
  }
}
