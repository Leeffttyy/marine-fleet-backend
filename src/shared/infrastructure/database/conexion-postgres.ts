import { readFileSync } from 'node:fs';
import { types } from 'pg';
import type { PostgresConnectionOptions } from 'typeorm/driver/postgres/PostgresConnectionOptions';

/**
 * Postgres entrega BIGINT (COUNT(*), la columna `version`) y NUMERIC (montos)
 * como texto para no perder precision. Los valores de este dominio caben de
 * sobra en un number, asi que se convierten al leer: es lo que esperan los
 * repositorios y los reportes.
 */
types.setTypeParser(types.builtins.INT8, Number);
types.setTypeParser(types.builtins.NUMERIC, Number);

type OpcionesConexion = Pick<
  PostgresConnectionOptions,
  'type' | 'url' | 'host' | 'port' | 'username' | 'password' | 'database' | 'ssl' | 'extra'
>;

/**
 * Conexion a PostgreSQL (Supabase o un Postgres local). La comparten la
 * aplicacion (database.config.ts) y el CLI de TypeORM (data-source.ts).
 *
 * Con Supabase basta DATABASE_URL: la cadena de conexion que da el boton
 * Connect (Session pooler), con la contrasena de la base. Sin ella se usan las
 * variables DB_HOST, DB_PORT, DB_USER, DB_PASSWORD y DB_NAME.
 *
 * No hace falta fijar zona horaria: las columnas son `timestamptz` y guardan
 * el instante exacto que envia Node.
 */
export function conexionPostgres(env: NodeJS.ProcessEnv = process.env): OpcionesConexion {
  const comunes = {
    type: 'postgres' as const,
    ssl: opcionesSsl(env),
    extra: {
      max: Number(env.DB_POOL_MAX ?? 10),
      application_name: 'marine-fleet-backend',
    },
  };

  if (env.DATABASE_URL) return { ...comunes, url: env.DATABASE_URL };

  return {
    ...comunes,
    host: env.DB_HOST ?? '127.0.0.1',
    port: Number(env.DB_PORT ?? 5432),
    username: env.DB_USER ?? 'postgres',
    password: env.DB_PASSWORD ?? '',
    database: env.DB_NAME ?? 'postgres',
  };
}

/**
 * Supabase exige conexion cifrada, asi que contra un host de Supabase el SSL
 * se activa solo; DB_SSL=true|false lo fuerza en cualquier caso. Con el
 * certificado de Supabase (Database Settings > SSL Configuration) en DB_SSL_CA
 * se verifica ademas la identidad del servidor; sin el, se cifra sin verificarla.
 */
function opcionesSsl(env: NodeJS.ProcessEnv): PostgresConnectionOptions['ssl'] {
  const destino = env.DATABASE_URL ?? env.DB_HOST ?? '';
  const usarSsl = env.DB_SSL ? env.DB_SSL === 'true' : /supabase\.(com|co)\b/.test(destino);
  if (!usarSsl) return false;
  if (env.DB_SSL_CA) return { ca: readFileSync(env.DB_SSL_CA, 'utf8') };
  return { rejectUnauthorized: false };
}
