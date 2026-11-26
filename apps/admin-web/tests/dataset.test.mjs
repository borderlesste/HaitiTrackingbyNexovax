import assert from "node:assert/strict";
import test from "node:test";

const { toGeoJson, toCsvRows } = await import("../src/lib/dataset.ts");

const row = {
  code: "HT-NXV-000001", name: "Mini Market Belle Vue", category: "Tienda / Mini Market",
  department: "Ouest", commune: "Delmas", commune_code: "HTI-ADM2-1", address_reference: "Delmas 33",
  lat: 18.5466123456, lng: -72.3035123456, accuracy_m: "8.50", approved_at: "2026-11-20T10:00:00Z", updated_at: "2026-11-20T10:00:00Z",
};

test("GeoJSON uses [lng, lat] points and carries license and attribution", () => {
  const g = toGeoJson([row], { license: "CC BY 4.0", attribution: "Nexovax" }, "2026-11-27T00:00:00Z");
  assert.equal(g.type, "FeatureCollection");
  assert.deepEqual(g.features[0].geometry, { type: "Point", coordinates: [-72.3035123, 18.5466123] });
  assert.equal(g.features[0].id, "HT-NXV-000001");
  assert.equal(g.features[0].properties.accuracy_m, 8.5);
  assert.deepEqual(g.metadata, { source: "Haiti Tracking by Nexovax", attribution: "Nexovax", license: "CC BY 4.0",
    generated_at: "2026-11-27T00:00:00Z", count: 1, crs: "EPSG:4326" });
});

test("CSV rows include WKT and no contributor data", () => {
  const [r] = toCsvRows([row], { license: "", attribution: "Nexovax" });
  assert.equal(r.wkt, "POINT(-72.3035123456 18.5466123456)");
  assert.ok(!Object.keys(r).some((k) => /user|author|photo/.test(k)));
});
