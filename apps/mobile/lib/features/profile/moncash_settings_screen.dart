import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/account.dart';
import '../../core/money.dart';
import '../../core/theme.dart';
import '../../core/ui.dart';
import '../rewards/withdraw_screens.dart';
import '../rewards/withdrawals_screen.dart';
import 'verify_phone_screen.dart';

/// Configuración de MonCash: número verificado, titular y reglas de retiro.
class MoncashSettingsScreen extends StatefulWidget {
  const MoncashSettingsScreen({super.key});

  @override
  State<MoncashSettingsScreen> createState() => _MoncashSettingsScreenState();
}

class _MoncashSettingsScreenState extends State<MoncashSettingsScreen> {
  MyProfile? _profile;
  DateTime? _verifiedAt;
  WithdrawalSettings _settings = const WithdrawalSettings();
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = Supabase.instance.client;
    try {
      final p = await loadMyProfile();
      DateTime? at;
      if (p.phoneVerified) {
        final row = await db
            .from('moncash_verifications')
            .select('verified_at')
            .eq('user_id', db.auth.currentUser!.id)
            .maybeSingle();
        if (row?['verified_at'] != null) at = DateTime.parse(row!['verified_at'] as String);
      }
      final s = await loadWithdrawalSettings();
      if (mounted) {
        setState(() {
          _profile = p;
          _verifiedAt = at;
          _settings = s;
        });
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _verify() async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const VerifyPhoneScreen()));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final p = _profile;
    final ok = p?.phoneVerified == true;
    final phone = ok ? p!.row['moncash_phone'] as String? : p?.phone;
    return HtScaffold(
      background: Colors.white,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
                children: [
                  const ScreenTitle('Mi MonCash',
                      icon: Icons.account_balance_wallet_outlined,
                      subtitle: 'La cuenta donde recibes tus recompensas.'),
                  const SizedBox(height: 16),
                  HtCard(
                    color: ok ? HtColors.greenSoft : HtColors.surface,
                    child: Row(children: [
                      const MonCashBadge(size: 52),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(phone == null || phone.isEmpty ? 'Sin número' : formatHaitiPhone(phone),
                              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                          const SizedBox(height: 4),
                          StatusChip(ok ? 'Verificado por SMS' : 'Sin verificar',
                              tone: ok ? ChipTone.ok : ChipTone.review),
                        ]),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 12),
                  HtCard(
                    child: Column(children: [
                      KvRow('Titular', (p?.fullName.isNotEmpty ?? false) ? p!.fullName : '—', icon: Icons.person_outline),
                      if (_verifiedAt != null)
                        KvRow('Verificado el', fechaHora(_verifiedAt!), icon: Icons.verified_outlined),
                      KvRow('Retiro mínimo', usd(_settings.minCents), icon: Icons.south_west),
                      KvRow('Retiro máximo', usd(_settings.maxCents), icon: Icons.north_east),
                      KvRow('Retiros', _settings.enabled ? 'Habilitados' : 'Aún no disponibles',
                          icon: Icons.schedule, valueColor: _settings.enabled ? HtColors.green : HtColors.amber),
                    ]),
                  ),
                  const SizedBox(height: 12),
                  InfoBanner(ok
                      ? 'Solo pagamos al número verificado. Si cambias de número, tendrás que verificarlo otra vez con un código SMS.'
                      : 'Para retirar dinero confirma tu número MonCash con un código SMS. El titular debe ser la misma persona de la cuenta.'),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: _verify,
                    icon: Icon(ok ? Icons.swap_horiz : Icons.sms_outlined),
                    label: Text(ok ? 'Cambiar número MonCash' : 'Verificar mi número'),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: () =>
                        Navigator.of(context).push(MaterialPageRoute(builder: (_) => const WithdrawalsScreen())),
                    icon: const Icon(Icons.receipt_long_outlined),
                    label: const Text('Ver mis retiros'),
                  ),
                ],
              ),
            ),
    );
  }
}
