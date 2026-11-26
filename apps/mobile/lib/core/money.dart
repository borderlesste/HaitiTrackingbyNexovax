/// Montos en centavos enteros para no usar float en dinero.
int cents(Object? v) {
  if (v == null) return 0;
  final s = v.toString();
  final neg = s.startsWith('-');
  final parts = (neg ? s.substring(1) : s).split('.');
  final whole = int.tryParse(parts[0]) ?? 0;
  final frac = parts.length > 1 ? int.tryParse(parts[1].padRight(2, '0').substring(0, 2)) ?? 0 : 0;
  final c = whole * 100 + frac;
  return neg ? -c : c;
}

String money(int c) => '${c < 0 ? '-' : ''}\$${(c.abs() ~/ 100)}.${(c.abs() % 100).toString().padLeft(2, '0')}';

/// Monto con la moneda: "$2.25 USD".
String usd(int c) => '${money(c)} USD';
