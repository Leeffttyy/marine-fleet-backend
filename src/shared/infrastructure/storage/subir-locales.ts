/* eslint-disable no-console */
import { config as loadEnv } from 'dotenv';
import { readFile, readdir } from 'node:fs/promises';
import { extname, join, relative, resolve } from 'node:path';
import { SupabaseStorageAdapter } from './supabase-storage.adapter';

/**
 * Sube a Supabase Storage las fotos y carteles que quedaron en el disco local
 * (storage/fotos y storage/carteles) antes de configurar las llaves. Conserva
 * las mismas rutas, asi que las URLs guardadas en la base siguen sirviendo.
 * Se puede repetir: sobrescribe lo que ya este en el bucket.
 *
 *   npm run storage:subir
 */
loadEnv();

const MIME: Record<string, string> = {
  '.pdf': 'application/pdf',
  '.svg': 'image/svg+xml',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.webp': 'image/webp',
};

async function archivosDe(carpeta: string): Promise<string[]> {
  const entradas = await readdir(carpeta, { withFileTypes: true }).catch(() => []);
  const anidados = await Promise.all(
    entradas.map((e) =>
      e.isDirectory() ? archivosDe(join(carpeta, e.name)) : [join(carpeta, e.name)],
    ),
  );
  return anidados.flat();
}

async function main(): Promise<void> {
  const { SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, SUPABASE_STORAGE_BUCKET } = process.env;
  if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY) {
    throw new Error('Faltan SUPABASE_URL y SUPABASE_SERVICE_ROLE_KEY en el .env.');
  }
  const storage = new SupabaseStorageAdapter({
    url: SUPABASE_URL,
    clave: SUPABASE_SERVICE_ROLE_KEY,
    bucket: SUPABASE_STORAGE_BUCKET ?? 'marine-fleet',
  });

  const raiz = resolve(
    (process.env.STORAGE_PATH ?? './storage/carteles').replace(/[\\/]carteles[\\/]?$/, ''),
  );
  let subidos = 0;
  for (const carpeta of ['fotos', 'carteles']) {
    for (const archivo of await archivosDe(join(raiz, carpeta))) {
      const mime = MIME[extname(archivo).toLowerCase()];
      if (!mime) continue;
      const ruta = relative(raiz, archivo).replace(/\\/g, '/');
      await storage.guardar(ruta, await readFile(archivo), mime);
      subidos++;
      console.warn(`  ${ruta}`);
    }
  }
  console.warn(`Listo: ${subidos} archivos en Supabase Storage.`);
}

main().catch((error: Error) => {
  console.error('No se pudieron subir los archivos:', error.message);
  process.exit(1);
});
