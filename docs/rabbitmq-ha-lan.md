# RabbitMQ HA en LAN

Esta fase agrega RabbitMQ HA para CampusEnroll usando un cluster de 3 nodos en LAN y un endpoint unico por HAProxy en PC Extra. No cambia PostgreSQL HA, Patroni, etcd, Redis, Swarm ni la logica de negocio.

## Topologia

| Nodo | IP | Servicio |
| --- | --- | --- |
| Mefi | `192.168.0.10` | `rabbitmq-mefi` |
| Brayan | `192.168.0.11` | `rabbitmq-brayan` |
| Jared | `192.168.0.12` | `rabbitmq-jared` |
| PC Extra | `192.168.0.13` | `campusenroll-rabbitmq-haproxy` |

Endpoint recomendado para microservicios:

```env
RABBITMQ_HOST=192.168.0.13
RABBITMQ_PORT=5672
RABBITMQ_USERNAME=campus
RABBITMQ_PASSWORD=campus123
SPRING_RABBITMQ_HOST=192.168.0.13
SPRING_RABBITMQ_PORT=5672
SPRING_RABBITMQ_USERNAME=campus
SPRING_RABBITMQ_PASSWORD=campus123
```

Puertos usados por cada nodo RabbitMQ:

- `5672`: AMQP
- `15672`: Management UI
- `15692`: Prometheus metrics
- `4369`: epmd
- `25672`: Erlang distribution

## Que implementa

- `docker-compose.rabbitmq-ha.yml`: servicios RabbitMQ por perfil (`jared`, `mefi`, `brayan`).
- `rabbitmq/rabbitmq-ha.conf`: clustering estatico entre los 3 hosts.
- `docker-compose.rabbitmq-haproxy.yml`: HAProxy TCP/HTTP en PC Extra.
- `haproxy/rabbitmq-ha.cfg`: balanceo de AMQP, UI y metricas.

La configuracion usa:

- Usuario: `campus`
- Password: `campus123`
- Cookie Erlang compartida: `campusenroll-rabbitmq-ha-cookie`
- Nombres Erlang cortos: `rabbit@rabbitmq-jared`, `rabbit@rabbitmq-mefi`, `rabbit@rabbitmq-brayan`
- Resolucion LAN por `/etc/hosts` en cada PC y `extra_hosts` dentro de cada contenedor
- Puerto fijo de distribucion Erlang: `25672`
- `cluster_partition_handling = pause_minority`
- `default_queue_type = quorum`

Con `default_queue_type = quorum`, las colas nuevas declaradas por Spring como durables se crean como quorum queues sin cambiar codigo Java. Si ya existen colas classic en un broker anterior, no se convierten automaticamente: hay que migrarlas o recrearlas en el cluster nuevo.

## Preparacion

Ejecutar en las 3 PCs RabbitMQ. Esto corrige la resolucion desde el host Linux y tambien ayuda a validar conectividad antes de tocar RabbitMQ:

```bash
sudo cp /etc/hosts /etc/hosts.campusenroll-rabbitmq-ha.bak.$(date +%Y%m%d%H%M%S)
sudo sed -i '/rabbitmq-jared/d;/rabbitmq-mefi/d;/rabbitmq-brayan/d' /etc/hosts
cat <<'EOF' | sudo tee -a /etc/hosts
192.168.0.12 rabbitmq-jared
192.168.0.10 rabbitmq-mefi
192.168.0.11 rabbitmq-brayan
EOF

getent hosts rabbitmq-jared rabbitmq-mefi rabbitmq-brayan
ping -c 2 rabbitmq-jared
ping -c 2 rabbitmq-mefi
ping -c 2 rabbitmq-brayan
```

Validar el compose en cada PC con el perfil del nodo que corresponde:

```bash
cd /home/arguetacode/Acadex/campusenroll-ha
docker compose --profile jared -f docker-compose.rabbitmq-ha.yml config --quiet
docker compose --profile mefi -f docker-compose.rabbitmq-ha.yml config --quiet
docker compose --profile brayan -f docker-compose.rabbitmq-ha.yml config --quiet
```

Ejecutar en PC Extra:

```bash
cd /home/arguetacode/Acadex/campusenroll-ha
docker compose -f docker-compose.rabbitmq-haproxy.yml config --quiet
```

Abrir firewall LAN en Mefi, Brayan y Jared:

```bash
sudo ufw allow from 192.168.0.0/24 to any port 5672 proto tcp
sudo ufw allow from 192.168.0.0/24 to any port 15672 proto tcp
sudo ufw allow from 192.168.0.0/24 to any port 15692 proto tcp
sudo ufw allow from 192.168.0.0/24 to any port 4369 proto tcp
sudo ufw allow from 192.168.0.0/24 to any port 25672 proto tcp
```

Abrir firewall LAN en PC Extra:

```bash
sudo ufw allow from 192.168.0.0/24 to any port 5672 proto tcp
sudo ufw allow from 192.168.0.0/24 to any port 15672 proto tcp
sudo ufw allow from 192.168.0.0/24 to any port 15692 proto tcp
```

Si PC Extra todavia corre el RabbitMQ local anterior (`campusenroll-rabbitmq`), detener solo ese contenedor antes de levantar HAProxy porque ocupa `5672` y `15672`:

```bash
docker stop campusenroll-rabbitmq
```

No usar `down -v`.

## Levantar cluster por PC

### Jared `192.168.0.12`

```bash
cd /home/arguetacode/Acadex/campusenroll-ha
docker compose --profile jared -f docker-compose.rabbitmq-ha.yml up -d rabbitmq-jared
```

### Mefi `192.168.0.10`

```bash
cd /home/arguetacode/Acadex/campusenroll-ha
docker compose --profile mefi -f docker-compose.rabbitmq-ha.yml up -d rabbitmq-mefi
```

### Brayan `192.168.0.11`

```bash
cd /home/arguetacode/Acadex/campusenroll-ha
docker compose --profile brayan -f docker-compose.rabbitmq-ha.yml up -d rabbitmq-brayan
```

### PC Extra `192.168.0.13`

```bash
cd /home/arguetacode/Acadex/campusenroll-ha
docker compose -f docker-compose.rabbitmq-haproxy.yml up -d campusenroll-rabbitmq-haproxy
```

## Unir nodos al cluster

Si los tres nodos ya arrancaron como nodos individuales, corregir `/etc/hosts` no los une automaticamente. Mantener Jared como nodo semilla y reinicializar solo la metadata RabbitMQ de Mefi y Brayan para que se unan a `rabbit@rabbitmq-jared`.

### Jared `192.168.0.12`

```bash
docker exec rabbitmq-jared rabbitmq-diagnostics -q ping
docker exec rabbitmq-jared rabbitmqctl cluster_status
```

### Mefi `192.168.0.10`

```bash
docker exec rabbitmq-mefi rabbitmq-diagnostics -q ping
docker exec rabbitmq-mefi rabbitmqctl stop_app
docker exec rabbitmq-mefi rabbitmqctl reset
docker exec rabbitmq-mefi rabbitmqctl join_cluster rabbit@rabbitmq-jared
docker exec rabbitmq-mefi rabbitmqctl start_app
docker exec rabbitmq-mefi rabbitmqctl cluster_status
```

### Brayan `192.168.0.11`

```bash
docker exec rabbitmq-brayan rabbitmq-diagnostics -q ping
docker exec rabbitmq-brayan rabbitmqctl stop_app
docker exec rabbitmq-brayan rabbitmqctl reset
docker exec rabbitmq-brayan rabbitmqctl join_cluster rabbit@rabbitmq-jared
docker exec rabbitmq-brayan rabbitmqctl start_app
docker exec rabbitmq-brayan rabbitmqctl cluster_status
```

## Verificar cluster

Desde cualquier nodo RabbitMQ, por ejemplo Brayan:

```bash
docker exec rabbitmq-brayan rabbitmq-diagnostics -q ping
docker exec rabbitmq-brayan rabbitmq-diagnostics -q resolve_hostname rabbitmq-jared
docker exec rabbitmq-brayan rabbitmq-diagnostics -q resolve_hostname rabbitmq-mefi
docker exec rabbitmq-brayan rabbitmq-diagnostics -q resolve_hostname rabbitmq-brayan
docker exec rabbitmq-brayan rabbitmqctl cluster_status
docker exec rabbitmq-brayan rabbitmqctl list_users
```

El cluster debe mostrar:

```text
rabbit@rabbitmq-jared
rabbit@rabbitmq-mefi
rabbit@rabbitmq-brayan
```

Verificar puertos desde PC Extra:

```bash
nc -vz 192.168.0.10 5672 15672 15692 4369 25672
nc -vz 192.168.0.11 5672 15672 15692 4369 25672
nc -vz 192.168.0.12 5672 15672 15692 4369 25672
```

Verificar HAProxy RabbitMQ:

```bash
docker logs --tail 80 campusenroll-rabbitmq-haproxy
curl -u campus:campus123 http://192.168.0.13:15672/api/overview
curl http://192.168.0.13:15692/metrics | head
```

## Variables de microservicios

En el nodo donde corren microservicios, usar:

```env
RABBITMQ_HOST=192.168.0.13
RABBITMQ_PORT=5672
RABBITMQ_USERNAME=campus
RABBITMQ_PASSWORD=campus123
```

Luego recrear solo servicios que usan RabbitMQ:

```bash
cd /home/arguetacode/Acadex/campusenroll-ha
docker compose --env-file env/lan-microservices.env.example \
  -f docker-compose.microservices-b.yml \
  up -d --build billing-service notification-service enrollment-service

docker compose --env-file env/lan-microservices.env.example \
  -f docker-compose.gateway.yml \
  up -d --force-recreate campusenroll-api-gateway
```

No es necesario cambiar `student-service` ni `course-service` por RabbitMQ.

## Verificar exchanges, queues y quorum

Primero ejecutar el smoke real para que Spring declare exchanges, colas y bindings:

```bash
docker run --rm --network host \
  -v "$PWD/tests:/scripts:ro" \
  -e GATEWAY_BASE_URL=http://localhost:8080 \
  grafana/k6 run /scripts/enrollment-flow-smoke.js
```

Luego verificar topologia RabbitMQ:

```bash
docker exec rabbitmq-brayan rabbitmqctl list_exchanges name type durable | grep -E 'campusenroll|^name'
docker exec rabbitmq-brayan rabbitmqctl list_bindings source_name destination_name routing_key | grep -E 'campusenroll|payment|^source'
docker exec rabbitmq-brayan rabbitmqctl list_queues name durable type messages_ready messages_unacknowledged consumers
```

Las colas de pago/notificacion deben aparecer como `quorum` si fueron creadas por este cluster nuevo.

## Simular caida de un nodo RabbitMQ

Ejemplo: detener Mefi.

```bash
cd /home/arguetacode/Acadex/campusenroll-ha
docker compose --profile mefi -f docker-compose.rabbitmq-ha.yml stop rabbitmq-mefi
```

Verificar desde Brayan:

```bash
docker exec rabbitmq-brayan rabbitmqctl cluster_status
docker exec rabbitmq-brayan rabbitmqctl list_queues name type messages_ready messages_unacknowledged consumers
```

Validar que la app siga funcionando:

```bash
curl http://localhost:8080/health
curl http://localhost:8080/health/billing-service
curl http://localhost:8080/health/enrollment-service
curl http://localhost:8080/health/notification-service

docker run --rm --network host \
  -v "$PWD/tests:/scripts:ro" \
  -e GATEWAY_BASE_URL=http://localhost:8080 \
  grafana/k6 run /scripts/enrollment-flow-smoke.js
```

Reintegrar Mefi:

```bash
docker compose --profile mefi -f docker-compose.rabbitmq-ha.yml up -d rabbitmq-mefi
docker exec rabbitmq-mefi rabbitmqctl cluster_status
```

## Riesgos y limites

- RabbitMQ quorum queues toleran perdida de un nodo en un cluster de 3 mientras exista mayoria.
- Si dos nodos caen, las quorum queues pueden quedar no disponibles hasta recuperar quorum.
- PC Extra sigue siendo el endpoint unico para AMQP en esta fase. El cluster RabbitMQ queda HA, pero el HAProxy de RabbitMQ no esta duplicado todavia.
- No se implementa Redis HA en esta fase.
- No se implementa Docker Swarm en esta fase.
- No se modifica Patroni, etcd ni PostgreSQL.
- No se agrega Outbox Pattern; si RabbitMQ cae exactamente despues de persistir pago y antes de publicar evento, esa garantia transaccional sigue pendiente.
