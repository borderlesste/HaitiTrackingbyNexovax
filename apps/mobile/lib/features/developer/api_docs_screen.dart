import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme.dart';
import '../../core/ui.dart';

const _supabaseUrl = String.fromEnvironment('SUPABASE_URL');

/// Pantalla 29: Documentación API (endpoints y ejemplos).
class ApiDocsScreen extends StatefulWidget {
  const ApiDocsScreen({super.key});

  @override
  State<ApiDocsScreen> createState() => _ApiDocsScreenState();
}

class _ApiDocsScreenState extends State<ApiDocsScreen> {
  int _lang = 0;

  String get _endpoint => '$_supabaseUrl/rest/v1/rpc/api_places_nearby';

  String get _example => switch (_lang) {
        1 => "const res = await fetch('$_endpoint', {\n"
            "  method: 'POST',\n"
            "  headers: {\n"
            "    'apikey': process.env.HT_PUBLISHABLE_KEY,\n"
            "    'Content-Type': 'application/json',\n"
            "  },\n"
            "  body: JSON.stringify({\n"
            "    p_api_key: process.env.HT_SECRET_KEY,\n"
            "    p_lat: 18.5392, p_lng: -72.3350,\n"
            "    p_radius_m: 1000, p_limit: 50,\n"
            "  }),\n"
            "});\n"
            "const places = await res.json();",
        2 => "import os, requests\n\n"
            "r = requests.post(\n"
            "    '$_endpoint',\n"
            "    headers={'apikey': os.environ['HT_PUBLISHABLE_KEY']},\n"
            "    json={\n"
            "        'p_api_key': os.environ['HT_SECRET_KEY'],\n"
            "        'p_lat': 18.5392, 'p_lng': -72.3350,\n"
            "        'p_radius_m': 1000, 'p_limit': 50,\n"
            "    },\n"
            ")\n"
            "places = r.json()",
        _ => "curl -X POST '$_endpoint' \\\n"
            "  -H \"apikey: \$HT_PUBLISHABLE_KEY\" \\\n"
            "  -H 'Content-Type: application/json' \\\n"
            "  -d '{\"p_api_key\": \"'\$HT_SECRET_KEY'\",\n"
            "       \"p_lat\": 18.5392, \"p_lng\": -72.3350,\n"
            "       \"p_radius_m\": 1000, \"p_limit\": 50}'",
      };

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 28),
      children: [
        const ScreenTitle('Documentación API', icon: Icons.menu_book_outlined, subtitle: 'Endpoints, parámetros y ejemplos.'),
        const SizedBox(height: 16),
        HtCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: HtColors.green, borderRadius: BorderRadius.circular(6)),
                child: const Text('POST', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12)),
              ),
              const SizedBox(width: 8),
              const Expanded(child: Text('Lugares cercanos', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
            ]),
            const SizedBox(height: 8),
            const Text('Devuelve lugares públicos aprobados alrededor de un punto, del más cercano al más lejano. '
                'Máximo 10 km de radio y 200 resultados por consulta.'),
            _Code('/rest/v1/rpc/api_places_nearby'),
          ]),
        ),
        const SizedBox(height: 14),
        const SectionTitle('Encabezados', icon: Icons.http),
        const SizedBox(height: 6),
        const HtCard(
          child: Column(children: [
            _Param('apikey', 'texto', 'Clave publicable de Haiti Tracking (la misma para todos).'),
            _Param('Content-Type', 'texto', 'application/json'),
          ]),
        ),
        const SizedBox(height: 14),
        const SectionTitle('Parámetros (cuerpo JSON)', icon: Icons.data_object),
        const SizedBox(height: 6),
        const HtCard(
          child: Column(children: [
            _Param('p_api_key', 'texto *', 'Tu clave secreta htk_… (solo en tu servidor).'),
            _Param('p_lat', 'número *', 'Latitud del punto de búsqueda.'),
            _Param('p_lng', 'número *', 'Longitud del punto de búsqueda.'),
            _Param('p_radius_m', 'número', 'Radio en metros (1000 por defecto, máx. 10000).'),
            _Param('p_limit', 'entero', 'Resultados (50 por defecto, máx. 200).'),
          ]),
        ),
        const SizedBox(height: 14),
        const SectionTitle('Ejemplo de solicitud', icon: Icons.code),
        const SizedBox(height: 6),
        FilterPills(labels: const ['cURL', 'JavaScript', 'Python'], selected: _lang, onSelected: (i) => setState(() => _lang = i)),
        _Code(_example),
        const SizedBox(height: 8),
        const SectionTitle('Respuesta 200', icon: Icons.check_circle_outline),
        _Code('[\n  {\n    "code": "HT-NXV-000001",\n    "name": "Pharmacie Santé",\n    "category": "Farmacia",\n'
            '    "commune": "Delmas",\n    "lat": 18.5466,\n    "lng": -72.3035,\n    "distance_m": 132.4\n  }\n]'),
        const SizedBox(height: 8),
        const SectionTitle('Errores', icon: Icons.error_outline),
        const SizedBox(height: 6),
        const HtCard(
          child: Column(children: [
            _Param('401 / 28000', 'clave', 'Clave inválida o revocada.'),
            _Param('403 / 42501', 'proyecto', 'Proyecto suspendido.'),
            _Param('400 / 53400', 'cuota', 'Cuota diaria superada; se reinicia a medianoche.'),
          ]),
        ),
        const SizedBox(height: 14),
        const InfoBanner(
          'Buenas prácticas: guarda la clave secreta en variables de entorno de tu servidor, nunca en una app móvil o web pública. '
          'Si una clave se expone, rótala desde Credenciales. Cita "Haiti Tracking by Nexovax" como fuente.',
          warning: true,
        ),
      ],
    );
  }
}

class _Code extends StatelessWidget {
  const _Code(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.fromLTRB(12, 6, 4, 12),
      decoration: BoxDecoration(color: const Color(0xFF101828), borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
        IconButton(
          visualDensity: VisualDensity.compact,
          tooltip: 'Copiar',
          icon: const Icon(Icons.copy, color: Colors.white54, size: 18),
          onPressed: () {
            Clipboard.setData(ClipboardData(text: text));
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copiado')));
          },
        ),
        SizedBox(
          width: double.infinity,
          child: SelectableText(text, style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: Color(0xFFB6F5C9), height: 1.4)),
        ),
      ]),
    );
  }
}

class _Param extends StatelessWidget {
  const _Param(this.name, this.type, this.text);
  final String name;
  final String type;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: 120,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w700, color: HtColors.blue)),
            Text(type, style: const TextStyle(fontSize: 12, color: HtColors.muted)),
          ]),
        ),
        Expanded(child: Text(text)),
      ]),
    );
  }
}
