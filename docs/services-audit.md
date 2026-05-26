# Services Audit

Fecha de auditoria: 2026-05-12

## Resumen

CampusEnroll HA opera con base compartida unica:
- Database: `campusenroll`
- Schema: `campusenroll`

Todos los servicios usan la misma base; no se usan `student_db`, `course_db` ni `enrollment_db`.

## Estado por servicio

- `student-service` (`8081`): activo, expone estado de estudiante.
- `course-service` (`8082`): activo, expone secciones, horarios y reserva/confirmacion/liberacion de cupos.
- `billing-service` (`8083`): activo, procesa pagos y publica eventos.
- `notification-service` (`8084`): activo, consume eventos y persiste notificaciones.
- `enrollment-service` (`8085`, profile `future`): hardening aplicado.

## Hardening aplicado en enrollment-service

- Endpoint agregado: `GET /health`.
- Se mantiene API existente:
  - `POST /api/enrollments`
  - `GET /api/enrollments/{id}`
  - `GET /api/students/{studentId}/enrollments`
  - `DELETE /api/enrollments/{id}`
- Validacion obligatoria de estudiante activo (`GET /students/{id}/status`).
- Validacion de existencia de seccion (`GET /sections/{id}`).
- Validacion de inscripcion duplicada para `PENDING_PAYMENT` y `CONFIRMED`.
- Estados y transiciones coordinados con billing documentados en `docs/enrollment-payment-states.md`.
- Validacion de traslape de horarios por `dayOfWeek/startTime/endTime`.
- Flujo robusto de cupo+pago:
  - reserva cupo
  - crea `PENDING_PAYMENT`
  - billing solo acepta pago para una inscripcion pendiente valida del mismo estudiante
  - procesa pago
  - confirma cupo y estado `CONFIRMED` si `APPROVED`
  - libera cupo y estado `PAYMENT_FAILED` si `FAILED` o error de integracion

## Observabilidad

`monitoring/prometheus.yml` incluye target:
- `enrollment-service:8085` con `metrics_path: /actuator/prometheus`.

Nota: si profile `future` no esta activo, ese target aparecera DOWN.
