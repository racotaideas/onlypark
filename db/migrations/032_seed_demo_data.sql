-- ============================================================================
-- 032 — Seed masivo de datos demo para que dashboards se vean con carnita
--
-- Meta: dataset creíble en las 6 plazas para que los portales Admin y
-- Corporativo carguen KPIs y tablas sin verse vacíos.
--
-- Incluye:
--   1. 30 clientes con vehículos y placas
--   2. 8 pensiones activas
--   3. 6 empleados de plaza (extras a los cajeros ya seed)
--   4. 4 locales anunciantes + 5 campañas de promoción con impresiones
--   5. 12 cámaras LPR (2 por plaza: entrada y salida)
--   6. 8 cortes de caja (2 por plaza principal, mix apertura/cierre)
--   7. ~300 sesiones distribuidas: 60% en IWOL, 40% Carso/ABC, últimos 30 días,
--      mix de tipos (normal 70%, preferencial 15%, empleado 8%, pensión 5%,
--      perdido 2%), 85% pagadas, 10% abiertas ahora, 5% canceladas.
--   8. Pagos generados para las sesiones pagadas.
--   9. Bitácora de eventos operativos (login, entrada, cobro, cortesía).
-- ============================================================================

-- ── Helpers ─────────────────────────────────────────────────────────────────
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname='pgcrypto') THEN
    CREATE EXTENSION IF NOT EXISTS pgcrypto;
  END IF;
END $$;

-- Truncar solo tablas transaccionales de la demo (no borra catálogos ni tenants)
TRUNCATE public.sesiones, public.pagos, public.cortes_caja RESTART IDENTITY CASCADE;

-- ─────────────────────────────────────────────────────────────────────────────
-- 1) 30 clientes con 30 vehículos y sus placas
-- ─────────────────────────────────────────────────────────────────────────────
DO $$
DECLARE
  v_emp_iwol   uuid;
  v_emp_carso  uuid;
  v_emp_abc    uuid;
  v_tc_ind     uuid;
  v_tv         uuid;
  i integer; j integer;
  v_cliente_id uuid; v_vehi_id uuid; v_placa_id uuid;
  nombres text[] := ARRAY['Ana','Luis','María','Carlos','Sofía','Pedro','Laura','Miguel','Elena','Diego',
                          'Paula','Jorge','Andrea','Fernando','Carmen','Ricardo','Isabel','Javier','Patricia','Roberto',
                          'Mónica','Alberto','Rosa','Manuel','Beatriz','Rafael','Silvia','Antonio','Verónica','Sergio'];
  apellidos text[] := ARRAY['García','Rodríguez','Martínez','López','González','Hernández','Pérez','Sánchez','Ramírez','Torres',
                            'Flores','Rivera','Gómez','Díaz','Cruz','Reyes','Morales','Ortiz','Vargas','Castillo',
                            'Jiménez','Ruiz','Álvarez','Mendoza','Aguilar','Silva','Romero','Chávez','Guzmán','Núñez'];
  marcas text[] := ARRAY['Nissan','Toyota','Volkswagen','Chevrolet','Honda','Mazda','Ford','Hyundai','KIA','Renault'];
  modelos text[] := ARRAY['Sedan','Versa','Aveo','Sentra','Vento','Jetta','Corolla','Yaris','Rio','Tsuru'];
  colores text[] := ARRAY['Blanco','Negro','Gris','Rojo','Azul','Plata','Beige'];
  letras text := 'ABCDEFGHJKLMNPQRSTUVWXYZ';
  digitos text := '0123456789';
BEGIN
  SELECT empresa_id INTO v_emp_iwol  FROM empresas WHERE codigo='IWOL';
  SELECT empresa_id INTO v_emp_carso FROM empresas WHERE codigo='CARSO_INMOB';
  SELECT empresa_id INTO v_emp_abc   FROM empresas WHERE codigo='HOSPITAL_ABC';
  SELECT tipo_cliente_id INTO v_tc_ind FROM cat_tipo_cliente WHERE codigo IN ('individual','persona_fisica') LIMIT 1;
  IF v_tc_ind IS NULL THEN SELECT tipo_cliente_id INTO v_tc_ind FROM cat_tipo_cliente LIMIT 1; END IF;
  SELECT tipo_vehiculo_id INTO v_tv FROM cat_tipo_vehiculo LIMIT 1;

  FOR i IN 1..30 LOOP
    -- cliente
    INSERT INTO clientes (empresa_id, tipo_cliente_id, nombre, apellidos, telefono, activo)
    VALUES (
      CASE WHEN i <= 12 THEN v_emp_iwol WHEN i <= 22 THEN v_emp_carso ELSE v_emp_abc END,
      v_tc_ind,
      nombres[1 + (i-1) % array_length(nombres,1)],
      apellidos[1 + (i-1) % array_length(apellidos,1)],
      '55' || lpad((10000000 + (random()*89999999)::int)::text, 8, '0'),
      true
    ) RETURNING cliente_id INTO v_cliente_id;

    -- vehículo
    INSERT INTO vehiculos (cliente_id, tipo_vehiculo_id, marca, modelo, anio, color, activo)
    VALUES (
      v_cliente_id, v_tv,
      marcas[1 + (i-1) % array_length(marcas,1)],
      modelos[1 + (i-1) % array_length(modelos,1)],
      2015 + (random()*10)::int,
      colores[1 + (i-1) % array_length(colores,1)],
      true
    ) RETURNING vehiculo_id INTO v_vehi_id;

    -- placa (formato MX típico: ABC-1234)
    INSERT INTO placas (numero, formato_original, pais_id, activa)
    VALUES (
      substr(letras, 1+((random()*24)::int), 1) ||
      substr(letras, 1+((random()*24)::int), 1) ||
      substr(letras, 1+((random()*24)::int), 1) || '-' ||
      lpad((1000 + (random()*8999)::int)::text, 4, '0'),
      'MX_LETRA_NUMERO',
      (SELECT pais_id FROM cat_pais WHERE codigo_iso2='MX' LIMIT 1),
      true
    ) RETURNING placa_id INTO v_placa_id;

    -- vínculo placa <-> vehículo
    INSERT INTO vinculos_placa_vehiculo (placa_id, vehiculo_id, vigente_desde)
    VALUES (v_placa_id, v_vehi_id, CURRENT_DATE - (random()*365)::int)
    ON CONFLICT DO NOTHING;
  END LOOP;
END $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 2) 8 pensiones activas
-- ─────────────────────────────────────────────────────────────────────────────
DO $$
DECLARE
  v_tp uuid; v_ep uuid; v_est uuid;
  i integer := 1;
  r RECORD;
BEGIN
  SELECT tipo_pension_id  INTO v_tp FROM cat_tipo_pension WHERE codigo IN ('mensual','base') LIMIT 1;
  IF v_tp IS NULL THEN SELECT tipo_pension_id INTO v_tp FROM cat_tipo_pension LIMIT 1; END IF;
  SELECT estado_pension_id INTO v_ep FROM cat_estado_pension WHERE codigo='activo';
  IF v_ep IS NULL THEN SELECT estado_pension_id INTO v_ep FROM cat_estado_pension LIMIT 1; END IF;

  FOR r IN
    SELECT c.cliente_id, v.vehiculo_id, vpv.placa_id, c.empresa_id
    FROM clientes c
    JOIN vehiculos v ON v.cliente_id=c.cliente_id
    JOIN vinculos_placa_vehiculo vpv ON vpv.vehiculo_id=v.vehiculo_id AND vpv.vigente_hasta IS NULL
    ORDER BY random() LIMIT 8
  LOOP
    SELECT est.estacionamiento_id INTO v_est
      FROM estacionamientos est
      JOIN sucursales s ON s.sucursal_id=est.sucursal_id
      WHERE s.empresa_id = r.empresa_id LIMIT 1;
    INSERT INTO pensiones_base (
      estacionamiento_id, cliente_id, vehiculo_id, placa_id, tipo_pension_id, estado_pension_id,
      monto_mensual, fecha_inicio, fecha_fin, hora_inicio, hora_fin, dia_pago, codigo_acceso, activo
    ) VALUES (
      v_est, r.cliente_id, r.vehiculo_id, r.placa_id, v_tp, v_ep,
      800 + (random()*1200)::int, CURRENT_DATE - (random()*180)::int,
      CURRENT_DATE + 30 + (random()*90)::int,
      '06:00'::time, '22:00'::time, 5 + (random()*10)::int,
      'PEN-' || lpad(i::text, 4, '0'), true
    );
    i := i+1;
  END LOOP;
END $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 3) 6 empleados extras
-- ─────────────────────────────────────────────────────────────────────────────
INSERT INTO perfiles_usuario (email, nombre_completo, activo, idioma)
SELECT
  'empleado' || g || '@onlypark.local',
  ('Empleado ' || (ARRAY['Norte','Sur','Este','Oeste','Centro','Principal'])[g]),
  true, 'es'
FROM generate_series(1,6) g
ON CONFLICT (email) DO NOTHING;

-- ─────────────────────────────────────────────────────────────────────────────
-- 4) 4 locales anunciantes + 5 campañas
-- ─────────────────────────────────────────────────────────────────────────────
INSERT INTO locales_anunciantes (estacionamiento_id, nombre, numero_local, categoria, contacto, telefono, activo)
SELECT est.estacionamiento_id, unnest(ARRAY['Café Aroma','Pizzas Napolitanas','Farmacia 24h','Boutique Luna']),
       unnest(ARRAY['L-01','L-02','L-03','L-04']),
       unnest(ARRAY['Alimentos','Alimentos','Salud','Moda']),
       unnest(ARRAY['Ana Ruiz','Luis Vega','Dra. Marín','Sofía Cano']),
       unnest(ARRAY['5511111111','5522222222','5533333333','5544444444']),
       true
FROM estacionamientos est WHERE est.codigo='PRINCIPAL' LIMIT 1
ON CONFLICT DO NOTHING;

DO $$
DECLARE
  v_est uuid; v_tp uuid; v_lok uuid;
  loc RECORD; i integer := 1;
BEGIN
  SELECT est.estacionamiento_id INTO v_est
  FROM estacionamientos est
  JOIN sucursales s ON s.sucursal_id=est.sucursal_id
  JOIN empresas e ON e.empresa_id=s.empresa_id WHERE e.codigo='IWOL' LIMIT 1;

  SELECT tipo_promocion_id INTO v_tp FROM cat_tipo_promocion LIMIT 1;

  FOR loc IN SELECT local_id, nombre FROM locales_anunciantes ORDER BY nombre LOOP
    INSERT INTO campanas_base (
      estacionamiento_id, local_id, tipo_promocion_id, nombre, titulo_promo, texto_promo,
      valor_promo, vigencia_desde, vigencia_hasta, prioridad, max_impresiones, estado
    ) VALUES (
      v_est, loc.local_id, v_tp,
      'Promo ' || loc.nombre,
      '2x1 en ' || loc.nombre,
      'Presenta tu boleto y obtén 2x1 este mes en ' || loc.nombre,
      2.0, CURRENT_DATE - 7, CURRENT_DATE + 60,
      10 - i, 5000, 'activa'
    );
    i := i + 1;
    EXIT WHEN i > 5;
  END LOOP;

  -- 5ta campaña genérica
  INSERT INTO campanas_base (
    estacionamiento_id, tipo_promocion_id, nombre, titulo_promo, texto_promo,
    valor_promo, vigencia_desde, vigencia_hasta, prioridad, max_impresiones, estado
  ) VALUES (
    v_est, v_tp, 'Bienvenida ONLYPARK',
    'Gracias por preferirnos', 'Regresa pronto y disfruta de nuestras tiendas',
    0, CURRENT_DATE - 30, CURRENT_DATE + 90, 1, 10000, 'activa'
  );
END $$;

-- Impresiones se generan DESPUÉS del seed de sesiones (dependen de sesion_id).
-- Ver bloque después de sesiones.

-- ─────────────────────────────────────────────────────────────────────────────
-- 5) 12 cámaras LPR (2 por plaza)
-- ─────────────────────────────────────────────────────────────────────────────
INSERT INTO camaras (estacionamiento_id, codigo, nombre, proposito, activa, es_simulada)
SELECT est.estacionamiento_id,
       'CAM_ENT_' || upper(est.codigo) || '_' || substr(est.estacionamiento_id::text,1,4),
       'Entrada · ' || est.nombre,
       'entrada', true, true
FROM estacionamientos est
ON CONFLICT DO NOTHING;

INSERT INTO camaras (estacionamiento_id, codigo, nombre, proposito, activa, es_simulada)
SELECT est.estacionamiento_id,
       'CAM_SAL_' || upper(est.codigo) || '_' || substr(est.estacionamiento_id::text,1,4),
       'Salida · ' || est.nombre,
       'salida', true, true
FROM estacionamientos est
ON CONFLICT DO NOTHING;

-- ─────────────────────────────────────────────────────────────────────────────
-- 6) 12 cortes de caja (2 por plaza, uno abierto + uno cerrado)
-- ─────────────────────────────────────────────────────────────────────────────
DO $$
DECLARE
  est RECORD; v_cajero uuid; v_turno_m uuid; v_turno_v uuid;
BEGIN
  SELECT perfil_id INTO v_cajero FROM perfiles_usuario WHERE email='cajero1@onlypark.local';
  SELECT turno_id INTO v_turno_m FROM cat_turno WHERE codigo IN ('matutino','MAT') LIMIT 1;
  SELECT turno_id INTO v_turno_v FROM cat_turno WHERE codigo IN ('vespertino','VESP') LIMIT 1;
  IF v_turno_m IS NULL THEN SELECT turno_id INTO v_turno_m FROM cat_turno LIMIT 1; END IF;
  IF v_turno_v IS NULL THEN v_turno_v := v_turno_m; END IF;

  FOR est IN SELECT estacionamiento_id, nombre FROM estacionamientos LOOP
    -- Corte cerrado ayer matutino
    INSERT INTO cortes_caja (estacionamiento_id, cajero_id, turno_id, tipo,
                              inicio_at, fin_at, fondo_inicial, total_cobrado, total_entregado, estado, notas)
    VALUES (est.estacionamiento_id, v_cajero, v_turno_m, 'cierre',
            (CURRENT_DATE - 1)::timestamptz + '07:00'::time,
            (CURRENT_DATE - 1)::timestamptz + '15:00'::time,
            500, 3500 + (random()*2000)::int, 4000 + (random()*2500)::int,
            'cerrado', 'Corte matutino de demo');
    -- Corte abierto hoy vespertino
    INSERT INTO cortes_caja (estacionamiento_id, cajero_id, turno_id, tipo,
                              inicio_at, fin_at, fondo_inicial, total_cobrado, estado, notas)
    VALUES (est.estacionamiento_id, v_cajero, v_turno_v, 'apertura',
            CURRENT_DATE::timestamptz + '15:00'::time,
            NULL, 500, 800 + (random()*1500)::int,
            'activo', 'Turno vespertino en curso');
  END LOOP;
END $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 7) ~300 sesiones distribuidas
-- ─────────────────────────────────────────────────────────────────────────────
DO $$
DECLARE
  v_tipo_normal uuid; v_tipo_pref uuid; v_tipo_emp uuid; v_tipo_pen uuid; v_tipo_perd uuid;
  v_est_abierta uuid; v_est_pagada uuid; v_est_cancelada uuid;
  v_cajero1 uuid; v_cajero2 uuid;
  est RECORD; placa RECORD; pen RECORD;
  i integer;
  v_entrada timestamptz; v_salida timestamptz; v_dur_min int;
  v_tipo uuid; v_estado uuid; v_importe numeric; v_folio text; v_cajero uuid;
  v_prob_pagada numeric;
BEGIN
  SELECT tipo_sesion_id INTO v_tipo_normal FROM cat_tipo_sesion WHERE codigo='normal';
  SELECT tipo_sesion_id INTO v_tipo_pref   FROM cat_tipo_sesion WHERE codigo='preferencial';
  SELECT tipo_sesion_id INTO v_tipo_emp    FROM cat_tipo_sesion WHERE codigo='empleado';
  SELECT tipo_sesion_id INTO v_tipo_pen    FROM cat_tipo_sesion WHERE codigo='pensionado';
  SELECT tipo_sesion_id INTO v_tipo_perd   FROM cat_tipo_sesion WHERE codigo='perdido';
  SELECT estado_sesion_id INTO v_est_abierta   FROM cat_estado_sesion WHERE codigo='abierta';
  SELECT estado_sesion_id INTO v_est_pagada    FROM cat_estado_sesion WHERE codigo='pagada';
  SELECT estado_sesion_id INTO v_est_cancelada FROM cat_estado_sesion WHERE codigo='cancelada';
  SELECT perfil_id INTO v_cajero1 FROM perfiles_usuario WHERE email='cajero1@onlypark.local';
  SELECT perfil_id INTO v_cajero2 FROM perfiles_usuario WHERE email='cajero2@onlypark.local';

  FOR est IN
    SELECT ee.estacionamiento_id, ee.codigo, e.codigo AS emp
    FROM estacionamientos ee
    JOIN sucursales s ON s.sucursal_id=ee.sucursal_id
    JOIN empresas e ON e.empresa_id=s.empresa_id
  LOOP
    -- Cada plaza: 80 sesiones si es IWOL, 40 en otras
    FOR i IN 1..CASE WHEN est.emp='IWOL' THEN 80 ELSE 40 END LOOP
      -- Elegir tipo con probabilidades
      IF random() < 0.70 THEN v_tipo := v_tipo_normal;
      ELSIF random() < 0.85 THEN v_tipo := v_tipo_pref;
      ELSIF random() < 0.93 THEN v_tipo := v_tipo_emp;
      ELSIF random() < 0.98 THEN v_tipo := v_tipo_pen;
      ELSE v_tipo := v_tipo_perd; END IF;

      -- Fecha entrada: últimos 30 días, entre 7am y 22h
      v_entrada := (CURRENT_DATE - (random()*29)::int)::timestamptz
                 + (7 + (random()*15))*interval '1 hour'
                 + (random()*59)*interval '1 minute';

      -- Duración: normal 30min-6h, preferencial 1h-8h, empleado 4-9h, pension todo el día
      v_dur_min := CASE
        WHEN v_tipo = v_tipo_normal THEN 30 + (random()*330)::int
        WHEN v_tipo = v_tipo_pref   THEN 60 + (random()*420)::int
        WHEN v_tipo = v_tipo_emp    THEN 240 + (random()*300)::int
        WHEN v_tipo = v_tipo_pen    THEN 360 + (random()*480)::int
        ELSE 120 + (random()*720)::int
      END;
      v_salida := v_entrada + (v_dur_min || ' minutes')::interval;

      -- Estado: 90% pagada (si el ticket ya cerró), 8% abierta (aún no sale), 2% cancelada
      IF v_salida > NOW() THEN
        v_estado := v_est_abierta;
        v_salida := NULL;
        v_importe := NULL;
      ELSIF random() < 0.02 THEN
        v_estado := v_est_cancelada;
        v_importe := 0;
      ELSE
        v_estado := v_est_pagada;
        -- Importe: cortesía si <15min, resto = 15 * ceil(min/60), pref = *0.6, empleado=0, pension=0
        IF v_dur_min <= 15 THEN v_importe := 0;
        ELSIF v_tipo = v_tipo_emp OR v_tipo = v_tipo_pen THEN v_importe := 0;
        ELSIF v_tipo = v_tipo_pref THEN v_importe := 6 * ceil(v_dur_min::numeric/60);
        ELSIF v_tipo = v_tipo_perd THEN v_importe := 150;
        ELSE v_importe := 15 * ceil(v_dur_min::numeric/60);
        END IF;
        IF v_importe < 15 AND v_dur_min > 15 THEN v_importe := 15; END IF;
      END IF;

      v_cajero := CASE WHEN random() < 0.5 THEN v_cajero1 ELSE v_cajero2 END;

      v_folio := upper(est.codigo) || '-' ||
                 to_char(v_entrada,'YYMMDD') || '-' ||
                 lpad(i::text, 4, '0');

      INSERT INTO sesiones (
        estacionamiento_id, tipo_sesion_id, estado_sesion_id,
        folio_entrada, entrada_at, salida_at,
        cajero_entrada_id, cajero_salida_id,
        importe_calculado, importe_total, requiere_cobro
      ) VALUES (
        est.estacionamiento_id, v_tipo, v_estado,
        v_folio, v_entrada, v_salida,
        v_cajero, CASE WHEN v_salida IS NOT NULL THEN v_cajero END,
        v_importe, v_importe, (v_importe IS NOT NULL AND v_importe > 0)
      );
    END LOOP;
  END LOOP;
END $$;

-- Impresiones de campaña sobre sesiones reales (max 3 por sesión, random)
INSERT INTO impresiones_campana (campana_id, sesion_id, cajero_id, momento)
SELECT
  (SELECT campana_id FROM campanas_base ORDER BY random() LIMIT 1),
  s.sesion_id, s.cajero_entrada_id,
  s.entrada_at + (random()*5 || ' minutes')::interval
FROM sesiones s
WHERE random() < 0.4
LIMIT 400;

-- ─────────────────────────────────────────────────────────────────────────────
-- 8) Pagos generados para sesiones pagadas con importe > 0
-- ─────────────────────────────────────────────────────────────────────────────
INSERT INTO pagos (sesion_id, estacionamiento_id, metodo_pago_id, estado_pago_id,
                    cobrado_por, monto, moneda_id, cobrado_at)
SELECT s.sesion_id, s.estacionamiento_id,
       (SELECT metodo_pago_id FROM cat_metodo_pago
         WHERE codigo IN ('efectivo','tarjeta','qr')
         ORDER BY CASE WHEN random() < 0.6 THEN 0 ELSE 1 END LIMIT 1),
       (SELECT estado_pago_id FROM cat_estado_pago WHERE codigo IN ('conciliado','capturado','autorizado') LIMIT 1),
       s.cajero_salida_id, s.importe_total,
       (SELECT moneda_id FROM cat_moneda LIMIT 1),
       s.salida_at
FROM sesiones s
WHERE s.estado_sesion_id = (SELECT estado_sesion_id FROM cat_estado_sesion WHERE codigo='pagada')
  AND s.importe_total > 0;

-- ─────────────────────────────────────────────────────────────────────────────
-- 9) Bitácora: eventos de operación variados (últimos 7 días)
-- ─────────────────────────────────────────────────────────────────────────────
INSERT INTO log_evento (tipo_bitacora_id, subtipo, estacionamiento_id, perfil_id,
                         sesion_id, descripcion, payload, ip, ocurrido_at)
SELECT
  (SELECT tipo_bitacora_id FROM cat_tipo_bitacora WHERE codigo='operativa'),
  CASE (random()*4)::int
    WHEN 0 THEN 'entrada'
    WHEN 1 THEN 'cobro'
    WHEN 2 THEN 'cortesia'
    ELSE 'impresion'
  END,
  s.estacionamiento_id, s.cajero_entrada_id, s.sesion_id,
  'Evento demo · folio ' || s.folio_entrada,
  jsonb_build_object('folio', s.folio_entrada, 'importe', s.importe_total, 'actor','demo'),
  ('192.168.0.' || (10 + (random()*245)::int)::text)::inet,
  s.entrada_at + (random()*10 || ' minutes')::interval
FROM sesiones s
WHERE s.entrada_at > NOW() - INTERVAL '7 days'
ORDER BY random()
LIMIT 200;

-- Login events (mezcla de cajeros por día)
INSERT INTO log_evento (tipo_bitacora_id, subtipo, estacionamiento_id, perfil_id,
                         descripcion, payload, ocurrido_at)
SELECT
  (SELECT tipo_bitacora_id FROM cat_tipo_bitacora WHERE codigo='seguridad'),
  'login',
  est.estacionamiento_id, p.perfil_id,
  'Login del cajero ' || p.email,
  jsonb_build_object('app','cajero','actor', p.nombre_completo),
  (CURRENT_DATE - g)::timestamptz + '07:00'::time
FROM estacionamientos est
CROSS JOIN generate_series(0, 7) g
JOIN perfiles_usuario p ON p.email IN ('cajero1@onlypark.local','cajero2@onlypark.local','supervisor@onlypark.local')
ON CONFLICT DO NOTHING;

NOTIFY pgrst, 'reload schema';

-- ─────────────────────────────────────────────────────────────────────────────
-- Verificación final
-- ─────────────────────────────────────────────────────────────────────────────
SELECT
  (SELECT COUNT(*) FROM sesiones) AS sesiones,
  (SELECT COUNT(*) FROM sesiones WHERE estado_sesion_id=(SELECT estado_sesion_id FROM cat_estado_sesion WHERE codigo='pagada')) AS pagadas,
  (SELECT COUNT(*) FROM sesiones WHERE estado_sesion_id=(SELECT estado_sesion_id FROM cat_estado_sesion WHERE codigo='abierta')) AS abiertas,
  (SELECT COUNT(*) FROM pagos) AS pagos,
  (SELECT COUNT(*) FROM cortes_caja) AS cortes,
  (SELECT COUNT(*) FROM pensiones_base) AS pensiones,
  (SELECT COUNT(*) FROM campanas_base) AS campanas,
  (SELECT COUNT(*) FROM impresiones_campana) AS impresiones,
  (SELECT COUNT(*) FROM camaras) AS camaras,
  (SELECT COUNT(*) FROM clientes) AS clientes,
  (SELECT COUNT(*) FROM vehiculos) AS vehiculos,
  (SELECT COUNT(*) FROM log_evento) AS eventos,
  (SELECT SUM(importe_total)::int FROM sesiones WHERE estado_sesion_id=(SELECT estado_sesion_id FROM cat_estado_sesion WHERE codigo='pagada')) AS ingresos_totales;
