# CampusEnroll-HA Operational Baseline

Date: 2026-05-25

This document describes the current safe operating baseline for local and LAN lab demos. It is not a production HA certification. The current system is still a single Compose-based stack with manual recovery procedures.

## Services

Application services:

- `student-service`: student CRUD and student status.
- `course-service`: courses, sections, schedules, and seat reservation operations.
- `billing-service`: payment persistence, Redis cache, and RabbitMQ payment events.
- `notification-service`: payment-event consumer and notification persistence.
- `enrollment-service`: enrollment orchestration across student, course, billing, and payment events.

Infrastructure services:

- `campusenroll-postgres`: shared PostgreSQL database.
- `campusenroll-redis`: cache and idempotency support.
- `campusenroll-rabbitmq`: payment event broker.
- `campusenroll-api-gateway`: Nginx reverse proxy.
- `campusenroll-flyway`: schema migration runner.
- `campusenroll-prometheus`: metrics scraping.
- `campusenroll-grafana`: dashboards.
- `k6`: small smoke/load-test runner.

## Ports

| Component | Host port | Container port | Notes |
| --- | ---: | ---: | --- |
| API gateway | `8080` | `8080` | Main entry point |
| student-service | `8081` | `8081` | Direct service access |
| course-service | `8082` | `8082` | Direct service access |
| billing-service | `8083` | `8083` | Direct service access |
| notification-service | `8084` | `8084` | Direct service access |
| enrollment-service | `8085` | `8085` | Direct service access |
| PostgreSQL | `55432` | `5432` | Shared DB |
| Redis | `6379` | `6379` | Cache/idempotency |
| RabbitMQ | `5672` | `5672` | AMQP |
| RabbitMQ UI | `15672` | `15672` | Management UI |
| Prometheus | `9090` | `9090` | Metrics |
| Grafana | `3000` | `3000` | Dashboards |

## Safe Local Startup

From `campusenroll-ha`:

```powershell
docker compose config
docker compose up -d campusenroll-postgres campusenroll-redis campusenroll-rabbitmq
docker compose --profile db-migration run --rm campusenroll-flyway
docker compose up -d --build
```

This sequence is non-destructive. It keeps existing volumes and only starts or updates containers.

## Safe LAN Startup

Use the examples in `env/` as templates only. Copy one to `.env` on the target node and replace `192.168.x.x` placeholders with real static IPs or DNS names.

Recommended lab roles:

- DB/infra node: PostgreSQL, Redis, RabbitMQ, Prometheus, Grafana.
- Gateway node: Nginx gateway, pointing to reachable LAN service endpoints.
- Microservice node: one or more Spring Boot services.
- DB replica node: future PostgreSQL streaming replica.

## Health Checks

Gateway:

```powershell
curl http://localhost:8080/health
curl http://localhost:8080/health/student-service
curl http://localhost:8080/health/course-service
curl http://localhost:8080/health/billing-service
curl http://localhost:8080/health/notification-service
curl http://localhost:8080/health/enrollment-service
```

Direct services:

```powershell
curl http://localhost:8081/actuator/health
curl http://localhost:8082/actuator/health
curl http://localhost:8083/actuator/health
curl http://localhost:8084/actuator/health
curl http://localhost:8085/actuator/health
```

Container status:

```powershell
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
```

## Flyway Checks

Apply migrations:

```powershell
docker compose --profile db-migration run --rm campusenroll-flyway
```

Review applied migrations:

```powershell
docker exec campusenroll-postgres psql -U campus -d campusenroll -c "SELECT installed_rank, version, description, success FROM campusenroll.flyway_schema_history ORDER BY installed_rank;"
```

Review schema tables:

```powershell
docker exec campusenroll-postgres psql -U campus -d campusenroll -c "SELECT table_schema, table_name FROM information_schema.tables WHERE table_schema='campusenroll' ORDER BY table_name;"
```

## Safe Commands

Safe for local demo and LAN lab:

```powershell
docker compose config
docker compose ps
docker compose up -d
docker compose up -d --build
docker compose up -d campusenroll-postgres campusenroll-redis campusenroll-rabbitmq
docker compose --profile db-migration run --rm campusenroll-flyway
powershell -ExecutionPolicy Bypass -File .\scripts\gateway-smoke-ci.ps1
powershell -ExecutionPolicy Bypass -File .\scripts\gateway-smoke.ps1
powershell -ExecutionPolicy Bypass -File .\scripts\k6-gateway-ci.ps1 -TestProfile smoke
```

## Dangerous Commands

Do not run these against any environment with useful data:

```powershell
docker compose down -v
docker volume rm campusenroll-ha_campusenroll_pg_data
docker system prune --volumes
```

`docker compose down -v` deletes named volumes and can erase the PostgreSQL database. The local `gateway-smoke.ps1` now skips destructive cleanup by default. The only way to request a volume-deleting reset is:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\gateway-smoke.ps1 -AllowDestructiveCleanup
```

Use that only for disposable local resets, never for LAN, staging, demos with data, or CI.

## Current HA Reality

Current state:

- Services can be configured for LAN endpoints.
- Gateway can retry another upstream when multiple Nginx upstream servers are configured.
- PostgreSQL, RabbitMQ, Redis, and gateway are still single instances by default.
- Failover is manual and documented, not automatic.

This is readiness work for a LAN lab. It is not yet real production-grade high availability.
