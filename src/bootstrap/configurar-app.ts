import { ValidationPipe, VersioningType } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { Reflector } from '@nestjs/core';
import type { NestExpressApplication } from '@nestjs/platform-express';
import { DocumentBuilder, SwaggerModule } from '@nestjs/swagger';
import compression from 'compression';
import helmet from 'helmet';
import { AllExceptionsFilter } from '../common/filters/all-exceptions.filter';
import { AuditInterceptor } from '../common/interceptors/audit.interceptor';
import { LoggingInterceptor } from '../common/interceptors/logging.interceptor';
import { NombresInterceptor } from '../common/interceptors/nombres.interceptor';
import { TransformResponseInterceptor } from '../common/interceptors/transform-response.interceptor';
import { NOMBRES_LOOKUP, type NombresLookupPort } from '../shared/domain/lookup/nombres.port';
import {
  AUDITORIA_WRITER,
  type AuditoriaWriterPort,
} from '../shared/domain/auditoria/auditoria.port';

/**
 * Configuracion comun de la aplicacion: prefijo, versionado, seguridad, CORS,
 * validacion, filtros, interceptores y Swagger.
 *
 * La usan los DOS puntos de entrada, asi se comportan exactamente igual:
 *  - main.ts: servidor normal (`npm run start:dev`, Railway, un VPS...).
 *  - serverless.ts: la funcion de Vercel.
 */
export function configurarApp(app: NestExpressApplication): void {
  const config = app.get(ConfigService);
  const reflector = app.get(Reflector);

  // La foto del criminal viaja en base64 (hasta 2 MB de imagen = ~2.8 MB de texto).
  // El limite por defecto de Express (100 KB) la rechazaba con un 413.
  app.useBodyParser('json', { limit: '4mb' });

  app.use(helmet());
  app.use(compression());
  app.setGlobalPrefix('api');
  app.enableVersioning({ type: VersioningType.URI, defaultVersion: '1' });

  // FRONTEND_URL admite varias URLs separadas por coma (ej. la de produccion
  // y la de las vistas previas de Vercel).
  app.enableCors({
    origin: (config.get<string>('app.frontendUrl') ?? 'http://localhost:5173')
      .split(',')
      .map((url) => url.trim())
      .filter(Boolean),
    credentials: true,
    methods: ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS'],
  });

  // whitelist + forbidNonWhitelisted: una propiedad no declarada en el DTO es
  // un error, no algo que se ignora en silencio.
  app.useGlobalPipes(
    new ValidationPipe({
      whitelist: true,
      forbidNonWhitelisted: true,
      transform: true,
      transformOptions: { enableImplicitConversion: false },
    }),
  );

  app.useGlobalFilters(new AllExceptionsFilter());
  app.useGlobalInterceptors(
    new LoggingInterceptor(),
    new AuditInterceptor(reflector, app.get<AuditoriaWriterPort>(AUDITORIA_WRITER)),
    new TransformResponseInterceptor(),
    // El mas interno: completa nombres antes de que la respuesta se envuelva.
    new NombresInterceptor(reflector, app.get<NombresLookupPort>(NOMBRES_LOOKUP)),
  );

  // Swagger: siempre en desarrollo; en produccion solo con SWAGGER_HABILITADO=true.
  if (!config.get<boolean>('app.isProduction') || process.env.SWAGGER_HABILITADO === 'true') {
    const swaggerConfig = new DocumentBuilder()
      .setTitle('Marine Fleet API')
      .setDescription(
        'Sistema de Gestion de Recompensas y Captura de Criminales de la Marina. ' +
          'Este contrato OpenAPI es la fuente de verdad para el frontend.',
      )
      .setVersion('1.0')
      .addBearerAuth()
      .addTag('auth', 'RF-7 Autenticacion y RBAC')
      .addTag('criminales', 'RF-1 Registro y gestion de criminales')
      .addTag('carteles', 'RF-2 Generacion automatica de carteles')
      .addTag('inteligencia', 'RF-3 Avistamientos y reportes')
      .addTag('operativos', 'RF-4 Coordinacion entre bases navales')
      .addTag('amenaza', 'RF-5 Clasificacion de riesgo')
      .addTag('incidentes', 'RF-6 Historial de enfrentamientos')
      .build();

    const document = SwaggerModule.createDocument(app, swaggerConfig);
    SwaggerModule.setup('api/docs', app, document, {
      swaggerOptions: { persistAuthorization: true },
    });
  }
}
