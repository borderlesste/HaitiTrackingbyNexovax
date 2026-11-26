# Haiti Tracking by Nexovax

Base geoespacial colaborativa de Haití construida con misiones remuneradas en un mapa.

- `apps/mobile` — app Android (Flutter): colaborador, empresa y desarrollador.
- `apps/admin-web` — panel administrativo privado (Next.js).
- `supabase/` — esquema PostgreSQL + PostGIS, políticas RLS y datos demo.
- `docs/` — especificación del producto y maquetas.

Ver `docs/especificacion/HaitiTracking-Especificacion-MobileFirst-v1.0.md`.

> Los retiros MonCash están desactivados hasta contar con aprobación comercial, legal y bancaria.
> La app ya permite solicitarlos: se activan con `update platform_settings set value = jsonb_set(value, '{enabled}', 'true') where key = 'withdrawals';`
> y cada solicitud queda en `withdrawal_requests` para pago manual por el equipo.

## Modo invitado, registro y verificación por SMS

- Sin cuenta se puede explorar la app (mapa, misiones, detalle). Hacer misiones, ver recompensas o usar
  los perfiles Empresa / Desarrollador pide crear una cuenta.
- Las cuentas nuevas se crean con teléfono + contraseña **sin código SMS**. Para eso, en Supabase:
  Authentication → Sign In / Providers → Phone, desactiva **Enable phone confirmations**. Mientras siga
  activado, la app muestra el paso del código como antes.
- El SMS solo se pide al colaborador que quiere retirar: la app envía el código, y tras verificarlo llama a
  `confirm_moncash_phone()`, que solo acepta sesiones abiertas con código SMS (amr `otp`) de los últimos 15 min
  y guarda el número en `moncash_verifications`. `request_withdrawal` paga solo a ese número.
- El proveedor SMS (Twilio o Vonage) se configura en la misma pantalla de Phone.
- Las cuentas antiguas con correo siguen entrando con su correo.

## Compilar la app móvil

1. Copia `apps/mobile/env.example.json` a `apps/mobile/env.json` con la URL y la clave publicable de Supabase.
2. Coloca `google-services.json` (Firebase, app `com.nexovax.haititracking`) en `apps/mobile/android/app/`. No se sube al repo.
3. `flutter build apk --release --target-platform android-arm64 --dart-define-from-file=env.json`

Los correos de Supabase (confirmación y recuperación) abren la app con `com.nexovax.haititracking://login-callback`.

## Panel admin

`cd apps/admin-web`, crea `.env.local` a partir de `.env.example` y ejecuta `npm run dev`.
