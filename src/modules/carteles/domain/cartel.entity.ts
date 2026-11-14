import { Column, CreateDateColumn, Entity, PrimaryColumn } from 'typeorm';

/** Por que se (re)genero el cartel. Columna `carteles.motivo_generacion`. */
export enum MotivoGeneracion {
  REGISTRO = 'REGISTRO',
  CAMBIO_FOTO = 'CAMBIO_FOTO',
  CAMBIO_RECOMPENSA = 'CAMBIO_RECOMPENSA',
  CAMBIO_ESTADO = 'CAMBIO_ESTADO',
  CAMBIO_AFILIACION = 'CAMBIO_AFILIACION',
  CAMBIO_DATOS = 'CAMBIO_DATOS',
  MANUAL = 'MANUAL',
}

/**
 * RF-2. Tabla `carteles`.
 *
 * `datos_instantanea` guarda una FOTO del criminal en el momento de generar el
 * cartel: un cartel impreso no cambia porque la recompensa suba despues. Esa
 * columna es la razon de que el cartel sea versionado y no una vista.
 */
@Entity('carteles')
export class Cartel {
  @PrimaryColumn({ type: 'varchar', length: 36 })
  id!: string;

  @Column({ name: 'criminal_id', type: 'varchar', length: 36 })
  criminalId!: string;

  @Column({ name: 'numero_version', type: 'int' })
  numeroVersion!: number;

  @Column({ type: 'boolean', default: true })
  vigente!: boolean;

  @Column({ type: 'jsonb' })
  archivo!: { url: string; mime: string; tamano_bytes: number };

  @Column({ name: 'datos_instantanea', type: 'jsonb' })
  datosInstantanea!: Record<string, unknown>;

  @Column({
    name: 'motivo_generacion',
    type: 'enum',
    enum: MotivoGeneracion,
    enumName: 'motivo_cartel',
  })
  motivoGeneracion!: MotivoGeneracion;

  @Column({ name: 'generado_por', type: 'varchar', length: 36, nullable: true })
  generadoPor!: string | null;

  @CreateDateColumn({ name: 'generado_en', type: 'timestamptz' })
  generadoEn!: Date;
}
