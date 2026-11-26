import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../core/account.dart';
import '../../core/money.dart';
import '../../core/theme.dart';
import '../../core/ui.dart';
import '../home/home_shell.dart';
import '../profile/verify_phone_screen.dart';
import 'withdrawals_screen.dart';

class WithdrawalSettings {
  const WithdrawalSettings({this.enabled = false, this.minCents = 500, this.maxCents = 5000});
  final bool enabled;
  final int minCents;
  final int maxCents;
}

Future<WithdrawalSettings> loadWithdrawalSettings() async {
  try {
    final row = await Supabase.instance.client.from('platform_settings').select('value').eq('key', 'withdrawals').maybeSingle();
    final v = (row?['value'] as Map<String, dynamic>?) ?? const {};
    return WithdrawalSettings(
      enabled: v['enabled'] == true,
      minCents: cents(v['min_usd'] ?? 5),
      maxCents: cents(v['max_usd'] ?? 50),
    );
  } catch (_) {
    return const WithdrawalSettings();
  }
}

// ---------------------------------------------------------------------------
// 1. Monto y cuenta MonCash
// ---------------------------------------------------------------------------
class WithdrawAmountScreen extends StatefulWidget {
  const WithdrawAmountScreen({super.key, required this.availableCents});
  final int availableCents;

  @override
  State<WithdrawAmountScreen> createState() => _WithdrawAmountScreenState();
}

class _WithdrawAmountScreenState extends State<WithdrawAmountScreen> {
  String? _phone;
  final _form = GlobalKey<FormState>();
  final _amount = TextEditingController();
  WithdrawalSettings _settings = const WithdrawalSettings();
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _loadPhone();
    loadWithdrawalSettings().then((s) {
      if (mounted) {
        setState(() {
          _settings = s;
          _loaded = true;
        });
      }
    });
  }

  Future<void> _loadPhone() async {
    final p = await loadMoncashPhone();
    if (mounted) setState(() => _phone = p);
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  String? _validate(String? v) {
    final c = cents((v ?? '').replaceAll(',', '.').trim());
    if (c <= 0) return 'Escribe el monto';
    if (c < _settings.minCents) return 'El mínimo es ${usd(_settings.minCents)}';
    if (c > _settings.maxCents) return 'El máximo por solicitud es ${usd(_settings.maxCents)}';
    if (c > widget.availableCents) return 'No puedes retirar más que tu saldo disponible';
    return null;
  }

  void _continue() {
    if (!_form.currentState!.validate()) return;
    final phone = _phone;
    if (phone == null) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => WithdrawConfirmScreen(amountCents: cents(_amount.text.replaceAll(',', '.').trim()), phone: phone),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final phone = _phone;
    return HtScaffold(
      background: Colors.white,
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
          children: [
            const ScreenTitle('Retirar recompensas',
                icon: Icons.account_balance_wallet_outlined,
                subtitle: 'Solicita el retiro de tu saldo disponible a tu cuenta MonCash.'),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              decoration: BoxDecoration(color: HtColors.greenSoft, borderRadius: BorderRadius.circular(12)),
              child: KvRow('Saldo disponible', usd(widget.availableCents), bold: true, valueColor: HtColors.green),
            ),
            const SizedBox(height: 18),
            const Text('Monto a retirar (USD)', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            TextFormField(
              controller: _amount,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d{0,3}([.,]\d{0,2})?'))],
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
              decoration: const InputDecoration(hintText: '10.00', prefixText: '\$ '),
              validator: _validate,
            ),
            const SizedBox(height: 4),
            Text('Monto mínimo: ${usd(_settings.minCents)} · máximo: ${usd(_settings.maxCents)}',
                style: const TextStyle(color: HtColors.muted)),
            const SizedBox(height: 18),
            const Text('Método de pago', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            const HtCard(
              padding: EdgeInsets.all(10),
              child: Row(children: [
                MonCashBadge(size: 44),
                SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('MonCash', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                    Text('Transferencia a tu billetera', style: TextStyle(color: HtColors.muted)),
                  ]),
                ),
              ]),
            ),
            const SizedBox(height: 18),
            const Text('Número MonCash', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            if (phone != null)
              HtCard(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                child: Row(children: [
                  Expanded(child: Text(formatHaitiPhone(phone), style: const TextStyle(fontSize: 18))),
                  const Icon(Icons.check_circle, color: HtColors.green),
                ]),
              )
            else
              OutlinedButton.icon(
                onPressed: () async {
                  await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const VerifyPhoneScreen()));
                  _loadPhone();
                },
                icon: const Icon(Icons.verified_user_outlined),
                label: const Text('Verificar mi número MonCash'),
              ),
            const SizedBox(height: 14),
            const InfoBanner('Asegúrate de que el número esté registrado a tu nombre. '
                'Solo pagamos al número verificado por SMS en tu cuenta.'),
            if (_loaded && !_settings.enabled) ...[
              const SizedBox(height: 12),
              const InfoBanner(
                'Los retiros todavía no están habilitados. Se activarán cuando el servicio MonCash esté aprobado. '
                'Tu saldo queda guardado.',
                warning: true,
              ),
            ],
            const SizedBox(height: 22),
            FilledButton(
              onPressed: _settings.enabled && phone != null ? _continue : null,
              child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text('Continuar'),
                SizedBox(width: 10),
                Icon(Icons.arrow_forward),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 2. Confirmar
// ---------------------------------------------------------------------------
class WithdrawConfirmScreen extends StatefulWidget {
  const WithdrawConfirmScreen({super.key, required this.amountCents, required this.phone});
  final int amountCents;
  final String phone;

  @override
  State<WithdrawConfirmScreen> createState() => _WithdrawConfirmScreenState();
}

class _WithdrawConfirmScreenState extends State<WithdrawConfirmScreen> {
  /// Una sola clave por pantalla: si se pulsa dos veces o se reintenta, no se crea otro retiro.
  final _key = const Uuid().v4();
  bool _busy = false;
  String? _error;

  Future<void> _confirm() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final amount = money(widget.amountCents).substring(1);
      final row = await Supabase.instance.client
          .rpc('request_withdrawal', params: {'p_amount': amount, 'p_idempotency_key': _key}) as Map<String, dynamic>;
      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => WithdrawDoneScreen(request: row)));
    } on PostgrestException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Sin conexión. Inténtalo de nuevo.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return HtScaffold(
      background: Colors.white,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
        children: [
          const ScreenTitle('Confirmar retiro',
              icon: Icons.fact_check_outlined, subtitle: 'Revisa los detalles de tu solicitud de retiro.'),
          const SizedBox(height: 16),
          HtCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              KvRow('Monto a retirar', usd(widget.amountCents)),
              const Divider(),
              const KvRow('Método de pago', '',
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    MonCashBadge(size: 30),
                    SizedBox(width: 8),
                    Text('MonCash', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  ])),
              const Divider(),
              KvRow('Número', formatHaitiPhone(widget.phone)),
              const Divider(),
              const Text('Recibirás', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(color: HtColors.greenSoft, borderRadius: BorderRadius.circular(12)),
                child: Text(usd(widget.amountCents),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: HtColors.green)),
              ),
              const SizedBox(height: 6),
              const Text('Menos la comisión de MonCash y según la cotización del día a HTG.',
                  style: TextStyle(fontSize: 12, color: HtColors.muted)),
            ]),
          ),
          const SizedBox(height: 12),
          const InfoBanner(
            'Una vez enviada la solicitud, será procesada por nuestro equipo. Te notificaremos cuando se complete.',
            warning: true,
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: HtColors.red)),
          ],
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _busy ? null : _confirm,
            icon: _busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.check),
            label: const Text('Confirmar retiro'),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _busy ? null : () => Navigator.pop(context),
            icon: const Icon(Icons.edit_outlined),
            label: const Text('Volver y editar'),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 3. Solicitud enviada
// ---------------------------------------------------------------------------
class WithdrawDoneScreen extends StatelessWidget {
  const WithdrawDoneScreen({super.key, required this.request});
  final Map<String, dynamic> request;

  @override
  Widget build(BuildContext context) {
    final amount = cents(request['amount_usd']);
    return HtScaffold(
      background: Colors.white,
      appBar: const HtAppBar(showBack: false),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          const Center(child: SuccessMark(size: 96)),
          const Text('¡Retiro solicitado!',
              textAlign: TextAlign.center, style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text.rich(
            TextSpan(children: [
              const TextSpan(text: 'Tu solicitud por '),
              TextSpan(text: usd(amount), style: const TextStyle(fontWeight: FontWeight.w800)),
              const TextSpan(text: ' ha sido recibida y está en proceso de resolución.'),
            ]),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16, color: HtColors.muted, height: 1.35),
          ),
          const SizedBox(height: 18),
          HtCard(
            child: Column(children: [
              const KvRow('Estado', '', icon: Icons.schedule, trailing: StatusChip('En proceso', tone: ChipTone.review)),
              const Divider(),
              KvRow('Fecha de solicitud', fechaHora(DateTime.parse(request['created_at'] as String)),
                  icon: Icons.calendar_month_outlined),
              const Divider(),
              const KvRow('Método de pago', 'MonCash', icon: Icons.account_balance_wallet_outlined),
              const Divider(),
              KvRow('Número', formatHaitiPhone(request['moncash_phone'] as String?), icon: Icons.phone_outlined),
            ]),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: () => Navigator.of(context)
                .pushReplacement(MaterialPageRoute(builder: (_) => const WithdrawalsScreen())),
            icon: const Icon(Icons.list),
            label: const Text('Ver mis retiros'),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () {
              HomeShell.tab.value = HomeTab.home;
              Navigator.of(context).popUntil((r) => r.isFirst);
            },
            icon: const Icon(Icons.home_outlined),
            label: const Text('Volver al inicio'),
          ),
        ],
      ),
    );
  }
}
