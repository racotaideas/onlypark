-- ══════════════════════════════════════════
-- ONLYPARK · 002 · Catálogos globales del sistema
-- ══════════════════════════════════════════
-- Sin FK a empresa. Solo Super Admin puede editar.
-- Idempotente. Requiere 001.

-- ── Países ────────────────────────────────
CREATE TABLE IF NOT EXISTS cat_pais (
  pais_id     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  codigo_iso2 TEXT NOT NULL UNIQUE,
  codigo_iso3 TEXT NOT NULL UNIQUE,
  nombre      TEXT NOT NULL,
  activo      BOOLEAN NOT NULL DEFAULT true
);

-- ── Monedas ───────────────────────────────
CREATE TABLE IF NOT EXISTS cat_moneda (
  moneda_id   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  codigo_iso  TEXT NOT NULL UNIQUE,
  nombre      TEXT NOT NULL,
  simbolo     TEXT NOT NULL,
  decimales   INT NOT NULL DEFAULT 2,
  activo      BOOLEAN NOT NULL DEFAULT true
);

-- ── Zonas horarias ────────────────────────
CREATE TABLE IF NOT EXISTS cat_timezone (
  timezone_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  codigo      TEXT NOT NULL UNIQUE,
  nombre      TEXT NOT NULL,
  offset_min  INT NOT NULL,
  activo      BOOLEAN NOT NULL DEFAULT true
);

-- ── Módulos comercializables ──────────────
CREATE TABLE IF NOT EXISTS cat_modulo (
  modulo_id   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  codigo      TEXT NOT NULL UNIQUE,
  nombre      TEXT NOT NULL,
  descripcion TEXT,
  activo      BOOLEAN NOT NULL DEFAULT true
);

-- ── Roles del sistema ─────────────────────
CREATE TABLE IF NOT EXISTS cat_rol (
  rol_id      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  codigo      TEXT NOT NULL UNIQUE,
  nombre      TEXT NOT NULL,
  descripcion TEXT,
  nivel       INT NOT NULL,
  activo      BOOLEAN NOT NULL DEFAULT true
);

-- ── Permisos atómicos ─────────────────────
CREATE TABLE IF NOT EXISTS cat_permiso (
  permiso_id  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  codigo      TEXT NOT NULL UNIQUE,
  nombre      TEXT NOT NULL,
  descripcion TEXT,
  modulo_id   UUID REFERENCES cat_modulo(modulo_id),
  activo      BOOLEAN NOT NULL DEFAULT true
);

-- ── Rol ↔ Permiso ─────────────────────────
CREATE TABLE IF NOT EXISTS cat_rol_permiso (
  rol_id     UUID NOT NULL REFERENCES cat_rol(rol_id) ON DELETE CASCADE,
  permiso_id UUID NOT NULL REFERENCES cat_permiso(permiso_id) ON DELETE CASCADE,
  PRIMARY KEY (rol_id, permiso_id)
);

-- ── Planes comerciales ────────────────────
CREATE TABLE IF NOT EXISTS cat_plan (
  plan_id     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  codigo      TEXT NOT NULL UNIQUE,
  nombre      TEXT NOT NULL,
  descripcion TEXT,
  precio_base NUMERIC(14,4),
  moneda_id   UUID REFERENCES cat_moneda(moneda_id),
  activo      BOOLEAN NOT NULL DEFAULT true
);

-- ── Tipos de límite ───────────────────────
CREATE TABLE IF NOT EXISTS cat_tipo_limite (
  tipo_limite_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  codigo         TEXT NOT NULL UNIQUE,
  nombre         TEXT NOT NULL,
  activo         BOOLEAN NOT NULL DEFAULT true
);

-- ── Métodos de pago genéricos ─────────────
CREATE TABLE IF NOT EXISTS cat_metodo_pago (
  metodo_pago_id      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  codigo              TEXT NOT NULL UNIQUE,
  nombre              TEXT NOT NULL,
  requiere_referencia BOOLEAN NOT NULL DEFAULT false,
  activo              BOOLEAN NOT NULL DEFAULT true
);

-- ── Tipos de vehículo ─────────────────────
CREATE TABLE IF NOT EXISTS cat_tipo_vehiculo (
  tipo_vehiculo_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  codigo           TEXT NOT NULL UNIQUE,
  nombre           TEXT NOT NULL,
  activo           BOOLEAN NOT NULL DEFAULT true
);

-- ── Tipos de bitácora ─────────────────────
CREATE TABLE IF NOT EXISTS cat_tipo_bitacora (
  tipo_bitacora_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  codigo           TEXT NOT NULL UNIQUE,
  nombre           TEXT NOT NULL,
  descripcion      TEXT,
  activo           BOOLEAN NOT NULL DEFAULT true
);

-- ── Estados por dominio ───────────────────
CREATE TABLE IF NOT EXISTS cat_estado_sesion (
  estado_sesion_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  codigo           TEXT NOT NULL UNIQUE,
  nombre           TEXT NOT NULL,
  es_final         BOOLEAN NOT NULL DEFAULT false,
  color_hex        TEXT,
  activo           BOOLEAN NOT NULL DEFAULT true
);

CREATE TABLE IF NOT EXISTS cat_estado_pago (
  estado_pago_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  codigo         TEXT NOT NULL UNIQUE,
  nombre         TEXT NOT NULL,
  es_final       BOOLEAN NOT NULL DEFAULT false,
  activo         BOOLEAN NOT NULL DEFAULT true
);

CREATE TABLE IF NOT EXISTS cat_estado_pension (
  estado_pension_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  codigo            TEXT NOT NULL UNIQUE,
  nombre            TEXT NOT NULL,
  activo            BOOLEAN NOT NULL DEFAULT true
);

CREATE TABLE IF NOT EXISTS cat_estado_licencia (
  estado_licencia_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  codigo             TEXT NOT NULL UNIQUE,
  nombre             TEXT NOT NULL,
  activo             BOOLEAN NOT NULL DEFAULT true
);

CREATE TABLE IF NOT EXISTS cat_estado_movimiento_monedero (
  estado_mm_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  codigo       TEXT NOT NULL UNIQUE,
  nombre       TEXT NOT NULL,
  activo       BOOLEAN NOT NULL DEFAULT true
);

-- ── Tipos de movimiento de monedero ───────
CREATE TABLE IF NOT EXISTS cat_tipo_movimiento_monedero (
  tipo_mm_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  codigo     TEXT NOT NULL UNIQUE,
  nombre     TEXT NOT NULL,
  signo      INT NOT NULL CHECK (signo IN (-1, 1)),
  activo     BOOLEAN NOT NULL DEFAULT true
);
