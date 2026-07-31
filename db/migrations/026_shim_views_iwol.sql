-- ============================================================================
-- 026 — Vistas shim de compatibilidad IWOL sobre schema ONLYPARK
--
-- Los HTML del sistema IWOL (portales/operador.html, admin.html, corporativo.html)
-- fueron portados tal cual, con solo colores y branding cambiados. Sus queries
-- Supabase siguen apuntando a los nombres de tabla antiguos:
--    tickets, dim_plaza, cortes, bitacora, cajeros, empleados
--
-- Este archivo crea VISTAS con esos nombres viejos, mapeando al schema nuevo:
--    tickets     -> sesiones (columnas renombradas)
--    dim_plaza   -> estacionamientos + cfg_estacionamiento
--    cortes      -> cortes_caja
--    bitacora    -> log_evento
--    cajeros     -> perfiles_usuario + asignaciones_rol (rol=cajero/supervisor)
--    empleados   -> perfiles_usuario (todos activos)
--
-- Las vistas son SOLO LECTURA por default. Para INSERT/UPDATE desde IWOL se
-- crean INSTEAD OF triggers en una segunda iteración.
-- ============================================================================

-- ─── tickets (mapea sesiones) ────────────────────────────────────────────────
CREATE OR REPLACE VIEW public.tickets AS
SELECT
  s.folio_entrada           AS folio,
  s.folio_salida            AS folio_salida,
  ts.codigo                 AS tipo,
  es.codigo                 AS estatus,
  s.entrada_at              AS hora_entrada_at,
  to_char(s.entrada_at AT TIME ZONE 'America/Mexico_City','HH24:MI') AS hora_entrada,
  s.salida_at               AS hora_salida_at,
  to_char(s.salida_at AT TIME ZONE 'America/Mexico_City','HH24:MI') AS hora_salida,
  s.importe_total           AS importe,
  s.importe_calculado       AS importe_calculado,
  s.importe_descuento       AS importe_descuento,
  s.duracion_minutos        AS minutos_estadia,
  s.estacionamiento_id      AS plaza_id,
  s.tipo_sesion_id,
  s.estado_sesion_id,
  s.placa_id,
  s.vehiculo_id,
  s.cliente_id,
  s.pension_id,
  s.cajero_entrada_id       AS cajero_entrada,
  s.cajero_salida_id        AS cajero_salida,
  COALESCE(s.cajero_salida_id, s.cajero_entrada_id) AS cajero,
  s.corte_caja_entrada_id   AS turno_entrada,
  s.corte_caja_salida_id    AS turno_id,
  s.camara_entrada_id,
  s.camara_salida_id,
  s.entrada_at::date        AS fecha_op,
  s.requiere_cobro,
  s.created_at,
  s.updated_at,
  s.sesion_id               AS ticket_id,
  s.folio_local
FROM public.sesiones s
LEFT JOIN public.cat_tipo_sesion   ts ON ts.tipo_sesion_id   = s.tipo_sesion_id
LEFT JOIN public.cat_estado_sesion es ON es.estado_sesion_id = s.estado_sesion_id;

GRANT SELECT ON public.tickets TO anon, authenticated, service_role;


-- ─── dim_plaza (mapea estacionamientos + cfg_estacionamiento) ────────────────
CREATE OR REPLACE VIEW public.dim_plaza AS
SELECT
  est.estacionamiento_id AS plaza_id,
  est.codigo             AS plaza_codigo,
  est.nombre             AS plaza_nombre,
  est.capacidad_total,
  cfg.timezone,
  cfg.hora_apertura,
  cfg.hora_relevo_1,
  cfg.hora_relevo_2,
  cfg.hora_cierre,
  cfg.url_facturacion,
  cfg.promociones_habilitado,
  cfg.pension_habilitada,
  cfg.monedero_habilitado,
  cfg.lpr_habilitado,
  cfg.tolerancia_salida_min,
  cfg.formato_folio,
  cfg.moneda_id,
  cfg.pin_operativo_hash,
  est.sucursal_id,
  est.activo
FROM public.estacionamientos est
LEFT JOIN public.cfg_estacionamiento cfg USING (estacionamiento_id);

GRANT SELECT ON public.dim_plaza TO anon, authenticated, service_role;


-- ─── cortes (mapea cortes_caja) ──────────────────────────────────────────────
CREATE OR REPLACE VIEW public.cortes AS
SELECT
  c.corte_caja_id           AS turno_id,
  c.corte_caja_id           AS corte_id,
  c.estacionamiento_id      AS plaza_id,
  c.perfil_id               AS cajero_id,
  t.codigo                  AS turno_codigo,
  c.abierto_at              AS hora_apertura,
  c.cerrado_at              AS hora_cierre,
  c.fondo_inicial,
  c.efectivo_final,
  c.total_entradas,
  c.total_cobros,
  c.total_cortesias,
  c.total_pensiones,
  c.total_perdidos,
  c.diferencia,
  c.notas,
  c.abierto_at::date        AS fecha_op,
  c.created_at,
  c.updated_at
FROM public.cortes_caja c
LEFT JOIN public.cat_turno t ON t.turno_id = c.turno_id;

GRANT SELECT ON public.cortes TO anon, authenticated, service_role;


-- ─── bitacora (mapea log_evento) ─────────────────────────────────────────────
CREATE OR REPLACE VIEW public.bitacora AS
SELECT
  l.log_evento_id          AS bitacora_id,
  tb.codigo                AS tipo,
  l.subtipo,
  l.estacionamiento_id     AS plaza_id,
  l.perfil_id              AS cajero_id,
  l.sesion_id              AS ticket_id,
  l.descripcion,
  l.payload,
  l.creado_at              AS created_at,
  l.creado_at              AS hora
FROM public.log_evento l
LEFT JOIN public.cat_tipo_bitacora tb ON tb.tipo_bitacora_id = l.tipo_bitacora_id;

GRANT SELECT ON public.bitacora TO anon, authenticated, service_role;


-- ─── cajeros (mapea perfiles_usuario + asignaciones_rol) ─────────────────────
CREATE OR REPLACE VIEW public.cajeros AS
SELECT DISTINCT
  p.perfil_id      AS cajero_id,
  p.email          AS usuario,
  p.nombre_completo AS nombre,
  r.codigo         AS rol,
  p.activo,
  p.telefono,
  p.avatar_url,
  a.estacionamiento_id AS plaza_id,
  a.vigencia_desde,
  a.vigencia_hasta,
  p.created_at,
  p.updated_at
FROM public.perfiles_usuario p
JOIN public.asignaciones_rol a ON a.perfil_id = p.perfil_id AND a.activo
JOIN public.cat_rol          r ON r.rol_id     = a.rol_id
WHERE p.activo
  AND (a.vigencia_hasta IS NULL OR a.vigencia_hasta >= CURRENT_DATE);

GRANT SELECT ON public.cajeros TO anon, authenticated, service_role;


-- ─── empleados (perfiles activos) ────────────────────────────────────────────
CREATE OR REPLACE VIEW public.empleados AS
SELECT
  p.perfil_id       AS id,
  p.nombre_completo,
  p.email,
  p.telefono,
  p.activo,
  p.created_at
FROM public.perfiles_usuario p
WHERE p.activo;

GRANT SELECT ON public.empleados TO anon, authenticated, service_role;
