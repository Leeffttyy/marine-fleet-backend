# ADR 0003 — PostgreSQL en Supabase en lugar de MySQL

- **Estado:** Aceptada
- **Fecha:** 2026-11-14
- **Decide:** Lead Tecnico + Analista de Datos Criminales
- **Reemplaza en parte:** el contexto de MySQL de la ADR 0002 (TypeORM se mantiene)

## Contexto

La base corria en MySQL/MariaDB local (XAMPP). Cada integrante tenia su propia copia y la
demo dependia del equipo de quien la presentara. El equipo decidio moverla a Supabase, que
ofrece PostgreSQL administrado y gratuito, con un panel para consultar los datos.

## Decision

Usamos **PostgreSQL en Supabase** con el driver `pg`. TypeORM sigue siendo el ORM y
`synchronize` sigue en `false`.

- El esquema vive en `database/supabase/01_esquema.sql`. La migracion
  `1731300000000-EsquemaPostgres` lo ejecuta, o solo se registra si el esquema ya se creo
  desde el SQL Editor de Supabase. Las migraciones de MySQL quedan en el historial de git.
- Los datos de prueba viven en `database/supabase/02_datos.sql`. `npm run seed` corre ese
  mismo archivo, asi que hay una sola fuente de datos.
- La conexion usa el **Session pooler** de Supabase con SSL (`DB_SSL=true`); la directa solo
  responde por IPv6.

## Consecuencias

### Positivas

- Una sola base compartida para el equipo y la demo, sin instalar nada.
- Postgres valida mas en la base: tipos enumerados, `CHECK`, indices unicos parciales (una
  sola recompensa `VIGENTE` por criminal) y triggers en PL/pgSQL que hacen inmutables las
  recompensas y la auditoria.
- Row Level Security activo en todas las tablas: la API publica de Supabase no expone datos.

### Negativas

- Las consultas SQL escritas a mano se reescribieron: parametros `$1` en lugar de `?`,
  alias en camelCase entre comillas, `ILIKE` en lugar de la collation `_ci`,
  `ON CONFLICT` en lugar de `ON DUPLICATE KEY` y codigos de error SQLSTATE (`23505`,
  `23503`) en el filtro de excepciones.
- MySQL comparaba texto sin distinguir mayusculas; Postgres no. Se replico donde importa:
  indices unicos sobre `lower(...)` para correos y nombres, y busquedas con `ILIKE`.
- `01_esquema.sql` es la linea base y no se vuelve a editar: los cambios al esquema van en
  migraciones nuevas.
- La demo necesita internet para llegar a Supabase. Un PostgreSQL local sigue funcionando
  con los mismos scripts.
