import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/panel.dart';
import '../../core/theme.dart';
import '../../core/ui.dart';

/// Planes y facturación de Empresa (pantalla 23) y Desarrollador (32).
/// Elegir un plan de pago genera su factura; se paga en línea (MonCash en HTG o tarjeta en USD)
/// y el plan se activa cuando el procesador confirma el cobro. Sin cobro en línea, el equipo lo activa a mano.
class BillingScreen extends StatefulWidget {
  const BillingScreen({super.key, required this.audience, this.orgId});
  final String audience; // 'company' | 'developer'
  final String? orgId;

  @override
  State<BillingScreen> createState() => _BillingScreenState();
}

class _BillingData {
  _BillingData(this.plans, this.subs, this.invoices, this.payments, this.settings);
  final List<Map<String, dynamic>> plans;
  final List<Map<String, dynamic>> subs;
  final List<Map<String, dynamic>> invoices;
  final List<Map<String, dynamic>> payments; // intentos en curso (CREATED)
  final Map<String, dynamic> settings;

  bool enabled(String provider) => (settings['providers'] as Map?)?[provider] == true;
  bool get canPayOnline => enabled('moncash') || enabled('stripe');
  num get rate => (settings['usd_htg_rate'] as num?) ?? 0;
  Map<String, dynamic>? pendingPayment(Object? invoiceId) =>
      payments.where((p) => p['invoice_id'] == invoiceId).firstOrNull;

  Map<String, dynamic>? get active => subs.where((s) => s['status'] == 'ACTIVE').firstOrNull;
  Map<String, dynamic>? get requested => subs.where((s) => s['status'] == 'REQUESTED').firstOrNull;
}

class _BillingScreenState extends State<BillingScreen> with WidgetsBindingObserver {
  final _db = Supabase.instance.client;
  late Future<_BillingData> _data = _load();
  final Set<String> _awaiting = {}; // pagos abiertos en el navegador en esta sesión
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Al volver del navegador, confirmamos el pago con el procesador.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _awaiting.isNotEmpty) {
      for (final id in _awaiting.toList()) {
        _verify(id, quiet: true);
      }
    }
  }

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
    final pendingIds = [for (final i in inv) if (i['status'] == 'PENDING') i['id'] as String];
    final payments = pendingIds.isEmpty
        ? const <Map<String, dynamic>>[]
        : await _db
            .from('invoice_payments')
            .select('id, invoice_id, provider, status, amount, currency, created_at')
            .inFilter('invoice_id', pendingIds)
            .eq('status', 'CREATED')
            .gte('created_at', DateTime.now().toUtc().subtract(const Duration(hours: 2)).toIso8601String())
            .order('created_at', ascending: false);
    final settings = await _db.from('platform_settings').select('value').eq('key', 'payments').maybeSingle();
    return _BillingData(List.from(plans), List.from(subs), List.from(inv), List.from(payments),
        Map<String, dynamic>.from((settings?['value'] as Map?) ?? const {}));
  }

  Map<String, String> _auth() => {'Authorization': 'Bearer ${_db.auth.currentSession?.accessToken ?? ''}'};

  /// Abre la página del procesador para pagar una factura.
  Future<void> _pay(_BillingData d, Map<String, dynamic> inv) async {
    final usd = (inv['amount_usd'] as num);
    final htg = (usd * d.rate).round();
    final provider = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text('Pagar ${inv['number']}', style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
          ),
          if (d.enabled('moncash'))
            ListTile(
              leading: const Icon(Icons.phone_android, color: HtColors.moncash),
              title: const Text('MonCash'),
              subtitle: Text('G ${_thousands(htg)} HTG · tasa ${d.rate} HTG por USD'),
              onTap: () => Navigator.pop(ctx, 'moncash'),
            ),
          if (d.enabled('stripe'))
            ListTile(
              leading: const Icon(Icons.credit_card, color: HtColors.blue),
              title: const Text('Tarjeta de crédito o débito'),
              subtitle: Text('\$${usd.toStringAsFixed(2)} USD'),
              onTap: () => Navigator.pop(ctx, 'stripe'),
            ),
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 4, 20, 16),
            child: Text('Se abrirá la página segura del procesador. Haiti Tracking no ve ni guarda tus datos de pago.',
                style: TextStyle(color: HtColors.muted)),
          ),
        ]),
      ),
    );
    if (provider == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final res = await _db.functions.invoke('billing-payments/checkout', headers: _auth(), body: {'invoice_id': inv['id'], 'provider': provider});
      final data = res.data;
      if (data is! Map || data['url'] is! String) throw const FormatException();
      _awaiting.add(data['payment_id'] as String);
      final opened = await launchUrl(Uri.parse(data['url'] as String), mode: LaunchMode.externalApplication);
      if (!opened && mounted) snack(context, 'No se pudo abrir la página de pago.');
      if (mounted) setState(() => _data = _load());
    } on FunctionException catch (e) {
      final details = e.details;
      if (mounted) snack(context, details is Map && details['message'] is String ? details['message'] as String : 'No se pudo iniciar el pago.');
    } catch (_) {
      if (mounted) snack(context, 'No se pudo iniciar el pago. Revisa tu conexión.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Pregunta al procesador si el pago ya se completó.
  Future<void> _verify(String paymentId, {bool quiet = false}) async {
    try {
      final res = await _db.functions.invoke('billing-payments/verify', headers: _auth(), body: {'payment_id': paymentId});
      final status = (res.data is Map) ? (res.data as Map)['status'] : null;
      if (status != 'CREATED') _awaiting.remove(paymentId);
      if (!mounted) return;
      if (status == 'PAID') {
        snack(context, 'Pago confirmado. Tu plan ya está activo.');
      } else if (status == 'REFUND_DUE') {
        snack(context, 'Recibimos un pago para una factura ya cerrada. El equipo te contactará para devolverlo.');
      } else if (!quiet) {
        snack(context, status == 'CREATED' ? 'Aún no recibimos la confirmación del pago.' : 'El pago no se completó. Puedes intentarlo de nuevo.');
      }
      setState(() => _data = _load());
    } catch (_) {
      if (mounted && !quiet) snack(context, 'No se pudo verificar el pago. Inténtalo de nuevo.');
    }
  }

  Future<void> _choose(_BillingData d, Map<String, dynamic> plan) async {
    final paid = (plan['price_usd_month'] as num) > 0;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Plan ${plan['name']}'),
        content: Text(!paid
            ? 'Cambiarás al plan gratuito de inmediato.'
            : d.canPayOnline
                ? 'Generaremos la factura del primer mes (${_price(plan)}) para que la pagues ahora en línea. '
                    'El plan se activa en cuanto se confirme el pago.'
                : 'Generaremos la factura del primer mes. El equipo te contactará para el pago (MonCash o transferencia) '
                    'y activará el plan cuando se confirme.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(!paid ? 'Cambiar' : d.canPayOnline ? 'Continuar al pago' : 'Solicitar')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final subId = await _db.rpc('request_plan', params: {'p_plan': plan['code'], 'p_org': widget.orgId});
      if (!mounted) return;
      setState(() => _data = _load());
      if (!paid) {
        snack(context, 'Plan actualizado.');
        return;
      }
      if (!d.canPayOnline) {
        snack(context, 'Solicitud enviada. Te contactaremos para el pago.');
        return;
      }
      final fresh = await _data;
      final inv = fresh.invoices.where((i) => i['subscription_id'] == subId && i['status'] == 'PENDING').firstOrNull;
      if (inv != null && mounted) await _pay(fresh, inv);
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
                  '${d.canPayOnline ? 'Paga su factura abajo y se activará al confirmarse el pago.' : 'Se activará cuando el equipo confirme el pago.'}',
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
                onChoose: () => _choose(d, p),
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
                        _ when d.pendingPayment(inv['id']) != null => TextButton(
                            onPressed: _busy ? null : () => _verify(d.pendingPayment(inv['id'])!['id'] as String),
                            child: const Text('Verificar pago')),
                        _ when d.canPayOnline && (inv['amount_usd'] as num) > 0 =>
                          FilledButton(onPressed: _busy ? null : () => _pay(d, inv), child: const Text('Pagar')),
                        _ => const StatusChip('Pendiente', tone: ChipTone.review),
                      },
                      // Tocar la fila permite volver a intentar el pago aunque haya uno en curso.
                      onTap: inv['status'] == 'PENDING' && d.canPayOnline && (inv['amount_usd'] as num) > 0 && !_busy
                          ? () => _pay(d, inv)
                          : null,
                      last: i == d.invoices.length - 1,
                    ),
                ]),
              ),
            const SizedBox(height: 16),
            InfoBanner(d.canPayOnline
                ? 'Los pagos se hacen en la página segura de MonCash o del procesador de tarjetas. '
                    'Nunca te pediremos datos de tarjeta dentro de la aplicación.'
                : 'Los pagos se coordinan con el equipo de Haiti Tracking. '
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

String _thousands(num v) => v.round().toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ' ');

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
