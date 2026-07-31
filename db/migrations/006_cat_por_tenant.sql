-- ══════════════════════════════════════════
-- ONLYPARK · 006 · Catálogos parametrizables por-tenant
-- ══════════════════════════════════════════
-- empresa_id NULL = plantilla global (semilla RANNIX que la empresa hereda).
-- Requiere 004, 005.

-- ── Tipos de sesión (evolución de tipo_boleto) ─
CREATE TABLE IF NOT EXISTS cat_tipo_sesion (
  tipo_sesion_id    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id        UUID REFERENCES empresas(empresa_id),
  codigo            TEXT NOT NULL,
  nombre            TEXT NOT NULL,
  genera_ingreso    BOOLEAN NOT NULL DEFAULT true,
  requiere_pension  BOOLEAN NOT NULL DEFAULT false,
  requiere_empleado BOOLEAN NOT NULL DEFAULT false,
  color_hex         TEXT,
  orden             INT DEFAULT 100,
  activo            BOOLEAN NOT NULL DEFAULT true,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (empresa_id, codigo)
);
-- Unique parcial para plantillas globales (empresa_id NULL) — UNIQUE arriba no cubre NULLs consistentemente
CREATE UNIQUE INDEX IF NOT EXISTS idx_cat_tipo_sesion_global
  ON cat_tipo_sesion(codigo) WHERE empresa_id IS NULL;

-- ── Tipos de tarifa (los 12 del motor) ────
CREATE TABLE IF NOT EXISTS cat_tipo_tarifa (
  tipo_tarifa_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id     UUID REFERENCES empresas(empresa_id),
  codigo         TEXT NOT NULL,
  nombre         TEXT NOT NULL,
  descripcion    TEXT,
  activo         BOOLEAN NOT NULL DEFAULT true,
  UNIQUE (empresa_id, codigo)
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_cat_tipo_tarifa_global
  ON cat_tipo_tarifa(codigo) WHERE empresa_id IS NULL;

-- ── Tipos de cortesía ─────────────────────
CREATE TABLE IF NOT EXISTS cat_tipo_cortesia (
  tipo_cortesia_id      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id            UUID REFERENCES empresas(empresa_id),
  codigo                TEXT NOT NULL,
  nombre                TEXT NOT NULL,
  requiere_autorizacion BOOLEAN NOT NULL DEFAULT false,
  activo                BOOLEAN NOT NULL DEFAULT true,
  UNIQUE (empresa_id, codigo)
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_cat_tipo_cortesia_global
  ON cat_tipo_cortesia(codigo) WHERE empresa_id IS NULL;

-- ── Tipos de descuento ────────────────────
CREATE TABLE IF NOT EXISTS cat_tipo_descuento (
  tipo_descuento_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id        UUID REFERENCES empresas(empresa_id),
  codigo            TEXT NOT NULL,
  nombre            TEXT NOT NULL,
  aplica_a          TEXT NOT NULL CHECK (aplica_a IN ('porcentaje','monto_fijo')),
  activo            BOOLEAN NOT NULL DEFAULT true,
  UNIQUE (empresa_id, codigo)
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_cat_tipo_descuento_global
  ON cat_tipo_descuento(codigo) WHERE empresa_id IS NULL;

-- ── Tipos de cliente ──────────────────────
CREATE TABLE IF NOT EXISTS cat_tipo_cliente (
  tipo_cliente_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id      UUID REFERENCES empresas(empresa_id),
  codigo          TEXT NOT NULL,
  nombre          TEXT NOT NULL,
  activo          BOOLEAN NOT NULL DEFAULT true,
  UNIQUE (empresa_id, codigo)
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_cat_tipo_cliente_global
  ON cat_tipo_cliente(codigo) WHERE empresa_id IS NULL;

-- ── Tipos de pensión ──────────────────────
CREATE TABLE IF NOT EXISTS cat_tipo_pension (
  tipo_pension_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id      UUID REFERENCES empresas(empresa_id),
  codigo          TEXT NOT NULL,
  nombre          TEXT NOT NULL,
  activo          BOOLEAN NOT NULL DEFAULT true,
  UNIQUE (empresa_id, codigo)
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_cat_tipo_pension_global
  ON cat_tipo_pension(codigo) WHERE empresa_id IS NULL;

-- ── Turnos (por estacionamiento) ──────────
CREATE TABLE IF NOT EXISTS cat_turno (
  turno_id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  estacionamiento_id UUID NOT NULL REFERENCES estacionamientos(estacionamiento_id),
  codigo             TEXT NOT NULL,
  nombre             TEXT NOT NULL,
  hora_inicio        TIME NOT NULL,
  hora_fin           TIME NOT NULL,
  activo             BOOLEAN NOT NULL DEFAULT true,
  UNIQUE (estacionamiento_id, codigo)
);

-- ── Franjas horarias (por estacionamiento) ─
CREATE TABLE IF NOT EXISTS cat_franja (
  franja_id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  estacionamiento_id UUID NOT NULL REFERENCES estacionamientos(estacionamiento_id),
  codigo             TEXT NOT NULL,
  nombre             TEXT NOT NULL,
  hora_inicio        TIME NOT NULL,
  hora_fin           TIME NOT NULL,
  color_hex          TEXT,
  activo             BOOLEAN NOT NULL DEFAULT true,
  UNIQUE (estacionamiento_id, codigo)
);

-- ── Tipos de promoción (global) ───────────
CREATE TABLE IF NOT EXISTS cat_tipo_promocion (
  tipo_promocion_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  codigo            TEXT NOT NULL UNIQUE,
  nombre            TEXT NOT NULL,
  activo            BOOLEAN NOT NULL DEFAULT true
);

-- ── Tipos de regla de impresión (global) ──
CREATE TABLE IF NOT EXISTS cat_tipo_regla_impresion (
  tipo_regla_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  codigo        TEXT NOT NULL UNIQUE,
  nombre        TEXT NOT NULL,
  activo        BOOLEAN NOT NULL DEFAULT true
);

-- ══════════════════════════════════════════
-- Semillas de PLANTILLAS globales
-- (empresa_id NULL = disponible para todas las empresas como base)
-- ══════════════════════════════════════════

-- Tipos de sesión (plantilla)
INSERT INTO cat_tipo_sesion (empresa_id, codigo, nombre, genera_ingreso, requiere_pension, requiere_empleado, color_hex, orden) VALUES
  (NULL,'normal',       'Entrada Normal',        true,  false, false, '#0A66C2', 10),
  (NULL,'preferencial', 'Entrada Preferencial',  true,  false, false, '#7B5EA7', 20),
  (NULL,'pensionado',   'Pensionado',            true,  true,  false, '#0D9457', 30),
  (NULL,'empleado',     'Empleado (cortesía)',   false, false, true,  '#888888', 40),
  (NULL,'invitado',     'Invitado',              false, false, false, '#F5A623', 50),
  (NULL,'vip',          'VIP',                   true,  false, false, '#8B0000', 60),
  (NULL,'proveedor',    'Proveedor',             false, false, false, '#4A4A4A', 70),
  (NULL,'evento',       'Evento especial',       true,  false, false, '#FF6B6B', 80),
  (NULL,'cortesia',     'Cortesía (≤tolerancia)',false, false, false, '#6E6E73', 90),
  (NULL,'perdido',      'Boleto perdido',        true,  false, false, '#D93025', 100)
ON CONFLICT DO NOTHING;

-- Tipos de tarifa (los 12)
INSERT INTO cat_tipo_tarifa (empresa_id, codigo, nombre, descripcion) VALUES
  (NULL,'hora','Por hora','Tarifa por hora completa'),
  (NULL,'fraccion','Por fracción','Tarifa por fracción de hora (min configurable)'),
  (NULL,'tolerancia','Tolerancia','Tiempo sin cobro'),
  (NULL,'minima','Tarifa mínima','Cobro mínimo garantizado'),
  (NULL,'maxima','Tarifa máxima','Tope diario/de sesión'),
  (NULL,'nocturna','Nocturna','Aplica en franja nocturna'),
  (NULL,'evento','Por evento','Tarifa plana para evento'),
  (NULL,'preferencial','Preferencial','Tarifa reducida para clientes preferentes'),
  (NULL,'convenio','Por convenio','Tarifa para empresas o entidades con convenio'),
  (NULL,'dia','Por día','Tarifa diaria fija'),
  (NULL,'mensual','Mensual','Tarifa mensual (base para pensiones)'),
  (NULL,'especial','Especial','Tarifa ad-hoc parametrizable')
ON CONFLICT DO NOTHING;

-- Tipos de cortesía (plantilla)
INSERT INTO cat_tipo_cortesia (empresa_id, codigo, nombre, requiere_autorizacion) VALUES
  (NULL,'validacion','Validación de local', false),
  (NULL,'empleado','Empleado', false),
  (NULL,'evento','Evento', true),
  (NULL,'invitado','Invitado autorizado', true),
  (NULL,'tolerancia_auto','Tolerancia automática', false),
  (NULL,'directiva','Autorización directiva', true)
ON CONFLICT DO NOTHING;

-- Tipos de descuento (plantilla)
INSERT INTO cat_tipo_descuento (empresa_id, codigo, nombre, aplica_a) VALUES
  (NULL,'porcentaje_general','Descuento porcentaje', 'porcentaje'),
  (NULL,'monto_fijo','Descuento monto fijo', 'monto_fijo'),
  (NULL,'promocion','Descuento por promoción', 'porcentaje'),
  (NULL,'convenio','Descuento por convenio', 'porcentaje')
ON CONFLICT DO NOTHING;

-- Tipos de cliente (plantilla)
INSERT INTO cat_tipo_cliente (empresa_id, codigo, nombre) VALUES
  (NULL,'individual','Individual'),
  (NULL,'vip','VIP'),
  (NULL,'empresa','Empresa (convenio)'),
  (NULL,'empleado','Empleado'),
  (NULL,'invitado','Invitado'),
  (NULL,'proveedor','Proveedor')
ON CONFLICT DO NOTHING;

-- Tipos de pensión (plantilla)
INSERT INTO cat_tipo_pension (empresa_id, codigo, nombre) VALUES
  (NULL,'dia','Diurna'),
  (NULL,'noche','Nocturna'),
  (NULL,'24h','24 horas'),
  (NULL,'fin_semana','Solo fin de semana'),
  (NULL,'semanal','Semanal')
ON CONFLICT DO NOTHING;

-- Tipos de promoción
INSERT INTO cat_tipo_promocion (codigo, nombre) VALUES
  ('descuento_pct','Descuento porcentaje'),
  ('descuento_fijo','Descuento monto fijo'),
  ('2x1','Promoción 2x1'),
  ('leyenda','Leyenda publicitaria'),
  ('codigo','Código promocional'),
  ('regalo','Regalo con compra')
ON CONFLICT DO NOTHING;

-- Tipos de regla de impresión
INSERT INTO cat_tipo_regla_impresion (codigo, nombre) VALUES
  ('siempre','Siempre'),
  ('aleatorio','Aleatorio'),
  ('cada_x_sesiones','Cada X sesiones'),
  ('porcentaje','Porcentaje de sesiones'),
  ('por_horario','Solo en horario'),
  ('por_dia','Solo en día de la semana'),
  ('por_tipo_sesion','Solo para tipo de sesión'),
  ('presupuesto','Hasta agotar presupuesto')
ON CONFLICT DO NOTHING;
