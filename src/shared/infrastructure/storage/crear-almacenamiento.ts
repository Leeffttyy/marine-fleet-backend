import { Logger } from '@nestjs/common';
import type { ConfigService } from '@nestjs/config';
import type { StoragePort } from '../../domain/storage/storage.port';
import { LocalStorageAdapter } from './local-storage.adapter';
import { SupabaseStorageAdapter } from './supabase-storage.adapter';

const logger = new Logger('Almacenamiento');

/**
 * Con SUPABASE_URL y SUPABASE_SERVICE_ROLE_KEY los archivos van al bucket de
 * Supabase Storage (compartido por todo el equipo); sin ellas, al disco local.
 */
export function crearAlmacenamiento(config: ConfigService): StoragePort {
  const url = config.get<string>('SUPABASE_URL');
  const clave = config.get<string>('SUPABASE_SERVICE_ROLE_KEY');
  if (url && clave) {
    const bucket = config.get<string>('SUPABASE_STORAGE_BUCKET') ?? 'marine-fleet';
    logger.log(`Fotos y carteles en Supabase Storage (bucket ${bucket}).`);
    return new SupabaseStorageAdapter({ url, clave, bucket });
  }
  if (url || clave) {
    logger.warn(
      'Falta SUPABASE_URL o SUPABASE_SERVICE_ROLE_KEY: fotos y carteles se guardan en el ' +
        'disco local y el resto del equipo no los vera.',
    );
  }
  return new LocalStorageAdapter(config);
}
