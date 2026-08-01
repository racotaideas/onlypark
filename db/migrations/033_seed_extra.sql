-- ============================================================================
-- 033 — Seed extra: 500 sesiones más para tener volumen decente (~800 total)
-- Se agrega a lo que ya existe, sin truncar.
-- ============================================================================
DO $$
DECLARE
  v_tipo_normal uuid; v_tipo_pref uuid; v_tipo_emp uuid; v_tipo_pen uuid; v_tipo_perd uuid; v_tipo_vip uuid;
  v_est_abierta uuid; v_est_pagada uuid; v_est_cancelada uuid;
  v_cajero uuid;
  est RECORD; i integer;
  v_entrada timestamptz; v_salida timestamptz; v_dur_min int;
  v_tipo uuid; v_estado uuid; v_importe numeric; v_folio text;
BEGIN
  SELECT tipo_sesion_id INTO v_tipo_normal FROM cat_tipo_sesion WHERE codigo='normal';
  SELECT tipo_sesion_id INTO v_tipo_pref   FROM cat_tipo_sesion WHERE codigo='preferencial';
  SELECT tipo_sesion_id INTO v_tipo_emp    FROM cat_tipo_sesion WHERE codigo='empleado';
  SELECT tipo_sesion_id INTO v_tipo_pen    FROM cat_tipo_sesion WHERE codigo='pensionado';
  SELECT tipo_sesion_id INTO v_tipo_perd   FROM cat_tipo_sesion WHERE codigo='perdido';
  SELECT tipo_sesion_id INTO v_tipo_vip    FROM cat_tipo_sesion WHERE codigo='vip';
  SELECT estado_sesion_id INTO v_est_abierta   FROM cat_estado_sesion WHERE codigo='abierta';
  SELECT estado_sesion_id INTO v_est_pagada    FROM cat_estado_sesion WHERE codigo='pagada';
  SELECT estado_sesion_id INTO v_est_cancelada FROM cat_estado_sesion WHERE codigo='cancelada';
  SELECT perfil_id INTO v_cajero FROM perfiles_usuario WHERE email='cajero1@onlypark.local';

  FOR est IN
    SELECT ee.estacionamiento_id, ee.codigo, e.codigo AS emp
    FROM estacionamientos ee
    JOIN sucursales s ON s.sucursal_id=ee.sucursal_id
    JOIN empresas e ON e.empresa_id=s.empresa_id
  LOOP
    FOR i IN 1..CASE WHEN est.emp='IWOL' THEN 150 ELSE 70 END LOOP
      IF random() < 0.68 THEN v_tipo := v_tipo_normal;
      ELSIF random() < 0.80 THEN v_tipo := v_tipo_pref;
      ELSIF random() < 0.88 THEN v_tipo := v_tipo_emp;
      ELSIF random() < 0.94 THEN v_tipo := v_tipo_pen;
      ELSIF random() < 0.98 THEN v_tipo := COALESCE(v_tipo_vip, v_tipo_normal);
      ELSE v_tipo := v_tipo_perd; END IF;

      -- Fecha entre 60 días atrás y ahora
      v_entrada := (CURRENT_DATE - (random()*59)::int)::timestamptz
                 + (6 + (random()*17))*interval '1 hour'
                 + (random()*59)*interval '1 minute';

      v_dur_min := CASE
        WHEN v_tipo = v_tipo_normal THEN 20 + (random()*400)::int
        WHEN v_tipo = v_tipo_pref   THEN 45 + (random()*480)::int
        WHEN v_tipo = v_tipo_emp    THEN 240 + (random()*300)::int
        WHEN v_tipo = v_tipo_pen    THEN 360 + (random()*480)::int
        ELSE 60 + (random()*720)::int
      END;
      v_salida := v_entrada + (v_dur_min || ' minutes')::interval;

      IF v_salida > NOW() THEN v_estado := v_est_abierta; v_salida := NULL; v_importe := NULL;
      ELSIF random() < 0.03 THEN v_estado := v_est_cancelada; v_importe := 0;
      ELSE
        v_estado := v_est_pagada;
        IF v_dur_min <= 15 THEN v_importe := 0;
        ELSIF v_tipo = v_tipo_emp OR v_tipo = v_tipo_pen THEN v_importe := 0;
        ELSIF v_tipo = v_tipo_pref THEN v_importe := 6 * ceil(v_dur_min::numeric/60);
        ELSIF v_tipo = v_tipo_perd THEN v_importe := 150;
        ELSIF v_tipo = v_tipo_vip  THEN v_importe := 0;
        ELSE v_importe := 15 * ceil(v_dur_min::numeric/60);
        END IF;
        IF v_importe < 15 AND v_dur_min > 15 AND v_tipo NOT IN (v_tipo_emp, v_tipo_pen, COALESCE(v_tipo_vip, v_tipo_emp)) THEN
          v_importe := 15;
        END IF;
      END IF;

      v_folio := upper(est.codigo) || '2-' ||
                 to_char(v_entrada,'YYMMDD') || '-' ||
                 lpad(i::text, 4, '0');

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

-- Pagos para los nuevos tickets pagados
INSERT INTO pagos (sesion_id, estacionamiento_id, metodo_pago_id, estado_pago_id,
                   cobrado_por, monto, moneda_id, cobrado_at)
SELECT s.sesion_id, s.estacionamiento_id,
       (SELECT metodo_pago_id FROM cat_metodo_pago
         WHERE codigo IN ('efectivo','tarjeta_debito','tarjeta_credito','qr','link_pago')
         ORDER BY random() LIMIT 1),
       (SELECT estado_pago_id FROM cat_estado_pago WHERE codigo='conciliado' LIMIT 1),
       s.cajero_salida_id, s.importe_total,
       (SELECT moneda_id FROM cat_moneda LIMIT 1),
       s.salida_at
FROM sesiones s
WHERE s.estado_sesion_id = (SELECT estado_sesion_id FROM cat_estado_sesion WHERE codigo='pagada')
  AND s.importe_total > 0
  AND s.folio_entrada LIKE '%2-%'  -- solo los nuevos
  AND NOT EXISTS (SELECT 1 FROM pagos p WHERE p.sesion_id = s.sesion_id);

-- Refrescar DWH
SELECT dwh.fn_etl_run_all() AS resultado;
