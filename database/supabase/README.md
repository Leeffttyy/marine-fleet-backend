# Base de datos en Supabase (PostgreSQL)

Scripts para crear la base del Caso 13 en Supabase. El backend los usa tal cual:
`npm run migration:run` corre `01_esquema.sql` y `npm run seed` corre
`02_datos.sql`.

| Archivo            | Qué hace                                                  |
| ------------------ | --------------------------------------------------------- |
| `00_reiniciar.sql` | Borra todo lo que crea el esquema. Solo para desarrollo.  |
| `01_esquema.sql`   | Tipos, 24 tablas, índices, triggers y Row Level Security. |
| `02_datos.sql`     | Datos de prueba del universo One Piece. Se puede repetir. |

Probados en PostgreSQL 17: esquema, datos, segunda carga sin duplicados,
reinicio y las reglas de la base (recompensas inmutables, una sola vigente,
auditoría de solo inserción). Cada script es una transacción: si algo falla,
no queda nada a medias.

## Cómo cargarlos

Lo más simple es desde el backend, con el `.env` apuntando a Supabase:

```bash
npm run migration:run
```

```bash
npm run seed
```

También puedes hacerlo desde el panel de Supabase: **SQL Editor → New query**,
pega `01_esquema.sql` y pulsa **Run**; después haz lo mismo con `02_datos.sql`.
Si luego corres `npm run migration:run`, solo registra la migración: no vuelve a
crear nada.

Para empezar de cero, corre `00_reiniciar.sql` y luego los otros dos.

`01_esquema.sql` es la línea base y no se vuelve a editar. Los cambios al
esquema van en migraciones nuevas (`npm run migration:create --name=...`).

## Qué datos quedan

| Tabla                | Filas | Contenido                                                   |
| -------------------- | ----: | ----------------------------------------------------------- |
| mares                |     5 | Los Cuatro Mares y la Grand Line                            |
| zonas_influencia     |    19 | Wano, Elbaph, Karai Bari, Impel Down, Sabaody...            |
| bases_navales        |     8 | Una inactiva (G-8) para probar los catálogos inactivos      |
| roles / usuarios     | 7 / 7 | Un usuario por rol                                          |
| organizaciones       |    14 | Cinco disueltas (Baroque Works, Barbablanca...)             |
| criminales           |    26 | 20 activos, 3 capturados y 3 muertos                        |
| recompensas          |    59 | 32 históricas, 25 vigentes, 1 pendiente y 1 rechazada       |
| membresias           |    33 | Seis pasadas (Robin en Baroque Works, Teach en Barbablanca) |
| antecedentes         |    14 |                                                             |
| avistamientos        |     7 | Verificados, pendientes y uno descartado                    |
| reportes_ciudadanos  |     4 | Pendientes, uno aprobado y uno rechazado                    |
| operativos           |     5 | Dos planificados, uno en curso, uno cerrado y uno abortado  |
| incidentes           |     6 | Marineford, fuga de Impel Down, captura de Doflamingo...    |
| analisis_riesgo      |    26 | Primera clasificación de cada criminal                      |
| reportes_recompensas |    15 | Agosto, septiembre y octubre de 2026 por mar                |

Las cuentas son `<rol>@marina.gov` (por ejemplo `almirante@marina.gov`) con la
contraseña `Marina.2026`. La lista completa está en `docs/EJECUCION.md`.

Los carteles no se siembran porque necesitan sus archivos. Se generan con
`POST /api/v1/carteles/regenerar-todos` una vez que el backend esté conectado.

## Historial de recompensas

Sí se maneja, y la base lo protege:

- Cada recompensa es una fila de `recompensas`. Un aumento no edita la anterior:
  crea una nueva y la anterior pasa a `HISTORICA` con su `vigente_hasta`.
- Estados: `PENDIENTE_VALIDACION → VIGENTE | RECHAZADA` y `VIGENTE → HISTORICA`.
  Un trigger rechaza cualquier otra transición, cambiar el monto o borrar.
- Un índice único garantiza una sola recompensa `VIGENTE` por criminal.
- Cada cambio de estado y de monto vigente queda en `criminales_historial`, con
  el usuario que lo hizo.
- El reporte mensual por mar usa `vigente_desde` y `vigente_hasta` para saber
  cuánto valía cada criminal en una fecha pasada.
- La API lo expone en `GET /api/v1/recompensas/criminal/:criminalId`.

## Conectar el backend

En el proyecto de Supabase pulsa **Connect** (arriba), pestaña **Connection
String**, método **Session pooler**, y copia la cadena al `.env` del backend,
cambiando `[YOUR-PASSWORD]` por la contraseña de la base:

```dotenv
DATABASE_URL=postgresql://postgres.<id-del-proyecto>:<contraseña>@aws-0-<region>.pooler.supabase.com:5432/postgres
```

Eso es todo: contra Supabase la conexión se cifra sola. Usa el Session pooler y
no la conexión directa, que solo funciona por IPv6. La contraseña va
únicamente en el `.env`, que nunca se commitea.

Las **API keys** (`anon`, `service_role`) no conectan el backend: sirven para la
API REST de Supabase. Con Row Level Security activo, además, no pueden leer
ninguna tabla.

Para verificar también la identidad del servidor, descarga el certificado en
**Database Settings → SSL Configuration** y pon su ruta en `DB_SSL_CA`.

Las razones del cambio y su costo están en
`docs/adr/0003-postgresql-en-supabase.md`.
