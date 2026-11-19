# Haiti Tracking by Nexovax

Base geoespacial colaborativa de Haití construida con misiones remuneradas en un mapa.

- `apps/mobile` — app Android (Flutter): colaborador, empresa y desarrollador.
- `apps/admin-web` — panel administrativo privado (Next.js).
- `supabase/` — esquema PostgreSQL + PostGIS, políticas RLS y datos demo.
- `docs/` — especificación del producto y maquetas.

Ver `docs/especificacion/HaitiTracking-Especificacion-MobileFirst-v1.0.md`.

> Los retiros MonCash están desactivados hasta contar con aprobación comercial, legal y bancaria.

## Compilar la app móvil

1. Copia `apps/mobile/env.example.json` a `apps/mobile/env.json` con la URL y la clave publicable de Supabase.
2. Coloca `google-services.json` (Firebase, app `com.nexovax.haititracking`) en `apps/mobile/android/app/`. No se sube al repo.
3. `flutter build apk --release --target-platform android-arm64 --dart-define-from-file=env.json`

Los correos de Supabase (confirmación y recuperación) abren la app con `com.nexovax.haititracking://login-callback`.

## Panel admin

`cd apps/admin-web`, crea `.env.local` a partir de `.env.example` y ejecuta `npm run dev`.
