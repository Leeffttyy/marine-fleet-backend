import type { ConfigService } from '@nestjs/config';
import { envValidationSchema } from '../../../config/env.validation';
import { crearAlmacenamiento } from './crear-almacenamiento';
import { LocalStorageAdapter } from './local-storage.adapter';
import { SupabaseStorageAdapter } from './supabase-storage.adapter';

interface Llamada {
  url: string;
  init: RequestInit;
}

/** fetch falso: responde segun la ruta y guarda cada llamada para revisarla. */
function fetchFalso(respuestas: Record<string, () => Response>): {
  http: typeof fetch;
  llamadas: Llamada[];
} {
  const llamadas: Llamada[] = [];
  const http = (async (url: string, init: RequestInit = {}) => {
    llamadas.push({ url, init });
    const clave = `${init.method ?? 'GET'} ${new URL(url).pathname}`;
    const responder = respuestas[clave];
    return responder
      ? responder()
      : new Response('{"message":"Object not found"}', { status: 400 });
  }) as unknown as typeof fetch;
  return { http, llamadas };
}

const URL_PROYECTO = 'https://abc123.supabase.co';
const SECRETA = 'sb_secret_xxxxxxxxxxxxxxxx';
const opciones = { url: URL_PROYECTO, clave: SECRETA, bucket: 'marine-fleet' };
const ok = (cuerpo = '{}'): Response => new Response(cuerpo, { status: 200 });

describe('SupabaseStorageAdapter', () => {
  it('guarda en el bucket con upsert y devuelve la URL del backend', async () => {
    const { http, llamadas } = fetchFalso({
      'POST /storage/v1/bucket': ok,
      'POST /storage/v1/object/marine-fleet/carteles/c-luffy/v2.pdf': ok,
    });
    const storage = new SupabaseStorageAdapter(opciones, http);

    const archivo = await storage.guardar(
      'carteles/c-luffy/v2.pdf',
      Buffer.from('%PDF'),
      'application/pdf',
    );

    expect(archivo).toEqual({
      ruta: 'carteles/c-luffy/v2.pdf',
      url: '/api/v1/archivos/carteles/c-luffy/v2.pdf',
      mime: 'application/pdf',
      tamanoBytes: 4,
    });
    const subida = llamadas[1].init.headers as Record<string, string>;
    expect(subida).toMatchObject({
      apikey: SECRETA,
      'x-upsert': 'true',
      'Content-Type': 'application/pdf',
    });
    // Una llave sb_secret_ no es JWT: no va como Bearer.
    expect(subida.Authorization).toBeUndefined();
  });

  it('crea el bucket una sola vez y acepta que ya exista', async () => {
    const { http, llamadas } = fetchFalso({
      'POST /storage/v1/bucket': () =>
        new Response(
          '{"statusCode":"409","error":"Duplicate","message":"The resource already exists"}',
          {
            status: 400,
          },
        ),
      'POST /storage/v1/object/marine-fleet/fotos/a.png': ok,
      'POST /storage/v1/object/marine-fleet/fotos/b.png': ok,
    });
    const storage = new SupabaseStorageAdapter(opciones, http);

    await storage.guardar('fotos/a.png', Buffer.from('x'), 'image/png');
    await storage.guardar('fotos/b.png', Buffer.from('y'), 'image/png');

    expect(llamadas.filter((l) => l.url.endsWith('/bucket'))).toHaveLength(1);
  });

  it('lee el contenido y responde si el archivo existe', async () => {
    const { http } = fetchFalso({
      'GET /storage/v1/object/marine-fleet/fotos/c-luffy/1.png': () => ok('PNGDATA'),
      'HEAD /storage/v1/object/marine-fleet/fotos/c-luffy/1.png': () => ok(''),
    });
    const storage = new SupabaseStorageAdapter(opciones, http);

    expect((await storage.leer('fotos/c-luffy/1.png')).toString()).toBe('PNGDATA');
    expect(await storage.existe('fotos/c-luffy/1.png')).toBe(true);
    expect(await storage.existe('fotos/c-luffy/no-esta.png')).toBe(false);
  });

  it('una service_role clasica (JWT) va tambien como Bearer', async () => {
    const jwt = 'eyJhbGciOiJIUzI1NiJ9.eyJyb2xlIjoic2VydmljZV9yb2xlIn0.firma';
    const { http, llamadas } = fetchFalso({
      'HEAD /storage/v1/object/marine-fleet/a.pdf': () => ok(''),
    });
    await new SupabaseStorageAdapter({ ...opciones, clave: jwt }, http).existe('a.pdf');
    expect((llamadas[0].init.headers as Record<string, string>).Authorization).toBe(
      `Bearer ${jwt}`,
    );
  });

  it('rechaza rutas que salen del bucket', async () => {
    const storage = new SupabaseStorageAdapter(opciones, fetchFalso({}).http);
    await expect(storage.leer('../secreto.txt')).rejects.toMatchObject({ codigo: 'RUTA_INVALIDA' });
  });

  it('un error de Supabase no expone la llave', async () => {
    const { http } = fetchFalso({
      'POST /storage/v1/bucket': ok,
      'POST /storage/v1/object/marine-fleet/a.pdf': () => new Response('denegado', { status: 403 }),
    });
    const error = await new SupabaseStorageAdapter(opciones, http)
      .guardar('a.pdf', Buffer.from('x'), 'application/pdf')
      .catch((e: Error) => e);
    expect(String(error)).toContain('403');
    expect(String(error)).not.toContain(SECRETA);
  });
});

describe('crearAlmacenamiento', () => {
  const config = (valores: Record<string, string>): ConfigService =>
    ({ get: (clave: string) => valores[clave] }) as unknown as ConfigService;

  it('usa Supabase Storage cuando estan la URL y la llave', () => {
    const storage = crearAlmacenamiento(
      config({ SUPABASE_URL: URL_PROYECTO, SUPABASE_SERVICE_ROLE_KEY: SECRETA }),
    );
    expect(storage).toBeInstanceOf(SupabaseStorageAdapter);
  });

  it('sin ellas, o con la llave vacia, guarda en el disco local', () => {
    expect(crearAlmacenamiento(config({}))).toBeInstanceOf(LocalStorageAdapter);
    expect(
      crearAlmacenamiento(config({ SUPABASE_URL: URL_PROYECTO, SUPABASE_SERVICE_ROLE_KEY: '' })),
    ).toBeInstanceOf(LocalStorageAdapter);
  });
});

describe('validacion de las llaves de Supabase', () => {
  const base = {
    DATABASE_URL:
      'postgresql://postgres.abc:clave@aws-1-us-west-2.pooler.supabase.com:5432/postgres',
    JWT_SECRET: 'x'.repeat(32),
    JWT_REFRESH_SECRET: 'y'.repeat(32),
  };

  it('acepta la URL con la llave secreta', () => {
    const { error } = envValidationSchema.validate({
      ...base,
      SUPABASE_URL: URL_PROYECTO,
      SUPABASE_SERVICE_ROLE_KEY: SECRETA,
    });
    expect(error).toBeUndefined();
  });

  it('rechaza la llave publishable o la anon', () => {
    const anon = 'eyJhbGciOiJIUzI1NiJ9.eyJyb2xlIjoiYW5vbiJ9.firma';
    for (const clave of ['sb_publishable_abc', anon]) {
      const { error } = envValidationSchema.validate({
        ...base,
        SUPABASE_URL: URL_PROYECTO,
        SUPABASE_SERVICE_ROLE_KEY: clave,
      });
      expect(error?.message).toContain('llave secreta');
    }
  });

  it('deja la llave vacia mientras se consigue (se usa el disco local)', () => {
    const { error } = envValidationSchema.validate({
      ...base,
      SUPABASE_URL: URL_PROYECTO,
      SUPABASE_SERVICE_ROLE_KEY: '',
    });
    expect(error).toBeUndefined();
  });
});
