# Checkpoint Status

## Que ya funciona

- Infraestructura base en Docker Compose con PostgreSQL, Redis, RabbitMQ, Prometheus y Grafana.
- `billing-service` funcional con persistencia PostgreSQL, cache en Redis y publicacion de eventos RabbitMQ.
- `notification-service` funcional consumiendo eventos de pago, persistiendo notificaciones e idempotencia con Redis.
- Targets de Prometheus configurados para billing y notification.
- Script de carga k6 actualizado para billing y chequeo opcional de notification.

## Que esta pendiente

- Cierre funcional completo de `student-service`, `course-service` y `enrollment-service` para flujo integral.
- Homologar version de Spring Boot de `enrollment-service` a `3.3.5`.
- Endpoint de salud uniforme en servicios de dominio restantes.
- Suite de pruebas integradas automatizadas del flujo completo de inscripcion.

## Servicios implementados

- `billing-service`
- `notification-service`

## Servicios pendientes/parcialmente implementados

- `student-service`
- `course-service`
- `enrollment-service`

## Endpoints disponibles

- Billing:
  - `POST /payments`
  - `GET /payments/{id}`
  - `GET /payments/{id}/cache-status`
  - `GET /health`
- Notification:
  - `GET /health`
  - `GET /students/{studentId}/notifications`
  - `PATCH /notifications/{id}/read`
- Student/Course/Enrollment:
  - APIs parciales disponibles, en proceso de homologacion documental y operativa.

## Evidencias tecnicas a capturar

- Contenedores arriba (`docker ps`).
- Health de billing y notification.
- POST de pagos `APPROVED`/`FAILED`.
- Datos en PostgreSQL (`payments`, `notifications`).
- Keys en Redis.
- Exchange/queue/bindings en RabbitMQ.
- Targets `UP` en Prometheus.
- Grafana accesible.

## Riesgos tecnicos actuales

- Inconsistencia de version de Spring Boot en `enrollment-service`.
- Estructura anidada de carpetas en `enrollment-service` dificulta mantenimiento.
- Heterogeneidad de rutas y health endpoints en servicios de dominio.

## Proximos pasos

1. Homologar `enrollment-service` a Spring Boot `3.3.5` y package estandar.
2. Definir contratos estables entre `student`, `course` y `enrollment`.
3. Incorporar pruebas E2E con Docker Compose para flujo de inscripcion completo.
