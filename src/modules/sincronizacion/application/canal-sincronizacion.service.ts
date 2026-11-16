import { Inject, Injectable } from '@nestjs/common';
import { Subject, concatMap, filter, from, merge, timer, type Observable } from 'rxjs';
import type { AuthenticatedUser } from '../../../shared/domain/rbac/authenticated-user';
import { esVisiblePara, type CambioSincronizado } from '../domain/cambio-sincronizado';
import { CAMBIOS_REPOSITORY, type CambiosRepositoryPort } from '../domain/sincronizacion.ports';

/** Maximo de cambios que devuelve una consulta (reconexion o polling). */
export const CAPACIDAD_BUFFER = 500;

/** Cada cuanto el canal SSE revisa la tabla por cambios hechos en OTRAS instancias. */
export const INTERVALO_SONDEO_MS = 3_000;

const RETENCION_MS = 7 * 24 * 60 * 60 * 1000;

/**
 * Canal por el que fluyen todos los hechos del sistema hacia las bases
 * conectadas (SSE) y hacia el polling de respaldo.
 *
 * Cumple el RNF "el estado de un operativo se refleja ... maximo 15 segundos
 * para todos los usuarios". Cada cambio:
 *  1. se GUARDA en `cambios_sincronizacion` (fuente de verdad compartida por
 *     todas las instancias del API: en Vercel hay varias y se apagan solas);
 *  2. sale al instante por el Subject a los navegadores conectados a ESTA
 *     instancia;
 *  3. los conectados a otras instancias lo reciben en el siguiente sondeo de la
 *     tabla (cada 3 s), sin duplicados porque se filtra por id.
 */
@Injectable()
export class CanalSincronizacion {
  private readonly flujo = new Subject<CambioSincronizado>();
  private ultimaPurga = 0;

  constructor(@Inject(CAMBIOS_REPOSITORY) private readonly cambios: CambiosRepositoryPort) {}

  async publicar(evento: string, datos: unknown): Promise<CambioSincronizado> {
    const cambio = await this.cambios.registrar(evento, datos);
    this.flujo.next(cambio);
    await this.purgarSiToca();
    return cambio;
  }

  /**
   * Flujo en vivo para un usuario, ya filtrado por lo que puede ver. Empieza
   * despues de `desdeId` y nunca repite un id.
   */
  flujoPara(
    usuario: Pick<AuthenticatedUser, 'permisos' | 'baseNavalId'>,
    desdeId: number,
  ): Observable<CambioSincronizado> {
    let ultimoEnviado = desdeId;
    // timer(0, ...): el primer sondeo es inmediato y entrega lo pendiente.
    const deOtrasInstancias = timer(0, INTERVALO_SONDEO_MS).pipe(
      concatMap(() =>
        from(this.cambios.listar({ despuesDeId: ultimoEnviado, limite: CAPACIDAD_BUFFER })),
      ),
      concatMap((lista) => from(lista)),
    );
    return merge(this.flujo.asObservable(), deOtrasInstancias).pipe(
      filter((cambio) => {
        if (cambio.id <= ultimoEnviado) return false;
        ultimoEnviado = cambio.id;
        return true;
      }),
      filter((cambio) => esVisiblePara(cambio, usuario)),
    );
  }

  /**
   * Cambios posteriores a una fecha o a un consecutivo. Es el polling de
   * respaldo para clientes sin SSE y la reanudacion tras un corte.
   */
  async cambiosDesde(
    usuario: Pick<AuthenticatedUser, 'permisos' | 'baseNavalId'>,
    criterio: { desde?: Date; despuesDeId?: number },
  ): Promise<CambioSincronizado[]> {
    const lista = await this.cambios.listar({ ...criterio, limite: CAPACIDAD_BUFFER });
    return lista.filter((cambio) => esVisiblePara(cambio, usuario));
  }

  ultimoId(): Promise<number> {
    return this.cambios.ultimoId();
  }

  /** Como mucho una vez por hora: borra lo de mas de 7 dias. */
  private async purgarSiToca(): Promise<void> {
    const ahora = Date.now();
    if (ahora - this.ultimaPurga < 60 * 60 * 1000) return;
    this.ultimaPurga = ahora;
    await this.cambios.purgarAntesDe(new Date(ahora - RETENCION_MS));
  }
}
