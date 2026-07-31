-- ============================================================================
-- DWH v1 — Parte 3: funciones ETL + monitoreo + runner
-- Todas SECURITY DEFINER (corren como owner), no leen contexto authenticated.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- Helper: registrar inicio/fin de ejecución
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION dwh.fn_log_etl_inicio(
  p_job text, p_watermark_desde timestamptz, p_watermark_hasta timestamptz
) RETURNS uuid LANGUAGE sql
SECURITY DEFINER SET search_path = dwh, public, pg_temp
AS $$
  INSERT INTO dwh.log_etl_ejecucion (job_codigo, estado, watermark_desde, watermark_hasta)
  VALUES (p_job, 'ejecutando', p_watermark_desde, p_watermark_hasta)
  RETURNING log_etl_id;
$$;

CREATE OR REPLACE FUNCTION dwh.fn_log_etl_fin(
  p_log_id uuid, p_estado text, p_rows_in int, p_rows_out int, p_rows_rej int,
  p_mensaje text, p_detalle jsonb
) RETURNS void LANGUAGE sql
SECURITY DEFINER SET search_path = dwh, public, pg_temp
AS $$
  UPDATE dwh.log_etl_ejecucion
     SET fin_at        = NOW(),
         duracion_ms   = EXTRACT(EPOCH FROM (NOW() - inicio_at))*1000,
         estado        = p_estado,
         rows_in       = p_rows_in,
         rows_out      = p_rows_out,
         rows_rechazados = p_rows_rej,
         mensaje       = p_mensaje,
         detalle       = p_detalle
   WHERE log_etl_id   = p_log_id;
$$;

-- ---------------------------------------------------------------------------
-- ETL dim_tiempo: poblar rango
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION dwh.fn_etl_populate_dim_tiempo(p_desde date, p_hasta date)
RETURNS integer LANGUAGE plpgsql
SECURITY DEFINER SET search_path = dwh, public, pg_temp
AS $$
DECLARE
  v_log uuid; v_rows int;
BEGIN
  v_log := dwh.fn_log_etl_inicio('dim_tiempo', p_desde::timestamptz, p_hasta::timestamptz);

  WITH gen AS (
    SELECT d::date AS fecha
    FROM generate_series(p_desde, p_hasta, interval '1 day') d
  ),
  ins AS (
    INSERT INTO dwh.dim_tiempo (
      fecha_id, fecha, anio, trimestre, mes, mes_nombre, semana_iso,
      dia, dia_semana, dia_semana_nombre, es_fin_semana, anio_mes, yyyymmdd
    )
    SELECT
      (to_char(fecha,'YYYYMMDD'))::int,
      fecha,
      EXTRACT(YEAR FROM fecha)::smallint,
      EXTRACT(QUARTER FROM fecha)::smallint,
      EXTRACT(MONTH FROM fecha)::smallint,
      to_char(fecha,'TMMonth'),
      EXTRACT(WEEK FROM fecha)::smallint,
      EXTRACT(DAY FROM fecha)::smallint,
      EXTRACT(ISODOW FROM fecha)::smallint,
      to_char(fecha,'TMDay'),
      EXTRACT(ISODOW FROM fecha) IN (6,7),
      (to_char(fecha,'YYYYMM'))::int,
      to_char(fecha,'YYYYMMDD')
    FROM gen
    ON CONFLICT (fecha_id) DO NOTHING
    RETURNING 1
  )
  SELECT COUNT(*) INTO v_rows FROM ins;

  PERFORM dwh.fn_log_etl_fin(v_log, 'finalizado', v_rows, v_rows, 0,
                             'poblado ' || v_rows || ' días', NULL);
  RETURN v_rows;
END $$;

-- ---------------------------------------------------------------------------
-- ETL dim_hora: poblar 0..23 (idempotente)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION dwh.fn_etl_populate_dim_hora()
RETURNS integer LANGUAGE sql
SECURITY DEFINER SET search_path = dwh, public, pg_temp
AS $$
  INSERT INTO dwh.dim_hora (hora_id, hora_texto, franja)
  SELECT h::smallint,
         lpad(h::text,2,'0') || ':00',
         CASE WHEN h BETWEEN 0 AND 5   THEN 'madrugada'
              WHEN h BETWEEN 6 AND 11  THEN 'mañana'
              WHEN h BETWEEN 12 AND 18 THEN 'tarde'
              ELSE 'noche' END
  FROM generate_series(0,23) h
  ON CONFLICT (hora_id) DO NOTHING
  RETURNING 1;
$$;

-- ---------------------------------------------------------------------------
-- ETL refresh de dims “pequeñas” (upsert desde public)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION dwh.fn_etl_refresh_dims()
RETURNS jsonb LANGUAGE plpgsql
SECURITY DEFINER SET search_path = dwh, public, pg_temp
AS $$
DECLARE
  v_log uuid; v_emp int; v_est int; v_ts int; v_mp int; v_usr int;
BEGIN
  v_log := dwh.fn_log_etl_inicio('refresh_dims', NULL, NOW());

  -- dim_empresa
  WITH src AS (
    SELECT em.empresa_id, em.codigo AS empresa_codigo, em.razon_social AS empresa_nombre,
           em.grupo_id, g.codigo AS grupo_codigo, g.nombre AS grupo_nombre, em.activo
    FROM public.empresas em
    JOIN public.grupos_empresariales g ON g.grupo_id = em.grupo_id
  ),
  up AS (
    INSERT INTO dwh.dim_empresa (empresa_id, empresa_codigo, empresa_nombre,
                                 grupo_id, grupo_codigo, grupo_nombre, activo)
    SELECT * FROM src
    ON CONFLICT (empresa_id) DO UPDATE SET
      empresa_codigo = EXCLUDED.empresa_codigo,
      empresa_nombre = EXCLUDED.empresa_nombre,
      grupo_id       = EXCLUDED.grupo_id,
      grupo_codigo   = EXCLUDED.grupo_codigo,
      grupo_nombre   = EXCLUDED.grupo_nombre,
      activo         = EXCLUDED.activo,
      actualizado_at = NOW()
    RETURNING 1
  )
  SELECT COUNT(*) INTO v_emp FROM up;

  -- dim_estacionamiento (jerarquía denormalizada permitida en DWH)
  WITH src AS (
    SELECT est.estacionamiento_id, est.codigo AS est_codigo, est.nombre AS est_nombre,
           est.capacidad_total,
           s.sucursal_id, s.codigo AS suc_codigo, s.nombre AS suc_nombre,
           em.empresa_id, em.codigo AS emp_codigo, em.razon_social AS emp_nombre,
           g.grupo_id, g.codigo AS grp_codigo, g.nombre AS grp_nombre,
           p.codigo_iso2, tz.codigo AS tz_iana, est.activo
    FROM public.estacionamientos est
    JOIN public.sucursales s      ON s.sucursal_id = est.sucursal_id
    JOIN public.empresas em       ON em.empresa_id = s.empresa_id
    JOIN public.grupos_empresariales g ON g.grupo_id = em.grupo_id
    LEFT JOIN public.cat_pais p       ON p.pais_id = est.pais_id
    LEFT JOIN public.cat_timezone tz  ON tz.timezone_id = est.timezone_id
  ),
  up AS (
    INSERT INTO dwh.dim_estacionamiento (
      estacionamiento_id, estacionamiento_codigo, estacionamiento_nombre, capacidad_total,
      sucursal_id, sucursal_codigo, sucursal_nombre,
      empresa_id, empresa_codigo, empresa_nombre,
      grupo_id, grupo_codigo, grupo_nombre,
      pais_iso2, timezone_iana, activo)
    SELECT * FROM src
    ON CONFLICT (estacionamiento_id) DO UPDATE SET
      estacionamiento_codigo = EXCLUDED.estacionamiento_codigo,
      estacionamiento_nombre = EXCLUDED.estacionamiento_nombre,
      capacidad_total        = EXCLUDED.capacidad_total,
      sucursal_id            = EXCLUDED.sucursal_id,
      sucursal_codigo        = EXCLUDED.sucursal_codigo,
      sucursal_nombre        = EXCLUDED.sucursal_nombre,
      empresa_id             = EXCLUDED.empresa_id,
      empresa_codigo         = EXCLUDED.empresa_codigo,
      empresa_nombre         = EXCLUDED.empresa_nombre,
      grupo_id               = EXCLUDED.grupo_id,
      grupo_codigo           = EXCLUDED.grupo_codigo,
      grupo_nombre           = EXCLUDED.grupo_nombre,
      pais_iso2              = EXCLUDED.pais_iso2,
      timezone_iana          = EXCLUDED.timezone_iana,
      activo                 = EXCLUDED.activo,
      actualizado_at         = NOW()
    RETURNING 1
  )
  SELECT COUNT(*) INTO v_est FROM up;

  -- dim_tipo_sesion
  WITH up AS (
    INSERT INTO dwh.dim_tipo_sesion (tipo_sesion_id, codigo, nombre)
    SELECT tipo_sesion_id, codigo, nombre FROM public.cat_tipo_sesion
    ON CONFLICT (tipo_sesion_id) DO UPDATE SET
      codigo = EXCLUDED.codigo, nombre = EXCLUDED.nombre, actualizado_at = NOW()
    RETURNING 1
  ) SELECT COUNT(*) INTO v_ts FROM up;

  -- dim_metodo_pago
  WITH up AS (
    INSERT INTO dwh.dim_metodo_pago (metodo_pago_id, codigo, nombre)
    SELECT metodo_pago_id, codigo, nombre FROM public.cat_metodo_pago
    ON CONFLICT (metodo_pago_id) DO UPDATE SET
      codigo = EXCLUDED.codigo, nombre = EXCLUDED.nombre, actualizado_at = NOW()
    RETURNING 1
  ) SELECT COUNT(*) INTO v_mp FROM up;

  -- dim_usuario
  WITH up AS (
    INSERT INTO dwh.dim_usuario (perfil_id, nombre_completo, email, activo)
    SELECT perfil_id, nombre_completo, email::text, activo FROM public.perfiles_usuario
    ON CONFLICT (perfil_id) DO UPDATE SET
      nombre_completo = EXCLUDED.nombre_completo,
      email           = EXCLUDED.email,
      activo          = EXCLUDED.activo,
      actualizado_at  = NOW()
    RETURNING 1
  ) SELECT COUNT(*) INTO v_usr FROM up;

  PERFORM dwh.fn_log_etl_fin(v_log, 'finalizado',
    v_emp+v_est+v_ts+v_mp+v_usr, v_emp+v_est+v_ts+v_mp+v_usr, 0,
    'refresh completo', jsonb_build_object(
      'empresa', v_emp, 'estacionamiento', v_est,
      'tipo_sesion', v_ts, 'metodo_pago', v_mp, 'usuario', v_usr));
  RETURN jsonb_build_object('empresa', v_emp, 'estacionamiento', v_est,
    'tipo_sesion', v_ts, 'metodo_pago', v_mp, 'usuario', v_usr);
END $$;

-- ---------------------------------------------------------------------------
-- ETL incremental fact_tickets (a partir del watermark)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION dwh.fn_etl_incremental_fact_tickets()
RETURNS integer LANGUAGE plpgsql
SECURITY DEFINER SET search_path = dwh, public, pg_temp
AS $$
DECLARE
  v_log uuid; v_wm timestamptz; v_now timestamptz := NOW(); v_rows int;
BEGIN
  SELECT COALESCE(last_watermark, 'epoch'::timestamptz) INTO v_wm
    FROM dwh.etl_control WHERE job_codigo = 'fact_tickets';
  IF NOT FOUND THEN
    INSERT INTO dwh.etl_control (job_codigo, descripcion, last_watermark)
    VALUES ('fact_tickets','Carga incremental de sesiones cerradas','epoch'::timestamptz);
    v_wm := 'epoch'::timestamptz;
  END IF;
  v_log := dwh.fn_log_etl_inicio('fact_tickets', v_wm, v_now);

  WITH src AS (
    SELECT s.sesion_id,
           (to_char(s.entrada_at AT TIME ZONE 'UTC','YYYYMMDD'))::int   AS fecha_ent_id,
           EXTRACT(HOUR FROM s.entrada_at AT TIME ZONE 'UTC')::smallint AS hora_ent,
           CASE WHEN s.salida_at IS NULL THEN NULL
                ELSE (to_char(s.salida_at AT TIME ZONE 'UTC','YYYYMMDD'))::int END AS fecha_sal_id,
           CASE WHEN s.salida_at IS NULL THEN NULL
                ELSE EXTRACT(HOUR FROM s.salida_at AT TIME ZONE 'UTC')::smallint END AS hora_sal,
           de.estacionamiento_sk,
           dem.empresa_sk,
           dts.tipo_sesion_sk,
           du_e.usuario_sk AS cajero_ent_sk,
           du_s.usuario_sk AS cajero_sal_sk,
           s.duracion_minutos,
           s.requiere_cobro,
           s.importe_calculado, s.importe_descuento, s.importe_total,
           EXISTS (SELECT 1 FROM public.pagos p
                    WHERE p.sesion_id = s.sesion_id AND p.cobrado_at IS NOT NULL) AS fue_cobrada,
           s.updated_at
    FROM public.sesiones s
    JOIN dwh.dim_estacionamiento de ON de.estacionamiento_id = s.estacionamiento_id
    JOIN dwh.dim_empresa dem
      ON dem.empresa_id = (SELECT empresa_id FROM public.sucursales su
                            JOIN public.estacionamientos es ON es.sucursal_id = su.sucursal_id
                           WHERE es.estacionamiento_id = s.estacionamiento_id)
    LEFT JOIN dwh.dim_tipo_sesion dts ON dts.tipo_sesion_id = s.tipo_sesion_id
    LEFT JOIN dwh.dim_usuario du_e    ON du_e.perfil_id     = s.cajero_entrada_id
    LEFT JOIN dwh.dim_usuario du_s    ON du_s.perfil_id     = s.cajero_salida_id
    WHERE s.updated_at > v_wm
  ),
  up AS (
    INSERT INTO dwh.fact_tickets (
      sesion_id, fecha_entrada_id, hora_entrada_id, fecha_salida_id, hora_salida_id,
      estacionamiento_sk, empresa_sk, tipo_sesion_sk, cajero_entrada_sk, cajero_salida_sk,
      duracion_minutos, requiere_cobro, importe_calculado, importe_descuento, importe_total,
      fue_cobrada, origen_updated_at)
    SELECT sesion_id, fecha_ent_id, hora_ent, fecha_sal_id, hora_sal,
           estacionamiento_sk, empresa_sk, tipo_sesion_sk, cajero_ent_sk, cajero_sal_sk,
           duracion_minutos, requiere_cobro, importe_calculado, importe_descuento, importe_total,
           fue_cobrada, updated_at
    FROM src
    ON CONFLICT (sesion_id) DO UPDATE SET
      fecha_salida_id   = EXCLUDED.fecha_salida_id,
      hora_salida_id    = EXCLUDED.hora_salida_id,
      cajero_salida_sk  = EXCLUDED.cajero_salida_sk,
      duracion_minutos  = EXCLUDED.duracion_minutos,
      importe_calculado = EXCLUDED.importe_calculado,
      importe_descuento = EXCLUDED.importe_descuento,
      importe_total     = EXCLUDED.importe_total,
      fue_cobrada       = EXCLUDED.fue_cobrada,
      origen_updated_at = EXCLUDED.origen_updated_at
    RETURNING 1
  )
  SELECT COUNT(*) INTO v_rows FROM up;

  UPDATE dwh.etl_control
     SET last_watermark = v_now, last_run_at = v_now, last_status = 'finalizado',
         last_rows_in = v_rows, last_rows_out = v_rows, updated_at = NOW()
   WHERE job_codigo = 'fact_tickets';

  PERFORM dwh.fn_log_etl_fin(v_log, 'finalizado', v_rows, v_rows, 0,
                             'incremental completado', NULL);
  RETURN v_rows;
END $$;

-- ---------------------------------------------------------------------------
-- ETL incremental fact_pagos
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION dwh.fn_etl_incremental_fact_pagos()
RETURNS integer LANGUAGE plpgsql
SECURITY DEFINER SET search_path = dwh, public, pg_temp
AS $$
DECLARE
  v_log uuid; v_wm timestamptz; v_now timestamptz := NOW(); v_rows int;
BEGIN
  SELECT COALESCE(last_watermark, 'epoch'::timestamptz) INTO v_wm
    FROM dwh.etl_control WHERE job_codigo = 'fact_pagos';
  IF NOT FOUND THEN
    INSERT INTO dwh.etl_control (job_codigo, descripcion, last_watermark)
    VALUES ('fact_pagos','Carga incremental de pagos cobrados','epoch'::timestamptz);
    v_wm := 'epoch'::timestamptz;
  END IF;
  v_log := dwh.fn_log_etl_inicio('fact_pagos', v_wm, v_now);

  WITH src AS (
    SELECT p.pago_id, p.sesion_id,
           (to_char(p.cobrado_at AT TIME ZONE 'UTC','YYYYMMDD'))::int AS fecha_id,
           EXTRACT(HOUR FROM p.cobrado_at AT TIME ZONE 'UTC')::smallint AS hora_id,
           de.estacionamiento_sk,
           dem.empresa_sk,
           dmp.metodo_pago_sk,
           du.usuario_sk AS cajero_sk,
           ft.fact_ticket_id,
           p.monto, p.moneda_id, p.referencia_externa, p.updated_at
    FROM public.pagos p
    JOIN dwh.dim_estacionamiento de ON de.estacionamiento_id = p.estacionamiento_id
    JOIN dwh.dim_empresa dem
      ON dem.empresa_id = (SELECT empresa_id FROM public.sucursales su
                            JOIN public.estacionamientos es ON es.sucursal_id = su.sucursal_id
                           WHERE es.estacionamiento_id = p.estacionamiento_id)
    LEFT JOIN dwh.dim_metodo_pago dmp ON dmp.metodo_pago_id = p.metodo_pago_id
    LEFT JOIN dwh.dim_usuario     du  ON du.perfil_id       = p.cobrado_por
    LEFT JOIN dwh.fact_tickets    ft  ON ft.sesion_id       = p.sesion_id
    WHERE p.cobrado_at IS NOT NULL AND p.updated_at > v_wm
  ),
  up AS (
    INSERT INTO dwh.fact_pagos (
      pago_id, sesion_id, fact_ticket_id, fecha_cobro_id, hora_cobro_id,
      estacionamiento_sk, empresa_sk, metodo_pago_sk, cajero_sk,
      monto, moneda_id, referencia_externa, origen_updated_at)
    SELECT pago_id, sesion_id, fact_ticket_id, fecha_id, hora_id,
           estacionamiento_sk, empresa_sk, metodo_pago_sk, cajero_sk,
           monto, moneda_id, referencia_externa, updated_at
    FROM src
    ON CONFLICT (pago_id) DO UPDATE SET
      monto              = EXCLUDED.monto,
      metodo_pago_sk     = EXCLUDED.metodo_pago_sk,
      cajero_sk          = EXCLUDED.cajero_sk,
      fact_ticket_id     = EXCLUDED.fact_ticket_id,
      origen_updated_at  = EXCLUDED.origen_updated_at
    RETURNING 1
  )
  SELECT COUNT(*) INTO v_rows FROM up;

  UPDATE dwh.etl_control
     SET last_watermark = v_now, last_run_at = v_now, last_status = 'finalizado',
         last_rows_in = v_rows, last_rows_out = v_rows, updated_at = NOW()
   WHERE job_codigo = 'fact_pagos';

  PERFORM dwh.fn_log_etl_fin(v_log, 'finalizado', v_rows, v_rows, 0,
                             'incremental completado', NULL);
  RETURN v_rows;
END $$;

-- ---------------------------------------------------------------------------
-- Runner: correr todo en orden
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION dwh.fn_etl_run_all()
RETURNS jsonb LANGUAGE plpgsql
SECURITY DEFINER SET search_path = dwh, public, pg_temp
AS $$
DECLARE
  v_dims jsonb; v_ft int; v_fp int; v_tt int;
BEGIN
  PERFORM dwh.fn_etl_populate_dim_hora();
  v_tt := dwh.fn_etl_populate_dim_tiempo((CURRENT_DATE - INTERVAL '3 years')::date, (CURRENT_DATE + INTERVAL '2 years')::date);
  v_dims := dwh.fn_etl_refresh_dims();
  v_ft := dwh.fn_etl_incremental_fact_tickets();
  v_fp := dwh.fn_etl_incremental_fact_pagos();
  RETURN jsonb_build_object(
    'dim_tiempo_nuevos', v_tt,
    'dims_refresh',      v_dims,
    'fact_tickets',      v_ft,
    'fact_pagos',        v_fp,
    'ejecutado_at',      NOW()
  );
END $$;

-- ---------------------------------------------------------------------------
-- Vista de monitoreo ETL
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW dwh.v_etl_monitor AS
SELECT
  c.job_codigo,
  c.descripcion,
  c.last_run_at,
  c.last_status,
  c.last_watermark,
  c.last_rows_in,
  c.last_rows_out,
  (SELECT COUNT(*) FROM dwh.log_etl_ejecucion l WHERE l.job_codigo=c.job_codigo AND l.estado='error') AS errores_totales,
  (SELECT MAX(fin_at) FROM dwh.log_etl_ejecucion l WHERE l.job_codigo=c.job_codigo AND l.estado='error') AS ultimo_error_at
FROM dwh.etl_control c
ORDER BY c.job_codigo;

-- ---------------------------------------------------------------------------
-- Permisos
-- ---------------------------------------------------------------------------
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA dwh FROM PUBLIC;
GRANT USAGE ON SCHEMA dwh TO authenticated, service_role;
GRANT SELECT ON ALL TABLES IN SCHEMA dwh TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION dwh.fn_etl_run_all() TO service_role;
GRANT EXECUTE ON FUNCTION dwh.fn_etl_refresh_dims() TO service_role;
GRANT EXECUTE ON FUNCTION dwh.fn_etl_incremental_fact_tickets() TO service_role;
GRANT EXECUTE ON FUNCTION dwh.fn_etl_incremental_fact_pagos() TO service_role;
GRANT EXECUTE ON FUNCTION dwh.fn_etl_populate_dim_tiempo(date, date) TO service_role;
GRANT EXECUTE ON FUNCTION dwh.fn_etl_populate_dim_hora() TO service_role;
