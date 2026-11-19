"use client";

import "leaflet/dist/leaflet.css";
import { Circle, CircleMarker, MapContainer, TileLayer, Tooltip, useMapEvents } from "react-leaflet";

export type MapPoint = { lat: number; lng: number; label?: string; color?: string };

function ClickHandler({ onPick }: { onPick?: (p: { lat: number; lng: number }) => void }) {
  useMapEvents({ click: (e) => onPick?.({ lat: e.latlng.lat, lng: e.latlng.lng }) });
  return null;
}

/** Mapa OpenStreetMap: puntos, un círculo opcional (área de misión) y selección por clic. */
export default function Map({
  center,
  zoom = 15,
  points = [],
  circle,
  onPick,
  height = 280,
}: {
  center: { lat: number; lng: number };
  zoom?: number;
  points?: MapPoint[];
  circle?: { lat: number; lng: number; radius: number };
  onPick?: (p: { lat: number; lng: number }) => void;
  height?: number;
}) {
  return (
    <MapContainer
      key={`${center.lat.toFixed(5)},${center.lng.toFixed(5)}`}
      center={[center.lat, center.lng]}
      zoom={zoom}
      style={{ height, width: "100%", borderRadius: 12 }}
    >
      <TileLayer url="https://tile.openstreetmap.org/{z}/{x}/{y}.png" attribution="© OpenStreetMap" />
      {circle && (
        <Circle center={[circle.lat, circle.lng]} radius={circle.radius} pathOptions={{ color: "#0d47c2", weight: 1 }} />
      )}
      {points.map((p, i) => (
        <CircleMarker
          key={i}
          center={[p.lat, p.lng]}
          radius={8}
          pathOptions={{ color: "#fff", weight: 2, fillColor: p.color ?? "#d62839", fillOpacity: 1 }}
        >
          {p.label && <Tooltip>{p.label}</Tooltip>}
        </CircleMarker>
      ))}
      <ClickHandler onPick={onPick} />
    </MapContainer>
  );
}
