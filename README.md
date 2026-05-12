# CampusEnroll HA

Arquitectura de microservicios para inscripcion universitaria con base de datos principal compartida.

## Decision de base de datos

Para este proyecto se adopta una sola base de datos PostgreSQL compartida:
- Database: `campusenroll`
- Schema: `campusenroll`
- Host local: `127.0.0.1:55432`
- Host Docker: `campusenroll-postgres:5432`

Todos los microservicios usan la misma conexion logica de base:
`jdbc:postgresql://campusenroll-postgres:5432/campusenroll`

No se usan `student_db`, `course_db` ni `enrollment_db`.

## Servicios y puertos

- `student-service`: `8081` (profile `future`)
- `course-service`: `8082` (profile `future`)
- `billing-service`: `8083`
- `notification-service`: `8084`
- `enrollment-service`: `8085` (profile `future`)

## Infraestructura

- PostgreSQL: `55432:5432`
- Redis: `6379:6379`
- RabbitMQ: `5672:5672` y UI `15672`
- Prometheus: `9090`
- Grafana: `3000`

## Migraciones (Flyway)

Las migraciones SQL versionadas viven en `database/migrations` y Flyway es el administrador de esquema.

Ejecucion recomendada en desarrollo local limpio:

```bash
cd campusenroll-ha
docker compose down -v
docker compose up -d campusenroll-postgres
docker compose --profile db-migration run --rm campusenroll-flyway
docker compose up -d --build
docker compose --profile future up -d --build student-service course-service
# cuando enrollment este listo
docker compose --profile future up -d --build enrollment-service
```

## Verificaciones

```bash
docker exec -it campusenroll-postgres psql -U campus -d campusenroll -c "SELECT installed_rank, version, description, success FROM campusenroll.flyway_schema_history ORDER BY installed_rank;"
docker exec -it campusenroll-postgres psql -U campus -d campusenroll -c "SELECT table_schema, table_name FROM information_schema.tables WHERE table_schema='campusenroll' ORDER BY table_name;"
docker exec -it campusenroll-postgres psql -U campus -d campusenroll -c "SELECT datname FROM pg_database ORDER BY datname;"
```

## Notas de evolucion

Esta decision de base compartida simplifica integracion, auditoria, backups, monitoreo y DR para el checkpoint. En una siguiente fase se puede evolucionar hacia `database-per-service` o schemas separados por dominio.