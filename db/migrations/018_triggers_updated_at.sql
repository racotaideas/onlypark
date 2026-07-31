-- ══════════════════════════════════════════
-- ONLYPARK · 018 · Triggers de updated_at
-- ══════════════════════════════════════════
-- Aplica tr_set_updated_at() a todas las tablas con columna updated_at.
-- Requiere 002-017.

-- ── Función universal ─────────────────────
CREATE OR REPLACE FUNCTION tr_set_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END; $$;

-- ── Aplicar el trigger a todas las tablas del schema public que tengan columna updated_at ─
DO $$
DECLARE
  r RECORD;
  trg_name TEXT;
BEGIN
  FOR r IN
    SELECT c.table_schema, c.table_name
    FROM information_schema.columns c
    JOIN information_schema.tables t
      ON t.table_schema = c.table_schema AND t.table_name = c.table_name
    WHERE c.column_name = 'updated_at'
      AND c.table_schema = 'public'
      AND t.table_type = 'BASE TABLE'
  LOOP
    trg_name := 'trg_' || r.table_name || '_updated_at';
    IF NOT EXISTS (
      SELECT 1 FROM pg_trigger WHERE tgname = trg_name AND tgrelid = (r.table_schema||'.'||r.table_name)::regclass
    ) THEN
      EXECUTE format(
        'CREATE TRIGGER %I BEFORE UPDATE ON %I.%I FOR EACH ROW EXECUTE FUNCTION tr_set_updated_at();',
        trg_name, r.table_schema, r.table_name
      );
    END IF;
  END LOOP;
END $$;
