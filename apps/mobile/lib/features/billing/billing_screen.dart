import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/panel.dart';
import '../../core/theme.dart';
import '../../core/ui.dart';

/// Planes y facturación de Empresa (pantalla 23) y Desarrollador (32).
/// Cambiar a un plan de pago queda "Solicitado" hasta que el equipo confirme el pago y lo active.
class BillingScreen extends StatefulWidget {
  const BillingScreen({super.key, required this.audience, this.orgId});
  final String audience; // 'company' | 'developer'
  final String? orgId;

  @override
  State<BillingScreen> createState() => _BillingScreenState();
}

class _BillingData {
  _BillingData(this.plans, this.subs, this.invoices);
  final List<Map<String, dynamic>> plans;
  final List<Map<String, dynamic>> subs;
  final List<Map<String, dynamic>> invoices;

  Map<String, dynamic>? get active => subs.where((s) => s['status'] == 'ACTIVE').firstOrNull;
  Map<String, dynamic>? get requested => subs.where((s) => s['status'] == 'REQUESTED').firstOrNull;
}

class _BillingScreenState extends State<BillingScreen> {
  final _db = Supabase.instance.client;
  late Future<_BillingData> _data = _load();

  Future<_BillingData> _load() async {
    final plans = await _db.from('billing_plans').select().eq('audience', widget.audience).order('sort');
    var subsQ = _db.from('billing_subscriptions').select().eq('audience', widget.audience);
    var invQ = _db.from('invoices').select().eq('audience', widget.audience);
    if (widget.orgId != null) {
      subsQ = subsQ.eq('org_id', widget.orgId!);
      invQ = invQ.eq('org_id', widget.orgId!);
    } else {
      subsQ = subsQ.eq('owner_id', _db.auth.currentUser!.id);
      invQ = invQ.eq('owner_id', _db.auth.currentUser!.id);
    }
    final subs = await subsQ.order('created_at', ascending: false);
    final inv = await invQ.order('created_at', ascending: false).limit(24);
    return _BillingData(List.from(plans), List.from(subs), List.from(inv));
  }

  Future<void> _choose(Map<String, dynamic> plan) async {
    final paid = (plan['price_usd_month'] as num) > 0;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Plan ${plan['name']}'),
        content: Text(paid
            ? 'Enviaremos tu solicitud al equipo. Te contactaremos para el pago (MonCash o transferencia) '
                'y el plan se activará cuando se confirme.'
            : 'Cambiarás al plan gratuito de inmediato.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(paid ? 'Solicitar' : 'Cambiar')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _db.rpc('request_plan', params: {'p_plan': plan['code'], 'p_org': widget.orgId});
      if (!mounted) return;
      snack(context, paid ? 'Solicitud enviada. Te contactaremos para el pago.' : 'Plan actualizado.');
      setState(() => _data = _load());
    } on PostgrestException catch (e) {
      if (mounted) snack(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_BillingData>(
      future: _data,
      builder: (context, snap) {
        final children = <Widget>[];
        if (snap.hasError) {
          children.add(EmptyState(
            icon: Icons.receipt_long,
            title: 'No se pudo cargar',
            text: 'Revisa tu conexión e inténtalo de nuevo.',
            action: OutlinedButton(onPressed: () => setState(() => _data = _load()), child: const Text('Reintentar')),
          ));
        } else if (!snap.hasData) {
          children.add(const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator())));
        } else {
          final d = snap.data!;
          final activeCode = d.active?['plan_code'] as String? ?? d.plans.firstOrNull?['code'];
          final activePlan = d.plans.where((p) => p['code'] == activeCode).firstOrNull;
          children.addAll([
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(color: HtColors.blue, borderRadius: BorderRadius.circular(18)),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Plan actual', style: TextStyle(color: Colors.white70, fontSize: 15)),
                    Text(activePlan?['name'] as String? ?? 'Gratis',
                        style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w800)),
                    Text(_price(activePlan), style: const TextStyle(color: Colors.white, fontSize: 15)),
                  ]),
                ),
                const Icon(Icons.workspace_premium, color: Colors.white, size: 54),
              ]),
            ),
            if (d.requested != null) ...[
              const SizedBox(height: 12),
              InfoBanner(
                  'Solicitaste el plan ${_planName(d, d.requested!['plan_code'])}. '
                  'Se activará cuando el equipo confirme el pago.',
                  warning: true),
            ],
            const SizedBox(height: 20),
            const SectionTitle('Planes disponibles', icon: Icons.layers_outlined),
            const SizedBox(height: 8),
            for (final p in d.plans) ...[
              _PlanCard(
                plan: p,
                current: p['code'] == activeCode,
                requested: p['code'] == d.requested?['plan_code'],
                onChoose: () => _choose(p),
              ),
              const SizedBox(height: 10),
            ],
            const SizedBox(height: 10),
            const SectionTitle('Facturas', icon: Icons.receipt_long_outlined),
            const SizedBox(height: 8),
            if (d.invoices.isEmpty)
              const HtCard(child: Text('Aún no tienes facturas.', style: TextStyle(color: HtColors.muted)))
            else
              HtCard(
                padding: EdgeInsets.zero,
                child: Column(children: [
                  for (final (i, inv) in d.invoices.indexed)
                    SettingRow(
                      icon: Icons.description_outlined,
                      title: '${inv['number']} · \$${(inv['amount_usd'] as num).toStringAsFixed(2)} USD',
                      subtitle: '${inv['description'] ?? ''} ${fechaCorta(DateTime.parse(inv['created_at'] as String))}'.trim(),
                      trailing: switch (inv['status']) {
                        'PAID' => const StatusChip('Pagada', tone: ChipTone.ok),
                        'VOID' => const StatusChip('Anulada', tone: ChipTone.bad),
                        _ => const StatusChip('Pendiente', tone: ChipTone.review),
                      },
                      last: i == d.invoices.length - 1,
                    ),
                ]),
              ),
            const SizedBox(height: 16),
            const InfoBanner('Los pagos se coordinan con el equipo de Haiti Tracking. '
                'Nunca te pediremos datos de tarjeta dentro de la aplicación.'),
          ]);
        }
        return PanelPage(
          title: 'Planes y facturación',
          icon: Icons.workspace_premium_outlined,
          subtitle: widget.audience == 'company' ? 'Suscripción de tu empresa, pagos y facturas.' : 'Cuotas de consulta, suscripción y pagos.',
          onRefresh: () async => setState(() => _data = _load()),
          children: children,
        );
      },
    );
  }

  String _planName(_BillingData d, Object? code) => d.plans.where((p) => p['code'] == code).firstOrNull?['name'] as String? ?? '';
}

String _price(Map<String, dynamic>? p) {
  final v = (p?['price_usd_month'] as num?) ?? 0;
  return v == 0 ? 'Sin costo' : '\$${v.toStringAsFixed(v == v.roundToDouble() ? 0 : 2)} USD / mes';
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({required this.plan, required this.current, required this.requested, required this.onChoose});
  final Map<String, dynamic> plan;
  final bool current;
  final bool requested;
  final VoidCallback onChoose;

  @override
  Widget build(BuildContext context) {
    final features = List<String>.from(plan['features'] as List? ?? const []);
    return HtCard(
      borderColor: current ? HtColors.blue : null,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(plan['name'] as String, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800))),
          Text(_price(plan), style: const TextStyle(fontWeight: FontWeight.w800, color: HtColors.green, fontSize: 16)),
        ]),
        const SizedBox(height: 8),
        for (final f in features)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(children: [
              const Icon(Icons.check_circle, size: 18, color: HtColors.green),
              const SizedBox(width: 8),
              Expanded(child: Text(f)),
            ]),
          ),
        const SizedBox(height: 10),
        if (current)
          const StatusChip('Plan actual', tone: ChipTone.ok)
        else if (requested)
          const StatusChip('Solicitado', tone: ChipTone.review)
        else
          OutlinedButton(onPressed: onChoose, child: const Text('Elegir este plan')),
      ]),
    );
  }
}
