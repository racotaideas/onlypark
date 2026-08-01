-- ============================================================================
-- 036 — Módulo Empleados: extender clientes con puesto/area + seed
--
-- Los "empleados del centro comercial" (los que reciben cortesía cuando
-- entran con su auto) se modelan como CLIENTES con tipo_cliente = 'empleado'.
-- Extendemos clientes con dos columnas descriptivas y sembramos 40 empleados
-- distribuidos por las 18 plazas para que el módulo tenga volumen.
-- ============================================================================

ALTER TABLE public.clientes
  ADD COLUMN IF NOT EXISTS puesto TEXT,
  ADD COLUMN IF NOT EXISTS area   TEXT,
  ADD COLUMN IF NOT EXISTS estacionamiento_asignado_id UUID
    REFERENCES public.estacionamientos(estacionamiento_id);

DO $$
DECLARE
  v_tc_emp uuid;
  est RECORD; i integer;
  nombres text[]  := ARRAY['Juan','María','Pedro','Ana','Luis','Carmen','José','Rosa','Miguel','Elena','Diego','Sofía','Carlos','Patricia','Roberto','Isabel','Javier','Andrea'];
  apellidos text[]:= ARRAY['Torres','García','López','Ramírez','Cruz','Rojas','Vega','Silva','Morales','Ortega','Salinas','Vargas','Zúñiga','Hernández','Reyes','Pérez'];
  puestos text[]  := ARRAY['Gerente','Cajero','Vendedor','Almacenista','Recepción','Seguridad','Limpieza','Coordinador','Supervisor','Encargado'];
  areas text[]    := ARRAY['Ventas','Operaciones','Administración','Atención a cliente','Almacén','Seguridad','Housekeeping','Recursos Humanos'];
BEGIN
  SELECT tipo_cliente_id INTO v_tc_emp FROM cat_tipo_cliente WHERE codigo='empleado';

  FOR est IN
    SELECT ee.estacionamiento_id, e.empresa_id
    FROM estacionamientos ee
    JOIN sucursales s ON s.sucursal_id=ee.sucursal_id
    JOIN empresas e ON e.empresa_id=s.empresa_id
  LOOP
    -- 2-4 empleados por estacionamiento
    FOR i IN 1..(2 + (random()*2)::int) LOOP
      INSERT INTO clientes (
        empresa_id, tipo_cliente_id, nombre, apellidos, telefono, activo,
        puesto, area, estacionamiento_asignado_id
      ) VALUES (
        est.empresa_id, v_tc_emp,
        nombres[1 + (random()*(array_length(nombres,1)-1))::int],
        apellidos[1 + (random()*(array_length(apellidos,1)-1))::int],
        '55' || lpad((10000000 + (random()*89999999)::int)::text, 8, '0'),
        true,
        puestos[1 + (random()*(array_length(puestos,1)-1))::int],
        areas[1 + (random()*(array_length(areas,1)-1))::int],
        est.estacionamiento_id
      );
    END LOOP;
  END LOOP;
END $$;

SELECT COUNT(*)::int AS empleados_creados FROM clientes WHERE tipo_cliente_id=(SELECT tipo_cliente_id FROM cat_tipo_cliente WHERE codigo='empleado');
