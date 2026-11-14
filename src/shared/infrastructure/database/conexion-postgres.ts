import { readFileSync } from 'node:fs';
import { types } from 'pg';
import type { PostgresConnectionOptions } from 'typeorm/driver/postgres/PostgresConnectionOptions';

/**
 * Postgres entrega BIGINT (COUNT(*), la columna `version`) y NUMERIC (montos)
 * como texto para no perder precision. Los valores de este dominio caben de
 * sobra en un number, asi que se convierten al leer: es lo que hacia mysql2 con
 * `decimalNumbers` y lo que esperan los repositorios y reportes.
 */
types.setTypeParser(types.builtins.INT8, Number);
types.setTypeParser(types.builtins.NUMERIC, Number);

type OpcionesConexion = Pick<
  PostgresConnectionOptions,
  'type' | 'host' | 'port' | 'username' | 'password' | 'database' | 'ssl' | 'extra'
>;

/**
 * Conexion a PostgreSQL (Supabase o un Postgres local). La comparten la
 * aplicacion (database.config.ts) y el CLI de TypeORM (data-source.ts).
 *
 * En Supabase se usa el Session pooler: la conexion directa solo responde por
 * IPv6. No hace falta fijar zona horaria: las columnas son `timestamptz` y
 * guardan el instante exacto que envia Node.
 */
export function conexionPostgres(env: NodeJS.ProcessEnv = process.env): OpcionesConexion {
  return {
    type: 'postgres',
    host: env.DB_HOST ?? '127.0.0.1',
    port: Number(env.DB_PORT ?? 5432),
    username: env.DB_USER ?? 'postgres',
    password: env.DB_PASSWORD ?? '',
    database: env.DB_NAME ?? 'postgres',
    ssl: opcionesSsl(env),
    extra: {
      max: Number(env.DB_POOL_MAX ?? 10),
      application_name: 'marine-fleet-backend',
    },
  };
}

/**
 * Con DB_SSL=true la conexion va cifrada. Si ademas se indica el certificado de
 * Supabase (Project Settings > Database > SSL Configuration) en DB_SSL_CA, se
 * verifica la identidad del servidor; sin el, se cifra sin verificarla.
 */
function opcionesSsl(env: NodeJS.ProcessEnv): PostgresConnectionOptions['ssl'] {
  if (env.DB_SSL !== 'true') return false;
  if (env.DB_SSL_CA) return { ca: readFileSync(env.DB_SSL_CA, 'utf8') };
  return { rejectUnauthorized: false };
}
