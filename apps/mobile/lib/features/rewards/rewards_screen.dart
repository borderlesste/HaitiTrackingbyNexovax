import 'package:flutter/material.dart' hide Text;
import 'package:haiti_tracking/core/i18n.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/money.dart';
import '../../core/theme.dart';
import '../../core/ui.dart';
import 'withdraw_screens.dart';
import 'withdrawals_screen.dart';

export '../../core/money.dart';

const minWithdrawalCents = 500; // USD 5
const maxWithdrawalCents = 5000; // USD 50

class RewardsData {
  RewardsData({required this.pendingCents, required this.totalEarnedCents, required this.withdrawableCents, required this.events});

  /// Potencial de aportes aún en revisión (no es saldo).
  final int pendingCents;

  /// Todo lo aprobado alguna vez (incluye lo ya retirado).
  final int totalEarnedCents;

  /// Disponible para retirar: recompensas disponibles − retiros no rechazados.
  final int withdrawableCents;
  final List<Map<String, dynamic>> events;
}

/// Saldo retirable. Si la función del servidor aún no existe, usa la suma de recompensas disponibles.
Future<int> loadWithdrawableCents() async {
  final db = Supabase.instance.client;
  try {
    return cents(await db.rpc('my_withdrawable_usd'));
  } on PostgrestException {
    final rows = await db
        .from('reward_events')
        .select('amount_usd')
        .eq('user_id', db.auth.currentUser!.id)
        .eq('status', 'AVAILABLE');
    return rows.fold<int>(0, (a, r) => a + cents(r['amount_usd']));
  }
}

Future<RewardsData> loadRewards() async {
  final db = Supabase.instance.client;
  final uid = db.auth.currentUser!.id;
  final events = List<Map<String, dynamic>>.from(await db
      .from('reward_events')
      .select('id, kind, amount_usd, status, reason, created_at, missions(title), mission_contributions(name)')
      .eq('user_id', uid)
      .order('created_at', ascending: false)
      .limit(200));
  final pending = await db
      .from('mission_contributions')
      .select('id, missions(individual_reward_usd)')
      .eq('user_id', uid)
      .inFilter('status', ['SUBMITTED', 'AUTO_CHECKED', 'HUMAN_REVIEW']);
  var pendingCents = 0;
  for (final p in pending) {
    pendingCents += cents((p['missions'] as Map<String, dynamic>?)?['individual_reward_usd']);
  }
  const earned = {'EARNED', 'AVAILABLE', 'WITHDRAWAL_REQUESTED', 'PAID'};
  final total = events.where((e) => earned.contains(e['status'])).fold<int>(0, (a, e) => a + cents(e['amount_usd']));
  return RewardsData(
    pendingCents: pendingCents,
    totalEarnedCents: total,
    withdrawableCents: await loadWithdrawableCents(),
    events: events,
  );
}

class RewardsScreen extends StatefulWidget {
  const RewardsScreen({super.key});

  @override
  State<RewardsScreen> createState() => _RewardsScreenState();
}

class _RewardsScreenState extends State<RewardsScreen> {
  late Future<RewardsData> _future = loadRewards();
  bool _all = false;

  Future<void> _refresh() async {
    final f = loadRewards();
    setState(() => _future = f);
    await f;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<RewardsData>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('No se pudieron cargar tus ganancias.'),
              TextButton(onPressed: _refresh, child: const Text('Reintentar')),
            ]),
          );
        }
        final d = snap.data!;
        final events = _all ? d.events : d.events.take(5).toList();
        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
            children: [
              const ScreenTitle('Mis recompensas', icon: Icons.savings, iconColor: HtColors.amber),
              const SizedBox(height: 14),
              _BalanceCard(cents: d.withdrawableCents),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: _MiniStat(
                    icon: Icons.schedule,
                    iconColor: HtColors.amber,
                    label: 'En revisión',
                    value: usd(d.pendingCents),
                    background: Colors.white,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _MiniStat(
                    icon: Icons.check_circle,
                    iconColor: HtColors.green,
                    label: 'Total ganado',
                    value: usd(d.totalEarnedCents),
                    valueColor: HtColors.green,
                    background: HtColors.greenSoft,
                  ),
                ),
              ]),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: () async {
                  await Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => WithdrawAmountScreen(availableCents: d.withdrawableCents)));
                  _refresh();
                },
                icon: const Icon(Icons.send),
                label: const Text('Retirar recompensas'),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const WithdrawalsScreen())),
                icon: const Icon(Icons.list),
                label: const Text('Mis retiros'),
              ),
              const SizedBox(height: 20),
              SectionTitle(
                'Historial de ganancias',
                icon: Icons.format_list_bulleted,
                action: d.events.length > 5 ? (_all ? 'Ver menos' : 'Ver todo') : null,
                onAction: () => setState(() => _all = !_all),
              ),
              const SizedBox(height: 6),
              if (d.events.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Text('Aún no tienes recompensas. Cuando se aprueben tus aportes aparecerán aquí.',
                      textAlign: TextAlign.center),
                )
              else
                HtCard(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  child: Column(children: [
                    for (var i = 0; i < events.length; i++) ...[
                      if (i > 0) const Divider(height: 1),
                      _EventRow(e: events[i]),
                    ],
                  ]),
                ),
              const SizedBox(height: 12),
              const Text(
                'Las recompensas se acreditan solo tras la aprobación de cada aporte. '
                'El saldo pasa a "disponible" después de los controles de calidad.',
                style: TextStyle(fontSize: 12, color: HtColors.muted),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({required this.cents});
  final int cents;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [HtColors.blue, Color(0xFF1E63E9)]),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Text('Saldo disponible', style: TextStyle(color: Colors.white, fontSize: 16)),
              const SizedBox(width: 6),
              Tooltip(
                message: trn('Recompensas aprobadas que ya puedes retirar.'),
                triggerMode: TooltipTriggerMode.tap,
                child: Icon(Icons.info_outline, color: Colors.white.withValues(alpha: .9), size: 18),
              ),
            ]),
            const SizedBox(height: 6),
            Text(usd(cents), style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w800)),
          ]),
        ),
        Icon(Icons.account_balance_wallet, color: Colors.white.withValues(alpha: .85), size: 56),
      ]),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
    required this.background,
    this.valueColor = HtColors.text,
  });
  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;
  final Color background;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    return HtCard(
      color: background,
      padding: const EdgeInsets.all(12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: iconColor),
        const SizedBox(width: 8),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(value, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: valueColor)),
            ),
          ]),
        ),
      ]),
    );
  }
}

class _EventRow extends StatelessWidget {
  const _EventRow({required this.e});
  final Map<String, dynamic> e;

  static const _kinds = {
    'CONTRIBUTION': 'Aporte aprobado',
    'MISSION_BONUS': 'Bono de misión',
    'WELCOME_BONUS': 'Bono de bienvenida',
    'ADJUSTMENT': 'Ajuste',
  };

  @override
  Widget build(BuildContext context) {
    final amount = cents(e['amount_usd']);
    final mission = (e['missions'] as Map<String, dynamic>?)?['title'] as String?;
    final place = (e['mission_contributions'] as Map<String, dynamic>?)?['name'] as String?;
    final title = e['kind'] == 'MISSION_BONUS'
        ? 'Bono de misión'
        : (mission != null ? 'Misión: $mission' : (_kinds[e['kind']] ?? e['kind'] as String));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(children: [
        IconTile(e['kind'] == 'MISSION_BONUS' ? Icons.emoji_events_outlined : Icons.storefront, size: 44),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
            Text(
              [if (place != null) place, fechaHora(DateTime.parse(e['created_at'] as String))].join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: HtColors.muted, fontSize: 13),
            ),
          ]),
        ),
        Text(
          '${amount >= 0 ? '+' : '-'}${money(amount.abs())}',
          style: TextStyle(fontWeight: FontWeight.w800, color: amount >= 0 ? HtColors.green : HtColors.red, fontSize: 16),
        ),
      ]),
    );
  }
}
