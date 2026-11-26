import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/money.dart';
import '../../core/theme.dart';
import '../../core/ui.dart';
import '../contributions/contribution_detail_screen.dart';
import '../profile/help_support_screen.dart';
import '../rewards/withdrawals_screen.dart';

/// Un aviso para el colaborador, armado a partir de sus datos (aportes, recompensas, retiros, soporte).
class AppNotice {
  AppNotice({required this.at, required this.icon, required this.color, required this.title, required this.body, this.open});
  final DateTime at;
  final IconData icon;
  final Color color;
  final String title;
  final String body;
  final Widget Function()? open;
}

/// Avisos del colaborador. No hay tabla de notificaciones: se calculan a partir de los cambios de estado.
class Notices {
  static final unread = ValueNotifier<int>(0);
  static const _seenKey = 'notices_seen_at_v1';

  static Future<DateTime> _seenAt() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getString(_seenKey);
    return v == null ? DateTime.now().subtract(const Duration(days: 7)) : DateTime.parse(v);
  }

  static Future<void> markSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_seenKey, DateTime.now().toUtc().toIso8601String());
    unread.value = 0;
  }

  /// Recalcula el contador de la campana.
  static Future<void> refreshBadge() async {
    try {
      final list = await load();
      final seen = await _seenAt();
      unread.value = list.where((n) => n.at.isAfter(seen)).length;
    } catch (_) {}
  }

  static Future<List<AppNotice>> load() async {
    final db = Supabase.instance.client;
    final uid = db.auth.currentUser?.id;
    if (uid == null) return const [];
    final out = <AppNotice>[];

    Future<void> safe(Future<void> Function() f) async {
      try {
        await f();
      } catch (_) {}
    }

    await Future.wait([
      safe(() async {
        final rows = await db
            .from('mission_contributions')
            .select('id, name, status, review_reason, reviewed_at')
            .eq('user_id', uid)
            .not('reviewed_at', 'is', null)
            .order('reviewed_at', ascending: false)
            .limit(30);
        for (final c in rows) {
          final status = c['status'] as String?;
          final id = c['id'] as String;
          final reason = (c['review_reason'] as String?) ?? '';
          final (title, icon, color) = switch (status) {
            'APPROVED' => ('Aporte aprobado', Icons.check_circle, HtColors.green),
            'REJECTED' => ('Aporte rechazado', Icons.cancel, HtColors.red),
            'NEEDS_CHANGES' => ('Tu aporte requiere cambios', Icons.edit_note, HtColors.amber),
            _ => ('Aporte revisado', Icons.assignment_turned_in_outlined, HtColors.blue),
          };
          out.add(AppNotice(
            at: DateTime.parse(c['reviewed_at'] as String),
            icon: icon,
            color: color,
            title: title,
            body: '${c['name']}${reason.isEmpty ? '' : ': $reason'}',
            open: () => ContributionDetailScreen(id: id),
          ));
        }
      }),
      safe(() async {
        final rows = await db
            .from('reward_events')
            .select('kind, amount_usd, created_at, missions(title)')
            .eq('user_id', uid)
            .order('created_at', ascending: false)
            .limit(30);
        for (final r in rows) {
          final kind = r['kind'] as String?;
          final mission = (r['missions'] as Map<String, dynamic>?)?['title'] as String?;
          out.add(AppNotice(
            at: DateTime.parse(r['created_at'] as String),
            icon: Icons.savings_outlined,
            color: HtColors.green,
            title: switch (kind) {
              'MISSION_BONUS' => 'Bono de misión ganado',
              'WELCOME_BONUS' => 'Bono de bienvenida',
              'ADJUSTMENT' => 'Ajuste en tu saldo',
              _ => 'Recompensa acreditada',
            },
            body: '${usd(cents(r['amount_usd']))}${mission == null ? '' : ' · $mission'}',
          ));
        }
      }),
      safe(() async {
        final rows = await db
            .from('withdrawal_requests')
            .select('code, status, amount_usd, created_at, processed_at, rejection_reason')
            .eq('user_id', uid)
            .order('created_at', ascending: false)
            .limit(20);
        for (final w in rows) {
          final status = w['status'] as String?;
          final at = DateTime.parse((w['processed_at'] ?? w['created_at']) as String);
          final (title, color) = switch (status) {
            'COMPLETED' => ('Retiro pagado', HtColors.green),
            'REJECTED' => ('Retiro rechazado', HtColors.red),
            'PROCESSING' => ('Retiro en proceso', HtColors.amber),
            _ => ('Retiro solicitado', HtColors.blue),
          };
          final why = w['rejection_reason'] as String?;
          out.add(AppNotice(
            at: at,
            icon: Icons.account_balance_wallet_outlined,
            color: color,
            title: title,
            body: 'Retiro #${w['code']} · ${usd(cents(w['amount_usd']))}${why == null || why.isEmpty ? '' : ' · $why'}',
            open: () => const WithdrawalsScreen(),
          ));
        }
      }),
      safe(() async {
        final rows = await db
            .from('support_tickets')
            .select('code, subject, admin_reply, status, updated_at')
            .eq('user_id', uid)
            .not('admin_reply', 'is', null)
            .order('updated_at', ascending: false)
            .limit(20);
        for (final t in rows) {
          out.add(AppNotice(
            at: DateTime.parse(t['updated_at'] as String),
            icon: Icons.support_agent,
            color: HtColors.navy,
            title: 'Soporte respondió tu solicitud ${t['code']}',
            body: t['admin_reply'] as String,
            open: () => const HelpSupportScreen(),
          ));
        }
      }),
      safe(() async {
        final since = DateTime.now().subtract(const Duration(days: 14)).toUtc().toIso8601String();
        final rows = await db
            .from('missions')
            .select('title, commune, start_at, created_at')
            .eq('status', 'ACTIVE')
            .gte('created_at', since)
            .order('created_at', ascending: false)
            .limit(10);
        for (final m in rows) {
          out.add(AppNotice(
            at: DateTime.parse((m['start_at'] ?? m['created_at']) as String),
            icon: Icons.flag_outlined,
            color: HtColors.blue,
            title: 'Nueva misión disponible',
            body: '${m['title']}${m['commune'] == null ? '' : ' · ${m['commune']}'}',
          ));
        }
      }),
    ]);
    final now = DateTime.now();
    out.removeWhere((n) => n.at.isAfter(now.add(const Duration(minutes: 5))));
    out.sort((a, b) => b.at.compareTo(a.at));
    return out;
  }
}

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<AppNotice> _items = const [];
  DateTime? _seen;
  bool _loading = true;
  int _filter = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final seen = await Notices._seenAt();
    final items = await Notices.load();
    if (!mounted) return;
    setState(() {
      _seen = seen;
      _items = items;
      _loading = false;
    });
    await Notices.markSeen();
  }

  @override
  Widget build(BuildContext context) {
    final seen = _seen;
    final unread = seen == null ? 0 : _items.where((n) => n.at.isAfter(seen)).length;
    final list = _filter == 1 && seen != null ? _items.where((n) => n.at.isAfter(seen)).toList() : _items;
    return HtScaffold(
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
          children: [
            const ScreenTitle('Notificaciones', icon: Icons.notifications_none),
            const SizedBox(height: 12),
            FilterPills(
              labels: ['Todas (${_items.length})', 'Nuevas ($unread)'],
              selected: _filter,
              onSelected: (i) => setState(() => _filter = i),
            ),
            const SizedBox(height: 12),
            if (_loading)
              const Padding(padding: EdgeInsets.all(30), child: Center(child: CircularProgressIndicator()))
            else if (list.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 50),
                child: Column(children: [
                  Icon(Icons.notifications_none, size: 56, color: HtColors.blue),
                  SizedBox(height: 10),
                  Text('No tienes notificaciones', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                  SizedBox(height: 6),
                  Text('Te avisaremos cuando se revise un aporte, recibas una recompensa o cambie un retiro.',
                      textAlign: TextAlign.center, style: TextStyle(color: HtColors.muted)),
                ]),
              )
            else
              HtCard(
                padding: EdgeInsets.zero,
                child: Column(children: [
                  for (var i = 0; i < list.length; i++) ...[
                    if (i > 0) const Divider(height: 1, indent: 16, endIndent: 16),
                    _NoticeTile(list[i], isNew: seen != null && list[i].at.isAfter(seen)),
                  ],
                ]),
              ),
          ],
        ),
      ),
    );
  }
}

class _NoticeTile extends StatelessWidget {
  const _NoticeTile(this.n, {required this.isNew});
  final AppNotice n;
  final bool isNew;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: n.open == null ? null : () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => n.open!())),
      child: Container(
        color: isNew ? HtColors.blueSoft.withValues(alpha: .5) : null,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          IconTile(n.icon, color: n.color, background: n.color.withValues(alpha: .12), size: 44),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(n.title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
              const SizedBox(height: 2),
              Text(n.body, maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(height: 1.3)),
              const SizedBox(height: 4),
              Text(fechaHora(n.at), style: const TextStyle(color: HtColors.muted, fontSize: 12)),
            ]),
          ),
          if (isNew)
            Container(
              margin: const EdgeInsets.only(left: 6, top: 4),
              width: 10,
              height: 10,
              decoration: const BoxDecoration(color: HtColors.red, shape: BoxShape.circle),
            ),
        ]),
      ),
    );
  }
}
