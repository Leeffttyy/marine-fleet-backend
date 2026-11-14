-- =============================================================================
-- Marine Fleet · Caso 13 · Esquema para Supabase (PostgreSQL 15 o superior)
-- =============================================================================
-- Modelo completo: catálogos, seguridad, criminales, recompensas, inteligencia,
-- operativos, incidentes, auditoría, amenaza, notificaciones y reportes.
--
-- Decisiones del esquema:
--   * Ids varchar(36) con gen_random_uuid() por defecto: la API genera UUID y
--     los datos de prueba usan ids legibles (c-luffy, b-loguetown).
--   * Estados como tipos enumerados, fechas como timestamptz y JSON como jsonb.
--   * Índices en todas las llaves foráneas.
--   * Nombres y correos únicos sin distinguir mayúsculas (índices sobre lower()).
--   * Una sola recompensa VIGENTE por criminal y un solo criterio vigente por
--     nivel, garantizados por índices únicos parciales.
--   * Las recompensas solo avanzan PENDIENTE_VALIDACION -> VIGENTE | RECHAZADA y
--     VIGENTE -> HISTORICA; nunca cambian de monto ni se borran.
--   * La bitácora de auditoría solo admite inserciones.
--   * Row Level Security activo en todas las tablas: la API pública de Supabase
--     (claves anon y authenticated) no puede leerlas. El backend entra con el
--     usuario postgres, dueño de las tablas, y no se ve afectado.
--
-- Cómo correrlo: `npm run migration:run` (migración 1731300000000-EsquemaPostgres)
-- o el SQL Editor de Supabase. Es atómico: si algo falla, no queda nada a medias.
-- Es la línea base: no se vuelve a editar; los cambios van en migraciones nuevas.
-- =============================================================================

BEGIN;

SET search_path = public;

-- =============================================================================
-- 1. Tipos enumerados
-- =============================================================================

CREATE TYPE tipo_mar               AS ENUM ('CUATRO_MARES', 'GRAND_LINE');
CREATE TYPE estado_base_naval      AS ENUM ('ACTIVA', 'INACTIVA');
CREATE TYPE estado_usuario         AS ENUM ('ACTIVO', 'BLOQUEADO', 'INACTIVO');
CREATE TYPE tipo_agrupacion        AS ENUM ('TRIPULACION', 'ORGANIZACION', 'BANDA');
CREATE TYPE categoria_organizacion AS ENUM ('PIRATA', 'REVOLUCIONARIO', 'CRIMINAL_INDEPENDIENTE');
CREATE TYPE estado_criminal        AS ENUM ('ACTIVO', 'CAPTURADO', 'MUERTO');
CREATE TYPE nivel_amenaza          AS ENUM ('BAJO', 'MEDIO', 'ALTO', 'PENDIENTE');
CREATE TYPE rol_membresia          AS ENUM ('LIDER', 'OFICIAL', 'MIEMBRO');
CREATE TYPE estado_recompensa      AS ENUM ('PENDIENTE_VALIDACION', 'VIGENTE', 'HISTORICA', 'RECHAZADA');
CREATE TYPE motivo_cartel          AS ENUM ('REGISTRO', 'CAMBIO_FOTO', 'CAMBIO_RECOMPENSA',
                                            'CAMBIO_ESTADO', 'CAMBIO_AFILIACION', 'CAMBIO_DATOS',
                                            'MANUAL');
CREATE TYPE estado_verificacion    AS ENUM ('PENDIENTE', 'VERIFICADO', 'DESCARTADO');
CREATE TYPE origen_avistamiento    AS ENUM ('OFICIAL', 'REPORTE_CIUDADANO');
CREATE TYPE estado_reporte         AS ENUM ('PENDIENTE', 'APROBADO', 'RECHAZADO');
CREATE TYPE estado_operativo       AS ENUM ('PLANIFICADO', 'EN_CURSO', 'CERRADO', 'ABORTADO');
CREATE TYPE prioridad_operativo    AS ENUM ('BAJA', 'MEDIA', 'ALTA', 'CRITICA');
CREATE TYPE resultado_operativo    AS ENUM ('EXITOSO', 'PARCIAL', 'FALLIDO');
CREATE TYPE rol_participacion      AS ENUM ('LIDER', 'APOYO', 'LOGISTICA', 'BLOQUEO');
CREATE TYPE tipo_incidente         AS ENUM ('ENFRENTAMIENTO', 'CAPTURA', 'FUGA',
                                            'AVISTAMIENTO_HOSTIL', 'SABOTAJE');
CREATE TYPE resultado_incidente    AS ENUM ('EN_CURSO', 'EXITO', 'FRACASO', 'PARCIAL');
CREATE TYPE rol_en_incidente       AS ENUM ('OBJETIVO', 'COMPLICE', 'TESTIGO');
CREATE TYPE desenlace_participante AS ENUM ('CAPTURADO', 'ESCAPO', 'MUERTO', 'DESCONOCIDO');
CREATE TYPE tipo_accion_auditoria  AS ENUM ('CREACION', 'ACTUALIZACION', 'ELIMINACION_LOGICA',
                                            'CONSULTA', 'AUTENTICACION');

-- =============================================================================
-- 2. Funciones comunes
-- =============================================================================

-- Mantiene updated_at al día en cada UPDATE.
CREATE FUNCTION fn_tocar_updated_at() RETURNS trigger
LANGUAGE plpgsql SET search_path = public AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

-- =============================================================================
-- 3. Catálogos
-- =============================================================================

CREATE TABLE mares (
  id     varchar(36)  PRIMARY KEY DEFAULT gen_random_uuid()::text,
  nombre varchar(100) NOT NULL,
  tipo   tipo_mar     NOT NULL,
  activo boolean      NOT NULL DEFAULT true
);
-- Sin distinguir mayúsculas: "east blue" y "East Blue" son el mismo mar.
CREATE UNIQUE INDEX uq_mares_nombre ON mares (lower(nombre));
COMMENT ON TABLE mares IS 'Los Cuatro Mares y la Grand Line.';

CREATE TABLE zonas_influencia (
  id          varchar(36)  PRIMARY KEY DEFAULT gen_random_uuid()::text,
  mar_id      varchar(36)  NOT NULL,
  nombre      varchar(100) NOT NULL,
  descripcion text,
  activo      boolean      NOT NULL DEFAULT true,
  CONSTRAINT fk_zonas_mar FOREIGN KEY (mar_id) REFERENCES mares (id) ON DELETE RESTRICT
);
CREATE UNIQUE INDEX uq_zona_mar_nombre ON zonas_influencia (mar_id, lower(nombre));
COMMENT ON TABLE zonas_influencia IS 'Islas o regiones de un mar donde operan bases y criminales.';

CREATE TABLE bases_navales (
  id                 varchar(36)       PRIMARY KEY DEFAULT gen_random_uuid()::text,
  nombre             varchar(100)      NOT NULL,
  zona_influencia_id varchar(36)       NOT NULL,
  ubicacion          text              NOT NULL,
  comandante_nombre  varchar(150)      NOT NULL,
  estado             estado_base_naval NOT NULL DEFAULT 'ACTIVA',
  version            bigint            NOT NULL DEFAULT 1,
  created_at         timestamptz       NOT NULL DEFAULT now(),
  updated_at         timestamptz       NOT NULL DEFAULT now(),
  CONSTRAINT fk_bases_zona FOREIGN KEY (zona_influencia_id)
    REFERENCES zonas_influencia (id) ON DELETE RESTRICT
);
CREATE UNIQUE INDEX uq_bases_nombre ON bases_navales (lower(nombre));
CREATE INDEX ix_bases_zona ON bases_navales (zona_influencia_id);
COMMENT ON TABLE bases_navales IS 'Bases de la Marina. Se desactivan, no se borran.';

-- =============================================================================
-- 4. Seguridad: roles y usuarios
-- =============================================================================

CREATE TABLE roles (
  id           varchar(36)  PRIMARY KEY DEFAULT gen_random_uuid()::text,
  codigo       varchar(50)  NOT NULL,
  nombre       varchar(100) NOT NULL,
  descripcion  text,
  permisos     jsonb        NOT NULL DEFAULT '[]'::jsonb,
  requiere_2fa boolean      NOT NULL DEFAULT false,
  activo       boolean      NOT NULL DEFAULT true,
  created_at   timestamptz  NOT NULL DEFAULT now(),
  updated_at   timestamptz  NOT NULL DEFAULT now(),
  CONSTRAINT uq_roles_codigo UNIQUE (codigo),
  CONSTRAINT ck_roles_permisos CHECK (jsonb_typeof(permisos) = 'array')
);
COMMENT ON TABLE roles IS 'Roles RBAC. permisos es la lista de permisos atómicos (ALL = todos).';

CREATE TABLE usuarios (
  id                  varchar(36)    PRIMARY KEY DEFAULT gen_random_uuid()::text,
  nombre_completo     varchar(150)   NOT NULL,
  email               varchar(150)   NOT NULL,
  password_hash       varchar(255)   NOT NULL,
  rol_id              varchar(36)    NOT NULL,
  base_naval_id       varchar(36),
  estado              estado_usuario NOT NULL DEFAULT 'ACTIVO',
  mfa_habilitado      boolean        NOT NULL DEFAULT false,
  mfa_secreto_cifrado text,
  intentos_fallidos   integer        NOT NULL DEFAULT 0,
  ultimo_acceso       timestamptz,
  version             bigint         NOT NULL DEFAULT 1,
  created_at          timestamptz    NOT NULL DEFAULT now(),
  updated_at          timestamptz    NOT NULL DEFAULT now(),
  CONSTRAINT ck_usuarios_intentos CHECK (intentos_fallidos >= 0),
  CONSTRAINT fk_usuarios_rol FOREIGN KEY (rol_id) REFERENCES roles (id) ON DELETE RESTRICT,
  CONSTRAINT fk_usuarios_base FOREIGN KEY (base_naval_id)
    REFERENCES bases_navales (id) ON DELETE SET NULL
);
-- El login busca por lower(email): el correo no distingue mayúsculas.
CREATE UNIQUE INDEX uq_usuarios_email ON usuarios (lower(email));
CREATE INDEX ix_usuarios_rol ON usuarios (rol_id);
CREATE INDEX ix_usuarios_base ON usuarios (base_naval_id);
COMMENT ON TABLE usuarios IS 'Cuentas del sistema. base_naval_id nulo = rol global.';

-- =============================================================================
-- 5. Dominio criminal
-- =============================================================================

CREATE TABLE organizaciones (
  id                 varchar(36)            PRIMARY KEY DEFAULT gen_random_uuid()::text,
  nombre             varchar(100)           NOT NULL,
  tipo_agrupacion    tipo_agrupacion        NOT NULL,
  categoria          categoria_organizacion NOT NULL,
  zona_influencia_id varchar(36),
  descripcion        text,
  activa             boolean                NOT NULL DEFAULT true,
  version            bigint                 NOT NULL DEFAULT 1,
  created_at         timestamptz            NOT NULL DEFAULT now(),
  updated_at         timestamptz            NOT NULL DEFAULT now(),
  CONSTRAINT fk_org_zona FOREIGN KEY (zona_influencia_id)
    REFERENCES zonas_influencia (id) ON DELETE SET NULL
);
CREATE UNIQUE INDEX uq_organizaciones_nombre ON organizaciones (lower(nombre));
CREATE INDEX ix_organizaciones_zona ON organizaciones (zona_influencia_id);
COMMENT ON TABLE organizaciones IS 'Tripulaciones, bandas y organizaciones criminales.';

CREATE TABLE criminales (
  id                       varchar(36)     PRIMARY KEY DEFAULT gen_random_uuid()::text,
  nombre                   varchar(150)    NOT NULL,
  nombre_normalizado       varchar(150)    NOT NULL,
  alias                    jsonb,
  edad                     integer,
  descripcion_fisica       text,
  foto                     jsonb,
  estado                   estado_criminal NOT NULL DEFAULT 'ACTIVO',
  fecha_baja               timestamptz,
  zona_influencia_id       varchar(36),
  recompensa_vigente_monto numeric(15, 2),
  nivel_amenaza            nivel_amenaza   NOT NULL DEFAULT 'PENDIENTE',
  origen_base_id           varchar(36),
  creado_por               varchar(36),
  actualizado_por          varchar(36),
  version                  bigint          NOT NULL DEFAULT 1,
  created_at               timestamptz     NOT NULL DEFAULT now(),
  updated_at               timestamptz     NOT NULL DEFAULT now(),
  CONSTRAINT uq_criminales_nombre_normalizado UNIQUE (nombre_normalizado),
  CONSTRAINT ck_criminales_edad CHECK (edad IS NULL OR edad BETWEEN 0 AND 500),
  CONSTRAINT ck_criminales_recompensa CHECK (recompensa_vigente_monto IS NULL
                                             OR recompensa_vigente_monto >= 0),
  CONSTRAINT ck_criminales_alias CHECK (alias IS NULL OR jsonb_typeof(alias) = 'array'),
  -- Un criminal en busca no tiene fecha de baja.
  CONSTRAINT ck_criminales_baja CHECK (estado <> 'ACTIVO' OR fecha_baja IS NULL),
  CONSTRAINT fk_criminales_zona FOREIGN KEY (zona_influencia_id)
    REFERENCES zonas_influencia (id) ON DELETE SET NULL,
  CONSTRAINT fk_criminales_base FOREIGN KEY (origen_base_id)
    REFERENCES bases_navales (id) ON DELETE SET NULL,
  CONSTRAINT fk_criminales_creado FOREIGN KEY (creado_por)
    REFERENCES usuarios (id) ON DELETE SET NULL,
  CONSTRAINT fk_criminales_actualizado FOREIGN KEY (actualizado_por)
    REFERENCES usuarios (id) ON DELETE SET NULL
);
CREATE INDEX ix_criminales_estado_nivel ON criminales (estado, nivel_amenaza);
CREATE INDEX ix_criminales_zona ON criminales (zona_influencia_id);
CREATE INDEX ix_criminales_origen_base ON criminales (origen_base_id);
COMMENT ON TABLE criminales IS
  'Ficha del criminal. recompensa_vigente_monto copia el monto de su recompensa VIGENTE.';

CREATE TABLE membresias (
  id              varchar(36)   PRIMARY KEY DEFAULT gen_random_uuid()::text,
  criminal_id     varchar(36)   NOT NULL,
  organizacion_id varchar(36)   NOT NULL,
  rol             rol_membresia NOT NULL DEFAULT 'MIEMBRO',
  vigente         boolean       NOT NULL DEFAULT true,
  fecha_ingreso   timestamptz,
  fecha_salida    timestamptz,
  creado_por      varchar(36),
  created_at      timestamptz   NOT NULL DEFAULT now(),
  CONSTRAINT ck_membresias_fechas CHECK (fecha_salida IS NULL OR fecha_ingreso IS NULL
                                         OR fecha_salida >= fecha_ingreso),
  CONSTRAINT fk_membresias_criminal FOREIGN KEY (criminal_id)
    REFERENCES criminales (id) ON DELETE CASCADE,
  CONSTRAINT fk_membresias_org FOREIGN KEY (organizacion_id)
    REFERENCES organizaciones (id) ON DELETE CASCADE
);
CREATE INDEX ix_membresias_criminal ON membresias (criminal_id);
CREATE INDEX ix_membresias_organizacion ON membresias (organizacion_id);
-- Un criminal no puede estar dos veces a la vez en la misma organización.
CREATE UNIQUE INDEX uq_membresias_vigente ON membresias (criminal_id, organizacion_id)
  WHERE vigente;
COMMENT ON TABLE membresias IS 'Afiliaciones. Al salir se marca vigente = false; no se borran.';

CREATE TABLE antecedentes (
  id             varchar(36)  PRIMARY KEY DEFAULT gen_random_uuid()::text,
  criminal_id    varchar(36)  NOT NULL,
  tipo_delito    varchar(100) NOT NULL,
  descripcion    text         NOT NULL,
  fecha_hecho    timestamptz,
  ubicacion      text,
  registrado_por varchar(36),
  version        bigint       NOT NULL DEFAULT 1,
  created_at     timestamptz  NOT NULL DEFAULT now(),
  updated_at     timestamptz  NOT NULL DEFAULT now(),
  CONSTRAINT fk_antecedentes_criminal FOREIGN KEY (criminal_id)
    REFERENCES criminales (id) ON DELETE CASCADE
);
CREATE INDEX ix_antecedentes_criminal ON antecedentes (criminal_id);
COMMENT ON TABLE antecedentes IS 'Delitos registrados de cada criminal.';

-- -----------------------------------------------------------------------------
-- Recompensas: historial completo e inmutable.
-- Cada cambio de monto es una fila nueva. La anterior pasa a HISTORICA con su
-- vigente_hasta, de modo que se puede reconstruir cuánto valía un criminal en
-- cualquier fecha (el reporte mensual por mar depende de eso).
-- -----------------------------------------------------------------------------
CREATE TABLE recompensas (
  id                  varchar(36)       PRIMARY KEY DEFAULT gen_random_uuid()::text,
  criminal_id         varchar(36)       NOT NULL,
  monto               numeric(15, 2)    NOT NULL,
  moneda              varchar(20)       NOT NULL DEFAULT 'BERRIES',
  estado              estado_recompensa NOT NULL DEFAULT 'PENDIENTE_VALIDACION',
  requiere_validacion boolean           NOT NULL DEFAULT false,
  solicitada_por      varchar(36),
  fecha_solicitud     timestamptz       NOT NULL DEFAULT now(),
  validada_por        varchar(36),
  fecha_validacion    timestamptz,
  vigente_desde       timestamptz,
  vigente_hasta       timestamptz,
  motivo              text,
  created_at          timestamptz       NOT NULL DEFAULT now(),
  CONSTRAINT ck_recompensas_monto CHECK (monto >= 0),
  CONSTRAINT ck_recompensas_periodo CHECK (vigente_hasta IS NULL OR vigente_desde IS NULL
                                           OR vigente_hasta >= vigente_desde),
  -- RESTRICT: un criminal con recompensas no se borra (las recompensas tampoco).
  CONSTRAINT fk_recompensas_criminal FOREIGN KEY (criminal_id)
    REFERENCES criminales (id) ON DELETE RESTRICT
);
CREATE INDEX ix_recompensas_criminal_estado ON recompensas (criminal_id, estado);
CREATE INDEX ix_recompensas_estado_solicitud ON recompensas (estado, fecha_solicitud DESC);
CREATE UNIQUE INDEX uq_recompensas_una_vigente ON recompensas (criminal_id)
  WHERE estado = 'VIGENTE';
COMMENT ON TABLE recompensas IS
  'Historial de recompensas. Inmutable: no se borra ni cambia el monto; solo avanza de estado.';

CREATE TABLE criterios_amenaza (
  id             varchar(36)    PRIMARY KEY DEFAULT gen_random_uuid()::text,
  nivel          nivel_amenaza  NOT NULL,
  monto_minimo   numeric(15, 2) NOT NULL,
  monto_maximo   numeric(15, 2),
  vigente        boolean        NOT NULL DEFAULT true,
  vigente_desde  timestamptz    NOT NULL DEFAULT now(),
  vigente_hasta  timestamptz,
  modificado_por varchar(36),
  motivo         text,
  CONSTRAINT ck_criterios_rango CHECK (monto_minimo >= 0
                                       AND (monto_maximo IS NULL OR monto_maximo >= monto_minimo))
);
CREATE UNIQUE INDEX uq_criterios_vigente_por_nivel ON criterios_amenaza (nivel) WHERE vigente;
COMMENT ON TABLE criterios_amenaza IS
  'Umbrales de recompensa por nivel de amenaza. Los reemplazados quedan con vigente = false.';

CREATE TABLE carteles (
  id                varchar(36)   PRIMARY KEY DEFAULT gen_random_uuid()::text,
  criminal_id       varchar(36)   NOT NULL,
  numero_version    integer       NOT NULL,
  vigente           boolean       NOT NULL DEFAULT true,
  archivo           jsonb         NOT NULL,
  datos_instantanea jsonb         NOT NULL,
  motivo_generacion motivo_cartel NOT NULL,
  generado_por      varchar(36),
  generado_en       timestamptz   NOT NULL DEFAULT now(),
  CONSTRAINT uq_cartel_version UNIQUE (criminal_id, numero_version),
  CONSTRAINT fk_carteles_criminal FOREIGN KEY (criminal_id)
    REFERENCES criminales (id) ON DELETE CASCADE
);
COMMENT ON TABLE carteles IS 'Versiones del cartel WANTED de cada criminal.';

-- =============================================================================
-- 6. Inteligencia
-- =============================================================================

CREATE TABLE avistamientos (
  id                  varchar(36)         PRIMARY KEY DEFAULT gen_random_uuid()::text,
  criminal_id         varchar(36)         NOT NULL,
  fecha_hora          timestamptz         NOT NULL,
  ubicacion           text                NOT NULL,
  testigo             varchar(150),
  zona_influencia_id  varchar(36),
  estado_verificacion estado_verificacion NOT NULL DEFAULT 'PENDIENTE',
  origen              origen_avistamiento NOT NULL DEFAULT 'OFICIAL',
  observaciones       text,
  registrado_por      varchar(36),
  verificado_por      varchar(36),
  created_at          timestamptz         NOT NULL DEFAULT now(),
  CONSTRAINT fk_avistamientos_criminal FOREIGN KEY (criminal_id)
    REFERENCES criminales (id) ON DELETE CASCADE,
  CONSTRAINT fk_avistamientos_zona FOREIGN KEY (zona_influencia_id)
    REFERENCES zonas_influencia (id) ON DELETE SET NULL
);
CREATE INDEX ix_avistamientos_criminal_fecha ON avistamientos (criminal_id, fecha_hora);
CREATE INDEX ix_avistamientos_zona ON avistamientos (zona_influencia_id);
CREATE INDEX ix_avistamientos_fecha ON avistamientos (fecha_hora);
COMMENT ON TABLE avistamientos IS 'Avistamientos oficiales o aprobados desde un reporte ciudadano.';

CREATE TABLE reportes_ciudadanos (
  id                 varchar(36)    PRIMARY KEY DEFAULT gen_random_uuid()::text,
  criminal_id        varchar(36)    NOT NULL,
  descripcion        text           NOT NULL,
  fecha_hecho        timestamptz,
  ubicacion          text           NOT NULL,
  zona_influencia_id varchar(36),
  informante         jsonb          NOT NULL,
  estado             estado_reporte NOT NULL DEFAULT 'PENDIENTE',
  revisado_por       varchar(36),
  fecha_revision     timestamptz,
  motivo_rechazo     text,
  avistamiento_id    varchar(36),
  created_at         timestamptz    NOT NULL DEFAULT now(),
  CONSTRAINT fk_reportes_criminal FOREIGN KEY (criminal_id)
    REFERENCES criminales (id) ON DELETE CASCADE,
  CONSTRAINT fk_reportes_zona FOREIGN KEY (zona_influencia_id)
    REFERENCES zonas_influencia (id) ON DELETE SET NULL,
  CONSTRAINT fk_reportes_avistamiento FOREIGN KEY (avistamiento_id)
    REFERENCES avistamientos (id) ON DELETE SET NULL
);
CREATE INDEX ix_reportes_criminal ON reportes_ciudadanos (criminal_id);
CREATE INDEX ix_reportes_estado ON reportes_ciudadanos (estado, created_at DESC);
COMMENT ON TABLE reportes_ciudadanos IS 'Reportes del público, pendientes de revisión.';

-- =============================================================================
-- 7. Trazabilidad de criminales (la alimentan triggers, nunca la aplicación)
-- =============================================================================

CREATE TABLE criminales_historial (
  id             bigint      GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
  criminal_id    varchar(36) NOT NULL,
  campo          varchar(60) NOT NULL,
  valor_anterior text,
  valor_nuevo    text,
  usuario_id     varchar(36),
  fecha          timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ix_historial_criminal_fecha ON criminales_historial (criminal_id, fecha);
COMMENT ON TABLE criminales_historial IS
  'Bitácora de cambios: atributos del criminal, afiliaciones, antecedentes y estados de recompensa.';

-- =============================================================================
-- 8. Operativos (RF-4)
-- =============================================================================

CREATE TABLE operativos (
  id                    varchar(36)         PRIMARY KEY DEFAULT gen_random_uuid()::text,
  codigo                varchar(50)         NOT NULL,
  nombre                varchar(150)        NOT NULL,
  objetivo_criminal_id  varchar(36),
  objetivo              text,
  zona_influencia_id    varchar(36)         NOT NULL,
  base_lider_id         varchar(36)         NOT NULL,
  estado                estado_operativo    NOT NULL DEFAULT 'PLANIFICADO',
  prioridad             prioridad_operativo NOT NULL DEFAULT 'MEDIA',
  descripcion           text,
  fecha_inicio_planeada timestamptz,
  fecha_inicio_real     timestamptz,
  fecha_cierre          timestamptz,
  resultado_final       resultado_operativo,
  observaciones_cierre  text,
  creado_por            varchar(36),
  version               bigint              NOT NULL DEFAULT 1,
  created_at            timestamptz         NOT NULL DEFAULT now(),
  updated_at            timestamptz         NOT NULL DEFAULT now(),
  CONSTRAINT uq_operativos_codigo UNIQUE (codigo),
  CONSTRAINT ck_operativos_version CHECK (version >= 0),
  -- El cierre exige resultado (regla del dominio).
  CONSTRAINT ck_operativos_cierre CHECK (estado <> 'CERRADO' OR resultado_final IS NOT NULL),
  CONSTRAINT fk_operativos_criminal FOREIGN KEY (objetivo_criminal_id)
    REFERENCES criminales (id) ON DELETE SET NULL,
  CONSTRAINT fk_operativos_zona FOREIGN KEY (zona_influencia_id)
    REFERENCES zonas_influencia (id) ON DELETE RESTRICT,
  CONSTRAINT fk_operativos_base_lider FOREIGN KEY (base_lider_id)
    REFERENCES bases_navales (id) ON DELETE RESTRICT,
  CONSTRAINT fk_operativos_creado FOREIGN KEY (creado_por)
    REFERENCES usuarios (id) ON DELETE SET NULL
);
CREATE INDEX ix_operativos_estado_prioridad ON operativos (estado, prioridad);
CREATE INDEX ix_operativos_zona_estado ON operativos (zona_influencia_id, estado);
CREATE INDEX ix_operativos_objetivo ON operativos (objetivo_criminal_id);
CREATE INDEX ix_operativos_base_lider ON operativos (base_lider_id);
COMMENT ON TABLE operativos IS 'Operativos coordinados entre bases navales.';

CREATE TABLE operativo_bases (
  id                 varchar(36)       PRIMARY KEY DEFAULT gen_random_uuid()::text,
  operativo_id       varchar(36)       NOT NULL,
  base_naval_id      varchar(36)       NOT NULL,
  rol_participacion  rol_participacion NOT NULL DEFAULT 'APOYO',
  unidades_asignadas integer           NOT NULL DEFAULT 0,
  confirmada         boolean           NOT NULL DEFAULT false,
  observaciones      text,
  recursos           text,
  created_at         timestamptz       NOT NULL DEFAULT now(),
  CONSTRAINT uq_operativo_base UNIQUE (operativo_id, base_naval_id),
  CONSTRAINT ck_opbases_unidades CHECK (unidades_asignadas >= 0),
  CONSTRAINT fk_opbases_operativo FOREIGN KEY (operativo_id)
    REFERENCES operativos (id) ON DELETE CASCADE,
  CONSTRAINT fk_opbases_base FOREIGN KEY (base_naval_id)
    REFERENCES bases_navales (id) ON DELETE RESTRICT
);
CREATE INDEX ix_opbases_base ON operativo_bases (base_naval_id);
COMMENT ON TABLE operativo_bases IS 'Bases que participan en cada operativo y sus recursos.';

CREATE TABLE operativo_responsables (
  id           varchar(36)  PRIMARY KEY DEFAULT gen_random_uuid()::text,
  operativo_id varchar(36)  NOT NULL,
  usuario_id   varchar(36)  NOT NULL,
  funcion      varchar(100) NOT NULL DEFAULT 'RESPONSABLE',
  created_at   timestamptz  NOT NULL DEFAULT now(),
  CONSTRAINT uq_operativo_responsable UNIQUE (operativo_id, usuario_id),
  CONSTRAINT fk_opresp_operativo FOREIGN KEY (operativo_id)
    REFERENCES operativos (id) ON DELETE CASCADE,
  CONSTRAINT fk_opresp_usuario FOREIGN KEY (usuario_id)
    REFERENCES usuarios (id) ON DELETE CASCADE
);
CREATE INDEX ix_opresp_usuario ON operativo_responsables (usuario_id);
COMMENT ON TABLE operativo_responsables IS 'Oficiales a cargo de cada operativo.';

-- =============================================================================
-- 9. Incidentes y enfrentamientos (RF-6)
-- =============================================================================

CREATE TABLE incidentes (
  id                   varchar(36)         PRIMARY KEY DEFAULT gen_random_uuid()::text,
  operativo_id         varchar(36),
  tipo                 tipo_incidente      NOT NULL,
  resultado            resultado_incidente NOT NULL DEFAULT 'EN_CURSO',
  fecha_hora           timestamptz         NOT NULL,
  ubicacion            text                NOT NULL,
  zona_influencia_id   varchar(36),
  base_naval_id        varchar(36),
  descripcion          text                NOT NULL,
  bajas_marina         integer             NOT NULL DEFAULT 0,
  bajas_enemigas       integer             NOT NULL DEFAULT 0,
  observaciones        text,
  participantes_marina jsonb,
  registrado_por       varchar(36),
  version              bigint              NOT NULL DEFAULT 1,
  created_at           timestamptz         NOT NULL DEFAULT now(),
  updated_at           timestamptz         NOT NULL DEFAULT now(),
  CONSTRAINT ck_incidentes_bajas CHECK (bajas_marina >= 0 AND bajas_enemigas >= 0),
  CONSTRAINT ck_incidentes_version CHECK (version >= 0),
  CONSTRAINT ck_incidentes_marina CHECK (participantes_marina IS NULL
                                         OR jsonb_typeof(participantes_marina) = 'array'),
  CONSTRAINT fk_incidentes_operativo FOREIGN KEY (operativo_id)
    REFERENCES operativos (id) ON DELETE SET NULL,
  CONSTRAINT fk_incidentes_zona FOREIGN KEY (zona_influencia_id)
    REFERENCES zonas_influencia (id) ON DELETE SET NULL,
  CONSTRAINT fk_incidentes_base FOREIGN KEY (base_naval_id)
    REFERENCES bases_navales (id) ON DELETE SET NULL,
  CONSTRAINT fk_incidentes_registrado FOREIGN KEY (registrado_por)
    REFERENCES usuarios (id) ON DELETE SET NULL
);
CREATE INDEX ix_incidentes_fecha ON incidentes (fecha_hora DESC);
CREATE INDEX ix_incidentes_tipo_resultado ON incidentes (tipo, resultado);
CREATE INDEX ix_incidentes_operativo ON incidentes (operativo_id);
COMMENT ON TABLE incidentes IS 'Enfrentamientos, capturas y fugas.';

CREATE TABLE incidente_participantes (
  id               varchar(36)            PRIMARY KEY DEFAULT gen_random_uuid()::text,
  incidente_id     varchar(36)            NOT NULL,
  criminal_id      varchar(36)            NOT NULL,
  rol_en_incidente rol_en_incidente       NOT NULL DEFAULT 'OBJETIVO',
  desenlace        desenlace_participante NOT NULL DEFAULT 'DESCONOCIDO',
  observaciones    text,
  created_at       timestamptz            NOT NULL DEFAULT now(),
  CONSTRAINT uq_incidente_criminal UNIQUE (incidente_id, criminal_id),
  CONSTRAINT fk_participantes_incidente FOREIGN KEY (incidente_id)
    REFERENCES incidentes (id) ON DELETE CASCADE,
  CONSTRAINT fk_participantes_criminal FOREIGN KEY (criminal_id)
    REFERENCES criminales (id) ON DELETE CASCADE
);
CREATE INDEX ix_participantes_criminal ON incidente_participantes (criminal_id);
COMMENT ON TABLE incidente_participantes IS 'Criminales involucrados en un incidente y su desenlace.';

-- =============================================================================
-- 10. Auditoría, amenaza, notificaciones y reportes
-- =============================================================================

CREATE TABLE auditoria (
  id             varchar(36)           PRIMARY KEY DEFAULT gen_random_uuid()::text,
  usuario_id     varchar(36),
  rol            varchar(50),
  accion         varchar(80)           NOT NULL,
  tipo_accion    tipo_accion_auditoria NOT NULL DEFAULT 'ACTUALIZACION',
  entidad        varchar(60),
  entidad_id     varchar(36),
  valor_anterior jsonb,
  valor_nuevo    jsonb,
  metodo         varchar(10),
  ruta           varchar(255),
  ip             varchar(64),
  exitoso        boolean               NOT NULL DEFAULT true,
  fecha          timestamptz           NOT NULL DEFAULT now()
);
CREATE INDEX ix_auditoria_fecha ON auditoria (fecha);
CREATE INDEX ix_auditoria_usuario ON auditoria (usuario_id, fecha);
CREATE INDEX ix_auditoria_entidad ON auditoria (entidad, entidad_id);
COMMENT ON TABLE auditoria IS 'Bitácora consultable de acciones. Solo admite inserciones.';

CREATE TABLE analisis_riesgo (
  id             varchar(36)    PRIMARY KEY DEFAULT gen_random_uuid()::text,
  criminal_id    varchar(36)    NOT NULL,
  fecha_analisis timestamptz    NOT NULL DEFAULT now(),
  monto_evaluado numeric(15, 2),
  nivel_base       nivel_amenaza NOT NULL,
  nivel_resultante nivel_amenaza NOT NULL,
  escalado       boolean        NOT NULL DEFAULT false,
  justificacion  text           NOT NULL,
  ejecutado_por  varchar(36),
  CONSTRAINT fk_analisis_criminal FOREIGN KEY (criminal_id)
    REFERENCES criminales (id) ON DELETE CASCADE
);
CREATE INDEX ix_analisis_criminal_fecha ON analisis_riesgo (criminal_id, fecha_analisis);
COMMENT ON TABLE analisis_riesgo IS 'Historial de clasificaciones de amenaza de cada criminal.';

CREATE TABLE notificaciones (
  id              varchar(36)  PRIMARY KEY DEFAULT gen_random_uuid()::text,
  base_naval_id   varchar(36),
  usuario_id      varchar(36),
  tipo            varchar(60)  NOT NULL,
  titulo          varchar(150) NOT NULL,
  mensaje         text         NOT NULL,
  referencia_tipo varchar(40),
  referencia_id   varchar(36),
  leida           boolean      NOT NULL DEFAULT false,
  created_at      timestamptz  NOT NULL DEFAULT now(),
  CONSTRAINT fk_notif_base FOREIGN KEY (base_naval_id)
    REFERENCES bases_navales (id) ON DELETE CASCADE
);
CREATE INDEX ix_notificaciones_base ON notificaciones (base_naval_id, leida, created_at);
COMMENT ON TABLE notificaciones IS 'Avisos a las bases. base_naval_id nulo = aviso global.';

CREATE TABLE reportes_recompensas (
  id                  varchar(36)    PRIMARY KEY DEFAULT gen_random_uuid()::text,
  periodo             char(7)        NOT NULL,
  mar_id              varchar(36)    NOT NULL,
  mar_nombre          varchar(100)   NOT NULL,
  total_acumulado     numeric(18, 2) NOT NULL DEFAULT 0,
  cantidad_criminales integer        NOT NULL DEFAULT 0,
  generado_por        varchar(36),
  generado_en         timestamptz    NOT NULL DEFAULT now(),
  CONSTRAINT uq_reporte_periodo_mar UNIQUE (periodo, mar_id),
  CONSTRAINT ck_reportes_periodo CHECK (periodo ~ '^[0-9]{4}-(0[1-9]|1[0-2])$')
);
COMMENT ON TABLE reportes_recompensas IS
  'Instantánea mensual del total en recompensas activas por mar (periodo YYYY-MM).';

-- =============================================================================
-- 11. Triggers
-- =============================================================================

-- updated_at automático en las tablas que lo tienen.
CREATE TRIGGER trg_bases_navales_updated_at BEFORE UPDATE ON bases_navales
  FOR EACH ROW EXECUTE FUNCTION fn_tocar_updated_at();
CREATE TRIGGER trg_roles_updated_at BEFORE UPDATE ON roles
  FOR EACH ROW EXECUTE FUNCTION fn_tocar_updated_at();
CREATE TRIGGER trg_usuarios_updated_at BEFORE UPDATE ON usuarios
  FOR EACH ROW EXECUTE FUNCTION fn_tocar_updated_at();
CREATE TRIGGER trg_organizaciones_updated_at BEFORE UPDATE ON organizaciones
  FOR EACH ROW EXECUTE FUNCTION fn_tocar_updated_at();
CREATE TRIGGER trg_criminales_updated_at BEFORE UPDATE ON criminales
  FOR EACH ROW EXECUTE FUNCTION fn_tocar_updated_at();
CREATE TRIGGER trg_antecedentes_updated_at BEFORE UPDATE ON antecedentes
  FOR EACH ROW EXECUTE FUNCTION fn_tocar_updated_at();
CREATE TRIGGER trg_operativos_updated_at BEFORE UPDATE ON operativos
  FOR EACH ROW EXECUTE FUNCTION fn_tocar_updated_at();
CREATE TRIGGER trg_incidentes_updated_at BEFORE UPDATE ON incidentes
  FOR EACH ROW EXECUTE FUNCTION fn_tocar_updated_at();

-- RNF de trazabilidad: el rastro lo deja la base, así que incluso un UPDATE
-- hecho a mano en el editor de Supabase queda registrado. El usuario se toma de
-- actualizado_por, que la aplicación llena en cada escritura.
CREATE FUNCTION fn_criminales_historial() RETURNS trigger
LANGUAGE plpgsql SET search_path = public AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    INSERT INTO criminales_historial
      (criminal_id, campo, valor_anterior, valor_nuevo, usuario_id, fecha)
    VALUES (NEW.id, 'REGISTRO', NULL, NEW.nombre, NEW.creado_por, NEW.created_at);
    RETURN NEW;
  END IF;

  INSERT INTO criminales_historial (criminal_id, campo, valor_anterior, valor_nuevo, usuario_id)
  SELECT NEW.id, cambio.campo, cambio.anterior, cambio.nuevo, NEW.actualizado_por
    FROM (VALUES
      ('nombre',                   OLD.nombre,                         NEW.nombre),
      ('alias',                    OLD.alias::text,                    NEW.alias::text),
      ('edad',                     OLD.edad::text,                     NEW.edad::text),
      ('descripcion_fisica',       OLD.descripcion_fisica,             NEW.descripcion_fisica),
      ('foto',                     OLD.foto::text,                     NEW.foto::text),
      ('estado',                   OLD.estado::text,                   NEW.estado::text),
      ('zona_influencia_id',       OLD.zona_influencia_id,             NEW.zona_influencia_id),
      ('recompensa_vigente_monto', OLD.recompensa_vigente_monto::text, NEW.recompensa_vigente_monto::text),
      ('nivel_amenaza',            OLD.nivel_amenaza::text,            NEW.nivel_amenaza::text)
    ) AS cambio (campo, anterior, nuevo)
   WHERE cambio.anterior IS DISTINCT FROM cambio.nuevo;
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_criminales_historial
  AFTER INSERT OR UPDATE ON criminales
  FOR EACH ROW EXECUTE FUNCTION fn_criminales_historial();

-- Afiliaciones: alta, baja (vigente pasa a false) y cambio de rango.
CREATE FUNCTION fn_membresias_historial() RETURNS trigger
LANGUAGE plpgsql SET search_path = public AS $$
DECLARE
  organizacion text;
BEGIN
  SELECT nombre INTO organizacion FROM organizaciones WHERE id = NEW.organizacion_id;

  IF TG_OP = 'INSERT' THEN
    INSERT INTO criminales_historial
      (criminal_id, campo, valor_anterior, valor_nuevo, usuario_id, fecha)
    VALUES (NEW.criminal_id, 'afiliacion', NULL,
            organizacion || ' (' || NEW.rol::text || ')', NEW.creado_por, NEW.created_at);
  ELSIF OLD.vigente AND NOT NEW.vigente THEN
    INSERT INTO criminales_historial
      (criminal_id, campo, valor_anterior, valor_nuevo, usuario_id, fecha)
    VALUES (NEW.criminal_id, 'afiliacion',
            organizacion || ' (' || OLD.rol::text || ')', 'DESAFILIADO', NEW.creado_por,
            COALESCE(NEW.fecha_salida, now()));
  ELSIF OLD.rol IS DISTINCT FROM NEW.rol THEN
    INSERT INTO criminales_historial (criminal_id, campo, valor_anterior, valor_nuevo, usuario_id)
    VALUES (NEW.criminal_id, 'afiliacion.rol', OLD.rol::text, NEW.rol::text, NEW.creado_por);
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_membresias_historial
  AFTER INSERT OR UPDATE ON membresias
  FOR EACH ROW EXECUTE FUNCTION fn_membresias_historial();

CREATE FUNCTION fn_antecedentes_historial() RETURNS trigger
LANGUAGE plpgsql SET search_path = public AS $$
BEGIN
  INSERT INTO criminales_historial
    (criminal_id, campo, valor_anterior, valor_nuevo, usuario_id, fecha)
  VALUES (NEW.criminal_id, 'antecedente', NULL, NEW.tipo_delito, NEW.registrado_por,
          NEW.created_at);
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_antecedentes_historial
  AFTER INSERT ON antecedentes
  FOR EACH ROW EXECUTE FUNCTION fn_antecedentes_historial();

-- Registros críticos: una recompensa nunca cambia de monto ni de criminal, no
-- se borra y solo avanza por su ciclo de vida.
CREATE FUNCTION fn_recompensas_inmutables() RETURNS trigger
LANGUAGE plpgsql SET search_path = public AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION 'Las recompensas no se eliminan.'
      USING ERRCODE = 'integrity_constraint_violation';
  END IF;

  IF NEW.monto IS DISTINCT FROM OLD.monto OR NEW.criminal_id IS DISTINCT FROM OLD.criminal_id THEN
    RAISE EXCEPTION 'Una recompensa es inmutable: emite una nueva en su lugar.'
      USING ERRCODE = 'integrity_constraint_violation';
  END IF;

  IF NEW.estado IS DISTINCT FROM OLD.estado AND NOT (
       (OLD.estado = 'PENDIENTE_VALIDACION' AND NEW.estado IN ('VIGENTE', 'RECHAZADA'))
    OR (OLD.estado = 'VIGENTE' AND NEW.estado = 'HISTORICA')
  ) THEN
    RAISE EXCEPTION 'Transición de recompensa no permitida: % -> %.', OLD.estado, NEW.estado
      USING ERRCODE = 'integrity_constraint_violation';
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_recompensas_inmutables
  BEFORE UPDATE OR DELETE ON recompensas
  FOR EACH ROW EXECUTE FUNCTION fn_recompensas_inmutables();

-- Cada cambio de estado de una recompensa queda en la bitácora del criminal.
CREATE FUNCTION fn_recompensas_historial() RETURNS trigger
LANGUAGE plpgsql SET search_path = public AS $$
BEGIN
  IF NEW.estado IS DISTINCT FROM OLD.estado THEN
    INSERT INTO criminales_historial (criminal_id, campo, valor_anterior, valor_nuevo, usuario_id)
    VALUES (NEW.criminal_id, 'recompensa:' || NEW.id, OLD.estado::text, NEW.estado::text,
            COALESCE(NEW.validada_por, NEW.solicitada_por));
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_recompensas_historial
  AFTER UPDATE ON recompensas
  FOR EACH ROW EXECUTE FUNCTION fn_recompensas_historial();

-- La bitácora de auditoría no se reescribe.
CREATE FUNCTION fn_auditoria_solo_insercion() RETURNS trigger
LANGUAGE plpgsql SET search_path = public AS $$
BEGIN
  RAISE EXCEPTION 'La auditoría solo admite inserciones.'
    USING ERRCODE = 'integrity_constraint_violation';
END;
$$;

CREATE TRIGGER trg_auditoria_solo_insercion
  BEFORE UPDATE OR DELETE ON auditoria
  FOR EACH ROW EXECUTE FUNCTION fn_auditoria_solo_insercion();

-- =============================================================================
-- 12. Row Level Security
-- =============================================================================
-- Sin políticas, las claves anon y authenticated de Supabase no ven ninguna
-- fila. El backend usa el usuario postgres (dueño de las tablas), al que RLS no
-- le aplica. Si algún día el frontend lee directo con supabase-js, se agregan
-- políticas puntuales en vez de desactivar RLS.

DO $$
DECLARE
  tabla text;
BEGIN
  FOREACH tabla IN ARRAY ARRAY[
    'mares', 'zonas_influencia', 'bases_navales', 'roles', 'usuarios', 'organizaciones',
    'criminales', 'membresias', 'antecedentes', 'recompensas', 'criterios_amenaza', 'carteles',
    'avistamientos', 'reportes_ciudadanos', 'criminales_historial', 'operativos',
    'operativo_bases', 'operativo_responsables', 'incidentes', 'incidente_participantes',
    'auditoria', 'analisis_riesgo', 'notificaciones', 'reportes_recompensas'
  ] LOOP
    EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY', tabla);
  END LOOP;
END;
$$;

COMMIT;
