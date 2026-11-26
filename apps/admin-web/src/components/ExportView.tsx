"use client";

import { useEffect, useMemo, useState, type FormEvent } from "react";
import { Download, Save } from "lucide-react";
import PageHead from "@/components/ui/PageHead";
import { DATASET_META, toCsvRows, toGeoJson, type DatasetMeta, type ExportPlace } from "@/lib/dataset";
import { downloadCsv, getSetting, saveSetting, supabase } from "@/lib/supabase";

type Area = { id: number; level: number; name: string; parent_id: number | null };

function downloadJson(filename: string, data: unknown) {
  const url = URL.createObjectURL(new Blob([JSON.stringify(data)], { type: "application/geo+json" }));
  const a = document.createElement("a");
  a.href = url;
  a.download = filename;
  a.click();
  URL.revokeObjectURL(url);
}

export default function ExportView() {
  const [areas, setAreas] = useState<Area[]>([]);
  const [categories, setCategories] = useState<string[]>([]);
  const [department, setDepartment] = useState("");
  const [commune, setCommune] = useState("");
  const [category, setCategory] = useState("");
  const [meta, setMeta] = useState<DatasetMeta>(DATASET_META);
  const [busy, setBusy] = useState(false);
  const [msg, setMsg] = useState<string | null>(null);
  const [err, setErr] = useState<string | null>(null);

  useEffect(() => {
    supabase
      .from("admin_areas_list")
      .select("id, level, name, parent_id")
      .in("level", [1, 2])
      .order("name")
      .then(({ data }) => setAreas((data ?? []) as Area[]));
    supabase
      .from("places")
      .select("category")
      .eq("visibility", "PUBLIC")
      .limit(5000)
      .then(({ data }) => setCategories([...new Set((data ?? []).map((r) => r.category as string))].sort()));
    getSetting<DatasetMeta>("dataset_export", DATASET_META).then(setMeta);
  }, []);

  const departments = areas.filter((a) => a.level === 1);
  const communes = useMemo(
    () => areas.filter((a) => a.level === 2 && (!department || a.parent_id === Number(department))),
    [areas, department],
  );

  async function fetchRows(): Promise<ExportPlace[] | null> {
    setBusy(true);
    setErr(null);
    setMsg(null);
    const { data, error } = await supabase.rpc("admin_export_places", {
      p_department_id: department ? Number(department) : null,
      p_commune_id: commune ? Number(commune) : null,
      p_category: category || null,
    });
    setBusy(false);
    if (error) {
      setErr(error.message);
      return null;
    }
    const rows = (data ?? []) as ExportPlace[];
    if (rows.length === 0) setMsg("No hay lugares públicos aprobados con esos filtros.");
    return rows.length ? rows : null;
  }

  const stamp = () => new Date().toISOString().slice(0, 10);

  async function exportGeoJson() {
    const rows = await fetchRows();
    if (!rows) return;
    downloadJson(`haiti-tracking-lugares-${stamp()}.geojson`, toGeoJson(rows, meta));
    setMsg(`${rows.length} lugares exportados en GeoJSON.`);
  }

  async function exportCsv() {
    const rows = await fetchRows();
    if (!rows) return;
    downloadCsv(`haiti-tracking-lugares-${stamp()}.csv`, toCsvRows(rows, meta));
    setMsg(`${rows.length} lugares exportados en CSV.`);
  }

  async function saveMeta(e: FormEvent) {
    e.preventDefault();
    const error = await saveSetting("dataset_export", meta);
    setErr(error);
    setMsg(error ? null : "Licencia y atribución guardadas.");
  }

  return (
    <div className="page">
      <PageHead
        title="Exportar datos"
        subtitle="Descarga los lugares públicos aprobados para entregarlos a socios cartográficos (Google Maps Content Partners, OpenStreetMap, instituciones). Cada exportación queda en Auditoría."
      />
      {msg && <p className="ok">{msg}</p>}
      {err && <p className="error">{err}</p>}

      <div className="grid2" style={{ margin: 0 }}>
        <div className="card form">
          <h3 style={{ marginTop: 0 }}>Filtros</h3>
          <label>
            Departamento
            <select value={department} onChange={(e) => { setDepartment(e.target.value); setCommune(""); }}>
              <option value="">Todo Haití</option>
              {departments.map((d) => <option key={d.id} value={d.id}>{d.name}</option>)}
            </select>
          </label>
          <label>
            Comuna
            <select value={commune} onChange={(e) => setCommune(e.target.value)}>
              <option value="">Todas</option>
              {communes.map((c) => <option key={c.id} value={c.id}>{c.name}</option>)}
            </select>
          </label>
          <label>
            Categoría
            <select value={category} onChange={(e) => setCategory(e.target.value)}>
              <option value="">Todas</option>
              {categories.map((c) => <option key={c} value={c}>{c}</option>)}
            </select>
          </label>
          {areas.length === 0 && (
            <p className="muted small">
              Aún no hay límites administrativos cargados. Ejecuta <span className="mono">supabase/scripts/limites-haiti.mjs</span> para filtrar por departamento o comuna.
            </p>
          )}
          <div className="row gap" style={{ marginTop: 8 }}>
            <button className="btn primary" disabled={busy} onClick={exportGeoJson}><Download size={14} /> GeoJSON</button>
            <button className="btn" disabled={busy} onClick={exportCsv}><Download size={14} /> CSV</button>
          </div>
          <p className="muted small">
            Solo incluye lugares con visibilidad pública. No incluye datos de colaboradores, fotos ni direcciones residenciales.
          </p>
        </div>

        <form className="card form" onSubmit={saveMeta}>
          <h3 style={{ marginTop: 0 }}>Licencia y atribución</h3>
          <label>
            Atribución
            <input value={meta.attribution} onChange={(e) => setMeta({ ...meta, attribution: e.target.value })} />
          </label>
          <label>
            Licencia del dataset
            <input
              placeholder="Ej.: CC BY 4.0, ODbL 1.0 o acuerdo con el socio"
              value={meta.license}
              onChange={(e) => setMeta({ ...meta, license: e.target.value })}
            />
          </label>
          <p className="muted small">
            Se escribe en cada archivo. Para OpenStreetMap los datos deben ser compatibles con ODbL; para Google Maps Content Partners rige el acuerdo que firmes con Google.
          </p>
          <button className="btn" type="submit"><Save size={14} /> Guardar</button>
        </form>
      </div>
    </div>
  );
}
