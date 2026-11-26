#!/usr/bin/env bash
set -euo pipefail

root=$(cd -- "$(dirname -- "$0")/../.." && pwd)
endpoint=${DOCKER_HOST:-}
if [[ -z "$endpoint" ]]; then endpoint=$(docker context inspect --format '{{.Endpoints.docker.Host}}'); fi
case "$endpoint" in
  unix://*|npipe://*) ;;
  *) echo 'Estas pruebas requieren Docker local' >&2; exit 1 ;;
esac
container=$(docker run --detach --rm --network none \
  -e POSTGRES_HOST_AUTH_METHOD=trust postgis/postgis:17-3.5)
trap 'docker stop "$container" >/dev/null' EXIT

for attempt in $(seq 1 60); do
  if docker exec "$container" bash -c \
    '[[ $(< /proc/1/comm) == postgres ]] && pg_isready -q -U postgres'; then
    break
  fi
  if [[ $attempt -eq 60 ]]; then
    echo 'No inició PostgreSQL de prueba' >&2
    exit 1
  fi
  sleep 1
done

run_sql() {
  docker exec -i "$container" psql -X -U postgres -d haiti_test -v ON_ERROR_STOP=1 -q "$@"
}

docker exec "$container" createdb -U postgres haiti_test

# Los roles, objetos y JWT se simulan localmente. Los permisos por defecto amplios reproducen
# los proyectos Supabase existentes que los tengan habilitados.
run_sql <<'SQL'
do $$ begin create role anon; exception when duplicate_object then null; end $$;
do $$ begin create role authenticated; exception when duplicate_object then null; end $$;
do $$ begin create role service_role bypassrls; exception when duplicate_object then null; end $$;
create schema auth;
create schema extensions;
create schema storage;
create table auth.users (
  id uuid primary key, instance_id uuid, aud text, role text, email text, phone text,
  phone_confirmed_at timestamptz, last_sign_in_at timestamptz, raw_user_meta_data jsonb,
  created_at timestamptz, updated_at timestamptz
);
create table auth.sessions (id uuid primary key, user_id uuid not null references auth.users, created_at timestamptz not null default now());
create table auth.mfa_amr_claims (session_id uuid references auth.sessions, authentication_method text, created_at timestamptz, updated_at timestamptz);
create function auth.jwt() returns jsonb language sql stable as
$$ select coalesce(nullif(current_setting('request.jwt.claims', true), ''), '{}')::jsonb $$;
create function auth.uid() returns uuid language sql stable as
$$ select coalesce(nullif(current_setting('request.jwt.claim.sub', true), ''), auth.jwt() ->> 'sub')::uuid $$;
create table storage.buckets (id text primary key, name text, public boolean, file_size_limit bigint, allowed_mime_types text[]);
create table storage.objects (bucket_id text not null references storage.buckets, name text not null, primary key (bucket_id, name));
create function storage.foldername(text) returns text[] language sql immutable as
$$ select (string_to_array($1, '/'))[1:array_length(string_to_array($1, '/'),1)-1] $$;
alter table storage.objects enable row level security;
grant usage on schema auth, storage to anon, authenticated;
grant select, insert, update, delete on storage.objects to anon, authenticated;
alter default privileges in schema public grant all on tables to anon, authenticated, service_role;
alter default privileges in schema public grant all on sequences to anon, authenticated, service_role;
alter default privileges in schema public grant all on functions to anon, authenticated, service_role;
SQL

for migration in "$root"/supabase/migrations/*.sql; do
  printf 'APLICAR %s\n' "$(basename "$migration")"
  run_sql --single-transaction -f - < "$migration"
done
run_sql < "$root/supabase/seed.sql"

for test_file in "$root"/supabase/tests/*.sql; do
  printf 'PROBAR %s\n' "$(basename "$test_file")"
  if result=$(run_sql < "$test_file" 2>&1); then
    printf 'OK %s\n' "$result"
  elif [[ "$result" == 'ERROR:  RESULTADOS '* && "$result" != *FALLO* && "$result" != *'=ERROR '* ]]; then
    printf '%s\n' "$result"
  else
    printf '%s\n' "$result" >&2
    exit 1
  fi
done

run_sql -Atc "select version(); select 'tablas_public='||count(*) from pg_tables where schemaname='public';"

if [[ $# -eq 1 ]]; then
  run_sql -At -v schemas=public -f - < "$root/supabase/schema_inventory.sql" > "$1"
fi
