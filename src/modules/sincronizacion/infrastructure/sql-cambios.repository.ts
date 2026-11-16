import { Injectable } from '@nestjs/common';
import { InjectDataSource } from '@nestjs/typeorm';
import type { DataSource } from 'typeorm';
import type { CambioSincronizado } from '../domain/cambio-sincronizado';
import type { CambiosRepositoryPort } from '../domain/sincronizacion.ports';

interface FilaCambio {
  id: number | string;
  evento: string;
  datos: unknown;
  fecha: Date | string;
}

const aCambio = (fila: FilaCambio): CambioSincronizado => ({
  id: Number(fila.id),
  evento: fila.evento,
  datos: fila.datos,
  fecha: new Date(fila.fecha).toISOString(),
});

/** Tabla `cambios_sincronizacion`. Consultas parametrizadas ($1, $2...). */
@Injectable()
export class SqlCambiosRepository implements CambiosRepositoryPort {
  constructor(@InjectDataSource() private readonly dataSource: DataSource) {}

  async registrar(evento: string, datos: unknown): Promise<CambioSincronizado> {
    const [fila] = (await this.dataSource.query(
      `INSERT INTO cambios_sincronizacion (evento, datos) VALUES ($1, $2::jsonb)
       RETURNING id, evento, datos, fecha`,
      [evento, JSON.stringify(datos ?? null)],
    )) as FilaCambio[];
    return aCambio(fila);
  }

  async listar(criterio: {
    despuesDeId?: number;
    desde?: Date;
    limite: number;
  }): Promise<CambioSincronizado[]> {
    const filas = (await this.dataSource.query(
      `SELECT id, evento, datos, fecha FROM cambios_sincronizacion
        WHERE ($1::bigint IS NULL OR id > $1::bigint)
          AND ($2::timestamptz IS NULL OR fecha > $2::timestamptz)
        ORDER BY id ASC
        LIMIT $3`,
      [criterio.despuesDeId ?? null, criterio.desde ?? null, criterio.limite],
    )) as FilaCambio[];
    return filas.map(aCambio);
  }

  async ultimoId(): Promise<number> {
    const [fila] = (await this.dataSource.query(
      `SELECT COALESCE(MAX(id), 0) AS id FROM cambios_sincronizacion`,
    )) as Array<{ id: number | string }>;
    return Number(fila?.id ?? 0);
  }

  async purgarAntesDe(fecha: Date): Promise<void> {
    await this.dataSource.query(`DELETE FROM cambios_sincronizacion WHERE fecha < $1`, [fecha]);
  }
}
