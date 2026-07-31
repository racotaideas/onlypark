-- ══════════════════════════════════════════
-- ONLYPARK · 001 · Extensiones Postgres
-- ══════════════════════════════════════════
-- Idempotente. Ejecutar primero.

CREATE EXTENSION IF NOT EXISTS "pgcrypto";       -- gen_random_uuid, digest
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";      -- utilidades UUID adicionales
CREATE EXTENSION IF NOT EXISTS "citext";         -- emails y placas case-insensitive
CREATE EXTENSION IF NOT EXISTS "pg_trgm";        -- búsqueda fuzzy (placas, clientes)
CREATE EXTENSION IF NOT EXISTS "btree_gist";     -- exclusion constraints (vigencias solapadas)

-- Verificación (informativa):
DO $$
BEGIN
  RAISE NOTICE 'Extensiones activas: %',
    (SELECT string_agg(extname, ', ' ORDER BY extname)
     FROM pg_extension
     WHERE extname IN ('pgcrypto','uuid-ossp','citext','pg_trgm','btree_gist'));
END $$;
