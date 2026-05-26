# Evidence Checklist

Usar el gateway local `http://localhost:8080` como punto principal de evidencia. Los puertos directos de servicios siguen disponibles para diagnostico, pero la demo recomendada entra por Nginx.

## Stack

- [ ] `docker compose config --quiet` sin errores.
- [ ] `docker compose ps` mostrando saludables:
  - `campusenroll-postgres`
  - `campusenroll-redis`
  - `campusenroll-rabbitmq`
  - `campusenroll-api-gateway`
  - `campusenroll-student-service`
  - `campusenroll-course-service`
  - `campusenroll-enrollment-service`
  - `campusenroll-billing-service`
  - `campusenroll-notification-service`
- [ ] `GET http://localhost:8080/health`.
- [ ] `GET http://localhost:8080/health/student-service`.
- [ ] `GET http://localhost:8080/health/course-service`.
- [ ] `GET http://localhost:8080/health/enrollment-service`.
- [ ] `GET http://localhost:8080/health/billing-service`.
- [ ] `GET http://localhost:8080/health/notification-service`.

## Flujo critico

- [ ] `POST http://localhost:8080/students` crea estudiante `ACTIVE`.
- [ ] `POST http://localhost:8080/courses` crea curso `ACTIVE`.
- [ ] `POST http://localhost:8080/sections` crea seccion con `maxCapacity` definido.
- [ ] `POST http://localhost:8080/api/enrollments` con `simulatePaymentFailure=false` devuelve `CONFIRMED`.
- [ ] `POST http://localhost:8080/api/enrollments` con `simulatePaymentFailure=true` devuelve `PAYMENT_FAILED`.
- [ ] La seccion aprobada incrementa `confirmedSeats`.
- [ ] La seccion con pago fallido libera el cupo reservado.
- [ ] `GET http://localhost:8080/students/{studentId}/notifications` muestra notificacion del pago.

## Base de datos

- [ ] `campusenroll.flyway_schema_history` muestra migraciones exitosas.
- [ ] `campusenroll.students` contiene estudiantes de prueba.
- [ ] `campusenroll.course_sections` refleja cupos reservados/confirmados sin superar `max_capacity`.
- [ ] `campusenroll.enrollments` contiene estados `CONFIRMED` y `PAYMENT_FAILED`.
- [ ] `campusenroll.payments` contiene pagos `APPROVED` y `FAILED`.
- [ ] `campusenroll.notifications` contiene eventos procesados.

## Mensajeria y cache

- [ ] RabbitMQ UI accesible en `http://localhost:15672`.
- [ ] Exchange `campusenroll.payments` existe.
- [ ] Queue `campusenroll.notifications.payments` existe y tiene consumidores.
- [ ] Queues de enrollment para pagos aprobados/fallidos existen.
- [ ] Redis contiene keys `billing:payment:*:status`.
- [ ] Redis contiene keys de idempotencia de notificaciones.

## Observabilidad

- [ ] Prometheus accesible en `http://localhost:9090`.
- [ ] Targets `UP` para los cinco microservicios.
- [ ] Targets `UP` para RabbitMQ, Redis exporter, PostgreSQL exporter y Nginx exporter.
- [ ] Grafana accesible en `http://localhost:3000`.
- [ ] Dashboard de CampusEnroll visible.

## Pruebas seguras

- [ ] `powershell -ExecutionPolicy Bypass -File .\scripts\gateway-smoke-ci.ps1 -SkipFlyway` pasa.
- [ ] `powershell -ExecutionPolicy Bypass -File .\scripts\k6-gateway-ci.ps1 -TestProfile smoke -SkipGatewayPrecheck` pasa o se documenta como smoke no bloqueante.
- [ ] No se ejecuta `docker compose down -v` ni comandos que borren volumenes.
