-- ══════════════════════════════════════════
-- ONLYPARK · 012 · Pensiones
-- ══════════════════════════════════════════
-- Requiere 002-011.

CREATE TABLE IF NOT EXISTS pensiones (
  pension_id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  estacionamiento_id UUID NOT NULL REFERENCES estacionamientos(estacionamiento_id),
  cliente_id         UUID NOT NULL REFERENCES clientes(cliente_id),
  vehiculo_id        UUID REFERENCES vehiculos(vehiculo_id),
  placa_id           UUID REFERENCES placas(placa_id),
  tipo_pension_id    UUID NOT NULL REFERENCES cat_tipo_pension(tipo_pension_id),
  estado_pension_id  UUID NOT NULL REFERENCES cat_estado_pension(estado_pension_id),
  monto_mensual      NUMERIC(14,4) NOT NULL CHECK (monto_mensual >= 0),
  regla_id_origen    UUID REFERENCES reglas_tarifarias(regla_id),
  hora_inicio        TIME,
  hora_fin           TIME,
  fecha_inicio       DATE NOT NULL,
  fecha_fin          DATE,
  dia_pago           INT NOT NULL DEFAULT 1 CHECK (dia_pago BETWEEN 1 AND 28),
  codigo_acceso      TEXT UNIQUE,
  notas              TEXT,
  registrado_por     UUID REFERENCES perfiles_usuario(perfil_id),
  activo             BOOLEAN NOT NULL DEFAULT true,
  created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at         TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_pens_estac_estado ON pensiones(estacionamiento_id, estado_pension_id);
CREATE INDEX IF NOT EXISTS idx_pens_placa        ON pensiones(placa_id) WHERE placa_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_pens_cliente      ON pensiones(cliente_id);
CREATE INDEX IF NOT EXISTS idx_pens_vehiculo     ON pensiones(vehiculo_id) WHERE vehiculo_id IS NOT NULL;

-- ── FKs diferidas: sesiones y pagos → pensiones ─
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='sesiones_pension_fk') THEN
    ALTER TABLE sesiones ADD CONSTRAINT sesiones_pension_fk FOREIGN KEY (pension_id) REFERENCES pensiones(pension_id);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='pagos_pension_fk') THEN
    ALTER TABLE pagos ADD CONSTRAINT pagos_pension_fk FOREIGN KEY (pension_id) REFERENCES pensiones(pension_id);
  END IF;
END $$;

-- ── Pagos de pensión ──────────────────────
CREATE TABLE IF NOT EXISTS pagos_pension (
  pago_pension_id  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  pension_id       UUID NOT NULL REFERENCES pensiones(pension_id),
  pago_id          UUID REFERENCES pagos(pago_id),
  periodo_mes      INT NOT NULL CHECK (periodo_mes BETWEEN 1 AND 12),
  periodo_anio     INT NOT NULL,
  monto_tarifa     NUMERIC(14,4) NOT NULL,
  monto_pagado     NUMERIC(14,4),
  diferencia       NUMERIC(14,4) GENERATED ALWAYS AS (COALESCE(monto_pagado,0) - monto_tarifa) STORED,
  fecha_limite     DATE,
  estado           TEXT NOT NULL DEFAULT 'pendiente'
                    CHECK (estado IN ('pendiente','por_validar','validado','rechazado')),
  fecha_validacion TIMESTAMPTZ,
  validado_por     UUID REFERENCES perfiles_usuario(perfil_id),
  notas            TEXT,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (pension_id, periodo_anio, periodo_mes)
);
CREATE INDEX IF NOT EXISTS idx_pp_pension_periodo ON pagos_pension(pension_id, periodo_anio DESC, periodo_mes DESC);
CREATE INDEX IF NOT EXISTS idx_pp_estado ON pagos_pension(estado);

-- ── Vista: semáforo de pensiones (rescatada de IWOL) ─
CREATE OR REPLACE VIEW v_pensiones_semaforo AS
SELECT
  p.pension_id,
  p.estacionamiento_id,
  c.nombre AS cliente_nombre,
  c.telefono, c.whatsapp,
  pl.numero AS placa,
  v.marca || ' ' || COALESCE(v.modelo,'') AS vehiculo,
  tp.codigo AS tipo,
  p.monto_mensual,
  p.dia_pago,
  ep.codigo AS estado_pension,
  (SELECT MAX(periodo_anio*100 + periodo_mes)
   FROM pagos_pension pp
   WHERE pp.pension_id = p.pension_id AND pp.estado = 'validado') AS ultimo_periodo_pagado,
  (SELECT pp.estado FROM pagos_pension pp
   WHERE pp.pension_id = p.pension_id
     AND pp.periodo_mes = EXTRACT(MONTH FROM CURRENT_DATE)
     AND pp.periodo_anio = EXTRACT(YEAR FROM CURRENT_DATE)
   LIMIT 1) AS estado_mes_actual,
  CASE
    WHEN ep.codigo != 'activo' THEN 'inactiva'
    WHEN EXISTS (
      SELECT 1 FROM pagos_pension pp
      WHERE pp.pension_id = p.pension_id
        AND pp.periodo_mes = EXTRACT(MONTH FROM CURRENT_DATE)
        AND pp.periodo_anio = EXTRACT(YEAR FROM CURRENT_DATE)
        AND pp.estado = 'validado'
    ) THEN 'al_corriente'
    WHEN EXTRACT(DAY FROM CURRENT_DATE) <= p.dia_pago THEN 'por_vencer'
    ELSE 'vencido'
  END AS semaforo
FROM pensiones p
JOIN clientes c ON c.cliente_id = p.cliente_id
LEFT JOIN vehiculos v ON v.vehiculo_id = p.vehiculo_id
LEFT JOIN placas pl ON pl.placa_id = p.placa_id
JOIN cat_tipo_pension tp ON tp.tipo_pension_id = p.tipo_pension_id
JOIN cat_estado_pension ep ON ep.estado_pension_id = p.estado_pension_id
WHERE p.activo;
