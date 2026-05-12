# Database HA Strategy - CampusEnroll HA

## Decision final del proyecto

Se usa **una sola base principal** para todos los microservicios:
- Database: `campusenroll`
- Schema: `campusenroll`
- Usuario desarrollo: `campus`
- Puerto local: `55432`
- Puerto interno: `5432`

Conexion Docker comun:
`jdbc:postgresql://campusenroll-postgres:5432/campusenroll`

## Alcance

- La separacion por dominio se hace por tablas y constraints dentro del schema compartido.
- No se crean `student_db`, `course_db` ni `enrollment_db`.
- Flyway controla DDL versionado (`V1..V8`).

## Motivacion

- Menor complejidad operativa para checkpoint final.
- Integracion y pruebas E2E mas directas.
- Observabilidad y backups centralizados.
- Preparacion clara para replica y recuperacion ante desastres.

## HA y escalamiento

- Escrituras criticas: siempre al primary.
- Lecturas de reporting: candidata a read replica (futuro).
- Redis: cache, idempotencia y soporte de rate-limiting.
- RabbitMQ: desacople de eventos (`campusenroll.payments`).
- PgBouncer: mejora futura para pooling de conexiones.

## Seguridad

- Desarrollo: usuario unico `campus`.
- Produccion: usuarios separados por servicio con least privilege, secrets manager, TLS y rotacion de credenciales.

## Evolucion futura

Cuando el proyecto crezca se puede migrar gradualmente a:
1. schemas separados por dominio, o
2. database-per-service.

La transicion debe hacerse con migraciones planificadas y contrato de datos versionado.