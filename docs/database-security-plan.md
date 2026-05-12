# Database Security Plan - CampusEnroll HA

## Access Model
- Separate DB user per microservice (`student_app`, `course_app`, `enrollment_app`, `billing_app`, `notification_app`).
- Keep ownership/admin roles separate from runtime app roles.

## Least Privilege
- App users: only required schema permissions (`SELECT/INSERT/UPDATE/DELETE` on owned tables).
- No `SUPERUSER` for applications.
- Restrict `CREATE`/`ALTER` to migration role.

## Credential Hygiene
- Store secrets in environment/secret manager, never in source control.
- Rotate passwords periodically and after incidents.
- Enforce strong password policy.

## Network and Encryption
- Enable TLS for PostgreSQL in production.
- Restrict inbound DB access by network policy/security groups.
- Use private networking between services and database.

## Backup Security
- Encrypt backups at rest.
- Encrypt backup transport.
- Limit restore permissions to controlled operators.

## Repository Hygiene
- Do not commit `.env` or secret files.
- Keep `.gitignore` updated for local env/log artifacts.

## Change Auditing
- Version all DDL with migrations.
- Audit critical table changes and privileged operations.
- Keep migration execution logs per environment.

## SQL Injection and Error Sanitization
- Use JPA repositories and parameterized queries only.
- Avoid dynamic SQL concatenation from user input.
- Return sanitized error payloads; do not expose SQL text, schema internals, or stack traces in production.