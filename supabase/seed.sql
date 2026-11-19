-- Datos de demostración (inventados). Solo para entornos de desarrollo.
insert into public.missions (code, type, title, description, commune, center, radius_m, required_approved_contributions,
  individual_reward_usd, completion_bonus_usd, max_participants, budget_authorized_usd, requirements, start_at, end_at, status)
values
  ('MIS-DEL-0001', 'BATCH_ZONE', 'Documentar cinco comercios públicos', 'Registra cinco comercios abiertos al público que no estén en el mapa.', 'Delmas',
   extensions.st_setsrid(extensions.st_makepoint(-72.2973, 18.5401), 4326)::extensions.geography, 800, 5, 0.25, 1.00, 30, 75.00,
   'GPS + foto + datos del lugar', now(), now() + interval '30 days', 'ACTIVE'),
  ('MIS-DEL-0002', 'NEW_PLACE', 'Registrar comercio faltante', 'Un comercio público que aún no aparece en el catálogo.', 'Delmas',
   extensions.st_setsrid(extensions.st_makepoint(-72.3050, 18.5470), 4326)::extensions.geography, 500, 1, 0.25, 0, 100, 25.00,
   'GPS + foto + datos del lugar', now(), now() + interval '30 days', 'ACTIVE'),
  ('MIS-PAP-0001', 'PRIORITY_PLACE', 'Zona prioritaria: centro de Port-au-Prince', 'Lugares públicos dentro de la zona prioritaria.', 'Port-au-Prince',
   extensions.st_setsrid(extensions.st_makepoint(-72.3388, 18.5425), 4326)::extensions.geography, 600, 1, 0.50, 0, 50, 25.00,
   'GPS + foto + datos del lugar', now(), now() + interval '30 days', 'ACTIVE'),
  ('MIS-PTV-0001', 'NEW_PLACE', 'Farmacias de Pétion-Ville', 'Registra farmacias abiertas al público.', 'Pétion-Ville',
   extensions.st_setsrid(extensions.st_makepoint(-72.2852, 18.5125), 4326)::extensions.geography, 700, 1, 0.25, 0, 50, 12.50,
   'GPS + foto + datos del lugar', now(), now() + interval '30 days', 'ACTIVE');
