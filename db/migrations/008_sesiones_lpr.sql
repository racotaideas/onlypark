-- ══════════════════════════════════════════
-- ONLYPARK · 008 · Sesiones de estacionamiento + LPR + cortes de caja
-- ══════════════════════════════════════════
-- Requiere 002-007. La FK a pensiones se agrega en 012 (diferida).

-- ── Cámaras (v1: todas simuladas) ─────────
CREATE TABLE IF NOT EXISTS camaras (
  camara_id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  estacionamiento_id UUID NOT NULL REFERENCES estacionamientos(estacionamiento_id),
  codigo             TEXT NOT NULL,
  nombre             TEXT NOT NULL,
  proposito          TEXT NOT NULL CHECK (proposito IN ('entrada','salida','ambas','patrullaje')),
  activa             BOOLEAN NOT NULL DEFAULT true,
  es_simulada        BOOLEAN NOT NULL DEFAULT true,
  created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (estacionamiento_id, codigo)
);

-- ── Cortes de caja ────────────────────────
CREATE TABLE IF NOT EXISTS cortes_caja (
  corte_caja_id      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  estacionamiento_id UUID NOT NULL REFERENCES estacionamientos(estacionamiento_id),
  cajero_id          UUID NOT NULL REFERENCES perfiles_usuario(perfil_id),
  turno_id           UUID REFERENCES cat_turno(turno_id),
  tipo               TEXT NOT NULL CHECK (tipo IN ('apertura','relevo','cierre')),
  inicio_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
  fin_at             TIMESTAMPTZ,
  fondo_inicial      NUMERIC(14,4) NOT NULL DEFAULT 0,
  total_cobrado      NUMERIC(14,4) DEFAULT 0,
  total_entregado    NUMERIC(14,4),
  cajero_relevo_id   UUID REFERENCES perfiles_usuario(perfil_id),
  estado             TEXT NOT NULL DEFAULT 'activo' CHECK (estado IN ('activo','relevado','cerrado')),
  notas              TEXT,
  created_at         TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_cortes_estac_estado ON cortes_caja(estacionamiento_id, estado);
CREATE INDEX IF NOT EXISTS idx_cortes_cajero      ON cortes_caja(cajero_id);
CREATE INDEX IF NOT EXISTS idx_cortes_inicio_at   ON cortes_caja(inicio_at DESC);

-- ── Sesiones (evolución del ticket) ───────
CREATE TABLE IF NOT EXISTS sesiones (
  sesion_id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  estacionamiento_id    UUID NOT NULL REFERENCES estacionamientos(estacionamiento_id),
  tipo_sesion_id        UUID NOT NULL REFERENCES cat_tipo_sesion(tipo_sesion_id),
  estado_sesion_id      UUID NOT NULL REFERENCES cat_estado_sesion(estado_sesion_id),
  -- Vehículo / cliente
  placa_id              UUID REFERENCES placas(placa_id),
  vehiculo_id           UUID REFERENCES vehiculos(vehiculo_id),
  cliente_id            UUID REFERENCES clientes(cliente_id),
  pension_id            UUID,  -- FK diferida a pensiones (012)
  -- Operación
  cajero_entrada_id     UUID REFERENCES perfiles_usuario(perfil_id),
  cajero_salida_id      UUID REFERENCES perfiles_usuario(perfil_id),
  corte_caja_entrada_id UUID REFERENCES cortes_caja(corte_caja_id),
  corte_caja_salida_id  UUID REFERENCES cortes_caja(corte_caja_id),
  camara_entrada_id     UUID REFERENCES camaras(camara_id),
  camara_salida_id      UUID REFERENCES camaras(camara_id),
  -- Folios
  folio_entrada         TEXT NOT NULL,
  folio_salida          TEXT,
  folio_local           TEXT,
  -- Tiempos
  entrada_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
  salida_at             TIMESTAMPTZ,
  liberada_at           TIMESTAMPTZ,
  tolerancia_hasta_at   TIMESTAMPTZ,
  duracion_minutos      INT GENERATED ALWAYS AS (
    CASE WHEN salida_at IS NULL THEN NULL
         ELSE GREATEST(0, (EXTRACT(EPOCH FROM (salida_at - entrada_at))/60)::INT) END
  ) STORED,
  -- Cobro
  requiere_cobro        BOOLEAN NOT NULL DEFAULT true,
  politica_tarifaria_id UUID,   -- FK diferida a politicas_tarifarias (009)
  tarifa_hist_id        UUID,   -- FK diferida a tarifas_historico (009)
  importe_calculado     NUMERIC(14,4),
  importe_descuento     NUMERIC(14,4) DEFAULT 0,
  importe_total         NUMERIC(14,4),
  moneda_id             UUID REFERENCES cat_moneda(moneda_id),
  -- Sync offline
  synced_at             TIMESTAMPTZ,
  created_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (estacionamiento_id, folio_entrada)
);
CREATE INDEX IF NOT EXISTS idx_sesion_estac_estado    ON sesiones(estacionamiento_id, estado_sesion_id);
CREATE INDEX IF NOT EXISTS idx_sesion_placa           ON sesiones(placa_id) WHERE placa_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_sesion_pension         ON sesiones(pension_id) WHERE pension_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_sesion_entrada_at      ON sesiones(entrada_at DESC);
CREATE INDEX IF NOT EXISTS idx_sesion_salida_at       ON sesiones(salida_at) WHERE salida_at IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_sesion_folio_salida    ON sesiones(estacionamiento_id, folio_salida) WHERE folio_salida IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_sesion_corte_entrada   ON sesiones(corte_caja_entrada_id);
CREATE INDEX IF NOT EXISTS idx_sesion_corte_salida    ON sesiones(corte_caja_salida_id);

-- ── Capturas LPR ──────────────────────────
CREATE TABLE IF NOT EXISTS capturas_lpr (
  captura_id     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  camara_id      UUID NOT NULL REFERENCES camaras(camara_id),
  sesion_id      UUID REFERENCES sesiones(sesion_id),
  placa_id       UUID REFERENCES placas(placa_id),
  placa_leida    TEXT,
  confianza      NUMERIC(5,2),
  fotografia_url TEXT NOT NULL,
  proposito      TEXT NOT NULL CHECK (proposito IN ('entrada','salida','revision','patrullaje')),
  momento        TIMESTAMPTZ NOT NULL DEFAULT now(),
  procesada      BOOLEAN NOT NULL DEFAULT false,
  error_ocr      TEXT,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_lpr_camara_momento ON capturas_lpr(camara_id, momento DESC);
CREATE INDEX IF NOT EXISTS idx_lpr_sesion         ON capturas_lpr(sesion_id) WHERE sesion_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_lpr_no_procesada   ON capturas_lpr(procesada) WHERE NOT procesada;

-- ── Cola sync offline generalizada ────────
CREATE TABLE IF NOT EXISTS sync_queue (
  sync_id            BIGSERIAL PRIMARY KEY,
  estacionamiento_id UUID NOT NULL REFERENCES estacionamientos(estacionamiento_id),
  tabla              TEXT NOT NULL,
  operacion          TEXT NOT NULL CHECK (operacion IN ('INSERT','UPDATE','DELETE')),
  payload            JSONB NOT NULL,
  intentos           INT NOT NULL DEFAULT 0,
  synced             BOOLEAN NOT NULL DEFAULT false,
  error_msg          TEXT,
  created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
  synced_at          TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS idx_sync_pending ON sync_queue(synced, created_at) WHERE NOT synced;
