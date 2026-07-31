-- ============================================================================
-- 025 — fn_calcular_importe_sesion: implementación v1
--
-- Reemplaza el stub. Semántica v1 (extensible):
--   1) Elegir política vigente para (estacionamiento, tipo_sesion, fecha_entrada).
--      Fallback: si no hay política específica por tipo_sesion, usar la que tiene
--      tipo_sesion_id NULL (política default del estacionamiento).
--   2) Calcular duración en minutos entre entrada_at y COALESCE(salida_at, NOW()).
--   3) Recorrer reglas activas de esa política en orden de prioridad ascendente
--      y aplicar la primera que sea "resolutiva" (tolerancia | hora | fraccion | dia).
--      Luego aplicar 'minima' y 'maxima' como pisos/topes.
--   4) Escribir importe_calculado / politica_tarifaria_id en la sesión.
--   5) Retornar el importe final.
--
-- Fuera de alcance de v1 (queda para próximas iteraciones):
--   - Reglas por franja horaria (hora_inicio/hora_fin) o días específicos.
--   - Tarifa nocturna diferenciada, convenios, promociones, descuentos.
--   - Cálculos multi-día con cortes por medianoche.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.fn_calcular_importe_sesion(p_sesion_id uuid)
RETURNS numeric LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
  v_ses               RECORD;
  v_politica_id       uuid;
  v_duracion_min      integer;
  v_horas             numeric;
  v_importe           numeric := 0;
  v_min               numeric;
  v_max               numeric;
  v_resolvio          boolean := false;
  v_fue_tolerancia    boolean := false;
  r                   RECORD;
BEGIN
  -- 1) Cargar sesión
  SELECT s.sesion_id, s.estacionamiento_id, s.tipo_sesion_id,
         s.entrada_at, s.salida_at
    INTO v_ses
    FROM sesiones s
   WHERE s.sesion_id = p_sesion_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'sesión % no existe', p_sesion_id;
  END IF;

  -- 2) Duración en minutos (ceil)
  v_duracion_min := CEIL(EXTRACT(EPOCH FROM (
    COALESCE(v_ses.salida_at, NOW()) - v_ses.entrada_at)) / 60.0)::integer;
  IF v_duracion_min < 0 THEN v_duracion_min := 0; END IF;

  -- 3) Resolver política vigente: específica por tipo_sesion o default (NULL)
  SELECT pt.politica_id INTO v_politica_id
    FROM politicas_tarifarias pt
   WHERE pt.estacionamiento_id = v_ses.estacionamiento_id
     AND pt.activo
     AND pt.vigente_desde <= v_ses.entrada_at::date
     AND (pt.vigente_hasta IS NULL OR pt.vigente_hasta >= v_ses.entrada_at::date)
     AND (pt.tipo_sesion_id = v_ses.tipo_sesion_id OR pt.tipo_sesion_id IS NULL)
   ORDER BY (pt.tipo_sesion_id = v_ses.tipo_sesion_id) DESC NULLS LAST,
            pt.vigente_desde DESC
   LIMIT 1;

  IF v_politica_id IS NULL THEN
    UPDATE sesiones SET importe_calculado = 0, updated_at = NOW() WHERE sesion_id = p_sesion_id;
    RETURN 0;
  END IF;

  -- 4) Recorrer reglas por prioridad
  FOR r IN
    SELECT rt.regla_id, tt.codigo AS tipo, rt.monto, rt.fraccion_min,
           rt.tolerancia_min, rt.prioridad
      FROM reglas_tarifarias rt
      JOIN cat_tipo_tarifa   tt ON tt.tipo_tarifa_id = rt.tipo_tarifa_id
     WHERE rt.politica_id = v_politica_id AND rt.activa
     ORDER BY rt.prioridad ASC
  LOOP
    -- Reglas resolutivas: sólo se aplica la primera que dispare
    IF NOT v_resolvio THEN
      IF r.tipo = 'tolerancia' AND v_duracion_min <= COALESCE(r.tolerancia_min, 0) THEN
        v_importe := COALESCE(r.monto, 0);
        v_resolvio := true;
        v_fue_tolerancia := true;
      ELSIF r.tipo = 'hora' THEN
        -- por hora completa (fraccion_min típicamente 60)
        v_horas := CEIL(v_duracion_min::numeric / GREATEST(COALESCE(r.fraccion_min,60),1));
        v_importe := v_horas * COALESCE(r.monto, 0);
        v_resolvio := true;
      ELSIF r.tipo = 'fraccion' THEN
        v_horas := CEIL(v_duracion_min::numeric / GREATEST(COALESCE(r.fraccion_min,15),1));
        v_importe := v_horas * COALESCE(r.monto, 0);
        v_resolvio := true;
      ELSIF r.tipo = 'dia' THEN
        v_horas := CEIL(v_duracion_min::numeric / (24*60));
        v_importe := v_horas * COALESCE(r.monto, 0);
        v_resolvio := true;
      END IF;
    END IF;

    -- Pisos y topes (siempre se evalúan después)
    IF r.tipo = 'minima' THEN v_min := COALESCE(r.monto, 0); END IF;
    IF r.tipo = 'maxima' THEN v_max := COALESCE(r.monto, 0); END IF;
  END LOOP;

  -- Mínima NO aplica si la tolerancia disparó gratuidad
  IF v_min IS NOT NULL AND v_importe < v_min AND v_duracion_min > 0 AND NOT v_fue_tolerancia THEN
    v_importe := v_min;
  END IF;
  IF v_max IS NOT NULL AND v_importe > v_max THEN
    v_importe := v_max;
  END IF;

  -- 5) Persistir
  UPDATE sesiones
     SET importe_calculado    = ROUND(v_importe, 4),
         politica_tarifaria_id = v_politica_id,
         updated_at           = NOW()
   WHERE sesion_id = p_sesion_id;

  RETURN ROUND(v_importe, 4);
END $$;

GRANT EXECUTE ON FUNCTION public.fn_calcular_importe_sesion(uuid) TO authenticated, service_role;
