# Architecture Summary

## Arquitectura de microservicios

CampusEnroll HA usa una arquitectura orientada a servicios para desacoplar dominios de estudiantes, cursos, inscripciones, pagos y notificaciones. Cada servicio mantiene responsabilidades acotadas y se integra por APIs y eventos.

## Rol de cada servicio

- `student-service`: administra estudiantes y su estado academico.
- `course-service`: administra cursos, secciones, horarios y cupos.
- `enrollment-service`: orquesta la inscripcion y coordina dependencias.
- `billing-service`: registra pagos y publica eventos de resultado.
- `notification-service`: consume eventos de pagos y genera notificaciones al estudiante.

## Rol de PostgreSQL

- Persistencia transaccional de entidades de negocio.
- Uso de schema `campusenroll` para tablas compartidas por checkpoint.
- Evidencia auditable de pagos y notificaciones.

## Rol de Redis

- Cache temporal de estado de pagos (`billing:payment:{paymentId}:status`).
- Idempotencia de eventos de notificacion (`notification:event:{eventId}`).
- Reduccion de reprocesamientos y respuestas mas rapidas.

## Rol de RabbitMQ

- Broker para comunicacion asincrona orientada a eventos.
- Exchange `campusenroll.payments` con routing keys:
  - `payment.approved`
  - `payment.failed`
- Permite desacoplar producer (`billing-service`) y consumer (`notification-service`).

## Rol de Prometheus/Grafana

- Prometheus recolecta metricas de infraestructura y servicios.
- Grafana visualiza disponibilidad, rendimiento y salud operacional.
- Soporte para evidencias del checkpoint tecnico.

## Estrategia de consistencia

- Consistencia eventual entre pagos e inscripciones/notificaciones via eventos.
- Idempotencia para evitar duplicacion de notificaciones.
- Persistencia duradera en PostgreSQL como fuente de verdad.

## Eventos principales

- `payment.approved`: habilita continuidad del flujo de inscripcion y notificacion positiva.
- `payment.failed`: bloquea confirmacion y dispara notificacion de fallo.

## Caso critico: inscripcion de curso con pago y notificacion

1. Usuario inicia inscripcion en `enrollment-service`.
2. `enrollment-service` solicita pago a `billing-service`.
3. `billing-service` guarda pago, cachea estado y publica evento.
4. `notification-service` consume evento desde RabbitMQ.
5. `notification-service` aplica idempotencia en Redis y guarda notificacion en PostgreSQL.
6. El sistema deja trazabilidad completa para soporte y checkpoint.
