-- ══════════════════════════════════════════
-- ONLYPARK · 019 · Row Level Security (RLS) policies
-- ══════════════════════════════════════════
-- Aplica RLS a todas las tablas operativas + catálogos.
-- Requiere 002-018.
--
-- Patrón por tipo de tabla:
--  A) Tablas con estacionamiento_id directo: filtrar por fn_mis_estacionamientos()
--  B) Tablas con empresa_id: filtrar por empresas visibles vía asignaciones
--  C) Catálogos globales (cat_*): SELECT abierto a authenticated; INSERT/UPDATE/DELETE = super_admin
--  D) Catálogos por-tenant: SELECT plantillas globales + propia empresa; escritura solo propia
--  E) Tablas via join (pagos_pension, movimientos_monedero, etc.): subquery al padre

-- ══════════════════════════════════════════
-- Helper adicional: empresas visibles
-- ══════════════════════════════════════════
CREATE OR REPLACE FUNCTION fn_mis_empresas()
RETURNS SETOF UUID LANGUAGE sql STABLE AS $$
  SELECT DISTINCT em.empresa_id
  FROM empresas em
  JOIN sucursales s ON s.empresa_id = em.empresa_id
  JOIN estacionamientos e ON e.sucursal_id = s.sucursal_id
  WHERE e.estacionamiento_id IN (SELECT fn_mis_estacionamientos())
$$;

-- ══════════════════════════════════════════
-- A) Tablas con estacionamiento_id directo
-- ══════════════════════════════════════════
DO $$
DECLARE
  t TEXT;
  tables TEXT[] := ARRAY[
    'sucursales','estacionamientos','sesiones','cortes_caja','camaras','sync_queue',
    'politicas_tarifarias','pagos','pensiones','locales_anunciantes','campanas',
    'cfg_bitacora','cfg_estacionamiento','avisos_operador'
  ];
BEGIN
  FOREACH t IN ARRAY tables LOOP
    EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY;', t);
    EXECUTE format('DROP POLICY IF EXISTS %I ON %I;', t||'_select', t);
    EXECUTE format('DROP POLICY IF EXISTS %I ON %I;', t||'_insert', t);
    EXECUTE format('DROP POLICY IF EXISTS %I ON %I;', t||'_update', t);
    EXECUTE format('DROP POLICY IF EXISTS %I ON %I;', t||'_delete', t);

    -- Sucursales y estacionamientos: el ámbito viene por join, no por estac_id directo.
    -- Se maneja aparte más abajo.
    IF t NOT IN ('sucursales','estacionamientos') THEN
      EXECUTE format($f$
        CREATE POLICY %I ON %I FOR SELECT TO authenticated
        USING (estacionamiento_id IN (SELECT fn_mis_estacionamientos()) OR fn_es_super_admin());
      $f$, t||'_select', t);
      EXECUTE format($f$
        CREATE POLICY %I ON %I FOR INSERT TO authenticated
        WITH CHECK (estacionamiento_id IN (SELECT fn_mis_estacionamientos()) OR fn_es_super_admin());
      $f$, t||'_insert', t);
      EXECUTE format($f$
        CREATE POLICY %I ON %I FOR UPDATE TO authenticated
        USING (estacionamiento_id IN (SELECT fn_mis_estacionamientos()) OR fn_es_super_admin())
        WITH CHECK (estacionamiento_id IN (SELECT fn_mis_estacionamientos()) OR fn_es_super_admin());
      $f$, t||'_update', t);
      EXECUTE format($f$
        CREATE POLICY %I ON %I FOR DELETE TO authenticated
        USING (fn_es_super_admin());
      $f$, t||'_delete', t);
    END IF;
  END LOOP;
END $$;

-- ══════════════════════════════════════════
-- Sucursales y estacionamientos (RLS con ámbito jerárquico)
-- ══════════════════════════════════════════
CREATE POLICY sucursales_select ON sucursales FOR SELECT TO authenticated
  USING (EXISTS (
    SELECT 1 FROM estacionamientos e
    WHERE e.sucursal_id = sucursales.sucursal_id
      AND e.estacionamiento_id IN (SELECT fn_mis_estacionamientos())
  ) OR fn_es_super_admin());
CREATE POLICY sucursales_insert ON sucursales FOR INSERT TO authenticated
  WITH CHECK (fn_tiene_permiso('sucursal.crear') OR fn_es_super_admin());
CREATE POLICY sucursales_update ON sucursales FOR UPDATE TO authenticated
  USING (empresa_id IN (SELECT fn_mis_empresas()) OR fn_es_super_admin())
  WITH CHECK (empresa_id IN (SELECT fn_mis_empresas()) OR fn_es_super_admin());
CREATE POLICY sucursales_delete ON sucursales FOR DELETE TO authenticated
  USING (fn_es_super_admin());

CREATE POLICY estacionamientos_select ON estacionamientos FOR SELECT TO authenticated
  USING (estacionamiento_id IN (SELECT fn_mis_estacionamientos()) OR fn_es_super_admin());
CREATE POLICY estacionamientos_insert ON estacionamientos FOR INSERT TO authenticated
  WITH CHECK (fn_tiene_permiso('estacionamiento.crear') OR fn_es_super_admin());
CREATE POLICY estacionamientos_update ON estacionamientos FOR UPDATE TO authenticated
  USING (estacionamiento_id IN (SELECT fn_mis_estacionamientos()) OR fn_es_super_admin())
  WITH CHECK (estacionamiento_id IN (SELECT fn_mis_estacionamientos()) OR fn_es_super_admin());
CREATE POLICY estacionamientos_delete ON estacionamientos FOR DELETE TO authenticated
  USING (fn_es_super_admin());

-- ══════════════════════════════════════════
-- B) Tablas con empresa_id
-- ══════════════════════════════════════════
ALTER TABLE empresas ENABLE ROW LEVEL SECURITY;
ALTER TABLE clientes ENABLE ROW LEVEL SECURITY;
ALTER TABLE licencias ENABLE ROW LEVEL SECURITY;
ALTER TABLE grupos_empresariales ENABLE ROW LEVEL SECURITY;

CREATE POLICY empresas_select ON empresas FOR SELECT TO authenticated
  USING (empresa_id IN (SELECT fn_mis_empresas()) OR fn_es_super_admin());
CREATE POLICY empresas_write ON empresas FOR ALL TO authenticated
  USING (fn_es_super_admin() OR (empresa_id IN (SELECT fn_mis_empresas()) AND fn_tiene_permiso('empresa.editar')))
  WITH CHECK (fn_es_super_admin() OR empresa_id IN (SELECT fn_mis_empresas()));

CREATE POLICY grupos_select ON grupos_empresariales FOR SELECT TO authenticated
  USING (fn_es_super_admin() OR EXISTS (
    SELECT 1 FROM empresas em WHERE em.grupo_id = grupos_empresariales.grupo_id
      AND em.empresa_id IN (SELECT fn_mis_empresas())
  ));
CREATE POLICY grupos_write ON grupos_empresariales FOR ALL TO authenticated
  USING (fn_es_super_admin()) WITH CHECK (fn_es_super_admin());

CREATE POLICY clientes_select ON clientes FOR SELECT TO authenticated
  USING (empresa_id IN (SELECT fn_mis_empresas()) OR fn_es_super_admin());
CREATE POLICY clientes_write ON clientes FOR ALL TO authenticated
  USING (empresa_id IN (SELECT fn_mis_empresas()) OR fn_es_super_admin())
  WITH CHECK (empresa_id IN (SELECT fn_mis_empresas()) OR fn_es_super_admin());

CREATE POLICY licencias_select ON licencias FOR SELECT TO authenticated
  USING (empresa_id IN (SELECT fn_mis_empresas()) OR fn_es_super_admin());
CREATE POLICY licencias_write ON licencias FOR ALL TO authenticated
  USING (fn_es_super_admin()) WITH CHECK (fn_es_super_admin());

-- ══════════════════════════════════════════
-- E) Tablas via join (usan subselect al padre)
-- ══════════════════════════════════════════

-- vehiculos → cliente → empresa
ALTER TABLE vehiculos ENABLE ROW LEVEL SECURITY;
CREATE POLICY vehiculos_select ON vehiculos FOR SELECT TO authenticated
  USING (cliente_id IS NULL OR EXISTS (
    SELECT 1 FROM clientes c WHERE c.cliente_id = vehiculos.cliente_id
      AND c.empresa_id IN (SELECT fn_mis_empresas())
  ) OR fn_es_super_admin());
CREATE POLICY vehiculos_write ON vehiculos FOR ALL TO authenticated
  USING (fn_es_super_admin() OR cliente_id IS NULL OR EXISTS (
    SELECT 1 FROM clientes c WHERE c.cliente_id = vehiculos.cliente_id
      AND c.empresa_id IN (SELECT fn_mis_empresas())
  ))
  WITH CHECK (fn_es_super_admin() OR cliente_id IS NULL OR EXISTS (
    SELECT 1 FROM clientes c WHERE c.cliente_id = vehiculos.cliente_id
      AND c.empresa_id IN (SELECT fn_mis_empresas())
  ));

-- placas: tabla global (uniqueness por país). Lectura abierta para authenticated
-- (necesario para LPR y consultas rápidas por número). Escritura autenticada.
ALTER TABLE placas ENABLE ROW LEVEL SECURITY;
CREATE POLICY placas_select ON placas FOR SELECT TO authenticated USING (true);
CREATE POLICY placas_insert ON placas FOR INSERT TO authenticated WITH CHECK (true);
CREATE POLICY placas_update ON placas FOR UPDATE TO authenticated
  USING (fn_tiene_permiso('placa.editar') OR fn_es_super_admin());
CREATE POLICY placas_delete ON placas FOR DELETE TO authenticated
  USING (fn_es_super_admin());

ALTER TABLE vinculos_placa_vehiculo ENABLE ROW LEVEL SECURITY;
CREATE POLICY vpv_select ON vinculos_placa_vehiculo FOR SELECT TO authenticated
  USING (EXISTS (
    SELECT 1 FROM vehiculos v LEFT JOIN clientes c ON c.cliente_id = v.cliente_id
    WHERE v.vehiculo_id = vinculos_placa_vehiculo.vehiculo_id
      AND (c.empresa_id IN (SELECT fn_mis_empresas()) OR c.empresa_id IS NULL)
  ) OR fn_es_super_admin());
CREATE POLICY vpv_write ON vinculos_placa_vehiculo FOR ALL TO authenticated
  USING (fn_es_super_admin() OR EXISTS (
    SELECT 1 FROM vehiculos v LEFT JOIN clientes c ON c.cliente_id = v.cliente_id
    WHERE v.vehiculo_id = vinculos_placa_vehiculo.vehiculo_id
      AND (c.empresa_id IN (SELECT fn_mis_empresas()) OR c.empresa_id IS NULL)
  ))
  WITH CHECK (fn_es_super_admin() OR EXISTS (
    SELECT 1 FROM vehiculos v LEFT JOIN clientes c ON c.cliente_id = v.cliente_id
    WHERE v.vehiculo_id = vinculos_placa_vehiculo.vehiculo_id
      AND (c.empresa_id IN (SELECT fn_mis_empresas()) OR c.empresa_id IS NULL)
  ));

-- reglas_tarifarias, tarifas_historico → politicas_tarifarias
ALTER TABLE reglas_tarifarias ENABLE ROW LEVEL SECURITY;
CREATE POLICY reglas_select ON reglas_tarifarias FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM politicas_tarifarias p WHERE p.politica_id = reglas_tarifarias.politica_id
    AND p.estacionamiento_id IN (SELECT fn_mis_estacionamientos())) OR fn_es_super_admin());
CREATE POLICY reglas_write ON reglas_tarifarias FOR ALL TO authenticated
  USING (fn_es_super_admin() OR EXISTS (SELECT 1 FROM politicas_tarifarias p WHERE p.politica_id = reglas_tarifarias.politica_id
    AND p.estacionamiento_id IN (SELECT fn_mis_estacionamientos())))
  WITH CHECK (fn_es_super_admin() OR EXISTS (SELECT 1 FROM politicas_tarifarias p WHERE p.politica_id = reglas_tarifarias.politica_id
    AND p.estacionamiento_id IN (SELECT fn_mis_estacionamientos())));

ALTER TABLE tarifas_historico ENABLE ROW LEVEL SECURITY;
CREATE POLICY thist_select ON tarifas_historico FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM reglas_tarifarias r JOIN politicas_tarifarias p ON p.politica_id = r.politica_id
    WHERE r.regla_id = tarifas_historico.regla_id
      AND p.estacionamiento_id IN (SELECT fn_mis_estacionamientos())) OR fn_es_super_admin());
CREATE POLICY thist_write ON tarifas_historico FOR ALL TO authenticated
  USING (fn_es_super_admin()) WITH CHECK (fn_es_super_admin());

-- capturas_lpr → camara → estacionamiento
ALTER TABLE capturas_lpr ENABLE ROW LEVEL SECURITY;
CREATE POLICY lpr_select ON capturas_lpr FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM camaras c WHERE c.camara_id = capturas_lpr.camara_id
    AND c.estacionamiento_id IN (SELECT fn_mis_estacionamientos())) OR fn_es_super_admin());
CREATE POLICY lpr_write ON capturas_lpr FOR ALL TO authenticated
  USING (fn_es_super_admin() OR EXISTS (SELECT 1 FROM camaras c WHERE c.camara_id = capturas_lpr.camara_id
    AND c.estacionamiento_id IN (SELECT fn_mis_estacionamientos())))
  WITH CHECK (fn_es_super_admin() OR EXISTS (SELECT 1 FROM camaras c WHERE c.camara_id = capturas_lpr.camara_id
    AND c.estacionamiento_id IN (SELECT fn_mis_estacionamientos())));

-- monederos, monedero_placas, movimientos_monedero → cliente → empresa
ALTER TABLE monederos ENABLE ROW LEVEL SECURITY;
CREATE POLICY monederos_select ON monederos FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM clientes c WHERE c.cliente_id = monederos.cliente_id
    AND c.empresa_id IN (SELECT fn_mis_empresas())) OR fn_es_super_admin());
CREATE POLICY monederos_write ON monederos FOR ALL TO authenticated
  USING (fn_es_super_admin() OR EXISTS (SELECT 1 FROM clientes c WHERE c.cliente_id = monederos.cliente_id
    AND c.empresa_id IN (SELECT fn_mis_empresas())))
  WITH CHECK (fn_es_super_admin() OR EXISTS (SELECT 1 FROM clientes c WHERE c.cliente_id = monederos.cliente_id
    AND c.empresa_id IN (SELECT fn_mis_empresas())));

ALTER TABLE monedero_placas ENABLE ROW LEVEL SECURITY;
CREATE POLICY mp_select ON monedero_placas FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM monederos m JOIN clientes c ON c.cliente_id = m.cliente_id
    WHERE m.monedero_id = monedero_placas.monedero_id
      AND c.empresa_id IN (SELECT fn_mis_empresas())) OR fn_es_super_admin());
CREATE POLICY mp_write ON monedero_placas FOR ALL TO authenticated
  USING (fn_es_super_admin() OR EXISTS (SELECT 1 FROM monederos m JOIN clientes c ON c.cliente_id = m.cliente_id
    WHERE m.monedero_id = monedero_placas.monedero_id
      AND c.empresa_id IN (SELECT fn_mis_empresas())))
  WITH CHECK (fn_es_super_admin() OR EXISTS (SELECT 1 FROM monederos m JOIN clientes c ON c.cliente_id = m.cliente_id
    WHERE m.monedero_id = monedero_placas.monedero_id
      AND c.empresa_id IN (SELECT fn_mis_empresas())));

ALTER TABLE movimientos_monedero ENABLE ROW LEVEL SECURITY;
CREATE POLICY mm_select ON movimientos_monedero FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM monederos m JOIN clientes c ON c.cliente_id = m.cliente_id
    WHERE m.monedero_id = movimientos_monedero.monedero_id
      AND c.empresa_id IN (SELECT fn_mis_empresas())) OR fn_es_super_admin());
CREATE POLICY mm_write ON movimientos_monedero FOR ALL TO authenticated
  USING (fn_es_super_admin() OR EXISTS (SELECT 1 FROM monederos m JOIN clientes c ON c.cliente_id = m.cliente_id
    WHERE m.monedero_id = movimientos_monedero.monedero_id
      AND c.empresa_id IN (SELECT fn_mis_empresas())))
  WITH CHECK (fn_es_super_admin() OR EXISTS (SELECT 1 FROM monederos m JOIN clientes c ON c.cliente_id = m.cliente_id
    WHERE m.monedero_id = movimientos_monedero.monedero_id
      AND c.empresa_id IN (SELECT fn_mis_empresas())));

-- pagos_pension → pension → estacionamiento
ALTER TABLE pagos_pension ENABLE ROW LEVEL SECURITY;
CREATE POLICY pp_select ON pagos_pension FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM pensiones p WHERE p.pension_id = pagos_pension.pension_id
    AND p.estacionamiento_id IN (SELECT fn_mis_estacionamientos())) OR fn_es_super_admin());
CREATE POLICY pp_write ON pagos_pension FOR ALL TO authenticated
  USING (fn_es_super_admin() OR EXISTS (SELECT 1 FROM pensiones p WHERE p.pension_id = pagos_pension.pension_id
    AND p.estacionamiento_id IN (SELECT fn_mis_estacionamientos())))
  WITH CHECK (fn_es_super_admin() OR EXISTS (SELECT 1 FROM pensiones p WHERE p.pension_id = pagos_pension.pension_id
    AND p.estacionamiento_id IN (SELECT fn_mis_estacionamientos())));

-- campana_* → campana → estacionamiento
DO $$
DECLARE
  t TEXT;
  tables TEXT[] := ARRAY['campana_tipos_sesion','campana_franjas','campana_dias_semana',
                          'campana_reglas_impresion','impresiones_campana'];
BEGIN
  FOREACH t IN ARRAY tables LOOP
    EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY;', t);
    EXECUTE format($f$
      CREATE POLICY %I ON %I FOR SELECT TO authenticated
      USING (EXISTS (SELECT 1 FROM campanas c WHERE c.campana_id = %I.campana_id
        AND c.estacionamiento_id IN (SELECT fn_mis_estacionamientos())) OR fn_es_super_admin());
    $f$, t||'_select', t, t);
    EXECUTE format($f$
      CREATE POLICY %I ON %I FOR ALL TO authenticated
      USING (fn_es_super_admin() OR EXISTS (SELECT 1 FROM campanas c WHERE c.campana_id = %I.campana_id
        AND c.estacionamiento_id IN (SELECT fn_mis_estacionamientos())))
      WITH CHECK (fn_es_super_admin() OR EXISTS (SELECT 1 FROM campanas c WHERE c.campana_id = %I.campana_id
        AND c.estacionamiento_id IN (SELECT fn_mis_estacionamientos())));
    $f$, t||'_write', t, t, t);
  END LOOP;
END $$;

-- conversiones_campana → impresion → campana → estacionamiento
ALTER TABLE conversiones_campana ENABLE ROW LEVEL SECURITY;
CREATE POLICY conv_select ON conversiones_campana FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM impresiones_campana i JOIN campanas c ON c.campana_id = i.campana_id
    WHERE i.impresion_id = conversiones_campana.impresion_id
      AND c.estacionamiento_id IN (SELECT fn_mis_estacionamientos())) OR fn_es_super_admin());
CREATE POLICY conv_write ON conversiones_campana FOR ALL TO authenticated
  USING (fn_es_super_admin() OR EXISTS (SELECT 1 FROM impresiones_campana i JOIN campanas c ON c.campana_id = i.campana_id
    WHERE i.impresion_id = conversiones_campana.impresion_id
      AND c.estacionamiento_id IN (SELECT fn_mis_estacionamientos())))
  WITH CHECK (fn_es_super_admin() OR EXISTS (SELECT 1 FROM impresiones_campana i JOIN campanas c ON c.campana_id = i.campana_id
    WHERE i.impresion_id = conversiones_campana.impresion_id
      AND c.estacionamiento_id IN (SELECT fn_mis_estacionamientos())));

-- log_evento: super_admin ve todo, admins ven su ámbito
ALTER TABLE log_evento ENABLE ROW LEVEL SECURITY;
CREATE POLICY log_select ON log_evento FOR SELECT TO authenticated
  USING (fn_es_super_admin() OR
         (estacionamiento_id IS NOT NULL AND estacionamiento_id IN (SELECT fn_mis_estacionamientos())));
CREATE POLICY log_insert ON log_evento FOR INSERT TO authenticated WITH CHECK (true);
-- INSERT abierto: fn_log() controla el "si loguea o no" según cfg_bitacora.

-- Catálogos por-tenant (cat_tipo_sesion, cat_tipo_tarifa, cat_tipo_cortesia, cat_tipo_descuento, cat_tipo_cliente, cat_tipo_pension)
DO $$
DECLARE
  t TEXT;
  tables TEXT[] := ARRAY['cat_tipo_sesion','cat_tipo_tarifa','cat_tipo_cortesia',
                          'cat_tipo_descuento','cat_tipo_cliente','cat_tipo_pension'];
BEGIN
  FOREACH t IN ARRAY tables LOOP
    EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY;', t);
    EXECUTE format($f$
      CREATE POLICY %I ON %I FOR SELECT TO authenticated
      USING (empresa_id IS NULL OR empresa_id IN (SELECT fn_mis_empresas()) OR fn_es_super_admin());
    $f$, t||'_select', t);
    EXECUTE format($f$
      CREATE POLICY %I ON %I FOR ALL TO authenticated
      USING (fn_es_super_admin() OR (empresa_id IS NOT NULL AND empresa_id IN (SELECT fn_mis_empresas())))
      WITH CHECK (fn_es_super_admin() OR (empresa_id IS NOT NULL AND empresa_id IN (SELECT fn_mis_empresas())));
    $f$, t||'_write', t);
  END LOOP;
END $$;

-- cat_turno, cat_franja: RLS por estacionamiento
DO $$
DECLARE
  t TEXT;
  tables TEXT[] := ARRAY['cat_turno','cat_franja'];
BEGIN
  FOREACH t IN ARRAY tables LOOP
    EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY;', t);
    EXECUTE format($f$
      CREATE POLICY %I ON %I FOR SELECT TO authenticated
      USING (estacionamiento_id IN (SELECT fn_mis_estacionamientos()) OR fn_es_super_admin());
    $f$, t||'_select', t);
    EXECUTE format($f$
      CREATE POLICY %I ON %I FOR ALL TO authenticated
      USING (estacionamiento_id IN (SELECT fn_mis_estacionamientos()) OR fn_es_super_admin())
      WITH CHECK (estacionamiento_id IN (SELECT fn_mis_estacionamientos()) OR fn_es_super_admin());
    $f$, t||'_write', t);
  END LOOP;
END $$;

-- Catálogos globales: SELECT abierto a authenticated, escritura solo super_admin
DO $$
DECLARE
  t TEXT;
  tables TEXT[] := ARRAY[
    'cat_pais','cat_moneda','cat_timezone','cat_modulo','cat_rol','cat_permiso','cat_rol_permiso',
    'cat_plan','cat_tipo_limite','cat_metodo_pago','cat_tipo_vehiculo','cat_tipo_bitacora',
    'cat_estado_sesion','cat_estado_pago','cat_estado_pension','cat_estado_licencia',
    'cat_estado_movimiento_monedero','cat_tipo_movimiento_monedero','cat_tipo_promocion',
    'cat_tipo_regla_impresion','plan_modulos','plan_limites','licencia_modulo_overrides',
    'versiones_app'
  ];
BEGIN
  FOREACH t IN ARRAY tables LOOP
    EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY;', t);
    EXECUTE format($f$CREATE POLICY %I ON %I FOR SELECT TO authenticated USING (true);$f$,
                   t||'_select', t);
    EXECUTE format($f$CREATE POLICY %I ON %I FOR ALL TO authenticated
                     USING (fn_es_super_admin()) WITH CHECK (fn_es_super_admin());$f$,
                   t||'_write', t);
  END LOOP;
END $$;

-- Perfiles: ver los propios + los del ámbito administrable
ALTER TABLE perfiles_usuario ENABLE ROW LEVEL SECURITY;
CREATE POLICY perfil_self_select ON perfiles_usuario FOR SELECT TO authenticated
  USING (auth_user_id = auth.uid() OR fn_es_super_admin() OR EXISTS (
    SELECT 1 FROM asignaciones_rol a
    WHERE a.perfil_id = perfiles_usuario.perfil_id
      AND (a.grupo_id IN (SELECT em.grupo_id FROM empresas em WHERE em.empresa_id IN (SELECT fn_mis_empresas()))
           OR a.empresa_id IN (SELECT fn_mis_empresas())
           OR a.estacionamiento_id IN (SELECT fn_mis_estacionamientos()))
  ));
CREATE POLICY perfil_self_update ON perfiles_usuario FOR UPDATE TO authenticated
  USING (auth_user_id = auth.uid() OR fn_es_super_admin())
  WITH CHECK (auth_user_id = auth.uid() OR fn_es_super_admin());
CREATE POLICY perfil_insert ON perfiles_usuario FOR INSERT TO authenticated
  WITH CHECK (auth_user_id = auth.uid() OR fn_es_super_admin());

ALTER TABLE asignaciones_rol ENABLE ROW LEVEL SECURITY;
CREATE POLICY asig_select ON asignaciones_rol FOR SELECT TO authenticated
  USING (perfil_id = fn_perfil_actual() OR fn_es_super_admin() OR
         (estacionamiento_id IS NOT NULL AND estacionamiento_id IN (SELECT fn_mis_estacionamientos())) OR
         (empresa_id IS NOT NULL AND empresa_id IN (SELECT fn_mis_empresas())));
CREATE POLICY asig_write ON asignaciones_rol FOR ALL TO authenticated
  USING (fn_es_super_admin() OR fn_tiene_permiso('rol.asignar'))
  WITH CHECK (fn_es_super_admin() OR fn_tiene_permiso('rol.asignar'));
