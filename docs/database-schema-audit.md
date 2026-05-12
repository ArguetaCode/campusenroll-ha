# Database Schema Audit - CampusEnroll HA

## Estado objetivo confirmado

- Base unica: `campusenroll`
- Schema unico: `campusenroll`
- Todos los microservicios apuntan a la misma base

## Tablas esperadas por dominio

- Estudiantes: `campusenroll.students`
- Cursos: `campusenroll.courses`, `campusenroll.course_sections`, `campusenroll.section_schedules`
- Inscripciones: `campusenroll.enrollments`
- Pagos: `campusenroll.payments`
- Notificaciones: `campusenroll.notifications`

## Integridad esperada

- PK en todas las tablas
- UNIQUE `students.email`
- UNIQUE `courses.course_code` y compatibilidad con `courses.code`
- UNIQUE `enrollments(student_id, section_id)`
- CHECK `payments.amount > 0`
- CHECK `section_schedules.start_time < end_time`
- CHECK de capacidad en `course_sections`
- FK entre cursos-secciones-horarios e inscripciones

## Indices esperados

- `students(email)`, `students(status)`
- `courses(code)`, `courses(course_code)`
- `course_sections(course_id)`
- `section_schedules(section_id)`
- `enrollments(student_id)`, `enrollments(section_id)`, `enrollments(student_id,status)`, `enrollments(student_id,section_id)`
- `payments(enrollment_id)`, `payments(student_id)`
- `notifications(student_id)`, `notifications(event_id)`

## Observaciones de consistencia

- El enfoque de bases separadas fue retirado del compose principal.
- Flyway es el origen de verdad para DDL (`database/migrations/V1..V8`).
- `ddl-auto=update` se mantiene temporalmente para desarrollo; objetivo posterior `validate`.

## Plan ddl-auto

Estado actual:
- `student-service`: `update`
- `course-service`: `update`
- `billing-service`: `update`
- `notification-service`: `update`
- `enrollment-service`: `update`

Transicion:
1. Ejecutar Flyway en todos los ambientes.
2. Verificar paridad de esquema con smoke/integration tests.
3. Mover a `validate` por etapas iniciando en staging.