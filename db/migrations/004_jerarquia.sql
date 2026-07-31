-- ══════════════════════════════════════════
-- ONLYPARK · 004 · Jerarquía multi-tenant
-- ══════════════════════════════════════════
-- grupos_empresariales → empresas → sucursales → estacionamientos
-- Requiere 002 y 003.

-- ── Grupo empresarial ────────────────────
CREATE TABLE IF NOT EXISTS grupos_empresariales (
  grupo_id   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  codigo     TEXT NOT NULL UNIQUE,
  nombre     TEXT NOT NULL,
  logo_url   TEXT,
  activo     BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_by UUID,   -- FK diferida a perfiles_usuario (005)
  updated_by UUID
);

-- ── Empresa ──────────────────────────────
CREATE TABLE IF NOT EXISTS empresas (
  empresa_id       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  grupo_id         UUID NOT NULL REFERENCES grupos_empresariales(grupo_id),
  pais_id          UUID NOT NULL REFERENCES cat_pais(pais_id),
  moneda_id        UUID NOT NULL REFERENCES cat_moneda(moneda_id),
  codigo           TEXT NOT NULL,
  razon_social     TEXT NOT NULL,
  nombre_comercial TEXT,
  rfc              TEXT,
  regimen_fiscal   TEXT,
  telefono         TEXT,
  email            CITEXT,
  logo_url         TEXT,
  activo           BOOLEAN NOT NULL DEFAULT true,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_by       UUID,
  updated_by       UUID,
  UNIQUE (grupo_id, codigo)
);
CREATE INDEX IF NOT EXISTS idx_empresas_grupo  ON empresas(grupo_id);
CREATE INDEX IF NOT EXISTS idx_empresas_activo ON empresas(activo);

-- ── Sucursal ─────────────────────────────
CREATE TABLE IF NOT EXISTS sucursales (
  sucursal_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id  UUID NOT NULL REFERENCES empresas(empresa_id),
  codigo      TEXT NOT NULL,
  nombre      TEXT NOT NULL,
  direccion   TEXT,
  telefono    TEXT,
  activo      BOOLEAN NOT NULL DEFAULT true,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_by  UUID,
  updated_by  UUID,
  UNIQUE (empresa_id, codigo)
);
CREATE INDEX IF NOT EXISTS idx_sucursales_empresa ON sucursales(empresa_id);

-- ── Estacionamiento ──────────────────────
CREATE TABLE IF NOT EXISTS estacionamientos (
  estacionamiento_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  sucursal_id        UUID NOT NULL REFERENCES sucursales(sucursal_id),
  pais_id            UUID NOT NULL REFERENCES cat_pais(pais_id),
  timezone_id        UUID NOT NULL REFERENCES cat_timezone(timezone_id),
  codigo             TEXT NOT NULL,
  nombre             TEXT NOT NULL,
  descripcion        TEXT,
  capacidad_total    INT NOT NULL CHECK (capacidad_total > 0),
  direccion          TEXT,
  latitud            NUMERIC(9,6),
  longitud           NUMERIC(9,6),
  telefono           TEXT,
  activo             BOOLEAN NOT NULL DEFAULT true,
  created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_by         UUID,
  updated_by         UUID,
  UNIQUE (sucursal_id, codigo)
);
CREATE INDEX IF NOT EXISTS idx_estac_sucursal ON estacionamientos(sucursal_id);
CREATE INDEX IF NOT EXISTS idx_estac_activo   ON estacionamientos(activo);

-- ── Vista denormalizada de jerarquía ─────
CREATE OR REPLACE VIEW v_jerarquia_estacionamientos AS
SELECT
  e.estacionamiento_id,
  e.codigo   AS estacionamiento_codigo,
  e.nombre   AS estacionamiento_nombre,
  e.capacidad_total,
  e.timezone_id,
  s.sucursal_id, s.codigo AS sucursal_codigo, s.nombre AS sucursal_nombre,
  em.empresa_id, em.codigo AS empresa_codigo, em.razon_social,
  em.pais_id, em.moneda_id,
  g.grupo_id, g.codigo AS grupo_codigo, g.nombre AS grupo_nombre
FROM estacionamientos e
JOIN sucursales s      ON s.sucursal_id = e.sucursal_id
JOIN empresas em       ON em.empresa_id = s.empresa_id
JOIN grupos_empresariales g ON g.grupo_id = em.grupo_id
WHERE e.activo AND s.activo AND em.activo AND g.activo;
