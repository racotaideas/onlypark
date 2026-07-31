-- ============================================================================
-- DWH v1 — Parte 2: Facts (fact_tickets, fact_pagos, fact_ocupacion_hora)
-- ============================================================================

-- fact_tickets: 1 fila por sesión cerrada
CREATE TABLE IF NOT EXISTS dwh.fact_tickets (
  fact_ticket_id       uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  sesion_id            uuid NOT NULL UNIQUE,
  fecha_entrada_id     integer NOT NULL REFERENCES dwh.dim_tiempo(fecha_id),
  hora_entrada_id      smallint NOT NULL REFERENCES dwh.dim_hora(hora_id),
  fecha_salida_id      integer     REFERENCES dwh.dim_tiempo(fecha_id),
  hora_salida_id       smallint    REFERENCES dwh.dim_hora(hora_id),
  estacionamiento_sk   uuid NOT NULL REFERENCES dwh.dim_estacionamiento(estacionamiento_sk),
  empresa_sk           bigint NOT NULL REFERENCES dwh.dim_empresa(empresa_sk),
  tipo_sesion_sk       bigint REFERENCES dwh.dim_tipo_sesion(tipo_sesion_sk),
  cajero_entrada_sk    bigint REFERENCES dwh.dim_usuario(usuario_sk),
  cajero_salida_sk     bigint REFERENCES dwh.dim_usuario(usuario_sk),
  duracion_minutos     integer,
  requiere_cobro       boolean,
  importe_calculado    numeric(14,4),
  importe_descuento    numeric(14,4),
  importe_total        numeric(14,4),
  fue_cobrada          boolean NOT NULL DEFAULT false,
  cargado_at           timestamptz NOT NULL DEFAULT NOW(),
  origen_updated_at    timestamptz NOT NULL
);
CREATE INDEX IF NOT EXISTS ix_ft_est_fecha  ON dwh.fact_tickets(estacionamiento_sk, fecha_entrada_id);
CREATE INDEX IF NOT EXISTS ix_ft_emp_fecha  ON dwh.fact_tickets(empresa_sk, fecha_entrada_id);
CREATE INDEX IF NOT EXISTS ix_ft_orig_upd   ON dwh.fact_tickets(origen_updated_at);

-- fact_pagos: 1 fila por pago cobrado
CREATE TABLE IF NOT EXISTS dwh.fact_pagos (
  fact_pago_id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  pago_id              uuid NOT NULL UNIQUE,
  sesion_id            uuid,
  fact_ticket_id       uuid REFERENCES dwh.fact_tickets(fact_ticket_id),
  fecha_cobro_id       integer NOT NULL REFERENCES dwh.dim_tiempo(fecha_id),
  hora_cobro_id        smallint NOT NULL REFERENCES dwh.dim_hora(hora_id),
  estacionamiento_sk   uuid NOT NULL REFERENCES dwh.dim_estacionamiento(estacionamiento_sk),
  empresa_sk           bigint NOT NULL REFERENCES dwh.dim_empresa(empresa_sk),
  metodo_pago_sk       bigint REFERENCES dwh.dim_metodo_pago(metodo_pago_sk),
  cajero_sk            bigint REFERENCES dwh.dim_usuario(usuario_sk),
  monto                numeric(14,4) NOT NULL,
  moneda_id            uuid,
  referencia_externa   text,
  cargado_at           timestamptz NOT NULL DEFAULT NOW(),
  origen_updated_at    timestamptz NOT NULL
);
CREATE INDEX IF NOT EXISTS ix_fp_est_fecha  ON dwh.fact_pagos(estacionamiento_sk, fecha_cobro_id);
CREATE INDEX IF NOT EXISTS ix_fp_metodo     ON dwh.fact_pagos(metodo_pago_sk);
CREATE INDEX IF NOT EXISTS ix_fp_orig_upd   ON dwh.fact_pagos(origen_updated_at);

-- fact_ocupacion_hora: agregado por hora × estacionamiento
CREATE TABLE IF NOT EXISTS dwh.fact_ocupacion_hora (
  fact_ocup_id         bigserial PRIMARY KEY,
  fecha_id             integer NOT NULL REFERENCES dwh.dim_tiempo(fecha_id),
  hora_id              smallint NOT NULL REFERENCES dwh.dim_hora(hora_id),
  estacionamiento_sk   uuid NOT NULL REFERENCES dwh.dim_estacionamiento(estacionamiento_sk),
  entradas             integer NOT NULL DEFAULT 0,
  salidas              integer NOT NULL DEFAULT 0,
  ocupacion_snapshot   integer,
  capacidad_total      integer,
  pct_ocupacion        numeric(6,3),
  cargado_at           timestamptz NOT NULL DEFAULT NOW(),
  UNIQUE (estacionamiento_sk, fecha_id, hora_id)
);
