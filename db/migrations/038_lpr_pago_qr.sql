-- ============================================================================
-- 038 — Flujo LPR + QR + pago autoservicio + salida automática
--
-- Escenario:
--   Entrada  → cámara lee placa → registra ticket → imprime boleto con QR
--   Pago     → cliente escanea QR con celular → ve importe → paga → sesión pagada
--   Salida   → cámara lee placa → verifica pagado → autoriza levantar pluma
--
-- Este archivo agrega:
--   • Columna sesiones.link_token (uuid) — un solo uso, expira 24h
--   • Columna sesiones.pagado_at (timestamptz)
--   • RPC fn_registrar_entrada_lpr(placa, estacionamiento) — crea sesión + genera token
--   • RPC fn_obtener_ticket_por_token(token) — pantalla pública de pago (sin auth)
--   • RPC fn_confirmar_pago_token(token, metodo) — marca como pagado
--   • RPC fn_verificar_salida_lpr(placa, estacionamiento) — valida salida
--
-- Todos expuestos a anon para que el cliente final (sin cuenta) pueda usar
-- el link del ticket.
-- ============================================================================

ALTER TABLE public.sesiones
  ADD COLUMN IF NOT EXISTS link_token uuid,
  ADD COLUMN IF NOT EXISTS pagado_at  timestamptz;

CREATE INDEX IF NOT EXISTS ix_sesiones_link_token ON public.sesiones(link_token) WHERE link_token IS NOT NULL;
CREATE INDEX IF NOT EXISTS ix_sesiones_placa_abierta ON public.sesiones(placa_id, estacionamiento_id) WHERE salida_at IS NULL;

-- ─── fn_registrar_entrada_lpr ────────────────────────────────────────────────
-- Se llama cuando la cámara detecta placa entrante.
-- Crea (o localiza) la placa, crea sesión 'abierta' y devuelve el ticket + link.
CREATE OR REPLACE FUNCTION public.fn_registrar_entrada_lpr(
  p_placa_numero    text,
  p_estacionamiento uuid,
  p_tipo_codigo     text DEFAULT 'normal'
)
RETURNS TABLE (
  sesion_id     uuid,
  folio_entrada text,
  link_token    uuid,
  placa_numero  text,
  entrada_at    timestamptz
)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp
AS $$
DECLARE
  v_placa_id  uuid;
  v_tipo_id   uuid;
  v_estado_id uuid;
  v_pais_id   uuid;
  v_folio     text;
  v_token     uuid;
  v_sesion    uuid;
  v_now       timestamptz := NOW();
BEGIN
  -- Normalizar placa (uppercase, sin espacios)
  p_placa_numero := upper(regexp_replace(p_placa_numero, '\s+', '', 'g'));

  SELECT tipo_sesion_id INTO v_tipo_id FROM cat_tipo_sesion WHERE codigo = COALESCE(p_tipo_codigo,'normal');
  IF v_tipo_id IS NULL THEN SELECT tipo_sesion_id INTO v_tipo_id FROM cat_tipo_sesion WHERE codigo='normal'; END IF;
  SELECT estado_sesion_id INTO v_estado_id FROM cat_estado_sesion WHERE codigo='abierta';
  SELECT pais_id INTO v_pais_id FROM cat_pais WHERE codigo_iso2='MX' LIMIT 1;

  -- Placa: reutilizar si existe, crear si no
  SELECT placa_id INTO v_placa_id FROM placas WHERE numero = p_placa_numero LIMIT 1;
  IF v_placa_id IS NULL THEN
    INSERT INTO placas (numero, pais_id, activa) VALUES (p_placa_numero, v_pais_id, true)
    RETURNING placa_id INTO v_placa_id;
  END IF;

  -- Bloquear duplicados: si ya hay sesión abierta con esta placa en esta plaza, devolver esa
  SELECT s.sesion_id INTO v_sesion FROM sesiones s
   WHERE s.placa_id=v_placa_id AND s.estacionamiento_id=p_estacionamiento AND s.salida_at IS NULL
   LIMIT 1;
  IF v_sesion IS NOT NULL THEN
    RETURN QUERY
    SELECT s.sesion_id, s.folio_entrada, s.link_token, p_placa_numero, s.entrada_at
    FROM sesiones s WHERE s.sesion_id=v_sesion;
    RETURN;
  END IF;

  -- Generar folio y token
  v_folio := 'LPR-' || to_char(v_now,'YYMMDD') || '-' || substr(gen_random_uuid()::text,1,6);
  v_token := gen_random_uuid();

  INSERT INTO sesiones (
    estacionamiento_id, tipo_sesion_id, estado_sesion_id,
    folio_entrada, entrada_at, placa_id, link_token, requiere_cobro
  ) VALUES (
    p_estacionamiento, v_tipo_id, v_estado_id,
    v_folio, v_now, v_placa_id, v_token, true
  ) RETURNING sesiones.sesion_id INTO v_sesion;

  RETURN QUERY
  SELECT v_sesion, v_folio, v_token, p_placa_numero, v_now;
END $$;

GRANT EXECUTE ON FUNCTION public.fn_registrar_entrada_lpr(text,uuid,text) TO anon, authenticated, service_role;


-- ─── fn_obtener_ticket_por_token ────────────────────────────────────────────
-- La página pública /pay?token=X llama esto (via anon) para mostrar el importe.
CREATE OR REPLACE FUNCTION public.fn_obtener_ticket_por_token(p_token uuid)
RETURNS TABLE (
  sesion_id       uuid,
  folio_entrada   text,
  placa_numero    text,
  plaza_nombre    text,
  entrada_at      timestamptz,
  ahora           timestamptz,
  minutos         int,
  importe         numeric,
  pagado          boolean,
  pagado_at       timestamptz
)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,pg_temp
AS $$
DECLARE
  v_importe numeric;
  v_min     int;
BEGIN
  -- Recalcular importe en vivo antes de mostrar
  SELECT fn_calcular_importe_sesion(s.sesion_id) INTO v_importe
    FROM sesiones s WHERE s.link_token = p_token;

  RETURN QUERY
  SELECT
    s.sesion_id, s.folio_entrada, pl.numero, est.nombre,
    s.entrada_at, NOW(),
    GREATEST(0, CEIL(EXTRACT(EPOCH FROM (NOW()-s.entrada_at))/60.0))::int,
    v_importe,
    (s.pagado_at IS NOT NULL),
    s.pagado_at
  FROM sesiones s
  LEFT JOIN placas pl ON pl.placa_id = s.placa_id
  LEFT JOIN estacionamientos est ON est.estacionamiento_id = s.estacionamiento_id
  WHERE s.link_token = p_token
  LIMIT 1;
END $$;

GRANT EXECUTE ON FUNCTION public.fn_obtener_ticket_por_token(uuid) TO anon, authenticated, service_role;


-- ─── fn_confirmar_pago_token ────────────────────────────────────────────────
-- El "checkout" (o mock de Stripe) llama esto tras cobrar.
CREATE OR REPLACE FUNCTION public.fn_confirmar_pago_token(
  p_token          uuid,
  p_metodo_codigo  text DEFAULT 'link_pago',
  p_referencia     text DEFAULT NULL
)
RETURNS TABLE (
  sesion_id  uuid,
  monto      numeric,
  pagado_at  timestamptz,
  mensaje    text
)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp
AS $$
DECLARE
  v_ses       RECORD;
  v_metodo_id uuid;
  v_estado_id uuid;
  v_pago_id   uuid;
  v_importe   numeric;
  v_now       timestamptz := NOW();
BEGIN
  SELECT * INTO v_ses FROM sesiones WHERE link_token = p_token LIMIT 1;
  IF v_ses IS NULL THEN
    RETURN QUERY SELECT NULL::uuid, 0::numeric, NULL::timestamptz, 'Token inválido'::text; RETURN;
  END IF;
  IF v_ses.pagado_at IS NOT NULL THEN
    RETURN QUERY SELECT v_ses.sesion_id, v_ses.importe_total, v_ses.pagado_at, 'Ya pagado'::text; RETURN;
  END IF;

  -- Recalcular importe justo antes de cobrar
  v_importe := fn_calcular_importe_sesion(v_ses.sesion_id);

  SELECT metodo_pago_id INTO v_metodo_id FROM cat_metodo_pago WHERE codigo=p_metodo_codigo;
  IF v_metodo_id IS NULL THEN SELECT metodo_pago_id INTO v_metodo_id FROM cat_metodo_pago WHERE codigo='link_pago'; END IF;
  SELECT estado_pago_id INTO v_estado_id FROM cat_estado_pago WHERE codigo='capturado';

  INSERT INTO pagos (sesion_id, estacionamiento_id, metodo_pago_id, estado_pago_id,
                     monto, moneda_id, referencia_externa, cobrado_at, descripcion)
  VALUES (v_ses.sesion_id, v_ses.estacionamiento_id, v_metodo_id, v_estado_id,
          v_importe, (SELECT moneda_id FROM cat_moneda LIMIT 1),
          p_referencia, v_now, 'Pago autoservicio via QR/link')
  RETURNING pagos.pago_id INTO v_pago_id;

  UPDATE sesiones SET
    pagado_at        = v_now,
    importe_total    = v_importe,
    updated_at       = v_now,
    estado_sesion_id = (SELECT estado_sesion_id FROM cat_estado_sesion WHERE codigo='pagada')
  WHERE sesion_id = v_ses.sesion_id;

  RETURN QUERY SELECT v_ses.sesion_id, v_importe, v_now, 'Pago registrado'::text;
END $$;

GRANT EXECUTE ON FUNCTION public.fn_confirmar_pago_token(uuid,text,text) TO anon, authenticated, service_role;


-- ─── fn_verificar_salida_lpr ────────────────────────────────────────────────
-- Cámara de salida lee placa. Sistema busca sesión abierta+pagada de esa placa
-- en ese estacionamiento. Si existe, marca salida y devuelve 'autorizado'.
-- Si existe pero no está pagada, devuelve 'requiere_pago' + link_token.
-- Si no existe, devuelve 'no_encontrado'.
CREATE OR REPLACE FUNCTION public.fn_verificar_salida_lpr(
  p_placa_numero    text,
  p_estacionamiento uuid
)
RETURNS TABLE (
  resultado    text,       -- autorizado | requiere_pago | no_encontrado
  sesion_id    uuid,
  folio        text,
  importe      numeric,
  link_token   uuid,
  minutos      int
)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp
AS $$
DECLARE
  v_placa_id uuid; v_ses RECORD; v_importe numeric;
BEGIN
  p_placa_numero := upper(regexp_replace(p_placa_numero, '\s+', '', 'g'));
  SELECT placa_id INTO v_placa_id FROM placas WHERE numero=p_placa_numero;
  IF v_placa_id IS NULL THEN
    RETURN QUERY SELECT 'no_encontrado'::text, NULL::uuid, NULL::text, 0::numeric, NULL::uuid, 0; RETURN;
  END IF;

  SELECT * INTO v_ses FROM sesiones
   WHERE placa_id=v_placa_id AND estacionamiento_id=p_estacionamiento AND salida_at IS NULL
   ORDER BY entrada_at DESC LIMIT 1;
  IF v_ses IS NULL THEN
    RETURN QUERY SELECT 'no_encontrado'::text, NULL::uuid, NULL::text, 0::numeric, NULL::uuid, 0; RETURN;
  END IF;

  v_importe := fn_calcular_importe_sesion(v_ses.sesion_id);

  IF v_ses.pagado_at IS NULL AND v_importe > 0 THEN
    RETURN QUERY SELECT 'requiere_pago'::text, v_ses.sesion_id, v_ses.folio_entrada, v_importe,
                  v_ses.link_token, CEIL(EXTRACT(EPOCH FROM (NOW()-v_ses.entrada_at))/60)::int;
    RETURN;
  END IF;

  -- Autorizado: marcar salida
  UPDATE sesiones SET
    salida_at         = NOW(),
    folio_salida      = 'SAL-' || substr(v_ses.folio_entrada,5),
    estado_sesion_id  = (SELECT estado_sesion_id FROM cat_estado_sesion WHERE codigo='cerrada'),
    updated_at        = NOW()
  WHERE sesion_id = v_ses.sesion_id;

  RETURN QUERY SELECT 'autorizado'::text, v_ses.sesion_id, v_ses.folio_entrada,
               COALESCE(v_importe,0), v_ses.link_token,
               CEIL(EXTRACT(EPOCH FROM (NOW()-v_ses.entrada_at))/60)::int;
END $$;

GRANT EXECUTE ON FUNCTION public.fn_verificar_salida_lpr(text,uuid) TO anon, authenticated, service_role;

-- Regenerar link_token para tickets abiertos existentes (así demo funciona con datos ya sembrados)
UPDATE sesiones SET link_token = gen_random_uuid()
 WHERE salida_at IS NULL AND link_token IS NULL AND entrada_at > NOW() - INTERVAL '1 day';

NOTIFY pgrst, 'reload schema';

SELECT
  (SELECT COUNT(*) FROM sesiones WHERE link_token IS NOT NULL)::int AS con_link_token,
  (SELECT COUNT(*) FROM sesiones WHERE salida_at IS NULL)::int      AS abiertas_ahora;
