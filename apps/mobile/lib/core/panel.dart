import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'theme.dart';
import 'ui.dart';

/// Piezas comunes de los paneles Empresa y Desarrollador.

/// Estado de revisión (PENDING/APPROVED/REJECTED) → etiqueta.
Widget reviewChip(String? status) => switch (status) {
      'APPROVED' => const StatusChip('Aprobado', tone: ChipTone.ok),
      'REJECTED' => const StatusChip('Rechazado', tone: ChipTone.bad),
      'ACTIVE' => const StatusChip('Activo', tone: ChipTone.ok),
      'SUSPENDED' => const StatusChip('Suspendido', tone: ChipTone.bad),
      _ => const StatusChip('En revisión', tone: ChipTone.review),
    };

/// Tarjeta de cifra: icono, valor grande y etiqueta.
class StatTile extends StatelessWidget {
  const StatTile({super.key, required this.icon, required this.value, required this.label, this.color = HtColors.blue, this.onTap});
  final IconData icon;
  final String value;
  final String label;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return HtCard(
      padding: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            IconTile(icon, color: color, background: color.withValues(alpha: .1), size: 40),
            const SizedBox(height: 10),
            Text(value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: HtColors.text)),
            Text(label, style: const TextStyle(fontSize: 13, color: HtColors.muted)),
          ]),
        ),
      ),
    );
  }
}

/// Acceso rápido: icono + texto en una tarjeta.
class QuickAction extends StatelessWidget {
  const QuickAction({super.key, required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return HtCard(
      padding: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
          child: Column(children: [
            Icon(icon, color: HtColors.blue, size: 28),
            const SizedBox(height: 6),
            Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          ]),
        ),
      ),
    );
  }
}

/// Fila de ajustes dentro de una tarjeta.
class SettingRow extends StatelessWidget {
  const SettingRow({super.key, required this.icon, required this.title, this.subtitle, this.trailing, this.onTap, this.last = false, this.color = HtColors.navy});
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool last;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      ListTile(
        leading: Icon(icon, color: color),
        title: Text(title, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15.5, color: color == HtColors.red ? HtColors.red : null)),
        subtitle: subtitle == null ? null : Text(subtitle!),
        trailing: trailing ?? (onTap == null ? null : const Icon(Icons.chevron_right)),
        onTap: onTap,
      ),
      if (!last) const Divider(height: 1, indent: 16, endIndent: 16),
    ]);
  }
}

/// Mensaje centrado para listas vacías.
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, required this.text, this.action});
  final IconData icon;
  final String title;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        IconTile(icon, size: 72),
        const SizedBox(height: 14),
        Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        Text(text, textAlign: TextAlign.center, style: const TextStyle(color: HtColors.muted, height: 1.4)),
        if (action != null) ...[const SizedBox(height: 18), action!],
      ]),
    );
  }
}

/// Etiqueta de campo con asterisco opcional.
class FieldLabel extends StatelessWidget {
  const FieldLabel(this.text, {super.key, this.required = false});
  final String text;
  final bool required;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6, top: 12),
        child: Text.rich(TextSpan(
          text: text,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: HtColors.text),
          children: [if (required) const TextSpan(text: ' *', style: TextStyle(color: HtColors.red))],
        )),
      );
}

/// Pantalla secundaria con la cabecera de la marca y un título.
class PanelPage extends StatelessWidget {
  const PanelPage({super.key, required this.title, required this.icon, required this.children, this.subtitle, this.bottom, this.onRefresh});
  final String title;
  final IconData icon;
  final String? subtitle;
  final List<Widget> children;
  final Widget? bottom;
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context) {
    final list = ListView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 28),
      physics: const AlwaysScrollableScrollPhysics(),
      children: [ScreenTitle(title, icon: icon, subtitle: subtitle), const SizedBox(height: 16), ...children],
    );
    return HtScaffold(
      body: onRefresh == null ? list : RefreshIndicator(onRefresh: onRefresh!, child: list),
      bottomNavigationBar: bottom == null ? null : SafeArea(child: Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 12), child: bottom)),
    );
  }
}

/// Barra horizontal de progreso con texto.
class ProgressLine extends StatelessWidget {
  const ProgressLine({super.key, required this.value, required this.total, this.label = 'Progreso'});
  final int value;
  final int total;
  final String label;

  @override
  Widget build(BuildContext context) {
    final ratio = total <= 0 ? 0.0 : (value / total).clamp(0.0, 1.0);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: Text('$label: $value de $total', style: const TextStyle(fontWeight: FontWeight.w600))),
        Text('${(ratio * 100).round()} %', style: const TextStyle(fontWeight: FontWeight.w700)),
      ]),
      const SizedBox(height: 8),
      ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: LinearProgressIndicator(value: ratio, minHeight: 10, backgroundColor: HtColors.border, color: HtColors.blue),
      ),
    ]);
  }
}

/// Gráfico de barras sencillo (sin dependencias) para consumo diario.
class MiniBars extends StatelessWidget {
  const MiniBars({super.key, required this.values, required this.labels, this.height = 120, this.color = HtColors.blue});
  final List<int> values;
  final List<String> labels;
  final double height;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final max = values.fold<int>(0, (a, b) => b > a ? b : a);
    return SizedBox(
      height: height + 34,
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        for (var i = 0; i < values.length; i++)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                if (values[i] > 0)
                  Text('${values[i]}', style: const TextStyle(fontSize: 9, color: HtColors.muted), maxLines: 1),
                Container(
                  height: max == 0 ? 2 : (values[i] / max * height).clamp(2, height).toDouble(),
                  decoration: BoxDecoration(color: values[i] == 0 ? HtColors.border : color, borderRadius: BorderRadius.circular(4)),
                ),
                const SizedBox(height: 4),
                Text(labels[i], style: const TextStyle(fontSize: 10, color: HtColors.muted), maxLines: 1),
              ]),
            ),
          ),
      ]),
    );
  }
}

void snack(BuildContext context, String text) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

/// Ayuda y soporte: envía una consulta al equipo (tabla support_tickets del panel admin).
void showSupportSheet(BuildContext context, {required String audience}) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _SupportForm(audience: audience),
  );
}

class _SupportForm extends StatefulWidget {
  const _SupportForm({required this.audience});
  final String audience;

  @override
  State<_SupportForm> createState() => _SupportFormState();
}

class _SupportFormState extends State<_SupportForm> {
  final _subject = TextEditingController();
  final _message = TextEditingController();
  String _kind = 'QUESTION';
  bool _busy = false;
  String? _error;

  Future<void> _send() async {
    if (_subject.text.trim().length < 3 || _message.text.trim().length < 5) {
      return setState(() => _error = 'Escribe un asunto y describe tu consulta.');
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final db = Supabase.instance.client;
      await db.from('support_tickets').insert({
        'user_id': db.auth.currentUser!.id,
        // Tabla de soporte del panel admin (20261126100000_panel_admin.sql).
        'category': _kind == 'CLAIM' ? 'COMPLAINT' : (widget.audience.startsWith('Empresa') ? 'COMPANY' : 'API'),
        'subject': '[${widget.audience}${_kind == 'INCIDENT' ? ' · incidencia' : ''}] ${_subject.text.trim()}',
        'message': _message.text.trim(),
      });
      if (!mounted) return;
      Navigator.pop(context);
      snack(context, 'Consulta enviada. Te responderemos en la app.');
    } catch (_) {
      setState(() => _error = 'No se pudo enviar. Inténtalo de nuevo.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Row(children: [
            Icon(Icons.support_agent, color: HtColors.blue, size: 30),
            SizedBox(width: 10),
            Text('Ayuda y soporte', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          ]),
          const SizedBox(height: 12),
          FilterPills(
            labels: const ['Consulta', 'Incidencia', 'Reclamación'],
            selected: ['QUESTION', 'INCIDENT', 'CLAIM'].indexOf(_kind),
            onSelected: (i) => setState(() => _kind = ['QUESTION', 'INCIDENT', 'CLAIM'][i]),
          ),
          const SizedBox(height: 12),
          TextField(controller: _subject, maxLength: 100, decoration: const InputDecoration(labelText: 'Asunto')),
          TextField(controller: _message, maxLines: 4, maxLength: 2000, decoration: const InputDecoration(labelText: 'Describe tu consulta')),
          if (_error != null) Text(_error!, style: const TextStyle(color: HtColors.red)),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _busy ? null : _send,
            icon: const Icon(Icons.send),
            label: const Text('Enviar al equipo'),
          ),
        ]),
      ),
    );
  }
}
