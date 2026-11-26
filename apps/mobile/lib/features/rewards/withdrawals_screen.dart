import 'package:flutter/material.dart' hide Text;
import 'package:haiti_tracking/core/i18n.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/money.dart';
import '../../core/theme.dart';
import '../../core/ui.dart';

const _statusText = {
  'REQUESTED': ('En proceso', ChipTone.review),
  'PROCESSING': ('En proceso', ChipTone.review),
  'COMPLETED': ('Completado', ChipTone.ok),
  'REJECTED': ('Rechazado', ChipTone.bad),
};

/// Historial de solicitudes de retiro con su estado.
class WithdrawalsScreen extends StatefulWidget {
  const WithdrawalsScreen({super.key});

  @override
  State<WithdrawalsScreen> createState() => _WithdrawalsScreenState();
}

class _WithdrawalsScreenState extends State<WithdrawalsScreen> {
  List<Map<String, dynamic>> _rows = const [];
  bool _loading = true;
  String? _error;
  int _filter = 0;
  String? _expanded;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rows = await Supabase.instance.client
          .from('withdrawal_requests')
          .select()
          .order('created_at', ascending: false)
          .limit(100);
      if (!mounted) return;
      setState(() {
        _rows = List<Map<String, dynamic>>.from(rows);
        _expanded ??= _rows.isEmpty ? null : _rows.first['id'] as String;
        _error = null;
      });
    } catch (_) {
      if (mounted) setState(() => _error = 'No se pudieron cargar tus retiros.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  static bool _inProcess(Map<String, dynamic> r) => r['status'] == 'REQUESTED' || r['status'] == 'PROCESSING';

  bool _matches(Map<String, dynamic> r, int f) => switch (f) {
        1 => _inProcess(r),
        2 => r['status'] == 'COMPLETED',
        3 => r['status'] == 'REJECTED',
        _ => true,
      };

  @override
  Widget build(BuildContext context) {
    final withdrawn = _rows.where((r) => r['status'] == 'COMPLETED').fold<int>(0, (a, r) => a + cents(r['amount_usd']));
    final inProcess = _rows.where(_inProcess).fold<int>(0, (a, r) => a + cents(r['amount_usd']));
    final counts = [for (var f = 0; f < 4; f++) _rows.where((r) => _matches(r, f)).length];
    final visible = _rows.where((r) => _matches(r, _filter)).toList();
    return HtScaffold(
      appBar: const HtAppBar(showBell: true),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
                children: [
                  const ScreenTitle('Mis retiros',
                      icon: Icons.account_balance_wallet_outlined,
                      subtitle: 'Historial y estado de tus solicitudes de retiro.'),
                  const SizedBox(height: 14),
                  HtCard(
                    child: IntrinsicHeight(
                      child: Row(children: [
                        Expanded(child: _Total(Icons.savings_outlined, HtColors.blue, 'Total retirado', usd(withdrawn), HtColors.green)),
                        const VerticalDivider(),
                        Expanded(child: _Total(Icons.schedule, HtColors.amber, 'En proceso', usd(inProcess), HtColors.amber)),
                      ]),
                    ),
                  ),
                  const SizedBox(height: 14),
                  FilterPills(
                    labels: [
                      'Todos (${counts[0]})',
                      'En proceso (${counts[1]})',
                      'Completados (${counts[2]})',
                      'Rechazados (${counts[3]})',
                    ],
                    selected: _filter,
                    onSelected: (i) => setState(() => _filter = i),
                  ),
                  const SizedBox(height: 12),
                  if (_error != null)
                    InfoBanner(_error!, warning: true)
                  else if (visible.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 40),
                      child: Text('No tienes retiros en esta lista.', textAlign: TextAlign.center),
                    ),
                  for (final r in visible) ...[
                    _WithdrawalCard(
                      row: r,
                      expanded: _expanded == r['id'],
                      onToggle: () => setState(() => _expanded = _expanded == r['id'] ? null : r['id'] as String),
                    ),
                    const SizedBox(height: 10),
                  ],
                  const SizedBox(height: 4),
                  const InfoBanner('Los retiros están sujetos a verificación y aprobación.'),
                ],
              ),
            ),
    );
  }
}

class _Total extends StatelessWidget {
  const _Total(this.icon, this.iconColor, this.label, this.value, this.valueColor);
  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      IconTile(icon, color: iconColor, background: iconColor.withValues(alpha: .12), size: 44),
      const SizedBox(width: 10),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(fontSize: 14)),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: valueColor)),
          ),
        ]),
      ),
    ]);
  }
}

class _WithdrawalCard extends StatelessWidget {
  const _WithdrawalCard({required this.row, required this.expanded, required this.onToggle});
  final Map<String, dynamic> row;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final (label, tone) = _statusText[row['status']] ?? (row['status'] as String, ChipTone.info);
    final amount = cents(row['amount_usd']);
    final fee = row['fee_usd'];
    final rate = row['htg_rate'];
    final reference = row['reference'] as String?;
    final rejection = row['rejection_reason'] as String?;
    return HtCard(
      borderColor: expanded ? HtColors.blue.withValues(alpha: .4) : null,
      color: expanded ? const Color(0xFFF7FAFF) : Colors.white,
      padding: const EdgeInsets.all(12),
      child: Column(children: [
        InkWell(
          onTap: onToggle,
          child: Row(children: [
            const MonCashBadge(size: 46),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Retiro #${row['code']}', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                Text(fechaHora(DateTime.parse(row['created_at'] as String)), style: const TextStyle(color: HtColors.muted)),
              ]),
            ),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              StatusChip(label, tone: tone),
              const SizedBox(height: 4),
              Text(usd(amount), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            ]),
            Icon(expanded ? Icons.expand_less : Icons.expand_more),
          ]),
        ),
        if (expanded) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
            decoration: BoxDecoration(color: HtColors.blueSoft, borderRadius: BorderRadius.circular(10)),
            child: Column(children: [
              KvRow('Número MonCash', maskPhone(row['moncash_phone'] as String?), icon: Icons.phone_outlined),
              KvRow('Importe', usd(amount), icon: Icons.savings_outlined),
              KvRow('Comisión', fee == null ? 'Según las políticas vigentes' : usd(cents(fee)), icon: Icons.swap_horiz),
              KvRow('Conversión a HTG', rate == null ? 'Según cotización del día' : '1 USD = $rate HTG',
                  icon: Icons.currency_exchange),
              KvRow('Referencia', reference ?? 'Disponible al completarse', icon: Icons.description_outlined),
              if (rejection != null && rejection.isNotEmpty) KvRow('Motivo', rejection, icon: Icons.info_outline),
            ]),
          ),
        ],
      ]),
    );
  }
}
