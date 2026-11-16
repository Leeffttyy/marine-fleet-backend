import { ConfigService } from '@nestjs/config';
import { NestFactory } from '@nestjs/core';
import type { NestExpressApplication } from '@nestjs/platform-express';
import { AppModule } from './app.module';
import { configurarApp } from './bootstrap/configurar-app';

/** Servidor HTTP de larga duracion (desarrollo local, Railway, VPS). */
async function bootstrap(): Promise<void> {
  const app = await NestFactory.create<NestExpressApplication>(AppModule, { bufferLogs: true });
  configurarApp(app);
  const port = app.get(ConfigService).get<number>('app.port') ?? 3000;
  await app.listen(port);
}

void bootstrap();
