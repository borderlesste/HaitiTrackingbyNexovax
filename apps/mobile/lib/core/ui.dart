import 'package:flutter/material.dart' hide Text;
import 'package:haiti_tracking/core/i18n.dart';

import '../features/notifications/notifications_screen.dart';
import 'theme.dart';

/// Marca de la cabecera: pin rojo + "Haiti Tracking / by Nexovax".
class HtBrand extends StatelessWidget {
  const HtBrand({super.key, this.size = 1});
  final double size;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Stack(alignment: const Alignment(0, -.35), children: [
          Icon(Icons.location_on, color: HtColors.red, size: 40 * size),
          Container(
            width: 12 * size,
            height: 12 * size,
            decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
          ),
        ]),
        const SizedBox(width: 6),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Haiti Tracking',
                style: TextStyle(color: Colors.white, fontSize: 20 * size, fontWeight: FontWeight.w700, height: 1.1)),
            Text('by Nexovax', style: TextStyle(color: Colors.white, fontSize: 15 * size, height: 1.1)),
          ],
        ),
      ],
    );
  }
}

/// Cabecera azul marino de todas las pantallas.
class HtAppBar extends StatelessWidget implements PreferredSizeWidget {
  const HtAppBar({super.key, this.onMenu, this.showBell = false, this.onBell, this.showBack});

  final VoidCallback? onMenu;
  final bool showBell;
  final VoidCallback? onBell;

  /// null = automático (si se puede volver atrás).
  final bool? showBack;

  @override
  Size get preferredSize => const Size.fromHeight(72);

  @override
  Widget build(BuildContext context) {
    final canPop = showBack ?? Navigator.of(context).canPop();
    Widget? leading;
    if (canPop) {
      leading = IconButton(
        icon: const Icon(Icons.arrow_back, color: Colors.white, size: 28),
        tooltip: trn('Volver'),
        onPressed: () => Navigator.of(context).maybePop(),
      );
    } else if (onMenu != null) {
      leading = IconButton(
        icon: const Icon(Icons.menu, color: Colors.white, size: 30),
        tooltip: trn('Menú'),
        onPressed: onMenu,
      );
    }
    return AppBar(
      toolbarHeight: 72,
      backgroundColor: HtColors.navy,
      automaticallyImplyLeading: false,
      leading: leading,
      leadingWidth: 60,
      centerTitle: true,
      title: const HtBrand(),
      actions: [
        if (showBell)
          ValueListenableBuilder<int>(
            valueListenable: Notices.unread,
            builder: (context, n, _) => IconButton(
              icon: Badge(
                isLabelVisible: n > 0,
                label: Text(n > 9 ? '9+' : '$n'),
                child: const Icon(Icons.notifications, color: Colors.white, size: 28),
              ),
              tooltip: trn('Notificaciones'),
              onPressed: onBell ?? () => showNotificationsSheet(context),
            ),
          )
        else
          const SizedBox(width: 60),
      ],
    );
  }
}

void showNotificationsSheet(BuildContext context) {
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NotificationsScreen()));
}

/// Cuerpo con esquinas superiores redondeadas sobre la cabecera azul (como en las maquetas).
class HtScaffold extends StatelessWidget {
  const HtScaffold({
    super.key,
    required this.body,
    this.appBar,
    this.bottomNavigationBar,
    this.drawer,
    this.background = HtColors.surface,
    this.scaffoldKey,
  });

  final Key? scaffoldKey;
  final Widget body;
  final PreferredSizeWidget? appBar;
  final Widget? bottomNavigationBar;
  final Widget? drawer;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: scaffoldKey,
      backgroundColor: HtColors.navy,
      appBar: appBar ?? const HtAppBar(),
      drawer: drawer,
      bottomNavigationBar: bottomNavigationBar,
      body: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        child: ColoredBox(color: background, child: body),
      ),
    );
  }
}

/// Título de pantalla con icono: "Mi perfil", "Mis aportes"...
class ScreenTitle extends StatelessWidget {
  const ScreenTitle(this.text, {super.key, required this.icon, this.subtitle, this.iconColor = HtColors.navy});
  final String text;
  final IconData icon;
  final String? subtitle;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: subtitle == null ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 32, color: iconColor),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(text, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: HtColors.text)),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(subtitle!, style: const TextStyle(fontSize: 15, color: HtColors.muted)),
            ],
          ]),
        ),
      ],
    );
  }
}

/// Encabezado de sección: icono + texto, con acción opcional a la derecha.
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, required this.icon, this.action, this.onAction});
  final String text;
  final IconData icon;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Icon(icon, color: HtColors.navy, size: 24),
      const SizedBox(width: 10),
      Expanded(child: Text(text, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: HtColors.text))),
      if (action != null) TextButton(onPressed: onAction, child: Text(action!)),
    ]);
  }
}

/// Tarjeta blanca con borde suave.
class HtCard extends StatelessWidget {
  const HtCard({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.color = Colors.white, this.borderColor});
  final Widget child;
  final EdgeInsets padding;
  final Color color;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor ?? HtColors.border.withValues(alpha: .7)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .04), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      // Material propio para que ListTile e InkWell muestren su efecto al tocar.
      child: Material(type: MaterialType.transparency, child: child),
    );
  }
}

/// Icono dentro de un cuadrado de color suave.
class IconTile extends StatelessWidget {
  const IconTile(this.icon, {super.key, this.color = HtColors.blue, this.background = HtColors.blueSoft, this.size = 52});
  final IconData icon;
  final Color color;
  final Color background;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(size * .25)),
      child: Icon(icon, color: color, size: size * .55),
    );
  }
}

enum ChipTone { review, ok, bad, info }

/// Etiqueta de estado: "En revisión", "Aprobado", "Rechazado"...
class StatusChip extends StatelessWidget {
  const StatusChip(this.label, {super.key, required this.tone});
  final String label;
  final ChipTone tone;

  @override
  Widget build(BuildContext context) {
    final (IconData icon, Color fg, Color bg) = switch (tone) {
      ChipTone.review => (Icons.schedule, const Color(0xFFB07800), HtColors.amberSoft),
      ChipTone.ok => (Icons.check_circle, HtColors.green, HtColors.greenSoft),
      ChipTone.bad => (Icons.cancel, HtColors.red, HtColors.redSoft),
      ChipTone.info => (Icons.info, HtColors.blue, HtColors.blueSoft),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 16, color: fg),
        const SizedBox(width: 5),
        Text(label, style: TextStyle(color: fg, fontWeight: FontWeight.w700, fontSize: 13)),
      ]),
    );
  }
}

/// Aviso con icono (azul informativo o ámbar de advertencia).
class InfoBanner extends StatelessWidget {
  const InfoBanner(this.text, {super.key, this.warning = false});
  final String text;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: warning ? HtColors.amberSoft : HtColors.blueSoft,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.info_outline, color: warning ? HtColors.amber : HtColors.blue),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: const TextStyle(fontSize: 14, color: HtColors.text, height: 1.35))),
      ]),
    );
  }
}

/// Gran check verde con destellos (pantallas de éxito).
class SuccessMark extends StatelessWidget {
  const SuccessMark({super.key, this.size = 110});
  final double size;

  @override
  Widget build(BuildContext context) {
    Widget spark(double angle, Color c) => Transform.rotate(
          angle: angle,
          child: Container(width: 4, height: size * .16, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(2))),
        );
    return SizedBox(
      width: size * 1.8,
      height: size * 1.2,
      child: Stack(alignment: Alignment.center, children: [
        Container(
          width: size * 1.1,
          height: size * 1.1,
          decoration: const BoxDecoration(color: HtColors.greenSoft, shape: BoxShape.circle),
        ),
        Container(
          width: size * .85,
          height: size * .85,
          decoration: const BoxDecoration(color: Color(0xFF22B35E), shape: BoxShape.circle),
          child: Icon(Icons.check, color: Colors.white, size: size * .6),
        ),
        Positioned(left: size * .1, top: size * .15, child: spark(-.8, HtColors.blue)),
        Positioned(left: size * 0.0, top: size * .55, child: spark(1.57, HtColors.amber)),
        Positioned(right: size * .1, top: size * .15, child: spark(.8, HtColors.blue)),
        Positioned(right: size * 0.0, top: size * .55, child: spark(1.57, HtColors.amber)),
      ]),
    );
  }
}

/// Fila etiqueta/valor (resúmenes y desgloses).
class KvRow extends StatelessWidget {
  const KvRow(this.label, this.value, {super.key, this.icon, this.valueColor, this.bold = false, this.trailing});
  final String label;
  final String value;
  final IconData? icon;
  final Color? valueColor;
  final bool bold;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(children: [
        if (icon != null) ...[Icon(icon, color: HtColors.navy, size: 22), const SizedBox(width: 12)],
        Expanded(
          child: Text(label,
              style: TextStyle(fontSize: 15, color: HtColors.text, fontWeight: bold ? FontWeight.w700 : FontWeight.w500)),
        ),
        trailing ??
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 190),
              child: Text(value,
                  textAlign: TextAlign.right,
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: valueColor ?? HtColors.text)),
            ),
      ]),
    );
  }
}

/// Logo de MonCash (cuadro rojo).
class MonCashBadge extends StatelessWidget {
  const MonCashBadge({super.key, this.size = 48});
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size * 1.3,
      height: size,
      decoration: BoxDecoration(color: HtColors.moncash, borderRadius: BorderRadius.circular(size * .18)),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.account_balance_wallet_outlined, color: Colors.white, size: size * .38),
        Text('MonCash', style: TextStyle(color: Colors.white, fontSize: size * .2, fontWeight: FontWeight.w700)),
      ]),
    );
  }
}

/// Fila de pasos numerados (1 — 2 — 3 ...). Los pasos < [current] aparecen completados.
class StepDots extends StatelessWidget {
  const StepDots({super.key, required this.total, required this.current});
  final int total;
  final int current;

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      for (var i = 1; i <= total; i++) ...[
        if (i > 1) Expanded(child: Container(height: 2, color: HtColors.border)),
        Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: i < current ? const Color(0xFF22B35E) : (i == current ? HtColors.blue : Colors.white),
            border: Border.all(color: i <= current ? Colors.transparent : HtColors.border, width: 1.5),
          ),
          child: i < current
              ? const Icon(Icons.check, color: Colors.white, size: 20)
              : Text('$i',
                  style: TextStyle(
                      color: i == current ? Colors.white : HtColors.text, fontWeight: FontWeight.w700, fontSize: 15)),
        ),
      ],
    ]);
  }
}

/// Fila de filtros tipo píldora: "Todos (8)", "En revisión (3)"...
class FilterPills extends StatelessWidget {
  const FilterPills({super.key, required this.labels, required this.selected, required this.onSelected});
  final List<String> labels;
  final int selected;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: [
        for (var i = 0; i < labels.length; i++)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(labels[i]),
              selected: i == selected,
              showCheckmark: false,
              onSelected: (_) => onSelected(i),
              selectedColor: HtColors.blue,
              backgroundColor: Colors.white,
              side: BorderSide(color: i == selected ? HtColors.blue : HtColors.border),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              labelStyle: TextStyle(
                color: i == selected ? Colors.white : HtColors.text,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
      ]),
    );
  }
}

/// Teléfono con los dígitos centrales ocultos: +509 •••• 3456.
String maskPhone(String? phone) {
  if (phone == null || phone.isEmpty) return 'Sin número';
  final digits = phone.replaceAll(RegExp(r'\D'), '');
  if (digits.length < 8) return phone;
  final last = digits.substring(digits.length - 4);
  return digits.startsWith('509') ? '+509 •••• $last' : '•••• $last';
}

/// "+50937123456" → "+509 37 12 34 56".
String formatHaitiPhone(String? phone) {
  if (phone == null || phone.isEmpty) return '';
  var d = phone.replaceAll(RegExp(r'\D'), '');
  if (d.startsWith('509')) d = d.substring(3);
  if (d.length != 8) return phone;
  return '+509 ${d.substring(0, 2)} ${d.substring(2, 4)} ${d.substring(4, 6)} ${d.substring(6)}';
}

const _meses = {
  'es': ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'],
  'fr': ['janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin', 'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.'],
  'ht': ['jan', 'fev', 'mas', 'avr', 'me', 'jen', 'jiy', 'out', 'sep', 'okt', 'nov', 'des'],
  'en': ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'],
};

/// "19 nov 2026" (sin depender de los datos de idioma de intl).
String fechaCorta(DateTime d) {
  final l = d.toLocal();
  return '${l.day} ${(_meses[Lang.current.value] ?? _meses['es']!)[l.month - 1]} ${l.year}';
}

/// "19 nov 2026, 10:24".
String fechaHora(DateTime d) {
  final l = d.toLocal();
  return '${fechaCorta(l)}, ${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
}
