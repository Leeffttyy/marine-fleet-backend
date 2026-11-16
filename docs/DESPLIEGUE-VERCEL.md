# Despliegue en Vercel + Supabase

Tres piezas: **Supabase** (base de datos PostgreSQL + archivos), **backend** en Vercel y
**frontend** en Vercel. Son dos proyectos de Vercel, uno por repositorio. Orden: Supabase →
backend → frontend → volver al backend para ajustar CORS.

## 1. Supabase (base y archivos)

Si la base ya está creada en Supabase, salta al paso 1.3.

1.1. En [supabase.com](https://supabase.com) crea el proyecto y guarda la **contraseña de la base**.

1.2. En tu PC, con el `.env` apuntando a Supabase (ver `.env.example`), corre:

```bash
npm run migration:run   # esquema + tabla cambios_sincronizacion
npm run seed            # datos de prueba
```

1.3. Anota tres valores. Los vas a pegar en Vercel:

| Valor                       | Dónde está en Supabase                                                                                   |
| --------------------------- | -------------------------------------------------------------------------------------------------------- |
| Cadena de conexión          | Botón **Connect** → **Transaction pooler** (puerto **6543**). Cambia `[YOUR-PASSWORD]` por la contraseña |
| `SUPABASE_URL`              | Project Settings → Data API → Project URL                                                                |
| `SUPABASE_SERVICE_ROLE_KEY` | Project Settings → API Keys → la **secret** / `service_role` (nunca la anon)                             |

> **Por qué Transaction pooler (6543) y no Session (5432):** en Vercel cada petición puede caer en
> una instancia distinta y cada una abre conexiones. El modo transacción las comparte y no agota
> el límite del plan gratuito.

> **Si ya habían corrido las migraciones antes de este cambio:** corre `npm run migration:run`
> otra vez. Solo crea la tabla nueva `cambios_sincronizacion`.

## 2. Backend en Vercel

2.1. En [vercel.com](https://vercel.com): **Add New → Project →** importa `marine-fleet-backend`.

2.2. **Framework Preset: Other.** Lo demás lo toma de `vercel.json`: build `npm run build`, la
función `api/index.js` y la redirección de `/api/*`.

2.3. **Environment Variables** (pégalas antes de dar Deploy):

| Variable                                    | Valor                                                                                      |
| ------------------------------------------- | ------------------------------------------------------------------------------------------ |
| `NODE_ENV`                                  | `production`                                                                               |
| `DATABASE_URL`                              | La cadena del Transaction pooler (paso 1.3)                                                |
| `DB_POOL_MAX`                               | `2`                                                                                        |
| `JWT_SECRET`                                | Texto aleatorio de 32 o más caracteres                                                     |
| `JWT_REFRESH_SECRET`                        | **Otro** texto aleatorio de 32 o más caracteres                                            |
| `JWT_EXPIRES_IN` / `JWT_REFRESH_EXPIRES_IN` | `15m` / `7d`                                                                               |
| `SUPABASE_URL`                              | Paso 1.3                                                                                   |
| `SUPABASE_SERVICE_ROLE_KEY`                 | Paso 1.3 (**obligatoria en Vercel**: sin ella intenta guardar en disco y falla)            |
| `FRONTEND_URL`                              | `http://localhost:5173` por ahora; en el paso 4 pones la URL real                          |
| `SSE_DURACION_MAXIMA_SEGUNDOS`              | `50` (cierra el canal en vivo antes del límite de la función; el navegador reconecta solo) |
| `SWAGGER_HABILITADO`                        | `true` si quieren Swagger en línea para la sustentación                                    |

Para generar los secretos JWT: `node -e "console.log(require('crypto').randomBytes(48).toString('hex'))"`.

2.4. **Deploy.** Prueba `https://<tu-backend>.vercel.app/api/v1/salud`: debe responder
`"estado":"OK"` con `baseDeDatos.disponible: true`.

## 3. Frontend en Vercel

3.1. **Add New → Project →** importa `marine-fleet-frontend`. Vercel detecta **Vite**.

3.2. Variable de entorno:

| Variable       | Valor                                                          |
| -------------- | -------------------------------------------------------------- |
| `VITE_API_URL` | `https://<tu-backend>.vercel.app` (sin `/api` ni `/` al final) |

3.3. **Deploy.** El `vercel.json` del frontend hace que al recargar en cualquier ruta
(`/criminales`, `/comando`...) se cargue la aplicación en vez de un 404.

## 4. Conectar los dos (CORS)

En el proyecto del **backend** → Settings → Environment Variables → `FRONTEND_URL` = la URL del
frontend, por ejemplo `https://marine-fleet-frontend.vercel.app`. Se pueden poner varias separadas
por coma. Luego **Deployments → … → Redeploy**: las variables solo aplican al desplegar de nuevo.

Listo: entra al frontend con `almirante@marina.gov` / `Marina.2026`.

## Qué cambia al correr en Vercel (para explicarlo si preguntan)

- **Una función serverless, no un servidor encendido.** `src/serverless.ts` crea la app una vez
  por instancia y la reutiliza. La primera petición tras un rato sin uso tarda unos segundos
  (arranque en frío).
- **El canal en tiempo real se guarda en la base.** Cada cambio va a la tabla
  `cambios_sincronizacion`, que comparten todas las instancias. El SSE la revisa cada 3 s, así
  que un cambio hecho en una instancia llega a quien está conectado a otra, dentro del RNF de
  15 s.
- **Los eventos se esperan antes de responder** (`emitAsync`). Si no, Vercel podía congelar la
  función con un cartel o una notificación a medio hacer.
- **Fotos y carteles en Supabase Storage.** El disco de Vercel se borra.
- Sigue funcionando igual en local con `npm run start:dev`: `main.ts` y `serverless.ts` usan la
  misma configuración (`src/bootstrap/configurar-app.ts`).
