import type { MigrationInterface, QueryRunner } from 'typeorm';

/**
 * Canal de sincronizacion persistente.
 *
 * Antes los cambios vivian en la memoria de UNA instancia del API. En Vercel hay
 * varias instancias que ademas se apagan solas, asi que un cambio hecho en una
 * no llegaba a quien estaba conectado a otra. Ahora cada cambio se guarda aqui
 * y todas las instancias lo leen de la misma tabla.
 *
 * Se conservan solo los ultimos 7 dias (los borra el propio canal).
 */
export class CambiosSincronizacion1731400000000 implements MigrationInterface {
  name = 'CambiosSincronizacion1731400000000';

  public async up(qr: QueryRunner): Promise<void> {
    await qr.query(`
      CREATE TABLE IF NOT EXISTS cambios_sincronizacion (
        id BIGSERIAL PRIMARY KEY,
        evento VARCHAR(60) NOT NULL,
        datos JSONB,
        fecha TIMESTAMPTZ NOT NULL DEFAULT now()
      )`);
    await qr.query(
      `CREATE INDEX IF NOT EXISTS ix_cambios_sincronizacion_fecha ON cambios_sincronizacion (fecha)`,
    );
    await qr.query(`COMMENT ON TABLE cambios_sincronizacion IS
      'Hechos del sistema para SSE y polling entre bases. Retencion: 7 dias.'`);
    // Igual que el resto del esquema: sin politicas, la API REST publica de
    // Supabase no puede leerla; el backend entra como propietario.
    await qr.query(`ALTER TABLE cambios_sincronizacion ENABLE ROW LEVEL SECURITY`);
  }

  public async down(qr: QueryRunner): Promise<void> {
    await qr.query(`DROP TABLE IF EXISTS cambios_sincronizacion`);
  }
}
