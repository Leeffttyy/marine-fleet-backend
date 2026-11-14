import { Column, CreateDateColumn, Entity, PrimaryColumn, UpdateDateColumn } from 'typeorm';
import type { Permiso } from '../../../shared/domain/rbac/permiso.enum';
import { RolCodigo } from '../../../shared/domain/rbac/rol.enum';

/**
 * RF-7. Tabla `roles`: la matriz de permisos se persiste en la columna JSON.
 *
 * No extiende BaseEntity a proposito: `roles` no tiene columna `version` en el
 * esquema, y mapearla hace fallar cualquier consulta que cargue el rol.
 */
@Entity('roles')
export class Rol {
  @PrimaryColumn({ type: 'varchar', length: 36 })
  id!: string;

  @Column({ type: 'varchar', length: 50, unique: true })
  codigo!: RolCodigo;

  @Column({ type: 'varchar', length: 100 })
  nombre!: string;

  @Column({ type: 'text', nullable: true })
  descripcion!: string | null;

  @Column({ type: 'jsonb' })
  permisos!: Permiso[];

  @Column({ name: 'requiere_2fa', type: 'boolean', default: false })
  requiere2fa!: boolean;

  @Column({ type: 'boolean', default: true })
  activo!: boolean;

  @CreateDateColumn({ name: 'created_at', type: 'timestamptz' })
  createdAt!: Date;

  @UpdateDateColumn({ name: 'updated_at', type: 'timestamptz' })
  updatedAt!: Date;
}
