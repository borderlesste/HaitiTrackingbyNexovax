import 'package:flutter/material.dart' hide Text;
import 'package:haiti_tracking/core/i18n.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/panel.dart';
import '../../core/profile_context.dart';
import '../../core/theme.dart';
import '../../core/ui.dart';
import 'developer_repo.dart';

/// Texto de las condiciones de uso de la API (versión api-terms-2026-11).
const apiTermsText = '''1. Solo recibirás datos de lugares públicos aprobados: nunca viviendas ni datos personales de colaboradores.
2. Tu clave secreta es personal: guárdala en tu servidor. Nunca la incluyas en una app móvil, en una web pública ni en un repositorio.
3. Cada proyecto tiene una cuota diaria. Al superarla, la API responde con error hasta el día siguiente.
4. No puedes revender los datos en bruto ni usarlos para vigilar personas.
5. Debes citar "Haiti Tracking by Nexovax" como fuente cuando muestres los lugares.
6. Podemos suspender proyectos que incumplan estas condiciones o pongan en riesgo a la comunidad.''';

void showApiTerms(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: const [
          Text('Condiciones de uso de la API', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          SizedBox(height: 12),
          Text(apiTermsText, style: TextStyle(height: 1.5)),
        ]),
      ),
    ),
  );
}

/// Pantalla 25: Registro de desarrollador (identidad y aceptación de condiciones API).
class DeveloperRegisterScreen extends StatefulWidget {
  const DeveloperRegisterScreen({super.key, required this.onDone});
  final VoidCallback onDone;

  @override
  State<DeveloperRegisterScreen> createState() => _DeveloperRegisterScreenState();
}

class _DeveloperRegisterScreenState extends State<DeveloperRegisterScreen> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(
      text: (Supabase.instance.client.auth.currentUser?.userMetadata?['full_name'] as String?) ?? '');
  final _company = TextEditingController();
  final _country = TextEditingController(text: 'Haití');
  final _website = TextEditingController();
  final _use = TextEditingController();
  String _kind = 'Persona';
  bool _terms = false;
  bool _busy = false;
  String? _error;

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    if (!_terms) return setState(() => _error = 'Debes aceptar las condiciones de la API.');
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      String? t(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();
      await DeveloperRepo().register(
        name: _name.text.trim(),
        useCase: _use.text.trim(),
        company: _kind == 'Empresa' ? t(_company) : null,
        country: t(_country),
        website: t(_website),
      );
      widget.onDone();
    } on PostgrestException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'No se pudo registrar. Revisa tu conexión.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _form,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 28),
        children: [
          const ScreenTitle('Registro de desarrollador', icon: Icons.code, subtitle: 'Accede a la API de lugares verificados de Haití.'),
          const SizedBox(height: 16),
          const HtCard(
            color: HtColors.blueSoft,
            borderColor: Colors.transparent,
            child: Row(children: [
              Icon(Icons.api, color: HtColors.blue, size: 36),
              SizedBox(width: 12),
              Expanded(child: Text('Crea proyectos, genera claves y consulta comercios, farmacias, escuelas y más lugares públicos.', style: TextStyle(height: 1.35))),
            ]),
          ),
          const FieldLabel('Desarrollas como', required: true),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'Persona', label: Text('Persona'), icon: Icon(Icons.person_outline)),
              ButtonSegment(value: 'Empresa', label: Text('Empresa'), icon: Icon(Icons.business_outlined)),
            ],
            selected: {_kind},
            onSelectionChanged: (s) => setState(() => _kind = s.first),
          ),
          const FieldLabel('Nombre completo', required: true),
          TextFormField(controller: _name, decoration: const InputDecoration(prefixIcon: Icon(Icons.person_outline)),
              validator: (v) => (v ?? '').trim().length < 2 ? tr('Obligatorio') : null),
          if (_kind == 'Empresa') ...[
            const FieldLabel('Empresa u organización', required: true),
            TextFormField(controller: _company, decoration: const InputDecoration(prefixIcon: Icon(Icons.business_outlined)),
                validator: (v) => _kind == 'Empresa' && (v ?? '').trim().length < 2 ? tr('Obligatorio') : null),
          ],
          const FieldLabel('País'),
          TextFormField(controller: _country, decoration: const InputDecoration(prefixIcon: Icon(Icons.public))),
          const FieldLabel('Sitio web o repositorio'),
          TextFormField(controller: _website, keyboardType: TextInputType.url, decoration: InputDecoration(prefixIcon: Icon(Icons.link), hintText: trn('Opcional'))),
          const FieldLabel('¿Para qué usarás la API?', required: true),
          TextFormField(
            controller: _use,
            maxLines: 3,
            decoration: InputDecoration(hintText: trn('Ej.: mostrar farmacias cercanas en mi app de salud')),
            validator: (v) => (v ?? '').trim().length < 5 ? tr('Describe el uso previsto') : null,
          ),
          const SizedBox(height: 12),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Checkbox(value: _terms, onChanged: (v) => setState(() => _terms = v ?? false)),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Wrap(children: [
                  const Text('Acepto las '),
                  GestureDetector(
                    onTap: () => showApiTerms(context),
                    child: const Text('condiciones de uso de la API', style: TextStyle(color: HtColors.blue, fontWeight: FontWeight.w700)),
                  ),
                  const Text(' y guardaré mis claves solo en mi servidor.'),
                ]),
              ),
            ),
          ]),
          if (_error != null) ...[const SizedBox(height: 8), Text(_error!, style: const TextStyle(color: HtColors.red))],
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: _busy ? null : _submit,
            icon: _busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.check),
            label: const Text('Crear cuenta de desarrollador'),
          ),
          const SizedBox(height: 10),
          TextButton.icon(onPressed: () => showProfileSwitcher(context), icon: const Icon(Icons.swap_horiz), label: const Text('Cambiar de perfil')),
        ],
      ),
    );
  }
}
