# CampusEnroll-HA LAN Lab Runbook

This guide prepares a small LAN lab without Kubernetes or Docker Swarm. It keeps the existing local Docker Compose workflow intact and does not claim production HA.

## Target Roles

| Role | Purpose | Example IP |
| --- | --- | --- |
| DB/infra primary | PostgreSQL primary, Redis, RabbitMQ, Prometheus, Grafana | `192.168.1.10` |
| Gateway | Nginx API gateway | `192.168.1.20` |
| Microservices A | student/course services | `192.168.1.30` |
| Microservices B | billing/notification/enrollment services | `192.168.1.31` |
| DB replica | Optional PostgreSQL HA Lab experiment, not production DR | `192.168.1.11` |

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
docker compose -f .\docker-compose.infra.yml up -d
docker compose -f .\docker-compose.infra.yml --profile db-migration run --rm campusenroll-flyway
```

## Microservice Node

On a node that runs services against central infra:

```powershell
Copy-Item .\env\lan-microservices.env.example .\.env
# Edit DB_HOST, REDIS_HOST, RABBITMQ_HOST, and service URLs.
docker compose -f .\docker-compose.microservices-a.yml up -d --build
```

For the other microservice group:

```powershell
docker compose -f .\docker-compose.microservices-b.yml up -d --build
```

Run only the services assigned to the node. Do not start a duplicate service on the same port unless the node has a different host port plan.

## Gateway Node

For local mode, keep `api-gateway/nginx.conf`.

For LAN failover experiments, you can either copy the example file and edit upstream IPs, or generate it from `.env` upstream lists.

```powershell
Copy-Item .\env\lan-gateway.env.example .\.env
# Edit *SERVICE_UPSTREAMS vars with the real service node IPs/ports.
powershell -ExecutionPolicy Bypass -File .\scripts\gateway-generate-nginx-lan.ps1 -OutputPath .\api-gateway\nginx.lan.generated.conf
```

Then start only the gateway role:

```powershell
$env:GATEWAY_NGINX_CONF = ".\\api-gateway\\nginx.lan.generated.conf"
docker compose -f .\docker-compose.gateway.yml up -d
```

The default `docker-compose.yml` stays local-safe; this workflow is for LAN labs.

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
- PostgreSQL HA Lab is isolated from the default Compose database and should not be mixed into a normal demo unless the demo is specifically about lab replication.

## Validation Checklist

- `docker compose config --quiet` passes on each node.
- LAN connectivity passes with `Test-NetConnection <ip> -Port <port>`.
- Gateway `/health/*` endpoints return service health.
- Flyway history shows all expected migrations as successful.
- Smoke test passes from the gateway node with `scripts/gateway-smoke-ci.ps1`.
- k6 uses only `smoke`; no performance or 50,000-request run is part of this lab.
- A backup is created and restored into an isolated PostgreSQL instance before any failover exercise is considered successful.
