-- ============================================================================
-- 029 — Extender shim views + arreglar mapeos de columnas y enums
--
-- Problemas detectados desde el portal IWOL:
--   1. dim_plaza: faltan tarifa_normal/pref/perdido, tolerancia_min/redondeo
--   2. avisos_operador: IWOL usa 'id' pero tabla real usa aviso_id
--   3. empleados: faltan puesto, area
--   4. pensiones: IWOL espera join a vehiculos/clientes con placas
--   5. campanas: IWOL usa fecha_inicio/fecha_fin, tabla real usa vigencia_desde/hasta
--   6. estatus enum: IWOL manda 'abierto'/'cobrado', enum real usa 'abierta'/'pagada'
-- ============================================================================

-- ── 1) dim_plaza: agregar tarifas + tolerancia_redondeo ─────────────────────
DROP VIEW IF EXISTS public.dim_plaza CASCADE;
CREATE VIEW public.dim_plaza AS
WITH tarifas AS (
  SELECT p.estacionamiento_id,
         MAX(CASE WHEN tt.codigo='hora'       THEN rt.monto END) AS tarifa_normal,
         MAX(CASE WHEN tt.codigo='preferencial' THEN rt.monto END) AS tarifa_pref,
         MAX(CASE WHEN tt.codigo IN ('perdido','maxima') THEN rt.monto END) AS tarifa_perdido
    FROM public.politicas_tarifarias p
    JOIN public.reglas_tarifarias rt USING (politica_id)
    JOIN public.cat_tipo_tarifa   tt USING (tipo_tarifa_id)
   WHERE p.activo AND rt.activa
   GROUP BY p.estacionamiento_id
)
SELECT
  est.estacionamiento_id     AS plaza_id,
  est.codigo                 AS plaza_codigo,
  est.nombre                 AS plaza_nombre,
  est.capacidad_total,
  tz.codigo                  AS timezone,
  cfg.hora_apertura,
  NULL::time                 AS hora_relevo_1,
  NULL::time                 AS hora_relevo_2,
  cfg.hora_cierre,
  cfg.contacto_web           AS url_facturacion,
  cfg.promociones_habilitado,
  false                      AS pension_habilitada,
  cfg.onlywallet_habilitado  AS monedero_habilitado,
  cfg.lpr_habilitado,
  cfg.minutos_tolerancia_salida AS tolerancia_salida_min,
  cfg.tolerancia_min,
  false                      AS tolerancia_redondeo_habilitado,
  15                         AS tolerancia_redondeo_min,
  COALESCE(t.tarifa_normal,   15)::numeric AS tarifa_normal,
  COALESCE(t.tarifa_pref,     15)::numeric AS tarifa_pref,
  COALESCE(t.tarifa_perdido,  100)::numeric AS tarifa_perdido,
  cfg.formato_folio_entrada  AS formato_folio,
  NULL::uuid                 AS moneda_id,
  NULL::text                 AS pin_operativo_hash,
  est.sucursal_id,
  est.activo
FROM public.estacionamientos est
LEFT JOIN public.cfg_estacionamiento cfg USING (estacionamiento_id)
LEFT JOIN public.cat_timezone tz ON tz.timezone_id = est.timezone_id
LEFT JOIN tarifas t              ON t.estacionamiento_id = est.estacionamiento_id;

GRANT SELECT ON public.dim_plaza TO anon, authenticated, service_role;


-- ── 2) avisos_operador shim view (alias id, campos IWOL) ────────────────────
-- La tabla real se queda como está; solo agregamos vista con alias id.
DROP VIEW IF EXISTS public.v_avisos_operador CASCADE;
-- NOTA: no podemos crear vista con MISMO nombre que la tabla. Renombramos la tabla
-- o dejamos la vista con otro nombre y REDIRECT via IWOL. Mejor: cambiamos la
-- tabla real a avisos_operador_base y creamos vista avisos_operador con alias id.
ALTER TABLE public.avisos_operador RENAME TO avisos_operador_base;

CREATE OR REPLACE VIEW public.avisos_operador AS
SELECT
  a.aviso_id                 AS id,
  a.aviso_id,
  a.estacionamiento_id,
  a.estacionamiento_id       AS plaza_id,
  a.destinatario_perfil      AS destinatario,
  a.destinatario_rol_id,
  a.mensaje,
  a.origen,
  a.hilo_id,
  a.leido_admin,
  a.leido_destinatario,
  a.creado_por,
  a.created_at
FROM public.avisos_operador_base a;

GRANT SELECT ON public.avisos_operador TO anon, authenticated, service_role;

-- INSTEAD OF INSERT en avisos_operador (IWOL manda {plaza_id, usuario, mensaje, origen, destinatario, leido_admin})
CREATE OR REPLACE FUNCTION public.trg_avisos_ii()
RETURNS trigger LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE v_perfil uuid; v_dest_id uuid;
BEGIN
  v_perfil  := public.fn_perfil_por_texto(COALESCE(NEW.creado_por::text, NULL));
  v_dest_id := CASE WHEN NEW.destinatario ~ '^[0-9a-f-]{36}$' THEN NEW.destinatario::uuid ELSE NULL END;

  INSERT INTO public.avisos_operador_base
    (estacionamiento_id, destinatario_perfil, mensaje, origen, leido_admin, leido_destinatario, creado_por, hilo_id)
  VALUES (NEW.estacionamiento_id, v_dest_id, NEW.mensaje, COALESCE(NEW.origen,'cajero'),
          COALESCE(NEW.leido_admin,false), COALESCE(NEW.leido_destinatario,false),
          v_perfil, NEW.hilo_id);
  RETURN NEW;
END $$;

CREATE TRIGGER avisos_operador_instead_insert INSTEAD OF INSERT ON public.avisos_operador
FOR EACH ROW EXECUTE FUNCTION public.trg_avisos_ii();


-- ── 3) empleados: agregar puesto y area (NULL por ahora) ────────────────────
DROP VIEW IF EXISTS public.empleados CASCADE;
CREATE VIEW public.empleados AS
SELECT
  p.perfil_id       AS id,
  p.nombre_completo,
  NULL::text        AS puesto,
  NULL::text        AS area,
  p.email,
  p.telefono,
  p.activo,
  p.created_at
FROM public.perfiles_usuario p
WHERE p.activo;

GRANT SELECT ON public.empleados TO anon, authenticated, service_role;


-- ── 4) pensiones shim con estado='activo' y hijas vehiculos/clientes ────────
DROP VIEW IF EXISTS public.v_pensiones_iwol CASCADE;
-- No podemos crear vista con mismo nombre que tabla, así que renombramos tabla real
ALTER TABLE public.pensiones RENAME TO pensiones_base;

CREATE OR REPLACE VIEW public.pensiones AS
SELECT
  p.pension_id,
  p.estacionamiento_id,
  p.cliente_id,
  p.vehiculo_id,
  p.placa_id,
  tp.codigo                   AS tipo,
  ep.codigo                   AS estado,
  p.monto_mensual,
  p.fecha_inicio,
  p.fecha_fin,
  p.hora_inicio,
  p.hora_fin,
  p.dia_pago,
  p.codigo_acceso,
  p.notas,
  p.activo,
  p.created_at,
  p.updated_at
FROM public.pensiones_base p
LEFT JOIN public.cat_tipo_pension   tp ON tp.tipo_pension_id   = p.tipo_pension_id
LEFT JOIN public.cat_estado_pension ep ON ep.estado_pension_id = p.estado_pension_id;

GRANT SELECT ON public.pensiones TO anon, authenticated, service_role;


-- ── 5) campanas shim con fecha_inicio/fecha_fin + impactos ──────────────────
DROP VIEW IF EXISTS public.v_campanas_iwol CASCADE;
ALTER TABLE public.campanas RENAME TO campanas_base;

CREATE OR REPLACE VIEW public.campanas AS
SELECT
  c.campana_id                 AS id,
  c.campana_id,
  c.estacionamiento_id,
  c.local_id,
  c.tipo_promocion_id,
  c.nombre,
  c.titulo_promo,
  c.texto_promo,
  c.valor_promo,
  c.qr_url,
  c.logo_url,
  c.vigencia_desde             AS fecha_inicio,
  c.vigencia_hasta             AS fecha_fin,
  c.hora_desde,
  c.hora_hasta,
  c.prioridad,
  c.max_impresiones,
  c.estado,
  c.presupuesto_impactos,
  c.costo_por_impacto,
  COALESCE((SELECT COUNT(*)::int FROM public.impresiones_campana ic WHERE ic.campana_id = c.campana_id), 0) AS impactos,
  c.notas,
  c.creado_por,
  c.created_at,
  c.updated_at
FROM public.campanas_base c;

GRANT SELECT ON public.campanas TO anon, authenticated, service_role;

-- INSTEAD OF UPDATE en campanas (IWOL puede incrementar impresiones u actualizar campos)
CREATE OR REPLACE FUNCTION public.trg_campanas_iu()
RETURNS trigger LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public, pg_temp
AS $$
BEGIN
  UPDATE public.campanas_base SET
    estado       = COALESCE(NEW.estado, estado),
    max_impresiones = COALESCE(NEW.max_impresiones, max_impresiones),
    vigencia_desde  = COALESCE(NEW.fecha_inicio, vigencia_desde),
    vigencia_hasta  = COALESCE(NEW.fecha_fin, vigencia_hasta),
    titulo_promo    = COALESCE(NEW.titulo_promo, titulo_promo),
    texto_promo     = COALESCE(NEW.texto_promo, texto_promo),
    updated_at      = NOW()
  WHERE campana_id = OLD.campana_id;
  RETURN NEW;
END $$;

CREATE TRIGGER campanas_instead_update INSTEAD OF UPDATE ON public.campanas
FOR EACH ROW EXECUTE FUNCTION public.trg_campanas_iu();


-- ── 6) Mapeo de estatus IWOL -> enum ONLYPARK en trigger tickets ────────────
-- IWOL usa: abierto, cobrado, cancelado, perdido, empleado, pension
-- ONLYPARK: abierta, cancelada, cerrada, liberada, pagada, perdida
CREATE OR REPLACE FUNCTION public.fn_estado_sesion_por_iwol(p_codigo text)
RETURNS uuid LANGUAGE sql STABLE
SECURITY DEFINER SET search_path = public, pg_temp
AS $$
  SELECT estado_sesion_id FROM public.cat_estado_sesion
   WHERE codigo = CASE lower(coalesce(p_codigo,''))
                    WHEN 'abierto'  THEN 'abierta'
                    WHEN 'cerrado'  THEN 'cerrada'
                    WHEN 'cobrado'  THEN 'pagada'
                    WHEN 'liberado' THEN 'liberada'
                    WHEN 'cancelado' THEN 'cancelada'
                    WHEN 'perdido'  THEN 'perdida'
                    ELSE lower(p_codigo)
                  END
   LIMIT 1;
$$;

-- Recrear triggers de tickets usando el mapeo
CREATE OR REPLACE FUNCTION public.trg_tickets_instead_insert()
RETURNS trigger LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
  v_tipo_id uuid; v_estado_id uuid; v_cajero_ent uuid;
BEGIN
  SELECT tipo_sesion_id INTO v_tipo_id
    FROM cat_tipo_sesion WHERE codigo = COALESCE(NEW.tipo,'normal');
  IF v_tipo_id IS NULL THEN SELECT tipo_sesion_id INTO v_tipo_id FROM cat_tipo_sesion WHERE codigo='normal'; END IF;

  v_estado_id  := public.fn_estado_sesion_por_iwol(COALESCE(NEW.estatus,'abierta'));
  IF v_estado_id IS NULL THEN SELECT estado_sesion_id INTO v_estado_id FROM cat_estado_sesion WHERE codigo='abierta'; END IF;

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
EXCEPTION WHEN unique_violation THEN RETURN NEW;
END $$;

CREATE OR REPLACE FUNCTION public.trg_tickets_instead_update()
RETURNS trigger LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE v_estado_id uuid; v_cajero_sal uuid;
BEGIN
  IF NEW.estatus IS DISTINCT FROM OLD.estatus AND NEW.estatus IS NOT NULL THEN
    v_estado_id := public.fn_estado_sesion_por_iwol(NEW.estatus);
  END IF;
  IF NEW.cajero_salida IS DISTINCT FROM OLD.cajero_salida AND NEW.cajero_salida IS NOT NULL THEN
    v_cajero_sal := public.fn_perfil_por_texto(NEW.cajero_salida);
  END IF;

  UPDATE public.sesiones SET
    folio_salida         = COALESCE(NEW.folio_salida,       folio_salida),
    salida_at            = COALESCE(NEW.hora_salida_at,     salida_at),
    importe_total        = COALESCE(NEW.importe,            importe_total),
    importe_calculado    = COALESCE(NEW.importe_calculado,  importe_calculado),
    importe_descuento    = COALESCE(NEW.importe_descuento,  importe_descuento),
    duracion_minutos     = COALESCE(NEW.minutos_estancia,   duracion_minutos),
    estado_sesion_id     = COALESCE(v_estado_id,            estado_sesion_id),
    cajero_salida_id     = COALESCE(v_cajero_sal,           cajero_salida_id),
    corte_caja_salida_id = COALESCE(NEW.turno_id,           corte_caja_salida_id),
    updated_at           = NOW()
  WHERE folio_entrada = OLD.folio;
  RETURN NEW;
END $$;

-- Notify PostgREST para invalidar cache
NOTIFY pgrst, 'reload schema';

-- Sanity checks
SELECT
  'dim_plaza filas'   AS check, COUNT(*)::int AS n FROM public.dim_plaza
UNION ALL SELECT 'campanas filas',   COUNT(*)::int FROM public.campanas
UNION ALL SELECT 'empleados filas',  COUNT(*)::int FROM public.empleados
UNION ALL SELECT 'pensiones filas',  COUNT(*)::int FROM public.pensiones
UNION ALL SELECT 'avisos filas',     COUNT(*)::int FROM public.avisos_operador;
