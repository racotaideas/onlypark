-- ══════════════════════════════════════════
-- ONLYPARK · 009 · Motor de tarifas
-- ══════════════════════════════════════════
-- Políticas + reglas + historial SCD2. Requiere 002-008.

-- ── Política tarifaria (contenedor vigente) ─
CREATE TABLE IF NOT EXISTS politicas_tarifarias (
  politica_id        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  estacionamiento_id UUID NOT NULL REFERENCES estacionamientos(estacionamiento_id),
  tipo_sesion_id     UUID REFERENCES cat_tipo_sesion(tipo_sesion_id),  -- NULL = default del estacionamiento
  nombre             TEXT NOT NULL,
  vigente_desde      DATE NOT NULL,
  vigente_hasta      DATE,
  motivo_cambio      TEXT,
  activo             BOOLEAN NOT NULL DEFAULT true,
  created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_by         UUID REFERENCES perfiles_usuario(perfil_id),
  CONSTRAINT politica_no_solape EXCLUDE USING gist (
    estacionamiento_id WITH =,
    (COALESCE(tipo_sesion_id::text, '__default__')) WITH =,
    daterange(vigente_desde, COALESCE(vigente_hasta, 'infinity'::date), '[)') WITH &&
  ) WHERE (activo)
);
CREATE INDEX IF NOT EXISTS idx_polit_estac_vig ON politicas_tarifarias(estacionamiento_id, vigente_desde DESC);

-- ── Reglas tarifarias dentro de una política ─
CREATE TABLE IF NOT EXISTS reglas_tarifarias (
  regla_id       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  politica_id    UUID NOT NULL REFERENCES politicas_tarifarias(politica_id) ON DELETE CASCADE,
  tipo_tarifa_id UUID NOT NULL REFERENCES cat_tipo_tarifa(tipo_tarifa_id),
  monto          NUMERIC(14,4),
  fraccion_min   INT,
  tolerancia_min INT,
  hora_inicio    TIME,
  hora_fin       TIME,
  dias_semana    INT[],
  prioridad      INT NOT NULL DEFAULT 100,
  parametros     JSONB,
  activa         BOOLEAN NOT NULL DEFAULT true,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_regla_politica ON reglas_tarifarias(politica_id);
CREATE INDEX IF NOT EXISTS idx_regla_tipo     ON reglas_tarifarias(tipo_tarifa_id);

-- ── Historial de cambios de monto (SCD2 fino) ─
CREATE TABLE IF NOT EXISTS tarifas_historico (
  tarifa_hist_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  regla_id       UUID NOT NULL REFERENCES reglas_tarifarias(regla_id),
  monto_previo   NUMERIC(14,4),
  monto_nuevo    NUMERIC(14,4) NOT NULL,
  vigente_desde  DATE NOT NULL,
  vigente_hasta  DATE,
  motivo_cambio  TEXT,
  cambiado_por   UUID REFERENCES perfiles_usuario(perfil_id),
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_thist_regla_desde ON tarifas_historico(regla_id, vigente_desde DESC);

-- ── FKs diferidas de sesiones hacia política/histórico ─
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='sesiones_politica_fk') THEN
    ALTER TABLE sesiones
      ADD CONSTRAINT sesiones_politica_fk FOREIGN KEY (politica_tarifaria_id) REFERENCES politicas_tarifarias(politica_id);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='sesiones_tarifa_hist_fk') THEN
    ALTER TABLE sesiones
      ADD CONSTRAINT sesiones_tarifa_hist_fk FOREIGN KEY (tarifa_hist_id) REFERENCES tarifas_historico(tarifa_hist_id);
  END IF;
END $$;

-- ── Stub de cálculo de importe (implementación real en fase posterior) ─
CREATE OR REPLACE FUNCTION fn_calcular_importe_sesion(p_sesion_id UUID)
RETURNS NUMERIC LANGUAGE plpgsql AS $$
DECLARE
  v_importe NUMERIC := 0;
BEGIN
  -- TODO: resolver política vigente (estac, tipo_sesion), recorrer reglas por prioridad,
  -- aplicar hora/fracción/tolerancia/mínima/máxima/nocturna, escribir importe_calculado.
  RAISE NOTICE 'fn_calcular_importe_sesion: pendiente de implementar para sesion %', p_sesion_id;
  RETURN v_importe;
END; $$;

-- ── Cambiar tarifa (cierra la anterior, abre la nueva) ─
CREATE OR REPLACE FUNCTION fn_cambiar_tarifa(
  p_regla_id     UUID,
  p_monto_nuevo  NUMERIC,
  p_vigente_desde DATE,
  p_motivo       TEXT DEFAULT NULL
) RETURNS UUID LANGUAGE plpgsql AS $$
DECLARE
  v_hist_id UUID;
  v_monto_actual NUMERIC;
BEGIN
  SELECT monto INTO v_monto_actual FROM reglas_tarifarias WHERE regla_id = p_regla_id FOR UPDATE;
  IF v_monto_actual IS NULL THEN RAISE EXCEPTION 'Regla % no existe', p_regla_id; END IF;

  -- Cerrar histórico vigente anterior
  UPDATE tarifas_historico SET vigente_hasta = p_vigente_desde - 1
   WHERE regla_id = p_regla_id AND vigente_hasta IS NULL;

  -- Insertar nuevo histórico
  INSERT INTO tarifas_historico (regla_id, monto_previo, monto_nuevo, vigente_desde, motivo_cambio, cambiado_por)
  VALUES (p_regla_id, v_monto_actual, p_monto_nuevo, p_vigente_desde, p_motivo, fn_perfil_actual())
  RETURNING tarifa_hist_id INTO v_hist_id;

  -- Actualizar regla con el monto vigente
  UPDATE reglas_tarifarias SET monto = p_monto_nuevo, updated_at = now() WHERE regla_id = p_regla_id;

  RETURN v_hist_id;
END; $$;
