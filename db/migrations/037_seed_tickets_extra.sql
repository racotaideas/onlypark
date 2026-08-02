-- ============================================================================
-- 037 — Más tickets para consulta:
--   • Nivelar Carso/ABC/IWOL a ~400 tickets/estac (últimos 30 días)
--   • Sembrar actividad del DÍA ACTUAL para que "en vivo" tenga datos
--   • Placas vinculadas a los tickets (para que la búsqueda por placa opere)
--   • Cortes de caja del día en curso
-- ============================================================================

DO $$
DECLARE
  v_tn uuid; v_tp uuid; v_te uuid; v_tpen uuid; v_tperd uuid; v_tvip uuid;
  v_ea uuid; v_epag uuid; v_ecan uuid;
  v_cajero1 uuid; v_cajero2 uuid;
  est RECORD; i int; n_faltantes int;
  v_entrada timestamptz; v_salida timestamptz; v_dur_min int;
  v_tipo uuid; v_estado uuid; v_importe numeric; v_folio text; v_cajero uuid;
  v_placa RECORD;
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

  -- ─── PARTE 1: Nivelar estac con pocos tickets (Carso/ABC/IWOL) ────────────
  FOR est IN
    SELECT ee.estacionamiento_id, ee.codigo,
           (SELECT COUNT(*) FROM sesiones WHERE estacionamiento_id=ee.estacionamiento_id) AS actuales
    FROM estacionamientos ee
  LOOP
    n_faltantes := GREATEST(0, 400 - est.actuales);
    IF n_faltantes = 0 THEN CONTINUE; END IF;

    FOR i IN 1..n_faltantes LOOP
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
        IF v_importe < 15 AND v_dur_min > 15 AND v_tipo NOT IN (v_te, v_tpen, COALESCE(v_tvip,v_te)) THEN v_importe := 15; END IF;
      END IF;

      v_cajero := CASE WHEN random() < 0.55 THEN v_cajero1 ELSE v_cajero2 END;
      v_folio  := upper(est.codigo) || 'N-' || to_char(v_entrada,'YYMMDD') || '-' || lpad(i::text,4,'0');

      INSERT INTO sesiones (
        estacionamiento_id, tipo_sesion_id, estado_sesion_id,
        folio_entrada, entrada_at, salida_at, cajero_entrada_id, cajero_salida_id,
        importe_calculado, importe_total, requiere_cobro
      ) VALUES (
        est.estacionamiento_id, v_tipo, v_estado,
        v_folio, v_entrada, v_salida, v_cajero,
        CASE WHEN v_salida IS NOT NULL THEN v_cajero END,
        v_importe, v_importe, (v_importe IS NOT NULL AND v_importe > 0)
      );
    END LOOP;
  END LOOP;

  -- ─── PARTE 2: Actividad del DÍA ACTUAL (última 12h) por estac ─────────────
  -- Meta: cada estac tiene 20-40 tickets nuevos hoy, mix de abiertos y ya salidos.
  FOR est IN SELECT estacionamiento_id, codigo, capacidad_total FROM estacionamientos LOOP
    FOR i IN 1..(20 + (random()*20)::int) LOOP
      IF random() < 0.75 THEN v_tipo := v_tn;
      ELSIF random() < 0.90 THEN v_tipo := v_tp;
      ELSIF random() < 0.96 THEN v_tipo := v_te;
      ELSE v_tipo := v_tpen; END IF;

      -- Entrada en las últimas 12h (hoy)
      v_entrada := NOW() - (random()*12*3600 || ' seconds')::interval;
      v_dur_min := 15 + (random()*300)::int;
      v_salida := v_entrada + (v_dur_min || ' minutes')::interval;

      -- 40% siguen dentro (abiertas), 60% ya salieron
      IF v_salida > NOW() OR random() < 0.40 THEN
        v_estado := v_ea; v_salida := NULL; v_importe := NULL;
      ELSE
        v_estado := v_epag;
        v_importe := CASE
          WHEN v_dur_min <= 15 THEN 0
          WHEN v_tipo IN (v_te, v_tpen) THEN 0
          WHEN v_tipo = v_tp THEN 6 * ceil(v_dur_min::numeric/60)
          ELSE 15 * ceil(v_dur_min::numeric/60)
        END;
        IF v_importe < 15 AND v_dur_min > 15 AND v_tipo NOT IN (v_te, v_tpen) THEN v_importe := 15; END IF;
      END IF;

      v_cajero := CASE WHEN random() < 0.55 THEN v_cajero1 ELSE v_cajero2 END;
      v_folio := upper(est.codigo) || 'H-' || to_char(v_entrada,'HH24MISS') || '-' || lpad(i::text,3,'0');

      INSERT INTO sesiones (
        estacionamiento_id, tipo_sesion_id, estado_sesion_id,
        folio_entrada, entrada_at, salida_at, cajero_entrada_id, cajero_salida_id,
        importe_calculado, importe_total, requiere_cobro
      ) VALUES (
        est.estacionamiento_id, v_tipo, v_estado,
        v_folio, v_entrada, v_salida, v_cajero,
        CASE WHEN v_salida IS NOT NULL THEN v_cajero END,
        v_importe, v_importe, (v_importe IS NOT NULL AND v_importe > 0)
      );
    END LOOP;
  END LOOP;

  -- ─── PARTE 3: Ligar placas a un subset de tickets recientes ───────────────
  -- Para que la búsqueda por placa devuelva algo.
  UPDATE sesiones s SET placa_id = (
    SELECT p.placa_id FROM placas p WHERE p.activa
    ORDER BY random() LIMIT 1
  )
  WHERE s.placa_id IS NULL
    AND s.entrada_at > NOW() - INTERVAL '7 days'
    AND random() < 0.6;
END $$;

-- Pagos para todos los tickets pagados que aún no los tengan
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
WHERE s.estado_sesion_id=(SELECT estado_sesion_id FROM cat_estado_sesion WHERE codigo='pagada')
  AND s.importe_total > 0
  AND NOT EXISTS (SELECT 1 FROM pagos p WHERE p.sesion_id = s.sesion_id);

-- Cortes de caja del día en curso (para el "Rendimiento por cajero" del admin)
INSERT INTO cortes_caja (estacionamiento_id, cajero_id, turno_id, tipo,
                          inicio_at, fondo_inicial, total_cobrado, estado, notas)
SELECT est.estacionamiento_id,
       (SELECT perfil_id FROM perfiles_usuario WHERE email='cajero1@onlypark.local'),
       (SELECT turno_id FROM cat_turno LIMIT 1),
       'apertura',
       CURRENT_DATE::timestamptz + '07:00'::time,
       500,
       (SELECT COALESCE(SUM(s.importe_total),0) FROM sesiones s
         WHERE s.estacionamiento_id=est.estacionamiento_id
           AND s.entrada_at::date=CURRENT_DATE
           AND s.estado_sesion_id=(SELECT estado_sesion_id FROM cat_estado_sesion WHERE codigo='pagada'))::int,
       'activo',
       'Turno del día en curso'
FROM estacionamientos est
WHERE NOT EXISTS (
  SELECT 1 FROM cortes_caja c
  WHERE c.estacionamiento_id=est.estacionamiento_id
    AND c.inicio_at::date=CURRENT_DATE AND c.estado='activo'
);

-- Refrescar DWH
SELECT dwh.fn_etl_run_all() AS resultado;

-- Verificación
SELECT
  (SELECT COUNT(*) FROM sesiones) AS total_tickets,
  (SELECT COUNT(*) FROM sesiones WHERE entrada_at::date=CURRENT_DATE) AS tickets_hoy,
  (SELECT COUNT(*) FROM sesiones WHERE salida_at IS NULL) AS abiertos_ahora,
  (SELECT COUNT(*) FROM sesiones WHERE placa_id IS NOT NULL) AS con_placa,
  (SELECT COUNT(*) FROM pagos) AS total_pagos,
  (SELECT SUM(importe_total)::int FROM sesiones WHERE estado_sesion_id=(SELECT estado_sesion_id FROM cat_estado_sesion WHERE codigo='pagada')) AS ingresos_totales,
  (SELECT SUM(importe_total)::int FROM sesiones WHERE entrada_at::date=CURRENT_DATE AND estado_sesion_id=(SELECT estado_sesion_id FROM cat_estado_sesion WHERE codigo='pagada')) AS ingresos_hoy;
