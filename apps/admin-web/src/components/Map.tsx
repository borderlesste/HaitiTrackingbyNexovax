"use client";

import "leaflet/dist/leaflet.css";
import { Circle, CircleMarker, MapContainer, Popup, TileLayer, Tooltip, useMapEvents } from "react-leaflet";

export type MapPoint = { lat: number; lng: number; label?: string; color?: string; size?: number; popup?: string };
export type MapCircle = { lat: number; lng: number; radius: number; color?: string; label?: string };

function ClickHandler({ onPick }: { onPick?: (p: { lat: number; lng: number }) => void }) {
  useMapEvents({ click: (e) => onPick?.({ lat: e.latlng.lat, lng: e.latlng.lng }) });
  return null;
}

/** Mapa OpenStreetMap: puntos, círculos (zonas de misión) y selección por clic. */
export default function Map({
  center,
  zoom = 15,
  points = [],
  circle,
  circles = [],
  onPick,
  height = 280,
}: {
  center: { lat: number; lng: number };
  zoom?: number;
  points?: MapPoint[];
  circle?: MapCircle;
  circles?: MapCircle[];
  onPick?: (p: { lat: number; lng: number }) => void;
  height?: number;
}) {
  const allCircles = circle ? [circle, ...circles] : circles;
  return (
    <MapContainer
      key={`${center.lat.toFixed(5)},${center.lng.toFixed(5)}`}
      center={[center.lat, center.lng]}
      zoom={zoom}
      style={{ height, width: "100%", borderRadius: 12, zIndex: 0 }}
    >
      <TileLayer url="https://tile.openstreetmap.org/{z}/{x}/{y}.png" attribution="© OpenStreetMap" />
      {allCircles.map((c, i) => (
        <Circle key={`c${i}`} center={[c.lat, c.lng]} radius={c.radius} pathOptions={{ color: c.color ?? "#0d47c2", weight: 1, fillOpacity: 0.12 }}>
          {c.label && <Tooltip>{c.label}</Tooltip>}
        </Circle>
      ))}
      {points.map((p, i) => (
        <CircleMarker
          key={i}
          center={[p.lat, p.lng]}
          radius={p.size ?? 8}
          pathOptions={{ color: "#fff", weight: 2, fillColor: p.color ?? "#d62839", fillOpacity: 1 }}
        >
          {p.label && <Tooltip>{p.label}</Tooltip>}
          {p.popup && <Popup>{p.popup}</Popup>}
        </CircleMarker>
      ))}
      <ClickHandler onPick={onPick} />
    </MapContainer>
  );
}
