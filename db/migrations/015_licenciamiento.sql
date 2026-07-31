-- ══════════════════════════════════════════
-- ONLYPARK · 015 · Licenciamiento SaaS
-- ══════════════════════════════════════════
-- Requiere 002-014.

-- ── Plan ↔ módulos incluidos ──────────────
CREATE TABLE IF NOT EXISTS plan_modulos (
  plan_id   UUID NOT NULL REFERENCES cat_plan(plan_id) ON DELETE CASCADE,
  modulo_id UUID NOT NULL REFERENCES cat_modulo(modulo_id),
  PRIMARY KEY (plan_id, modulo_id)
);

-- ── Plan ↔ límites (cajones, usuarios, sucursales, ...) ─
CREATE TABLE IF NOT EXISTS plan_limites (
  plan_id        UUID NOT NULL REFERENCES cat_plan(plan_id) ON DELETE CASCADE,
  tipo_limite_id UUID NOT NULL REFERENCES cat_tipo_limite(tipo_limite_id),
  valor          INT NOT NULL,
  PRIMARY KEY (plan_id, tipo_limite_id)
);

-- ── Licencia por empresa ──────────────────
CREATE TABLE IF NOT EXISTS licencias (
  licencia_id        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id         UUID NOT NULL REFERENCES empresas(empresa_id),
  plan_id            UUID NOT NULL REFERENCES cat_plan(plan_id),
  estado_licencia_id UUID NOT NULL REFERENCES cat_estado_licencia(estado_licencia_id),
  vigencia_desde     DATE NOT NULL,
  vigencia_hasta     DATE NOT NULL,
  precio_pactado     NUMERIC(14,4),
  moneda_id          UUID REFERENCES cat_moneda(moneda_id),
  referencia_venta   TEXT,
  notas              TEXT,
  created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
  CHECK (vigencia_hasta >= vigencia_desde)
);
CREATE INDEX IF NOT EXISTS idx_lic_empresa_vig ON licencias(empresa_id, vigencia_hasta DESC);

-- ── Override de módulos por licencia ──────
CREATE TABLE IF NOT EXISTS licencia_modulo_overrides (
  licencia_id UUID NOT NULL REFERENCES licencias(licencia_id) ON DELETE CASCADE,
  modulo_id   UUID NOT NULL REFERENCES cat_modulo(modulo_id),
  habilitado  BOOLEAN NOT NULL,
  motivo      TEXT,
  PRIMARY KEY (licencia_id, modulo_id)
);

-- ── Vista: módulos efectivamente habilitados por empresa ─
CREATE OR REPLACE VIEW v_empresa_modulos_habilitados AS
WITH lic_vigente AS (
  SELECT l.*, el.codigo AS estado_codigo
  FROM licencias l
  JOIN cat_estado_licencia el ON el.estado_licencia_id = l.estado_licencia_id
  WHERE el.codigo IN ('activa','en_gracia')
    AND CURRENT_DATE BETWEEN l.vigencia_desde AND l.vigencia_hasta
)
-- Módulos del plan, no vetados por override
SELECT DISTINCT
  l.empresa_id, m.modulo_id, m.codigo AS modulo_codigo, m.nombre AS modulo_nombre
FROM lic_vigente l
JOIN plan_modulos pm ON pm.plan_id = l.plan_id
JOIN cat_modulo m    ON m.modulo_id = pm.modulo_id AND m.activo
LEFT JOIN licencia_modulo_overrides lmo
  ON lmo.licencia_id = l.licencia_id AND lmo.modulo_id = m.modulo_id
WHERE COALESCE(lmo.habilitado, true)
UNION
-- Módulos habilitados por override que NO están en el plan
SELECT DISTINCT
  l.empresa_id, m.modulo_id, m.codigo AS modulo_codigo, m.nombre AS modulo_nombre
FROM lic_vigente l
JOIN licencia_modulo_overrides lmo ON lmo.licencia_id = l.licencia_id AND lmo.habilitado
JOIN cat_modulo m ON m.modulo_id = lmo.modulo_id AND m.activo
LEFT JOIN plan_modulos pm ON pm.plan_id = l.plan_id AND pm.modulo_id = m.modulo_id
WHERE pm.plan_id IS NULL;

-- ── Helper: ¿empresa tiene módulo habilitado? ─
CREATE OR REPLACE FUNCTION fn_modulo_habilitado(p_empresa_id UUID, p_codigo_modulo TEXT)
RETURNS BOOLEAN LANGUAGE sql STABLE AS $$
  SELECT EXISTS (
    SELECT 1 FROM v_empresa_modulos_habilitados
    WHERE empresa_id = p_empresa_id AND modulo_codigo = p_codigo_modulo
  );
$$;

-- ══════════════════════════════════════════
-- Semillas: contenido de planes
-- ══════════════════════════════════════════

-- BASIC: caseta + dashboard admin + pensiones + bitácoras
INSERT INTO plan_modulos (plan_id, modulo_id)
SELECT (SELECT plan_id FROM cat_plan WHERE codigo='basic'), m.modulo_id
FROM cat_modulo m
WHERE m.codigo IN ('caseta','dashboard_admin','pensiones','bitacoras','analisis_demanda')
ON CONFLICT DO NOTHING;

-- PROFESSIONAL: todo lo de BASIC + corporativo + promociones + rendimiento cajeros
INSERT INTO plan_modulos (plan_id, modulo_id)
SELECT (SELECT plan_id FROM cat_plan WHERE codigo='professional'), m.modulo_id
FROM cat_modulo m
WHERE m.codigo IN ('caseta','dashboard_admin','dashboard_corporativo','pensiones',
                   'promociones','bitacoras','analisis_demanda','rendimiento_cajeros')
ON CONFLICT DO NOTHING;

-- ENTERPRISE: todo
INSERT INTO plan_modulos (plan_id, modulo_id)
SELECT (SELECT plan_id FROM cat_plan WHERE codigo='enterprise'), m.modulo_id
FROM cat_modulo m
WHERE m.activo
ON CONFLICT DO NOTHING;

-- Límites
INSERT INTO plan_limites (plan_id, tipo_limite_id, valor)
SELECT (SELECT plan_id FROM cat_plan WHERE codigo='basic'),
       (SELECT tipo_limite_id FROM cat_tipo_limite WHERE codigo=c),
       v
FROM (VALUES ('cajones',100),('usuarios',5),('sucursales',1),('estacionamientos',1),('empresas',1))
     AS l(c, v)
ON CONFLICT DO NOTHING;

INSERT INTO plan_limites (plan_id, tipo_limite_id, valor)
SELECT (SELECT plan_id FROM cat_plan WHERE codigo='professional'),
       (SELECT tipo_limite_id FROM cat_tipo_limite WHERE codigo=c),
       v
FROM (VALUES ('cajones',500),('usuarios',25),('sucursales',5),('estacionamientos',10),('empresas',1))
     AS l(c, v)
ON CONFLICT DO NOTHING;

INSERT INTO plan_limites (plan_id, tipo_limite_id, valor)
SELECT (SELECT plan_id FROM cat_plan WHERE codigo='enterprise'),
       (SELECT tipo_limite_id FROM cat_tipo_limite WHERE codigo=c),
       v
FROM (VALUES ('cajones',999999),('usuarios',999999),('sucursales',999999),('estacionamientos',999999),('empresas',999999))
     AS l(c, v)
ON CONFLICT DO NOTHING;
