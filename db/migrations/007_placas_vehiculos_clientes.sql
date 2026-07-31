-- ══════════════════════════════════════════
-- ONLYPARK · 007 · Placas, vehículos, clientes
-- ══════════════════════════════════════════
-- La placa es entidad estratégica de primer nivel. Requiere 002-006.

-- ── Placas (únicas por país) ──────────────
CREATE TABLE IF NOT EXISTS placas (
  placa_id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  pais_id          UUID NOT NULL REFERENCES cat_pais(pais_id),
  numero           CITEXT NOT NULL,
  formato_original TEXT,
  estado_emisor    TEXT,
  activa           BOOLEAN NOT NULL DEFAULT true,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (pais_id, numero)
);
CREATE INDEX IF NOT EXISTS idx_placa_numero_trgm ON placas USING gin (numero gin_trgm_ops);

-- ── Clientes ──────────────────────────────
CREATE TABLE IF NOT EXISTS clientes (
  cliente_id      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id      UUID NOT NULL REFERENCES empresas(empresa_id),
  tipo_cliente_id UUID REFERENCES cat_tipo_cliente(tipo_cliente_id),
  nombre          TEXT NOT NULL,
  apellidos       TEXT,
  razon_social    TEXT,
  rfc             TEXT,
  email           CITEXT,
  telefono        TEXT,
  whatsapp        TEXT,
  perfil_id       UUID REFERENCES perfiles_usuario(perfil_id),
  activo          BOOLEAN NOT NULL DEFAULT true,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_by      UUID REFERENCES perfiles_usuario(perfil_id),
  updated_by      UUID REFERENCES perfiles_usuario(perfil_id)
);
CREATE INDEX IF NOT EXISTS idx_clientes_empresa ON clientes(empresa_id);
CREATE INDEX IF NOT EXISTS idx_clientes_email   ON clientes(email);
CREATE INDEX IF NOT EXISTS idx_clientes_nombre_trgm ON clientes USING gin (nombre gin_trgm_ops);

-- ── Vehículos ─────────────────────────────
CREATE TABLE IF NOT EXISTS vehiculos (
  vehiculo_id      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  cliente_id       UUID REFERENCES clientes(cliente_id),
  tipo_vehiculo_id UUID NOT NULL REFERENCES cat_tipo_vehiculo(tipo_vehiculo_id),
  marca            TEXT,
  modelo           TEXT,
  anio             INT,
  color            TEXT,
  num_serie        TEXT,
  notas            TEXT,
  activo           BOOLEAN NOT NULL DEFAULT true,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_vehiculos_cliente ON vehiculos(cliente_id);

-- ── Vínculo placa ↔ vehículo con historial ─
CREATE TABLE IF NOT EXISTS vinculos_placa_vehiculo (
  vinculo_id    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  placa_id      UUID NOT NULL REFERENCES placas(placa_id),
  vehiculo_id   UUID NOT NULL REFERENCES vehiculos(vehiculo_id),
  vigente_desde DATE NOT NULL DEFAULT CURRENT_DATE,
  vigente_hasta DATE,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT vpv_no_solape EXCLUDE USING gist (
    placa_id WITH =,
    daterange(vigente_desde, COALESCE(vigente_hasta, 'infinity'::date), '[)') WITH &&
  )
);
CREATE INDEX IF NOT EXISTS idx_vpv_placa    ON vinculos_placa_vehiculo(placa_id);
CREATE INDEX IF NOT EXISTS idx_vpv_vehiculo ON vinculos_placa_vehiculo(vehiculo_id);

-- ── Vista: vehículo vigente por placa ─────
CREATE OR REPLACE VIEW v_placa_vehiculo_vigente AS
SELECT
  p.placa_id, p.numero, p.pais_id,
  v.vehiculo_id, v.marca, v.modelo, v.color, v.anio, v.tipo_vehiculo_id,
  c.cliente_id, c.nombre AS cliente_nombre, c.empresa_id
FROM placas p
JOIN vinculos_placa_vehiculo vpv
  ON vpv.placa_id = p.placa_id
  AND (vpv.vigente_hasta IS NULL OR vpv.vigente_hasta >= CURRENT_DATE)
  AND vpv.vigente_desde <= CURRENT_DATE
JOIN vehiculos v ON v.vehiculo_id = vpv.vehiculo_id
LEFT JOIN clientes c ON c.cliente_id = v.cliente_id
WHERE p.activa AND v.activo;
