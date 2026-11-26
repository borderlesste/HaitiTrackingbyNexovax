import 'dart:io';

import 'package:flutter/material.dart' hide Text;
import 'package:haiti_tracking/core/i18n.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/evidence_upload.dart';
import '../../core/panel.dart';
import '../../core/theme.dart';
import '../../core/ui.dart';
import 'company_register_screen.dart';
import 'company_repo.dart';

/// Pantalla 16: Verificación empresarial (estado, documentos y reenvío si fue rechazada).
class CompanyVerificationScreen extends StatefulWidget {
  const CompanyVerificationScreen({super.key, required this.org, required this.onChanged});
  final Map<String, dynamic> org;
  final Future<void> Function() onChanged;

  @override
  State<CompanyVerificationScreen> createState() => _CompanyVerificationScreenState();
}

class _CompanyVerificationScreenState extends State<CompanyVerificationScreen> {
  final _repo = CompanyRepo();
  late Map<String, dynamic> _org = widget.org;
  late Future<List<Map<String, dynamic>>> _docs = _repo.documents(_org['id'] as String);
  bool _uploading = false;

  Future<void> _reload() async {
    await widget.onChanged();
    final org = await _repo.myOrganization();
    if (!mounted) return;
    setState(() {
      if (org != null) _org = org;
      _docs = _repo.documents(_org['id'] as String);
    });
  }

  Future<void> _upload() async {
    final type = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('¿Qué documento vas a subir?', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          ),
          for (final e in orgDocTypes.entries)
            ListTile(leading: const Icon(Icons.description_outlined, color: HtColors.blue), title: Text(e.value), onTap: () => Navigator.pop(ctx, e.key)),
        ]),
      ),
    );
    if (type == null || !mounted) return;
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.photo_camera_outlined), title: const Text('Tomar foto del documento'), onTap: () => Navigator.pop(ctx, ImageSource.camera)),
          ListTile(leading: const Icon(Icons.photo_library_outlined), title: const Text('Elegir de la galería'), onTap: () => Navigator.pop(ctx, ImageSource.gallery)),
        ]),
      ),
    );
    if (source == null) return;
    final picked = await ImagePicker().pickImage(source: source, maxWidth: 2000, imageQuality: 75);
    if (picked == null || !mounted) return;
    setState(() => _uploading = true);
    try {
      await _repo.uploadDocument(_org['id'] as String, type, File(picked.path), picked.name);
      if (mounted) snack(context, 'Documento enviado.');
      await _reload();
    } on InvalidEvidence catch (e) {
      if (mounted) snack(context, e.message);
    } catch (_) {
      if (mounted) snack(context, 'No se pudo subir el documento. Revisa tu conexión.');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _edit() async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (ctx) => HtScaffold(
        body: CompanyRegisterScreen(org: _org, onDone: () => Navigator.pop(ctx)),
      ),
    ));
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final status = _org['status'] as String;
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _docs,
      builder: (context, snap) {
        final docs = snap.data ?? const [];
        return PanelPage(
          title: 'Verificación empresarial',
          icon: Icons.verified_user_outlined,
          subtitle: 'Documentación y aprobación de tu empresa.',
          onRefresh: _reload,
          bottom: status == 'APPROVED'
              ? null
              : FilledButton.icon(
                  onPressed: _uploading ? null : _upload,
                  icon: _uploading
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.upload_file),
                  label: const Text('Subir documento'),
                ),
          children: [
            HtCard(
              child: Row(children: [
                IconTile(Icons.storefront, size: 56),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(_org['name'] as String, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                    Text('${_org['sector']} · ${_org['commune'] ?? ''}', style: const TextStyle(color: HtColors.muted)),
                  ]),
                ),
                reviewChip(status),
              ]),
            ),
            const SizedBox(height: 16),
            HtCard(
              child: Column(children: [
                _Step(done: true, title: 'Registro enviado', text: 'Datos de la empresa y del representante.'),
                _Step(
                  done: docs.isNotEmpty,
                  title: 'Documentos',
                  text: docs.isEmpty ? 'Sube al menos el registro de comercio o el NIF.' : '${docs.length} documento(s) enviado(s).',
                ),
                _Step(
                  done: status != 'PENDING',
                  active: status == 'PENDING',
                  title: 'Revisión del equipo',
                  text: status == 'PENDING' ? 'Normalmente tarda de 1 a 3 días hábiles.' : 'Revisión terminada.',
                ),
                _Step(
                  done: status == 'APPROVED',
                  failed: status == 'REJECTED',
                  last: true,
                  title: status == 'REJECTED' ? 'Verificación rechazada' : 'Empresa verificada',
                  text: switch (status) {
                    'APPROVED' => 'Ya puedes registrar establecimientos y solicitar misiones.',
                    'REJECTED' => _org['review_reason'] as String? ?? 'Corrige los datos y vuelve a enviarlos.',
                    _ => 'Te avisaremos al aprobarse.',
                  },
                ),
              ]),
            ),
            if (status == 'REJECTED') ...[
              const SizedBox(height: 12),
              FilledButton.icon(onPressed: _edit, icon: const Icon(Icons.edit), label: const Text('Corregir y reenviar')),
            ] else if (status == 'PENDING') ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(onPressed: _edit, icon: const Icon(Icons.edit_outlined), label: const Text('Editar datos del registro')),
            ],
            const SizedBox(height: 20),
            const SectionTitle('Documentos enviados', icon: Icons.folder_open_outlined),
            const SizedBox(height: 8),
            if (!snap.hasData)
              const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator()))
            else if (docs.isEmpty)
              const HtCard(child: Text('Todavía no has subido documentos.', style: TextStyle(color: HtColors.muted)))
            else
              HtCard(
                padding: EdgeInsets.zero,
                child: Column(children: [
                  for (final (i, d) in docs.indexed)
                    SettingRow(
                      icon: Icons.description_outlined,
                      title: orgDocTypes[d['doc_type']] ?? 'Documento',
                      subtitle: [fechaHora(DateTime.parse(d['created_at'] as String)), if (d['review_reason'] != null) d['review_reason']].join('\n'),
                      trailing: reviewChip(d['status'] as String?),
                      last: i == docs.length - 1,
                    ),
                ]),
              ),
            const SizedBox(height: 14),
            const InfoBanner('Tus documentos se guardan de forma privada: solo los ve el equipo de verificación.'),
          ],
        );
      },
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.done, required this.title, required this.text, this.active = false, this.failed = false, this.last = false});
  final bool done;
  final bool active;
  final bool failed;
  final bool last;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    final color = failed ? HtColors.red : (done ? HtColors.green : (active ? HtColors.amber : HtColors.border));
    final icon = failed ? Icons.close : (done ? Icons.check : (active ? Icons.schedule : Icons.circle_outlined));
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Column(children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            child: Icon(icon, size: 18, color: Colors.white),
          ),
          if (!last) Expanded(child: Container(width: 2, color: HtColors.border)),
        ]),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(bottom: last ? 0 : 16, top: 3),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5)),
              Text(text, style: const TextStyle(color: HtColors.muted)),
            ]),
          ),
        ),
      ]),
    );
  }
}
