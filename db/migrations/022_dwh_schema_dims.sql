-- ============================================================================
-- DWH v1 — Parte 1: esquema, control ETL, dimensiones
-- Aislado en schema `dwh` (dashboards NUNCA consultan public directo).
-- ============================================================================

CREATE SCHEMA IF NOT EXISTS dwh;

-- ---------------------------------------------------------------------------
-- Control ETL
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS dwh.etl_control (
  etl_control_id   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  job_codigo       text NOT NULL UNIQUE,
  descripcion      text,
  last_watermark   timestamptz,
  last_run_at      timestamptz,
  last_status      text,
  last_rows_in     integer,
  last_rows_out    integer,
  activo           boolean NOT NULL DEFAULT true,
  created_at       timestamptz NOT NULL DEFAULT NOW(),
  updated_at       timestamptz NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS dwh.log_etl_ejecucion (
  log_etl_id       uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  job_codigo       text NOT NULL,
  inicio_at        timestamptz NOT NULL DEFAULT NOW(),
  fin_at           timestamptz,
  duracion_ms      integer,
  estado           text NOT NULL CHECK (estado IN ('ejecutando','finalizado','error','reprocesando','pendiente')),
  rows_in          integer,
  rows_out         integer,
  rows_rechazados  integer,
  watermark_desde  timestamptz,
  watermark_hasta  timestamptz,
  mensaje          text,
  detalle          jsonb
);
CREATE INDEX IF NOT EXISTS ix_log_etl_job_inicio ON dwh.log_etl_ejecucion(job_codigo, inicio_at DESC);

-- ---------------------------------------------------------------------------
-- Dimensiones
-- ---------------------------------------------------------------------------

-- dim_tiempo (grano: día). PK como YYYYMMDD int, más columnas usables.
CREATE TABLE IF NOT EXISTS dwh.dim_tiempo (
  fecha_id         integer PRIMARY KEY,             -- YYYYMMDD
  fecha            date NOT NULL UNIQUE,
  anio             smallint NOT NULL,
  trimestre        smallint NOT NULL,
  mes              smallint NOT NULL,
  mes_nombre       text NOT NULL,
  semana_iso       smallint NOT NULL,
  dia              smallint NOT NULL,
  dia_semana       smallint NOT NULL,               -- 1=lunes ... 7=domingo
  dia_semana_nombre text NOT NULL,
  es_fin_semana    boolean NOT NULL,
  es_feriado       boolean NOT NULL DEFAULT false,
  anio_mes         integer NOT NULL,                -- YYYYMM
  yyyymmdd         text NOT NULL
);

-- dim_hora (0..23), útil para heatmaps de ocupación
CREATE TABLE IF NOT EXISTS dwh.dim_hora (
  hora_id          smallint PRIMARY KEY,            -- 0..23
  hora_texto       text NOT NULL,                   -- '00:00', '01:00', ...
  franja           text NOT NULL                    -- madrugada/mañana/tarde/noche
);

-- dim_empresa (desnormalizada con grupo)
CREATE TABLE IF NOT EXISTS dwh.dim_empresa (
  empresa_sk       bigserial PRIMARY KEY,
  empresa_id       uuid NOT NULL UNIQUE,
  empresa_codigo   text NOT NULL,
  empresa_nombre   text NOT NULL,
  grupo_id         uuid NOT NULL,
  grupo_codigo     text NOT NULL,
  grupo_nombre     text NOT NULL,
  activo           boolean NOT NULL,
  actualizado_at   timestamptz NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS ix_dim_empresa_grupo ON dwh.dim_empresa(grupo_id);

-- dim_estacionamiento (SCD tipo 1, con jerarquía denormalizada permitida en DWH)
CREATE TABLE IF NOT EXISTS dwh.dim_estacionamiento (
  estacionamiento_sk uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  estacionamiento_id uuid NOT NULL UNIQUE,
  estacionamiento_codigo text NOT NULL,
  estacionamiento_nombre text NOT NULL,
  capacidad_total    integer,
  sucursal_id        uuid NOT NULL,
  sucursal_codigo    text NOT NULL,
  sucursal_nombre    text NOT NULL,
  empresa_id         uuid NOT NULL,
  empresa_codigo     text NOT NULL,
  empresa_nombre     text NOT NULL,
  grupo_id           uuid NOT NULL,
  grupo_codigo       text NOT NULL,
  grupo_nombre       text NOT NULL,
  pais_iso2          text,
  timezone_iana      text,
  activo             boolean NOT NULL,
  actualizado_at     timestamptz NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS ix_dim_est_empresa ON dwh.dim_estacionamiento(empresa_id);
CREATE INDEX IF NOT EXISTS ix_dim_est_grupo   ON dwh.dim_estacionamiento(grupo_id);

-- dim_tipo_sesion
CREATE TABLE IF NOT EXISTS dwh.dim_tipo_sesion (
  tipo_sesion_sk    bigserial PRIMARY KEY,
  tipo_sesion_id    uuid NOT NULL UNIQUE,
  codigo            text NOT NULL,
  nombre            text NOT NULL,
  actualizado_at    timestamptz NOT NULL DEFAULT NOW()
);

-- dim_metodo_pago
CREATE TABLE IF NOT EXISTS dwh.dim_metodo_pago (
  metodo_pago_sk    bigserial PRIMARY KEY,
  metodo_pago_id    uuid NOT NULL UNIQUE,
  codigo            text NOT NULL,
  nombre            text NOT NULL,
  actualizado_at    timestamptz NOT NULL DEFAULT NOW()
);

-- dim_usuario (perfil operativo — cajeros, supervisores)
CREATE TABLE IF NOT EXISTS dwh.dim_usuario (
  usuario_sk        bigserial PRIMARY KEY,
  perfil_id         uuid NOT NULL UNIQUE,
  nombre_completo   text,
  email             text,
  activo            boolean NOT NULL,
  actualizado_at    timestamptz NOT NULL DEFAULT NOW()
);
