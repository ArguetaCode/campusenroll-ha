# Next Implementation Plan

Fecha: 2026-05-12

## Completado

1. Arquitectura consolidada en base unica `campusenroll`.
2. Flyway como control de migraciones versionadas.
3. Hardening funcional de `enrollment-service` en `8085`.
4. Validacion de traslape, duplicado, estudiante activo y resiliencia en flujo de cupo/pago.

## Siguiente paso recomendado

1. Ejecutar pruebas E2E desde Postman/Newman con profile `future` activo.
2. Agregar pruebas automatizadas de integracion para escenarios:
   - estudiante inactivo
   - traslape de horario
   - pago fallido y liberacion de cupo
3. Preparar paso de `ddl-auto=update` a `ddl-auto=validate` en staging.
4. Incorporar PgBouncer y politicas de retry/circuit-breaker como hardening de red.