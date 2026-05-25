# CampusEnroll HA

Arquitectura de microservicios para inscripcion universitaria con base de datos principal compartida.

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

## Migraciones (Flyway)

Las migraciones SQL versionadas viven en `database/migrations` y Flyway es el administrador de esquema.

## Flujo operativo (Fase 1)

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

## Base para API Gateway / Reverse Proxy (sin implementacion)

En esta fase no se implementa gateway, pero se deja preparada la base:

- Servicios ya exponen `health` y `prometheus`.
- URLs internas de `enrollment-service` son configurables por variables (`*_SERVICE_URL`).
- Puertos y contratos estan estables para enrutar trafico externo.

Propuesta de entrada unica para siguiente fase:

- `api.campusenroll.lan` (DNS interno o entrada en `hosts`).
- Ruteo sugerido:
  - `/students/**` -> `student-service`
  - `/courses/**` -> `course-service`
  - `/payments/**` -> `billing-service`
  - `/notifications/**` -> `notification-service`
  - `/api/enrollments/**` -> `enrollment-service`
- Capacidades objetivo del gateway/reverse proxy:
  - TLS terminacion
  - CORS centralizado
  - Rate limiting basico
  - Request logging y trazabilidad por `X-Request-ID`
  - Timeouts y manejo de errores consistente

Pendientes para activar gateway en siguiente fase:

- Definir tecnologia (Spring Cloud Gateway o Nginx/Traefik).
- Definir estrategia de autenticacion/autorizacion de borde.
- Definir politicas de rate limit por cliente.

## Fase 3 - Primera capa de entrada con Nginx

Se agrego un reverse proxy Nginx como punto unico de entrada en `:8080`.

- Servicio Compose: `campusenroll-api-gateway`
- Configuracion: `api-gateway/nginx.conf`
- Health del gateway: `GET /health`

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

## Configuracion de base de datos

- `spring.jpa.hibernate.ddl-auto` queda en modo seguro `validate` en los 5 servicios.
- Para cambios de esquema, usar Flyway (`database/migrations`).
- Solo si se requiere diagnostico local temporal, se puede sobreescribir con:

```bash
SPRING_JPA_HIBERNATE_DDL_AUTO=update
```

## Verificaciones

```bash
docker exec -it campusenroll-postgres psql -U campus -d campusenroll -c "SELECT installed_rank, version, description, success FROM campusenroll.flyway_schema_history ORDER BY installed_rank;"
docker exec -it campusenroll-postgres psql -U campus -d campusenroll -c "SELECT table_schema, table_name FROM information_schema.tables WHERE table_schema='campusenroll' ORDER BY table_name;"
docker exec -it campusenroll-postgres psql -U campus -d campusenroll -c "SELECT datname FROM pg_database ORDER BY datname;"
```

## Prueba k6 (recomendado)

```bash
cd campusenroll-ha
docker compose up -d campusenroll-postgres campusenroll-redis campusenroll-rabbitmq
docker compose --profile db-migration run --rm campusenroll-flyway
docker compose up -d --build
docker compose --profile testing run --rm -e GATEWAY_BASE_URL=http://campusenroll-api-gateway:8080 k6 run /scripts/load-test.js
```

## k6 por perfiles (gateway)

`tests/load-test.js` soporta perfiles:

- `smoke`: `5` VUs por `20s`
- `baseline`: `20` VUs por `60s`

Overrides disponibles:

- `TEST_PROFILE`
- `K6_VUS`
- `K6_DURATION`
- `GATEWAY_BASE_URL`
- `INCLUDE_NOTIFICATION_CHECK`
- `K6_THRESHOLD_FAILURE_RATE`
- `K6_THRESHOLD_P95_DURATION`
- `K6_THRESHOLD_CHECKS_RATE`

Ejemplos:

```bash
# smoke
docker compose --profile testing run --rm -e GATEWAY_BASE_URL=http://campusenroll-api-gateway:8080 -e TEST_PROFILE=smoke k6 run /scripts/load-test.js

# baseline
docker compose --profile testing run --rm -e GATEWAY_BASE_URL=http://campusenroll-api-gateway:8080 -e TEST_PROFILE=baseline k6 run /scripts/load-test.js

# override puntual
docker compose --profile testing run --rm -e GATEWAY_BASE_URL=http://campusenroll-api-gateway:8080 -e TEST_PROFILE=baseline -e K6_VUS=15 -e K6_DURATION=45s k6 run /scripts/load-test.js
```

## Script CI de k6

Script no destructivo para pipeline:

`scripts/k6-gateway-ci.ps1`

Caracteristicas:

- Ejecuta precheck con `gateway-smoke-ci.ps1` (puede omitirse con `-SkipGatewayPrecheck`).
- Corre k6 contra el gateway Nginx.
- Permite `smoke` y `baseline` + overrides de VUs/duracion.
- Exporta artefactos JSON (`summary` y `results`) en `artifacts/k6`.
- Aplica thresholds de k6 para pass/fail automatico.
- Valida de forma ligera el `summary-*.json` generado: JSON valido, metricas base y bloques de thresholds.
- Falla con codigo no-cero si hay error.

Uso:

```powershell
cd campusenroll-ha
powershell -ExecutionPolicy Bypass -File .\scripts\k6-gateway-ci.ps1 -TestProfile smoke
powershell -ExecutionPolicy Bypass -File .\scripts\k6-gateway-ci.ps1 -TestProfile baseline -K6Vus 25 -K6Duration 90s

# fail controlado para validar pass/fail automatico de thresholds en CI
powershell -ExecutionPolicy Bypass -File .\scripts\k6-gateway-ci.ps1 -TestProfile smoke -K6Vus 1 -K6Duration 5s -K6ThresholdChecksRate "rate>1"
```

## GitHub Actions

Workflow: `.github/workflows/campusenroll-ci.yml`

- `Smoke CI`: corre automaticamente en `push` y `pull_request`.
  - Valida `docker compose config`.
  - Ejecuta `scripts/gateway-smoke-ci.ps1`.
  - Ejecuta `scripts/k6-gateway-ci.ps1 -TestProfile smoke`.
  - Publica `artifacts/k6/*.json` como artifact del job.
- `Baseline Manual`: corre solo con `workflow_dispatch`.
  - Ejecuta `scripts/k6-gateway-ci.ps1 -TestProfile baseline`.
  - Publica `artifacts/k6/*.json` como artifact del job.

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
