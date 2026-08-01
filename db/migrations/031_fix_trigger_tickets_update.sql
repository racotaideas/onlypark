-- ============================================================================
-- 031 — Fix trg_tickets_instead_update: no tocar duracion_minutos (generada)
--       y validar turno_id como UUID antes de usar.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.trg_tickets_instead_update()
RETURNS trigger LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE v_estado_id uuid; v_cajero_sal uuid; v_corte uuid;
BEGIN
  IF NEW.estatus IS DISTINCT FROM OLD.estatus AND NEW.estatus IS NOT NULL THEN
    v_estado_id := public.fn_estado_sesion_por_iwol(NEW.estatus);
  END IF;
  IF NEW.cajero_salida IS DISTINCT FROM OLD.cajero_salida AND NEW.cajero_salida IS NOT NULL THEN
    v_cajero_sal := public.fn_perfil_por_texto(NEW.cajero_salida);
  END IF;
  -- turno_id: solo tomarlo si es UUID valido (IWOL a veces manda 'T1785...' local)
  IF NEW.turno_id IS NOT NULL AND NEW.turno_id::text ~ '^[0-9a-f-]{36}$' THEN
    v_corte := NEW.turno_id;
  END IF;

  -- NOTA: duracion_minutos es columna GENERATED, no se puede asignar aqui.
  --       Se calcula automaticamente por Postgres desde salida_at - entrada_at.
  UPDATE public.sesiones SET
    folio_salida         = COALESCE(NEW.folio_salida,       folio_salida),
    salida_at            = COALESCE(NEW.hora_salida_at,     salida_at),
    importe_total        = COALESCE(NEW.importe,            importe_total),
    importe_calculado    = COALESCE(NEW.importe_calculado,  importe_calculado),
    importe_descuento    = COALESCE(NEW.importe_descuento,  importe_descuento),
    estado_sesion_id     = COALESCE(v_estado_id,            estado_sesion_id),
    cajero_salida_id     = COALESCE(v_cajero_sal,           cajero_salida_id),
    corte_caja_salida_id = COALESCE(v_corte,                corte_caja_salida_id),
    updated_at           = NOW()
  WHERE folio_entrada = OLD.folio;
  RETURN NEW;
END $$;

NOTIFY pgrst, 'reload schema';
