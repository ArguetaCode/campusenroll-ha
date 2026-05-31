# CampusEnroll HA

Arquitectura de microservicios para inscripcion universitaria con base de datos principal compartida.

## Estado honesto de HA

El proyecto esta preparado para laboratorio local/LAN y failover manual simple, pero todavia no es alta disponibilidad real de produccion. PostgreSQL, Redis, RabbitMQ y el gateway siguen siendo instancias unicas por defecto.

## Estado actual del proyecto

Si existe actualmente:

- Microservicios Spring Boot funcionales para estudiantes, cursos, inscripciones, pagos y notificaciones.
- Docker Compose local con PostgreSQL, Redis, RabbitMQ, Nginx gateway, Prometheus, Grafana y k6.
- Migraciones Flyway versionadas.
- CI seguro con smoke tests y k6 smoke pequeno.
- Scripts de backup/restore y PostgreSQL HA Lab con advertencias y confirmaciones explicitas.

Todavia no existe:

- Alta disponibilidad real de produccion.
- Kubernetes, Docker Swarm, Patroni o failover automatico.
- Performance testing real o pruebas de 50,000 peticiones.
- Separacion database-per-service.
- Hardening productivo de secretos, TLS, monitoreo y alertas.

Documentos operativos nuevos:

- `docs/operational-baseline.md`: baseline seguro, puertos, health checks, Flyway y comandos peligrosos.
- `docs/demo-local.md`: flujo corto de demo local por gateway con pago aprobado, pago fallido y notificaciones.
- `docs/lan-lab-runbook.md`: guia por nodos LAN sin Kubernetes ni Docker Swarm.
- `docs/postgresql-ha-lab.md`: guia inicial de primaria/replica, streaming replication, WAL/PITR y promocion manual.
- `docs/postgresql-ha-lab-post-promotion.md`: flujo para reconstruir el laboratorio despues de promover una replica.
- `docs/database-backup-restore.md`: estrategia de backup/restore, retencion y restore drill.

## Decision de base de datos

Para este proyecto se adopta una sola base de datos PostgreSQL compartida:
- Database: `campusenroll`
- Schema: `campusenroll`
- Host local: `127.0.0.1:55432`
- Host Docker: `campusenroll-postgres:5432`

Todos los microservicios usan la misma conexion logica de base:
`jdbc:postgresql://campusenroll-postgres:5432/campusenroll`

No se usan `student_db`, `course_db` ni `enrollment_db`.

## Servicios y puertos

- `student-service`: `8081`
- `course-service`: `8082`
- `billing-service`: `8083`
- `notification-service`: `8084`
- `enrollment-service`: `8085`

## Infraestructura

- PostgreSQL: `55432:5432`
- Redis: `6379:6379`
- RabbitMQ: `5672:5672` y UI `15672`
- Prometheus: `9090`
- Grafana: `3000`

## Estabilidad Bajo Carga

- Los servicios Spring Boot tienen `healthcheck` via `/actuator/health` en `docker-compose.yml`.
- `depends_on` usa `condition: service_healthy` para evitar llamadas tempranas.
- `k6` depende del `campusenroll-api-gateway` saludable antes de iniciar.
- `billing-service` y otros servicios reducen logging SQL por defecto para evitar saturacion de stdout.
- En la fase actual, k6 se usa solo como smoke funcional pequeno. No representa una validacion de performance.

## Migraciones (Flyway)

Las migraciones SQL versionadas viven en `database/migrations` y Flyway es el administrador de esquema.

## Flyway Local Volume Note

Si Flyway falla con `Found non-empty schema(s) "campusenroll" but no schema history table`, normalmente existe un volumen PostgreSQL local creado antes de que Flyway administrara el esquema.

Este caso no indica por si solo un fallo del gateway ni de Docker Compose: el stack puede estar saludable, pero Flyway se detiene porque encuentra tablas existentes sin `campusenroll.flyway_schema_history`.

En CI con volumenes limpios no deberia ocurrir. Para tener un entorno local completamente gestionado por Flyway, la salida limpia es recrear manualmente el volumen PostgreSQL local despues de confirmar que no hay datos que se deban conservar. No se habilita `baselineOnMigrate` automaticamente para no ocultar drift real del esquema.

## Flujo operativo (Fase 1)

Comandos seguros: usar `up -d`, `run --rm` para Flyway/k6 y scripts `*-ci.ps1`. No usar `docker compose down -v` en entornos con datos.

### 1) Levantar solo infraestructura

```bash
cd campusenroll-ha
docker compose up -d campusenroll-postgres campusenroll-redis campusenroll-rabbitmq campusenroll-prometheus campusenroll-grafana
```

### 2) Ejecutar migraciones

```bash
docker compose --profile db-migration run --rm campusenroll-flyway
```

### 3) Levantar todos los microservicios

```bash
docker compose up -d --build student-service course-service billing-service notification-service enrollment-service
```

### 4) Levantar solo un microservicio

```bash
# Ejemplo: student-service
docker compose up -d --build student-service
```

### 5) Levantar todo en un solo comando (infra + servicios)

```bash
docker compose up -d --build
```

## Variables de entorno para LAN distribuida (Fase 2)

- Archivo base recomendado: `.env.lan.example`.
- Para uso real, crear `.env` en esta carpeta a partir de ese ejemplo y ajustar hosts/IP.
- Las aplicaciones aceptan variables genericas (`DB_*`, `REDIS_*`, `RABBITMQ_*`, `*_SERVICE_URL`) y mantienen compatibilidad con `SPRING_*`.
- La guia operativa completa A/B/C esta en la seccion `Guia operativa LAN A/B/C (Fase 2)`.

Ejemplo rapido:

```bash
cd campusenroll-ha
cp .env.lan.example .env
# editar .env con IPs/DNS reales de tu red LAN
docker compose up -d --build
```

## Guia operativa LAN A/B/C (Fase 2)

Objetivo: ejecutar CampusEnroll-HA en varias computadoras dentro de la misma red local sin Kubernetes.

### Requisitos de red

- IP fija o reserva DHCP para cada equipo.
- Puertos abiertos entre equipos:
  - PostgreSQL `55432` (host) / `5432` (contenedor)
  - Redis `6379`
  - RabbitMQ `5672` y opcional UI `15672`
  - Microservicios `8081..8085`
- Conectividad validada con `ping`/`Test-NetConnection` entre equipos.

### Computadora A (infraestructura central)

1. Clonar repo y entrar a `campusenroll-ha`.
2. Crear `.env` desde `.env.lan.example`.
3. Mantener en A:
   - `DB_HOST=campusenroll-postgres`
   - `REDIS_HOST=campusenroll-redis`
   - `RABBITMQ_HOST=campusenroll-rabbitmq`
4. Levantar infraestructura:

```bash
docker compose up -d campusenroll-postgres campusenroll-redis campusenroll-rabbitmq campusenroll-prometheus campusenroll-grafana
docker compose --profile db-migration run --rm campusenroll-flyway
```

5. (Opcional) Levantar tambien servicios en A:

```bash
docker compose up -d --build billing-service notification-service enrollment-service
```

### Computadora B (ejemplo: student-service)

Ejecutar el microservicio fuera de A (Docker o Maven local), apuntando a la infraestructura de A.

Variables minimas:

```env
SERVER_PORT=8081
DB_HOST=<IP-A>
DB_PORT=55432
DB_NAME=campusenroll
DB_USER=campus
DB_PASSWORD=campus123
```

Ejecucion ejemplo (Maven):

```bash
cd student-service
mvn spring-boot:run
```

### Computadora C (ejemplo: course-service)

Variables minimas:

```env
SERVER_PORT=8082
DB_HOST=<IP-A>
DB_PORT=55432
DB_NAME=campusenroll
DB_USER=campus
DB_PASSWORD=campus123
```

Ejecucion ejemplo (Maven):

```bash
cd course-service
mvn spring-boot:run
```

### Configuracion de enrollment-service en distribuido

Si `enrollment-service` corre en A o en otro host, debe resolver servicios remotos por URL LAN:

```env
SERVER_PORT=8085
DB_HOST=<IP-A>
DB_PORT=55432
DB_NAME=campusenroll
DB_USER=campus
DB_PASSWORD=campus123
RABBITMQ_HOST=<IP-A>
RABBITMQ_PORT=5672
RABBITMQ_USERNAME=campus
RABBITMQ_PASSWORD=campus123
STUDENT_SERVICE_URL=http://<IP-B>:8081
COURSE_SERVICE_URL=http://<IP-C>:8082
BILLING_SERVICE_URL=http://<IP-A>:8083
NOTIFICATION_SERVICE_URL=http://<IP-A>:8084
```

### Verificacion operativa A/B/C

Desde cualquier equipo con acceso:

```bash
curl http://<IP-B>:8081/actuator/health
curl http://<IP-C>:8082/actuator/health
curl http://<IP-A>:8083/actuator/health
curl http://<IP-A>:8084/actuator/health
curl http://<IP-A>:8085/actuator/health
```

```bash
curl http://<IP-A>:8085/actuator/prometheus
```

## API Gateway local con Nginx

Se agrego un reverse proxy Nginx como punto unico de entrada en `:8080`.

- Servicio Compose: `campusenroll-api-gateway`
- Configuracion: `api-gateway/nginx.conf`
- Health del gateway: `GET /health`
- Health por upstream: `GET /health/<service>`

### Flujo de entrada

`Cliente -> Nginx :8080 -> microservicios internos :8081..8085`

### Rutas publicadas en el gateway

- `/students/**` y `/api/students/**` -> `student-service:8081`
- `/courses/**` y `/sections/**` -> `course-service:8082`
- `/payments/**` -> `billing-service:8083`
- `/notifications/**` -> `notification-service:8084`
- `/api/enrollments/**` -> `enrollment-service:8085`
- `/api/students/{studentId}/enrollments` -> `enrollment-service:8085`

### Levantar con gateway

```bash
cd campusenroll-ha
docker compose up -d --build
```

### Verificacion rapida del gateway

```bash
curl http://localhost:8080/health
curl http://localhost:8080/students
curl http://localhost:8080/courses
curl http://localhost:8080/payments
curl http://localhost:8080/notifications
curl http://localhost:8080/api/enrollments
```

Si `8080` ya esta ocupado por otro proyecto local, usar un puerto alterno sin cambiar la configuracion interna del
gateway:

```powershell
$env:GATEWAY_PORT="18080"
docker compose up -d campusenroll-api-gateway campusenroll-nginx-exporter
powershell -ExecutionPolicy Bypass -File .\scripts\gateway-smoke-ci.ps1 -SkipFlyway -GatewayBaseUrl http://localhost:18080
powershell -ExecutionPolicy Bypass -File .\scripts\k6-gateway-ci.ps1 -TestProfile smoke -GatewayHostBaseUrl http://localhost:18080 -K6Script enrollment-flow-smoke.js -SkipGatewayPrecheck
```

## Configuracion de base de datos

- `spring.jpa.hibernate.ddl-auto` queda en modo seguro `validate` en los 5 servicios.
- Para cambios de esquema, usar Flyway (`database/migrations`).
- Solo si se requiere diagnostico local temporal, se puede sobreescribir con:

```bash
SPRING_JPA_HIBERNATE_DDL_AUTO=update
```

## Verificaciones

```bash
docker compose config --quiet
docker exec -it campusenroll-postgres psql -U campus -d campusenroll -c "SELECT installed_rank, version, description, success FROM campusenroll.flyway_schema_history ORDER BY installed_rank;"
docker exec -it campusenroll-postgres psql -U campus -d campusenroll -c "SELECT table_schema, table_name FROM information_schema.tables WHERE table_schema='campusenroll' ORDER BY table_name;"
docker exec -it campusenroll-postgres psql -U campus -d campusenroll -c "SELECT datname FROM pg_database ORDER BY datname;"
```

## Checklist de demo segura

Desde `campusenroll-ha`:

```powershell
docker compose config --quiet
docker compose up -d campusenroll-postgres campusenroll-redis campusenroll-rabbitmq
docker compose --profile db-migration run --rm campusenroll-flyway
docker compose up -d --build
powershell -ExecutionPolicy Bypass -File .\scripts\gateway-smoke-ci.ps1 -SkipFlyway
powershell -ExecutionPolicy Bypass -File .\scripts\k6-gateway-ci.ps1 -TestProfile smoke -SkipGatewayPrecheck
docker compose ps
```

Reglas para demo:

- No usar `docker compose down -v`.
- No borrar volumenes.
- No ejecutar perfiles k6 distintos de `smoke`.
- Usar PostgreSQL HA Lab solo si la demo es especificamente sobre replicacion de laboratorio.

## Prueba k6 smoke directa

```bash
cd campusenroll-ha
docker compose up -d campusenroll-postgres campusenroll-redis campusenroll-rabbitmq
docker compose --profile db-migration run --rm campusenroll-flyway
docker compose up -d --build
docker compose --profile testing run --rm -e GATEWAY_BASE_URL=http://campusenroll-api-gateway:8080 k6 run /scripts/load-test.js
```

Este comando crea pagos de prueba y mantiene el perfil smoke fijo. Para CI y demos repetibles se recomienda usar `scripts/k6-gateway-ci.ps1`.

## k6 smoke seguro (gateway)

`tests/load-test.js` soporta solo el perfil seguro actual:

- `smoke`: `5` VUs por `20s`

Los perfiles `baseline` y `volume50k` estan deshabilitados en esta fase del proyecto. k6 se usa solo para smoke funcional pequeno en CI/demo, no para performance ni carga masiva.

Overrides disponibles:

- `TEST_PROFILE`
- `GATEWAY_BASE_URL`
- `INCLUDE_NOTIFICATION_CHECK`
- `K6_THRESHOLD_FAILURE_RATE`
- `K6_THRESHOLD_P95_DURATION`
- `K6_THRESHOLD_CHECKS_RATE`

`K6_VUS`, `K6_DURATION`, `K6_SLEEP_SECONDS`, `K6_FLOW_VUS`, `K6_FLOW_ITERATIONS` y `K6_FLOW_MAX_DURATION` estan deshabilitados para evitar carga accidental.

Ejemplos:

```bash
# smoke
docker compose --profile testing run --rm -e GATEWAY_BASE_URL=http://campusenroll-api-gateway:8080 -e TEST_PROFILE=smoke k6 run /scripts/load-test.js
```

## Script CI de k6

Script no destructivo para pipeline:

`scripts/k6-gateway-ci.ps1`

Caracteristicas:

- Ejecuta precheck con `gateway-smoke-ci.ps1` (puede omitirse con `-SkipGatewayPrecheck`).
- Corre k6 contra el gateway Nginx.
- Permite solo `smoke`; bloquea `baseline`, `volume50k` y overrides de VUs/duracion.
- Exporta artefactos JSON (`summary` y `results`) en `artifacts/k6`.
- Aplica thresholds de k6 para pass/fail automatico.
- Valida de forma ligera el `summary-*.json` generado: JSON valido, metricas base y bloques de thresholds.
- Falla con codigo no-cero si hay error.

Uso:

```powershell
cd campusenroll-ha
powershell -ExecutionPolicy Bypass -File .\scripts\k6-gateway-ci.ps1 -TestProfile smoke
powershell -ExecutionPolicy Bypass -File .\scripts\k6-gateway-ci.ps1 -TestProfile smoke -K6Script enrollment-flow-smoke.js

# fail controlado para validar pass/fail automatico de thresholds en CI
powershell -ExecutionPolicy Bypass -File .\scripts\k6-gateway-ci.ps1 -TestProfile smoke -K6ThresholdChecksRate "rate>1"
```

## GitHub Actions

Workflow: `.github/workflows/campusenroll-ci.yml`

- `Smoke CI`: corre automaticamente en `push` y `pull_request`.
  - Valida `docker compose config --quiet`.
  - Ejecuta `scripts/gateway-smoke-ci.ps1`.
  - Ejecuta `scripts/k6-gateway-ci.ps1 -TestProfile smoke`.
  - Publica `artifacts/k6/*.json` como artifact del job.
- Requiere el secret `CAMPUSENROLL_CI_TOKEN` con permisos de lectura sobre los repos privados hermanos (`student-service`, `course-service`, `billing-service`, `notification`, `enrollment-service`).
- Si falta `CAMPUSENROLL_CI_TOKEN`, el workflow muestra una advertencia y omite el smoke completo que depende de repos privados. Las validaciones estaticas del repo `campusenroll-ha` siguen ejecutandose.

Nota local: el workflow vive en `.github/workflows/campusenroll-ci.yml` dentro del repo `campusenroll-ha`. Usa `docker compose config --quiet`, `gateway-smoke-ci.ps1` y k6 `smoke`. No usa `docker compose down -v`; al final solo detiene contenedores con `docker compose stop`.

## Smoke tests seguros

- `scripts/gateway-smoke-ci.ps1`: recomendado para CI y demos seguras. No borra volumenes.
- `scripts/gateway-smoke.ps1`: recomendado para ejecucion local manual. Es seguro por defecto y no borra volumenes.
- `scripts/gateway-smoke.ps1 -AllowDestructiveCleanup`: queda deshabilitado en el smoke test; falla con un mensaje claro para evitar borrado accidental de volumenes.

## k6 actual y prueba de flujo completo

`tests/load-test.js` sigue siendo la prueba principal de CI:

- Perfil `smoke`: 5 VUs por 20s.
- Cubre creacion de pagos via gateway.
- Puede consultar notificaciones si `INCLUDE_NOTIFICATION_CHECK=true`.
- No cubre por si sola el flujo completo de estudiante, curso, seccion, inscripcion, pago y notificacion.

Se agrega `tests/enrollment-flow-smoke.js` como smoke pequeno de flujo completo:

- Crea estudiante.
- Crea curso.
- Crea seccion con horario.
- Crea inscripcion con pago aprobado.
- Consulta notificaciones del estudiante.
- Esta pensado para demo/local controlado. Crea datos reales y queda limitado a 1 VU y 1 iteracion.

Uso seguro:

```powershell
docker compose up -d --build
docker compose --profile testing run --rm -e GATEWAY_BASE_URL=http://campusenroll-api-gateway:8080 k6 run /scripts/enrollment-flow-smoke.js
```

O con el runner de k6 para una demo controlada:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\k6-gateway-ci.ps1 -TestProfile smoke -K6Script enrollment-flow-smoke.js
```

## Limitaciones actuales

- El stack local sigue dependiendo de instancias unicas de PostgreSQL, Redis, RabbitMQ y Nginx.
- El PostgreSQL HA Lab esta aislado en `docker-compose.postgres-ha-lab.yml`; no reemplaza la base local ni prueba HA productiva.
- Los smoke tests crean datos de prueba en la base configurada.
- El CI valida arranque, migraciones, gateway y smoke k6; no valida carga masiva ni failover real.
- Los secretos por defecto son de laboratorio y no deben usarse en produccion.

## Ejecucion de un microservicio en otra computadora (LAN)

Para ejecutar un servicio fuera del host principal:

1. Exponer infraestructura central por IP fija/DNS interno (`postgres`, `rabbitmq`, `redis`).
2. Iniciar el microservicio remoto con variables apuntando al host central:
   - `DB_HOST=<HOST-CENTRAL>`
   - `RABBITMQ_HOST=<HOST-CENTRAL>`
   - `REDIS_HOST=<HOST-CENTRAL>`
   - En `enrollment-service`: `STUDENT_SERVICE_URL`, `COURSE_SERVICE_URL`, `BILLING_SERVICE_URL` hacia endpoints accesibles en red.
3. Verificar conectividad (`/actuator/health`) y scraping de metricas (`/actuator/prometheus`).

## Notas de evolucion

Esta decision de base compartida simplifica integracion, auditoria, backups, monitoreo y DR para el checkpoint. En una siguiente fase se puede evolucionar hacia `database-per-service` o schemas separados por dominio.
