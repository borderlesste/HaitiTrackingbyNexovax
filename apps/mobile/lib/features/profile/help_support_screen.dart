import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme.dart';
import '../../core/ui.dart';

enum TicketKind { question, incident, claim, deletion }

const _kindCode = {
  TicketKind.question: 'QUESTION',
  TicketKind.incident: 'INCIDENT',
  TicketKind.claim: 'CLAIM',
  TicketKind.deletion: 'ACCOUNT_DELETION',
};

const _kindLabel = {
  'QUESTION': 'Consulta',
  'INCIDENT': 'Incidencia',
  'CLAIM': 'Reclamación',
  'ACCOUNT_DELETION': 'Eliminar cuenta',
};

const _statusLabel = {
  'OPEN': ('Recibida', ChipTone.review),
  'IN_PROGRESS': ('En curso', ChipTone.info),
  'RESOLVED': ('Resuelta', ChipTone.ok),
  'CLOSED': ('Cerrada', ChipTone.info),
};

const _faq = [
  ('¿Cuándo recibo mi recompensa?',
      'Cuando el equipo aprueba tu aporte (normalmente en 24 a 72 horas). El monto pasa a tu saldo y puedes retirarlo por MonCash cuando los retiros estén activos.'),
  ('¿Por qué rechazaron mi aporte?',
      'Los motivos más comunes son: foto borrosa o sin el frente del lugar, GPS lejos del establecimiento, lugar duplicado o datos incompletos. En el detalle del aporte verás la observación y podrás corregirlo.'),
  ('¿Cómo mejoro la precisión del GPS?',
      'Sal al aire libre, acércate a la entrada, espera unos segundos y toca "Capturar de nuevo". Bajo techos o entre edificios altos la precisión empeora.'),
  ('¿Puedo registrar sin conexión?',
      'Sí. El aporte queda guardado en el teléfono y se envía solo cuando vuelve la señal. Lo verás en "Pendientes de envío".'),
  ('¿Por qué me piden un código SMS para retirar?',
      'Para asegurarnos de que el número MonCash es tuyo. Solo se pide al retirar, no al registrarte.'),
  ('¿Qué lugares no debo registrar?',
      'Viviendas privadas sin autorización, interiores de casas, lugares peligrosos y fotos con personas identificables.'),
];

/// Ayuda y soporte: preguntas frecuentes, consultas, incidencias y reclamaciones.
class HelpSupportScreen extends StatefulWidget {
  const HelpSupportScreen({super.key});

  @override
  State<HelpSupportScreen> createState() => _HelpSupportScreenState();
}

class _HelpSupportScreenState extends State<HelpSupportScreen> {
  List<Map<String, dynamic>>? _tickets;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final db = Supabase.instance.client;
      final rows = await db
          .from('support_tickets')
          .select()
          .eq('user_id', db.auth.currentUser!.id)
          .order('created_at', ascending: false)
          .limit(50);
      if (mounted) setState(() => _tickets = List<Map<String, dynamic>>.from(rows));
    } catch (_) {
      if (mounted) setState(() => _tickets = const []);
    }
  }

  Future<void> _new(TicketKind kind) async {
    final sent = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => NewTicketScreen(kind: kind)));
    if (sent == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final t = _tickets;
    return HtScaffold(
      background: Colors.white,
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
          children: [
            const ScreenTitle('Ayuda y soporte', icon: Icons.support_agent, subtitle: 'Estamos aquí para ayudarte.'),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(child: _Action(Icons.help_outline, 'Consulta', () => _new(TicketKind.question))),
              const SizedBox(width: 10),
              Expanded(child: _Action(Icons.report_problem_outlined, 'Incidencia', () => _new(TicketKind.incident))),
              const SizedBox(width: 10),
              Expanded(child: _Action(Icons.gavel_outlined, 'Reclamación', () => _new(TicketKind.claim))),
            ]),
            const SizedBox(height: 20),
            const SectionTitle('Preguntas frecuentes', icon: Icons.quiz_outlined),
            const SizedBox(height: 6),
            HtCard(
              padding: EdgeInsets.zero,
              child: Column(children: [
                for (final f in _faq)
                  ExpansionTile(
                    title: Text(f.$1, style: const TextStyle(fontWeight: FontWeight.w700)),
                    childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                    shape: const Border(),
                    children: [Text(f.$2, style: const TextStyle(height: 1.4))],
                  ),
              ]),
            ),
            const SizedBox(height: 20),
            const SectionTitle('Mis solicitudes', icon: Icons.inbox_outlined),
            const SizedBox(height: 6),
            if (t == null)
              const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator()))
            else if (t.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text('Aún no has enviado consultas.', textAlign: TextAlign.center, style: TextStyle(color: HtColors.muted)),
              )
            else
              HtCard(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: Column(children: [
                  for (var i = 0; i < t.length; i++) ...[
                    if (i > 0) const Divider(height: 1),
                    _TicketRow(t[i]),
                  ],
                ]),
              ),
          ],
        ),
      ),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action(this.icon, this.label, this.onTap);
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: HtCard(
          color: HtColors.blueSoft,
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
          child: Column(children: [
            Icon(icon, color: HtColors.blue, size: 30),
            const SizedBox(height: 6),
            Text(label, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700)),
          ]),
        ),
      );
}

class _TicketRow extends StatelessWidget {
  const _TicketRow(this.t);
  final Map<String, dynamic> t;

  @override
  Widget build(BuildContext context) {
    final st = _statusLabel[t['status']] ?? ('${t['status']}', ChipTone.info);
    final response = t['response'] as String?;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(t['subject'] as String,
                maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
          StatusChip(st.$1, tone: st.$2),
        ]),
        Text('${_kindLabel[t['kind']] ?? t['kind']} · ${fechaHora(DateTime.parse(t['created_at'] as String))}',
            style: const TextStyle(color: HtColors.muted, fontSize: 13)),
        if (response != null && response.isNotEmpty) ...[
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: HtColors.greenSoft, borderRadius: BorderRadius.circular(10)),
            child: Text('Respuesta: $response'),
          ),
        ],
      ]),
    );
  }
}

/// Formulario para enviar una consulta, incidencia, reclamación o pedir borrar la cuenta.
class NewTicketScreen extends StatefulWidget {
  const NewTicketScreen({super.key, required this.kind, this.contributionId, this.withdrawalId, this.subject});
  final TicketKind kind;
  final String? contributionId;
  final String? withdrawalId;
  final String? subject;

  @override
  State<NewTicketScreen> createState() => _NewTicketScreenState();
}

class _NewTicketScreenState extends State<NewTicketScreen> {
  final _form = GlobalKey<FormState>();
  late final _subject = TextEditingController(text: widget.subject ?? '');
  final _message = TextEditingController();
  late TicketKind _kind = widget.kind;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _subject.dispose();
    _message.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final db = Supabase.instance.client;
      await db.from('support_tickets').insert({
        'user_id': db.auth.currentUser!.id,
        'kind': _kindCode[_kind],
        'subject': _subject.text.trim(),
        'message': _message.text.trim(),
        if (widget.contributionId != null) 'contribution_id': widget.contributionId,
        if (widget.withdrawalId != null) 'withdrawal_id': widget.withdrawalId,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Solicitud enviada. Te responderemos pronto.')));
      Navigator.pop(context, true);
    } on PostgrestException catch (e) {
      setState(() => _error = e.code == '42P01' ? 'El soporte aún no está activo en el servidor.' : e.message);
    } catch (_) {
      setState(() => _error = 'Sin conexión. Inténtalo de nuevo.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final deletion = _kind == TicketKind.deletion;
    return HtScaffold(
      background: Colors.white,
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
          children: [
            ScreenTitle(deletion ? 'Eliminar mi cuenta' : 'Nueva solicitud',
                icon: deletion ? Icons.person_remove_outlined : Icons.edit_note,
                subtitle: deletion
                    ? 'El equipo borrará tus datos personales. Los aportes aprobados quedan en el mapa sin tu nombre.'
                    : 'Cuéntanos qué pasa y te responderemos aquí.'),
            const SizedBox(height: 16),
            if (!deletion) ...[
              FilterPills(
                labels: const ['Consulta', 'Incidencia', 'Reclamación'],
                selected: _kind.index.clamp(0, 2),
                onSelected: (i) => setState(() => _kind = TicketKind.values[i]),
              ),
              const SizedBox(height: 16),
            ],
            TextFormField(
              controller: _subject,
              maxLength: 120,
              decoration: const InputDecoration(labelText: 'Asunto'),
              validator: (v) => (v == null || v.trim().length < 3) ? 'Escribe un asunto' : null,
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _message,
              maxLines: 6,
              maxLength: 2000,
              decoration: InputDecoration(
                labelText: deletion ? 'Motivo (opcional, mínimo 5 letras)' : 'Mensaje',
                alignLabelWithHint: true,
              ),
              validator: (v) => (v == null || v.trim().length < 5) ? 'Escribe al menos 5 letras' : null,
            ),
            if (deletion) ...[
              const SizedBox(height: 8),
              const InfoBanner('Antes de borrar la cuenta, retira tu saldo disponible: el saldo no retirado se pierde.',
                  warning: true),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: HtColors.red)),
            ],
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _busy ? null : _send,
              style: deletion ? FilledButton.styleFrom(backgroundColor: HtColors.red) : null,
              icon: _busy
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Icon(deletion ? Icons.delete_outline : Icons.send),
              label: Text(deletion ? 'Solicitar eliminación' : 'Enviar'),
            ),
          ],
        ),
      ),
    );
  }
}
