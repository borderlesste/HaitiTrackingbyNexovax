# Haiti Tracking by Nexovax

Base geoespacial colaborativa de Haití construida con misiones remuneradas en un mapa.

- `apps/mobile` — app Android (Flutter): colaborador, empresa y desarrollador.
- `apps/admin-web` — panel administrativo privado (Next.js).
- `supabase/` — esquema PostgreSQL + PostGIS, políticas RLS y datos demo.
- `docs/` — especificación del producto y maquetas.

Ver `docs/especificacion/HaitiTracking-Especificacion-MobileFirst-v1.0.md`.

> Los retiros MonCash están desactivados hasta contar con aprobación comercial, legal y bancaria.
> Antes de habilitar retiros, valida en preproducción la migración de prueba telefónica, la función `verify-moncash` y la versión móvil que la invoca. Cada solicitud queda en `withdrawal_requests` para pago manual por el equipo.

## Modo invitado, registro y verificación por SMS

- Sin cuenta se puede explorar la app (mapa, misiones, detalle). Hacer misiones, ver recompensas o usar
  los perfiles Empresa / Desarrollador pide crear una cuenta.
- Las cuentas nuevas se crean con teléfono + contraseña **sin código SMS**. Para eso, en Supabase:
  Authentication → Sign In / Providers → Phone, desactiva **Enable phone confirmations**. Mientras siga
  activado, la app muestra el paso del código como antes.
- Para MonCash, Auth envía el SMS y la función `verify-moncash` valida el código de teléfono antes de guardar la prueba. El servidor exige coincidencia con la cuenta y la sesión de Auth. Las verificaciones anteriores requieren un código nuevo para autorizar retiros.
- Con autoconfirmación, Supabase puede cambiar el número de inicio de sesión de inmediato. La app envía un SMS adicional para probar el control de ese número antes de habilitarlo para MonCash.
- El proveedor SMS (Twilio o Vonage) se configura en la misma pantalla de Phone.
- Las cuentas antiguas con correo siguen entrando con su correo.

## Compilar la app móvil

1. Copia `apps/mobile/env.example.json` a `apps/mobile/env.json` con la URL y la clave publicable de Supabase.
2. Coloca `google-services.json` (Firebase, app `com.nexovax.haititracking`) en `apps/mobile/android/app/`. No se sube al repo.
3. `flutter build apk --release --target-platform android-arm64 --dart-define-from-file=env.json`

Los correos de Supabase (confirmación y recuperación) abren la app con `com.nexovax.haititracking://login-callback`.

## Panel admin

`cd apps/admin-web`, crea `.env.local` a partir de `.env.example` y ejecuta `npm run dev`.

## Pruebas de seguridad locales

Ejecuta `bash supabase/tests/run-local.sh` con Docker local y `node --test supabase/tests/moncash_handler.test.mjs` con Node.js. Para generar un inventario del esquema de prueba, pasa un nombre de archivo, por ejemplo `bash supabase/tests/run-local.sh haiti-local.jsonl`. [Informe de auditoría](docs/auditoria-seguridad-haiti-tracking.md)
