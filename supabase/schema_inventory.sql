-- PostgreSQL 15+. Usar en una instancia local o copia autorizada, mediante un servicio psql configurado por separado.
-- psql -X -q -d service=haiti_local -v schemas=public -f supabase/schema_inventory.sql -o haiti-local.jsonl
-- Repetir con el mismo alcance en la copia alojada y comparar: git diff --no-index -- haiti-local.jsonl haiti-copia.jsonl
-- Si ya hay un pg_dump --schema-only, inspeccionar el DDL y usar exclusivamente una restauración desechable de confianza.
-- Comparar instancias de la misma versión mayor. Una copia sin propietarios o ACL oculta diferencias de permisos.
-- El resultado contiene nombres y estado de controles. Las definiciones, cuerpos y ACL salen como huellas SHA-256.
-- Para explicar un total combinado, agregar explícitamente esquemas administrados a ambas exportaciones.
-- Quedan fuera las filas de aplicación y los buckets, las membresías de roles, el historial de migraciones y la configuración de plataforma.
\set ON_ERROR_STOP on
\pset format unaligned
\pset tuples_only on
\encoding UTF8
\if :{?schemas}
\else
\set schemas public
\endif

begin read only;
set local search_path = pg_catalog;
set local TimeZone = 'UTC';
set local DateStyle = 'ISO, YMD';

with requested as (
  select distinct btrim(schema_name) as schema_name
  from unnest(string_to_array(:'schemas', ',')) as input(schema_name)
  where btrim(schema_name) <> ''
), namespaces as (
  select n.* from pg_namespace n join requested r on r.schema_name = n.nspname
), relations as (
  select c.*, n.nspname::text as schema_name
  from pg_class c join namespaces n on n.oid = c.relnamespace
  where c.relkind in ('r', 'p', 'f', 'v', 'm', 'S')
), inventory(kind, schema_name, object_name, flags, definition) as (
  select 'schema', r.schema_name, '', jsonb_build_object('present', n.oid is not null),
         jsonb_build_array(pg_get_userbyid(n.nspowner), array(select x::text from unnest(n.nspacl) x order by x::text collate "C"))
  from requested r left join namespaces n on n.nspname = r.schema_name

  union all
  select case r.relkind when 'r' then 'table' when 'p' then 'partitioned_table' when 'f' then 'foreign_table'
           when 'v' then 'view' when 'm' then 'materialized_view' else 'sequence' end,
         r.schema_name, quote_ident(r.relname),
         jsonb_build_object('rls', r.relrowsecurity, 'force_rls', r.relforcerowsecurity,
                            'security_invoker', 'security_invoker=true' = any(coalesce(r.reloptions, array[]::text[]))),
         jsonb_build_array(pg_get_userbyid(r.relowner), r.relpersistence,
           array(select x::text from unnest(r.relacl) x order by x::text collate "C"),
           array(select x from unnest(r.reloptions) x order by x collate "C"),
           case when r.relkind in ('v', 'm') then pg_get_viewdef(r.oid) end,
           case when r.relkind = 'p' then pg_get_partkeydef(r.oid) end,
           pg_get_expr(r.relpartbound, r.oid),
           array(select format('%I.%I', n.nspname, p.relname)
                 from pg_inherits i join pg_class p on p.oid = i.inhparent
                 join pg_namespace n on n.oid = p.relnamespace
                 where i.inhrelid = r.oid order by i.inhseqno))
  from relations r

  union all
  select 'column', r.schema_name, format('%I.%I', r.relname, a.attname),
         jsonb_build_object('type', format_type(a.atttypid, a.atttypmod), 'not_null', a.attnotnull),
         jsonb_build_array(row_number() over (partition by r.oid order by a.attnum), a.attidentity, a.attgenerated,
           case when co.oid is not null then format('%I.%I', cn.nspname, co.collname) end,
           pg_get_expr(d.adbin, d.adrelid),
           array(select x::text from unnest(a.attacl) x order by x::text collate "C"))
  from relations r join pg_attribute a on a.attrelid = r.oid
  left join pg_attrdef d on d.adrelid = r.oid and d.adnum = a.attnum
  left join pg_collation co on co.oid = a.attcollation
  left join pg_namespace cn on cn.oid = co.collnamespace
  where a.attnum > 0 and not a.attisdropped and r.relkind <> 'S'

  union all
  select 'sequence_options', r.schema_name, quote_ident(r.relname), '{}'::jsonb,
         jsonb_build_array(format_type(s.seqtypid, null), s.seqstart, s.seqincrement, s.seqmax, s.seqmin, s.seqcache, s.seqcycle)
  from relations r join pg_sequence s on s.seqrelid = r.oid

  union all
  select 'constraint', n.nspname, format('%s.%I', coalesce(quote_ident(r.relname), quote_ident(t.typname)), c.conname),
         jsonb_build_object('type', c.contype, 'validated', c.convalidated),
         jsonb_build_array(pg_get_constraintdef(c.oid), c.condeferrable, c.condeferred)
  from pg_constraint c join namespaces n on n.oid = c.connamespace
  left join pg_class r on r.oid = c.conrelid left join pg_type t on t.oid = c.contypid
  where c.conrelid <> 0 or c.contypid <> 0

  union all
  select 'index', r.schema_name, quote_ident(c.relname),
         jsonb_build_object('valid', i.indisvalid, 'ready', i.indisready, 'unique', i.indisunique),
         jsonb_build_array(pg_get_indexdef(i.indexrelid), i.indisclustered, i.indisreplident)
  from relations r join pg_index i on i.indrelid = r.oid join pg_class c on c.oid = i.indexrelid

  union all
  select 'policy', r.schema_name, format('%I.%I', r.relname, p.polname),
         jsonb_build_object('command', p.polcmd, 'permissive', p.polpermissive),
         jsonb_build_array(pg_get_expr(p.polqual, r.oid), pg_get_expr(p.polwithcheck, r.oid),
           array(select role_name from (select case when x = 0 then 'PUBLIC' else pg_get_userbyid(x)::text end as role_name
                                        from unnest(p.polroles) x) roles order by role_name collate "C"))
  from relations r join pg_policy p on p.polrelid = r.oid

  union all
  select 'trigger', r.schema_name, format('%I.%I', r.relname, t.tgname),
         jsonb_build_object('enabled', t.tgenabled), jsonb_build_array(pg_get_triggerdef(t.oid))
  from relations r join pg_trigger t on t.tgrelid = r.oid where not t.tgisinternal

  union all
  select 'routine', n.nspname, format('%I(%s)', p.proname, pg_get_function_identity_arguments(p.oid)),
         jsonb_build_object('security_definer', p.prosecdef, 'kind', p.prokind),
         jsonb_build_array(pg_get_userbyid(p.proowner), pg_get_functiondef(p.oid),
           array(select x::text from unnest(p.proacl) x order by x::text collate "C"))
  from pg_proc p join namespaces n on n.oid = p.pronamespace where p.prokind <> 'a'

  union all
  select 'enum', n.nspname, quote_ident(t.typname), '{}'::jsonb,
         jsonb_build_array(pg_get_userbyid(t.typowner),
           array(select e.enumlabel from pg_enum e where e.enumtypid = t.oid order by e.enumsortorder),
           array(select x::text from unnest(t.typacl) x order by x::text collate "C"))
  from pg_type t join namespaces n on n.oid = t.typnamespace where t.typtype = 'e'

  union all
  select 'default_acl', coalesce(n.nspname::text, ''),
         format('%I/%s', pg_get_userbyid(a.defaclrole), a.defaclobjtype), '{}'::jsonb,
         jsonb_build_array(array(select x::text from unnest(a.defaclacl) x order by x::text collate "C"))
  from pg_default_acl a left join namespaces n on n.oid = a.defaclnamespace
  where a.defaclnamespace = 0 or n.oid is not null
)
select jsonb_build_object('kind', kind, 'schema', schema_name, 'name', object_name, 'flags', flags,
         'sha256', encode(sha256(convert_to(definition::text, 'UTF8')), 'hex'))
from inventory
order by schema_name collate "C", kind collate "C", object_name collate "C";

commit;
