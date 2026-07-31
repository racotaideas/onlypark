-- ══════════════════════════════════════════
-- ONLYPARK · 005 · Perfiles de usuario, asignaciones de rol, helpers de seguridad
-- ══════════════════════════════════════════
-- Extiende auth.users de Supabase. Requiere 002, 003, 004.

-- ── Perfil de usuario (1:1 con auth.users) ─
CREATE TABLE IF NOT EXISTS perfiles_usuario (
  perfil_id       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  auth_user_id    UUID NOT NULL UNIQUE REFERENCES auth.users(id) ON DELETE CASCADE,
  email           CITEXT NOT NULL,
  nombre_completo TEXT NOT NULL,
  telefono        TEXT,
  avatar_url      TEXT,
  idioma          TEXT NOT NULL DEFAULT 'es',
  activo          BOOLEAN NOT NULL DEFAULT true,
  ultimo_login_at TIMESTAMPTZ,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_perfil_email ON perfiles_usuario(email);

-- ── FKs de auditoría diferidas hacia jerarquía ─
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='grupos_created_by_fk') THEN
    ALTER TABLE grupos_empresariales
      ADD CONSTRAINT grupos_created_by_fk FOREIGN KEY (created_by) REFERENCES perfiles_usuario(perfil_id),
      ADD CONSTRAINT grupos_updated_by_fk FOREIGN KEY (updated_by) REFERENCES perfiles_usuario(perfil_id);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='empresas_created_by_fk') THEN
    ALTER TABLE empresas
      ADD CONSTRAINT empresas_created_by_fk FOREIGN KEY (created_by) REFERENCES perfiles_usuario(perfil_id),
      ADD CONSTRAINT empresas_updated_by_fk FOREIGN KEY (updated_by) REFERENCES perfiles_usuario(perfil_id);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='sucursales_created_by_fk') THEN
    ALTER TABLE sucursales
      ADD CONSTRAINT sucursales_created_by_fk FOREIGN KEY (created_by) REFERENCES perfiles_usuario(perfil_id),
      ADD CONSTRAINT sucursales_updated_by_fk FOREIGN KEY (updated_by) REFERENCES perfiles_usuario(perfil_id);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='estac_created_by_fk') THEN
    ALTER TABLE estacionamientos
      ADD CONSTRAINT estac_created_by_fk FOREIGN KEY (created_by) REFERENCES perfiles_usuario(perfil_id),
      ADD CONSTRAINT estac_updated_by_fk FOREIGN KEY (updated_by) REFERENCES perfiles_usuario(perfil_id);
  END IF;
END $$;

-- ── Asignaciones de rol jerárquicas ──────
CREATE TABLE IF NOT EXISTS asignaciones_rol (
  asignacion_id      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  perfil_id          UUID NOT NULL REFERENCES perfiles_usuario(perfil_id),
  rol_id             UUID NOT NULL REFERENCES cat_rol(rol_id),
  grupo_id           UUID REFERENCES grupos_empresariales(grupo_id),
  empresa_id         UUID REFERENCES empresas(empresa_id),
  sucursal_id        UUID REFERENCES sucursales(sucursal_id),
  estacionamiento_id UUID REFERENCES estacionamientos(estacionamiento_id),
  vigencia_desde     DATE NOT NULL DEFAULT CURRENT_DATE,
  vigencia_hasta     DATE,
  activo             BOOLEAN NOT NULL DEFAULT true,
  created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_by         UUID REFERENCES perfiles_usuario(perfil_id),
  CONSTRAINT asig_ambito_coherente CHECK (
    (estacionamiento_id IS NOT NULL AND sucursal_id IS NOT NULL AND empresa_id IS NOT NULL AND grupo_id IS NOT NULL)
    OR
    (estacionamiento_id IS NULL AND sucursal_id IS NOT NULL AND empresa_id IS NOT NULL AND grupo_id IS NOT NULL)
    OR
    (estacionamiento_id IS NULL AND sucursal_id IS NULL AND empresa_id IS NOT NULL AND grupo_id IS NOT NULL)
    OR
    (estacionamiento_id IS NULL AND sucursal_id IS NULL AND empresa_id IS NULL AND grupo_id IS NOT NULL)
    OR
    (estacionamiento_id IS NULL AND sucursal_id IS NULL AND empresa_id IS NULL AND grupo_id IS NULL)
  )
);
CREATE INDEX IF NOT EXISTS idx_asig_perfil ON asignaciones_rol(perfil_id) WHERE activo;
CREATE INDEX IF NOT EXISTS idx_asig_estac  ON asignaciones_rol(estacionamiento_id) WHERE activo;
CREATE INDEX IF NOT EXISTS idx_asig_sucur  ON asignaciones_rol(sucursal_id) WHERE activo;
CREATE INDEX IF NOT EXISTS idx_asig_empresa ON asignaciones_rol(empresa_id) WHERE activo;
CREATE INDEX IF NOT EXISTS idx_asig_grupo   ON asignaciones_rol(grupo_id) WHERE activo;

-- ══════════════════════════════════════════
-- Funciones helper de seguridad
-- ══════════════════════════════════════════

-- Perfil actual (basado en auth.uid())
CREATE OR REPLACE FUNCTION fn_perfil_actual()
RETURNS UUID LANGUAGE sql STABLE AS $$
  SELECT perfil_id FROM perfiles_usuario WHERE auth_user_id = auth.uid();
$$;

-- Estacionamientos visibles para un perfil (cierre transitivo del ámbito)
CREATE OR REPLACE FUNCTION fn_estacionamientos_visibles(p_perfil_id UUID)
RETURNS TABLE (estacionamiento_id UUID) LANGUAGE sql STABLE AS $$
  -- Super admin: todos los activos
  SELECT e.estacionamiento_id
  FROM estacionamientos e
  WHERE e.activo AND EXISTS (
    SELECT 1 FROM asignaciones_rol a
    JOIN cat_rol r ON r.rol_id = a.rol_id
    WHERE a.perfil_id = p_perfil_id
      AND a.activo
      AND r.codigo = 'super_admin'
      AND (a.vigencia_hasta IS NULL OR a.vigencia_hasta >= CURRENT_DATE)
  )
  UNION
  -- Ámbito por grupo / empresa / sucursal / estacionamiento
  SELECT DISTINCT e.estacionamiento_id
  FROM estacionamientos e
  JOIN sucursales s ON s.sucursal_id = e.sucursal_id
  JOIN empresas em  ON em.empresa_id = s.empresa_id
  JOIN asignaciones_rol a ON a.perfil_id = p_perfil_id AND a.activo
    AND (a.vigencia_hasta IS NULL OR a.vigencia_hasta >= CURRENT_DATE)
  WHERE e.activo AND s.activo AND em.activo
    AND (
      (a.estacionamiento_id IS NOT NULL AND a.estacionamiento_id = e.estacionamiento_id)
      OR
      (a.estacionamiento_id IS NULL AND a.sucursal_id IS NOT NULL AND a.sucursal_id = e.sucursal_id)
      OR
      (a.sucursal_id IS NULL AND a.empresa_id IS NOT NULL AND a.empresa_id = em.empresa_id)
      OR
      (a.empresa_id IS NULL AND a.grupo_id IS NOT NULL AND a.grupo_id = em.grupo_id)
    );
$$;

-- Estacionamientos del usuario logueado (usado por RLS)
CREATE OR REPLACE FUNCTION fn_mis_estacionamientos()
RETURNS SETOF UUID LANGUAGE sql STABLE AS $$
  SELECT estacionamiento_id FROM fn_estacionamientos_visibles(fn_perfil_actual());
$$;

-- ¿El usuario actual tiene un permiso dado?
CREATE OR REPLACE FUNCTION fn_tiene_permiso(p_codigo_permiso TEXT)
RETURNS BOOLEAN LANGUAGE sql STABLE AS $$
  SELECT EXISTS (
    SELECT 1
    FROM asignaciones_rol a
    JOIN cat_rol_permiso rp ON rp.rol_id = a.rol_id
    JOIN cat_permiso p ON p.permiso_id = rp.permiso_id
    WHERE a.perfil_id = fn_perfil_actual()
      AND a.activo
      AND (a.vigencia_hasta IS NULL OR a.vigencia_hasta >= CURRENT_DATE)
      AND p.codigo = p_codigo_permiso
  );
$$;

-- ¿Es super admin?
CREATE OR REPLACE FUNCTION fn_es_super_admin()
RETURNS BOOLEAN LANGUAGE sql STABLE AS $$
  SELECT EXISTS (
    SELECT 1 FROM asignaciones_rol a
    JOIN cat_rol r ON r.rol_id = a.rol_id
    WHERE a.perfil_id = fn_perfil_actual()
      AND a.activo AND r.codigo = 'super_admin'
      AND (a.vigencia_hasta IS NULL OR a.vigencia_hasta >= CURRENT_DATE)
  );
$$;
