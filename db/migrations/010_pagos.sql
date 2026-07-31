-- ══════════════════════════════════════════
-- ONLYPARK · 010 · Pagos (unificados: sesión / pensión / recarga monedero)
-- ══════════════════════════════════════════
-- FK a monederos y pensiones se agregan como diferidas en sus migraciones (011, 012).
-- Requiere 002-009.

CREATE TABLE IF NOT EXISTS pagos (
  pago_id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  sesion_id          UUID REFERENCES sesiones(sesion_id),
  pension_id         UUID,   -- FK diferida a pensiones (012)
  monedero_id        UUID,   -- FK diferida a monederos (011)
  estacionamiento_id UUID NOT NULL REFERENCES estacionamientos(estacionamiento_id),
  metodo_pago_id     UUID NOT NULL REFERENCES cat_metodo_pago(metodo_pago_id),
  estado_pago_id     UUID NOT NULL REFERENCES cat_estado_pago(estado_pago_id),
  cobrado_por        UUID REFERENCES perfiles_usuario(perfil_id),
  corte_caja_id      UUID REFERENCES cortes_caja(corte_caja_id),
  monto              NUMERIC(14,4) NOT NULL CHECK (monto >= 0),
  moneda_id          UUID NOT NULL REFERENCES cat_moneda(moneda_id),
  referencia_externa TEXT,
  link_pago          TEXT,
  qr_url             TEXT,
  comprobante_url    TEXT,
  descripcion        TEXT,
  cobrado_at         TIMESTAMPTZ,
  conciliado_at      TIMESTAMPTZ,
  created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT pagos_destino_excluyente CHECK (
    (sesion_id IS NOT NULL AND pension_id IS NULL) OR
    (sesion_id IS NULL AND pension_id IS NOT NULL) OR
    (sesion_id IS NULL AND pension_id IS NULL AND monedero_id IS NOT NULL)
  )
);
CREATE INDEX IF NOT EXISTS idx_pagos_sesion    ON pagos(sesion_id) WHERE sesion_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_pagos_pension   ON pagos(pension_id) WHERE pension_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_pagos_monedero  ON pagos(monedero_id) WHERE monedero_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_pagos_estado    ON pagos(estado_pago_id);
CREATE INDEX IF NOT EXISTS idx_pagos_corte     ON pagos(corte_caja_id);
CREATE INDEX IF NOT EXISTS idx_pagos_cobrado_at ON pagos(cobrado_at DESC);
CREATE INDEX IF NOT EXISTS idx_pagos_estac      ON pagos(estacionamiento_id);
