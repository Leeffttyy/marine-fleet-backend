import {
  ArgumentsHost,
  Catch,
  ExceptionFilter,
  HttpException,
  HttpStatus,
  Logger,
} from '@nestjs/common';
import type { Request, Response } from 'express';
import { QueryFailedError } from 'typeorm';
import { ConcurrencyError } from '../../shared/domain/errors/concurrency.error';
import { DomainError } from '../../shared/domain/errors/domain.error';
import { ForbiddenError } from '../../shared/domain/errors/forbidden.error';
import { NotFoundError } from '../../shared/domain/errors/not-found.error';
import { UnauthorizedError } from '../../shared/domain/errors/unauthorized.error';

/**
 * Traduce excepciones a HTTP en un solo lugar: los casos de uso lanzan errores
 * de dominio y no conocen codigos HTTP.
 *
 * Regla de seguridad: un error inesperado nunca filtra su mensaje al cliente.
 */
@Catch()
export class AllExceptionsFilter implements ExceptionFilter {
  private readonly logger = new Logger('ExceptionFilter');

  catch(exception: unknown, host: ArgumentsHost): void {
    const ctx = host.switchToHttp();
    const response = ctx.getResponse<Response>();
    const request = ctx.getRequest<Request>();

    const { status, message, codigo } = this.traducir(exception);

    if (status >= HttpStatus.INTERNAL_SERVER_ERROR) {
      this.logger.error(
        `${request.method} ${request.originalUrl} -> ${status}`,
        exception instanceof Error ? exception.stack : String(exception),
      );
    }

    response.status(status).json({
      success: false,
      error: { codigo, message, status },
      path: request.originalUrl.replace(/([?&]token=)[^&]*/i, '$1***'),
      timestamp: new Date().toISOString(),
    });
  }

  private traducir(exception: unknown): { status: number; message: string; codigo: string } {
    if (exception instanceof DomainError) {
      return {
        status: this.estadoDeDominio(exception),
        message: exception.message,
        codigo: exception.codigo,
      };
    }

    if (exception instanceof HttpException) {
      const respuesta = exception.getResponse();
      const message =
        typeof respuesta === 'string'
          ? respuesta
          : ((respuesta as { message?: string | string[] }).message ?? exception.message);
      return {
        status: exception.getStatus(),
        message: Array.isArray(message) ? message.join('; ') : message,
        codigo: 'HTTP',
      };
    }

    if (exception instanceof QueryFailedError) {
      const deLaBase = this.errorDePostgres(exception);
      if (deLaBase) return deLaBase;
    }

    const deExpress = this.errorDeExpress(exception);
    if (deExpress) return deExpress;

    return {
      status: HttpStatus.INTERNAL_SERVER_ERROR,
      message: 'Error interno del servidor.',
      codigo: 'INTERNO',
    };
  }

  /**
   * Restricciones de la base, por su codigo SQLSTATE de Postgres. Las reglas
   * que protegen registros criticos (recompensas inmutables, auditoria de solo
   * insercion) las lanzan triggers propios con un mensaje pensado para el
   * usuario; cualquier otro error de la base no muestra su mensaje.
   */
  private errorDePostgres(
    exception: QueryFailedError,
  ): { status: number; message: string; codigo: string } | null {
    const driverError = exception.driverError as { code?: string; message?: string } | undefined;
    switch (driverError?.code) {
      case '23505':
        return {
          status: HttpStatus.CONFLICT,
          message: 'El registro ya existe.',
          codigo: 'DUPLICADO',
        };
      case '23503':
        return {
          status: HttpStatus.BAD_REQUEST,
          message: 'Una referencia enviada no existe.',
          codigo: 'FK_INVALIDA',
        };
      case '23514':
        return {
          status: HttpStatus.BAD_REQUEST,
          message: 'Los datos no cumplen una regla de la base de datos.',
          codigo: 'RESTRICCION_INCUMPLIDA',
        };
      case '23000':
        return {
          status: HttpStatus.CONFLICT,
          message: driverError.message ?? 'El registro esta protegido contra cambios.',
          codigo: 'REGISTRO_PROTEGIDO',
        };
      default:
        return null;
    }
  }

  /**
   * Errores de middlewares de Express (body-parser: 413 cuerpo muy grande, 400
   * JSON mal formado) traen su propio status: se respetan en vez de un 500.
   */
  private errorDeExpress(
    exception: unknown,
  ): { status: number; message: string; codigo: string } | null {
    const conStatus = exception as { status?: unknown; statusCode?: unknown } | null;
    const status = Number(conStatus?.statusCode ?? conStatus?.status);
    if (!(status >= 400 && status < 500)) return null;
    const grande = status === HttpStatus.PAYLOAD_TOO_LARGE;
    return {
      status,
      message: grande
        ? 'El cuerpo de la peticion es demasiado grande.'
        : 'La peticion no tiene un formato valido.',
      codigo: grande ? 'CUERPO_DEMASIADO_GRANDE' : 'PETICION_INVALIDA',
    };
  }

  /**
   * Estado HTTP de cada error de dominio. Los especificos van primero: todos
   * heredan de DomainError, que es el caso general (400).
   */
  private estadoDeDominio(error: DomainError): number {
    const porTipo: ReadonlyArray<[new (...args: never[]) => DomainError, number]> = [
      [NotFoundError, HttpStatus.NOT_FOUND],
      [UnauthorizedError, HttpStatus.UNAUTHORIZED],
      [ForbiddenError, HttpStatus.FORBIDDEN],
      [ConcurrencyError, HttpStatus.CONFLICT],
    ];

    return porTipo.find(([tipo]) => error instanceof tipo)?.[1] ?? HttpStatus.BAD_REQUEST;
  }
}
