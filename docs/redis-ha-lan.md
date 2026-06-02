# Redis HA en LAN

Esta fase agrega Redis HA para CampusEnroll usando 3 nodos Redis, 3 Sentinel y un endpoint estable por HAProxy en PC Extra. Redis HA queda aislado inicialmente: no cambia PostgreSQL HA, Patroni, etcd, RabbitMQ HA, HAProxy PostgreSQL, HAProxy RabbitMQ ni microservicios.

## Topologia

| Nodo | IP | Redis | Sentinel |
| --- | --- | --- | --- |
| Mefi | `192.168.0.10` | `redis-mefi:6379` | `redis-sentinel-mefi:26379` |
| Brayan | `192.168.0.11` | `redis-brayan:6379` | `redis-sentinel-brayan:26379` |
| Jared | `192.168.0.12` | `redis-jared:6379` | `redis-sentinel-jared:26379` |
| PC Extra | `192.168.0.13` | `campusenroll-redis-haproxy:6379` | HAProxy stats `:8405/stats` |

Nombre Sentinel del master:

```text
campusenroll-redis
```

Estado inicial esperado:

- Master inicial: `redis-jared` en `192.168.0.12:6379`
- Replicas iniciales: `redis-mefi` y `redis-brayan`
- Quorum Sentinel: `2`
- Endpoint compatible para microservicios, despues de validar: `192.168.0.13:6379`

## Que implementa

- `docker-compose.redis-ha.yml`: Redis y Sentinel por perfil (`jared`, `mefi`, `brayan`).
- `redis/redis-*.conf`: configuracion Redis por nodo LAN.
- `redis/sentinel-*.conf`: configuracion Sentinel por nodo LAN.
- `docker-compose.redis-haproxy.yml`: HAProxy Redis en PC Extra.
- `haproxy/redis-ha.cfg`: balancea solo al Redis que responde como `role:master`.

No se conectan microservicios a Redis HA todavia.

## Preparacion

Ejecutar en las 3 PCs Redis:

```bash
cd /home/arguetacode/Acadex/campusenroll-ha
docker compose --profile jared -f docker-compose.redis-ha.yml config --quiet
docker compose --profile mefi -f docker-compose.redis-ha.yml config --quiet
docker compose --profile brayan -f docker-compose.redis-ha.yml config --quiet
```

Ejecutar en PC Extra:

```bash
cd /home/arguetacode/Acadex/campusenroll-ha
docker compose -f docker-compose.redis-haproxy.yml config --quiet
```

Abrir firewall LAN en Mefi, Brayan y Jared:

```bash
sudo ufw allow from 192.168.0.0/24 to any port 6379 proto tcp
sudo ufw allow from 192.168.0.0/24 to any port 26379 proto tcp
```

Abrir firewall LAN en PC Extra:

```bash
sudo ufw allow from 192.168.0.0/24 to any port 6379 proto tcp
sudo ufw allow from 192.168.0.0/24 to any port 8405 proto tcp
```

Si PC Extra todavia corre el Redis local anterior (`campusenroll-redis`) y ocupa `6379`, no levantar HAProxy Redis hasta detener solo ese contenedor:

```bash
docker stop campusenroll-redis
```

No usar `down -v`.

## Levantar Redis HA por PC

### Jared `192.168.0.12`

Levantar primero Jared porque es el master inicial:

```bash
cd /home/arguetacode/Acadex/campusenroll-ha
docker compose --profile jared -f docker-compose.redis-ha.yml up -d redis-jared redis-sentinel-jared
```

Validar:

```bash
docker exec redis-jared redis-cli ping
docker exec redis-jared redis-cli info replication | grep -E 'role|connected_slaves|slave[0-9]'
docker exec redis-sentinel-jared redis-cli -p 26379 SENTINEL get-master-addr-by-name campusenroll-redis
```

### Mefi `192.168.0.10`

```bash
cd /home/arguetacode/Acadex/campusenroll-ha
docker compose --profile mefi -f docker-compose.redis-ha.yml up -d redis-mefi redis-sentinel-mefi
```

Validar:

```bash
docker exec redis-mefi redis-cli ping
docker exec redis-mefi redis-cli info replication | grep -E 'role|master_host|master_link_status'
docker exec redis-sentinel-mefi redis-cli -p 26379 SENTINEL get-master-addr-by-name campusenroll-redis
```

### Brayan `192.168.0.11`

```bash
cd /home/arguetacode/Acadex/campusenroll-ha
docker compose --profile brayan -f docker-compose.redis-ha.yml up -d redis-brayan redis-sentinel-brayan
```

Validar:

```bash
docker exec redis-brayan redis-cli ping
docker exec redis-brayan redis-cli info replication | grep -E 'role|master_host|master_link_status'
docker exec redis-sentinel-brayan redis-cli -p 26379 SENTINEL get-master-addr-by-name campusenroll-redis
```

### PC Extra `192.168.0.13`

Levantar HAProxy Redis solo despues de validar Redis/Sentinel:

```bash
cd /home/arguetacode/Acadex/campusenroll-ha
docker compose -f docker-compose.redis-haproxy.yml up -d campusenroll-redis-haproxy
```

Validar:

```bash
docker logs --tail 80 campusenroll-redis-haproxy
redis-cli -h 192.168.0.13 -p 6379 ping
redis-cli -h 192.168.0.13 -p 6379 info replication | grep role
curl http://192.168.0.13:8405/stats
```

## Validar master y replicas

Desde cualquier PC con acceso LAN:

```bash
redis-cli -h 192.168.0.12 -p 6379 info replication | grep -E 'role|connected_slaves|master_host|master_link_status'
redis-cli -h 192.168.0.10 -p 6379 info replication | grep -E 'role|connected_slaves|master_host|master_link_status'
redis-cli -h 192.168.0.11 -p 6379 info replication | grep -E 'role|connected_slaves|master_host|master_link_status'

redis-cli -h 192.168.0.12 -p 26379 SENTINEL master campusenroll-redis
redis-cli -h 192.168.0.12 -p 26379 SENTINEL replicas campusenroll-redis
redis-cli -h 192.168.0.12 -p 26379 SENTINEL sentinels campusenroll-redis
```

Probar escritura por HAProxy:

```bash
redis-cli -h 192.168.0.13 -p 6379 set campusenroll:redis-ha:probe "$(date -Is)"
redis-cli -h 192.168.0.13 -p 6379 get campusenroll:redis-ha:probe
```

## Probar failover

Ejemplo: detener el master inicial Jared.

### Jared `192.168.0.12`

```bash
cd /home/arguetacode/Acadex/campusenroll-ha
docker compose --profile jared -f docker-compose.redis-ha.yml stop redis-jared
```

### Mefi o Brayan

Esperar el failover y revisar el nuevo master:

```bash
redis-cli -h 192.168.0.10 -p 26379 SENTINEL get-master-addr-by-name campusenroll-redis
redis-cli -h 192.168.0.11 -p 26379 SENTINEL get-master-addr-by-name campusenroll-redis

redis-cli -h 192.168.0.13 -p 6379 info replication | grep role
redis-cli -h 192.168.0.13 -p 6379 set campusenroll:redis-ha:failover "$(date -Is)"
redis-cli -h 192.168.0.13 -p 6379 get campusenroll:redis-ha:failover
```

El endpoint `192.168.0.13:6379` debe seguir escribiendo porque HAProxy solo envia trafico al nodo que responde `role:master`.

## Devolver nodo caido

### Jared `192.168.0.12`

```bash
cd /home/arguetacode/Acadex/campusenroll-ha
docker compose --profile jared -f docker-compose.redis-ha.yml up -d redis-jared redis-sentinel-jared
```

Validar que Jared vuelva como replica si otro nodo quedo como master:

```bash
docker exec redis-jared redis-cli info replication | grep -E 'role|master_host|master_link_status'
docker exec redis-sentinel-jared redis-cli -p 26379 SENTINEL get-master-addr-by-name campusenroll-redis
```

Si Jared vuelve como master cuando Sentinel ya promovio otro nodo, esperar unos segundos y volver a consultar. Si no se reconfigura, forzar manualmente la replica al master reportado por Sentinel:

```bash
MASTER_IP=$(docker exec redis-sentinel-jared redis-cli -p 26379 SENTINEL get-master-addr-by-name campusenroll-redis | head -n 1)
docker exec redis-jared redis-cli replicaof "$MASTER_IP" 6379
docker exec redis-jared redis-cli config rewrite
```

## Variables para microservicios

No aplicar todavia. Cuando Redis HA este validado y se apruebe mover microservicios, usar el endpoint HAProxy compatible con la configuracion actual de Spring:

```env
REDIS_HOST=192.168.0.13
REDIS_PORT=6379
SPRING_REDIS_HOST=192.168.0.13
SPRING_REDIS_PORT=6379
```

Los microservicios actuales usan `spring.data.redis.host` y `spring.data.redis.port`; no hay configuracion Sentinel nativa todavia. Por eso esta fase usa HAProxy para mantener compatibilidad.

Servicios que usan Redis:

- `billing-service`: cache de estado e idempotencia de pagos.
- `notification-service`: acceso Redis por `StringRedisTemplate`.

## Riesgos y limites

- Redis Sentinel no evita perdida de escrituras ya aceptadas por el master y no replicadas antes de una caida.
- Quorum `2` requiere al menos dos Sentinels vivos para decidir failover.
- HAProxy Redis en PC Extra es el endpoint estable, pero en esta fase queda como punto unico para clientes Redis.
- Sin password Redis para mantener compatibilidad con la configuracion actual; limitar por firewall LAN.
- Los templates iniciales de Mefi y Brayan apuntan a Jared como master inicial. Despues de un failover, Sentinel debe reconfigurar roles; validar `info replication` antes de conectar microservicios.
- No usar `down -v` durante pruebas: eliminaria datos Redis/Sentinel de esta fase.

## Siguiente paso

1. Levantar Redis/Sentinel en Jared, Mefi y Brayan.
2. Validar master, replicas y quorum Sentinel.
3. Levantar HAProxy Redis en PC Extra.
4. Probar failover y retorno del nodo caido.
5. Solo despues, confirmar el cambio de microservicios a `192.168.0.13:6379`.
