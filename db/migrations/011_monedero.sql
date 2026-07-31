-- ══════════════════════════════════════════
-- ONLYPARK · 011 · ONLYWALLET (monedero electrónico)
-- ══════════════════════════════════════════
-- Requiere 002-010.

-- ── Monederos (por cliente + moneda) ──────
CREATE TABLE IF NOT EXISTS monederos (
  monedero_id     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  cliente_id      UUID NOT NULL REFERENCES clientes(cliente_id),
  moneda_id       UUID NOT NULL REFERENCES cat_moneda(moneda_id),
  saldo           NUMERIC(14,4) NOT NULL DEFAULT 0,
  saldo_bloqueado NUMERIC(14,4) NOT NULL DEFAULT 0,
  activo          BOOLEAN NOT NULL DEFAULT true,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (cliente_id, moneda_id),
  CHECK (saldo >= 0),
  CHECK (saldo_bloqueado >= 0)
);
CREATE INDEX IF NOT EXISTS idx_monederos_cliente ON monederos(cliente_id);

-- ── Vinculación monedero ↔ placas (M2M) ───
CREATE TABLE IF NOT EXISTS monedero_placas (
  monedero_id  UUID NOT NULL REFERENCES monederos(monedero_id),
  placa_id     UUID NOT NULL REFERENCES placas(placa_id),
  vinculada_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  activo       BOOLEAN NOT NULL DEFAULT true,
  PRIMARY KEY (monedero_id, placa_id)
);
CREATE INDEX IF NOT EXISTS idx_mp_placa ON monedero_placas(placa_id) WHERE activo;

-- ── Movimientos de monedero ───────────────
CREATE TABLE IF NOT EXISTS movimientos_monedero (
  movimiento_id        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  monedero_id          UUID NOT NULL REFERENCES monederos(monedero_id),
  tipo_mm_id           UUID NOT NULL REFERENCES cat_tipo_movimiento_monedero(tipo_mm_id),
  estado_mm_id         UUID NOT NULL REFERENCES cat_estado_movimiento_monedero(estado_mm_id),
  monto                NUMERIC(14,4) NOT NULL CHECK (monto >= 0),
  saldo_pre            NUMERIC(14,4) NOT NULL,
  saldo_post           NUMERIC(14,4) NOT NULL,
  referencia           TEXT,
  sesion_id            UUID REFERENCES sesiones(sesion_id),
  pago_id              UUID REFERENCES pagos(pago_id),
  movimiento_origen_id UUID REFERENCES movimientos_monedero(movimiento_id),
  descripcion          TEXT,
  aplicado_por         UUID REFERENCES perfiles_usuario(perfil_id),
  created_at           TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_mm_monedero_created ON movimientos_monedero(monedero_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_mm_sesion           ON movimientos_monedero(sesion_id) WHERE sesion_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_mm_pago             ON movimientos_monedero(pago_id) WHERE pago_id IS NOT NULL;

-- ── FK diferida de pagos → monederos ──────
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='pagos_monedero_fk') THEN
    ALTER TABLE pagos
      ADD CONSTRAINT pagos_monedero_fk FOREIGN KEY (monedero_id) REFERENCES monederos(monedero_id);
  END IF;
END $$;

-- ── Función atómica: aplicar movimiento y actualizar saldo ─
CREATE OR REPLACE FUNCTION fn_aplicar_movimiento_monedero(
  p_monedero_id    UUID,
  p_tipo_mm_codigo TEXT,
  p_monto          NUMERIC,
  p_referencia     TEXT DEFAULT NULL,
  p_sesion_id      UUID DEFAULT NULL,
  p_pago_id        UUID DEFAULT NULL,
  p_descripcion    TEXT DEFAULT NULL
) RETURNS UUID LANGUAGE plpgsql AS $$
DECLARE
  v_tipo_id     UUID;
  v_signo       INT;
  v_saldo       NUMERIC;
  v_saldo_nuevo NUMERIC;
  v_mov_id      UUID;
  v_estado_aplicado UUID;
BEGIN
  IF p_monto <= 0 THEN
    RAISE EXCEPTION 'El monto debe ser positivo (recibido: %)', p_monto;
  END IF;

  SELECT tipo_mm_id, signo INTO v_tipo_id, v_signo
    FROM cat_tipo_movimiento_monedero WHERE codigo = p_tipo_mm_codigo AND activo;
  IF v_tipo_id IS NULL THEN
    RAISE EXCEPTION 'Tipo de movimiento % no existe', p_tipo_mm_codigo;
  END IF;

  SELECT estado_mm_id INTO v_estado_aplicado
    FROM cat_estado_movimiento_monedero WHERE codigo = 'aplicado';

  SELECT saldo INTO v_saldo FROM monederos WHERE monedero_id = p_monedero_id FOR UPDATE;
  IF v_saldo IS NULL THEN
    RAISE EXCEPTION 'Monedero % no existe', p_monedero_id;
  END IF;

  v_saldo_nuevo := v_saldo + (p_monto * v_signo);
  IF v_saldo_nuevo < 0 THEN
    RAISE EXCEPTION 'Saldo insuficiente: % + (% * %) = %', v_saldo, p_monto, v_signo, v_saldo_nuevo;
  END IF;

  UPDATE monederos SET saldo = v_saldo_nuevo, updated_at = now() WHERE monedero_id = p_monedero_id;

  INSERT INTO movimientos_monedero
    (monedero_id, tipo_mm_id, estado_mm_id, monto, saldo_pre, saldo_post,
     referencia, sesion_id, pago_id, descripcion, aplicado_por)
  VALUES
    (p_monedero_id, v_tipo_id, v_estado_aplicado, p_monto, v_saldo, v_saldo_nuevo,
     p_referencia, p_sesion_id, p_pago_id, p_descripcion, fn_perfil_actual())
  RETURNING movimiento_id INTO v_mov_id;

  RETURN v_mov_id;
END; $$;

-- ── Reversar un movimiento ────────────────
CREATE OR REPLACE FUNCTION fn_reversar_movimiento_monedero(
  p_movimiento_id UUID,
  p_motivo        TEXT DEFAULT NULL
) RETURNS UUID LANGUAGE plpgsql AS $$
DECLARE
  v_orig RECORD;
  v_tipo_reversa TEXT;
  v_nuevo UUID;
BEGIN
  SELECT m.*, t.signo, t.codigo AS tipo_codigo
  INTO v_orig
  FROM movimientos_monedero m
  JOIN cat_tipo_movimiento_monedero t ON t.tipo_mm_id = m.tipo_mm_id
  WHERE m.movimiento_id = p_movimiento_id;

  IF v_orig IS NULL THEN
    RAISE EXCEPTION 'Movimiento % no existe', p_movimiento_id;
  END IF;

  -- Aplicar movimiento inverso
  v_tipo_reversa := CASE WHEN v_orig.signo = -1 THEN 'reversa_pago' ELSE 'ajuste_negativo' END;
  v_nuevo := fn_aplicar_movimiento_monedero(
    v_orig.monedero_id, v_tipo_reversa, v_orig.monto,
    'Reversa de ' || p_movimiento_id::text,
    v_orig.sesion_id, v_orig.pago_id,
    COALESCE(p_motivo, 'Reversa automática')
  );

  -- Marcar el original como reversado
  UPDATE movimientos_monedero
     SET estado_mm_id = (SELECT estado_mm_id FROM cat_estado_movimiento_monedero WHERE codigo='reversado')
   WHERE movimiento_id = p_movimiento_id;

  -- Ligar el nuevo con el original
  UPDATE movimientos_monedero SET movimiento_origen_id = p_movimiento_id
   WHERE movimiento_id = v_nuevo;

  RETURN v_nuevo;
END; $$;
