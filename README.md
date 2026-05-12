# CampusEnroll HA

CampusEnroll HA is a microservices architecture for university enrollment with limited seats, schedule validation, payment processing, asynchronous events, and observability.

## Implemented Services

- `billing-service` (`8083`): payment registration, Redis cache status, RabbitMQ event publishing.
- `notification-service` (`8084`): payment event consumption, notification persistence, idempotency, read status updates.
- `student-service` (`8081`): basic student CRUD (work in progress).
- `course-service` (`8082`): course/section/seat APIs (work in progress).
- `enrollment-service` (`8085`): enrollment orchestration with external integrations (work in progress).

## Infrastructure Components

- PostgreSQL: `localhost:55432` -> `campusenroll-postgres:5432`
- Redis: `localhost:6379` -> `campusenroll-redis:6379`
- RabbitMQ AMQP: `localhost:5672` -> `campusenroll-rabbitmq:5672`
- RabbitMQ UI: `http://localhost:15672` (user `campus`, pass `campus123`)
- Prometheus: `http://localhost:9090`
- Grafana: `http://localhost:3000`

## Docker Quick Start

```bash
cd campusenroll-ha
docker compose down -v
docker compose up -d --build
docker ps
```

## Microservice Ports

- `student-service`: `8081`
- `course-service`: `8082`
- `billing-service`: `8083`
- `notification-service`: `8084`
- `enrollment-service`: `8085`

## PostgreSQL Verification

```bash
docker exec -it campusenroll-postgres psql -U campus -d campusenroll -c "SELECT current_database(), current_user;"
docker exec -it campusenroll-postgres psql -U campus -d campusenroll -c "SELECT * FROM campusenroll.payments ORDER BY created_at DESC LIMIT 5;"
docker exec -it campusenroll-postgres psql -U campus -d campusenroll -c "SELECT * FROM campusenroll.notifications ORDER BY created_at DESC LIMIT 5;"
```

## Redis Verification

```bash
docker exec -it campusenroll-redis redis-cli KEYS "billing:payment:*:status"
docker exec -it campusenroll-redis redis-cli KEYS "notification:event:*"
```

## RabbitMQ Verification

- Open: `http://localhost:15672`
- Validate exchange: `campusenroll.payments`
- Validate queue: `campusenroll.notifications.payments`
- Validate bindings for routing keys:
  - `payment.approved`
  - `payment.failed`

## Prometheus and Grafana

- Prometheus targets page: `http://localhost:9090/targets`
- Grafana login (default): `admin/admin` (change on first access)

## End-to-End Flow (Billing -> RabbitMQ -> Notification)

1. Client calls `POST /payments` on `billing-service`.
2. `billing-service` stores payment in PostgreSQL (`campusenroll.payments`).
3. `billing-service` caches state in Redis (`billing:payment:{paymentId}:status`).
4. `billing-service` publishes event to exchange `campusenroll.payments` with:
   - `payment.approved` or `payment.failed`
5. `notification-service` consumes from queue `campusenroll.notifications.payments`.
6. `notification-service` applies idempotency key `notification:event:{eventId}` in Redis.
7. `notification-service` stores record in `campusenroll.notifications`.

## k6 Load Test

```bash
# billing only
k6 run tests/load-test.js

# billing + optional notification read check
INCLUDE_NOTIFICATION_CHECK=true k6 run tests/load-test.js
```

## Checkpoint Evidence Expectations

- All core containers up (`postgres`, `redis`, `rabbitmq`, `prometheus`, `grafana`, `billing`, `notification`).
- Health endpoints available for billing and notification.
- Payment insertions visible in PostgreSQL.
- Redis keys visible for billing status and notification idempotency.
- RabbitMQ exchange, queue, and bindings visible.
- Prometheus targets `UP` for billing and notification.
