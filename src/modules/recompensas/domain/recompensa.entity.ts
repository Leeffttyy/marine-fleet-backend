import { Column, CreateDateColumn, Entity, PrimaryColumn } from 'typeorm';
import { DomainError } from '../../../shared/domain/errors/domain.error';
import { EstadoRecompensa } from './estado-recompensa.enum';

/**
 * RF-1/RF-5. Tabla `recompensas`. Es un registro historico inmutable: una
 * recompensa no se edita, se sustituye y la anterior pasa a HISTORICA. Por eso
 * no extiende BaseEntity (no tiene `version` ni `updated_at` en el esquema).
 */
@Entity('recompensas')
export class Recompensa {
  @PrimaryColumn({ type: 'varchar', length: 36 })
  id!: string;

  @Column({ name: 'criminal_id', type: 'varchar', length: 36 })
  criminalId!: string;

  @Column({
    type: 'decimal',
    precision: 15,
    scale: 2,
    transformer: {
      to: (value: number) => value,
      from: (value: string) => Number(value),
    },
  })
  monto!: number;

  @Column({ type: 'varchar', length: 20, default: 'BERRIES' })
  moneda!: string;

  @Column({
    type: 'enum',
    enum: EstadoRecompensa,
    enumName: 'estado_recompensa',
    default: EstadoRecompensa.PENDIENTE_VALIDACION,
  })
  estado!: EstadoRecompensa;

  @Column({ name: 'requiere_validacion', type: 'boolean', default: false })
  requiereValidacion!: boolean;

  @Column({ name: 'solicitada_por', type: 'varchar', length: 36, nullable: true })
  solicitadaPor!: string | null;

  @CreateDateColumn({ name: 'fecha_solicitud', type: 'timestamptz' })
  fechaSolicitud!: Date;

  @Column({ name: 'validada_por', type: 'varchar', length: 36, nullable: true })
  validadaPor!: string | null;

  @Column({ name: 'fecha_validacion', type: 'timestamptz', nullable: true })
  fechaValidacion!: Date | null;

  @Column({ name: 'vigente_desde', type: 'timestamptz', nullable: true })
  vigenteDesde!: Date | null;

  @Column({ name: 'vigente_hasta', type: 'timestamptz', nullable: true })
  vigenteHasta!: Date | null;

  @Column({ type: 'text', nullable: true })
  motivo!: string | null;

  @CreateDateColumn({ name: 'created_at', type: 'timestamptz' })
  createdAt!: Date;

  // --- Comportamiento de dominio ---

  /** Pasa a VIGENTE. Si requeria validacion, deja la firma de quien la aprobo. */
  activar(validadaPor: string | null, ahora: Date = new Date()): void {
    if (this.estado !== EstadoRecompensa.PENDIENTE_VALIDACION) {
      throw new DomainError(
        `Solo una recompensa pendiente puede activarse (estado actual: ${this.estado}).`,
        'RECOMPENSA_NO_PENDIENTE',
      );
    }
    this.estado = EstadoRecompensa.VIGENTE;
    this.vigenteDesde = ahora;
    if (validadaPor) {
      this.validadaPor = validadaPor;
      this.fechaValidacion = ahora;
    }
  }

  rechazar(validadaPor: string, motivo: string, ahora: Date = new Date()): void {
    if (this.estado !== EstadoRecompensa.PENDIENTE_VALIDACION) {
      throw new DomainError(
        `Solo una recompensa pendiente puede rechazarse (estado actual: ${this.estado}).`,
        'RECOMPENSA_NO_PENDIENTE',
      );
    }
    this.estado = EstadoRecompensa.RECHAZADA;
    this.validadaPor = validadaPor;
    this.fechaValidacion = ahora;
    this.motivo = this.motivo ? `${this.motivo} | Rechazo: ${motivo}` : `Rechazo: ${motivo}`;
  }

  /** La vigente anterior se conserva como HISTORICA: nunca se borra ni se edita el monto. */
  pasarAHistorica(ahora: Date = new Date()): void {
    this.estado = EstadoRecompensa.HISTORICA;
    this.vigenteHasta = ahora;
  }
}
