-- ══════════════════════════════════════════
-- ONLYPARK · 017 · Versionado de apps y avisos operativos
-- ══════════════════════════════════════════
-- Requiere 002-016.

-- ── Versión por app (para forzar refresh de PWAs) ─
CREATE TABLE IF NOT EXISTS versiones_app (
  app             TEXT PRIMARY KEY,
  version         INT NOT NULL DEFAULT 0,
  changelog_url   TEXT,
  actualizado_en  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Semilla inicial: apps del portal
INSERT INTO versiones_app (app, version) VALUES
  ('caseta', 1),
  ('dashboard_admin', 1),
  ('dashboard_corporativo', 1),
  ('pensiones', 1),
  ('promociones', 1),
  ('lpr_simulador', 1),
  ('onlywallet_web', 1)
ON CONFLICT (app) DO NOTHING;

-- ── Avisos operador (Admin ↔ Cajero, con hilos) ─
CREATE TABLE IF NOT EXISTS avisos_operador (
  aviso_id            BIGSERIAL PRIMARY KEY,
  estacionamiento_id  UUID NOT NULL REFERENCES estacionamientos(estacionamiento_id),
  destinatario_perfil UUID REFERENCES perfiles_usuario(perfil_id),
  destinatario_rol_id UUID REFERENCES cat_rol(rol_id),
  mensaje             TEXT NOT NULL,
  origen              TEXT NOT NULL DEFAULT 'admin'
                        CHECK (origen IN ('admin','cajero','sistema')),
  hilo_id             BIGINT REFERENCES avisos_operador(aviso_id),
  leido_admin         BOOLEAN NOT NULL DEFAULT true,
  leido_destinatario  BOOLEAN NOT NULL DEFAULT false,
  creado_por          UUID REFERENCES perfiles_usuario(perfil_id),
  created_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_avisos_estac ON avisos_operador(estacionamiento_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_avisos_dest  ON avisos_operador(destinatario_perfil) WHERE destinatario_perfil IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_avisos_hilo  ON avisos_operador(hilo_id) WHERE hilo_id IS NOT NULL;
