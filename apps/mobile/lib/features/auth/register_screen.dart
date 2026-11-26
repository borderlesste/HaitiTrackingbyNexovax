import 'dart:async';

import 'package:flutter/material.dart' hide Text;
import 'package:haiti_tracking/core/i18n.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/account.dart';
import '../../core/otp_input.dart';
import '../../core/profile_context.dart';
import '../../core/theme.dart';
import '../../core/ui.dart';

/// Registro por pasos: datos básicos → perfil → cuenta creada.
/// La cuenta se crea con teléfono + contraseña, sin código SMS. El paso del código solo aparece si
/// Supabase todavía exige confirmar el teléfono al registrarse. El número se verifica al retirar fondos.
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key, this.profile = AppProfile.collaborator});

  /// Perfil que eligió la persona (colaborador, empresa o desarrollador).
  final AppProfile profile;

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  int _step = 0;
  String _phone = '';
  late AppProfile _profile = widget.profile;

  void _next() => setState(() => _step++);

  Future<bool> _onBack() async {
    // Tras verificar el teléfono la cuenta ya existe: no se vuelve a los pasos anteriores.
    if (_step == 1) {
      setState(() => _step = 0);
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final canGoBack = _step <= 1;
    return PopScope(
      canPop: _step == 0 || _step == 3,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onBack();
      },
      child: HtScaffold(
        background: Colors.white,
        appBar: HtAppBar(showBack: canGoBack),
        body: AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: switch (_step) {
            0 => _BasicDataStep(
                key: const ValueKey(0),
                profile: _profile,
                onProfile: (p) => setState(() => _profile = p),
                onSent: (phone, signedIn) {
                  _phone = phone;
                  setState(() => _step = signedIn ? 2 : 1);
                },
              ),
            1 => _VerifyStep(key: const ValueKey(1), phone: _phone, onVerified: _next),
            2 => _ProfileStep(key: const ValueKey(2), profile: _profile, onDone: _next),
            _ => _CreatedStep(key: const ValueKey(3), profile: _profile),
          },
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Paso 1: datos básicos
// ---------------------------------------------------------------------------
class _BasicDataStep extends StatefulWidget {
  const _BasicDataStep({super.key, required this.profile, required this.onProfile, required this.onSent});
  final AppProfile profile;
  final ValueChanged<AppProfile> onProfile;
  final void Function(String phone, bool signedIn) onSent;

  @override
  State<_BasicDataStep> createState() => _BasicDataStepState();
}

class _BasicDataStepState extends State<_BasicDataStep> {
  final _form = GlobalKey<FormState>();
  final _first = TextEditingController();
  final _last = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _first.dispose();
    _last.dispose();
    _phone.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    final phone = normalizeHaitiPhone(_phone.text)!;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final first = _first.text.trim();
      final last = _last.text.trim();
      final res = await Supabase.instance.client.auth.signUp(
        phone: phone,
        password: _password.text,
        channel: OtpChannel.sms,
        data: {'full_name': '$first $last', 'first_name': first, 'last_name': last},
      );
      if (mounted) widget.onSent(phone, res.session != null);
    } on AuthException catch (e) {
      if (mounted) {
        setState(() => _error = e.code == 'weak_password'
            ? 'Elige una contraseña más segura.'
            : 'No se pudo crear la cuenta. Revisa tus datos o usa la recuperación de contraseña.');
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'Sin conexión. Inténtalo de nuevo.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final collaborator = widget.profile == AppProfile.collaborator;
    return Form(
      key: _form,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
        children: [
          ScreenTitle('Crear una cuenta',
              icon: Icons.person_add_alt,
              subtitle: switch (widget.profile) {
                AppProfile.collaborator => 'Únete como colaborador y comienza a registrar lugares en tu comunidad.',
                AppProfile.company => 'Crea tu cuenta de empresa para gestionar tus establecimientos.',
                AppProfile.developer => 'Crea tu cuenta de desarrollador para usar la API de lugares.',
              }),
          const SizedBox(height: 16),
          const _Label('Quiero ser'),
          FilterPills(
            labels: [for (final p in AppProfile.values) profileInfo[p]!.$2],
            selected: widget.profile.index,
            onSelected: (i) => widget.onProfile(AppProfile.values[i]),
          ),
          const SizedBox(height: 16),
          const _Label('Nombre(s)'),
          TextFormField(
            controller: _first,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(prefixIcon: Icon(Icons.person_outline), hintText: trn('Jean')),
            validator: (v) => (v == null || v.trim().length < 2) ? tr('Escribe tu nombre') : null,
          ),
          const SizedBox(height: 14),
          const _Label('Apellido(s)'),
          TextFormField(
            controller: _last,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(prefixIcon: Icon(Icons.person_outline), hintText: trn('Pierre')),
            validator: (v) => (v == null || v.trim().length < 2) ? tr('Escribe tu apellido') : null,
          ),
          const SizedBox(height: 14),
          _Label(collaborator ? 'Número de teléfono (MonCash)' : 'Número de teléfono'),
          TextFormField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            autofillHints: const [AutofillHints.telephoneNumber],
            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(8)],
            decoration: InputDecoration(
              prefixIcon: Icon(Icons.phone_outlined),
              prefixText: trn('+509 '),
              hintText: trn('37123456'),
              counterText: trn(''),
            ),
            validator: (v) => normalizeHaitiPhone(v ?? '') == null ? tr('Número haitiano de 8 dígitos') : null,
          ),
          const SizedBox(height: 14),
          const _Label('Contraseña'),
          TextFormField(
            controller: _password,
            obscureText: _obscure,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.lock_outline),
              hintText: trn('Mínimo 8 caracteres'),
              suffixIcon: IconButton(
                icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
            validator: (v) => (v == null || v.length < 8) ? tr('Mínimo 8 caracteres') : null,
          ),
          const SizedBox(height: 16),
          InfoBanner(collaborator
              ? 'Con tu número y tu contraseña iniciarás sesión. No hace falta ningún código ahora: '
                  'solo te pediremos verificarlo por SMS cuando quieras retirar tus recompensas por MonCash.'
              : 'Con tu número y tu contraseña iniciarás sesión.'),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: HtColors.red)),
          ],
          const SizedBox(height: 22),
          _ArrowButton(label: 'Continuar', busy: _busy, onPressed: _submit),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Paso 2: código SMS
// ---------------------------------------------------------------------------
class _VerifyStep extends StatefulWidget {
  const _VerifyStep({super.key, required this.phone, required this.onVerified});
  final String phone;
  final VoidCallback onVerified;

  @override
  State<_VerifyStep> createState() => _VerifyStepState();
}

class _VerifyStepState extends State<_VerifyStep> {
  final _code = TextEditingController();
  Timer? _timer;
  int _seconds = 60;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    setState(() => _seconds = 60);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_seconds <= 1) t.cancel();
      if (mounted) setState(() => _seconds--);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _code.dispose();
    super.dispose();
  }

  Future<void> _resend() async {
    try {
      await Supabase.instance.client.auth.resend(type: OtpType.sms, phone: widget.phone);
      _startTimer();
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    }
  }

  Future<void> _verify() async {
    if (_code.text.length != 6) {
      setState(() => _error = 'Escribe los 6 dígitos del código.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await Supabase.instance.client.auth.verifyOTP(type: OtpType.sms, phone: widget.phone, token: _code.text);
      widget.onVerified();
    } on AuthException {
      setState(() => _error = 'Código incorrecto o vencido. Revisa el SMS o pide otro código.');
    } catch (_) {
      setState(() => _error = 'Sin conexión. Inténtalo de nuevo.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mm = (_seconds ~/ 60).toString().padLeft(2, '0');
    final ss = (_seconds % 60).toString().padLeft(2, '0');
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
      children: [
        const ScreenTitle('Verificar tu teléfono',
            icon: Icons.mark_chat_read_outlined,
            subtitle: 'Hemos enviado un código de verificación por SMS al número:'),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(color: HtColors.blueSoft, borderRadius: BorderRadius.circular(14)),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Icon(Icons.phone_in_talk_outlined, color: HtColors.blue),
            const SizedBox(width: 12),
            Text(formatHaitiPhone(widget.phone), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          ]),
        ),
        const SizedBox(height: 24),
        const _Label('Código de verificación'),
        OtpInput(controller: _code, onCompleted: (_) => _verify()),
        const SizedBox(height: 22),
        Center(
          child: _seconds > 0
              ? Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.timer_outlined, size: 20, color: HtColors.text),
                  const SizedBox(width: 8),
                  Text('Reenviar código en $mm:$ss', style: const TextStyle(fontSize: 15)),
                ])
              : TextButton.icon(onPressed: _resend, icon: const Icon(Icons.refresh), label: const Text('Reenviar código')),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: const TextStyle(color: HtColors.red), textAlign: TextAlign.center),
        ],
        const SizedBox(height: 28),
        FilledButton.icon(
          onPressed: _busy ? null : _verify,
          icon: _busy ? const _Spinner() : const Icon(Icons.check),
          label: const Text('Verificar y continuar'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Paso 3: completar perfil
// ---------------------------------------------------------------------------
class _ProfileStep extends StatefulWidget {
  const _ProfileStep({super.key, required this.profile, required this.onDone});
  final AppProfile profile;
  final VoidCallback onDone;

  @override
  State<_ProfileStep> createState() => _ProfileStepState();
}

class _ProfileStepState extends State<_ProfileStep> {
  final _form = GlobalKey<FormState>();
  DateTime? _birth;
  String? _commune;
  String? _department;
  String _language = Lang.current.value;
  String? _type = collaboratorTypes.first;
  bool _terms = false;
  bool _busy = false;
  String? _error;

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _birth ?? DateTime(now.year - 25),
      firstDate: DateTime(now.year - 100),
      lastDate: DateTime(now.year - 18, now.month, now.day),
      helpText: trn('Fecha de nacimiento'),
    );
    if (picked != null) setState(() => _birth = picked);
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    if (_birth == null) return setState(() => _error = 'Indica tu fecha de nacimiento.');
    if (!_terms) return setState(() => _error = 'Debes aceptar los Términos de Uso y la Política de Privacidad.');
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final user = Supabase.instance.client.auth.currentUser!;
      final meta = user.userMetadata ?? const {};
      final collaborator = widget.profile == AppProfile.collaborator;
      await updateMyProfile({
        'first_name': meta['first_name'],
        'last_name': meta['last_name'],
        'full_name': meta['full_name'],
        'phone': user.phone == null || user.phone!.isEmpty ? null : '+${user.phone}',
        'birth_date': DateFormat('yyyy-MM-dd').format(_birth!),
        'commune': _commune,
        'department': _department,
        'preferred_language': _language,
        if (collaborator) 'collaborator_type': _type,
        'terms_accepted_at': DateTime.now().toUtc().toIso8601String(),
      });
      await ProfileContext.set(widget.profile);
      widget.onDone();
    } catch (_) {
      setState(() => _error = 'No se pudo guardar tu perfil. Inténtalo de nuevo.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showLegal(String title) {
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            const Text(
              'Haiti Tracking usa tu nombre, teléfono y ubicación solo para validar tus aportes y pagarte recompensas. '
              'Las fotos deben ser de lugares públicos, sin personas identificables ni interiores de viviendas. '
              'Las recompensas se acreditan solo tras la revisión y aprobación de cada aporte.',
              style: TextStyle(height: 1.4),
            ),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _form,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
        children: [
          const ScreenTitle('Completa tu perfil', icon: Icons.badge_outlined, subtitle: 'Cuéntanos un poco más sobre ti.'),
          const SizedBox(height: 22),
          const _Label('Fecha de nacimiento'),
          InkWell(
            onTap: _pickDate,
            borderRadius: BorderRadius.circular(12),
            child: InputDecorator(
              decoration: const InputDecoration(prefixIcon: Icon(Icons.calendar_month_outlined)),
              child: Text(
                _birth == null
                    ? 'DD / MM / AAAA'
                    : '${DateFormat('dd / MM / yyyy').format(_birth!)}  ·  ${ageFrom(_birth!)} años',
                style: TextStyle(fontSize: 16, color: _birth == null ? HtColors.muted : HtColors.text),
              ),
            ),
          ),
          const SizedBox(height: 14),
          const _Label('Comuna / Ciudad'),
          DropdownButtonFormField<String>(
            initialValue: _commune,
            isExpanded: true,
            decoration: const InputDecoration(prefixIcon: Icon(Icons.location_on_outlined)),
            hint: const Text('Elige tu comuna'),
            items: [for (final c in haitiCommunes) DropdownMenuItem(value: c, child: Text(c))],
            onChanged: (v) => setState(() {
              _commune = v;
              _department = communeDepartment[v] ?? _department;
            }),
            validator: (v) => v == null ? tr('Elige tu comuna') : null,
          ),
          const SizedBox(height: 14),
          const _Label('Departamento'),
          DropdownButtonFormField<String>(
            key: ValueKey(_department),
            initialValue: _department,
            isExpanded: true,
            decoration: const InputDecoration(prefixIcon: Icon(Icons.map_outlined)),
            hint: const Text('Elige tu departamento'),
            items: [for (final d in haitiDepartments) DropdownMenuItem(value: d, child: Text(d))],
            onChanged: (v) => setState(() => _department = v),
            validator: (v) => v == null ? tr('Elige tu departamento') : null,
          ),
          const SizedBox(height: 14),
          const _Label('Idioma preferido'),
          DropdownButtonFormField<String>(
            initialValue: _language,
            isExpanded: true,
            decoration: const InputDecoration(prefixIcon: Icon(Icons.language)),
            items: [for (final e in languageNames.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
            onChanged: (v) {
              setState(() => _language = v ?? 'ht');
              Lang.set(_language);
            },
          ),
          const SizedBox(height: 14),
          if (widget.profile == AppProfile.collaborator) ...[
            const _Label('¿Cómo te identificas?'),
            DropdownButtonFormField<String>(
              initialValue: _type,
              isExpanded: true,
              decoration: const InputDecoration(prefixIcon: Icon(Icons.groups_outlined)),
              items: [for (final c in collaboratorTypes) DropdownMenuItem(value: c, child: Text(c))],
              onChanged: (v) => setState(() => _type = v),
            ),
          ],
          const SizedBox(height: 16),
          const Divider(),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Checkbox(value: _terms, onChanged: (v) => setState(() => _terms = v ?? false)),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Wrap(children: [
                  const Text('Acepto los ', style: TextStyle(fontSize: 15)),
                  _Link('Términos de Uso', () => _showLegal('Términos de Uso')),
                  const Text(' y la ', style: TextStyle(fontSize: 15)),
                  _Link('Política de Privacidad', () => _showLegal('Política de Privacidad')),
                  const Text(' de Haiti Tracking by Nexovax. *', style: TextStyle(fontSize: 15)),
                ]),
              ),
            ),
          ]),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!, style: const TextStyle(color: HtColors.red)),
          ],
          const SizedBox(height: 22),
          FilledButton.icon(
            onPressed: _busy ? null : _submit,
            icon: _busy ? const _Spinner() : const Icon(Icons.person_add_alt),
            label: const Text('Crear mi cuenta'),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Paso 4: cuenta creada
// ---------------------------------------------------------------------------
class _CreatedStep extends StatelessWidget {
  const _CreatedStep({super.key, required this.profile});
  final AppProfile profile;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
      children: [
        const Center(child: SuccessMark()),
        const SizedBox(height: 16),
        const Text('¡Cuenta creada!',
            textAlign: TextAlign.center, style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, color: HtColors.text)),
        const SizedBox(height: 10),
        Text(
          switch (profile) {
            AppProfile.collaborator => 'Tu registro ha sido completado con éxito. Ya puedes comenzar a realizar aportes.',
            AppProfile.company => 'Tu cuenta de empresa está lista. Ya puedes registrar tus establecimientos.',
            AppProfile.developer => 'Tu cuenta de desarrollador está lista. Ya puedes crear tu primer proyecto.',
          },
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 16, color: HtColors.muted, height: 1.4),
        ),
        const SizedBox(height: 24),
        if (profile == AppProfile.collaborator) const HtCard(
          color: HtColors.blueSoft,
          child: Row(children: [
            Icon(Icons.savings_outlined, color: HtColors.amber, size: 36),
            SizedBox(width: 14),
            Expanded(
              child: Text('Registra lugares, completa misiones y gana recompensas con MonCash.',
                  style: TextStyle(fontSize: 15, height: 1.35)),
            ),
          ]),
        ),
        const SizedBox(height: 28),
        FilledButton.icon(
          // AuthGate ya muestra la app debajo: basta con volver a la raíz.
          onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst),
          icon: const Icon(Icons.login),
          label: const Text('Comenzar'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text.rich(TextSpan(
          text: text,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: HtColors.text),
          children: const [TextSpan(text: ' *', style: TextStyle(color: HtColors.red))],
        )),
      );
}

class _Link extends StatelessWidget {
  const _Link(this.text, this.onTap);
  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Text(text, style: const TextStyle(fontSize: 15, color: HtColors.blue, fontWeight: FontWeight.w600)),
      );
}

class _Spinner extends StatelessWidget {
  const _Spinner();

  @override
  Widget build(BuildContext context) =>
      const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white));
}

class _ArrowButton extends StatelessWidget {
  const _ArrowButton({required this.label, required this.onPressed, this.busy = false});
  final String label;
  final VoidCallback onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: busy ? null : onPressed,
      child: busy
          ? const _Spinner()
          : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text(label),
              const SizedBox(width: 10),
              const Icon(Icons.arrow_forward),
            ]),
    );
  }
}
