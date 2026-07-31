-- ══════════════════════════════════════════
-- ONLYPARK · 013 · ONLYPROMO ENGINE
-- ══════════════════════════════════════════
-- Requiere 002-012.

-- ── Locales anunciantes ───────────────────
CREATE TABLE IF NOT EXISTS locales_anunciantes (
  local_id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  estacionamiento_id UUID NOT NULL REFERENCES estacionamientos(estacionamiento_id),
  nombre             TEXT NOT NULL,
  numero_local       TEXT,
  categoria          TEXT,
  contacto           TEXT,
  telefono           TEXT,
  logo_url           TEXT,
  activo             BOOLEAN NOT NULL DEFAULT true,
  created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at         TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_locales_estac ON locales_anunciantes(estacionamiento_id);

-- ── Campañas ──────────────────────────────
CREATE TABLE IF NOT EXISTS campanas (
  campana_id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  estacionamiento_id   UUID NOT NULL REFERENCES estacionamientos(estacionamiento_id),
  local_id             UUID REFERENCES locales_anunciantes(local_id),
  tipo_promocion_id    UUID NOT NULL REFERENCES cat_tipo_promocion(tipo_promocion_id),
  nombre               TEXT NOT NULL,
  titulo_promo         TEXT NOT NULL,
  texto_promo          TEXT NOT NULL,
  valor_promo          TEXT,
  qr_url               TEXT,
  logo_url             TEXT,
  vigencia_desde       DATE NOT NULL,
  vigencia_hasta       DATE NOT NULL,
  hora_desde           TIME DEFAULT '00:00',
  hora_hasta           TIME DEFAULT '23:59',
  prioridad            INT NOT NULL DEFAULT 100,
  max_impresiones      INT,
  estado               TEXT NOT NULL DEFAULT 'activa'
                        CHECK (estado IN ('borrador','programada','activa','pausada','terminada')),
  presupuesto_impactos INT,
  costo_por_impacto    NUMERIC(14,4),
  notas                TEXT,
  campana_origen_id    UUID REFERENCES campanas(campana_id),
  creado_por           UUID REFERENCES perfiles_usuario(perfil_id),
  created_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
  CHECK (vigencia_hasta >= vigencia_desde)
);
CREATE INDEX IF NOT EXISTS idx_camp_estac_estado ON campanas(estacionamiento_id, estado);
CREATE INDEX IF NOT EXISTS idx_camp_vigencia     ON campanas(vigencia_desde, vigencia_hasta);
CREATE INDEX IF NOT EXISTS idx_camp_local        ON campanas(local_id) WHERE local_id IS NOT NULL;

-- ── Público objetivo (M2M con tipos de sesión) ─
CREATE TABLE IF NOT EXISTS campana_tipos_sesion (
  campana_id     UUID NOT NULL REFERENCES campanas(campana_id) ON DELETE CASCADE,
  tipo_sesion_id UUID NOT NULL REFERENCES cat_tipo_sesion(tipo_sesion_id),
  PRIMARY KEY (campana_id, tipo_sesion_id)
);

-- ── Franjas aplicables (M2M) ──────────────
CREATE TABLE IF NOT EXISTS campana_franjas (
  campana_id UUID NOT NULL REFERENCES campanas(campana_id) ON DELETE CASCADE,
  franja_id  UUID NOT NULL REFERENCES cat_franja(franja_id),
  PRIMARY KEY (campana_id, franja_id)
);

-- ── Días de la semana (M2M) ───────────────
CREATE TABLE IF NOT EXISTS campana_dias_semana (
  campana_id UUID NOT NULL REFERENCES campanas(campana_id) ON DELETE CASCADE,
  dia_semana INT NOT NULL CHECK (dia_semana BETWEEN 1 AND 7),
  PRIMARY KEY (campana_id, dia_semana)
);

-- ── Reglas de impresión ───────────────────
CREATE TABLE IF NOT EXISTS campana_reglas_impresion (
  regla_imp_id  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  campana_id    UUID NOT NULL REFERENCES campanas(campana_id) ON DELETE CASCADE,
  tipo_regla_id UUID NOT NULL REFERENCES cat_tipo_regla_impresion(tipo_regla_id),
  cada_x        INT,
  porcentaje    NUMERIC(5,2) CHECK (porcentaje IS NULL OR (porcentaje BETWEEN 0 AND 100)),
  parametros    JSONB,
  activa        BOOLEAN NOT NULL DEFAULT true
);
CREATE INDEX IF NOT EXISTS idx_regla_imp_camp ON campana_reglas_impresion(campana_id) WHERE activa;

-- ── Impresiones (impactos publicitarios) ──
CREATE TABLE IF NOT EXISTS impresiones_campana (
  impresion_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  campana_id   UUID NOT NULL REFERENCES campanas(campana_id),
  sesion_id    UUID NOT NULL REFERENCES sesiones(sesion_id),
  cajero_id    UUID REFERENCES perfiles_usuario(perfil_id),
  momento      TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_imp_camp_momento ON impresiones_campana(campana_id, momento DESC);
CREATE INDEX IF NOT EXISTS idx_imp_sesion       ON impresiones_campana(sesion_id);

-- ── Conversiones (uso efectivo de la promoción) ─
CREATE TABLE IF NOT EXISTS conversiones_campana (
  conversion_id   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  impresion_id    UUID NOT NULL REFERENCES impresiones_campana(impresion_id),
  monto_venta     NUMERIC(14,4),
  monto_descuento NUMERIC(14,4),
  local_id        UUID REFERENCES locales_anunciantes(local_id),
  registrada_por  UUID REFERENCES perfiles_usuario(perfil_id),
  momento         TIMESTAMPTZ NOT NULL DEFAULT now(),
  notas           TEXT,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_conv_impresion ON conversiones_campana(impresion_id);
