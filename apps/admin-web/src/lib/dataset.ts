/** Fila que devuelve admin_export_places. */
export type ExportPlace = {
  code: string;
  name: string;
  category: string;
  department: string | null;
  commune: string | null;
  commune_code: string | null;
  address_reference: string | null;
  lat: number;
  lng: number;
  accuracy_m: number | string | null;
  approved_at: string | null;
  updated_at: string;
};

export type DatasetMeta = { license: string; attribution: string };

export const DATASET_META: DatasetMeta = {
  license: "",
  attribution: "Haiti Tracking by Nexovax y sus colaboradores",
};

/** GeoJSON (RFC 7946): puntos en [lng, lat] con propiedades planas, aptas para Content Partners, QGIS u OSM. */
export function toGeoJson(rows: ExportPlace[], meta: DatasetMeta, generatedAt = new Date().toISOString()) {
  return {
    type: "FeatureCollection",
    name: "haiti-tracking-lugares",
    metadata: {
      source: "Haiti Tracking by Nexovax",
      attribution: meta.attribution,
      license: meta.license || null,
      generated_at: generatedAt,
      count: rows.length,
      crs: "EPSG:4326",
    },
    features: rows.map((r) => ({
      type: "Feature",
      id: r.code,
      geometry: { type: "Point", coordinates: [Number(r.lng.toFixed(7)), Number(r.lat.toFixed(7))] },
      properties: {
        code: r.code,
        name: r.name,
        category: r.category,
        department: r.department,
        commune: r.commune,
        commune_code: r.commune_code,
        address_reference: r.address_reference,
        accuracy_m: r.accuracy_m === null ? null : Number(r.accuracy_m),
        approved_at: r.approved_at,
        updated_at: r.updated_at,
        source: "Haiti Tracking by Nexovax",
      },
    })),
  };
}

/** Filas planas para CSV (lat/lng y WKT, que aceptan hojas de cálculo y SIG). */
export function toCsvRows(rows: ExportPlace[], meta: DatasetMeta) {
  return rows.map((r) => ({
    code: r.code,
    name: r.name,
    category: r.category,
    department: r.department,
    commune: r.commune,
    commune_code: r.commune_code,
    address_reference: r.address_reference,
    lat: r.lat,
    lng: r.lng,
    wkt: `POINT(${r.lng} ${r.lat})`,
    accuracy_m: r.accuracy_m === null ? null : Number(r.accuracy_m),
    approved_at: r.approved_at,
    updated_at: r.updated_at,
    source: "Haiti Tracking by Nexovax",
    attribution: meta.attribution,
    license: meta.license,
  }));
}
