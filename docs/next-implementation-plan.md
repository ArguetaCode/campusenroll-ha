# Next Implementation Plan

Fecha: 2026-05-11

## Completado en esta iteracion

1. Unificacion de base de datos compartida en todos los servicios.
2. Eliminacion del enfoque de bases separadas en `docker-compose`.
3. Flyway definido como mecanismo de migraciones versionadas.
4. Documentacion de backup/restore, seguridad y replica alineada al nuevo enfoque.

## Siguiente paso recomendado

1. Ejecutar corrida limpia local (`down -v`, `postgres`, `flyway`, servicios).
2. Validar arranque de `student`, `course`, `enrollment` con profile `future`.
3. Validar constraints `NOT VALID` con estrategia gradual de limpieza de datos.
4. Preparar cambio controlado de `ddl-auto=update` a `ddl-auto=validate` en staging.