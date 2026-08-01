-- ============================================================================
-- 035 — Políticas tarifarias variadas + cfg_estacionamiento para todos
--
-- Cada estacionamiento tiene su propia política, independiente de las demás.
-- Reglas soportadas (cat_tipo_tarifa): tolerancia, hora, fraccion (cuartos),
--                                        minima, maxima, perdido, dia (libre)
--
-- Perfiles asignados según ubicación/nivel del centro comercial:
--   Vips/cafés (bajo tránsito):     $20/h   fraccion 15min = $6
--   Herradura/plazas medianas:      $25/h   fraccion 15min = $7
--   Palacio CDMX (premium):         $50/h   fraccion 15min = $15
--   Palacio MTY:                    $40/h   fraccion 15min = $12
--   Hospital ABC:                   $30/h   fraccion 15min = $8    tarifa_libre_dia 8h=$150 hora_extra=$30
--   Carso plazas satelite:          $18/h   fraccion 15min = $6    tarifa_libre_dia 8h=$120
--   IWOL (queda igual):             $15/h   sin fraccion
-- ============================================================================

DO $$
DECLARE
  est RECORD;
  v_politica uuid;
  v_tipo_tol uuid; v_tipo_hora uuid; v_tipo_frac uuid; v_tipo_min uuid;
  v_tipo_max uuid; v_tipo_perd uuid; v_tipo_dia uuid;

  -- Tarifa por perfil (grupo/empresa)
  v_tarifa_hora numeric; v_tarifa_frac numeric; v_tarifa_min numeric;
  v_tarifa_perd numeric; v_tarifa_dia numeric; v_horas_libres int; v_tarifa_extra numeric;
  v_usar_fraccion boolean;
  v_grupo_cod text; v_empresa_cod text;
BEGIN
  SELECT tipo_tarifa_id INTO v_tipo_tol  FROM cat_tipo_tarifa WHERE codigo='tolerancia';
  SELECT tipo_tarifa_id INTO v_tipo_hora FROM cat_tipo_tarifa WHERE codigo='hora';
  SELECT tipo_tarifa_id INTO v_tipo_frac FROM cat_tipo_tarifa WHERE codigo='fraccion';
  SELECT tipo_tarifa_id INTO v_tipo_min  FROM cat_tipo_tarifa WHERE codigo='minima';
  SELECT tipo_tarifa_id INTO v_tipo_max  FROM cat_tipo_tarifa WHERE codigo='maxima';
  SELECT tipo_tarifa_id INTO v_tipo_perd FROM cat_tipo_tarifa WHERE codigo IN ('perdido','maxima') LIMIT 1;
  SELECT tipo_tarifa_id INTO v_tipo_dia  FROM cat_tipo_tarifa WHERE codigo='dia';

  FOR est IN
    SELECT ee.estacionamiento_id, ee.codigo AS est_cod, ee.nombre AS est_nom,
           e.codigo AS emp_cod, g.codigo AS grp_cod, g.nombre AS grupo
    FROM estacionamientos ee
    JOIN sucursales s ON s.sucursal_id=ee.sucursal_id
    JOIN empresas e ON e.empresa_id=s.empresa_id
    JOIN grupos_empresariales g ON g.grupo_id=e.grupo_id
  LOOP
    -- Perfil según grupo/empresa
    IF est.grp_cod = 'GRP_VIPS' THEN
      v_tarifa_hora := 20; v_tarifa_frac := 6;  v_tarifa_min := 20; v_tarifa_perd := 200;
      v_tarifa_dia := NULL; v_horas_libres := 0; v_tarifa_extra := NULL;
      v_usar_fraccion := true;
    ELSIF est.grp_cod = 'GRP_HERRADURA' THEN
      v_tarifa_hora := 25; v_tarifa_frac := 7;  v_tarifa_min := 25; v_tarifa_perd := 300;
      v_tarifa_dia := NULL; v_horas_libres := 0; v_tarifa_extra := NULL;
      v_usar_fraccion := true;
    ELSIF est.grp_cod = 'GRP_PALACIO' AND est.emp_cod = 'PALACIO_CDMX' THEN
      v_tarifa_hora := 50; v_tarifa_frac := 15; v_tarifa_min := 50; v_tarifa_perd := 500;
      v_tarifa_dia := 400; v_horas_libres := 8; v_tarifa_extra := 60;
      v_usar_fraccion := true;
    ELSIF est.grp_cod = 'GRP_PALACIO' AND est.emp_cod = 'PALACIO_MTY' THEN
      v_tarifa_hora := 40; v_tarifa_frac := 12; v_tarifa_min := 40; v_tarifa_perd := 400;
      v_tarifa_dia := 320; v_horas_libres := 8; v_tarifa_extra := 50;
      v_usar_fraccion := true;
    ELSIF est.grp_cod IN ('GRP_HOSPITALARIO_ABC') OR est.grupo ILIKE '%Hospitalario%' THEN
      v_tarifa_hora := 30; v_tarifa_frac := 8;  v_tarifa_min := 30; v_tarifa_perd := 350;
      v_tarifa_dia := 150; v_horas_libres := 8; v_tarifa_extra := 30;
      v_usar_fraccion := true;
    ELSIF est.grupo ILIKE '%Carso%' THEN
      v_tarifa_hora := 18; v_tarifa_frac := 6;  v_tarifa_min := 18; v_tarifa_perd := 250;
      v_tarifa_dia := 120; v_horas_libres := 8; v_tarifa_extra := 25;
      v_usar_fraccion := true;
    ELSE  -- IWOL y default
      v_tarifa_hora := 15; v_tarifa_frac := 5;  v_tarifa_min := 15; v_tarifa_perd := 150;
      v_tarifa_dia := NULL; v_horas_libres := 0; v_tarifa_extra := NULL;
      v_usar_fraccion := false;
    END IF;

    -- cfg_estacionamiento (crear si no existe)
    INSERT INTO cfg_estacionamiento (
      estacionamiento_id, tolerancia_min, minutos_tolerancia_salida,
      lpr_habilitado, promociones_habilitado, onlywallet_habilitado,
      pagos_qr_habilitado, pagos_link_habilitado, offline_habilitado,
      bitacora_click_habilitada, usa_pin_operativo,
      formato_folio_entrada, formato_folio_salida,
      hora_apertura, hora_cierre
    ) VALUES (
      est.estacionamiento_id, 15, 15,
      random() < 0.4, true, true,
      random() < 0.5, true, true,
      true, false,
      upper(substr(est.est_cod,1,3)) || '-YYMMDDNNN', 'SAL-YYMMDDNNN',
      '06:00'::time, '23:00'::time
    )
    ON CONFLICT (estacionamiento_id) DO UPDATE SET
      tolerancia_min = COALESCE(cfg_estacionamiento.tolerancia_min, 15),
      minutos_tolerancia_salida = COALESCE(cfg_estacionamiento.minutos_tolerancia_salida, 15),
      lpr_habilitado = COALESCE(cfg_estacionamiento.lpr_habilitado, random() < 0.4),
      promociones_habilitado = true,
      onlywallet_habilitado = true,
      pagos_qr_habilitado = true,
      pagos_link_habilitado = true,
      updated_at = NOW();

    -- Política tarifaria: eliminar la vieja si existe, crear nueva
    DELETE FROM reglas_tarifarias WHERE politica_id IN
      (SELECT politica_id FROM politicas_tarifarias WHERE estacionamiento_id=est.estacionamiento_id);
    DELETE FROM politicas_tarifarias WHERE estacionamiento_id=est.estacionamiento_id;

    INSERT INTO politicas_tarifarias (
      estacionamiento_id, nombre, vigente_desde, activo
    ) VALUES (
      est.estacionamiento_id,
      'Política ' || est.grupo || ' · ' || est.est_nom,
      CURRENT_DATE - 30, true
    ) RETURNING politica_id INTO v_politica;

    -- Reglas: tolerancia gratis + hora/fracción + mínima + perdido + libre (si aplica)
    INSERT INTO reglas_tarifarias (politica_id, tipo_tarifa_id, monto, tolerancia_min, prioridad, activa)
    VALUES (v_politica, v_tipo_tol, 0, 15, 10, true);

    IF v_usar_fraccion THEN
      -- Redondeo a 15 minutos (cuartos de hora)
      INSERT INTO reglas_tarifarias (politica_id, tipo_tarifa_id, monto, fraccion_min, prioridad, activa)
      VALUES (v_politica, v_tipo_frac, v_tarifa_frac, 15, 20, true);
    ELSE
      -- Redondeo a hora completa
      INSERT INTO reglas_tarifarias (politica_id, tipo_tarifa_id, monto, fraccion_min, prioridad, activa)
      VALUES (v_politica, v_tipo_hora, v_tarifa_hora, 60, 20, true);
    END IF;

    INSERT INTO reglas_tarifarias (politica_id, tipo_tarifa_id, monto, prioridad, activa)
    VALUES (v_politica, v_tipo_min, v_tarifa_min, 30, true);

    IF v_tipo_perd IS NOT NULL THEN
      INSERT INTO reglas_tarifarias (politica_id, tipo_tarifa_id, monto, prioridad, activa)
      VALUES (v_politica, v_tipo_perd, v_tarifa_perd, 40, true);
    END IF;

    -- Tarifa libre por día (8h) para hospitales y plazas premium
    IF v_tarifa_dia IS NOT NULL AND v_tipo_dia IS NOT NULL THEN
      INSERT INTO reglas_tarifarias (
        politica_id, tipo_tarifa_id, monto, fraccion_min, prioridad, activa, parametros
      ) VALUES (
        v_politica, v_tipo_dia, v_tarifa_dia, v_horas_libres * 60, 15, true,
        jsonb_build_object(
          'horas_libres', v_horas_libres,
          'costo_hora_extra', v_tarifa_extra,
          'descripcion', 'Tarifa libre ' || v_horas_libres || 'h por $' || v_tarifa_dia ||
                         '. Hora extra: $' || v_tarifa_extra
        )
      );
    END IF;
  END LOOP;
END $$;

-- Matriz final legible
SELECT
  g.nombre                             AS grupo,
  substr(est.nombre,1,25)              AS estacionamiento,
  est.capacidad_total                  AS cajones,
  MAX(CASE WHEN tt.codigo='hora'      THEN rt.monto END)::int AS hora,
  MAX(CASE WHEN tt.codigo='fraccion'  THEN rt.monto END)::int AS "15min",
  MAX(CASE WHEN tt.codigo='minima'    THEN rt.monto END)::int AS minima,
  MAX(CASE WHEN tt.codigo='dia'       THEN rt.monto END)::int AS libre_dia,
  MAX(CASE WHEN tt.codigo='dia'       THEN (rt.parametros->>'horas_libres')::int END) AS libre_h,
  MAX(CASE WHEN tt.codigo='dia'       THEN (rt.parametros->>'costo_hora_extra')::int END) AS extra,
  MAX(CASE WHEN tt.codigo IN ('perdido','maxima') THEN rt.monto END)::int AS perdido
FROM estacionamientos est
JOIN sucursales s ON s.sucursal_id=est.sucursal_id
JOIN empresas e ON e.empresa_id=s.empresa_id
JOIN grupos_empresariales g ON g.grupo_id=e.grupo_id
LEFT JOIN politicas_tarifarias pt ON pt.estacionamiento_id=est.estacionamiento_id AND pt.activo
LEFT JOIN reglas_tarifarias rt ON rt.politica_id=pt.politica_id AND rt.activa
LEFT JOIN cat_tipo_tarifa tt ON tt.tipo_tarifa_id=rt.tipo_tarifa_id
GROUP BY g.nombre, est.nombre, est.capacidad_total
ORDER BY g.nombre, est.nombre;
