-- ══════════════════════════════════════════
-- ONLYPARK · 014 · Bitácoras CORE (parametrizables)
-- ══════════════════════════════════════════
-- Requiere 002-013.

-- ── Configuración por estacionamiento ─────
CREATE TABLE IF NOT EXISTS cfg_bitacora (
  cfg_bitacora_id    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  estacionamiento_id UUID NOT NULL REFERENCES estacionamientos(estacionamiento_id),
  tipo_bitacora_id   UUID NOT NULL REFERENCES cat_tipo_bitacora(tipo_bitacora_id),
  habilitada         BOOLEAN NOT NULL DEFAULT true,
  retencion_dias     INT NOT NULL DEFAULT 365,
  muestreo_pct       NUMERIC(5,2) NOT NULL DEFAULT 100 CHECK (muestreo_pct BETWEEN 0 AND 100),
  updated_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_by         UUID REFERENCES perfiles_usuario(perfil_id),
  UNIQUE (estacionamiento_id, tipo_bitacora_id)
);

-- ── log_evento base (particionado por mes) ─
CREATE TABLE IF NOT EXISTS log_evento (
  log_id             BIGSERIAL,
  tipo_bitacora_id   UUID NOT NULL REFERENCES cat_tipo_bitacora(tipo_bitacora_id),
  subtipo            TEXT NOT NULL,
  estacionamiento_id UUID REFERENCES estacionamientos(estacionamiento_id),
  perfil_id          UUID REFERENCES perfiles_usuario(perfil_id),
  sesion_id          UUID REFERENCES sesiones(sesion_id),
  ip                 INET,
  user_agent         TEXT,
  ruta               TEXT,
  descripcion        TEXT,
  payload            JSONB,
  ocurrido_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (log_id, ocurrido_at)
) PARTITION BY RANGE (ocurrido_at);

-- Particiones iniciales (12 meses desde 2026-07). Automatizar via job después.
DO $$
DECLARE
  d DATE := DATE '2026-07-01';
  next_d DATE;
  part_name TEXT;
BEGIN
  FOR i IN 0..17 LOOP
    next_d := (d + (i || ' months')::interval)::date;
    part_name := 'log_evento_' || to_char(next_d, 'YYYY_MM');
    IF NOT EXISTS (SELECT 1 FROM pg_class WHERE relname = part_name) THEN
      EXECUTE format(
        'CREATE TABLE %I PARTITION OF log_evento FOR VALUES FROM (%L) TO (%L);',
        part_name, next_d, (next_d + interval '1 month')::date
      );
    END IF;
  END LOOP;
END $$;

CREATE INDEX IF NOT EXISTS idx_log_tipo_ocur   ON log_evento(tipo_bitacora_id, ocurrido_at DESC);
CREATE INDEX IF NOT EXISTS idx_log_perfil_ocur ON log_evento(perfil_id, ocurrido_at DESC);
CREATE INDEX IF NOT EXISTS idx_log_estac_ocur  ON log_evento(estacionamiento_id, ocurrido_at DESC);
CREATE INDEX IF NOT EXISTS idx_log_subtipo     ON log_evento(subtipo);

-- ── Helper: registrar evento respetando config/muestreo ─
CREATE OR REPLACE FUNCTION fn_log(
  p_tipo_codigo         TEXT,
  p_subtipo             TEXT,
  p_estacionamiento_id  UUID,
  p_payload             JSONB DEFAULT NULL,
  p_descripcion         TEXT DEFAULT NULL,
  p_sesion_id           UUID DEFAULT NULL
) RETURNS VOID LANGUAGE plpgsql AS $$
DECLARE
  v_tipo UUID;
  v_habilitada BOOLEAN;
  v_muestreo NUMERIC;
BEGIN
  SELECT tipo_bitacora_id INTO v_tipo
  FROM cat_tipo_bitacora WHERE codigo = p_tipo_codigo AND activo;
  IF v_tipo IS NULL THEN RETURN; END IF;

  SELECT habilitada, muestreo_pct INTO v_habilitada, v_muestreo
  FROM cfg_bitacora
  WHERE estacionamiento_id = p_estacionamiento_id AND tipo_bitacora_id = v_tipo;

  -- Default: habilitada al 100% si no hay config aún
  IF NOT COALESCE(v_habilitada, true) THEN RETURN; END IF;
  IF random() * 100 > COALESCE(v_muestreo, 100) THEN RETURN; END IF;

  INSERT INTO log_evento
    (tipo_bitacora_id, subtipo, estacionamiento_id, perfil_id, sesion_id, payload, descripcion)
  VALUES
    (v_tipo, p_subtipo, p_estacionamiento_id, fn_perfil_actual(), p_sesion_id, p_payload, p_descripcion);
END; $$;
