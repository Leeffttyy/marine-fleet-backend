import { registerAs } from '@nestjs/config';
import type { TypeOrmModuleOptions } from '@nestjs/typeorm';
import { conexionPostgres } from '../shared/infrastructure/database/conexion-postgres';
import { ConcurrenciaOptimistaSubscriber } from '../shared/infrastructure/database/subscribers/concurrencia-optimista.subscriber';

export default registerAs('database', (): TypeOrmModuleOptions => ({
  ...conexionPostgres(),

  // El esquema vive en database/supabase y en migraciones versionadas. NUNCA
  // poner esto en true: TypeORM alteraria el esquema real y borraria los
  // triggers de historial y de recompensas inmutables.
  synchronize: false,

  autoLoadEntities: true,
  subscribers: [ConcurrenciaOptimistaSubscriber],
  migrationsRun: false,
  logging: process.env.NODE_ENV === 'development' ? ['error', 'warn', 'migration'] : ['error'],
}));
