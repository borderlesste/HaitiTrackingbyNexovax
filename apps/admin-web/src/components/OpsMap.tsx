"use client";

import dynamic from "next/dynamic";
import { useEffect, useState } from "react";
import PageHead from "@/components/ui/PageHead";
import { MISSION_STATUS_ES, supabase, usd } from "@/lib/supabase";
import { PAP, type Mission } from "@/components/MissionsView";

const Map = dynamic(() => import("@/components/Map"), { ssr: false });

type Place = { id: string; code: string; name: string; category: string; lat: number; lng: number };
type Pending = { id: string; name: string; category: string; status: string; lat: number; lng: number; mission_code: string };

const PENDING = ["SUBMITTED", "AUTO_CHECKED", "HUMAN_REVIEW", "NEEDS_CHANGES"];

export default function OpsMap() {
  const [missions, setMissions] = useState<Mission[]>([]);
  const [places, setPlaces] = useState<Place[]>([]);
  const [pending, setPending] = useState<Pending[]>([]);
  const [show, setShow] = useState({ active: true, inactive: false, places: true, pending: true });
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    Promise.all([
      supabase.from("missions_admin").select("*"),
      supabase.from("places_admin").select("id, code, name, category, lat, lng").limit(5000),
      supabase.from("review_queue").select("id, name, category, status, lat, lng, mission_code").in("status", PENDING).limit(2000),
    ]).then(([m, p, c]) => {
      setError(m.error?.message ?? p.error?.message ?? c.error?.message ?? null);
      setMissions((m.data ?? []) as Mission[]);
      setPlaces((p.data ?? []) as Place[]);
      setPending((c.data ?? []) as Pending[]);
    });
  }, []);

  const ms = missions.filter((m) => (m.status === "ACTIVE" ? show.active : show.inactive && ["DRAFT", "PAUSED", "SCHEDULED"].includes(m.status)));
  const toggle = (k: keyof typeof show) => setShow((s) => ({ ...s, [k]: !s[k] }));

  return (
    <div className="page">
      <PageHead title="Mapa operativo" subtitle="Zonas de misión, cobertura de lugares verificados y aportes en revisión." />
      <div className="toolbar">
        <Check on={show.active} onClick={() => toggle("active")} color="#0d47c2" label={`Misiones activas (${missions.filter((m) => m.status === "ACTIVE").length})`} />
        <Check on={show.inactive} onClick={() => toggle("inactive")} color="#999" label="Borradores y pausadas" />
        <Check on={show.places} onClick={() => toggle("places")} color="#1e9e5a" label={`Lugares verificados (${places.length})`} />
        <Check on={show.pending} onClick={() => toggle("pending")} color="#f59e0b" label={`Aportes en revisión (${pending.length})`} />
      </div>
      {error && <p className="error">{error}</p>}
      <Map
        center={PAP}
        zoom={11}
        height={620}
        circles={ms
          .filter((m) => m.radius_m)
          .map((m) => ({
            lat: m.lat,
            lng: m.lng,
            radius: m.radius_m!,
            color: m.status === "ACTIVE" ? "#0d47c2" : "#999",
            label: `${m.code} · ${m.title} · ${usd(m.individual_reward_usd)} · ${MISSION_STATUS_ES[m.status]} · ${m.approved_count} aprobados`,
          }))}
        points={[
          ...(show.places ? places.map((p) => ({ lat: p.lat, lng: p.lng, color: "#1e9e5a", size: 5, label: `${p.code} · ${p.name} (${p.category})` })) : []),
          ...(show.pending ? pending.map((p) => ({ lat: p.lat, lng: p.lng, color: "#f59e0b", size: 6, label: `${p.name} · ${p.mission_code} · en revisión` })) : []),
          ...ms.map((m) => ({ lat: m.lat, lng: m.lng, color: m.status === "ACTIVE" ? "#0d47c2" : "#999", size: 7, label: `${m.code} · ${m.title}` })),
        ]}
      />
    </div>
  );
}

function Check({ on, onClick, color, label }: { on: boolean; onClick: () => void; color: string; label: string }) {
  return (
    <button className="btn small" onClick={onClick} style={{ opacity: on ? 1 : 0.5 }}>
      <span style={{ display: "inline-block", width: 10, height: 10, borderRadius: 99, background: color, marginRight: 6 }} />
      {label}
    </button>
  );
}
