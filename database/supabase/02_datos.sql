-- =============================================================================
-- Marine Fleet · Caso 13 · Datos de prueba del universo One Piece
-- =============================================================================
-- Es lo que corre `npm run seed`; también se puede pegar en el SQL Editor de
-- Supabase. Correr después de 01_esquema.sql.
--
-- Qué cambió respecto al seed anterior:
--   * Recompensas al día con el canon (Buggy 3.189M, Nami 366M, Teach 3.996M...)
--     y con su progresión completa: cada criminal trae su historial de
--     recompensas HISTORICA -> VIGENTE con fechas contiguas, así el reporte
--     mensual por mar da valores distintos según el mes consultado.
--   * 26 criminales (antes 12), entre ellos los del tablero de mando: Shanks,
--     Kaido y Law. Aparecen los tres estados: ACTIVO, CAPTURADO y MUERTO.
--   * Afiliaciones pasadas (Robin en Baroque Works, Teach en Barbablanca...).
--   * Operativos, bases asignadas, responsables, incidentes, notificaciones,
--     análisis de riesgo y reportes mensuales, que antes no se sembraban.
--   * Una recompensa PENDIENTE_VALIDACION y una RECHAZADA para la bandeja del
--     Almirante, y criterios de amenaza vigentes junto a los reemplazados.
--   * Los ids de usuario y rol usan guiones (u-director-inteligencia): el guion
--     bajo no pasaba la validación de ids de la API (ParseIdPipe).
--   * El nivel de amenaza no se escribe a mano: se calcula con los criterios
--     vigentes de la tabla, con la misma regla del motor de clasificación.
--
-- Usuarios: <codigo>@marina.gov, contraseña Marina.2026 (hash bcrypt, costo 10).
-- Es idempotente: se puede correr varias veces sin duplicar filas.
-- Los carteles no se siembran porque necesitan sus archivos; se generan con
-- POST /api/v1/carteles/regenerar-todos.
-- =============================================================================

BEGIN;

SET search_path = public;

-- Fechas de la semilla: un día a mediodía, hora de Colombia.
CREATE OR REPLACE FUNCTION pg_temp.dia(d date) RETURNS timestamptz
LANGUAGE sql STABLE AS $$ SELECT (d::text || ' 12:00-05')::timestamptz $$;

-- =============================================================================
-- 1. Catálogos
-- =============================================================================

INSERT INTO mares (id, nombre, tipo) VALUES
  ('m-east-blue',  'East Blue',  'CUATRO_MARES'),
  ('m-west-blue',  'West Blue',  'CUATRO_MARES'),
  ('m-north-blue', 'North Blue', 'CUATRO_MARES'),
  ('m-south-blue', 'South Blue', 'CUATRO_MARES'),
  ('m-grand-line', 'Grand Line', 'GRAND_LINE')
ON CONFLICT DO NOTHING;

INSERT INTO zonas_influencia (id, mar_id, nombre, descripcion) VALUES
  ('z-foosha',       'm-east-blue',  'Villa Foosha',          'Isla Dawn, pueblo natal de Luffy'),
  ('z-loguetown',    'm-east-blue',  'Loguetown',             'Ciudad del principio y del fin'),
  ('z-shells',       'm-east-blue',  'Shells Town',           'Sede de la Base 153'),
  ('z-cocoyasi',     'm-east-blue',  'Villa Cocoyasi',        'Isla Conomi'),
  ('z-ohara',        'm-west-blue',  'Ohara',                 'Isla de los arqueólogos'),
  ('z-flevance',     'm-north-blue', 'Flevance',              'El pueblo blanco'),
  ('z-baterilla',    'm-south-blue', 'Baterilla',             'Isla natal de Portgas D. Rouge'),
  ('z-alabasta',     'm-grand-line', 'Alabasta',              'Reino del desierto'),
  ('z-water7',       'm-grand-line', 'Water 7',               'Ciudad de los astilleros'),
  ('z-sabaody',      'm-grand-line', 'Archipiélago Sabaody',  'Antesala del Nuevo Mundo'),
  ('z-marineford',   'm-grand-line', 'Marineford',            'Antiguo Cuartel General de la Marina'),
  ('z-impel-down',   'm-grand-line', 'Impel Down',            'Gran prisión submarina del Gobierno Mundial'),
  ('z-amazon-lily',  'm-grand-line', 'Amazon Lily',           'Isla de las Kuja, en el Calm Belt'),
  ('z-navarone',     'm-grand-line', 'Navarone',              'Fortaleza naval G-8'),
  ('z-dressrosa',    'm-grand-line', 'Dressrosa',             'Reino del Nuevo Mundo'),
  ('z-wano',         'm-grand-line', 'Wano',                  'País cerrado del Nuevo Mundo'),
  ('z-karai-bari',   'm-grand-line', 'Karai Bari',            'Sede de Cross Guild, Nuevo Mundo'),
  ('z-hachinosu',    'm-grand-line', 'Hachinosu',             'Isla Colmena, guarida de Barbanegra'),
  ('z-elbaph',       'm-grand-line', 'Elbaph',                'Isla de los gigantes, Nuevo Mundo')
ON CONFLICT DO NOTHING;

INSERT INTO bases_navales (id, nombre, zona_influencia_id, ubicacion, comandante_nombre, estado) VALUES
  ('b-153',         'Base 153',         'z-shells',      'Shells Town, East Blue',         'Capitán Ripper',              'ACTIVA'),
  ('b-loguetown',   'Base de Loguetown','z-loguetown',   'Loguetown, East Blue',           'Capitán Smoker',              'ACTIVA'),
  ('b-16',          'Base 16',          'z-alabasta',    'Nanohana, Alabasta',             'Capitana Hina',               'ACTIVA'),
  ('b-g1',          'Base G-1',         'z-sabaody',     'Archipiélago Sabaody',           'Vicealmirante Momonga',       'ACTIVA'),
  ('b-marineford',  'Base de Marineford','z-marineford',  'Marineford',                     'Almirante de Flota Sakazuki', 'ACTIVA'),
  ('b-g5',          'Base G-5',         'z-dressrosa',   'Nuevo Mundo',                    'Vicealmirante Smoker',        'ACTIVA'),
  ('b-impel-down',  'Impel Down',       'z-impel-down',  'Calm Belt, bajo el mar',         'Jefe de Prisión Magellan',    'ACTIVA'),
  ('b-g8',          'Base G-8',         'z-navarone',    'Isla Navarone, Grand Line',      'Vicealmirante Jonathan',      'INACTIVA')
ON CONFLICT DO NOTHING;

-- =============================================================================
-- 2. Roles y usuarios (uno por rol)
-- =============================================================================
-- Se actualizan si ya existen, por si cambió la matriz de permisos
-- (PERMISOS_POR_ROL en src/shared/domain/rbac/permiso.enum.ts).

INSERT INTO roles (id, codigo, nombre, descripcion, permisos, requiere_2fa) VALUES
  ('r-almirante', 'ALMIRANTE', 'Almirante de la Marina',
   'Mando supremo: valida las recompensas de mil millones o más.',
   '["ALL"]', true),
  ('r-director-inteligencia', 'DIRECTOR_INTELIGENCIA', 'Director de Inteligencia',
   'Dirige el Centro de Inteligencia y revisa los reportes ciudadanos.',
   '["CRIMINALES_LEER","CRIMINALES_ESCRIBIR","INTELIGENCIA_LEER","INTELIGENCIA_ESCRIBIR",
     "INTELIGENCIA_REVISAR_REPORTES","OPERATIVOS_LEER","INCIDENTES_LEER","CARTELES_GENERAR",
     "REPORTES_LEER"]', true),
  ('r-analista-datos-criminales', 'ANALISTA_DATOS_CRIMINALES', 'Analista de Datos Criminales',
   'Registra criminales, solicita recompensas y es el único que ajusta los criterios de amenaza.',
   '["CRIMINALES_LEER","CRIMINALES_ESCRIBIR","RECOMPENSAS_SOLICITAR","CARTELES_GENERAR",
     "INTELIGENCIA_LEER","INCIDENTES_LEER","OPERATIVOS_LEER","AMENAZA_CONFIGURAR_CRITERIOS",
     "REPORTES_LEER"]', false),
  ('r-coordinador-operaciones', 'COORDINADOR_OPERACIONES', 'Coordinador de Operaciones',
   'Planifica operativos entre bases y registra enfrentamientos.',
   '["CRIMINALES_LEER","INTELIGENCIA_LEER","OPERATIVOS_LEER","OPERATIVOS_COORDINAR",
     "INCIDENTES_LEER","INCIDENTES_ESCRIBIR","CATALOGOS_ADMINISTRAR","REPORTES_LEER"]', false),
  ('r-desarrollador-backend', 'DESARROLLADOR_BACKEND', 'Desarrollador Backend',
   'Soporte técnico del sistema.',
   '["CRIMINALES_LEER","INTELIGENCIA_LEER","OPERATIVOS_LEER","INCIDENTES_LEER",
     "SISTEMA_CONFIGURAR"]', false),
  ('r-especialista-seguridad', 'ESPECIALISTA_SEGURIDAD', 'Especialista en Seguridad Informática',
   'Administra cuentas y consulta la auditoría.',
   '["USUARIOS_ADMINISTRAR","AUDITORIA_LEER","SISTEMA_CONFIGURAR","CRIMINALES_LEER"]', true),
  ('r-capitan', 'CAPITAN', 'Capitán de Base',
   'Opera desde su base: registra criminales, avistamientos e incidentes.',
   '["CRIMINALES_LEER","CRIMINALES_ESCRIBIR","RECOMPENSAS_SOLICITAR","INTELIGENCIA_LEER",
     "INTELIGENCIA_ESCRIBIR","OPERATIVOS_LEER","INCIDENTES_LEER","INCIDENTES_ESCRIBIR"]', false)
ON CONFLICT (id) DO UPDATE
  SET nombre = EXCLUDED.nombre, descripcion = EXCLUDED.descripcion,
      permisos = EXCLUDED.permisos, requiere_2fa = EXCLUDED.requiere_2fa, activo = true;

-- MFA queda deshabilitado en las cuentas de prueba: no tienen secreto TOTP
-- enrolado y la demo debe poder entrar solo con contraseña.
INSERT INTO usuarios (id, nombre_completo, email, password_hash, rol_id, base_naval_id) VALUES
  ('u-almirante',                 'Sakazuki',                              'almirante@marina.gov',                 '$2b$10$KdSp1325u26jsyQBdDKkMOZJd/Hc9Zig.e/j1EIvgPAWLIB3ZfqLe', 'r-almirante',                 NULL),
  ('u-director-inteligencia',     'Tsuru',                                 'director_inteligencia@marina.gov',     '$2b$10$KdSp1325u26jsyQBdDKkMOZJd/Hc9Zig.e/j1EIvgPAWLIB3ZfqLe', 'r-director-inteligencia',     NULL),
  ('u-analista-datos-criminales', 'Tashigi',                               'analista_datos_criminales@marina.gov', '$2b$10$KdSp1325u26jsyQBdDKkMOZJd/Hc9Zig.e/j1EIvgPAWLIB3ZfqLe', 'r-analista-datos-criminales', NULL),
  ('u-coordinador-operaciones',   'Brannew',                               'coordinador_operaciones@marina.gov',   '$2b$10$KdSp1325u26jsyQBdDKkMOZJd/Hc9Zig.e/j1EIvgPAWLIB3ZfqLe', 'r-coordinador-operaciones',   'b-marineford'),
  ('u-desarrollador-backend',     'Vegapunk',                              'desarrollador_backend@marina.gov',     '$2b$10$KdSp1325u26jsyQBdDKkMOZJd/Hc9Zig.e/j1EIvgPAWLIB3ZfqLe', 'r-desarrollador-backend',     NULL),
  ('u-especialista-seguridad',    'Doberman',                              'especialista_seguridad@marina.gov',    '$2b$10$KdSp1325u26jsyQBdDKkMOZJd/Hc9Zig.e/j1EIvgPAWLIB3ZfqLe', 'r-especialista-seguridad',    NULL),
  ('u-capitan',                   'Smoker',                                'capitan@marina.gov',                   '$2b$10$KdSp1325u26jsyQBdDKkMOZJd/Hc9Zig.e/j1EIvgPAWLIB3ZfqLe', 'r-capitan',                   'b-loguetown')
ON CONFLICT (id) DO UPDATE
  SET nombre_completo = EXCLUDED.nombre_completo, rol_id = EXCLUDED.rol_id,
      password_hash = EXCLUDED.password_hash,
      base_naval_id = EXCLUDED.base_naval_id, estado = 'ACTIVO', intentos_fallidos = 0;

-- =============================================================================
-- 3. Criterios de amenaza
-- =============================================================================
-- Los vigentes son los que usa el motor de clasificación. Los de 2023 quedan
-- como historial (vigente = false), igual que cuando el Analista los reemplaza.

INSERT INTO criterios_amenaza
  (id, nivel, monto_minimo, monto_maximo, vigente, vigente_desde, vigente_hasta, modificado_por, motivo)
VALUES
  ('ca-2023-bajo',  'BAJO',  1,             49999999,  false, pg_temp.dia('2023-01-10'), pg_temp.dia('2025-01-10'), 'u-analista-datos-criminales', 'Umbrales iniciales del sistema'),
  ('ca-2023-medio', 'MEDIO', 50000000,      499999999, false, pg_temp.dia('2023-01-10'), pg_temp.dia('2025-01-10'), 'u-analista-datos-criminales', 'Umbrales iniciales del sistema'),
  ('ca-2023-alto',  'ALTO',  500000000,     NULL,      false, pg_temp.dia('2023-01-10'), pg_temp.dia('2025-01-10'), 'u-analista-datos-criminales', 'Umbrales iniciales del sistema'),
  ('ca-bajo',       'BAJO',  1,             99999999,  true,  pg_temp.dia('2025-01-10'), NULL, 'u-analista-datos-criminales', 'Se elevaron los umbrales con la llegada de los nuevos Emperadores'),
  ('ca-medio',      'MEDIO', 100000000,     999999999, true,  pg_temp.dia('2025-01-10'), NULL, 'u-analista-datos-criminales', 'Se elevaron los umbrales con la llegada de los nuevos Emperadores'),
  ('ca-alto',       'ALTO',  1000000000,    NULL,      true,  pg_temp.dia('2025-01-10'), NULL, 'u-analista-datos-criminales', 'Se elevaron los umbrales con la llegada de los nuevos Emperadores')
ON CONFLICT DO NOTHING;

-- =============================================================================
-- 4. Organizaciones
-- =============================================================================

INSERT INTO organizaciones (id, nombre, tipo_agrupacion, categoria, zona_influencia_id, descripcion, activa) VALUES
  ('org-sombrero-paja',  'Piratas del Sombrero de Paja', 'TRIPULACION',  'PIRATA',                 'z-wano',        'Tripulación de Monkey D. Luffy, uno de los Cuatro Emperadores', true),
  ('org-pelirrojo',      'Piratas del Pelirrojo',        'TRIPULACION',  'PIRATA',                 'z-elbaph',      'Tripulación de Shanks, uno de los Cuatro Emperadores', true),
  ('org-barbanegra',     'Piratas de Barbanegra',        'TRIPULACION',  'PIRATA',                 'z-hachinosu',   'Tripulación de Marshall D. Teach, uno de los Cuatro Emperadores', true),
  ('org-cross-guild',    'Cross Guild',                  'ORGANIZACION', 'PIRATA',                 'z-karai-bari',  'Ofrece recompensas por la cabeza de los marines', true),
  ('org-buggy',          'Piratas de Buggy',             'TRIPULACION',  'PIRATA',                 'z-karai-bari',  'Tripulación de Buggy, absorbida por Cross Guild', true),
  ('org-heart',          'Piratas Heart',                'TRIPULACION',  'PIRATA',                 'z-wano',        'Tripulación de Trafalgar Law', true),
  ('org-kuja',           'Piratas Kuja',                 'TRIPULACION',  'PIRATA',                 'z-amazon-lily', 'Tripulación de guerreras de Amazon Lily', true),
  ('org-arlong',         'Piratas de Arlong',            'BANDA',        'PIRATA',                 'z-cocoyasi',    'Banda de hombres pez', true),
  ('org-revolucionario', 'Ejército Revolucionario',      'ORGANIZACION', 'REVOLUCIONARIO',         NULL,            'Organización política opuesta al Gobierno Mundial', true),
  ('org-baroque',        'Baroque Works',                'ORGANIZACION', 'CRIMINAL_INDEPENDIENTE', 'z-alabasta',    'Sindicato criminal secreto, desmantelado en Alabasta', false),
  ('org-donquixote',     'Familia Donquixote',           'ORGANIZACION', 'CRIMINAL_INDEPENDIENTE', 'z-dressrosa',   'Red de tráfico de armas, desmantelada en Dressrosa', false),
  ('org-bestias',        'Piratas de las Bestias',       'TRIPULACION',  'PIRATA',                 'z-wano',        'Tripulación de Kaido, disuelta tras la batalla de Onigashima', false),
  ('org-barbablanca',    'Piratas de Barbablanca',       'TRIPULACION',  'PIRATA',                 NULL,            'Tripulación de Edward Newgate, disuelta tras Marineford', false),
  ('org-roger',          'Piratas de Roger',             'TRIPULACION',  'PIRATA',                 NULL,            'Tripulación del Rey de los Piratas, disuelta', false)
ON CONFLICT DO NOTHING;

-- =============================================================================
-- 5. Criminales con su historial de recompensas
-- =============================================================================

CREATE TEMP TABLE semilla_criminales (
  id          text PRIMARY KEY,
  nombre      text NOT NULL,
  alias       jsonb NOT NULL,
  edad        integer,
  descripcion text,
  estado      estado_criminal NOT NULL,
  baja        date,
  zona        text NOT NULL,
  base_origen text
) ON COMMIT DROP;

INSERT INTO semilla_criminales VALUES
  ('c-luffy',       'Monkey D. Luffy',        '["Sombrero de Paja","Quinto Emperador"]',            19, 'Sombrero de paja, cicatriz bajo el ojo izquierdo y otra en forma de X en el pecho', 'ACTIVO',    NULL,         'z-wano',        'b-loguetown'),
  ('c-zoro',        'Roronoa Zoro',           '["Cazador de Piratas","Rey del Infierno"]',          21, 'Cabello verde, tres espadas y una cicatriz sobre el ojo izquierdo',                'ACTIVO',    NULL,         'z-wano',        'b-153'),
  ('c-nami',        'Nami',                   '["Gata Ladrona"]',                                   20, 'Cabello naranja y tatuaje en el hombro izquierdo',                                 'ACTIVO',    NULL,         'z-cocoyasi',    NULL),
  ('c-usopp',       'Usopp',                  '["Dios Usopp","Sogeking"]',                          19, 'Nariz larga, overol y gafas de francotirador',                                     'ACTIVO',    NULL,         'z-water7',      NULL),
  ('c-sanji',       'Sanji',                  '["Pierna Negra","Vinsmoke Sanji"]',                  21, 'Cabello rubio que le tapa un ojo y ceja en espiral',                               'ACTIVO',    NULL,         'z-wano',        NULL),
  ('c-chopper',     'Tony Tony Chopper',      '["Amante del algodón de azúcar"]',                   17, 'Reno con sombrero rosado y nariz azul',                                            'ACTIVO',    NULL,         'z-wano',        NULL),
  ('c-robin',       'Nico Robin',             '["Niña Demonio","Luz de la Revolución"]',            30, 'Cabello negro largo y mirada serena',                                              'ACTIVO',    NULL,         'z-ohara',       NULL),
  ('c-franky',      'Franky',                 '["Cyborg Franky","Iron Man Franky"]',                36, 'Cyborg de cabello azul con antebrazos enormes',                                    'ACTIVO',    NULL,         'z-water7',      NULL),
  ('c-brook',       'Brook',                  '["Soul King","Brook el Tarareador"]',                90, 'Esqueleto con afro y sombrero de copa',                                            'ACTIVO',    NULL,         'z-wano',        NULL),
  ('c-jinbe',       'Jinbe',                  '["Caballero del Mar"]',                              46, 'Hombre pez tiburón ballena con kimono',                                            'ACTIVO',    NULL,         'z-wano',        NULL),
  ('c-shanks',      'Shanks',                 '["Pelirrojo"]',                                      39, 'Cabello rojo, tres cicatrices sobre el ojo izquierdo y sin brazo izquierdo',      'ACTIVO',    NULL,         'z-elbaph',      NULL),
  ('c-teach',       'Marshall D. Teach',      '["Barbanegra"]',                                     40, 'Barba negra y le faltan varios dientes',                                           'ACTIVO',    NULL,         'z-sabaody',     'b-g1'),
  ('c-buggy',       'Buggy',                  '["El Payaso","Buggy el Genial"]',                    39, 'Nariz roja de payaso; su cuerpo se separa en pedazos',                             'ACTIVO',    NULL,         'z-foosha',      'b-153'),
  ('c-mihawk',      'Dracule Mihawk',         '["Ojos de Halcón","El mejor espadachín del mundo"]', 43, 'Ojos amarillos y la espada negra Yoru',                                            'ACTIVO',    NULL,         'z-karai-bari',  NULL),
  ('c-crocodile',   'Sir Crocodile',          '["Mr. 0"]',                                          46, 'Garfio dorado y cicatriz que le cruza el rostro',                                  'ACTIVO',    NULL,         'z-alabasta',    'b-16'),
  ('c-mr3',         'Galdino',                '["Mr. 3"]',                                          31, 'Peinado en forma de 3',                                                            'ACTIVO',    NULL,         'z-alabasta',    'b-16'),
  ('c-law',         'Trafalgar D. Water Law', '["Cirujano de la Muerte"]',                          26, 'Gorro moteado y tatuajes en manos y brazos',                                       'ACTIVO',    NULL,         'z-flevance',    NULL),
  ('c-hancock',     'Boa Hancock',            '["Emperatriz Pirata","Princesa Serpiente"]',         31, 'Cabello negro largo; considerada la mujer más bella del mundo',                    'ACTIVO',    NULL,         'z-amazon-lily', NULL),
  ('c-sabo',        'Sabo',                   '["Jefe del Estado Mayor"]',                          22, 'Sombrero de copa y cicatriz de quemadura en el ojo izquierdo',                     'ACTIVO',    NULL,         'z-baterilla',   NULL),
  ('c-dragon',      'Monkey D. Dragon',       '["El Revolucionario"]',                              55, 'Tatuaje rojo en el lado izquierdo del rostro',                                     'ACTIVO',    NULL,         'z-flevance',    NULL),
  ('c-doflamingo',  'Donquixote Doflamingo',  '["Joker","Demonio Celestial"]',                      41, 'Abrigo de plumas rosado y gafas de sol',                                           'CAPTURADO', '2024-09-12', 'z-dressrosa',   'b-g5'),
  ('c-kaido',       'Kaido',                  '["El más fuerte de las criaturas","Rey de las Bestias"]', 59, 'Gigante con cuernos, bigote largo y tatuajes en los brazos',                 'CAPTURADO', '2025-08-30', 'z-wano',        NULL),
  ('c-arlong',      'Arlong',                 '["Arlong el Sierra"]',                               41, 'Hombre pez con nariz de sierra',                                                   'CAPTURADO', '2023-03-12', 'z-cocoyasi',    'b-153'),
  ('c-ace',         'Portgas D. Ace',         '["Puño de Fuego"]',                                  20, 'Sombrero naranja y pecas',                                                         'MUERTO',    '2024-01-25', 'z-marineford',  NULL),
  ('c-barbablanca', 'Edward Newgate',         '["Barbablanca"]',                                    72, 'Bigote blanco en forma de media luna',                                             'MUERTO',    '2024-01-25', 'z-marineford',  NULL),
  ('c-roger',       'Gol D. Roger',           '["Rey de los Piratas"]',                             53, 'Bigote poblado y sombrero de capitán',                                             'MUERTO',    '2002-04-01', 'z-loguetown',   NULL);

-- Progresión de recompensas: la última de cada criminal queda VIGENTE y las
-- anteriores HISTORICA, cerradas el día en que entró la siguiente. Las
-- anteriores a 2023 vienen del archivo histórico de la Marina.
CREATE TEMP TABLE semilla_recompensas (
  criminal_id text NOT NULL,
  orden       integer NOT NULL,
  monto       numeric(15, 2) NOT NULL,
  desde       date NOT NULL,
  motivo      text NOT NULL,
  PRIMARY KEY (criminal_id, orden)
) ON COMMIT DROP;

INSERT INTO semilla_recompensas VALUES
  ('c-luffy', 1,     30000000, '2023-03-12', 'Derrotó a Arlong en East Blue'),
  ('c-luffy', 2,    100000000, '2023-06-20', 'Frustró el golpe de Estado de Crocodile en Alabasta'),
  ('c-luffy', 3,    300000000, '2023-10-25', 'Ataque a Enies Lobby y quema de la bandera del Gobierno Mundial'),
  ('c-luffy', 4,    400000000, '2024-02-01', 'Irrumpió en Impel Down y en la guerra de Marineford'),
  ('c-luffy', 5,    500000000, '2024-09-20', 'Caída de Doflamingo en Dressrosa'),
  ('c-luffy', 6,   1500000000, '2025-02-25', 'Incidente de Whole Cake Island'),
  ('c-luffy', 7,   3000000000, '2025-09-05', 'Derrota de Kaido en Wano; reconocido como Emperador'),
  ('c-zoro', 1,      60000000, '2023-06-20', 'Alabasta'),
  ('c-zoro', 2,     120000000, '2023-10-25', 'Enies Lobby'),
  ('c-zoro', 3,     320000000, '2024-09-20', 'Dressrosa'),
  ('c-zoro', 4,    1111000000, '2025-09-05', 'Derrotó a King en Onigashima'),
  ('c-nami', 1,      16000000, '2023-10-25', 'Enies Lobby'),
  ('c-nami', 2,      66000000, '2024-09-20', 'Dressrosa'),
  ('c-nami', 3,     366000000, '2025-09-05', 'Wano'),
  ('c-usopp', 1,     30000000, '2023-10-25', 'Enies Lobby (registrado como Sogeking)'),
  ('c-usopp', 2,    200000000, '2024-09-20', 'Derribó a Sugar en Dressrosa'),
  ('c-usopp', 3,    500000000, '2025-09-05', 'Wano'),
  ('c-sanji', 1,     77000000, '2023-10-25', 'Enies Lobby (el cartel salió con un dibujo)'),
  ('c-sanji', 2,    177000000, '2024-09-20', 'Dressrosa'),
  ('c-sanji', 3,    330000000, '2025-02-25', 'Whole Cake Island'),
  ('c-sanji', 4,   1032000000, '2025-09-05', 'Derrotó a Queen en Onigashima'),
  ('c-chopper', 1,         50, '2023-10-25', 'Enies Lobby (lo tomaron por la mascota)'),
  ('c-chopper', 2,        100, '2024-09-20', 'Dressrosa'),
  ('c-chopper', 3,       1000, '2025-09-05', 'Wano'),
  ('c-robin', 1,     79000000, '2004-05-01', 'Única sobreviviente de Ohara, con ocho años'),
  ('c-robin', 2,     80000000, '2023-10-25', 'Enies Lobby'),
  ('c-robin', 3,    130000000, '2024-09-20', 'Dressrosa'),
  ('c-robin', 4,    930000000, '2025-09-05', 'Derrotó a Black Maria en Onigashima'),
  ('c-franky', 1,    44000000, '2023-10-25', 'Enies Lobby'),
  ('c-franky', 2,    94000000, '2024-09-20', 'Dressrosa'),
  ('c-franky', 3,   394000000, '2025-09-05', 'Wano'),
  ('c-brook', 1,     33000000, '1976-05-01', 'Pirata de Rumbar, hace más de cincuenta años'),
  ('c-brook', 2,     83000000, '2024-09-20', 'Dressrosa'),
  ('c-brook', 3,    383000000, '2025-09-05', 'Wano'),
  ('c-jinbe', 1,    438000000, '2024-02-01', 'Renunció a ser Shichibukai y luchó en Marineford'),
  ('c-jinbe', 2,   1100000000, '2025-09-05', 'Wano'),
  ('c-shanks', 1,  4048900000, '2023-01-15', 'Emperador del Nuevo Mundo'),
  ('c-teach', 1,   2247600000, '2024-11-15', 'Recompensa revelada tras el Reverie'),
  ('c-teach', 2,   3996000000, '2026-10-05', 'Capturó a Pudding y atacó Hachinosu con su flota'),
  ('c-buggy', 1,     15000000, '2023-02-01', 'Saqueos en East Blue'),
  ('c-buggy', 2,   3189000000, '2026-09-15', 'Nombrado Emperador y cara visible de Cross Guild'),
  ('c-mihawk', 1,  3590000000, '2026-09-15', 'Cofundador de Cross Guild'),
  ('c-crocodile', 1, 81000000, '2003-03-01', 'Recompensa previa a su nombramiento como Shichibukai'),
  ('c-crocodile', 2, 1965000000, '2026-09-15', 'Cofundador de Cross Guild'),
  ('c-mr3', 1,       24000000, '2023-05-01', 'Agente de Baroque Works'),
  ('c-law', 1,      200000000, '2023-12-01', 'Supernova en el archipiélago Sabaody'),
  ('c-law', 2,      500000000, '2024-09-20', 'Alianza con Luffy en Dressrosa'),
  ('c-law', 3,     3000000000, '2025-09-05', 'Derrota de Big Mom en Wano'),
  ('c-hancock', 1,   80000000, '2012-01-01', 'Recompensa previa a su nombramiento como Shichibukai'),
  ('c-hancock', 2, 1659000000, '2026-08-10', 'Fin del sistema de Shichibukai'),
  ('c-sabo', 1,     602000000, '2024-11-15', 'Recompensa revelada tras el Reverie'),
  ('c-doflamingo', 1, 340000000, '2009-01-01', 'Recompensa congelada al volverse Shichibukai'),
  ('c-kaido', 1,   4611100000, '2023-01-15', 'Emperador del Nuevo Mundo'),
  ('c-arlong', 1,    20000000, '2015-01-01', 'Dominio de la isla Conomi'),
  ('c-ace', 1,      550000000, '2022-06-01', 'Comandante de la segunda división de Barbablanca'),
  ('c-barbablanca', 1, 5046000000, '2015-01-01', 'Emperador del Nuevo Mundo'),
  ('c-roger', 1,   5564800000, '2001-01-01', 'Conquistó la Grand Line');

-- Clasificación de amenaza con la regla de motor-clasificacion.ts:
--   * sin recompensa -> PENDIENTE;
--   * el rango de los criterios vigentes da el nivel base;
--   * en la Grand Line o cerca del Cuartel General (Sabaody, Marineford,
--     Mary Geoise) un nivel BAJO o MEDIO sube un escalón.
CREATE TEMP TABLE semilla_clasificacion ON COMMIT DROP AS
WITH vigente AS (
  SELECT DISTINCT ON (criminal_id) criminal_id, monto, desde
    FROM semilla_recompensas
   ORDER BY criminal_id, orden DESC
), primera AS (
  SELECT criminal_id, min(desde) AS desde FROM semilla_recompensas GROUP BY criminal_id
), base AS (
  SELECT c.id, v.monto, v.desde AS vigente_desde,
         (m.tipo = 'GRAND_LINE' OR z.nombre ~* '(sabaody|marineford|mary geoise)') AS zona_sensible,
         CASE
           WHEN v.monto IS NULL OR v.monto <= 0 THEN 'PENDIENTE'::nivel_amenaza
           ELSE COALESCE(
             (SELECT ca.nivel FROM criterios_amenaza ca
               WHERE ca.vigente AND ca.nivel <> 'PENDIENTE'
                 AND v.monto >= ca.monto_minimo
                 AND (ca.monto_maximo IS NULL OR v.monto <= ca.monto_maximo)
               ORDER BY ca.monto_minimo LIMIT 1),
             'ALTO')
         END AS nivel_base,
         -- Registro en el sistema: la primera recompensa, o la puesta en marcha
         -- del sistema (10 de enero de 2023) si esa recompensa es anterior.
         greatest(COALESCE(pg_temp.dia(p.desde) - interval '3 days', pg_temp.dia('2023-01-10')),
                  pg_temp.dia('2023-01-10')) AS registrado
    FROM semilla_criminales c
    JOIN zonas_influencia z ON z.id = c.zona
    JOIN mares m ON m.id = z.mar_id
    LEFT JOIN vigente v ON v.criminal_id = c.id
    LEFT JOIN primera p ON p.criminal_id = c.id
)
SELECT id, monto, vigente_desde, nivel_base, registrado,
       (zona_sensible AND nivel_base IN ('BAJO', 'MEDIO')) AS escalado,
       CASE
         WHEN zona_sensible AND nivel_base = 'BAJO'  THEN 'MEDIO'::nivel_amenaza
         WHEN zona_sensible AND nivel_base = 'MEDIO' THEN 'ALTO'::nivel_amenaza
         ELSE nivel_base
       END AS nivel
  FROM base;

INSERT INTO criminales
  (id, nombre, nombre_normalizado, alias, edad, descripcion_fisica, estado, fecha_baja,
   zona_influencia_id, recompensa_vigente_monto, nivel_amenaza, origen_base_id,
   creado_por, actualizado_por, created_at, updated_at)
SELECT c.id, c.nombre,
       -- Igual que normalizarNombre(): minúsculas, sin signos, espacios simples.
       btrim(regexp_replace(regexp_replace(lower(c.nombre), '[^a-z0-9\s]', ' ', 'g'), '\s+', ' ', 'g')),
       c.alias, c.edad, c.descripcion, c.estado, pg_temp.dia(c.baja),
       c.zona, k.monto, k.nivel, c.base_origen,
       'u-analista-datos-criminales', 'u-analista-datos-criminales', k.registrado, k.registrado
  FROM semilla_criminales c
  JOIN semilla_clasificacion k ON k.id = c.id
ON CONFLICT DO NOTHING;

INSERT INTO recompensas
  (id, criminal_id, monto, moneda, estado, requiere_validacion, solicitada_por, fecha_solicitud,
   validada_por, fecha_validacion, vigente_desde, vigente_hasta, motivo, created_at)
SELECT 'rc-' || substr(r.criminal_id, 3) || '-' || r.orden,
       r.criminal_id, r.monto, 'BERRIES',
       CASE WHEN siguiente.desde IS NULL THEN 'VIGENTE' ELSE 'HISTORICA' END::estado_recompensa,
       r.monto >= 1000000000,
       'u-analista-datos-criminales',
       pg_temp.dia(r.desde) - interval '2 days',
       CASE WHEN r.monto >= 1000000000 THEN 'u-almirante' END,
       CASE WHEN r.monto >= 1000000000 THEN pg_temp.dia(r.desde) END,
       pg_temp.dia(r.desde),
       pg_temp.dia(siguiente.desde),
       r.motivo,
       pg_temp.dia(r.desde) - interval '2 days'
  FROM semilla_recompensas r
  LEFT JOIN semilla_recompensas siguiente
    ON siguiente.criminal_id = r.criminal_id AND siguiente.orden = r.orden + 1
ON CONFLICT DO NOTHING;

-- Bandeja del Almirante: una solicitud por firmar y una rechazada.
INSERT INTO recompensas
  (id, criminal_id, monto, estado, requiere_validacion, solicitada_por, fecha_solicitud,
   validada_por, fecha_validacion, motivo, created_at)
VALUES
  ('rc-sabo-pendiente', 'c-sabo', 1200000000, 'PENDIENTE_VALIDACION', true,
   'u-analista-datos-criminales', '2026-11-08 14:00-05', NULL, NULL,
   'Incidente de Mary Geoise: requiere firma del Almirante', '2026-11-08 14:00-05'),
  ('rc-usopp-rechazada', 'c-usopp', 1000000000, 'RECHAZADA', true,
   'u-capitan', '2026-09-15 09:30-05', 'u-almirante', '2026-09-16 11:00-05',
   'Héroe de Dressrosa y Wano según la prensa | Rechazo: ninguna base naval corroboró el informe',
   '2026-09-15 09:30-05')
ON CONFLICT DO NOTHING;

-- La bitácora del criminal muestra cada aumento de su recompensa, como lo
-- habría registrado el trigger al actualizar recompensa_vigente_monto.
INSERT INTO criminales_historial (criminal_id, campo, valor_anterior, valor_nuevo, usuario_id, fecha)
SELECT r.criminal_id, 'recompensa_vigente_monto', anterior.monto::text, r.monto::text,
       CASE WHEN r.monto >= 1000000000 THEN 'u-almirante' ELSE 'u-analista-datos-criminales' END,
       pg_temp.dia(r.desde)
  FROM semilla_recompensas r
  JOIN semilla_clasificacion k ON k.id = r.criminal_id
  LEFT JOIN semilla_recompensas anterior
    ON anterior.criminal_id = r.criminal_id AND anterior.orden = r.orden - 1
 WHERE pg_temp.dia(r.desde) > k.registrado
   AND NOT EXISTS (SELECT 1 FROM criminales_historial h
                    WHERE h.criminal_id = r.criminal_id
                      AND h.campo = 'recompensa_vigente_monto'
                      AND h.fecha = pg_temp.dia(r.desde));

-- Primer análisis de riesgo de cada criminal (mismo texto que el motor).
INSERT INTO analisis_riesgo
  (id, criminal_id, fecha_analisis, monto_evaluado, nivel_base, nivel_resultante, escalado,
   justificacion, ejecutado_por)
SELECT 'ar-' || substr(k.id, 3), k.id,
       greatest(COALESCE(pg_temp.dia(k.vigente_desde), k.registrado), k.registrado),
       k.monto, k.nivel_base, k.nivel, k.escalado,
       CASE
         WHEN k.monto IS NULL THEN 'Sin recompensa vigente: queda pendiente de clasificacion.'
         WHEN k.escalado THEN
           'Bounty de ' || trunc(k.monto)::bigint || ' clasifica como ' || k.nivel_base
           || ', escalado a ' || k.nivel || ' por operar en zona de alta sensibilidad.'
         ELSE 'Bounty de ' || trunc(k.monto)::bigint || ' clasifica como ' || k.nivel_base || '.'
       END,
       'u-analista-datos-criminales'
  FROM semilla_clasificacion k
ON CONFLICT DO NOTHING;

-- =============================================================================
-- 6. Afiliaciones (actuales y pasadas)
-- =============================================================================

CREATE TEMP TABLE semilla_membresias (
  id          text PRIMARY KEY,
  criminal_id text NOT NULL,
  org_id      text NOT NULL,
  rol         rol_membresia NOT NULL,
  ingreso     date NOT NULL,
  salida      date
) ON COMMIT DROP;

INSERT INTO semilla_membresias VALUES
  ('m-luffy',             'c-luffy',       'org-sombrero-paja',  'LIDER',   '2023-01-15', NULL),
  ('m-zoro',              'c-zoro',        'org-sombrero-paja',  'OFICIAL', '2023-01-20', NULL),
  ('m-nami',              'c-nami',        'org-sombrero-paja',  'MIEMBRO', '2023-03-12', NULL),
  ('m-usopp',             'c-usopp',       'org-sombrero-paja',  'MIEMBRO', '2023-04-01', NULL),
  ('m-sanji',             'c-sanji',       'org-sombrero-paja',  'OFICIAL', '2023-04-20', NULL),
  ('m-chopper',           'c-chopper',     'org-sombrero-paja',  'MIEMBRO', '2023-05-10', NULL),
  ('m-robin-baroque',     'c-robin',       'org-baroque',        'OFICIAL', '2019-01-01', '2023-06-20'),
  ('m-robin',             'c-robin',       'org-sombrero-paja',  'MIEMBRO', '2023-06-25', NULL),
  ('m-franky',            'c-franky',      'org-sombrero-paja',  'MIEMBRO', '2023-11-01', NULL),
  ('m-brook',             'c-brook',       'org-sombrero-paja',  'MIEMBRO', '2023-11-20', NULL),
  ('m-jinbe',             'c-jinbe',       'org-sombrero-paja',  'OFICIAL', '2025-03-01', NULL),
  ('m-shanks-roger',      'c-shanks',      'org-roger',          'MIEMBRO', '1995-01-01', '2002-04-01'),
  ('m-shanks',            'c-shanks',      'org-pelirrojo',      'LIDER',   '2003-01-01', NULL),
  ('m-teach-barbablanca', 'c-teach',       'org-barbablanca',    'MIEMBRO', '2003-01-01', '2023-08-01'),
  ('m-teach',             'c-teach',       'org-barbanegra',     'LIDER',   '2023-08-01', NULL),
  ('m-buggy-roger',       'c-buggy',       'org-roger',          'MIEMBRO', '1995-01-01', '2002-04-01'),
  ('m-buggy',             'c-buggy',       'org-buggy',          'LIDER',   '2015-01-01', NULL),
  ('m-buggy-cross',       'c-buggy',       'org-cross-guild',    'LIDER',   '2026-09-15', NULL),
  ('m-mihawk',            'c-mihawk',      'org-cross-guild',    'OFICIAL', '2026-09-15', NULL),
  ('m-crocodile-baroque', 'c-crocodile',   'org-baroque',        'LIDER',   '2019-01-01', '2023-06-20'),
  ('m-crocodile',         'c-crocodile',   'org-cross-guild',    'OFICIAL', '2026-09-15', NULL),
  ('m-mr3-baroque',       'c-mr3',         'org-baroque',        'MIEMBRO', '2019-06-01', '2023-06-20'),
  ('m-mr3',               'c-mr3',         'org-buggy',          'OFICIAL', '2024-02-01', NULL),
  ('m-law',               'c-law',         'org-heart',          'LIDER',   '2018-01-01', NULL),
  ('m-hancock',           'c-hancock',     'org-kuja',           'LIDER',   '2010-01-01', NULL),
  ('m-sabo',              'c-sabo',        'org-revolucionario', 'OFICIAL', '2012-01-01', NULL),
  ('m-dragon',            'c-dragon',      'org-revolucionario', 'LIDER',   '2005-01-01', NULL),
  ('m-doflamingo',        'c-doflamingo',  'org-donquixote',     'LIDER',   '2000-01-01', NULL),
  ('m-kaido',             'c-kaido',       'org-bestias',        'LIDER',   '2000-01-01', NULL),
  ('m-arlong',            'c-arlong',      'org-arlong',         'LIDER',   '2015-01-01', NULL),
  ('m-ace',               'c-ace',         'org-barbablanca',    'OFICIAL', '2021-01-01', NULL),
  ('m-barbablanca',       'c-barbablanca', 'org-barbablanca',    'LIDER',   '1990-01-01', NULL),
  ('m-roger',             'c-roger',       'org-roger',          'LIDER',   '1990-01-01', NULL);

INSERT INTO membresias
  (id, criminal_id, organizacion_id, rol, vigente, fecha_ingreso, creado_por, created_at)
SELECT s.id, s.criminal_id, s.org_id, s.rol, true, pg_temp.dia(s.ingreso),
       'u-analista-datos-criminales', greatest(pg_temp.dia(s.ingreso), c.created_at)
  FROM semilla_membresias s
  JOIN criminales c ON c.id = s.criminal_id
ON CONFLICT DO NOTHING;

-- Las pasadas se cierran después, así el trigger deja la desafiliación en la
-- bitácora igual que cuando la hace la aplicación.
UPDATE membresias m
   SET vigente = false, fecha_salida = pg_temp.dia(s.salida)
  FROM semilla_membresias s
 WHERE m.id = s.id AND s.salida IS NOT NULL AND m.vigente;

-- =============================================================================
-- 7. Antecedentes
-- =============================================================================

INSERT INTO antecedentes
  (id, criminal_id, tipo_delito, descripcion, fecha_hecho, ubicacion, registrado_por, created_at, updated_at)
SELECT a.id, a.criminal_id, a.tipo, a.descripcion, pg_temp.dia(a.fecha), a.ubicacion,
       'u-analista-datos-criminales',
       greatest(pg_temp.dia(a.fecha) + interval '1 day', c.created_at),
       greatest(pg_temp.dia(a.fecha) + interval '1 day', c.created_at)
  FROM (VALUES
    ('a-luffy-1',      'c-luffy',      'Ataque a un Noble Mundial',              'Golpeó a Saint Charlos en Sabaody',                                   DATE '2023-12-05', 'Archipiélago Sabaody'),
    ('a-luffy-2',      'c-luffy',      'Invasión de instalación gubernamental',   'Irrumpió en Impel Down y en Marineford',                              DATE '2024-01-25', 'Marineford'),
    ('a-zoro-1',       'c-zoro',       'Agresión a oficiales de la Marina',       'Hirió a marines de la Base 153 al escapar de Shells Town',           DATE '2023-01-20', 'Shells Town'),
    ('a-robin-1',      'c-robin',      'Investigación prohibida',                 'Lectura de Poneglyphs, prohibida por el Gobierno Mundial',            DATE '2004-05-01', 'Ohara'),
    ('a-teach-1',      'c-teach',      'Homicidio',                               'Asesinó al comandante Thatch para robar una Fruta del Diablo',        DATE '2023-08-01', 'Nuevo Mundo'),
    ('a-teach-2',      'c-teach',      'Liberación de prisioneros',               'Reclutó a presos del nivel 6 de Impel Down',                          DATE '2024-01-22', 'Impel Down'),
    ('a-buggy-1',      'c-buggy',      'Fuga de prisión',                         'Escapó de Impel Down durante la fuga masiva',                         DATE '2024-01-20', 'Impel Down'),
    ('a-crocodile-1',  'c-crocodile',  'Intento de golpe de Estado',              'Planeó derrocar al Reino de Alabasta',                                DATE '2023-06-15', 'Alabasta'),
    ('a-crocodile-2',  'c-crocodile',  'Fuga de prisión',                         'Escapó del nivel 6 de Impel Down',                                    DATE '2024-01-20', 'Impel Down'),
    ('a-law-1',        'c-law',        'Ataque a instalación gubernamental',      'Destruyó el laboratorio de Punk Hazard',                              DATE '2024-05-15', 'Punk Hazard'),
    ('a-doflamingo-1', 'c-doflamingo', 'Tráfico de armas',                        'Red de comercio de frutas artificiales SMILE',                        DATE '2024-08-01', 'Dressrosa'),
    ('a-kaido-1',      'c-kaido',      'Ocupación de un país',                    'Sometió al país de Wano durante veinte años junto a Kurozumi Orochi', DATE '2025-08-30', 'Wano'),
    ('a-arlong-1',     'c-arlong',     'Extorsión',                               'Cobró tributo a las aldeas de la isla Conomi durante ocho años',      DATE '2023-03-12', 'Villa Cocoyasi'),
    ('a-sabo-1',       'c-sabo',       'Ataque a la Tierra Santa',                'Irrumpió en Mary Geoise durante el Reverie',                          DATE '2024-11-10', 'Mary Geoise')
  ) AS a (id, criminal_id, tipo, descripcion, fecha, ubicacion)
  JOIN criminales c ON c.id = a.criminal_id
ON CONFLICT DO NOTHING;

-- =============================================================================
-- 8. Inteligencia: avistamientos y reportes ciudadanos
-- =============================================================================

INSERT INTO avistamientos
  (id, criminal_id, fecha_hora, ubicacion, testigo, zona_influencia_id, estado_verificacion,
   origen, observaciones, registrado_por, verificado_por, created_at)
VALUES
  ('av-1', 'c-luffy',  '2026-10-20 14:30-05', 'Costa este de Wano',      'Patrulla G-5',                    'z-wano',       'VERIFICADO', 'OFICIAL', NULL,                                              'u-director-inteligencia', 'u-director-inteligencia', '2026-10-20 18:00-05'),
  ('av-2', 'c-teach',  '2026-10-28 09:00-05', 'Grove 41, Sabaody',       'Comerciante local',               'z-sabaody',    'PENDIENTE',  'OFICIAL', NULL,                                              'u-capitan',               NULL,                      '2026-10-28 10:15-05'),
  ('av-3', 'c-buggy',  '2026-11-02 18:15-05', 'Puerto de Villa Foosha',  'Alcalde Woop Slap',               'z-foosha',     'VERIFICADO', 'OFICIAL', NULL,                                              'u-capitan',               'u-director-inteligencia', '2026-11-02 19:00-05'),
  ('av-4', 'c-shanks', '2026-10-12 07:45-05', 'Costa de Elbaph',         'Buque explorador de la Base G-5', 'z-elbaph',     'VERIFICADO', 'OFICIAL', 'La flota del Pelirrojo sigue anclada en la isla', 'u-director-inteligencia', 'u-director-inteligencia', '2026-10-12 09:00-05'),
  ('av-5', 'c-mihawk', '2026-11-09 16:20-05', 'Muelle de Karai Bari',    'Informante infiltrado',           'z-karai-bari', 'PENDIENTE',  'OFICIAL', NULL,                                              'u-director-inteligencia', NULL,                      '2026-11-09 17:00-05'),
  ('av-6', 'c-teach',  '2026-09-03 21:10-05', 'Hachinosu',               'Pescador de la zona',             'z-hachinosu',  'DESCARTADO', 'OFICIAL', 'La foto mostraba a un pirata disfrazado',       'u-director-inteligencia', 'u-director-inteligencia', '2026-09-04 08:00-05'),
  ('av-7', 'c-zoro',   '2026-11-05 11:00-05', 'Mercado de Loguetown',    'Vendedor de frutas',              'z-loguetown',  'VERIFICADO', 'REPORTE_CIUDADANO', 'Aprobado desde el reporte rep-1',          'u-director-inteligencia', 'u-director-inteligencia', '2026-11-06 09:00-05')
ON CONFLICT DO NOTHING;

INSERT INTO reportes_ciudadanos
  (id, criminal_id, descripcion, fecha_hecho, ubicacion, zona_influencia_id, informante, estado,
   revisado_por, fecha_revision, motivo_rechazo, avistamiento_id, created_at)
VALUES
  ('rep-1', 'c-zoro', 'Un espadachín de cabello verde preguntó cómo llegar al puerto... tres veces.',
   '2026-11-05 11:00-05', 'Mercado de Loguetown', 'z-loguetown',
   '{"nombre": "Vendedor de frutas", "anonimo": false}', 'APROBADO',
   'u-director-inteligencia', '2026-11-06 09:00-05', NULL, 'av-7', '2026-11-05 12:30-05'),
  ('rep-2', 'c-mr3', 'Vi esculturas de cera sospechosas en la plaza.',
   '2026-11-07 16:00-05', 'Nanohana', 'z-alabasta',
   '{"anonimo": true}', 'PENDIENTE', NULL, NULL, NULL, NULL, '2026-11-07 17:10-05'),
  ('rep-3', 'c-chopper', 'Un mapache con sombrero rosado compró todo el algodón de azúcar de la feria.',
   '2026-11-10 19:00-05', 'Feria de Water 7', 'z-water7',
   '{"nombre": "Dueña del puesto", "anonimo": false}', 'PENDIENTE', NULL, NULL, NULL, NULL, '2026-11-10 20:05-05'),
  ('rep-4', 'c-luffy', 'Vi a Sombrero de Paja comiendo carne en el muelle.',
   '2026-11-01 13:00-05', 'Muelle de Loguetown', 'z-loguetown',
   '{"anonimo": true}', 'RECHAZADO', 'u-director-inteligencia', '2026-11-02 08:30-05',
   'Era un niño disfrazado de Sombrero de Paja', NULL, '2026-11-01 13:40-05')
ON CONFLICT DO NOTHING;

-- =============================================================================
-- 9. Operativos
-- =============================================================================

INSERT INTO operativos
  (id, codigo, nombre, objetivo_criminal_id, objetivo, zona_influencia_id, base_lider_id, estado,
   prioridad, descripcion, fecha_inicio_planeada, fecha_inicio_real, fecha_cierre, resultado_final,
   observaciones_cierre, creado_por, created_at, updated_at)
VALUES
  ('op-dressrosa', 'OP-2024-017', 'Captura de Donquixote Doflamingo', 'c-doflamingo',
   'Detener al Joker y desmantelar la red SMILE', 'z-dressrosa', 'b-g5', 'CERRADO', 'CRITICA',
   'Operativo conjunto con la flota del Almirante Fujitora.',
   '2024-09-01 06:00-05', '2024-09-02 06:00-05', '2024-09-12 20:00-05', 'EXITOSO',
   'Doflamingo trasladado a Impel Down. Los Sombrero de Paja escaparon con la flota de Bartolomeo.',
   'u-coordinador-operaciones', '2024-08-25 10:00-05', '2024-09-12 20:00-05'),
  ('op-cross-guild', 'OP-2026-022', 'Interceptación de Cross Guild', 'c-buggy',
   'Impedir que Cross Guild publique recompensas contra marines', 'z-karai-bari', 'b-g5', 'ABORTADO', 'ALTA',
   'Escuadra de la Base G-5 con apoyo de la Base G-1.',
   '2026-09-20 06:00-05', '2026-09-20 08:00-05', '2026-09-22 15:00-05', NULL,
   'Abortado: la flota de Cross Guild superaba a la escuadra tres a uno.',
   'u-coordinador-operaciones', '2026-09-17 09:00-05', '2026-09-22 15:00-05'),
  ('op-sabaody', 'OP-2026-031', 'Redada en Sabaody', 'c-teach',
   'Capturar a Barbanegra antes de que cruce al Nuevo Mundo', 'z-sabaody', 'b-g1', 'EN_CURSO', 'ALTA',
   'Cerco a los groves 40 a 45 con apoyo del Cuartel General.',
   '2026-10-28 06:00-05', '2026-10-29 05:30-05', NULL, NULL, NULL,
   'u-coordinador-operaciones', '2026-10-27 16:00-05', '2026-10-29 05:30-05'),
  ('op-impel-down', 'OP-2026-034', 'Refuerzo de Impel Down', NULL,
   'Reforzar los niveles 5 y 6 tras los rumores de una nueva fuga', 'z-impel-down', 'b-impel-down',
   'PLANIFICADO', 'ALTA', 'Relevo de guardias y revisión de las compuertas del Calm Belt.',
   '2026-11-20 06:00-05', NULL, NULL, NULL, NULL,
   'u-coordinador-operaciones', '2026-11-10 11:00-05', '2026-11-10 11:00-05'),
  ('op-elbaph', 'OP-2026-036', 'Vigilancia de Elbaph', 'c-shanks',
   'Seguir los movimientos de la flota del Pelirrojo sin entrar en combate', 'z-elbaph', 'b-marineford',
   'PLANIFICADO', 'CRITICA', 'Solo observación: ningún buque entra en aguas de Elbaph.',
   '2026-12-01 06:00-05', NULL, NULL, NULL, NULL,
   'u-coordinador-operaciones', '2026-11-12 15:00-05', '2026-11-12 15:00-05')
ON CONFLICT DO NOTHING;

INSERT INTO operativo_bases
  (id, operativo_id, base_naval_id, rol_participacion, unidades_asignadas, confirmada, recursos, created_at)
VALUES
  ('opb-dressrosa-g5',    'op-dressrosa',   'b-g5',         'LIDER',     12, true,  '4 buques de guerra',                 '2024-08-25 10:00-05'),
  ('opb-dressrosa-id',    'op-dressrosa',   'b-impel-down', 'LOGISTICA',  3, true,  '1 buque de traslado de prisioneros', '2024-08-25 10:00-05'),
  ('opb-cross-g5',        'op-cross-guild', 'b-g5',         'LIDER',      8, true,  '3 buques de guerra',                 '2026-09-17 09:00-05'),
  ('opb-cross-g1',        'op-cross-guild', 'b-g1',         'APOYO',      4, true,  '2 buques',                           '2026-09-17 09:00-05'),
  ('opb-sabaody-g1',      'op-sabaody',     'b-g1',         'LIDER',     10, true,  '3 buques y 2 pelotones',             '2026-10-27 16:00-05'),
  ('opb-sabaody-hq',      'op-sabaody',     'b-marineford', 'APOYO',      6, true,  '2 buques de guerra',                 '2026-10-27 16:00-05'),
  ('opb-sabaody-lt',      'op-sabaody',     'b-loguetown',  'LOGISTICA',  2, false, 'Suministros y Den Den Mushi',        '2026-10-27 16:00-05'),
  ('opb-impel-id',        'op-impel-down',  'b-impel-down', 'LIDER',      5, true,  'Guardias de los niveles 5 y 6',      '2026-11-10 11:00-05'),
  ('opb-impel-16',        'op-impel-down',  'b-16',         'APOYO',      3, false, '1 buque de escolta',                 '2026-11-10 11:00-05'),
  ('opb-elbaph-hq',       'op-elbaph',      'b-marineford', 'LIDER',     20, true,  '5 buques de guerra',                 '2026-11-12 15:00-05')
ON CONFLICT DO NOTHING;

INSERT INTO operativo_responsables (id, operativo_id, usuario_id, funcion, created_at) VALUES
  ('opr-dressrosa', 'op-dressrosa',   'u-coordinador-operaciones', 'COORDINADOR', '2024-08-25 10:00-05'),
  ('opr-cross',     'op-cross-guild', 'u-coordinador-operaciones', 'COORDINADOR', '2026-09-17 09:00-05'),
  ('opr-sabaody-1', 'op-sabaody',     'u-coordinador-operaciones', 'COORDINADOR', '2026-10-27 16:00-05'),
  ('opr-sabaody-2', 'op-sabaody',     'u-capitan',                 'LOGISTICA',   '2026-10-27 16:00-05'),
  ('opr-impel',     'op-impel-down',  'u-coordinador-operaciones', 'COORDINADOR', '2026-11-10 11:00-05'),
  ('opr-elbaph',    'op-elbaph',      'u-coordinador-operaciones', 'COORDINADOR', '2026-11-12 15:00-05')
ON CONFLICT DO NOTHING;

-- =============================================================================
-- 10. Incidentes
-- =============================================================================

INSERT INTO incidentes
  (id, operativo_id, tipo, resultado, fecha_hora, ubicacion, zona_influencia_id, base_naval_id,
   descripcion, bajas_marina, bajas_enemigas, observaciones, participantes_marina, registrado_por,
   created_at, updated_at)
VALUES
  ('inc-arlong', NULL, 'CAPTURA', 'EXITO', '2023-03-12 16:00-05', 'Arlong Park, isla Conomi',
   'z-cocoyasi', 'b-153', 'Arlong fue arrestado tras su derrota frente a Monkey D. Luffy.', 0, 0, NULL,
   '[{"nombre": "Ripper", "rango": "Capitán"}]', 'u-capitan', '2023-03-12 20:00-05', '2023-03-12 20:00-05'),
  ('inc-impel-down', NULL, 'FUGA', 'FRACASO', '2024-01-20 09:00-05', 'Impel Down, nivel 6',
   'z-impel-down', 'b-impel-down', 'Fuga masiva de Impel Down: 241 presos escaparon.', 340, 0,
   'Barbanegra liberó a parte de los presos del nivel 6.',
   '[{"nombre": "Magellan", "rango": "Jefe de Prisión"}, {"nombre": "Hannyabal", "rango": "Subjefe"}]',
   'u-coordinador-operaciones', '2024-01-20 18:00-05', '2024-01-20 18:00-05'),
  ('inc-marineford', NULL, 'ENFRENTAMIENTO', 'PARCIAL', '2024-01-25 15:00-05', 'Bahía de Marineford',
   'z-marineford', 'b-marineford', 'Guerra en Marineford por la ejecución de Portgas D. Ace.', 2310, 1890,
   'Barbablanca y Ace murieron; Sombrero de Paja escapó.',
   '[{"nombre": "Sengoku", "rango": "Almirante de Flota"}, {"nombre": "Sakazuki", "rango": "Almirante"}, {"nombre": "Borsalino", "rango": "Almirante"}, {"nombre": "Kuzan", "rango": "Almirante"}]',
   'u-coordinador-operaciones', '2024-01-26 10:00-05', '2024-01-26 10:00-05'),
  ('inc-dressrosa', 'op-dressrosa', 'CAPTURA', 'EXITO', '2024-09-12 18:00-05', 'Palacio real de Dressrosa',
   'z-dressrosa', 'b-g5', 'Doflamingo fue derrotado por Monkey D. Luffy y arrestado por la flota del Almirante Fujitora.',
   3, 27, NULL,
   '[{"nombre": "Issho", "rango": "Almirante"}, {"nombre": "Bastille", "rango": "Vicealmirante"}]',
   'u-coordinador-operaciones', '2024-09-12 22:00-05', '2024-09-12 22:00-05'),
  ('inc-onigashima', NULL, 'CAPTURA', 'EXITO', '2025-08-30 12:00-05', 'Onigashima, país de Wano',
   'z-wano', 'b-g5', 'Tras su derrota en Onigashima, Kaido quedó bajo custodia de la Marina.', 0, 0, NULL,
   '[{"nombre": "Smoker", "rango": "Vicealmirante"}]', 'u-coordinador-operaciones',
   '2025-08-30 18:00-05', '2025-08-30 18:00-05'),
  ('inc-sabaody', 'op-sabaody', 'AVISTAMIENTO_HOSTIL', 'EN_CURSO', '2026-10-30 22:00-05', 'Grove 41, Sabaody',
   'z-sabaody', 'b-g1', 'Disparos contra una patrulla de la Base G-1; el objetivo huyó hacia el Nuevo Mundo.',
   2, 0, NULL, '[{"nombre": "Momonga", "rango": "Vicealmirante"}]', 'u-capitan',
   '2026-10-30 23:30-05', '2026-10-30 23:30-05')
ON CONFLICT DO NOTHING;

INSERT INTO incidente_participantes (id, incidente_id, criminal_id, rol_en_incidente, desenlace, created_at) VALUES
  ('ip-arlong',           'inc-arlong',      'c-arlong',      'OBJETIVO', 'CAPTURADO',   '2023-03-12 20:00-05'),
  ('ip-impel-luffy',      'inc-impel-down',  'c-luffy',       'OBJETIVO', 'ESCAPO',      '2024-01-20 18:00-05'),
  ('ip-impel-buggy',      'inc-impel-down',  'c-buggy',       'OBJETIVO', 'ESCAPO',      '2024-01-20 18:00-05'),
  ('ip-impel-mr3',        'inc-impel-down',  'c-mr3',         'OBJETIVO', 'ESCAPO',      '2024-01-20 18:00-05'),
  ('ip-impel-crocodile',  'inc-impel-down',  'c-crocodile',   'OBJETIVO', 'ESCAPO',      '2024-01-20 18:00-05'),
  ('ip-impel-jinbe',      'inc-impel-down',  'c-jinbe',       'OBJETIVO', 'ESCAPO',      '2024-01-20 18:00-05'),
  ('ip-impel-teach',      'inc-impel-down',  'c-teach',       'COMPLICE', 'ESCAPO',      '2024-01-20 18:00-05'),
  ('ip-mf-barbablanca',   'inc-marineford',  'c-barbablanca', 'OBJETIVO', 'MUERTO',      '2024-01-26 10:00-05'),
  ('ip-mf-ace',           'inc-marineford',  'c-ace',         'OBJETIVO', 'MUERTO',      '2024-01-26 10:00-05'),
  ('ip-mf-luffy',         'inc-marineford',  'c-luffy',       'COMPLICE', 'ESCAPO',      '2024-01-26 10:00-05'),
  ('ip-mf-jinbe',         'inc-marineford',  'c-jinbe',       'COMPLICE', 'ESCAPO',      '2024-01-26 10:00-05'),
  ('ip-mf-crocodile',     'inc-marineford',  'c-crocodile',   'COMPLICE', 'ESCAPO',      '2024-01-26 10:00-05'),
  ('ip-mf-buggy',         'inc-marineford',  'c-buggy',       'COMPLICE', 'ESCAPO',      '2024-01-26 10:00-05'),
  ('ip-mf-teach',         'inc-marineford',  'c-teach',       'COMPLICE', 'ESCAPO',      '2024-01-26 10:00-05'),
  ('ip-mf-shanks',        'inc-marineford',  'c-shanks',      'TESTIGO',  'ESCAPO',      '2024-01-26 10:00-05'),
  ('ip-dr-doflamingo',    'inc-dressrosa',   'c-doflamingo',  'OBJETIVO', 'CAPTURADO',   '2024-09-12 22:00-05'),
  ('ip-dr-luffy',         'inc-dressrosa',   'c-luffy',       'COMPLICE', 'ESCAPO',      '2024-09-12 22:00-05'),
  ('ip-dr-law',           'inc-dressrosa',   'c-law',         'COMPLICE', 'ESCAPO',      '2024-09-12 22:00-05'),
  ('ip-oni-kaido',        'inc-onigashima',  'c-kaido',       'OBJETIVO', 'CAPTURADO',   '2025-08-30 18:00-05'),
  ('ip-sab-teach',        'inc-sabaody',     'c-teach',       'OBJETIVO', 'DESCONOCIDO', '2026-10-30 23:30-05')
ON CONFLICT DO NOTHING;

-- =============================================================================
-- 11. Notificaciones (mismos textos que politica-notificacion.ts)
-- =============================================================================

INSERT INTO notificaciones
  (id, base_naval_id, tipo, titulo, mensaje, referencia_tipo, referencia_id, leida, created_at)
VALUES
  ('n-sabaody-creado-g1', 'b-g1', 'OPERATIVO_CREADO', 'Operativo OP-2026-031',
   'Nuevo operativo OP-2026-031 con participacion de tu base (prioridad ALTA).',
   'operativo', 'op-sabaody', true, '2026-10-27 16:00-05'),
  ('n-sabaody-creado-lt', 'b-loguetown', 'OPERATIVO_CREADO', 'Operativo OP-2026-031',
   'Nuevo operativo OP-2026-031 con participacion de tu base (prioridad ALTA).',
   'operativo', 'op-sabaody', false, '2026-10-27 16:00-05'),
  ('n-sabaody-estado-g1', 'b-g1', 'OPERATIVO_ESTADO', 'Operativo OP-2026-031',
   'El operativo OP-2026-031 cambio a estado EN_CURSO.',
   'operativo', 'op-sabaody', false, '2026-10-29 05:30-05'),
  ('n-sabaody-estado-hq', 'b-marineford', 'OPERATIVO_ESTADO', 'Operativo OP-2026-031',
   'El operativo OP-2026-031 cambio a estado EN_CURSO.',
   'operativo', 'op-sabaody', false, '2026-10-29 05:30-05'),
  ('n-sabaody-incidente', 'b-g1', 'INCIDENTE_REGISTRADO', 'Nuevo enfrentamiento',
   'Se registro un enfrentamiento con 1 criminal(es).',
   'incidente', 'inc-sabaody', false, '2026-10-30 23:30-05'),
  ('n-impel-creado', 'b-16', 'OPERATIVO_CREADO', 'Operativo OP-2026-034',
   'Nuevo operativo OP-2026-034 con participacion de tu base (prioridad ALTA).',
   'operativo', 'op-impel-down', false, '2026-11-10 11:00-05'),
  ('n-sabo-pendiente', NULL, 'RECOMPENSA_POR_VALIDAR', 'Recompensa pendiente de validacion',
   'Una recompensa de 1200000000 berries requiere la firma del Almirante.',
   'recompensa', 'rc-sabo-pendiente', false, '2026-11-08 14:00-05')
ON CONFLICT DO NOTHING;

-- =============================================================================
-- 12. Reportes mensuales por mar (agosto a octubre de 2026)
-- =============================================================================
-- Misma consulta que SQL_RECOMPENSAS_POR_MAR: recompensa vigente en la fecha de
-- corte (último instante del mes, hora de Colombia) de los criminales ACTIVOS.

WITH periodos AS (
  SELECT p.periodo,
         ((((p.periodo || '-01')::date + interval '1 month')::date)::text || ' 00:00-05')::timestamptz
           - interval '1 millisecond' AS corte
    FROM (VALUES ('2026-08'), ('2026-09'), ('2026-10')) AS p (periodo)
), vigentes AS (
  SELECT DISTINCT ON (p.periodo, r.criminal_id) p.periodo, r.criminal_id, r.monto
    FROM periodos p
    JOIN recompensas r
      ON r.estado IN ('VIGENTE', 'HISTORICA')
     AND r.vigente_desde IS NOT NULL AND r.vigente_desde <= p.corte
     AND (r.vigente_hasta IS NULL OR r.vigente_hasta > p.corte)
   ORDER BY p.periodo, r.criminal_id, r.vigente_desde DESC, r.created_at DESC
)
INSERT INTO reportes_recompensas
  (id, periodo, mar_id, mar_nombre, total_acumulado, cantidad_criminales, generado_por, generado_en)
SELECT 'rr-' || p.periodo || '-' || substr(m.id, 3), p.periodo, m.id, m.nombre,
       COALESCE(sum(v.monto), 0), count(v.criminal_id), 'u-almirante', p.corte
  FROM periodos p
  CROSS JOIN mares m
  LEFT JOIN zonas_influencia z ON z.mar_id = m.id
  LEFT JOIN criminales c ON c.zona_influencia_id = z.id AND c.estado = 'ACTIVO'
  LEFT JOIN vigentes v ON v.periodo = p.periodo AND v.criminal_id = c.id
 WHERE m.activo
 GROUP BY p.periodo, p.corte, m.id, m.nombre
ON CONFLICT (periodo, mar_id) DO UPDATE
  SET mar_nombre = EXCLUDED.mar_nombre, total_acumulado = EXCLUDED.total_acumulado,
      cantidad_criminales = EXCLUDED.cantidad_criminales, generado_en = EXCLUDED.generado_en;

COMMIT;
