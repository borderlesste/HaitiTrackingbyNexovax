# Límites administrativos de Haití

Generados con `node supabase/scripts/limites-haiti.mjs` desde [geoBoundaries](https://www.geoboundaries.org/) (gbOpen HTI):

| Archivo | Contenido | Licencia |
| --- | --- | --- |
| `haiti-limites-01.sql` | 10 departamentos (ADM1, nivel 1) | ODbL 1.0 |
| `haiti-limites-02.sql` | 140 comunas (ADM3, nivel 2) | CC BY 4.0 |
| `haiti-limites-03.sql` | Enlace comuna → departamento y reasignación de lugares | — |

Ejecutar en orden en el SQL Editor después de la migración `20261127000000_cartografia_base.sql`.
Atribución obligatoria: "Límites administrativos: geoBoundaries (Runfola et al. 2020), con datos de origen indicados en cada registro (`admin_areas.source`)."
