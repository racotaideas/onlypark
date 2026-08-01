-- ============================================================================
-- 030 — login_cajero mapea roles ONLYPARK -> roles IWOL
--
-- Los portales IWOL solo conocen 3 códigos de rol: cajero, admin_plaza, super_admin.
-- Nuestros roles jerárquicos son distintos (admin_estacionamiento, admin_grupo,
-- admin_empresa, admin_sucursal, supervisor, consulta). Este mapeo permite que
-- cualquier rol ONLYPARK entre a los portales sin cambiar el HTML del IWOL:
--
--   super_admin                                          -> super_admin
--   admin_grupo | admin_empresa | admin_sucursal
--     | admin_estacionamiento                            -> admin_plaza
--   supervisor                                           -> admin_plaza
--   cajero                                               -> cajero
--   consulta                                             -> cajero (solo lectura)
-- ============================================================================

CREATE OR REPLACE FUNCTION public.fn_rol_iwol(p_codigo text)
RETURNS text LANGUAGE sql IMMUTABLE
AS $$
  SELECT CASE lower(p_codigo)
    WHEN 'super_admin'            THEN 'super_admin'
    WHEN 'admin_grupo'            THEN 'admin_plaza'
    WHEN 'admin_empresa'          THEN 'admin_plaza'
    WHEN 'admin_sucursal'         THEN 'admin_plaza'
    WHEN 'admin_estacionamiento'  THEN 'admin_plaza'
    WHEN 'supervisor'             THEN 'admin_plaza'
    WHEN 'cajero'                 THEN 'cajero'
    WHEN 'consulta'               THEN 'cajero'
    ELSE 'cajero'
  END;
$$;

-- Redefinir login_cajero para devolver el rol mapeado
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
    p.perfil_id                       AS cajero_id,
    p.email::text                     AS usuario,
    p.nombre_completo                 AS nombre,
    public.fn_rol_iwol(r.codigo)      AS rol,
    a.estacionamiento_id              AS plaza_id,
    e.nombre                          AS plaza_nombre,
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
  ORDER BY 4 DESC  -- prefiere super_admin > admin_plaza > cajero
  LIMIT 1;
$$;

REVOKE ALL ON FUNCTION public.login_cajero(text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.login_cajero(text, text) TO anon, authenticated, service_role;

-- También actualizar la vista cajeros para exponer el rol mapeado (el portal
-- llena su combo desde 'cajeros?rol=in.(cajero,admin_plaza,super_admin)')
DROP VIEW IF EXISTS public.cajeros CASCADE;
CREATE VIEW public.cajeros AS
SELECT DISTINCT
  p.perfil_id                    AS cajero_id,
  p.email::text                  AS usuario,
  p.nombre_completo              AS nombre,
  public.fn_rol_iwol(r.codigo)   AS rol,
  r.codigo                       AS rol_original,
  p.activo,
  p.telefono,
  p.avatar_url,
  a.estacionamiento_id           AS plaza_id,
  a.vigencia_desde,
  a.vigencia_hasta,
  p.created_at,
  p.updated_at
FROM public.perfiles_usuario p
JOIN public.asignaciones_rol a ON a.perfil_id = p.perfil_id AND a.activo
JOIN public.cat_rol          r ON r.rol_id     = a.rol_id
WHERE p.activo
  AND (a.vigencia_hasta IS NULL OR a.vigencia_hasta >= CURRENT_DATE);

GRANT SELECT ON public.cajeros TO anon, authenticated, service_role;

NOTIFY pgrst, 'reload schema';

-- Verificación
SELECT usuario, nombre, rol, rol_original FROM public.cajeros ORDER BY rol_original;
