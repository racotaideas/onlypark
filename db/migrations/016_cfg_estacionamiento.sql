-- ══════════════════════════════════════════
-- ONLYPARK · 016 · Configuración por estacionamiento (feature flags + parámetros)
-- ══════════════════════════════════════════
-- Requiere 002-015.

CREATE TABLE IF NOT EXISTS cfg_estacionamiento (
  cfg_estac_id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  estacionamiento_id         UUID NOT NULL UNIQUE REFERENCES estacionamientos(estacionamiento_id),
  -- Operación
  tolerancia_min             INT NOT NULL DEFAULT 15,
  minutos_cortesia_automatica INT NOT NULL DEFAULT 15,
  hora_apertura              TIME,
  hora_cierre                TIME,
  minutos_tolerancia_salida  INT NOT NULL DEFAULT 15,
  -- Folios
  formato_folio_entrada      TEXT NOT NULL DEFAULT 'E-{AAMMDD}{NNN}',
  formato_folio_salida       TEXT NOT NULL DEFAULT 'S-{AAMMDD}{NNN}',
  -- PIN operativo (legado NIP de IWOL — opcional para atajos rápidos en caseta)
  usa_pin_operativo          BOOLEAN NOT NULL DEFAULT false,
  -- Feature flags
  lpr_habilitado             BOOLEAN NOT NULL DEFAULT false,
  onlywallet_habilitado      BOOLEAN NOT NULL DEFAULT false,
  promociones_habilitado     BOOLEAN NOT NULL DEFAULT true,
  pagos_qr_habilitado        BOOLEAN NOT NULL DEFAULT false,
  pagos_link_habilitado      BOOLEAN NOT NULL DEFAULT false,
  offline_habilitado         BOOLEAN NOT NULL DEFAULT true,
  bitacora_click_habilitada  BOOLEAN NOT NULL DEFAULT false,
  -- Layout de ticket (JSONB flexible)
  layout_ticket_entrada      JSONB,
  layout_ticket_salida       JSONB,
  -- Contacto en ticket
  contacto_telefono          TEXT,
  contacto_web               TEXT,
  contacto_redes             JSONB,
  avisos_legales             TEXT,
  updated_at                 TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_by                 UUID REFERENCES perfiles_usuario(perfil_id)
);
