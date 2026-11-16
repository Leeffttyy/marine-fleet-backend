import { ForbiddenError } from '../../../shared/domain/errors/forbidden.error';
import { Permiso, tienePermiso } from '../../../shared/domain/rbac/permiso.enum';
import { Controller, Get, Inject, Query, Sse, type MessageEvent } from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiTags } from '@nestjs/swagger';
import { from, interval, map, merge, of, switchMap, takeUntil, timer, type Observable } from 'rxjs';
import { CurrentUser } from '../../../common/decorators/current-user.decorator';
import { Public } from '../../../common/decorators/public.decorator';
import type { AuthenticatedUser } from '../../../shared/domain/rbac/authenticated-user';
import { CanalSincronizacion } from '../application/canal-sincronizacion.service';
import type { CambioSincronizado } from '../domain/cambio-sincronizado';
import { VERIFICADOR_SESION, type VerificadorSesionPort } from '../domain/sincronizacion.ports';
import { CambiosQueryDto, StreamQueryDto } from './dto/sincronizacion.dto';

export const INTERVALO_LATIDO_MS = 15_000;
/**
 * Cuanto dura abierto un canal SSE. Por defecto, la vida del access token (15
 * min). En Vercel se baja con SSE_DURACION_MAXIMA_SEGUNDOS para cerrar antes de
 * que la plataforma corte la funcion; el cliente reconecta solo.
 */
export function duracionMaximaMs(env: NodeJS.ProcessEnv = process.env): number {
  const segundos = Number(env.SSE_DURACION_MAXIMA_SEGUNDOS);
  return Number.isFinite(segundos) && segundos > 0 ? segundos * 1000 : 15 * 60_000;
}

const aMensaje = (cambio: CambioSincronizado): MessageEvent => ({
  id: String(cambio.id),
  type: cambio.evento,
  data: cambio,
});

/**
 * Sincronizacion entre bases navales en tiempo real.
 *
 *  - GET /sincronizacion/stream: Server-Sent Events. El navegador abre
 *    `new EventSource('/api/v1/sincronizacion/stream?token=...')` y recibe cada
 *    hecho del sistema en cuanto ocurre (operativos, avistamientos, criminales,
 *    enfrentamientos...). Cumple el RNF de <= 15 s con margen: la latencia real
 *    es de milisegundos.
 *  - GET /sincronizacion/cambios: polling de respaldo para clientes sin SSE.
 */
@ApiTags('sincronizacion')
@Controller({ path: 'sincronizacion', version: '1' })
export class SincronizacionController {
  constructor(
    private readonly canal: CanalSincronizacion,
    @Inject(VERIFICADOR_SESION) private readonly verificador: VerificadorSesionPort,
  ) {}

  /**
   * @Public() justificado: el guard global lee el header Authorization, que
   * EventSource no puede enviar. El token se verifica aqui, ANTES de abrir el
   * canal: un token invalido recibe 401 y no un stream vacio.
   */
  @Public()
  @Sse('stream')
  @ApiOperation({ summary: 'Canal SSE de cambios en tiempo real (token por query string)' })
  stream(@Query() query: StreamQueryDto): Observable<MessageEvent> {
    const usuario = this.verificador.verificar(query.token);
    // Los eventos llevan datos de criminales: solo roles con lectura de criminales.
    if (!tienePermiso(usuario.permisos, Permiso.CRIMINALES_LEER)) {
      throw new ForbiddenError('recibir el canal de sincronizacion');
    }

    const latido = interval(INTERVALO_LATIDO_MS).pipe(
      map((): MessageEvent => ({
        type: 'latido',
        data: { evento: 'latido', fecha: new Date().toISOString() },
      })),
    );

    // Sin ultimoId se empieza desde el ultimo cambio existente (solo lo nuevo);
    // con ultimoId se reenvia lo que el cliente se perdio durante el corte.
    const desdeId$ =
      query.ultimoId !== undefined ? of(query.ultimoId) : from(this.canal.ultimoId());

    // El token solo se valida al abrir: el canal se cierra al cumplir la
    // duracion maxima (en Vercel, antes del limite de la funcion). EventSource
    // reconecta solo con su ultimoId y, si el token vencio, recibe 401.
    return merge(
      desdeId$
        .pipe(switchMap((desdeId) => this.canal.flujoPara(usuario, desdeId)))
        .pipe(map(aMensaje)),
      latido,
    ).pipe(takeUntil(timer(duracionMaximaMs())));
  }

  @Get('cambios')
  @ApiBearerAuth()
  @ApiOperation({ summary: 'Cambios recientes (polling de respaldo, ultimos 500)' })
  async cambios(
    @Query() query: CambiosQueryDto,
    @CurrentUser() usuario: AuthenticatedUser,
  ): Promise<{ ultimoId: number; cambios: CambioSincronizado[] }> {
    const [ultimoId, cambios] = await Promise.all([
      this.canal.ultimoId(),
      this.canal.cambiosDesde(usuario, {
        desde: query.desde ? new Date(query.desde) : undefined,
        despuesDeId: query.despuesDeId,
      }),
    ]);
    return { ultimoId, cambios };
  }
}
