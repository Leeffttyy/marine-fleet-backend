import { posix } from 'node:path';
import { DomainError } from '../../domain/errors/domain.error';
import type { ArchivoGuardado, StoragePort } from '../../domain/storage/storage.port';

export interface OpcionesSupabaseStorage {
  /** URL del proyecto, por ejemplo https://<id>.supabase.co */
  readonly url: string;
  /** Llave secreta (service_role o sb_secret_...). Nunca sale del backend. */
  readonly clave: string;
  readonly bucket: string;
}

const TIEMPO_MAXIMO_MS = 20_000;

/**
 * Almacenamiento en Supabase Storage: fotos y carteles quedan en un bucket
 * privado del proyecto y los ve todo el equipo, no solo quien los genero.
 *
 * Las URLs que devuelve siguen siendo `/api/v1/archivos/<ruta>`: el navegador
 * los pide al backend, que los lee del bucket con la llave secreta. Por eso el
 * bucket es privado y la llave nunca llega al frontend.
 *
 * Usa la API REST de Storage con fetch: no hace falta el SDK de Supabase.
 */
export class SupabaseStorageAdapter implements StoragePort {
  private readonly api: string;
  private bucketListo: Promise<void> | null = null;

  constructor(
    private readonly opciones: OpcionesSupabaseStorage,
    private readonly http: typeof fetch = fetch,
  ) {
    this.api = `${opciones.url.replace(/\/+$/, '')}/storage/v1`;
  }

  async guardar(ruta: string, contenido: Buffer, mime: string): Promise<ArchivoGuardado> {
    const relativa = rutaSegura(ruta);
    await this.asegurarBucket();
    const respuesta = await this.pedir(`/object/${this.opciones.bucket}/${codificar(relativa)}`, {
      method: 'POST',
      headers: { 'Content-Type': mime, 'x-upsert': 'true', 'Cache-Control': 'max-age=3600' },
      body: new Uint8Array(contenido),
    });
    await this.exigirOk(respuesta, `guardar ${relativa}`);
    return {
      ruta: relativa,
      url: `/api/v1/archivos/${relativa}`,
      mime,
      tamanoBytes: contenido.length,
    };
  }

  async leer(ruta: string): Promise<Buffer> {
    const relativa = rutaSegura(ruta);
    const respuesta = await this.pedir(`/object/${this.opciones.bucket}/${codificar(relativa)}`);
    await this.exigirOk(respuesta, `leer ${relativa}`);
    return Buffer.from(await respuesta.arrayBuffer());
  }

  async existe(ruta: string): Promise<boolean> {
    const relativa = rutaSegura(ruta);
    const respuesta = await this.pedir(`/object/${this.opciones.bucket}/${codificar(relativa)}`, {
      method: 'HEAD',
    });
    return respuesta.ok;
  }

  /** Crea el bucket privado la primera vez; si ya existe, sigue. */
  private asegurarBucket(): Promise<void> {
    this.bucketListo ??= (async (): Promise<void> => {
      const { bucket } = this.opciones;
      const respuesta = await this.pedir('/bucket', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ id: bucket, name: bucket, public: false }),
      });
      if (respuesta.ok) return;
      const texto = await respuesta.text();
      if (/already exists|duplicate/i.test(texto)) return;
      throw new Error(`Supabase Storage no pudo crear el bucket ${bucket} (${respuesta.status}).`);
    })().catch((error: unknown) => {
      this.bucketListo = null;
      throw error;
    });
    return this.bucketListo;
  }

  /**
   * Las llaves nuevas (sb_secret_...) van solo en `apikey`: no son JWT y el
   * gateway de Supabase arma el token. La service_role clasica (un JWT) va
   * tambien como Bearer.
   */
  private pedir(ruta: string, init: RequestInit = {}): Promise<Response> {
    const { clave } = this.opciones;
    return this.http(`${this.api}${ruta}`, {
      ...init,
      headers: {
        apikey: clave,
        ...(clave.startsWith('eyJ') ? { Authorization: `Bearer ${clave}` } : {}),
        ...(init.headers as Record<string, string> | undefined),
      },
      signal: AbortSignal.timeout(TIEMPO_MAXIMO_MS),
    });
  }

  /** El mensaje de error nunca incluye la llave, solo la operacion y el estado. */
  private async exigirOk(respuesta: Response, operacion: string): Promise<void> {
    if (respuesta.ok) return;
    const detalle = (await respuesta.text().catch(() => '')).slice(0, 200);
    throw new Error(`Supabase Storage no pudo ${operacion} (${respuesta.status}): ${detalle}`);
  }
}

/** Ruta relativa dentro del bucket. Rechaza `..` y rutas absolutas (path traversal). */
function rutaSegura(ruta: string): string {
  const relativa = posix.normalize(ruta.replace(/\\/g, '/')).replace(/^\/+/, '');
  if (relativa === '.' || relativa === '..' || relativa.startsWith('../')) {
    throw new DomainError('Ruta de archivo no valida.', 'RUTA_INVALIDA');
  }
  return relativa;
}

const codificar = (ruta: string): string => ruta.split('/').map(encodeURIComponent).join('/');
