import { config as loadEnv } from 'dotenv';
import { DataSource } from 'typeorm';
import { conexionPostgres } from './conexion-postgres';

/**
 * DataSource exclusivo para el CLI de TypeORM (generar y correr migraciones) y
 * el seed. La aplicacion usa TypeOrmModule con database.config.ts; este archivo
 * existe porque el CLI no pasa por el contenedor de NestJS.
 */
loadEnv();

export default new DataSource({
  ...conexionPostgres(),
  synchronize: false,
  entities: ['src/**/*.entity.ts'],
  migrations: ['src/shared/infrastructure/database/migrations/*.ts'],
  migrationsTableName: 'typeorm_migrations',
});
