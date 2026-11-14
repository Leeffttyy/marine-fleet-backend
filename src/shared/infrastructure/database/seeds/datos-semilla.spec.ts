import * as bcrypt from 'bcrypt';
import { PERMISOS_POR_ROL } from '../../../domain/rbac/permiso.enum';
import { RolCodigo, ROLES_CON_MFA_OBLIGATORIO } from '../../../domain/rbac/rol.enum';
import { leerScript } from '../scripts-sql';

/**
 * 02_datos.sql escribe la matriz RBAC a mano porque es SQL puro, pensado para
 * el SQL Editor de Supabase. Estas pruebas evitan que se desincronice del
 * codigo, que es quien decide los permisos.
 */
describe('database/supabase/02_datos.sql', () => {
  const sql = leerScript('02_datos.sql');
  const roles = [
    ...sql.matchAll(/\('r-[a-z-]+', '([A-Z_]+)',[\s\S]*?'(\[[^\]]*\])', (true|false)\)/g),
  ].map(([, codigo, permisos, mfa]) => ({
    codigo: codigo as RolCodigo,
    permisos: JSON.parse(permisos) as string[],
    mfa: mfa === 'true',
  }));

  it('siembra los siete roles del sistema', () => {
    expect(roles.map((r) => r.codigo).sort()).toEqual(Object.values(RolCodigo).sort());
  });

  it.each(Object.values(RolCodigo))(
    '%s tiene los permisos y el MFA que define el codigo',
    (codigo) => {
      const rol = roles.find((r) => r.codigo === codigo);
      expect(rol?.permisos.sort()).toEqual([...PERMISOS_POR_ROL[codigo]].sort());
      expect(rol?.mfa).toBe(ROLES_CON_MFA_OBLIGATORIO.includes(codigo));
    },
  );

  it('la contrasena documentada de las cuentas de prueba es Marina.2026', async () => {
    const hashes = new Set(sql.match(/\$2[aby]\$\d{2}\$[./A-Za-z0-9]{53}/g));
    expect(hashes.size).toBe(1);
    await expect(bcrypt.compare('Marina.2026', [...hashes][0])).resolves.toBe(true);
  });
});
