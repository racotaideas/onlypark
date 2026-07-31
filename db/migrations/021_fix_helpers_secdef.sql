-- FIX #1: convertir helpers de identidad a SECURITY DEFINER
-- Motivo: fn_perfil_actual() consulta perfiles_usuario, cuya policy RLS invoca
--         fn_mis_empresas / fn_es_super_admin, que a su vez llaman fn_perfil_actual
--         -> recursión infinita (stack depth exceeded) al ejecutar bajo `authenticated`.
-- Práctica estándar en Supabase para helpers de RLS: SECURITY DEFINER + search_path fijo.

CREATE OR REPLACE FUNCTION public.fn_perfil_actual()
RETURNS uuid LANGUAGE sql STABLE
SECURITY DEFINER SET search_path = public, pg_temp
AS $$
  SELECT perfil_id FROM perfiles_usuario WHERE auth_user_id = auth.uid();
$$;

CREATE OR REPLACE FUNCTION public.fn_es_super_admin()
RETURNS boolean LANGUAGE sql STABLE
SECURITY DEFINER SET search_path = public, pg_temp
AS $$
  SELECT EXISTS (
    SELECT 1 FROM asignaciones_rol a
    JOIN cat_rol r ON r.rol_id = a.rol_id
    WHERE a.perfil_id = fn_perfil_actual()
      AND a.activo AND r.codigo = 'super_admin'
      AND (a.vigencia_hasta IS NULL OR a.vigencia_hasta >= CURRENT_DATE)
  );
$$;

CREATE OR REPLACE FUNCTION public.fn_estacionamientos_visibles(p_perfil_id uuid)
RETURNS TABLE(estacionamiento_id uuid) LANGUAGE sql STABLE
SECURITY DEFINER SET search_path = public, pg_temp
AS $$
  SELECT e.estacionamiento_id
  FROM estacionamientos e
  WHERE e.activo AND EXISTS (
    SELECT 1 FROM asignaciones_rol a
    JOIN cat_rol r ON r.rol_id = a.rol_id
    WHERE a.perfil_id = p_perfil_id
      AND a.activo AND r.codigo = 'super_admin'
      AND (a.vigencia_hasta IS NULL OR a.vigencia_hasta >= CURRENT_DATE)
  )
  UNION
  SELECT DISTINCT e.estacionamiento_id
  FROM estacionamientos e
  JOIN sucursales s ON s.sucursal_id = e.sucursal_id
  JOIN empresas em  ON em.empresa_id = s.empresa_id
  JOIN asignaciones_rol a ON a.perfil_id = p_perfil_id AND a.activo
    AND (a.vigencia_hasta IS NULL OR a.vigencia_hasta >= CURRENT_DATE)
  WHERE e.activo AND s.activo AND em.activo
    AND (
      (a.estacionamiento_id IS NOT NULL AND a.estacionamiento_id = e.estacionamiento_id)
      OR (a.estacionamiento_id IS NULL AND a.sucursal_id IS NOT NULL AND a.sucursal_id = e.sucursal_id)
      OR (a.sucursal_id IS NULL AND a.empresa_id IS NOT NULL AND a.empresa_id = em.empresa_id)
      OR (a.empresa_id IS NULL AND a.grupo_id IS NOT NULL AND a.grupo_id = em.grupo_id)
    );
$$;

CREATE OR REPLACE FUNCTION public.fn_mis_estacionamientos()
RETURNS SETOF uuid LANGUAGE sql STABLE
SECURITY DEFINER SET search_path = public, pg_temp
AS $$
  SELECT estacionamiento_id FROM fn_estacionamientos_visibles(fn_perfil_actual());
$$;

CREATE OR REPLACE FUNCTION public.fn_mis_empresas()
RETURNS SETOF uuid LANGUAGE sql STABLE
SECURITY DEFINER SET search_path = public, pg_temp
AS $$
  SELECT DISTINCT em.empresa_id
  FROM empresas em
  JOIN sucursales s ON s.empresa_id = em.empresa_id
  JOIN estacionamientos e ON e.sucursal_id = s.sucursal_id
  WHERE e.estacionamiento_id IN (SELECT fn_mis_estacionamientos());
$$;

CREATE OR REPLACE FUNCTION public.fn_tiene_permiso(p_codigo_permiso text)
RETURNS boolean LANGUAGE sql STABLE
SECURITY DEFINER SET search_path = public, pg_temp
AS $$
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

CREATE OR REPLACE FUNCTION public.fn_modulo_habilitado(p_empresa_id uuid, p_codigo_modulo text)
RETURNS boolean LANGUAGE sql STABLE
SECURITY DEFINER SET search_path = public, pg_temp
AS $$
  SELECT EXISTS (
    SELECT 1 FROM v_empresa_modulos_habilitados
    WHERE empresa_id = p_empresa_id AND modulo_codigo = p_codigo_modulo
  );
$$;

-- REVOKE público → sólo authenticated/service_role las pueden ejecutar
REVOKE ALL ON FUNCTION public.fn_perfil_actual() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_es_super_admin() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_estacionamientos_visibles(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_mis_estacionamientos() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_mis_empresas() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_tiene_permiso(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_modulo_habilitado(uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.fn_perfil_actual()                   TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_es_super_admin()                  TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_estacionamientos_visibles(uuid)   TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_mis_estacionamientos()            TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_mis_empresas()                    TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_tiene_permiso(text)               TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_modulo_habilitado(uuid, text)     TO authenticated, service_role;
