import { Global, Module } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { NOMBRES_LOOKUP } from './domain/lookup/nombres.port';
import { AppLogger } from './infrastructure/logging/logger.service';
import { SqlNombresLookup } from './infrastructure/lookup/sql-nombres.lookup';
import { crearAlmacenamiento } from './infrastructure/storage/crear-almacenamiento';
import { STORAGE_PORT } from './infrastructure/storage/storage.port';

/**
 * Infraestructura transversal disponible para todos los modulos sin que cada
 * uno tenga que importarla: evita diez cambios cuando se sustituye un adaptador.
 */
@Global()
@Module({
  providers: [
    AppLogger,
    // Supabase Storage si el .env trae sus llaves; si no, disco local.
    { provide: STORAGE_PORT, inject: [ConfigService], useFactory: crearAlmacenamiento },
    { provide: NOMBRES_LOOKUP, useClass: SqlNombresLookup },
  ],
  exports: [AppLogger, STORAGE_PORT, NOMBRES_LOOKUP],
})
export class SharedModule {}
