# Swarm Failover Test Plan - CampusEnroll

This plan validates the first HA layer only: microservice orchestration and automatic re-scheduling with Docker Swarm.

## Preconditions

- 4 PCs joined to the same Swarm
- existing PostgreSQL, Redis, and RabbitMQ infra reachable from all Swarm nodes
- stack deployed with `docker-stack.yml`
- 2 replicas per microservice and gateway

## Baseline Checks

```powershell
docker node ls
docker service ls
docker stack services campusenroll
docker stack ps campusenroll
```

Gateway health:

```powershell
curl http://<NODE_IP>:8080/health
curl http://<NODE_IP>:8080/health/student-service
curl http://<NODE_IP>:8080/health/course-service
curl http://<NODE_IP>:8080/health/billing-service
curl http://<NODE_IP>:8080/health/notification-service
curl http://<NODE_IP>:8080/health/enrollment-service
```

Baseline smoke:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\gateway-smoke-ci.ps1 -GatewayBaseUrl http://<NODE_IP>:8080 -SwarmMode -StackName campusenroll
```

Baseline k6 smoke:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\k6-gateway-ci.ps1 -TestProfile smoke -GatewayHostBaseUrl http://<NODE_IP>:8080 -K6Script enrollment-flow-smoke.js -SkipGatewayPrecheck -SwarmMode -StackName campusenroll
```

## Failover Test: Drain a Node

1. Pick a node that currently hosts tasks.
2. Drain it:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\swarm\drain-node-test.ps1 -NodeName <NODE_NAME> -StackName campusenroll
```

3. Confirm tasks are rescheduled:

```powershell
docker stack ps campusenroll
docker stack services campusenroll
```

4. Re-run health checks.
5. Re-run smoke.
6. Re-run k6 smoke.

## Recovery

Return the node to active:

```powershell
docker node update --availability active <NODE_NAME>
```

Optional rebalance:
- Swarm does not immediately rebalance all existing tasks just because a node becomes active again.
- A rolling service update can gradually spread tasks later if needed.

## Success Criteria

- no service loses all replicas
- gateway `/health` stays reachable
- gateway upstream health endpoints still return `200`
- smoke passes after re-scheduling
- k6 smoke passes after re-scheduling

## What This Test Does Not Prove

- PostgreSQL HA
- RabbitMQ HA
- Redis HA
- disaster recovery
- zero downtime under every failure mode
