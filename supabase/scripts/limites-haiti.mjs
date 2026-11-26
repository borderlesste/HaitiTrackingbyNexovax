#!/usr/bin/env node
// Descarga los límites administrativos de Haití (geoBoundaries, gbOpen) y los carga en public.admin_areas.
//
// Uso (Node 18 o superior, desde la raíz del repo):
//   node supabase/scripts/limites-haiti.mjs            -> escribe supabase/limites/*.sql para pegar en el SQL Editor
//   node supabase/scripts/limites-haiti.mjs --subir    -> carga directa; requiere SUPABASE_URL y SUPABASE_SERVICE_ROLE_KEY
//   Añade --secciones para incluir también las secciones comunales (ADM3) si geoBoundaries las publica.
//
// Requiere la migración 20261127000000_cartografia_base.sql. Volver a ejecutarlo actualiza los mismos registros.

import { mkdir, writeFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const API = "https://www.geoboundaries.org/api/current/gbOpen/HTI";
const args = new Set(process.argv.slice(2));
const levels = [1, 2, ...(args.has("--secciones") ? [3] : [])];
const outDir = join(dirname(fileURLToPath(import.meta.url)), "..", "limites");
const MAX_SQL_BYTES = 900_000;

const round = (c) => (typeof c[0] === "number" ? c.map((v) => Math.round(v * 1e5) / 1e5) : c.map(round));

async function getJson(url) {
  const res = await fetch(url, { redirect: "follow" });
  if (!res.ok) throw new Error(`${res.status} al descargar ${url}`);
  return res.json();
}

async function loadLevel(level) {
  const meta = await getJson(`${API}/ADM${level}/`);
  const url = meta.simplifiedGeometryGeoJSON || meta.gjDownloadURL;
  const geo = await getJson(url);
  const features = geo.features.map((f) => ({
    type: "Feature",
    properties: { shapeID: f.properties.shapeID, shapeName: f.properties.shapeName, shapeISO: f.properties.shapeISO ?? "" },
    geometry: { type: f.geometry.type, coordinates: round(f.geometry.coordinates) },
  }));
  const source = `geoBoundaries gbOpen HTI ADM${level} (${meta.boundarySource ?? "fuente sin indicar"}, ${meta.boundaryYearRepresented ?? meta.sourceDataUpdateDate ?? ""})`;
  const license = meta.boundaryLicense ?? "Ver geoboundaries.org";
  console.log(`ADM${level}: ${features.length} áreas · ${license}`);
  return { level, features, source, license };
}

/** Agrupa features en lotes cuyo JSON no supere el tamaño máximo. */
function batches(features) {
  const out = [];
  let cur = [];
  let size = 0;
  for (const f of features) {
    const s = JSON.stringify(f).length;
    if (cur.length && size + s > MAX_SQL_BYTES) {
      out.push(cur);
      cur = [];
      size = 0;
    }
    cur.push(f);
    size += s;
  }
  if (cur.length) out.push(cur);
  return out;
}

const sqlText = (s) => `'${String(s).replace(/'/g, "''")}'`;

async function writeSql(data) {
  await mkdir(outDir, { recursive: true });
  let n = 0;
  for (const { level, features, source, license } of data) {
    for (const b of batches(features)) {
      n++;
      const json = JSON.stringify(b);
      if (json.includes("$geo$")) throw new Error("Contenido inesperado en el GeoJSON");
      const sql = `-- Límites de Haití ADM${level}, lote ${n}. Pegar en el SQL Editor de Supabase.\n` +
        `select public.import_admin_areas(${level}::smallint, $geo$${json}$geo$::jsonb, ${sqlText(source)}, ${sqlText(license)});\n`;
      await writeFile(join(outDir, `haiti-limites-${String(n).padStart(2, "0")}.sql`), sql);
    }
  }
  n++;
  await writeFile(join(outDir, `haiti-limites-${String(n).padStart(2, "0")}.sql`),
    "-- Último paso: enlaza comunas con su departamento y reasigna los lugares.\nselect public.link_admin_areas();\n");
  console.log(`Listo: ${n} archivos en ${outDir}. Ejecútalos en orden en el SQL Editor.`);
}

async function upload(data) {
  const url = process.env.SUPABASE_URL;
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!url || !key) throw new Error("Define SUPABASE_URL y SUPABASE_SERVICE_ROLE_KEY para usar --subir");
  const rpc = async (fn, body) => {
    const res = await fetch(`${url.replace(/\/$/, "")}/rest/v1/rpc/${fn}`, {
      method: "POST",
      headers: { apikey: key, Authorization: `Bearer ${key}`, "Content-Type": "application/json" },
      body: JSON.stringify(body),
    });
    if (!res.ok) throw new Error(`${fn}: ${res.status} ${await res.text()}`);
    return res.json();
  };
  for (const { level, features, source, license } of data) {
    for (const b of batches(features)) {
      const n = await rpc("import_admin_areas", { p_level: level, p_features: b, p_source: source, p_license: license });
      console.log(`ADM${level}: ${n} áreas guardadas`);
    }
  }
  console.log("Enlace y reasignación:", await rpc("link_admin_areas", {}));
}

const data = [];
for (const level of levels) data.push(await loadLevel(level));
if (args.has("--subir")) await upload(data);
else await writeSql(data);
