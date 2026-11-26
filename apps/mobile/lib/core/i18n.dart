// Traducción de toda la app. El texto fuente está en español dentro del código;
// `Text` (este archivo lo reemplaza al de Flutter) y `tr()` lo buscan en
// translations.dart según el idioma elegido. Lo que no está traducido se muestra en español.
import 'package:flutter/material.dart' as m;
import 'package:flutter/material.dart' hide Text;
import 'package:shared_preferences/shared_preferences.dart';

import 'translations.dart';

class Lang {
  Lang._();

  static const codes = ['es', 'fr', 'ht', 'en'];
  static const _prefKey = 'app_lang';
  static const _oldWelcomeKey = 'welcome_lang';

  /// Idioma actual: es, fr, ht o en.
  static final current = ValueNotifier<String>('es');

  /// true cuando la persona eligió idioma en este teléfono (así no lo pisa el del perfil).
  static bool chosen = false;

  static Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_prefKey) ?? prefs.getString(_oldWelcomeKey);
      if (saved != null && codes.contains(saved)) {
        chosen = true;
        current.value = saved;
        return;
      }
    } catch (_) {}
    final device = WidgetsBinding.instance.platformDispatcher.locale.languageCode;
    if (codes.contains(device)) current.value = device;
  }

  /// Cambia el idioma de toda la app al instante y lo recuerda.
  static Future<void> set(String code) async {
    if (!codes.contains(code)) return;
    chosen = true;
    if (current.value != code) {
      current.value = code;
      _cache.clear();
      _rebuildAll();
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKey, code);
    } catch (_) {}
  }

  /// Usa el idioma guardado en el perfil si en este teléfono aún no se eligió uno.
  static void adoptFromProfile(String? code) {
    if (chosen || code == null || !codes.contains(code)) return;
    set(code);
  }

  /// Locale para los textos propios de Flutter (calendarios, botones del sistema).
  /// Flutter no trae Kreyòl, así que usa francés.
  static Locale get materialLocale => Locale(current.value == 'ht' ? 'fr' : current.value);

  static void _rebuildAll() {
    void mark(Element e) {
      e.markNeedsBuild();
      e.visitChildren(mark);
    }

    WidgetsBinding.instance.rootElement?.visitChildren(mark);
  }
}

final Map<String, String> _cache = {};

final List<(RegExp, String, List<String>)> _templates = [
  for (final e in templateTranslations.entries) (_compile(e.key), e.key, e.value),
]..sort((a, b) => b.$2.replaceAll('{}', '').length.compareTo(a.$2.replaceAll('{}', '').length));

RegExp _compile(String template) {
  final parts = template.split('{}').map(RegExp.escape).toList();
  return RegExp('^${parts.join('(.*?)')}\$', dotAll: true);
}

int get _langIndex => switch (Lang.current.value) { 'fr' => 0, 'ht' => 1, 'en' => 2, _ => -1 };

/// Traduce un texto escrito en español al idioma actual.
String tr(String s) {
  final i = _langIndex;
  if (i < 0 || s.isEmpty) return s;
  final hit = _cache[s];
  if (hit != null) return hit;
  final out = _translate(s, i);
  if (_cache.length > 3000) _cache.clear();
  _cache[s] = out;
  return out;
}

/// Igual que [tr] pero acepta null.
String? trn(String? s) => s == null ? null : tr(s);

String _translate(String s, int i) {
  final exact = translations[s];
  if (exact != null) return exact[i];
  // Mensajes de error con prefijo ("Exception: ...").
  for (final p in const ['Exception: ', 'Bad state: ']) {
    if (s.startsWith(p)) {
      final rest = translations[s.substring(p.length)];
      if (rest != null) return rest[i];
    }
  }
  final trimmed = s.trim();
  if (trimmed != s && trimmed.isNotEmpty) {
    final t = translations[trimmed];
    if (t != null) return s.replaceFirst(trimmed, t[i]);
  }
  for (final (re, _, values) in _templates) {
    final mm = re.firstMatch(s);
    if (mm == null) continue;
    var k = 0;
    return values[i].replaceAllMapped(RegExp(r'\{\}'), (_) {
      final g = k < mm.groupCount ? mm.group(++k) ?? '' : '';
      return translations[g]?[i] ?? g;
    });
  }
  return s;
}

InlineSpan _trSpan(InlineSpan span) {
  if (span is! TextSpan) return span;
  return TextSpan(
    text: span.text == null ? null : tr(span.text!),
    children: span.children?.map(_trSpan).toList(),
    style: span.style,
    recognizer: span.recognizer,
    mouseCursor: span.mouseCursor,
    onEnter: span.onEnter,
    onExit: span.onExit,
    semanticsLabel: span.semanticsLabel,
    locale: span.locale,
    spellOut: span.spellOut,
  );
}

/// Reemplaza al `Text` de Flutter: traduce su contenido al idioma actual.
class Text extends StatelessWidget {
  const Text(
    String this.data, {
    super.key,
    this.style,
    this.strutStyle,
    this.textAlign,
    this.textDirection,
    this.locale,
    this.softWrap,
    this.overflow,
    this.textScaler,
    this.maxLines,
    this.semanticsLabel,
    this.textWidthBasis,
    this.textHeightBehavior,
    this.selectionColor,
  }) : textSpan = null;

  const Text.rich(
    InlineSpan this.textSpan, {
    super.key,
    this.style,
    this.strutStyle,
    this.textAlign,
    this.textDirection,
    this.locale,
    this.softWrap,
    this.overflow,
    this.textScaler,
    this.maxLines,
    this.semanticsLabel,
    this.textWidthBasis,
    this.textHeightBehavior,
    this.selectionColor,
  }) : data = null;

  final String? data;
  final InlineSpan? textSpan;
  final TextStyle? style;
  final StrutStyle? strutStyle;
  final TextAlign? textAlign;
  final TextDirection? textDirection;
  final Locale? locale;
  final bool? softWrap;
  final TextOverflow? overflow;
  final TextScaler? textScaler;
  final int? maxLines;
  final String? semanticsLabel;
  final TextWidthBasis? textWidthBasis;
  final TextHeightBehavior? textHeightBehavior;
  final Color? selectionColor;

  @override
  Widget build(BuildContext context) {
    if (data != null) {
      return m.Text(
        tr(data!),
        style: style,
        strutStyle: strutStyle,
        textAlign: textAlign,
        textDirection: textDirection,
        locale: locale,
        softWrap: softWrap,
        overflow: overflow,
        textScaler: textScaler,
        maxLines: maxLines,
        semanticsLabel: semanticsLabel,
        textWidthBasis: textWidthBasis,
        textHeightBehavior: textHeightBehavior,
        selectionColor: selectionColor,
      );
    }
    return m.Text.rich(
      _trSpan(textSpan!),
      style: style,
      strutStyle: strutStyle,
      textAlign: textAlign,
      textDirection: textDirection,
      locale: locale,
      softWrap: softWrap,
      overflow: overflow,
      textScaler: textScaler,
      maxLines: maxLines,
      semanticsLabel: semanticsLabel,
      textWidthBasis: textWidthBasis,
      textHeightBehavior: textHeightBehavior,
      selectionColor: selectionColor,
    );
  }
}
