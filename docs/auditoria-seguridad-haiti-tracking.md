# Auditoría de seguridad de Haiti Tracking

**Fecha:** 26 de noviembre de 2026  
**Alcance:** rama local `main` de Haiti Tracking by Nexovax, base del análisis `1d734a7`  
**Estado:** endurecimiento local verificado. La certificación del entorno alojado sigue pendiente.

La revisión cubrió Next.js, Flutter, las migraciones de Supabase, las pruebas SQL, la configuración versionada y el historial Git disponible. El proyecto Supabase indicado tiene 62 tablas. La cadena versionada recrea 26 tablas en `public` y configura un bucket privado de evidencias. Queda pendiente conciliar ambos inventarios. RD Marketplace quedó fuera del alcance.

Los clientes web y móvil llaman a Supabase con credenciales publicables. PostgREST, RLS, Storage y las funciones PostgreSQL autorizan el acceso a los datos. Supabase Auth gestiona las contraseñas con bcrypt y emite los JWT. La revisión tomó como referencia los controles de autorización, autenticación, configuración, validación y auditoría de OWASP Top 10 2025 y ASVS 5.0.0. [OWASP Top 10](https://top10.owasp.org/2025/) · [OWASP ASVS](https://asvs.owasp.org/) · [Contraseñas en Supabase Auth](https://supabase.com/docs/guides/auth/password-security)

## 1. Hallazgos y correcciones

| Riesgo | Hallazgo y ubicación | Corrección |
| --- | --- | --- |
| Alto | El segundo factor se comprobaba en `AuthGate.tsx`. Las políticas y RPC administrativas aceptaban el rol con AAL1. | `has_role()` exige `aal2` para administración y moderación. `is_panel_staff()` consulta la fila de la propia cuenta para iniciar el MFA. El panel comprueba los roles con el JWT activo y limita las vistas exclusivas de administración. |
| Alto, condicionado a permisos por defecto amplios | La política de `organizations` comprobaba pertenencia. Un permiso de tabla podía permitir cambios a columnas de aprobación. La concesión por columnas de `developer_api_keys` podía coexistir con una de tabla que incluía los hashes. | La migración revoca esos permisos amplios y concede explícitamente las columnas legítimas. También limita escrituras directas de perfiles, aportes, interacciones de empresa y soporte. |
| Alto | `contribution_draft.dart` compartía la cola offline entre cuentas. La sincronización podía asociar GPS, texto y fotos a otra cuenta del dispositivo. | La cola se vincula a una cuenta. La app verifica el propietario al enviar, incluye su identidad en la inserción y RLS exige que coincida con la sesión. La app descarta el estado de interfaz al cambiar de cuenta. Los borradores históricos sin propietario siguen guardados localmente y se excluyen de la lista y de la sincronización. |
| Alto | `check_duplicates()` ejecutaba con privilegios del propietario y podía devolver nombre, categoría y distancia de aportes ajenos pendientes. Storage permitía a moderadores leer documentos de identidad corporativos. | La búsqueda respeta RLS, exige sesión y admite un radio máximo de 250 m. Los moderadores AAL2 pueden leer evidencia asociada a un aporte. La carpeta de documentos corporativos se excluye de ese acceso. El bucket sigue privado y restringe tamaño a 10 MiB y MIME declarado a JPEG, PNG y PDF. |
| Alto | Las escrituras directas de aportes y retiros podían omitir las transiciones controladas y la bitácora. El retiro comprobaba la idempotencia antes de adquirir el bloqueo. | Las transiciones pasan por sus RPC. El retiro serializa por usuario antes de resolver un reintento. Las entradas de auditoría nuevas omiten contenidos de soporte, motivos en texto libre, referencias y valores íntegros de configuración. |
| Medio | `is_restricted()` exponía el estado de otras cuentas. El catálogo de misiones incluía presupuestos internos. | Las restricciones respetan RLS. Presupuestos y vistas de gestión requieren personal con AAL2. El catálogo conserva sus campos operativos y recompensas anunciadas. |
| Medio | El alta de proyectos y perfiles de desarrollador aceptaba consentimiento nulo. Las operaciones de claves podían solaparse. | El consentimiento debe ser verdadero. Emisión y rotación bloquean la fila de proyecto. La rotación exige que la clave previa siga activa. |
| Medio | Los CSV del panel podían interpretar texto como fórmulas. Faltaba una CSP estricta para scripts. | El exportador neutraliza prefijos de fórmula y conserva los valores numéricos. Next.js aplica CSP con nonce por respuesta, HSTS y protección contra marcos. El nonce requiere renderizado dinámico. |
| Medio | La recuperación móvil mostraba errores que distinguían estados de cuenta. Las subidas de evidencia carecían de un límite común. | Se unificaron los mensajes de autenticación y recuperación, se vinculó el flujo SMS a su sesión y se validó el tamaño de archivos. Android deshabilita copia de seguridad y tráfico en claro. Los reportes de errores móviles omiten mensajes de excepción. |

Las definiciones de acceso y permisos están en las dos migraciones nuevas. Se ajustaron dos migraciones históricas para restaurar desde cero. Una instala `pg_trgm` antes de usarlo. La otra corrige el estado inválido `PENDING` de los aportes de campañas. [MFA](../supabase/migrations/20261126190822_staff_requires_aal2.sql) · [Mínimo privilegio](../supabase/migrations/20261126190855_api_least_privilege.sql) · [Migración de aportes](../supabase/migrations/20261119000003_aportes.sql) · [Migración de campañas](../supabase/migrations/20261126000020_paneles_empresa_desarrollador.sql)

Las correcciones de clientes abarcan acceso, CSV y cabeceras en el panel y alta, recuperación, sesiones, borradores, soporte y archivos en Flutter. Soporte de Empresa y Desarrollador ahora envía la columna `category`. [Acceso web](../apps/admin-web/src/components/AuthGate.tsx) · [Cliente y CSV](../apps/admin-web/src/lib/supabase.ts) · [CSP](../apps/admin-web/src/proxy.ts) · [Borradores](../apps/mobile/lib/features/contributions/contribution_draft.dart) · [Envío de aportes](../apps/mobile/lib/features/contributions/contribution_service.dart) · [Recuperación](../apps/mobile/lib/features/auth/recover_password_screen.dart) · [Evidencia](../apps/mobile/lib/core/evidence_upload.dart)

## 2. Matriz de acceso

| Sesión | Permisos comprobados |
| --- | --- |
| Anónima | Catálogo público de misiones y lugares. Sin acceso a aportes pendientes, presupuestos internos ni consulta de elegibilidad al panel. |
| Autenticada | Acceso a datos propios. Empresa y desarrollador conservan su ámbito de pertenencia y propiedad. |
| Personal AAL1 | Acceso de su propia cuenta y consulta de elegibilidad para iniciar MFA. Operaciones y lecturas privilegiadas bloqueadas. |
| Moderador AAL2 | Moderación, evidencia de aportes y operaciones de soporte autorizadas. Sin acceso a asignación de roles ni documentos corporativos ajenos. |
| Administrador AAL2 | Operaciones administrativas según las RPC y políticas. El procesamiento de retiros pasa por su RPC. |

[Prueba MFA](../supabase/tests/prueba_mfa_admin.sql) · [Prueba de permisos](../supabase/tests/prueba_minimo_privilegio.sql) · [Guía de Supabase MFA](https://supabase.com/docs/guides/auth/auth-mfa)

## 3. Evidencias de verificación

| Verificación | Resultado |
| --- | --- |
| Base limpia con permisos por defecto amplios | 14 migraciones y 6 suites SQL con datos sintéticos en PostgreSQL 17.5 con PostGIS 3.5.2. La misma cadena pasó en PGlite 0.6.0 con PostGIS. Se cubrieron MFA, mínimo privilegio, aportes, moderación y Empresa/Desarrollador. La moderación publicó 5 lugares y produjo 6 asientos por USD 2,25. Los cambios de aprobación y las lecturas de registros ajenos quedaron bloqueados. |
| Concurrencia y respaldo local | Dos transacciones simultáneas con la misma clave de retiro devolvieron la misma solicitud y reservaron el saldo una vez. Una copia lógica con pg_dump y pg_restore recuperó las 26 tablas públicas y pasó nuevamente la prueba de MFA en la base restaurada. |
| Panel web | `npm test` pasó 3/3. `npm run lint` y `npm run build` pasaron. El manejador HTTP compilado devolvió 200 en `/` y `/retiros`. Los nonces fueron distintos por solicitud y coincidían con el HTML. Se observaron HSTS y protección contra marcos. `npm audit --json` devolvió 0 avisos para el lockfile. |
| Flutter | `flutter test --no-pub` pasó 8/8. `flutter analyze --no-pub --no-fatal-infos` terminó con 60 avisos informativos. OSV devolvió 0 coincidencias para 137 paquetes Pub bloqueados. La compilación debug arm64 de la primera ronda y su manifiesto combinado verificaron los controles Android. El seguimiento compiló una variante debug x86_64 para el emulador con configuración sintética. |
| Android sin red | En un dispositivo virtual limpio, el APK sintético mostró bienvenida, inicio de sesión y recuperación. Las acciones de autenticación permanecieron sin sesión y mostraron el error de conexión. Se registró un ANR de arranque antes de que la app renderizara. También se observó un ANR de un componente del sistema. La causa del primer ANR queda por confirmar en un dispositivo físico. |
| Análisis estático | Semgrep 1.187.0 con p/owasp-top-ten procesó 120 archivos en el panel, Flutter y las migraciones. Reportó 0 coincidencias y 0 errores. La revisión manual cubrió permisos y reglas que requieren contexto de negocio. [Semgrep](https://semgrep.dev/docs/getting-started/quickstart) |
| Secretos | Gitleaks 8.30.1 revisó 24 commits con salida redactada. La única coincidencia histórica correspondía a una clave de preferencias locales. El barrido del código actual devolvió 0 coincidencias. La inspección clasificada confirmó claves Supabase publicables en la configuración local del panel y de móvil, en archivos ignorados por Git. |
| Daybreak | La consulta del repositorio devolvió 0 ejecuciones y 0 hallazgos abiertos visibles. La auditoría descrita aquí se realizó en el repositorio local. |

`bash supabase/tests/run-local.sh` restaura y prueba el esquema con Docker local, en un contenedor aislado. Las suites de aplicaciones se ejecutan desde `apps/admin-web` y `apps/mobile`. [Ejecución SQL local](../supabase/tests/run-local.sh) · [Pruebas web](../apps/admin-web/tests/security.test.mjs) · [Pruebas móviles](../apps/mobile/test/security_test.dart) · [Consulta OSV](https://google.github.io/osv.dev/post-v1-querybatch/)

La prueba de integración de TOTP usó GoTrue v2.197.0, PostgREST v16.1 y PostgreSQL 18 locales. Cargó la política real de perfiles y el RPC de roles junto con la migración MFA. La sesión original AAL1 obtuvo su propio estado de acceso al panel y recibió HTTP 403 al asignar roles. El registro, desafío y verificación TOTP devolvieron HTTP 200 y GoTrue emitió un JWT AAL2. Con ese JWT, la asignación de rol devolvió HTTP 204 y se comprobó el cambio. La sesión original siguió bloqueada. El panel vuelve a verificar los permisos al renovar el token y puede interrumpir un formulario abierto.

### Continuación de la auditoría

GoTrue verificó el mismo número con un código sintético en su API local. La respuesta confirmó la misma cuenta y el mismo número, actualizó phone_confirmed_at y emitió una sesión nueva. El cambio de número se cubrió con un proveedor simulado. La prueba directa de ese caso quedó pendiente por el arranque de GoTrue en Docker/WSL. La entrega de SMS, el gateway Edge y el cambio de número requieren pruebas en preproducción. [Configuración de Edge Functions](https://supabase.com/docs/guides/functions/auth) · [Cambio de teléfono en GoTrue](https://github.com/supabase/auth/blob/v2.197.0/internal/api/user.go#L253-L266)

- MonCash delega la validación del código telefónico a GoTrue a través de una función Edge. Registra una prueba vinculada a la cuenta, al número vigente y a una sesión reciente, sin devolver tokens al cliente. La API pública anterior queda revocada. Las pruebas históricas se conservan y requieren nueva verificación. La autorización fija la prueba para que un cambio posterior de teléfono no impida registrar un pago manual ya enviado. El panel desactiva las acciones de autorización y pago cuando la prueba no está disponible. [Panel de retiros](../apps/admin-web/src/components/WithdrawalsView.tsx) · [Migración](../supabase/migrations/20261126194245_moncash_phone_proof.sql) · [Función Edge](../supabase/functions/verify-moncash/handler.ts) · [Prueba SQL](../supabase/tests/prueba_moncash_phone.sql)
- Las nueve pruebas unitarias del manejador verificaron teléfono vigente, cambio pendiente, errores de sesión o código y aislamiento entre cuentas. Deno verificó los tipos de la función Edge y Gitleaks no detectó coincidencias en su código. Comprobaron que la respuesta contiene solo el resultado y que una sesión temporal distinta se cierra por alcance local. [Prueba del manejador](../supabase/tests/moncash_handler.test.mjs)
- La conciliación cuenta con un inventario SQL de solo lectura que exporta nombres, estado de controles y huellas SHA‑256. Una prueba en PostgreSQL 18 confirmó igualdad tras insertar una fila y detectó cambios en tablas, RLS, políticas y permisos de funciones. La exportación local verificó 26 tablas y 791 entradas del catálogo. La cadena local genera el inventario público con `bash supabase/tests/run-local.sh haiti-local.jsonl`. Para comparar, se necesita el mismo inventario de una copia autorizada o una exportación `pg_dump --schema-only` restaurada en una base desechable, con la misma versión mayor y los mismos esquemas. `git diff --no-index -- haiti-local.jsonl haiti-copia.jsonl` muestra las diferencias. [Inventario SQL](../supabase/schema_inventory.sql)

## 4. Riesgos pendientes

| Prioridad | Riesgo | Verificación o decisión pendiente |
| --- | --- | --- |
| Alta | El despliegue de la prueba telefónica para MonCash requiere validar el gateway y la entrega de SMS en preproducción. Los retiros siguen deshabilitados por defecto y los pagos son manuales. | Mantener los retiros deshabilitados hasta validar el canal con el proveedor. Conciliar las solicitudes históricas antes de registrar o rechazar transferencias antiguas. [Emisión de OTP en Supabase Auth](https://github.com/supabase/auth/blob/v2.197.0/internal/api/verify.go) |
| Alta | La cadena local cubre 26 tablas públicas. Siguen pendientes el catálogo alojado, las migraciones efectivamente aplicadas y la eficacia de respaldos, PITR y restauración. | Conciliar el catálogo de 62 tablas en una copia autorizada y verificar una restauración antes de programar cambios. |
| Alta | El panel conserva la sesión accesible a JavaScript por su acceso directo a Supabase. La CSP reduce la exposición. | Para usar cookies `HttpOnly`, `Secure` y `SameSite`, mover la sesión y las operaciones sensibles web a un backend y añadir control CSRF. |
| Media | La interfaz reduce la enumeración. Respuestas directas y límites de Auth, expiración y uso único de recuperación, configuración SMTP/SMS, CORS y redirección HTTPS dependen del despliegue. | Validar en preproducción. Configurar alertas de autenticación fallida, denegaciones reiteradas y operaciones críticas. Verificar acceso y retención de registros. |
| Media | Storage valida límite de tamaño y MIME declarado. El móvil comprueba las cabeceras de JPEG, PNG y PDF y usa el tipo detectado. Quedan pendientes validar el contenido completo en el servidor, análisis de archivos y comprobar la carga con Storage real. | Probar JPEG, PNG y PDF sintéticos en preproducción. Revisar el acceso legítimo de miembros de empresa a los documentos que no subieron ellos mismos. |
| Media | Solicitudes simultáneas de plan pueden duplicarse. Las reglas de presupuesto y ventanas de aportes requieren aprobación funcional. | Revisar transiciones, concurrencia y conciliación con el responsable comercial. En este checkout los procesos de Stripe, PayPal y Resend carecen de integración versionada. |
| Media | Gradle configura la variante release con el keystore de depuración. | Confirmar certificado de distribución y configurar firma autorizada antes de empaquetar una release. |

## 5. Preparación para un despliegue autorizado

1. Verificar respaldos y restaurar una copia controlada. Comparar el historial aplicado con el esquema restaurado y usar las migraciones como referencia. El archivo setup_completo.sql corresponde a un arranque histórico.
2. Probar el panel junto con las migraciones. Confirmar TOTP para administración y moderación en preproducción, incluida la recuperación si se pierde el segundo factor.
3. Ejercitar recuperación, Storage y retiros con datos sintéticos. Conectar alertas con un destino autorizado y verificar acceso y retención de registros.
4. Registrar evidencia del dominio HTTPS, las políticas del proveedor, la firma Android y la conciliación financiera antes de desplegar.

## 6. Estado final

El esquema versionado exige el segundo factor para los privilegios del panel y restringe los accesos entre cuentas comprobados. Los cambios y pruebas se hicieron en `main` con datos sintéticos. Producción y RD Marketplace quedaron fuera de la ejecución. La certificación alojada y la entrega de SMS en preproducción siguen pendientes.

