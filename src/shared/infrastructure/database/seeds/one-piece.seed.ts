/* eslint-disable no-console */
import dataSource from '../data-source';
import { leerScript } from '../scripts-sql';

/**
 * Siembra el universo de prueba con database/supabase/02_datos.sql, el mismo
 * script que se puede pegar en el SQL Editor de Supabase. Asi los datos viven
 * en un solo lugar.
 *
 * Es IDEMPOTENTE: se puede correr varias veces. Requiere el esquema creado
 * (`npm run migration:run` o 01_esquema.sql).
 */
async function main(): Promise<void> {
  await dataSource.initialize();
  try {
    await dataSource.query(leerScript('02_datos.sql'));
  } finally {
    await dataSource.destroy();
  }
  console.warn('Seed completado. Usuarios: <rol>@marina.gov / Marina.2026.');
  console.warn('Para generar los carteles iniciales: POST /api/v1/carteles/regenerar-todos');
}

main().catch((error) => {
  console.error('Seed fallido:', error);
  process.exit(1);
});
