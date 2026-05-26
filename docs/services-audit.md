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
- Una inscripcion `PAYMENT_FAILED` o `CANCELLED` no bloquea un nuevo intento; la base restringe unicamente inscripciones activas duplicadas.
- Estados y transiciones coordinados con billing documentados en `docs/enrollment-payment-states.md`.
- Validacion de traslape de horarios por `dayOfWeek/startTime/endTime`.
- Validacion de capacidad y horarios al crear secciones; una seccion sin cupos responde conflicto de negocio.
- Flujo robusto de cupo+pago:
  - reserva cupo
  - crea `PENDING_PAYMENT`
  - billing solo acepta pago para una inscripcion pendiente valida del mismo estudiante
  - procesa pago
  - confirma cupo y estado `CONFIRMED` si `APPROVED`
  - libera cupo y estado `PAYMENT_FAILED` si `FAILED` o error de integracion

## Reglas de cupos e inscripciones

- `course-service` serializa reserva, confirmacion y liberacion con bloqueo de la seccion.
- `reserved_seats` y `confirmed_seats` no pueden ser negativos ni superar juntos `max_capacity`.
- La inscripcion duplicada activa y la reserva sin cupo deben responder `409 Conflict`.
- Los horarios de una misma seccion deben tener inicio anterior al fin y no solaparse el mismo dia.

## Observabilidad

`monitoring/prometheus.yml` incluye target:
- `enrollment-service:8085` con `metrics_path: /actuator/prometheus`.

Nota: si profile `future` no esta activo, ese target aparecera DOWN.
