# Services Audit

Fecha de auditoria: 2026-05-11

## Resumen

CampusEnroll HA queda alineado a una arquitectura de base compartida:
- Database unica: `campusenroll`
- Schema unico: `campusenroll`
- Sin `student_db`, `course_db`, `enrollment_db`

## Infraestructura y perfiles

- Servicios base: `postgres`, `redis`, `rabbitmq`, `prometheus`, `grafana`, `billing-service`, `notification-service`
- Profile `future`: `student-service`, `course-service`, `enrollment-service`
- Profile `db-migration`: `campusenroll-flyway`

## Conectividad de datos

Todos los microservicios en compose usan:
- `SPRING_DATASOURCE_URL=jdbc:postgresql://campusenroll-postgres:5432/campusenroll`

## Notas de estabilidad

- `billing-service` y `notification-service` se mantienen sin cambios funcionales de negocio.
- `enrollment-service` mantiene su logica actual; se corrigio `build.context` a la ruta real del `pom.xml`.
- `ddl-auto=update` se mantiene temporalmente para no romper arranque, con plan de cambio a `validate` documentado.