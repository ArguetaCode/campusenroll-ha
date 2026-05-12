# Database Schema Audit - CampusEnroll HA

## Scope
Audited sources:
- `student-service`
- `course-service`
- `billing-service`
- `notification`
- `enrollment-service`

Shared database target:
- Database: `campusenroll`
- Schema: `campusenroll`

## Expected Tables By Microservice

### student-service
- `campusenroll.students`

Main columns:
- `id` PK
- `student_code` UNIQUE, NOT NULL
- `full_name` NOT NULL
- `email` UNIQUE, NOT NULL
- `status` NOT NULL
- `created_at` NOT NULL

Constraints:
- PK on `id`
- UNIQUE on `student_code`
- UNIQUE on `email`

Indexes needed:
- `students(email)`
- `students(status)`

### course-service
- `campusenroll.courses`
- `campusenroll.course_sections`
- `campusenroll.section_schedules`

Main columns:
- `courses`: `id`, `course_code`, optional compatibility `code`, `name`, `description`, `status`, `created_at`
- `course_sections`: `id`, `course_id`, `section_code`, `max_capacity`, compatibility `capacity`, `reserved_seats`, `confirmed_seats`, compatibility `enrolled_seats`, `status`, `created_at`
- `section_schedules`: `id`, `section_id`, `day_of_week`, `start_time`, `end_time`, `classroom`, `created_at`

Constraints:
- PK in all tables
- UNIQUE `courses.course_code`
- UNIQUE `courses.code` (if present for compatibility)
- UNIQUE `course_sections(course_id, section_code)`
- FK `course_sections.course_id -> courses.id`
- FK `section_schedules.section_id -> course_sections.id`
- CHECK `start_time < end_time`
- CHECK `enrolled_seats + reserved_seats <= capacity` mapped as compatibility check with existing `confirmed_seats/max_capacity`

Indexes needed:
- `courses(code)`
- `courses(course_code)`
- `course_sections(course_id)`
- `section_schedules(section_id)`

### enrollment-service
- `campusenroll.enrollments`

Main columns:
- `id` PK
- `student_id` NOT NULL
- `section_id` NOT NULL
- `status` NOT NULL
- `payment_reference`
- `created_at`
- `updated_at`
- `version`

Constraints:
- PK `id`
- UNIQUE `(student_id, section_id)`
- FK `student_id -> students.id`
- FK `section_id -> course_sections.id`

Indexes needed:
- `enrollments(student_id)`
- `enrollments(section_id)`
- `enrollments(student_id, status)`
- `enrollments(student_id, section_id)`

### billing-service
- `campusenroll.payments`

Main columns:
- `id` PK
- `enrollment_id` NOT NULL
- `student_id` NOT NULL
- `amount` NUMERIC(10,2) NOT NULL
- `status` NOT NULL
- `failure_reason`
- `created_at`

Constraints:
- PK `id`
- CHECK `amount > 0`

Indexes needed:
- `payments(enrollment_id)`
- `payments(student_id)`

### notification-service
- `campusenroll.notifications`

Main columns:
- `id` PK
- `student_id` NOT NULL
- `event_id` UNIQUE, NOT NULL
- `event_type` NOT NULL
- `payment_id` NOT NULL
- `enrollment_id` NOT NULL
- `type` NOT NULL
- `message` NOT NULL
- `status` NOT NULL
- `created_at` NOT NULL

Constraints:
- PK `id`
- UNIQUE `event_id`

Indexes needed:
- `notifications(student_id)`
- `notifications(event_id)`

## Inconsistencies Identified
1. `campusenroll-ha/docker-compose.yml` currently routes `student/course/enrollment` (profile `future`) to separate DBs (`student_db`, `course_db`, `enrollment_db`) while services default to shared `campusenroll` in local execution.
2. Naming mismatch in course section capacity model:
   - Requested: `capacity`, `enrolled_seats`
   - Current JPA: `max_capacity`, `confirmed_seats`
3. Naming mismatch in course code:
   - Requested index on `courses(code)`
   - Current JPA uses `course_code`.
4. Current strategy relies on `spring.jpa.hibernate.ddl-auto=update`; no canonical versioned migration history existed.

## Integrity Risks
- Divergent schemas per execution mode (local vs compose profiles) can produce runtime drift.
- Without explicit FK/check constraints, race conditions under high concurrency can persist invalid states.
- `ddl-auto=update` may apply implicit ALTERs that are difficult to review/audit.

## Recommendations
1. Keep a single canonical shared schema migration history under `campusenroll-ha/database/migrations`.
2. Run Flyway migrations before app startup in controlled environments.
3. Freeze DDL changes into explicit SQL files and move services gradually to `ddl-auto=validate`.
4. Keep compatibility columns (`code`, `capacity`, `enrolled_seats`) only as transition support; converge model names later in a dedicated hardening iteration.
5. Add migration CI checks (Flyway `info` + `validate`) before deployments.

## `ddl-auto` Transition Plan (`update` -> `validate`)
Current status (do not change yet):
- `student-service`: `spring.jpa.hibernate.ddl-auto=update`
- `course-service`: `spring.jpa.hibernate.ddl-auto=update`
- `billing-service`: `spring.jpa.hibernate.ddl-auto=update`
- `notification-service`: `spring.jpa.hibernate.ddl-auto=update`
- `enrollment-service`: `spring.jpa.hibernate.ddl-auto=update`

Proposed transition:
1. Apply Flyway migrations in every environment and verify schema parity.
2. Run each service in staging with `ddl-auto=validate` and execute integration tests.
3. Fix any mismatch through new Flyway migration files only (never ad-hoc ALTER).
4. Promote to production with `validate` once all services pass startup and smoke tests.
