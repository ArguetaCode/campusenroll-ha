# Services Audit

Fecha de auditoria: 2026-05-08

## Resumen de infraestructura (campusenroll-ha)

- `docker-compose.yml`: infraestructura principal estable.
- Servicios por defecto: `postgres`, `redis`, `rabbitmq`, `prometheus`, `grafana`, `billing-service`, `notification-service`.
- Servicios en `profiles: [future]`: `student-service`, `course-service`, `enrollment-service`.
- Puertos criticos conservados:
  - PostgreSQL `55432:5432`
  - Redis `6379:6379`
  - RabbitMQ `5672`, UI `15672`
  - Prometheus `9090`
  - Grafana `3000`
  - Billing `8083`
  - Notification `8084`
- `monitoring/prometheus.yml` incluye targets de `student-service` y `course-service`; estaran activos cuando se levanten con `--profile future`.

## Tabla de auditoria por servicio

| Servicio | Estado | Compila | Puerto | Package | Dockerfile | Integrado en Compose | Endpoints existentes | Pendientes |
|---|---|---|---|---|---|---|---|---|
| student-service | Funcional minimo para integracion | Si (`mvn clean compile`) | 8081 | `com.campusenroll.student` | Si | Si, en `future` | `GET /health`, `GET /students`, `GET /students/{id}`, `POST /students`, `PUT /students/{id}`, `DELETE /students/{id}`, `GET /students/{id}/status`, `PATCH /students/{id}/status` | Estandarizar contrato final de rutas (`/students` vs `/api/students`) |
| course-service | Funcional minimo para integracion | Si (`mvn clean compile`) | 8082 | `com.campusenroll.course` | Si | Si, en `future` | `GET /health`, `POST /courses`, `GET /courses`, `GET /courses/{id}`, `POST /sections`, `GET /sections/{id}`, `GET /sections/{id}/schedule`, `POST /sections/{id}/reserve-seat`, `POST /sections/{id}/confirm-seat`, `POST /sections/{id}/release-seat` | Pruebas integradas con enrollment para traslapes |
| enrollment-service | Parcial, con deuda estructural | Si (`mvn clean compile`) | 8085 configurado, con inconsistencias en artefactos | `com.campusenroll.enrollment_service` | Si (ruta real profunda) | Si, en `future` pero con `build.context` inconsistente con ruta real | `POST /api/enrollments`, `GET /api/enrollments/{id}`, `GET /api/students/{studentId}/enrollments`, `DELETE /api/enrollments/{id}` | Falta `GET /health`, validacion de traslape, alineacion de estructura/version |
| billing-service | Estable | Si (`mvn compile`) | 8083 | `com.campusenroll.billing` | Si | Si, por defecto | `GET /health`, `POST /payments`, `GET /payments/{id}`, `GET /payments/{id}/cache-status` | Sin bloqueantes |
| notification-service | Estable | Si (`mvn compile`) | 8084 | `com.campusenroll.notification` | Si | Si, por defecto | `GET /health`, `GET /students/{studentId}/notifications`, `PATCH /notifications/{id}/read` | Sin bloqueantes |

## Validaciones ejecutadas

- `student-service`: `mvn clean compile` OK.
- `course-service`: `mvn clean compile` OK.
- `enrollment-service`: `mvn clean compile` OK en ruta real anidada.

## Conclusion

`student-service` y `course-service` quedaron listos con endpoints minimos requeridos para integrar luego con `enrollment-service` sin romper la logica existente.
