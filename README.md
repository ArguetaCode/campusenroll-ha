# CampusEnroll HA

CampusEnroll HA es un sistema de inscripción universitaria basado en microservicios. El sistema permite gestionar estudiantes, cursos, secciones, cupos limitados, pagos simulados, notificaciones y eventos asíncronos.

## Propuesta asignada

Sistema de inscripción de cursos universitarios con cupos limitados y validación de horarios.

## Microservicios principales

- student-service
- course-service
- enrollment-service
- billing-service
- notification-service

## Infraestructura

El proyecto utiliza:

- Java Spring Boot
- PostgreSQL
- Docker Compose
- Redis
- RabbitMQ
- Prometheus
- Grafana
- Postman
- k6

## Reglas críticas

1. No permitir más inscripciones que el cupo máximo de una sección.
2. No duplicar inscripciones.
3. No permitir traslapes de horario.
4. No confirmar inscripción si el pago falla.
5. Liberar cupo si el pago falla.
6. No perder eventos críticos del proceso.
7. No permitir estados inválidos dentro del flujo de inscripción.

## Servicios de infraestructura

| Servicio | Puerto | Descripción |
|---|---:|---|
| PostgreSQL | 5432 | Base de datos principal |
| Redis | 6379 | Caché y apoyo temporal |
| RabbitMQ | 5672 | Broker de mensajería |
| RabbitMQ Management | 15672 | Panel web de RabbitMQ |
| Prometheus | 9090 | Métricas |
| Grafana | 3000 | Dashboards |

## Levantar infraestructura

```bash
docker compose up -d