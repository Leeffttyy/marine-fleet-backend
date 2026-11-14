/**
 * SQL del modelo de lectura de reportes (PostgreSQL). Cada reporte es UNA
 * consulta agregada (sin N+1) para cumplir el RNF de 3 segundos. Todos los
 * valores del usuario entran como parametros `$n`, nunca interpolados.
 *
 * Los alias en camelCase van entre comillas dobles: sin ellas Postgres los
 * devuelve en minusculas y el adaptador no los encontraria.
 */

/**
 * Recompensa vigente de cada criminal ACTIVO en la fecha de corte. Si por error
 * hubiera dos recompensas solapadas, se toma la mas reciente (rn = 1), asi nunca
 * se cuenta doble.
 * Parametros: $1 corte, $2 corte.
 */
export const SQL_RECOMPENSAS_POR_MAR = `
  SELECT m.id AS "marId", m.nombre AS "marNombre", m.tipo AS "tipoMar",
         COALESCE(SUM(rv.monto), 0) AS "totalAcumulado",
         COUNT(rv.criminal_id) AS "cantidadCriminales"
    FROM mares m
    LEFT JOIN zonas_influencia z ON z.mar_id = m.id
    LEFT JOIN criminales c ON c.zona_influencia_id = z.id AND c.estado = 'ACTIVO'
    LEFT JOIN (
      SELECT criminal_id, monto FROM (
        SELECT r.criminal_id, r.monto,
               ROW_NUMBER() OVER (PARTITION BY r.criminal_id
                                  ORDER BY r.vigente_desde DESC, r.created_at DESC) AS rn
          FROM recompensas r
         WHERE r.estado IN ('VIGENTE', 'HISTORICA')
           AND r.vigente_desde IS NOT NULL AND r.vigente_desde <= $1
           AND (r.vigente_hasta IS NULL OR r.vigente_hasta > $2)
      ) ordenadas WHERE rn = 1
    ) rv ON rv.criminal_id = c.id
   WHERE m.activo
   GROUP BY m.id, m.nombre, m.tipo
   ORDER BY m.tipo ASC, m.nombre ASC`;

export const SQL_GUARDAR_INSTANTANEA = `
  INSERT INTO reportes_recompensas
    (id, periodo, mar_id, mar_nombre, total_acumulado, cantidad_criminales, generado_por, generado_en)
  VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
  ON CONFLICT (periodo, mar_id) DO UPDATE
    SET mar_nombre = EXCLUDED.mar_nombre, total_acumulado = EXCLUDED.total_acumulado,
        cantidad_criminales = EXCLUDED.cantidad_criminales, generado_por = EXCLUDED.generado_por,
        generado_en = EXCLUDED.generado_en`;

export const SQL_INSTANTANEAS = `
  SELECT periodo, mar_id AS "marId", mar_nombre AS "marNombre", total_acumulado AS "totalAcumulado",
         cantidad_criminales AS "cantidadCriminales", generado_por AS "generadoPor",
         generado_en AS "generadoEn"
    FROM reportes_recompensas
   ORDER BY periodo DESC, mar_nombre ASC
   LIMIT 600`;

/** Columnas de conteo comunes a las tres tendencias. */
const CONTEOS = `
  COUNT(c.id) AS "totalCriminales",
  COUNT(c.id) FILTER (WHERE c.estado = 'ACTIVO') AS activos,
  COUNT(c.id) FILTER (WHERE c.estado = 'CAPTURADO') AS capturados,
  COUNT(c.id) FILTER (WHERE c.estado = 'MUERTO') AS muertos,
  COALESCE(SUM(c.recompensa_vigente_monto) FILTER (WHERE c.estado = 'ACTIVO'), 0)
    AS "recompensaActiva"`;

/** Orden de severidad de los niveles de amenaza, del mas grave al pendiente. */
const ORDEN_NIVEL = `array_position(ARRAY['ALTO', 'MEDIO', 'BAJO', 'PENDIENTE'], c.nivel_amenaza::text)`;

/** Parametro: $1 desde (avistamientos recientes). */
export const SQL_TENDENCIA_ZONA = `
  SELECT COALESCE(z.nombre, 'Sin zona') AS grupo, COALESCE(m.nombre, 'Sin mar') AS subgrupo, ${CONTEOS},
         COALESCE(MAX(av.n), 0) AS "avistamientosRecientes"
    FROM criminales c
    LEFT JOIN zonas_influencia z ON z.id = c.zona_influencia_id
    LEFT JOIN mares m ON m.id = z.mar_id
    LEFT JOIN (SELECT zona_influencia_id, COUNT(*) AS n FROM avistamientos
                WHERE fecha_hora >= $1 GROUP BY zona_influencia_id) av
           ON av.zona_influencia_id = c.zona_influencia_id
   GROUP BY z.id, z.nombre, m.nombre
   ORDER BY "recompensaActiva" DESC, "totalCriminales" DESC`;

export const SQL_TENDENCIA_NIVEL = `
  SELECT c.nivel_amenaza AS grupo, NULL::text AS subgrupo, ${CONTEOS},
         COALESCE(MAX(av.n), 0) AS "avistamientosRecientes"
    FROM criminales c
    LEFT JOIN (SELECT c2.nivel_amenaza, COUNT(*) AS n FROM avistamientos a
                 JOIN criminales c2 ON c2.id = a.criminal_id
                WHERE a.fecha_hora >= $1 GROUP BY c2.nivel_amenaza) av
           ON av.nivel_amenaza = c.nivel_amenaza
   GROUP BY c.nivel_amenaza
   ORDER BY ${ORDEN_NIVEL}`;

/**
 * Una sola afiliacion por criminal: la de mayor rango (LIDER > OFICIAL >
 * MIEMBRO) y, a igual rango, la mas antigua. Sin esto, un criminal con dos
 * membresias vigentes se contaba (y su recompensa se sumaba) en las dos, y el
 * total del reporte superaba al numero real de criminales.
 */
const MEMBRESIA_PRINCIPAL = `
  (SELECT criminal_id, organizacion_id FROM (
     SELECT mb.criminal_id, mb.organizacion_id,
            ROW_NUMBER() OVER (PARTITION BY mb.criminal_id
                               ORDER BY array_position(ARRAY['LIDER', 'OFICIAL', 'MIEMBRO'], mb.rol::text),
                                        mb.fecha_ingreso, mb.id) AS rn
       FROM membresias mb WHERE mb.vigente) ranqueadas
    WHERE rn = 1)`;

export const SQL_TENDENCIA_AFILIACION = `
  SELECT COALESCE(o.categoria::text, 'SIN_AFILIACION') AS grupo,
         COALESCE(o.nombre, 'Sin afiliacion') AS subgrupo,
         ${CONTEOS}, COALESCE(MAX(av.n), 0) AS "avistamientosRecientes"
    FROM criminales c
    LEFT JOIN ${MEMBRESIA_PRINCIPAL} mb ON mb.criminal_id = c.id
    LEFT JOIN organizaciones o ON o.id = mb.organizacion_id
    LEFT JOIN (SELECT mb2.organizacion_id, COUNT(*) AS n FROM avistamientos a
                 JOIN ${MEMBRESIA_PRINCIPAL} mb2 ON mb2.criminal_id = a.criminal_id
                WHERE a.fecha_hora >= $1 GROUP BY mb2.organizacion_id) av
           ON av.organizacion_id IS NOT DISTINCT FROM o.id
   GROUP BY o.id, o.categoria, o.nombre
   ORDER BY "recompensaActiva" DESC, "totalCriminales" DESC`;

export const SQL_RESUMEN = `
  SELECT
    (SELECT COUNT(*) FROM criminales WHERE estado = 'ACTIVO') AS "criminalesActivos",
    (SELECT COUNT(*) FROM criminales WHERE estado = 'CAPTURADO') AS "criminalesCapturados",
    (SELECT COUNT(*) FROM criminales WHERE estado = 'MUERTO') AS "criminalesMuertos",
    (SELECT COALESCE(SUM(recompensa_vigente_monto), 0) FROM criminales WHERE estado = 'ACTIVO')
      AS "recompensaActivaTotal",
    (SELECT COUNT(*) FROM reportes_ciudadanos WHERE estado = 'PENDIENTE') AS "reportesPendientes",
    (SELECT COUNT(*) FROM avistamientos WHERE estado_verificacion = 'PENDIENTE')
      AS "avistamientosPendientes",
    (SELECT COUNT(*) FROM recompensas WHERE estado = 'PENDIENTE_VALIDACION')
      AS "recompensasPorValidar"`;

export const SQL_POR_NIVEL = `
  SELECT nivel_amenaza AS etiqueta, COUNT(*) AS valor FROM criminales
   WHERE estado = 'ACTIVO' GROUP BY nivel_amenaza ORDER BY nivel_amenaza`;

export const SQL_POR_ESTADO = `
  SELECT estado AS etiqueta, COUNT(*) AS valor FROM criminales GROUP BY estado ORDER BY estado`;

export const SQL_POR_MAR = `
  SELECT m.nombre AS etiqueta, COUNT(c.id) AS valor
    FROM mares m
    LEFT JOIN zonas_influencia z ON z.mar_id = m.id
    LEFT JOIN criminales c ON c.zona_influencia_id = z.id AND c.estado = 'ACTIVO'
   WHERE m.activo
   GROUP BY m.id, m.nombre, m.tipo
   ORDER BY m.tipo ASC, m.nombre ASC`;

export const SQL_POR_CATEGORIA = `
  SELECT COALESCE(o.categoria::text, 'SIN_AFILIACION') AS etiqueta, COUNT(DISTINCT c.id) AS valor
    FROM criminales c
    LEFT JOIN membresias mb ON mb.criminal_id = c.id AND mb.vigente
    LEFT JOIN organizaciones o ON o.id = mb.organizacion_id
   WHERE c.estado = 'ACTIVO'
   GROUP BY 1
   ORDER BY valor DESC`;

/**
 * El mes se calcula en hora de Colombia (UTC-5), la misma de periodo.ts, sin
 * importar la zona horaria del servidor de base de datos. Parametro: $1 desde.
 */
export const SQL_AVISTAMIENTOS_POR_MES = `
  SELECT to_char(fecha_hora AT TIME ZONE 'America/Bogota', 'YYYY-MM') AS etiqueta,
         COUNT(*) AS valor
    FROM avistamientos
   WHERE fecha_hora >= $1
   GROUP BY 1
   ORDER BY 1`;
