-- =============================================================================
-- Marine Fleet · Borra todo lo que crea 01_esquema.sql
-- =============================================================================
-- Tablas con sus datos, funciones y tipos. Sirve para volver a correr el
-- esquema desde cero en una base de desarrollo. NO tiene vuelta atrás: nunca lo
-- corras sobre una base con datos reales.
-- =============================================================================

BEGIN;

SET search_path = public;

DROP TABLE IF EXISTS
  reportes_recompensas, notificaciones, analisis_riesgo, auditoria,
  incidente_participantes, incidentes, operativo_responsables, operativo_bases, operativos,
  criminales_historial, reportes_ciudadanos, avistamientos, carteles, criterios_amenaza,
  recompensas, antecedentes, membresias, criminales, organizaciones,
  usuarios, roles, bases_navales, zonas_influencia, mares
  CASCADE;

DROP FUNCTION IF EXISTS
  fn_tocar_updated_at(), fn_criminales_historial(), fn_membresias_historial(),
  fn_antecedentes_historial(), fn_recompensas_inmutables(), fn_recompensas_historial(),
  fn_auditoria_solo_insercion();

DROP TYPE IF EXISTS
  tipo_mar, estado_base_naval, estado_usuario, tipo_agrupacion, categoria_organizacion,
  estado_criminal, nivel_amenaza, rol_membresia, estado_recompensa, motivo_cartel,
  estado_verificacion, origen_avistamiento, estado_reporte, estado_operativo,
  prioridad_operativo, resultado_operativo, rol_participacion, tipo_incidente,
  resultado_incidente, rol_en_incidente, desenlace_participante, tipo_accion_auditoria;

COMMIT;
