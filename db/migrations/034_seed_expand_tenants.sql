-- ============================================================================
-- 034 — Expandir tenants: 6 grupos totales, ~15 empresas, ~30 sucursales,
--        ~40 estacionamientos, ~8000 tickets adicionales.
--
-- Regla operativa asumida: 68 cajones = ~1000 tickets/semana → ~14.7 t/cajón/sem.
-- Aplicado a un mes de historia genera volumen creíble para dashboards.
-- ============================================================================

DO $$
DECLARE
  v_pais uuid; v_moneda uuid; v_tz uuid;
  v_plan_pro uuid; v_plan_ent uuid;
BEGIN
  SELECT pais_id INTO v_pais FROM cat_pais WHERE codigo_iso2='MX' LIMIT 1;
  SELECT moneda_id INTO v_moneda FROM cat_moneda WHERE codigo_iso='MXN' LIMIT 1;
  IF v_moneda IS NULL THEN SELECT moneda_id INTO v_moneda FROM cat_moneda LIMIT 1; END IF;
  SELECT timezone_id INTO v_tz FROM cat_timezone LIMIT 1;
  SELECT plan_id INTO v_plan_pro FROM cat_plan WHERE nombre='Professional' LIMIT 1;
  SELECT plan_id INTO v_plan_ent FROM cat_plan WHERE nombre='Enterprise' LIMIT 1;

  -- ── 3 grupos nuevos con empresas y sucursales ─────────────────────────────
  -- 1. Grupo Palacio (2 empresas, 4 sucursales, 6 plazas)
  WITH gn AS (
    INSERT INTO grupos_empresariales (codigo, nombre, activo)
    VALUES ('GRP_PALACIO', 'Grupo Palacio de Hierro', true)
    RETURNING grupo_id
  ),
  emps AS (
    INSERT INTO empresas (grupo_id, pais_id, moneda_id, codigo, razon_social, nombre_comercial, activo)
    SELECT g.grupo_id, v_pais, v_moneda, x.cod, x.rz, x.nc, true
    FROM gn g, (VALUES
      ('PALACIO_CDMX','El Palacio de Hierro Retail S.A. de C.V.','Palacio CDMX'),
      ('PALACIO_MTY','Palacio Norte S.A. de C.V.','Palacio Norte')
    ) x(cod, rz, nc)
    RETURNING empresa_id, codigo
  ),
  sucs AS (
    INSERT INTO sucursales (empresa_id, codigo, nombre, direccion, activo)
    SELECT e.empresa_id, x.cod, x.nom, x.dir, true
    FROM emps e, (VALUES
      ('PALACIO_CDMX','POLANCO','Palacio Polanco','Molière 222, Polanco'),
      ('PALACIO_CDMX','PERISUR','Palacio Perisur','Anillo Periférico Sur 4690'),
      ('PALACIO_MTY','MTY_CENTRO','Palacio Monterrey Centro','Av. Constitución 500'),
      ('PALACIO_MTY','MTY_VALLE','Palacio Valle Oriente','Av. Lázaro Cárdenas 2500')
    ) x(emp_cod, cod, nom, dir)
    WHERE e.codigo = x.emp_cod
    RETURNING sucursal_id, codigo, empresa_id
  )
  INSERT INTO estacionamientos (sucursal_id, pais_id, timezone_id, codigo, nombre, capacidad_total, activo)
  SELECT s.sucursal_id, v_pais, v_tz, x.cod, x.nom, x.cap, true
  FROM sucs s, (VALUES
    ('POLANCO','P1','Nivel 1',180), ('POLANCO','P2','Nivel 2',180),
    ('PERISUR','PRINCIPAL','Sótano principal',220),
    ('MTY_CENTRO','PRINCIPAL','Estacionamiento único',95),
    ('MTY_VALLE','P1','Nivel 1',140), ('MTY_VALLE','P2','Nivel 2',140)
  ) x(suc_cod, cod, nom, cap)
  WHERE s.codigo = x.suc_cod;

  -- 2. Grupo Vips (2 empresas, 3 sucursales, 3 plazas)
  WITH gn AS (
    INSERT INTO grupos_empresariales (codigo, nombre, activo)
    VALUES ('GRP_VIPS', 'Grupo Alsea Vips', true)
    RETURNING grupo_id
  ),
  emps AS (
    INSERT INTO empresas (grupo_id, pais_id, moneda_id, codigo, razon_social, nombre_comercial, activo)
    SELECT g.grupo_id, v_pais, v_moneda, x.cod, x.rz, x.nc, true
    FROM gn g, (VALUES
      ('ALSEA_VIPS','Operadora Vips S. de R.L. de C.V.','Vips'),
      ('ALSEA_CAFE','Cafeterías Alsea S.A. de C.V.','Alsea Cafés')
    ) x(cod, rz, nc)
    RETURNING empresa_id, codigo
  ),
  sucs AS (
    INSERT INTO sucursales (empresa_id, codigo, nombre, direccion, activo)
    SELECT e.empresa_id, x.cod, x.nom, x.dir, true
    FROM emps e, (VALUES
      ('ALSEA_VIPS','INSURGENTES','Vips Insurgentes','Av. Insurgentes Sur 800'),
      ('ALSEA_VIPS','REFORMA','Vips Reforma','Paseo de la Reforma 180'),
      ('ALSEA_CAFE','SANTA_FE','Café Alsea Santa Fe','Av. Vasco de Quiroga 3800')
    ) x(emp_cod, cod, nom, dir)
    WHERE e.codigo = x.emp_cod
    RETURNING sucursal_id, codigo, empresa_id
  )
  INSERT INTO estacionamientos (sucursal_id, pais_id, timezone_id, codigo, nombre, capacidad_total, activo)
  SELECT s.sucursal_id, v_pais, v_tz, 'PRINCIPAL', 'Estacionamiento único', x.cap, true
  FROM sucs s, (VALUES
    ('INSURGENTES', 45), ('REFORMA', 55), ('SANTA_FE', 80)
  ) x(suc_cod, cap)
  WHERE s.codigo = x.suc_cod;

  -- 3. Grupo Herradura (1 empresa, 2 sucursales, 3 plazas)
  WITH gn AS (
    INSERT INTO grupos_empresariales (codigo, nombre, activo)
    VALUES ('GRP_HERRADURA', 'Grupo Comercial Herradura', true)
    RETURNING grupo_id
  ),
  emps AS (
    INSERT INTO empresas (grupo_id, pais_id, moneda_id, codigo, razon_social, nombre_comercial, activo)
    SELECT g.grupo_id, v_pais, v_moneda, 'HERRADURA', 'Comercial Herradura S.A. de C.V.', 'Herradura', true
    FROM gn g
    RETURNING empresa_id, codigo
  ),
  sucs AS (
    INSERT INTO sucursales (empresa_id, codigo, nombre, direccion, activo)
    SELECT e.empresa_id, x.cod, x.nom, x.dir, true
    FROM emps e, (VALUES
      ('HUIXQUILUCAN','Centro Comercial Huixquilucan','Interlomas'),
      ('MERIDA','Plaza Mérida Norte','Mérida Yucatán')
    ) x(cod, nom, dir)
    RETURNING sucursal_id, codigo
  )
  INSERT INTO estacionamientos (sucursal_id, pais_id, timezone_id, codigo, nombre, capacidad_total, activo)
  SELECT s.sucursal_id, v_pais, v_tz, x.cod, x.nom, x.cap, true
  FROM sucs s, (VALUES
    ('HUIXQUILUCAN','P1','Torre A - Nivel 1',120),
    ('HUIXQUILUCAN','P2','Torre A - Nivel 2',120),
    ('MERIDA','PRINCIPAL','Sótano principal',110)
  ) x(suc_cod, cod, nom, cap)
  WHERE s.codigo = x.suc_cod;

  -- Licencias para las empresas nuevas
  INSERT INTO licencias (empresa_id, plan_id, estado_licencia_id, vigencia_desde, vigencia_hasta, precio_pactado, moneda_id)
  SELECT e.empresa_id, v_plan_pro,
         (SELECT estado_licencia_id FROM cat_estado_licencia WHERE codigo='activa' LIMIT 1),
         CURRENT_DATE - 60, CURRENT_DATE + 365,
         1500 + (random()*2000)::int, v_moneda
  FROM empresas e
  WHERE e.codigo IN ('PALACIO_CDMX','PALACIO_MTY','ALSEA_VIPS','ALSEA_CAFE','HERRADURA');
END $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- Seed masivo de tickets sobre los nuevos estacionamientos (~30 días atrás)
-- Regla: 68 cajones ≈ 1000 tickets/semana → ~14.7 t/cajón/sem
-- Para dev, usamos ~7 t/cajón/sem × 4 semanas ≈ 28 t/cajón/mes.
-- ─────────────────────────────────────────────────────────────────────────────
DO $$
DECLARE
  v_tn uuid; v_tp uuid; v_te uuid; v_tpen uuid; v_tperd uuid; v_tvip uuid;
  v_ea uuid; v_epag uuid; v_ecan uuid;
  v_cajero1 uuid; v_cajero2 uuid;
  est RECORD; n_tick int; i integer;
  v_entrada timestamptz; v_salida timestamptz; v_dur_min int;
  v_tipo uuid; v_estado uuid; v_importe numeric; v_folio text; v_cajero uuid;
BEGIN
  SELECT tipo_sesion_id INTO v_tn   FROM cat_tipo_sesion WHERE codigo='normal';
  SELECT tipo_sesion_id INTO v_tp   FROM cat_tipo_sesion WHERE codigo='preferencial';
  SELECT tipo_sesion_id INTO v_te   FROM cat_tipo_sesion WHERE codigo='empleado';
  SELECT tipo_sesion_id INTO v_tpen FROM cat_tipo_sesion WHERE codigo='pensionado';
  SELECT tipo_sesion_id INTO v_tperd FROM cat_tipo_sesion WHERE codigo='perdido';
  SELECT tipo_sesion_id INTO v_tvip FROM cat_tipo_sesion WHERE codigo='vip';
  SELECT estado_sesion_id INTO v_ea   FROM cat_estado_sesion WHERE codigo='abierta';
  SELECT estado_sesion_id INTO v_epag FROM cat_estado_sesion WHERE codigo='pagada';
  SELECT estado_sesion_id INTO v_ecan FROM cat_estado_sesion WHERE codigo='cancelada';
  SELECT perfil_id INTO v_cajero1 FROM perfiles_usuario WHERE email='cajero1@onlypark.local';
  SELECT perfil_id INTO v_cajero2 FROM perfiles_usuario WHERE email='cajero2@onlypark.local';

  -- Solo los estacionamientos NUEVOS (los que aún no tienen sesiones)
  FOR est IN
    SELECT ee.estacionamiento_id, ee.codigo, ee.capacidad_total
    FROM estacionamientos ee
    LEFT JOIN sesiones s ON s.estacionamiento_id = ee.estacionamiento_id
    WHERE s.sesion_id IS NULL
    GROUP BY ee.estacionamiento_id, ee.codigo, ee.capacidad_total
  LOOP
    -- ~7 tickets por cajón en 30 días
    n_tick := GREATEST(50, LEAST(500, (est.capacidad_total * 7 * 30 / 7)::int));
    -- Cap para no explotar: max 400 por estac
    n_tick := LEAST(n_tick, 400);

    FOR i IN 1..n_tick LOOP
      IF random() < 0.68 THEN v_tipo := v_tn;
      ELSIF random() < 0.82 THEN v_tipo := v_tp;
      ELSIF random() < 0.90 THEN v_tipo := v_te;
      ELSIF random() < 0.96 THEN v_tipo := v_tpen;
      ELSIF random() < 0.99 THEN v_tipo := COALESCE(v_tvip, v_tn);
      ELSE v_tipo := v_tperd; END IF;

      v_entrada := (CURRENT_DATE - (random()*29)::int)::timestamptz
                 + (6 + (random()*17))*interval '1 hour'
                 + (random()*59)*interval '1 minute';

      v_dur_min := CASE
        WHEN v_tipo = v_tn   THEN 20 + (random()*400)::int
        WHEN v_tipo = v_tp   THEN 45 + (random()*480)::int
        WHEN v_tipo = v_te   THEN 240 + (random()*300)::int
        WHEN v_tipo = v_tpen THEN 360 + (random()*480)::int
        ELSE 60 + (random()*720)::int
      END;
      v_salida := v_entrada + (v_dur_min || ' minutes')::interval;

      IF v_salida > NOW() THEN v_estado := v_ea; v_salida := NULL; v_importe := NULL;
      ELSIF random() < 0.03 THEN v_estado := v_ecan; v_importe := 0;
      ELSE
        v_estado := v_epag;
        IF v_dur_min <= 15 THEN v_importe := 0;
        ELSIF v_tipo IN (v_te, v_tpen) THEN v_importe := 0;
        ELSIF v_tipo = v_tp THEN v_importe := 6 * ceil(v_dur_min::numeric/60);
        ELSIF v_tipo = v_tperd THEN v_importe := 150;
        ELSIF v_tipo = v_tvip  THEN v_importe := 0;
        ELSE v_importe := 15 * ceil(v_dur_min::numeric/60);
        END IF;
        IF v_importe < 15 AND v_dur_min > 15 AND v_tipo NOT IN (v_te, v_tpen, COALESCE(v_tvip,v_te)) THEN
          v_importe := 15;
        END IF;
      END IF;

      v_cajero := CASE WHEN random() < 0.55 THEN v_cajero1 ELSE v_cajero2 END;
      v_folio := upper(est.codigo) || 'X-' || to_char(v_entrada,'YYMMDD') || '-' || lpad(i::text,4,'0');

      INSERT INTO sesiones (
        estacionamiento_id, tipo_sesion_id, estado_sesion_id,
        folio_entrada, entrada_at, salida_at,
        cajero_entrada_id, cajero_salida_id,
        importe_calculado, importe_total, requiere_cobro
      ) VALUES (
        est.estacionamiento_id, v_tipo, v_estado,
        v_folio, v_entrada, v_salida, v_cajero,
        CASE WHEN v_salida IS NOT NULL THEN v_cajero END,
        v_importe, v_importe, (v_importe IS NOT NULL AND v_importe > 0)
      );
    END LOOP;
  END LOOP;
END $$;

-- Pagos para todos los nuevos tickets pagados
INSERT INTO pagos (sesion_id, estacionamiento_id, metodo_pago_id, estado_pago_id,
                   cobrado_por, monto, moneda_id, cobrado_at)
SELECT s.sesion_id, s.estacionamiento_id,
       (SELECT metodo_pago_id FROM cat_metodo_pago
         WHERE codigo IN ('efectivo','tarjeta_debito','tarjeta_credito','qr','link_pago','wallet')
         ORDER BY random() LIMIT 1),
       (SELECT estado_pago_id FROM cat_estado_pago WHERE codigo='conciliado' LIMIT 1),
       s.cajero_salida_id, s.importe_total,
       (SELECT moneda_id FROM cat_moneda LIMIT 1),
       s.salida_at
FROM sesiones s
WHERE s.estado_sesion_id = (SELECT estado_sesion_id FROM cat_estado_sesion WHERE codigo='pagada')
  AND s.importe_total > 0
  AND s.folio_entrada LIKE '%X-%'
  AND NOT EXISTS (SELECT 1 FROM pagos p WHERE p.sesion_id = s.sesion_id);

-- Cámaras para los estacionamientos nuevos
INSERT INTO camaras (estacionamiento_id, codigo, nombre, proposito, activa, es_simulada)
SELECT est.estacionamiento_id,
       'CAM_ENT_' || substr(est.estacionamiento_id::text,1,8),
       'Entrada · ' || est.nombre, 'entrada', true, true
FROM estacionamientos est
LEFT JOIN camaras c ON c.estacionamiento_id=est.estacionamiento_id AND c.proposito='entrada'
WHERE c.camara_id IS NULL;

INSERT INTO camaras (estacionamiento_id, codigo, nombre, proposito, activa, es_simulada)
SELECT est.estacionamiento_id,
       'CAM_SAL_' || substr(est.estacionamiento_id::text,1,8),
       'Salida · ' || est.nombre, 'salida', true, true
FROM estacionamientos est
LEFT JOIN camaras c ON c.estacionamiento_id=est.estacionamiento_id AND c.proposito='salida'
WHERE c.camara_id IS NULL;

-- ETL refresh
SELECT dwh.fn_etl_run_all() AS resultado;

-- Verificación
SELECT
  (SELECT COUNT(*) FROM grupos_empresariales WHERE activo) AS grupos,
  (SELECT COUNT(*) FROM empresas WHERE activo) AS empresas,
  (SELECT COUNT(*) FROM sucursales WHERE activo) AS sucursales,
  (SELECT COUNT(*) FROM estacionamientos WHERE activo) AS estacionamientos,
  (SELECT SUM(capacidad_total)::int FROM estacionamientos) AS cajones_totales,
  (SELECT COUNT(*) FROM sesiones) AS tickets_totales,
  (SELECT COUNT(*) FROM camaras WHERE activa) AS camaras_activas,
  (SELECT SUM(importe_total)::int FROM sesiones WHERE estado_sesion_id=(SELECT estado_sesion_id FROM cat_estado_sesion WHERE codigo='pagada')) AS ingresos_totales;
