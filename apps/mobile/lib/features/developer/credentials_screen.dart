import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/panel.dart';
import '../../core/theme.dart';
import '../../core/ui.dart';
import 'developer_repo.dart';

/// Muestra una clave recién creada UNA sola vez. La app no la guarda.
Future<void> showSecretOnce(BuildContext context, String secret, {bool rotated = false}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      title: Text(rotated ? 'Clave rotada' : 'Tu nueva clave'),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(
          rotated
              ? 'La clave anterior ya no funciona. Copia la nueva ahora: no volverá a mostrarse.'
              : 'Cópiala ahora: no volverá a mostrarse. Guárdala solo en tu servidor.',
          style: const TextStyle(color: HtColors.red),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: const Color(0xFF101828), borderRadius: BorderRadius.circular(10)),
          child: SelectableText(secret, style: const TextStyle(fontFamily: 'monospace', color: Color(0xFFB6F5C9), fontSize: 13)),
        ),
      ]),
      actions: [
        TextButton.icon(
          onPressed: () {
            Clipboard.setData(ClipboardData(text: secret));
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Clave copiada')));
          },
          icon: const Icon(Icons.copy),
          label: const Text('Copiar'),
        ),
        FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Ya la guardé')),
      ],
    ),
  );
}

/// Pantalla 28: Credenciales API (generar, rotar y revocar claves). Si se pasa [projectId], solo ese proyecto.
class CredentialsScreen extends StatefulWidget {
  const CredentialsScreen({super.key, this.projectId, this.embedded = false});
  final String? projectId;
  final bool embedded;

  @override
  State<CredentialsScreen> createState() => _CredentialsScreenState();
}

class _CredentialsScreenState extends State<CredentialsScreen> {
  final _repo = DeveloperRepo();
  late Future<(List<Map<String, dynamic>>, List<Map<String, dynamic>>)> _data = _load();

  Future<(List<Map<String, dynamic>>, List<Map<String, dynamic>>)> _load() async {
    var projects = await _repo.projects();
    if (widget.projectId != null) projects = projects.where((p) => p['id'] == widget.projectId).toList();
    final keys = await _repo.allKeys([for (final p in projects) p['id'] as String]);
    return (projects, keys);
  }

  void _reload() => setState(() => _data = _load());

  Future<void> _create(String projectId) async {
    try {
      final secret = await _repo.createKey(projectId);
      if (!mounted) return;
      await showSecretOnce(context, secret);
      _reload();
    } on PostgrestException catch (e) {
      if (mounted) snack(context, e.message);
    }
  }

  Future<bool> _confirm(String title, String text, String action) async =>
      await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: Text(text),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(action)),
          ],
        ),
      ) ==
      true;

  Future<void> _rotate(Map<String, dynamic> k) async {
    if (!await _confirm('Rotar clave', 'Se creará una clave nueva y ${k['prefix']}… dejará de funcionar de inmediato. '
        'Actualiza tu servidor con la nueva clave.', 'Rotar')) {
      return;
    }
    try {
      final secret = await _repo.rotateKey(k['id'] as String);
      if (!mounted) return;
      await showSecretOnce(context, secret, rotated: true);
      _reload();
    } on PostgrestException catch (e) {
      if (mounted) snack(context, e.message);
    }
  }

  Future<void> _revoke(Map<String, dynamic> k) async {
    if (!await _confirm('Revocar clave', 'La clave ${k['prefix']}… dejará de funcionar de inmediato. No se puede deshacer.', 'Revocar')) return;
    try {
      await _repo.revokeKey(k['id'] as String);
      _reload();
    } on PostgrestException catch (e) {
      if (mounted) snack(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: _data,
      builder: (context, snap) {
        final children = <Widget>[];
        if (snap.hasError) {
          children.add(EmptyState(icon: Icons.cloud_off, title: 'No se pudo cargar', text: 'Revisa tu conexión.',
              action: OutlinedButton(onPressed: _reload, child: const Text('Reintentar'))));
        } else if (!snap.hasData) {
          children.add(const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator())));
        } else {
          final (projects, keys) = snap.data!;
          if (projects.isEmpty) {
            children.add(const EmptyState(icon: Icons.vpn_key_outlined, title: 'Sin proyectos', text: 'Crea un proyecto para generar claves.'));
          }
          for (final p in projects) {
            final pk = keys.where((k) => k['project_id'] == p['id']).toList();
            final active = pk.where((k) => k['revoked_at'] == null).length;
            children.addAll([
              SectionTitle(p['name'] as String, icon: Icons.folder_outlined,
                  action: p['status'] == 'ACTIVE' && active < 3 ? 'Nueva clave' : null, onAction: () => _create(p['id'] as String)),
              const SizedBox(height: 6),
              if (pk.isEmpty)
                HtCard(
                  child: Row(children: [
                    const Expanded(child: Text('Sin claves todavía.', style: TextStyle(color: HtColors.muted))),
                    if (p['status'] == 'ACTIVE')
                      TextButton.icon(onPressed: () => _create(p['id'] as String), icon: const Icon(Icons.add), label: const Text('Generar')),
                  ]),
                ),
              for (final k in pk) ...[
                HtCard(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Icon(Icons.key, color: k['revoked_at'] == null ? HtColors.green : HtColors.muted),
                      const SizedBox(width: 10),
                      Expanded(child: Text('${k['prefix']}_••••••••', style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w700))),
                      k['revoked_at'] == null ? const StatusChip('Activa', tone: ChipTone.ok) : const StatusChip('Revocada', tone: ChipTone.bad),
                    ]),
                    const SizedBox(height: 6),
                    Text('Creada ${fechaHora(DateTime.parse(k['created_at'] as String))}', style: const TextStyle(color: HtColors.muted, fontSize: 13)),
                    Text(
                      k['last_used_at'] == null ? 'Sin uso todavía' : 'Último uso ${fechaHora(DateTime.parse(k['last_used_at'] as String))}',
                      style: const TextStyle(color: HtColors.muted, fontSize: 13),
                    ),
                    if (k['revoked_at'] == null && p['status'] == 'ACTIVE') ...[
                      const SizedBox(height: 8),
                      Row(children: [
                        Expanded(child: OutlinedButton.icon(onPressed: () => _rotate(k), icon: const Icon(Icons.autorenew), label: const Text('Rotar'))),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(foregroundColor: HtColors.red, side: const BorderSide(color: HtColors.red)),
                            onPressed: () => _revoke(k),
                            icon: const Icon(Icons.block),
                            label: const Text('Revocar'),
                          ),
                        ),
                      ]),
                    ],
                  ]),
                ),
                const SizedBox(height: 8),
              ],
              const SizedBox(height: 12),
            ]);
          }
          children.add(const InfoBanner('Por seguridad, la clave completa solo se muestra una vez al crearla o rotarla. '
              'La app no la guarda. Máximo 3 claves activas por proyecto.', warning: true));
        }
        if (widget.embedded) {
          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ListView(padding: const EdgeInsets.fromLTRB(16, 20, 16, 28), children: [
              const ScreenTitle('Credenciales API', icon: Icons.vpn_key_outlined, subtitle: 'Genera, rota y revoca tus claves.'),
              const SizedBox(height: 16),
              ...children,
            ]),
          );
        }
        return PanelPage(
          title: 'Credenciales API',
          icon: Icons.vpn_key_outlined,
          subtitle: 'Genera, rota y revoca tus claves.',
          onRefresh: () async => _reload(),
          children: children,
        );
      },
    );
  }
}
