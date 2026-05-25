# CampusEnroll HA CI Observability

## Prometheus Targets

Prometheus reads the following targets from `monitoring/prometheus.yml`:

- `billing-service:8083/actuator/prometheus`
- `notification-service:8084/actuator/prometheus`
- `student-service:8081/actuator/prometheus`
- `course-service:8082/actuator/prometheus`
- `enrollment-service:8085/actuator/prometheus`
- `campusenroll-rabbitmq:15692/metrics`
- `campusenroll-redis-exporter:9121/metrics`
- `campusenroll-postgres-exporter:9187/metrics`
- `campusenroll-nginx-exporter:9113/metrics`

RabbitMQ metrics require the `rabbitmq_prometheus` plugin, enabled by the Compose command for `campusenroll-rabbitmq`.

Grafana is provisioned with a Prometheus datasource and the `CampusEnroll Overview` dashboard from `monitoring/grafana/dashboards`.

## RabbitMQ Signals

Useful RabbitMQ metrics and diagnostic fields:

- `messages_ready`: queued messages waiting for consumers.
- `messages_unacknowledged`: messages delivered but not acknowledged.
- `consumers`: active queue consumers.
- `rabbitmq_queue_messages_ready`: Prometheus queue backlog.
- `rabbitmq_queue_messages_unacked`: Prometheus unacknowledged backlog.
- `rabbitmq_queue_consumers`: Prometheus consumer count.

During CI failures, `gateway-smoke-ci.ps1` and `k6-gateway-ci.ps1` print queue counts, payment exchange topology, payment bindings, and recent logs for gateway, billing, notification, enrollment, RabbitMQ, and Redis.

## Redis, PostgreSQL, and Gateway Signals

Useful Redis metrics:

- `redis_memory_used_bytes`: memory currently used by Redis.
- `redis_connected_clients`: active client connections.
- `redis_commands_processed_total`: command throughput source.

Useful PostgreSQL metrics:

- `pg_stat_database_numbackends`: active backend connections per database.
- `pg_stat_database_xact_commit` and `pg_stat_database_xact_rollback`: transaction activity.
- `pg_stat_database_blks_hit` and `pg_stat_database_blks_read`: cache hit/read signal.

Useful gateway metrics:

- `nginx_http_requests_total`: total requests seen by Nginx.
- `nginx_connections_active`: active gateway connections.
- `nginx_connections_waiting`: idle keepalive connections.

The gateway exposes `stub_status` at `/nginx_status` for the Nginx Prometheus exporter.

## k6 Smoke/Baseline Notes

k6 uses one `Idempotency-Key` per virtual user. This keeps the billing endpoint exercised while reducing RabbitMQ noise from repeated synthetic payments with nonexistent enrollment IDs.

The readiness preflight still creates a real synthetic payment and verifies that `notification-service` consumes the payment event and exposes it through `/students/{studentId}/notifications`.
