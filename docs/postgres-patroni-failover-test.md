# Prueba de failover Patroni en LAN

Objetivo: demostrar que si cae un nodo PostgreSQL individual, Patroni promueve una réplica y HAProxy sigue exponiendo un primary por `192.168.0.13:5000`.

## Precondiciones

Los tres nodos DB están arriba:

```bash
curl http://192.168.0.12:8008/patroni
curl http://192.168.0.10:8008/patroni
curl http://192.168.0.11:8008/patroni
```

HAProxy está arriba:

```bash
curl http://192.168.0.13:7000/
PGPASSWORD=campus123 psql -h 192.168.0.13 -p 5000 -U campus -d campusenroll -c "SELECT inet_server_addr(), pg_is_in_recovery();"
```

## Identificar primary

Desde cualquier PC con PowerShell:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\patroni\check-patroni-status.ps1
```

O con curl:

```bash
curl http://192.168.0.12:8008/patroni
curl http://192.168.0.10:8008/patroni
curl http://192.168.0.11:8008/patroni
```

El nodo con `"role": "primary"` es el que se debe detener para la prueba.

## Detener un primary

Ejemplo si el primary es Jared:

```bash
docker compose --profile jared -f docker-compose.patroni.yml stop patroni-jared
```

Ejemplo si el primary es Mefi:

```bash
docker compose --profile mefi -f docker-compose.patroni.yml stop patroni-mefi
```

Ejemplo si el primary es Brayan:

```bash
docker compose --profile brayan -f docker-compose.patroni.yml stop patroni-brayan
```

## Observar failover

Desde PC Extra o cualquier PC con acceso:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\patroni\failover-test.ps1
```

Validación manual:

```bash
watch -n 2 'curl -s http://192.168.0.12:8008/patroni; echo; curl -s http://192.168.0.10:8008/patroni; echo; curl -s http://192.168.0.11:8008/patroni; echo'
PGPASSWORD=campus123 psql -h 192.168.0.13 -p 5000 -U campus -d campusenroll -c "SELECT inet_server_addr(), pg_is_in_recovery();"
```

Resultado esperado:

- Uno de los nodos sobrevivientes cambia a `primary`.
- HAProxy deja de enviar tráfico al nodo caído.
- La conexión por `192.168.0.13:5000` vuelve a responder con `pg_is_in_recovery() = f`.

## Reiniciar el nodo caído

En la PC del nodo detenido:

```bash
docker compose --profile <jared|mefi|brayan> -f docker-compose.patroni.yml up -d
```

Patroni debe reinsertarlo como réplica. Si el timeline quedó divergente, `pg_rewind` queda habilitado para ayudar al rejoin.

## Prueba de pérdida total

No prometer failover automático si DB1, DB2 y DB3 caen juntos. Para demostrar el límite:

```bash
docker compose --profile jared -f docker-compose.patroni.yml stop patroni-jared etcd-jared
docker compose --profile mefi -f docker-compose.patroni.yml stop patroni-mefi etcd-mefi
docker compose --profile brayan -f docker-compose.patroni.yml stop patroni-brayan etcd-brayan
```

En ese caso usar recuperación de emergencia:

```bash
./scripts/patroni/restore-emergency-on-pc4.sh ./database/backups/<backup>.dump
```

Y apuntar temporalmente los microservicios a:

```env
SPRING_DATASOURCE_URL=jdbc:postgresql://192.168.0.13:55432/campusenroll
```
