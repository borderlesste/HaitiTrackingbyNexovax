import 'package:flutter/material.dart' hide Text;
import 'package:haiti_tracking/core/i18n.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/account.dart';
import '../../core/panel.dart';
import '../../core/profile_context.dart';
import '../../core/theme.dart';
import '../../core/ui.dart';
import 'company_repo.dart';

/// Pantalla 15: Registro empresarial (datos de la empresa y del representante).
/// Con [org] corrige y reenvía un registro pendiente o rechazado.
class CompanyRegisterScreen extends StatefulWidget {
  const CompanyRegisterScreen({super.key, this.org, required this.onDone});
  final Map<String, dynamic>? org;
  final VoidCallback onDone;

  @override
  State<CompanyRegisterScreen> createState() => _CompanyRegisterScreenState();
}

class _CompanyRegisterScreenState extends State<CompanyRegisterScreen> {
  final _repo = CompanyRepo();
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.org?['name'] as String?);
  late final _rep = TextEditingController(text: widget.org?['representative_name'] as String?);
  late final _legal = TextEditingController(text: widget.org?['legal_id'] as String?);
  late final _phone = TextEditingController(text: (widget.org?['contact_phone'] as String?)?.replaceFirst('+509', ''));
  late final _email = TextEditingController(text: widget.org?['contact_email'] as String?);
  late final _address = TextEditingController(text: widget.org?['address'] as String?);
  late final _website = TextEditingController(text: widget.org?['website'] as String?);
  late String _sector = companySectors.contains(widget.org?['sector']) ? widget.org!['sector'] as String : companySectors.first;
  late String? _commune = haitiCommunes.contains(widget.org?['commune']) ? widget.org!['commune'] as String : null;
  int _step = 1;
  bool _busy = false;
  String? _error;

  String? _t(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final f = {
      'name': _t(_name),
      'sector': _sector,
      'representative': _t(_rep),
      'legal_id': _t(_legal),
      'phone': normalizeHaitiPhone(_phone.text),
      'email': _t(_email),
      'address': _t(_address),
      'commune': _commune,
      'website': _t(_website),
    };
    try {
      if (widget.org == null) {
        await _repo.register(f);
        // El sitio web se guarda aparte (no forma parte del registro inicial).
        final org = await _repo.myOrganization();
        if (org != null && f['website'] != null) {
          await _repo.updateContact(org['id'] as String, phone: f['phone'], email: f['email'], address: f['address'], website: f['website']);
        }
      } else {
        await _repo.updateRegistration(widget.org!['id'] as String, f);
      }
      widget.onDone();
    } on PostgrestException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'No se pudo enviar. Revisa tu conexión.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.org != null;
    String? req(String? v, [int min = 2]) => (v ?? '').trim().length < min ? 'Obligatorio' : null;
    final companyFields = <Widget>[
      const FieldLabel('Nombre de la empresa', required: true),
      TextFormField(controller: _name, decoration: const InputDecoration(prefixIcon: Icon(Icons.business)), validator: req),
      const FieldLabel('Sector', required: true),
      DropdownButtonFormField<String>(
        initialValue: _sector,
        isExpanded: true,
        decoration: const InputDecoration(prefixIcon: Icon(Icons.category_outlined)),
        items: [for (final s in companySectors) DropdownMenuItem(value: s, child: Text(s))],
        onChanged: (v) => setState(() => _sector = v ?? 'Otro'),
      ),
      const FieldLabel('Número de registro / NIF'),
      TextFormField(controller: _legal, decoration: InputDecoration(prefixIcon: Icon(Icons.badge_outlined), hintText: trn('Opcional'))),
      const FieldLabel('Comuna', required: true),
      DropdownButtonFormField<String>(
        initialValue: _commune,
        isExpanded: true,
        decoration: const InputDecoration(prefixIcon: Icon(Icons.location_on_outlined)),
        hint: const Text('Elige la comuna'),
        items: [for (final c in haitiCommunes) DropdownMenuItem(value: c, child: Text(c))],
        onChanged: (v) => setState(() => _commune = v),
        validator: (v) => v == null ? tr('Elige la comuna') : null,
      ),
      const FieldLabel('Dirección'),
      TextFormField(controller: _address, decoration: const InputDecoration(prefixIcon: Icon(Icons.home_work_outlined))),
      const FieldLabel('Sitio web'),
      TextFormField(controller: _website, keyboardType: TextInputType.url, decoration: InputDecoration(prefixIcon: Icon(Icons.language), hintText: trn('Opcional'))),
    ];
    final repFields = <Widget>[
      const FieldLabel('Nombre del representante legal', required: true),
      TextFormField(controller: _rep, decoration: const InputDecoration(prefixIcon: Icon(Icons.person_outline)), validator: (v) => req(v, 3)),
      const FieldLabel('Teléfono de contacto', required: true),
      TextFormField(
        controller: _phone,
        keyboardType: TextInputType.phone,
        decoration: InputDecoration(prefixIcon: Icon(Icons.phone_outlined), prefixText: trn('+509 ')),
        validator: (v) => normalizeHaitiPhone(v ?? '') == null ? tr('Número de 8 dígitos') : null,
      ),
      const FieldLabel('Correo de contacto'),
      TextFormField(
        controller: _email,
        keyboardType: TextInputType.emailAddress,
        decoration: const InputDecoration(prefixIcon: Icon(Icons.mail_outline)),
        validator: (v) => (v ?? '').trim().isEmpty || RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v!.trim()) ? null : tr('Correo no válido'),
      ),
      const SizedBox(height: 16),
      const InfoBanner('Nuestro equipo verificará tu empresa antes de que puedas registrar establecimientos o solicitar misiones. '
          'Después podrás subir los documentos que lo acreditan.'),
    ];

    return Form(
      key: _form,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 28),
        children: [
          ScreenTitle(editing ? 'Corregir registro' : 'Registro empresarial',
              icon: Icons.storefront_outlined,
              subtitle: editing ? 'Actualiza los datos y reenvíalos a verificación.' : 'Registra tu empresa en Haiti Tracking.'),
          if (editing && widget.org!['review_reason'] != null) ...[
            const SizedBox(height: 12),
            InfoBanner('Motivo del rechazo: ${widget.org!['review_reason']}', warning: true),
          ],
          const SizedBox(height: 16),
          StepDots(total: 2, current: _step),
          const SizedBox(height: 6),
          Row(children: [
            Expanded(child: Text('Empresa', style: TextStyle(fontWeight: _step == 1 ? FontWeight.w800 : FontWeight.w500))),
            Text('Representante', style: TextStyle(fontWeight: _step == 2 ? FontWeight.w800 : FontWeight.w500)),
          ]),
          // Ambos pasos permanecen en el árbol para validar el formulario completo al enviar.
          Offstage(offstage: _step != 1, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: companyFields)),
          Offstage(offstage: _step != 2, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: repFields)),
          if (_error != null) ...[const SizedBox(height: 12), Text(_error!, style: const TextStyle(color: HtColors.red))],
          const SizedBox(height: 22),
          if (_step == 1)
            FilledButton.icon(
              onPressed: () {
                if (_name.text.trim().length < 2 || _commune == null) {
                  _form.currentState!.validate();
                  return;
                }
                setState(() => _step = 2);
              },
              icon: const Icon(Icons.arrow_forward),
              label: const Text('Continuar'),
            )
          else ...[
            FilledButton.icon(
              onPressed: _busy ? null : _submit,
              icon: _busy
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.send),
              label: Text(editing ? 'Reenviar a verificación' : 'Enviar para verificación'),
            ),
            const SizedBox(height: 10),
            OutlinedButton(onPressed: () => setState(() => _step = 1), child: const Text('Volver')),
          ],
          if (!editing) ...[
            const SizedBox(height: 14),
            TextButton.icon(
              onPressed: () => showProfileSwitcher(context),
              icon: const Icon(Icons.swap_horiz),
              label: const Text('Cambiar de perfil'),
            ),
          ],
        ],
      ),
    );
  }
}
