import { readFileSync } from 'node:fs';
import { join } from 'node:path';

/**
 * Carpeta database/supabase de la raiz del repo. Desde src/ (ts-node) y desde
 * dist/ (build) queda a la misma distancia: cuatro niveles arriba.
 */
const CARPETA = join(__dirname, '..', '..', '..', '..', 'database', 'supabase');

/**
 * Lee un script de database/supabase. Con `sinTransaccion` quita el BEGIN y el
 * COMMIT propios del script, para correrlo dentro de la transaccion de una
 * migracion de TypeORM.
 */
export function leerScript(nombre: string, { sinTransaccion = false } = {}): string {
  const sql = readFileSync(join(CARPETA, nombre), 'utf8');
  return sinTransaccion ? sql.replace(/^\s*(BEGIN|COMMIT);\s*$/gim, '') : sql;
}
