# Docker Swarm 4-Node HA - CampusEnroll

This phase adds orchestration and automatic microservice re-scheduling with Docker Swarm. It does not implement PostgreSQL HA, RabbitMQ HA, Redis HA, or disaster recovery automation.

## What Swarm Solves

- replicated microservices across multiple PCs
- rescheduling tasks when a node is drained or unavailable
- a replicated API gateway behind the Swarm ingress mesh
- centralized service lifecycle with `docker stack deploy`

## What Swarm Does Not Solve

- automatic PostgreSQL primary failover
- RabbitMQ cluster HA
- Redis Sentinel/cluster failover
- zero downtime in every failure mode
- cross-service data consistency guarantees

## Recommended 4-PC Layout

| PC | Swarm role | Recommended workload |
| --- | --- | --- |
| PC 1 | Manager | can run microservices and current infra if needed |
| PC 2 | Manager | can run microservices |
| PC 3 | Manager | can run microservices |
| PC 4 | Worker | extra capacity for gateway and replicas |

Use 3 managers to keep Swarm quorum. Use PC 4 primarily for extra replica capacity and failover headroom.

## Files

- `docker-stack.yml`
- `env/swarm.env.example`
- `api-gateway/nginx.swarm.conf`
- `scripts/swarm/*.ps1`

## Infra in This Phase

PostgreSQL, Redis, and RabbitMQ remain external to Swarm in this phase. The stack consumes them through configurable endpoints:

- `DB_HOST`
- `DB_PORT`
- `REDIS_HOST`
- `REDIS_PORT`
- `RABBITMQ_HOST`
- `RABBITMQ_PORT`

Recommended first use: point these to the existing LAN infra node.

## Build and Image Distribution

`docker stack deploy` does not build images. Every node must be able to pull the images referenced in `env/swarm.env`.

Recommended options:

1. Push images to a registry reachable by all 4 PCs.
2. Or manually load the same images into each node for a controlled lab.

The helper script `scripts/swarm/deploy-stack.ps1 -BuildImages` builds local images on the manager, but that alone is not enough for multi-node pulls unless the workers can also access those image references.

## Start the Cluster

On PC 1:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\swarm\init-manager.ps1 -AdvertiseAddress 192.168.1.10
```

Take note of the manager and worker join tokens printed by the script.

## Join the Other PCs

On PC 2 and PC 3 as managers:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\swarm\join-manager.ps1 -ManagerToken <TOKEN> -ManagerAddress 192.168.1.10:2377 -AdvertiseAddress <THIS_PC_IP>
```

On PC 4 as worker:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\swarm\join-worker.ps1 -WorkerToken <TOKEN> -ManagerAddress 192.168.1.10:2377 -AdvertiseAddress <THIS_PC_IP>
```

## Deploy the Stack

1. Copy `env/swarm.env.example` to `env/swarm.env`.
2. Replace image names and infra endpoints.
3. Deploy from a manager:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\swarm\deploy-stack.ps1 -StackName campusenroll -EnvFile .\env\swarm.env
```

Or build local images before deploy:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\swarm\deploy-stack.ps1 -StackName campusenroll -EnvFile .\env\swarm.env -BuildImages
```

## Check Cluster State

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\swarm\check-cluster.ps1 -StackName campusenroll
```

Core commands:

```powershell
docker node ls
docker service ls
docker stack services campusenroll
docker stack ps campusenroll
```

## Gateway in Swarm

The stack publishes the gateway through the Swarm ingress mesh:

- `api-gateway` replicas: 2
- published port: `8080` by default

Traffic can be sent to any reachable node IP on the published gateway port.

Gateway config for this phase:

- `api-gateway/nginx.swarm.conf`

It routes to internal Swarm DNS service names:

- `student-service`
- `course-service`
- `billing-service`
- `notification-service`
- `enrollment-service`

## Health Validation

```powershell
curl http://<NODE_IP>:8080/health
curl http://<NODE_IP>:8080/health/student-service
curl http://<NODE_IP>:8080/health/course-service
curl http://<NODE_IP>:8080/health/billing-service
curl http://<NODE_IP>:8080/health/notification-service
curl http://<NODE_IP>:8080/health/enrollment-service
```

## Failover Demonstration

Use a manager to drain one node and observe task re-scheduling:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\swarm\drain-node-test.ps1 -NodeName <NODE_NAME> -StackName campusenroll -ReactivateNode
```

Expected result:

- tasks on that node move to remaining active nodes
- gateway health endpoints continue responding
- smoke and k6 smoke continue working if enough healthy replicas remain

## Post-Failover Checks

Smoke:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\gateway-smoke-ci.ps1 -GatewayBaseUrl http://<NODE_IP>:8080 -SwarmMode -StackName campusenroll
```

k6 smoke:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\k6-gateway-ci.ps1 -TestProfile smoke -GatewayHostBaseUrl http://<NODE_IP>:8080 -K6Script enrollment-flow-smoke.js -SkipGatewayPrecheck -SwarmMode -StackName campusenroll
```

## Real Limits of This Phase

- PostgreSQL is still an external single primary in this phase.
- RabbitMQ is still a single cluster node in this phase.
- Redis is still a single node in this phase.
- Swarm can re-schedule stateless services, but stateful dependencies can still become SPOFs.
- Failover may still cause a few seconds of disruption during task replacement or ingress re-convergence.
