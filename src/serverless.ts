import { NestFactory } from '@nestjs/core';
import type { NestExpressApplication } from '@nestjs/platform-express';
import type { IncomingMessage, ServerResponse } from 'node:http';
import { AppModule } from './app.module';
import { configurarApp } from './bootstrap/configurar-app';

type Manejador = (req: IncomingMessage, res: ServerResponse) => void;

/**
 * Punto de entrada para Vercel (funcion serverless).
 *
 * Vercel llama a esta funcion en cada peticion. Arrancar NestJS cuesta unos
 * segundos, asi que la app se crea UNA vez por instancia y se reutiliza
 * mientras la instancia siga viva: el "arranque en frio" es solo la primera vez.
 * No se llama a listen(): Vercel entrega la peticion y Express la atiende.
 */
let manejador: Promise<Manejador> | null = null;

async function crearManejador(): Promise<Manejador> {
  const app = await NestFactory.create<NestExpressApplication>(AppModule, { bufferLogs: true });
  configurarApp(app);
  await app.init();
  return app.getHttpAdapter().getInstance() as Manejador;
}

export default async function handler(req: IncomingMessage, res: ServerResponse): Promise<void> {
  manejador ??= crearManejador().catch((error: unknown) => {
    // Si el arranque falla (p. ej. falta una variable de entorno), se reintenta
    // en la siguiente peticion en lugar de dejar la instancia rota.
    manejador = null;
    throw error;
  });
  (await manejador)(req, res);
}
