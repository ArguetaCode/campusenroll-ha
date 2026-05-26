# Checkpoint Status

## Que ya funciona

- Infraestructura base en Docker Compose con PostgreSQL, Redis, RabbitMQ, Nginx API Gateway, Prometheus y Grafana.
- Migraciones Flyway versionadas para el schema compartido `campusenroll`.
- `student-service` funcional para estudiantes y estado academico.
- `course-service` funcional para cursos, secciones, horarios y cupos con bloqueo pesimista.
- `enrollment-service` funcional para orquestar estudiante, seccion, pago y transiciones de inscripcion.
- `billing-service` funcional con persistencia PostgreSQL, cache en Redis, validacion de inscripcion pendiente y publicacion de eventos RabbitMQ.
- `notification-service` funcional consumiendo eventos de pago, persistiendo notificaciones e idempotencia con Redis.
- Gateway Nginx en `:8080` como punto unico para rutas de estudiantes, cursos, secciones, pagos, notificaciones e inscripciones.
- Observabilidad base con Prometheus/Grafana y targets para los cinco microservicios e infraestructura.
- Smoke tests seguros para gateway y k6 en modo pequeno.

## Pendiente real

- Homologar `enrollment-service` a Spring Boot `3.3.5` como el resto de servicios.
- Reducir la estructura anidada de `enrollment-service/enrollment-service/enrollment-service` en una siguiente fase de mantenimiento.
- Agregar una suite E2E automatizada estable del flujo completo de inscripcion, incluyendo pago fallido y liberacion de cupo.
- Implementar Outbox Pattern o un mecanismo equivalente para garantizar publicacion de eventos si RabbitMQ falla despues de persistir un pago.
- Agregar DLQ, reintentos con backoff y alertas para consumidores RabbitMQ.
- Reemplazar secretos de laboratorio, agregar TLS y politicas productivas antes de cualquier uso fuera de demo/laboratorio.

## Servicios implementados

- `student-service`
- `course-service`
- `enrollment-service`
- `billing-service`
- `notification-service`

## Endpoints principales por gateway

- Gateway:
  - `GET /health`
  - `GET /health/student-service`
  - `GET /health/course-service`
  - `GET /health/billing-service`
  - `GET /health/notification-service`
  - `GET /health/enrollment-service`
- Student:
  - `GET /students`
  - `GET /students/{id}`
  - `POST /students`
  - `GET /students/{id}/status`
  - `PATCH /students/{id}/status`
- Course:
  - `GET /courses`
  - `POST /courses`
  - `GET /sections`
  - `POST /sections`
  - `POST /sections/{id}/reserve-seat`
  - `POST /sections/{id}/confirm-seat`
  - `POST /sections/{id}/release-seat`
- Enrollment:
  - `POST /api/enrollments`
  - `GET /api/enrollments`
  - `GET /api/enrollments/{id}`
  - `GET /api/students/{studentId}/enrollments`
- Billing:
  - `POST /payments`
  - `GET /payments`
  - `GET /payments/{id}`
  - `GET /payments/{id}/cache-status`
- Notification:
  - `GET /notifications`
  - `GET /students/{studentId}/notifications`
  - `PATCH /notifications/{id}/read`

## Evidencias tecnicas a capturar

- `docker compose ps` con infraestructura, gateway y cinco microservicios saludables.
- Health del gateway y health por servicio.
- Flujo aprobado desde `POST http://localhost:8080/api/enrollments` con estado `CONFIRMED`.
- Flujo fallido con `simulatePaymentFailure=true` y estado `PAYMENT_FAILED`.
- Datos en PostgreSQL: `students`, `courses`, `course_sections`, `enrollments`, `payments`, `notifications`.
- Keys en Redis para pagos e idempotencia de eventos.
- Exchange `campusenroll.payments` y colas/bindings en RabbitMQ.
- Targets `UP` en Prometheus para servicios e infraestructura.
- Dashboard Grafana accesible.

## Riesgos tecnicos actuales

- El stack local sigue usando instancias unicas de PostgreSQL, Redis, RabbitMQ y Nginx.
- El PostgreSQL HA Lab es aislado y manual; no reemplaza la base del stack local.
- El CI completo depende de repos privados hermanos y puede saltar el smoke pesado si falta `CAMPUSENROLL_CI_TOKEN`.
- k6 se usa como smoke funcional pequeno, no como evidencia de performance o 50,000 peticiones.

## Proximos pasos recomendados

1. Mantener actualizada la evidencia de demo local.
2. Homologar `enrollment-service` a Spring Boot `3.3.5`.
3. Agregar E2E automatizado del flujo completo aprobado/fallido.
4. Implementar Outbox Pattern y DLQ para robustez de eventos.
