import 'package:supabase_flutter/supabase_flutter.dart';

/// Comunas ofrecidas en el registro y en el perfil.
const haitiCommunes = [
  'Puerto Príncipe',
  'Delmas',
  'Pétion-Ville',
  'Carrefour',
  'Tabarre',
  'Croix-des-Bouquets',
  'Cité Soleil',
  'Kenscoff',
  'Gressier',
  'Léogâne',
  'Cap-Haïtien',
  'Gonaïves',
  'Saint-Marc',
  'Les Cayes',
  'Jacmel',
  'Jérémie',
  'Hinche',
  'Port-de-Paix',
  'Fort-Liberté',
  'Miragoâne',
  'Otra',
];

/// Los 10 departamentos de Haití.
const haitiDepartments = [
  'Ouest',
  'Artibonite',
  'Centre',
  'Grand\'Anse',
  'Nippes',
  'Nord',
  'Nord-Est',
  'Nord-Ouest',
  'Sud',
  'Sud-Est',
];

/// Departamento de cada comuna de la lista (para completarlo solo).
const communeDepartment = {
  'Puerto Príncipe': 'Ouest',
  'Delmas': 'Ouest',
  'Pétion-Ville': 'Ouest',
  'Carrefour': 'Ouest',
  'Tabarre': 'Ouest',
  'Croix-des-Bouquets': 'Ouest',
  'Cité Soleil': 'Ouest',
  'Kenscoff': 'Ouest',
  'Gressier': 'Ouest',
  'Léogâne': 'Ouest',
  'Cap-Haïtien': 'Nord',
  'Gonaïves': 'Artibonite',
  'Saint-Marc': 'Artibonite',
  'Les Cayes': 'Sud',
  'Jacmel': 'Sud-Est',
  'Jérémie': 'Grand\'Anse',
  'Hinche': 'Centre',
  'Port-de-Paix': 'Nord-Ouest',
  'Fort-Liberté': 'Nord-Est',
  'Miragoâne': 'Nippes',
};

/// Edad cumplida a hoy.
int ageFrom(DateTime birth) {
  final now = DateTime.now();
  var age = now.year - birth.year;
  if (now.month < birth.month || (now.month == birth.month && now.day < birth.day)) age--;
  return age;
}

const collaboratorTypes = [
  'Colaborador independiente',
  'Estudiante',
  'Comerciante',
  'Chofer / mototaxista',
  'Otro',
];

const languageNames = {
  'ht': 'Criollo haitiano / Kreyòl',
  'fr': 'Francés / Français',
  'es': 'Español',
  'en': 'Inglés / English',
};

/// "37123456" o "+509 37 12 34 56" → "+50937123456". Devuelve null si no es un número haitiano de 8 dígitos.
String? normalizeHaitiPhone(String input) {
  var d = input.replaceAll(RegExp(r'\D'), '');
  if (d.startsWith('509') && d.length == 11) d = d.substring(3);
  if (d.length != 8) return null;
  return '+509$d';
}

class MyProfile {
  MyProfile(this.row);
  final Map<String, dynamic> row;

  String get fullName => (row['full_name'] as String?) ?? '';
  String get firstName {
    final f = (row['first_name'] as String?) ?? '';
    if (f.isNotEmpty) return f;
    return fullName.split(' ').first;
  }

  String? get phone => row['phone'] as String?;
  String? get commune => row['commune'] as String?;
  String? get department => row['department'] as String?;
  String? get birthDate => row['birth_date'] as String?;
  String? get collaboratorType => row['collaborator_type'] as String?;
  String get language => (row['preferred_language'] as String?) ?? 'ht';
  bool get verified => (row['verified'] as bool?) ?? false;
  bool get phoneVerified => (row['phone_verified'] as bool?) ?? false;
}

Future<MyProfile> loadMyProfile() async {
  final db = Supabase.instance.client;
  final uid = db.auth.currentUser!.id;
  final row = await db.from('profiles').select().eq('id', uid).single();
  final authPhone = db.auth.currentUser?.phone;
  final moncash = await loadMoncashPhone();
  return MyProfile({
    ...row,
    // Verificado = confirmado con código SMS para retirar (no basta con registrarse).
    'phone_verified': moncash != null,
    if (moncash != null) 'moncash_phone': moncash,
    if ((row['phone'] as String?) == null && authPhone != null && authPhone.isNotEmpty) 'phone': '+$authPhone',
  });
}

Future<void> updateMyProfile(Map<String, dynamic> values) async {
  final db = Supabase.instance.client;
  await db.from('profiles').update(values).eq('id', db.auth.currentUser!.id);
}

/// Número MonCash verificado por SMS (formato +509...), o null si falta verificarlo.
/// Solo cuenta si sigue siendo el número de la cuenta.
Future<String?> loadMoncashPhone() async {
  final db = Supabase.instance.client;
  final user = db.auth.currentUser;
  if (user == null) return null;
  try {
    final row = await db.from('moncash_verifications').select('phone').eq('user_id', user.id).maybeSingle();
    final phone = row?['phone'] as String?;
    final authPhone = (user.phone ?? '').isEmpty ? null : (user.phone!.startsWith('+') ? user.phone : '+${user.phone}');
    return phone != null && phone == authPhone ? phone : null;
  } catch (_) {
    return null;
  }
}
