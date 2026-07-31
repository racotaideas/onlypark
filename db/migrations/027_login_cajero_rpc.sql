-- ============================================================================
-- 027 — RPC login_cajero + seed de cajeros de prueba
--
-- Los portales IWOL (operador/admin/corporativo) tienen su propio flow de login
-- que llama al RPC public.login_cajero(p_usuario, p_password_hash) donde el hash
-- es SHA-256 hex del password (calculado client-side, ver opSha256Hex en operador.html).
--
-- Este archivo:
--   1. Agrega columna password_hash a perfiles_usuario (nullable).
--   2. Hace auth_user_id nullable para permitir cajeros operacionales que no
--      necesitan cuenta Supabase Auth (solo se autentican via login_cajero).
--   3. Crea el RPC login_cajero como SECURITY DEFINER (expuesto a anon).
--   4. Siembra 5 cajeros de prueba con password "1234" para poder abrir portales.
-- ============================================================================

-- 1) columna password_hash
ALTER TABLE public.perfiles_usuario
  ADD COLUMN IF NOT EXISTS password_hash TEXT;

-- 2) auth_user_id nullable
ALTER TABLE public.perfiles_usuario
  ALTER COLUMN auth_user_id DROP NOT NULL;

-- 2b) UNIQUE(email) para soportar ON CONFLICT
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.perfiles_usuario'::regclass
      AND conname = 'perfiles_usuario_email_key'
  ) THEN
    ALTER TABLE public.perfiles_usuario
      ADD CONSTRAINT perfiles_usuario_email_key UNIQUE (email);
  END IF;
END $$;

-- 3) RPC login_cajero
CREATE OR REPLACE FUNCTION public.login_cajero(
  p_usuario       text,
  p_password_hash text
)
RETURNS TABLE (
  cajero_id     uuid,
  usuario       text,
  nombre        text,
  rol           text,
  plaza_id      uuid,
  plaza_nombre  text,
  activo        boolean
)
LANGUAGE sql STABLE
SECURITY DEFINER SET search_path = public, pg_temp
AS $$
  SELECT DISTINCT
    p.perfil_id       AS cajero_id,
    p.email::text     AS usuario,
    p.nombre_completo AS nombre,
    r.codigo          AS rol,
    a.estacionamiento_id AS plaza_id,
    e.nombre          AS plaza_nombre,
    p.activo
  FROM public.perfiles_usuario p
  JOIN public.asignaciones_rol a ON a.perfil_id = p.perfil_id AND a.activo
    AND (a.vigencia_hasta IS NULL OR a.vigencia_hasta >= CURRENT_DATE)
  JOIN public.cat_rol r ON r.rol_id = a.rol_id
  LEFT JOIN public.estacionamientos e ON e.estacionamiento_id = a.estacionamiento_id
  WHERE p.activo
    AND p.password_hash IS NOT NULL
    AND lower(p.password_hash) = lower(p_password_hash)
    AND (
      lower(p.email::text) = lower(p_usuario)
      OR lower(split_part(p.email::text, '@', 1)) = lower(p_usuario)
    )
  LIMIT 1;
$$;

REVOKE ALL ON FUNCTION public.login_cajero(text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.login_cajero(text, text) TO anon, authenticated, service_role;

-- 4) Seed cajeros de prueba — password "1234"
--    SHA-256 hex de "1234" =
--    03ac674216f3e15c761ee1a5e255f067953623c8b388b4459e13f978d7c846f4
DO $$
DECLARE
  v_hash text := '03ac674216f3e15c761ee1a5e255f067953623c8b388b4459e13f978d7c846f4';
  v_est_iwol   uuid; v_suc_iwol uuid; v_emp_iwol uuid; v_grp_iwol uuid;
  v_grp_carso  uuid;
  v_perfil     uuid;
  v_rol_cajero uuid; v_rol_super uuid; v_rol_adm_est uuid; v_rol_adm_grp uuid; v_rol_supv uuid;
BEGIN
  SELECT rol_id INTO v_rol_cajero  FROM cat_rol WHERE codigo='cajero';
  SELECT rol_id INTO v_rol_supv    FROM cat_rol WHERE codigo='supervisor';
  SELECT rol_id INTO v_rol_adm_est FROM cat_rol WHERE codigo='admin_estacionamiento';
  SELECT rol_id INTO v_rol_adm_grp FROM cat_rol WHERE codigo='admin_grupo';
  SELECT rol_id INTO v_rol_super   FROM cat_rol WHERE codigo='super_admin';

  -- Jerarquía completa IWOL
  SELECT est.estacionamiento_id, s.sucursal_id, e.empresa_id, g.grupo_id
    INTO v_est_iwol, v_suc_iwol, v_emp_iwol, v_grp_iwol
  FROM estacionamientos est
    JOIN sucursales s ON s.sucursal_id=est.sucursal_id
    JOIN empresas   e ON e.empresa_id=s.empresa_id
    JOIN grupos_empresariales g ON g.grupo_id=e.grupo_id
  WHERE e.codigo='IWOL' LIMIT 1;

  SELECT grupo_id INTO v_grp_carso FROM grupos_empresariales WHERE nombre ILIKE '%Carso%' LIMIT 1;

  -- CAJERO 1 - IWOL
  INSERT INTO perfiles_usuario (email, nombre_completo, activo, idioma, password_hash)
  VALUES ('cajero1@onlypark.local', 'Cajero Uno', true, 'es', v_hash)
  ON CONFLICT (email) DO UPDATE SET password_hash=EXCLUDED.password_hash, activo=true
  RETURNING perfil_id INTO v_perfil;
  INSERT INTO asignaciones_rol (perfil_id, rol_id, grupo_id, empresa_id, sucursal_id, estacionamiento_id, activo)
  VALUES (v_perfil, v_rol_cajero, v_grp_iwol, v_emp_iwol, v_suc_iwol, v_est_iwol, true) ON CONFLICT DO NOTHING;

  -- CAJERO 2 - IWOL
  INSERT INTO perfiles_usuario (email, nombre_completo, activo, idioma, password_hash)
  VALUES ('cajero2@onlypark.local', 'Cajero Dos', true, 'es', v_hash)
  ON CONFLICT (email) DO UPDATE SET password_hash=EXCLUDED.password_hash, activo=true
  RETURNING perfil_id INTO v_perfil;
  INSERT INTO asignaciones_rol (perfil_id, rol_id, grupo_id, empresa_id, sucursal_id, estacionamiento_id, activo)
  VALUES (v_perfil, v_rol_cajero, v_grp_iwol, v_emp_iwol, v_suc_iwol, v_est_iwol, true) ON CONFLICT DO NOTHING;

  -- SUPERVISOR - IWOL
  INSERT INTO perfiles_usuario (email, nombre_completo, activo, idioma, password_hash)
  VALUES ('supervisor@onlypark.local', 'Supervisor Plaza', true, 'es', v_hash)
  ON CONFLICT (email) DO UPDATE SET password_hash=EXCLUDED.password_hash, activo=true
  RETURNING perfil_id INTO v_perfil;
  INSERT INTO asignaciones_rol (perfil_id, rol_id, grupo_id, empresa_id, sucursal_id, estacionamiento_id, activo)
  VALUES (v_perfil, v_rol_supv, v_grp_iwol, v_emp_iwol, v_suc_iwol, v_est_iwol, true) ON CONFLICT DO NOTHING;

  -- ADMIN plaza (ambito: estacionamiento IWOL)
  INSERT INTO perfiles_usuario (email, nombre_completo, activo, idioma, password_hash)
  VALUES ('admin@onlypark.local', 'Administrador Plaza', true, 'es', v_hash)
  ON CONFLICT (email) DO UPDATE SET password_hash=EXCLUDED.password_hash, activo=true
  RETURNING perfil_id INTO v_perfil;
  INSERT INTO asignaciones_rol (perfil_id, rol_id, grupo_id, empresa_id, sucursal_id, estacionamiento_id, activo)
  VALUES (v_perfil, v_rol_adm_est, v_grp_iwol, v_emp_iwol, v_suc_iwol, v_est_iwol, true) ON CONFLICT DO NOTHING;

  -- CORPORATIVO admin_grupo Carso (ambito: solo grupo)
  INSERT INTO perfiles_usuario (email, nombre_completo, activo, idioma, password_hash)
  VALUES ('corp@onlypark.local', 'Oficina Corporativa', true, 'es', v_hash)
  ON CONFLICT (email) DO UPDATE SET password_hash=EXCLUDED.password_hash, activo=true
  RETURNING perfil_id INTO v_perfil;
  INSERT INTO asignaciones_rol (perfil_id, rol_id, grupo_id, activo)
  VALUES (v_perfil, v_rol_adm_grp, v_grp_carso, true) ON CONFLICT DO NOTHING;

  -- SUPER (ambito global)
  INSERT INTO perfiles_usuario (email, nombre_completo, activo, idioma, password_hash)
  VALUES ('super@onlypark.local', 'Super Admin', true, 'es', v_hash)
  ON CONFLICT (email) DO UPDATE SET password_hash=EXCLUDED.password_hash, activo=true
  RETURNING perfil_id INTO v_perfil;
  INSERT INTO asignaciones_rol (perfil_id, rol_id, activo)
  VALUES (v_perfil, v_rol_super, true) ON CONFLICT DO NOTHING;
END $$;

-- Verificación
SELECT p.email, p.nombre_completo, r.codigo AS rol, COALESCE(e.nombre,'—') AS plaza
FROM perfiles_usuario p
JOIN asignaciones_rol a ON a.perfil_id=p.perfil_id AND a.activo
JOIN cat_rol r ON r.rol_id=a.rol_id
LEFT JOIN estacionamientos e ON e.estacionamiento_id=a.estacionamiento_id
WHERE p.password_hash IS NOT NULL
ORDER BY r.codigo, p.email;
