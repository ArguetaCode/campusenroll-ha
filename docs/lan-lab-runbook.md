# CampusEnroll-HA LAN Lab Runbook

This guide prepares a LAN lab without Kubernetes or Docker Swarm. It keeps the existing local Docker Compose workflow intact.

## Target Roles

| Role | Purpose | Example IP |
| --- | --- | --- |
| DB/infra primary | PostgreSQL primary, Redis, RabbitMQ, Prometheus, Grafana | `192.168.1.10` |
| Gateway | Nginx API gateway | `192.168.1.20` |
| Microservices A | student/course services | `192.168.1.30` |
| Microservices B | billing/notification/enrollment services | `192.168.1.31` |
| DB replica | PostgreSQL streaming replica, future DR target | `192.168.1.11` |

Use static IPs or DHCP reservations. Validate firewall rules before testing application behavior.

## Required LAN Ports

- Gateway: `8080`
- Microservices: `8081` to `8085`
- PostgreSQL host port: `55432`
- Redis: `6379`
- RabbitMQ: `5672`
- RabbitMQ UI: `15672`
- Prometheus: `9090`
- Grafana: `3000`

## Environment Templates

Templates live in `env/`:

- `lan-infra.env.example`
- `lan-gateway.env.example`
- `lan-microservices.env.example`
- `lan-db-primary.env.example`
- `lan-db-replica.env.example`

Copy the relevant file to `.env` on each node and replace placeholders.

## Infra Node

On the infra node:

```powershell
Copy-Item .\env\lan-infra.env.example .\.env
# Edit .env with the node IP and real lab values.
docker compose up -d campusenroll-postgres campusenroll-redis campusenroll-rabbitmq campusenroll-prometheus campusenroll-grafana
docker compose --profile db-migration run --rm campusenroll-flyway
```

## Microservice Node

On a node that runs services against central infra:

```powershell
Copy-Item .\env\lan-microservices.env.example .\.env
# Edit DB_HOST, REDIS_HOST, RABBITMQ_HOST, and service URLs.
docker compose up -d --build student-service course-service
```

Run only the services assigned to the node. Do not start a duplicate service on the same port unless the node has a different host port plan.

## Gateway Node

For local mode, keep `api-gateway/nginx.conf`.

For LAN failover experiments, copy the example and edit upstream IPs:

```powershell
Copy-Item .\api-gateway\examples\nginx.lan.example.conf .\api-gateway\nginx.lan.conf
# Edit nginx.lan.conf with real service node IPs.
```

Then temporarily point the Compose bind mount to `nginx.lan.conf` or run Nginx manually with that config. The default compose file remains local-safe and unchanged.

## Manual Service Failover

If a microservice node fails:

1. Confirm failure:

   ```powershell
   curl http://<FAILED_NODE_IP>:8081/actuator/health
   ```

2. Start the affected service on another node with the same central infra variables.

3. Update gateway upstreams if the new node IP is not already listed.

4. Reload or recreate only the gateway:

   ```powershell
   docker compose up -d campusenroll-api-gateway
   ```

5. Validate through gateway:

   ```powershell
   curl http://<GATEWAY_IP>:8080/health/student-service
   curl http://<GATEWAY_IP>:8080/students
   ```

## Limitations

- Compose `bridge` networking is single-host. Cross-node service routing depends on host IPs and published ports.
- Nginx OSS does not actively health-check upstreams. It marks failures during request handling using `max_fails`, `fail_timeout`, and `proxy_next_upstream`.
- The default Compose file uses fixed `container_name` values and fixed ports, which is fine for one instance per host but not for same-host horizontal scaling.
- PostgreSQL, Redis, RabbitMQ, and gateway are still single-instance unless separately deployed with HA patterns.

## Validation Checklist

- `docker compose config` passes on each node.
- LAN connectivity passes with `Test-NetConnection <ip> -Port <port>`.
- Gateway `/health/*` endpoints return service health.
- Flyway history shows all expected migrations as successful.
- Smoke test passes from the gateway node.
- A backup is created and restored into an isolated PostgreSQL instance before any failover exercise is considered successful.
