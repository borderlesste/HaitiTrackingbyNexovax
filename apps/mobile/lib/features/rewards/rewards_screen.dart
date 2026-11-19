import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme.dart';

/// Montos en centavos enteros para no usar float en dinero.
int cents(Object? v) {
  if (v == null) return 0;
  final s = v.toString();
  final neg = s.startsWith('-');
  final parts = (neg ? s.substring(1) : s).split('.');
  final whole = int.tryParse(parts[0]) ?? 0;
  final frac = parts.length > 1 ? int.tryParse(parts[1].padRight(2, '0').substring(0, 2)) ?? 0 : 0;
  final c = whole * 100 + frac;
  return neg ? -c : c;
}

String money(int c) => '\$${(c ~/ 100)}.${(c.abs() % 100).toString().padLeft(2, '0')}';

const minWithdrawalCents = 500; // USD 5
const maxWithdrawalCents = 5000; // USD 50

class RewardsData {
  RewardsData({required this.pendingCents, required this.earnedCents, required this.availableCents, required this.onHoldCents, required this.events});
  final int pendingCents;
  final int earnedCents;
  final int availableCents;
  final int onHoldCents;
  final List<Map<String, dynamic>> events;
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
  // Potencial: aportes aún en revisión × recompensa de su misión (no es saldo).
  final pending = await db
      .from('mission_contributions')
      .select('id, missions(individual_reward_usd)')
      .eq('user_id', uid)
      .inFilter('status', ['SUBMITTED', 'AUTO_CHECKED', 'HUMAN_REVIEW']);
  var pendingCents = 0;
  for (final p in pending) {
    pendingCents += cents((p['missions'] as Map<String, dynamic>?)?['individual_reward_usd']);
  }
  int sumWhere(String status) =>
      events.where((e) => e['status'] == status).fold(0, (a, e) => a + cents(e['amount_usd']));
  return RewardsData(
    pendingCents: pendingCents,
    earnedCents: sumWhere('EARNED'),
    availableCents: sumWhere('AVAILABLE'),
    onHoldCents: sumWhere('ON_HOLD'),
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
        final toward = d.earnedCents + d.availableCents;
        final progress = (toward / minWithdrawalCents).clamp(0.0, 1.0);
        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _BalanceCard(data: d),
              const SizedBox(height: 12),
              Card(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(
                      toward >= minWithdrawalCents
                          ? '¡Alcanzaste el mínimo de retiro!'
                          : 'Te faltan ${money(minWithdrawalCents - toward)} para el mínimo de retiro (\$5)',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(value: progress, minHeight: 12, color: HtColors.green, backgroundColor: const Color(0xFFE3E8F2)),
                    ),
                    const SizedBox(height: 6),
                    Text('${money(toward)} de \$5.00', style: const TextStyle(fontSize: 12, color: Colors.black54)),
                  ]),
                ),
              ),
              const SizedBox(height: 12),
              _WithdrawCard(availableCents: d.availableCents),
              const SizedBox(height: 16),
              const Text('Historial', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              if (d.events.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Text('Aún no tienes recompensas. Cuando un moderador apruebe tus aportes aparecerán aquí.', textAlign: TextAlign.center),
                ),
              for (final e in d.events) _EventTile(e: e),
              const SizedBox(height: 12),
              const Text(
                'Las recompensas se acreditan solo tras la aprobación de cada aporte. '
                'El saldo pasa a "disponible" después de los controles de calidad.',
                style: TextStyle(fontSize: 12, color: Colors.black54),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({required this.data});
  final RewardsData data;

  @override
  Widget build(BuildContext context) {
    Widget cell(String label, int c, {Color? color, String? hint}) => Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
            const SizedBox(height: 2),
            Text(money(c), style: TextStyle(color: color ?? Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
            if (hint != null) Text(hint, style: const TextStyle(color: Colors.white54, fontSize: 10)),
          ]),
        );
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: HtColors.navy, borderRadius: BorderRadius.circular(18)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Mis ganancias (USD)', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
        const SizedBox(height: 14),
        Row(children: [
          cell('En revisión', data.pendingCents, color: const Color(0xFFFFD580), hint: 'potencial'),
          cell('Aprobado', data.earnedCents),
          cell('Disponible', data.availableCents, color: const Color(0xFF8CF0B4)),
        ]),
        if (data.onHoldCents > 0) ...[
          const SizedBox(height: 10),
          Text('Retenido para revisión: ${money(data.onHoldCents)}', style: const TextStyle(color: Colors.white70, fontSize: 12)),
        ],
      ]),
    );
  }
}

class _WithdrawCard extends StatelessWidget {
  const _WithdrawCard({required this.availableCents});
  final int availableCents;

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Row(children: [
            Icon(Icons.account_balance_wallet_outlined, color: HtColors.red),
            SizedBox(width: 8),
            Text('Retirar con MonCash', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ]),
          const SizedBox(height: 6),
          Text('Mínimo ${money(minWithdrawalCents)} y máximo ${money(maxWithdrawalCents)} por solicitud. '
              'Las comisiones de MonCash corren por tu cuenta y se mostrarán antes de confirmar.'),
          const SizedBox(height: 10),
          const FilledButton(onPressed: null, child: Text('Retiro temporalmente no disponible')),
          const SizedBox(height: 4),
          const Text('Los retiros se activarán cuando el servicio MonCash esté aprobado. Tu saldo queda guardado.',
              style: TextStyle(fontSize: 12, color: Colors.black54)),
        ]),
      ),
    );
  }
}

class _EventTile extends StatelessWidget {
  const _EventTile({required this.e});
  final Map<String, dynamic> e;

  static const _kinds = {
    'CONTRIBUTION': 'Aporte aprobado',
    'MISSION_BONUS': 'Bono de misión',
    'WELCOME_BONUS': 'Bono de bienvenida',
    'ADJUSTMENT': 'Ajuste',
  };
  static const _status = {
    'EARNED': 'Aprobado',
    'AVAILABLE': 'Disponible',
    'ON_HOLD': 'Retenido',
    'WITHDRAWAL_REQUESTED': 'En retiro',
    'PAID': 'Pagado',
    'REVERSED': 'Revertido',
    'PENDING_REVIEW': 'En revisión',
  };

  @override
  Widget build(BuildContext context) {
    final amount = cents(e['amount_usd']);
    final place = (e['mission_contributions'] as Map<String, dynamic>?)?['name'] as String?;
    final mission = (e['missions'] as Map<String, dynamic>?)?['title'] as String?;
    final date = DateFormat('dd/MM/yyyy').format(DateTime.parse(e['created_at'] as String).toLocal());
    return Card(
      child: ListTile(
        leading: Icon(e['kind'] == 'MISSION_BONUS' ? Icons.emoji_events_outlined : Icons.place_outlined, color: HtColors.blue),
        title: Text(_kinds[e['kind']] ?? e['kind'] as String),
        subtitle: Text([if (place != null) place, if (mission != null) mission, '$date · ${_status[e['status']] ?? e['status']}'].join('\n')),
        isThreeLine: place != null || mission != null,
        trailing: Text(
          '${amount >= 0 ? '+' : '-'}${money(amount.abs())}',
          style: TextStyle(fontWeight: FontWeight.bold, color: amount >= 0 ? HtColors.green : HtColors.red, fontSize: 16),
        ),
      ),
    );
  }
}
