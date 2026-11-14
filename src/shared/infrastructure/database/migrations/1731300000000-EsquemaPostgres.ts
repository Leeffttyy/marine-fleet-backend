import type { MigrationInterface, QueryRunner } from 'typeorm';
import { leerScript } from '../scripts-sql';

/**
 * LINEA BASE EN POSTGRESQL. Reemplaza a las migraciones de MySQL (InitSchema,
 * CreateOperativos, CreateIncidentes, AmpliarModelo, AjustesRevision), que
 * siguen en el historial de git.
 *
 * Corre database/supabase/01_esquema.sql, el mismo script que se pega en el SQL
 * Editor de Supabase. Si el esquema ya se creo asi, no hace nada y solo queda
 * registrada: `npm run migration:run` funciona en ambos casos.
 *
 * 01_esquema.sql no se vuelve a editar. Los cambios al esquema van en
 * migraciones nuevas (`npm run migration:create --name=...`).
 */
export class EsquemaPostgres1731300000000 implements MigrationInterface {
  name = 'EsquemaPostgres1731300000000';

  public async up(queryRunner: QueryRunner): Promise<void> {
    const [fila] = (await queryRunner.query(
      `SELECT to_regclass('public.criminales') IS NOT NULL AS existe`,
    )) as Array<{ existe: boolean }>;
    if (fila?.existe) return;

    await queryRunner.query(leerScript('01_esquema.sql', { sinTransaccion: true }));
  }

  public async down(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(leerScript('00_reiniciar.sql', { sinTransaccion: true }));
  }
}
