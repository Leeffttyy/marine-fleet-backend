import { envValidationSchema } from '../../../config/env.validation';
import { conexionPostgres } from './conexion-postgres';

const SUPABASE =
  'postgresql://postgres.abcdefghijklmnop:clave@aws-0-us-east-1.pooler.supabase.com:5432/postgres';
const JWT = { JWT_SECRET: 'x'.repeat(32), JWT_REFRESH_SECRET: 'y'.repeat(32) };

describe('conexionPostgres', () => {
  it('con DATABASE_URL de Supabase usa la cadena y activa SSL solo', () => {
    const opciones = conexionPostgres({ DATABASE_URL: SUPABASE });
    expect(opciones.url).toBe(SUPABASE);
    expect(opciones.host).toBeUndefined();
    expect(opciones.ssl).toEqual({ rejectUnauthorized: false });
  });

  it('con un Postgres local usa las DB_* y no cifra', () => {
    const opciones = conexionPostgres({
      DB_HOST: '127.0.0.1',
      DB_USER: 'postgres',
      DB_NAME: 'marina',
    });
    expect(opciones).toMatchObject({
      host: '127.0.0.1',
      port: 5432,
      database: 'marina',
      ssl: false,
    });
  });

  it('DB_SSL manda sobre la deteccion automatica', () => {
    expect(conexionPostgres({ DATABASE_URL: SUPABASE, DB_SSL: 'false' }).ssl).toBe(false);
    expect(conexionPostgres({ DB_HOST: 'mi-servidor', DB_SSL: 'true' }).ssl).toBeTruthy();
  });
});

describe('validacion del .env de la base', () => {
  it('con DATABASE_URL no pide las DB_*', () => {
    expect(envValidationSchema.validate({ ...JWT, DATABASE_URL: SUPABASE }).error).toBeUndefined();
  });

  it('sin DATABASE_URL exige host, usuario, contrasena y base', () => {
    const { error } = envValidationSchema.validate({ ...JWT }, { abortEarly: false });
    const faltan = error?.details.map((d) => d.path[0]);
    expect(faltan).toEqual(
      expect.arrayContaining(['DB_HOST', 'DB_USER', 'DB_PASSWORD', 'DB_NAME']),
    );
  });

  it('rechaza algo que no es una cadena de conexion, como una API key', () => {
    const { error } = envValidationSchema.validate({
      ...JWT,
      DATABASE_URL: 'sb_publishable_abc123',
    });
    expect(error?.message).toContain('DATABASE_URL');
  });
});
