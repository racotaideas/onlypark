-- ============================================================================
-- 028 — INSTEAD OF triggers para que los portales IWOL puedan ESCRIBIR
--
-- Las vistas shim (026) son solo-lectura por default. Este archivo:
--   a) Reemplaza las vistas para que expongan campos "cajero" como TEXT
--      (email/nombre), permitiendo que el IWOL siga mandando strings.
--   b) Agrega INSTEAD OF triggers para INSERT/UPDATE en:
--        - tickets   (entrada de vehículo, cobro de salida)
--        - bitacora  (log de operaciones)
--        - cortes    (apertura/cierre de turno)
--   c) Los triggers corren SECURITY DEFINER para bypassear RLS y persisten
--      en las tablas nuevas (sesiones, log_evento, cortes_caja).
-- ============================================================================

-- ── Helper: resuelve perfil_id desde un texto (email, username o nombre) ─────
CREATE OR REPLACE FUNCTION public.fn_perfil_por_texto(p_ref text)
RETURNS uuid LANGUAGE sql STABLE
SECURITY DEFINER SET search_path = public, pg_temp
AS $$
  SELECT perfil_id FROM perfiles_usuario
  WHERE activo AND (
        lower(email::text) = lower(p_ref)
     OR lower(split_part(email::text, '@', 1)) = lower(p_ref)
     OR lower(nombre_completo) = lower(p_ref)
  )
  LIMIT 1;
$$;

GRANT EXECUTE ON FUNCTION public.fn_perfil_por_texto(text) TO anon, authenticated, service_role;


-- ── Reemplazar vista tickets: cajero_* como TEXT ────────────────────────────
DROP VIEW IF EXISTS public.tickets CASCADE;
CREATE VIEW public.tickets AS
SELECT
  s.folio_entrada           AS folio,
  s.folio_salida,
  ts.codigo                 AS tipo,
  es.codigo                 AS estatus,
  s.entrada_at              AS hora_entrada_at,
  to_char(s.entrada_at AT TIME ZONE 'America/Mexico_City','HH24:MI') AS hora_entrada,
  s.salida_at               AS hora_salida_at,
  to_char(s.salida_at AT TIME ZONE 'America/Mexico_City','HH24:MI') AS hora_salida,
  s.importe_total           AS importe,
  s.importe_calculado,
  s.importe_descuento,
  s.duracion_minutos        AS minutos_estancia,
  s.duracion_minutos        AS horas_cobradas,
  s.estacionamiento_id      AS plaza_id,
  s.tipo_sesion_id,
  s.estado_sesion_id,
  s.placa_id,
  s.vehiculo_id,
  s.cliente_id,
  s.pension_id,
  ce.email::text            AS cajero_entrada,
  cs.email::text            AS cajero_salida,
  COALESCE(cs.email::text, ce.email::text) AS cajero,
  s.corte_caja_entrada_id   AS turno_entrada,
  s.corte_caja_salida_id    AS turno_id,
  s.camara_entrada_id,
  s.camara_salida_id,
  s.entrada_at::date        AS fecha_op,
  s.requiere_cobro,
  s.created_at,
  s.updated_at,
  s.sesion_id               AS ticket_id,
  s.folio_local,
  NULL::integer             AS empleado_id,
  NULL::numeric             AS tarifa
FROM public.sesiones s
LEFT JOIN public.cat_tipo_sesion   ts ON ts.tipo_sesion_id   = s.tipo_sesion_id
LEFT JOIN public.cat_estado_sesion es ON es.estado_sesion_id = s.estado_sesion_id
LEFT JOIN public.perfiles_usuario  ce ON ce.perfil_id = s.cajero_entrada_id
LEFT JOIN public.perfiles_usuario  cs ON cs.perfil_id = s.cajero_salida_id;

GRANT SELECT ON public.tickets TO anon, authenticated, service_role;


-- ── INSTEAD OF INSERT en tickets ─────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.trg_tickets_instead_insert()
RETURNS trigger LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
  v_tipo_id    uuid;
  v_estado_id  uuid;
  v_cajero_ent uuid;
BEGIN
  SELECT tipo_sesion_id INTO v_tipo_id
    FROM cat_tipo_sesion WHERE codigo = COALESCE(NEW.tipo,'normal');
  IF v_tipo_id IS NULL THEN
    SELECT tipo_sesion_id INTO v_tipo_id FROM cat_tipo_sesion WHERE codigo='normal';
  END IF;

  SELECT estado_sesion_id INTO v_estado_id
    FROM cat_estado_sesion WHERE codigo = COALESCE(NEW.estatus,'abierta');
  IF v_estado_id IS NULL THEN
    SELECT estado_sesion_id INTO v_estado_id FROM cat_estado_sesion WHERE codigo='abierta';
  END IF;

  v_cajero_ent := public.fn_perfil_por_texto(NEW.cajero_entrada);

  INSERT INTO public.sesiones (
    estacionamiento_id, tipo_sesion_id, estado_sesion_id,
    folio_entrada, entrada_at, cajero_entrada_id,
    corte_caja_entrada_id, requiere_cobro
  ) VALUES (
    NEW.plaza_id, v_tipo_id, v_estado_id,
    NEW.folio, COALESCE(NEW.hora_entrada_at, NOW()),
    v_cajero_ent, NEW.turno_entrada, COALESCE(NEW.requiere_cobro, true)
  );
  RETURN NEW;
EXCEPTION WHEN unique_violation THEN
  -- Ya existe (idempotente): permitir sin fallar
  RETURN NEW;
END $$;

CREATE TRIGGER tickets_instead_insert INSTEAD OF INSERT ON public.tickets
FOR EACH ROW EXECUTE FUNCTION public.trg_tickets_instead_insert();


-- ── INSTEAD OF UPDATE en tickets (cobro salida) ──────────────────────────────
CREATE OR REPLACE FUNCTION public.trg_tickets_instead_update()
RETURNS trigger LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
  v_estado_id  uuid;
  v_cajero_sal uuid;
BEGIN
  IF NEW.estatus IS DISTINCT FROM OLD.estatus AND NEW.estatus IS NOT NULL THEN
    SELECT estado_sesion_id INTO v_estado_id
      FROM cat_estado_sesion WHERE codigo = NEW.estatus;
  END IF;

  IF NEW.cajero_salida IS DISTINCT FROM OLD.cajero_salida AND NEW.cajero_salida IS NOT NULL THEN
    v_cajero_sal := public.fn_perfil_por_texto(NEW.cajero_salida);
  END IF;

  UPDATE public.sesiones SET
    folio_salida       = COALESCE(NEW.folio_salida,       folio_salida),
    salida_at          = COALESCE(NEW.hora_salida_at,     salida_at),
    importe_total      = COALESCE(NEW.importe,            importe_total),
    importe_calculado  = COALESCE(NEW.importe_calculado,  importe_calculado),
    importe_descuento  = COALESCE(NEW.importe_descuento,  importe_descuento),
    duracion_minutos   = COALESCE(NEW.minutos_estancia,   duracion_minutos),
    estado_sesion_id   = COALESCE(v_estado_id,            estado_sesion_id),
    cajero_salida_id   = COALESCE(v_cajero_sal,           cajero_salida_id),
    corte_caja_salida_id = COALESCE(NEW.turno_id,         corte_caja_salida_id),
    updated_at         = NOW()
  WHERE folio_entrada = OLD.folio;
  RETURN NEW;
END $$;

CREATE TRIGGER tickets_instead_update INSTEAD OF UPDATE ON public.tickets
FOR EACH ROW EXECUTE FUNCTION public.trg_tickets_instead_update();


-- ── Reemplazar bitacora para incluir 'usuario' TEXT ─────────────────────────
DROP VIEW IF EXISTS public.bitacora CASCADE;
CREATE VIEW public.bitacora AS
SELECT
  l.log_id                 AS bitacora_id,
  tb.codigo                AS tipo,
  l.subtipo                AS accion,
  l.subtipo,
  l.estacionamiento_id     AS plaza_id,
  l.perfil_id              AS cajero_id,
  p.email::text            AS usuario,
  l.sesion_id              AS ticket_id,
  l.descripcion            AS detalle,
  l.payload,
  l.ip,
  l.user_agent,
  l.ruta,
  l.ocurrido_at            AS created_at,
  l.ocurrido_at            AS hora
FROM public.log_evento l
LEFT JOIN public.cat_tipo_bitacora tb ON tb.tipo_bitacora_id = l.tipo_bitacora_id
LEFT JOIN public.perfiles_usuario  p  ON p.perfil_id = l.perfil_id;

GRANT SELECT ON public.bitacora TO anon, authenticated, service_role;


-- ── INSTEAD OF INSERT en bitacora ────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.trg_bitacora_instead_insert()
RETURNS trigger LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
  v_tipo_id uuid;
  v_perfil  uuid;
BEGIN
  SELECT tipo_bitacora_id INTO v_tipo_id
    FROM cat_tipo_bitacora WHERE codigo = COALESCE(NEW.tipo,'operativa');
  IF v_tipo_id IS NULL THEN
    SELECT tipo_bitacora_id INTO v_tipo_id FROM cat_tipo_bitacora WHERE codigo='operativa';
  END IF;

  v_perfil := public.fn_perfil_por_texto(NEW.usuario);

  INSERT INTO public.log_evento (
    tipo_bitacora_id, subtipo, estacionamiento_id, perfil_id,
    sesion_id, descripcion, payload, ip, user_agent, ruta, ocurrido_at
  ) VALUES (
    v_tipo_id, COALESCE(NEW.accion, NEW.subtipo, 'evento'),
    NEW.plaza_id, v_perfil, NEW.ticket_id,
    NEW.detalle, NEW.payload, NEW.ip, NEW.user_agent, NEW.ruta,
    COALESCE(NEW.created_at, NOW())
  );
  RETURN NEW;
END $$;

CREATE TRIGGER bitacora_instead_insert INSTEAD OF INSERT ON public.bitacora
FOR EACH ROW EXECUTE FUNCTION public.trg_bitacora_instead_insert();


-- ── Reemplazar cortes para incluir 'cajero' como TEXT ───────────────────────
DROP VIEW IF EXISTS public.cortes CASCADE;
CREATE VIEW public.cortes AS
SELECT
  c.corte_caja_id           AS turno_id,
  c.corte_caja_id           AS corte_id,
  c.estacionamiento_id      AS plaza_id,
  c.cajero_id,
  p1.email::text            AS cajero,
  c.cajero_relevo_id        AS cajero_relevo_id,
  p2.email::text            AS cajero_relevo,
  t.codigo                  AS turno_codigo,
  c.tipo,
  c.inicio_at               AS hora_apertura,
  c.fin_at                  AS hora_cierre,
  c.fondo_inicial,
  c.total_cobrado           AS efectivo_final,
  c.total_cobrado,
  c.total_entregado,
  c.estado,
  c.notas,
  c.inicio_at::date         AS fecha_op,
  c.created_at
FROM public.cortes_caja c
LEFT JOIN public.cat_turno t ON t.turno_id = c.turno_id
LEFT JOIN public.perfiles_usuario p1 ON p1.perfil_id = c.cajero_id
LEFT JOIN public.perfiles_usuario p2 ON p2.perfil_id = c.cajero_relevo_id;

GRANT SELECT ON public.cortes TO anon, authenticated, service_role;


-- ── INSTEAD OF INSERT en cortes ──────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.trg_cortes_instead_insert()
RETURNS trigger LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
  v_turno_id uuid;
  v_cajero   uuid;
BEGIN
  SELECT turno_id INTO v_turno_id
    FROM cat_turno WHERE codigo = COALESCE(NEW.turno_codigo,'matutino');
  v_cajero := public.fn_perfil_por_texto(NEW.cajero);

  INSERT INTO public.cortes_caja (
    estacionamiento_id, cajero_id, turno_id, tipo,
    inicio_at, fin_at, fondo_inicial, total_cobrado, total_entregado,
    estado, notas
  ) VALUES (
    NEW.plaza_id, v_cajero, v_turno_id, COALESCE(NEW.tipo,'apertura'),
    COALESCE(NEW.hora_apertura, NOW()), NEW.hora_cierre,
    NEW.fondo_inicial, NEW.total_cobrado, NEW.total_entregado,
    COALESCE(NEW.estado,'abierto'), NEW.notas
  );
  RETURN NEW;
END $$;

CREATE TRIGGER cortes_instead_insert INSTEAD OF INSERT ON public.cortes
FOR EACH ROW EXECUTE FUNCTION public.trg_cortes_instead_insert();


-- ── Sanity check ─────────────────────────────────────────────────────────────
SELECT
  'triggers_instead_of' AS check,
  COUNT(*)::int         AS n
FROM pg_trigger t
JOIN pg_class c ON c.oid = t.tgrelid
WHERE c.relname IN ('tickets','bitacora','cortes')
  AND NOT t.tgisinternal;
