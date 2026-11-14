import { Column, Entity, PrimaryColumn } from 'typeorm';

export enum TipoMar {
  CUATRO_MARES = 'CUATRO_MARES',
  GRAND_LINE = 'GRAND_LINE',
}

/** Tabla `mares`. Catalogo de solo lectura. */
@Entity('mares')
export class Mar {
  @PrimaryColumn({ type: 'varchar', length: 36 })
  id!: string;

  @Column({ type: 'varchar', length: 100, unique: true })
  nombre!: string;

  @Column({ type: 'enum', enum: TipoMar, enumName: 'tipo_mar' })
  tipo!: TipoMar;

  @Column({ type: 'boolean', default: true })
  activo!: boolean;
}
