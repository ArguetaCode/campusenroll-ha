# PostgreSQL HA LAN con Patroni, etcd y HAProxy

Este runbook implementa PostgreSQL HA para CampusEnroll usando solo las IPs LAN reales `192.168.0.x`.

No usa Docker Swarm, Redis HA, RabbitMQ HA, Kafka HA, datasource read/write ni outbox.

## Arquitectura

| Rol | Hostname | IP | Servicios |
| --- | --- | --- | --- |
| DB1 / Jared | `arg-service` | `192.168.0.12` | PostgreSQL, Patroni, etcd |
| DB2 / Mefi | `mefi04` | `192.168.0.10` | PostgreSQL, Patroni, etcd |
| DB3 / Brayan | `brayan-service` | `192.168.0.11` | PostgreSQL, Patroni, etcd |
| APP / PC Extra | `arguetacode` | `192.168.0.13` | HAProxy, gateway, microservicios, RabbitMQ, Redis, backups |

Endpoint estable para escritura:

```env
SPRING_DATASOURCE_URL=jdbc:postgresql://192.168.0.13:5000/campusenroll
SPRING_DATASOURCE_USERNAME=campus
SPRING_DATASOURCE_PASSWORD=campus123
```

Los microservicios no deben conectarse directo a `192.168.0.12`, `192.168.0.10` ni `192.168.0.11`.

## Puertos

DB nodes:

- `2379`: etcd client
- `2380`: etcd peer
- `5432`: PostgreSQL gestionado por Patroni
- `8008`: Patroni REST API

PC Extra:

- `5000`: HAProxy PostgreSQL write endpoint
- `7000`: HAProxy stats

## Archivos

- `docker-compose.patroni.yml`: perfiles `jared`, `mefi`, `brayan`.
- `docker-compose.haproxy.yml`: HAProxy en PC Extra.
- `patroni/jared/patroni.yml`, `patroni/mefi/patroni.yml`, `patroni/brayan/patroni.yml`: configuración por nodo.
- `haproxy/haproxy.cfg`: health check `GET /primary` contra Patroni.
- `env/patroni-*.env.example` y `env/haproxy.env.example`: variables operativas.
- `scripts/patroni/*`: validación, firewall, backup y recuperación de emergencia.

## Preparación en las 4 PCs

En cada PC, clonar o actualizar este repo y abrir firewall:

```bash
cd campusenroll-ha
./scripts/patroni/open-firewall-postgres-ha.sh
```

Verificar conectividad:

```bash
ping -c 2 192.168.0.12
ping -c 2 192.168.0.10
ping -c 2 192.168.0.11
ping -c 2 192.168.0.13
nc -vz 192.168.0.12 2379 2380 5432 8008
nc -vz 192.168.0.10 2379 2380 5432 8008
nc -vz 192.168.0.11 2379 2380 5432 8008
nc -vz 192.168.0.13 5000 7000
```

## Levantar DB1 / Jared

En `arg-service` (`192.168.0.12`):

```bash
cd campusenroll-ha
docker compose --profile jared -f docker-compose.patroni.yml up -d etcd-jared patroni-jared
docker logs -f etcd-jared
docker logs -f patroni-jared
```

## Levantar DB2 / Mefi

En `mefi04` (`192.168.0.10`):

```bash
cd campusenroll-ha
docker compose --profile mefi -f docker-compose.patroni.yml up -d etcd-mefi patroni-mefi
docker logs -f etcd-mefi
docker logs -f patroni-mefi
```

## Levantar DB3 / Brayan

En `brayan-service` (`192.168.0.11`):

```bash
cd campusenroll-ha
docker compose --profile brayan -f docker-compose.patroni.yml up -d etcd-brayan patroni-brayan
docker logs -f etcd-brayan
docker logs -f patroni-brayan
```

## Levantar HAProxy en PC Extra

En `arguetacode` (`192.168.0.13`):

```bash
cd campusenroll-ha
docker compose -f docker-compose.haproxy.yml up -d
docker logs -f campusenroll-postgres-haproxy
```

Validar:

```bash
curl http://192.168.0.12:8008/patroni
curl http://192.168.0.10:8008/patroni
curl http://192.168.0.11:8008/patroni
curl http://192.168.0.13:7000/
PGPASSWORD=campus123 psql -h 192.168.0.13 -p 5000 -U campus -d campusenroll -c "SELECT inet_server_addr(), pg_is_in_recovery();"
```

`pg_is_in_recovery()` debe devolver `f` cuando se entra por HAProxy, porque HAProxy solo enruta al primary.

## Microservicios

Usar estos valores en la PC Extra:

```env
DB_HOST=192.168.0.13
DB_PORT=5000
DB_NAME=campusenroll
DB_USER=campus
DB_PASSWORD=campus123
SPRING_DATASOURCE_URL=jdbc:postgresql://192.168.0.13:5000/campusenroll
SPRING_DATASOURCE_USERNAME=campus
SPRING_DATASOURCE_PASSWORD=campus123
```

Después levantar gateway, microservicios, RabbitMQ y Redis con los compose actuales del proyecto. Esta tarea no convierte RabbitMQ, Redis ni Kafka a HA.

## Backups a PC Extra

Crear backup desde el endpoint HAProxy:

```bash
cd campusenroll-ha
./scripts/patroni/backup-to-emergency-node.sh
```

Variables útiles:

```bash
POSTGRES_HOST=192.168.0.13
POSTGRES_PORT=5000
POSTGRES_DB=campusenroll
POSTGRES_USER=campus
POSTGRES_PASSWORD=campus123
EMERGENCY_HOST=192.168.0.13
EMERGENCY_USER=<usuario-linux-pc-extra>
```

## Modo emergencia en PC Extra

Si caen DB1, DB2 y DB3 al mismo tiempo, no hay failover automático. En ese escenario se restaura un backup en PC Extra:

```bash
cd campusenroll-ha
./scripts/patroni/restore-emergency-on-pc4.sh ./database/backups/<backup>.dump
```

El script publica PostgreSQL de emergencia en `192.168.0.13:55432` por defecto. Mientras dure la recuperación:

```env
SPRING_DATASOURCE_URL=jdbc:postgresql://192.168.0.13:55432/campusenroll
```

Este modo es recuperación operativa, no HA normal.

## Validación estática

```bash
docker compose -f docker-compose.patroni.yml config --quiet
docker compose -f docker-compose.haproxy.yml config --quiet
```

## Riesgos y límites

- El quorum real de etcd requiere que al menos 2 de 3 nodos DB sigan vivos.
- Si fallan DB1, DB2 y DB3, Patroni no puede promover nada.
- Las contraseñas de ejemplo deben cambiarse antes de producción real.
- HAProxy expone solo endpoint de escritura; no hay split read/write.
- Los backups no reemplazan PITR completo con WAL archive externo.
- La imagen de Patroni debe validarse en cada PC con acceso al registry antes del día de demo.
