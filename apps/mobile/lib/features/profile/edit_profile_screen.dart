import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/account.dart';
import '../../core/theme.dart';
import '../../core/ui.dart';

/// Editar nombre, comuna, fecha de nacimiento y ocupación. El teléfono se cambia con verificación SMS.
class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key, required this.profile});
  final MyProfile profile;

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _form = GlobalKey<FormState>();
  late final _first = TextEditingController(text: widget.profile.row['first_name'] as String? ?? widget.profile.firstName);
  late final _last = TextEditingController(text: widget.profile.row['last_name'] as String? ?? '');
  late String? _commune = haitiCommunes.contains(widget.profile.commune) ? widget.profile.commune : null;
  late String? _type = collaboratorTypes.contains(widget.profile.collaboratorType) ? widget.profile.collaboratorType : null;
  late DateTime? _birth = widget.profile.birthDate == null ? null : DateTime.tryParse(widget.profile.birthDate!);
  bool _busy = false;

  @override
  void dispose() {
    _first.dispose();
    _last.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final first = _first.text.trim();
      final last = _last.text.trim();
      final full = [first, last].where((s) => s.isNotEmpty).join(' ');
      await updateMyProfile({
        'first_name': first,
        'last_name': last,
        'full_name': full,
        'commune': _commune,
        'collaborator_type': _type,
        'birth_date': _birth == null ? null : DateFormat('yyyy-MM-dd').format(_birth!),
      });
      await Supabase.instance.client.auth
          .updateUser(UserAttributes(data: {'full_name': full, 'first_name': first, 'last_name': last}));
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No se pudo guardar. Inténtalo de nuevo.')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return HtScaffold(
      background: Colors.white,
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
          children: [
            const ScreenTitle('Editar perfil', icon: Icons.edit_outlined),
            const SizedBox(height: 20),
            TextFormField(
              controller: _first,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Nombre(s)', prefixIcon: Icon(Icons.person_outline)),
              validator: (v) => (v == null || v.trim().length < 2) ? 'Escribe tu nombre' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _last,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Apellido(s)', prefixIcon: Icon(Icons.person_outline)),
            ),
            const SizedBox(height: 12),
            InkWell(
              onTap: () async {
                final now = DateTime.now();
                final d = await showDatePicker(
                  context: context,
                  initialDate: _birth ?? DateTime(now.year - 25),
                  firstDate: DateTime(now.year - 100),
                  lastDate: DateTime(now.year - 18, now.month, now.day),
                );
                if (d != null) setState(() => _birth = d);
              },
              child: InputDecorator(
                decoration: const InputDecoration(labelText: 'Fecha de nacimiento', prefixIcon: Icon(Icons.calendar_month_outlined)),
                child: Text(_birth == null ? 'Sin indicar' : DateFormat('dd / MM / yyyy').format(_birth!)),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _commune,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Comuna / Ciudad', prefixIcon: Icon(Icons.location_on_outlined)),
              items: [for (final c in haitiCommunes) DropdownMenuItem(value: c, child: Text(c))],
              onChanged: (v) => setState(() => _commune = v),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _type,
              isExpanded: true,
              decoration: const InputDecoration(labelText: '¿Cómo te identificas?', prefixIcon: Icon(Icons.groups_outlined)),
              items: [for (final c in collaboratorTypes) DropdownMenuItem(value: c, child: Text(c))],
              onChanged: (v) => setState(() => _type = v),
            ),
            const SizedBox(height: 12),
            const InfoBanner('Para cambiar tu número MonCash usa "Mi MonCash" en tu perfil: se verifica con un código SMS.'),
            const SizedBox(height: 22),
            FilledButton.icon(
              onPressed: _busy ? null : _save,
              icon: _busy
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.save_outlined),
              label: const Text('Guardar cambios'),
            ),
            const SizedBox(height: 8),
            Text('Los datos se usan solo para validar tus aportes y pagos.',
                textAlign: TextAlign.center, style: TextStyle(color: HtColors.muted.withValues(alpha: .9), fontSize: 12)),
          ],
        ),
      ),
    );
  }
}
