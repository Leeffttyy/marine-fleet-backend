import * as Joi from 'joi';

/**
 * Valida el .env al arrancar. Sin esto, una variable mal puesta se manifiesta
 * como un error oscuro de conexion a mitad de una peticion en lugar de como un
 * fallo claro en el arranque.
 */
export const envValidationSchema = Joi.object({
  NODE_ENV: Joi.string().valid('development', 'test', 'production').default('development'),
  PORT: Joi.number().port().default(3000),

  // Con DATABASE_URL (la cadena de conexion de Supabase) las DB_* sobran.
  DATABASE_URL: Joi.string()
    .pattern(/^postgres(ql)?:\/\/.+@.+/, 'cadena de conexion de PostgreSQL')
    .optional(),
  DB_HOST: Joi.string()
    .hostname()
    .when('DATABASE_URL', { is: Joi.exist(), then: Joi.optional(), otherwise: Joi.required() }),
  DB_PORT: Joi.number().port().default(5432),
  DB_USER: Joi.string().when('DATABASE_URL', {
    is: Joi.exist(),
    then: Joi.optional(),
    otherwise: Joi.required(),
  }),
  DB_PASSWORD: Joi.string()
    .allow('')
    .when('DATABASE_URL', { is: Joi.exist(), then: Joi.optional(), otherwise: Joi.required() }),
  DB_NAME: Joi.string().when('DATABASE_URL', {
    is: Joi.exist(),
    then: Joi.optional(),
    otherwise: Joi.required(),
  }),
  // Sin valor por defecto: si falta, el SSL se activa solo contra Supabase.
  DB_SSL: Joi.boolean().optional(),
  DB_SSL_CA: Joi.string().optional(),
  DB_POOL_MAX: Joi.number().min(1).max(50).default(10),

  JWT_SECRET: Joi.string().min(32).required(),
  JWT_EXPIRES_IN: Joi.string().default('15m'),
  JWT_REFRESH_SECRET: Joi.string().min(32).required(),
  JWT_REFRESH_EXPIRES_IN: Joi.string().default('7d'),
  BCRYPT_ROUNDS: Joi.number().min(10).max(14).default(10),
  MAX_INTENTOS_FALLIDOS: Joi.number().min(3).default(5),

  FRONTEND_URL: Joi.string().uri().default('http://localhost:5173'),
  STORAGE_PATH: Joi.string().default('./storage/carteles'),
});
