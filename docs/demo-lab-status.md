# CampusEnroll-HA Demo/Lab Phase Status

Fecha de cierre: 2026-05-31

Este documento resume el estado validado de la fase demo/laboratorio. No describe una arquitectura HA productiva.

## Estado actual

- Stack local con Docker Compose funcional usando gateway en `http://localhost:18080` cuando el puerto `8080` esta ocupado.
- Microservicios principales levantan y responden por el gateway:
  - `student-service`
  - `course-service`
  - `billing-service`
  - `notification-service`
  - `enrollment-service`
- Nginx API Gateway enruta endpoints de negocio y health checks por servicio.
- Flyway esta en version `10` segun `campusenroll.flyway_schema_history`.
- Prometheus reporta targets `up` para gateway/exporters, servicios, PostgreSQL, Redis y RabbitMQ.
- PostgreSQL HA Lab esta aislado del stack normal con primary/replica en puertos `55433` y `55434`.

## Validaciones ejecutadas

Comandos validados:

```powershell
$env:GATEWAY_PORT="18080"
docker compose config --quiet
docker compose --profile testing config --quiet
docker exec campusenroll-api-gateway nginx -t
```

Health checks validados:

```powershell
Invoke-WebRequest http://localhost:18080/health
Invoke-WebRequest http://localhost:18080/health/student-service
Invoke-WebRequest http://localhost:18080/health/course-service
Invoke-WebRequest http://localhost:18080/health/billing-service
Invoke-WebRequest http://localhost:18080/health/notification-service
Invoke-WebRequest http://localhost:18080/health/enrollment-service
```

Smoke y k6 validados:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\gateway-smoke-ci.ps1 -SkipFlyway -GatewayBaseUrl http://localhost:18080
powershell -ExecutionPolicy Bypass -File .\scripts\k6-gateway-ci.ps1 -TestProfile smoke -GatewayHostBaseUrl http://localhost:18080 -K6Script enrollment-flow-smoke.js -SkipGatewayPrecheck
```

PostgreSQL HA Lab validado:

```powershell
powershell -ExecutionPolicy Bypass -File .\database\scripts\postgres-ha-lab-status.ps1
powershell -ExecutionPolicy Bypass -File .\database\scripts\postgres-ha-lab-check-replication.ps1
```

Resultados esperados del lab:

- `postgres-primary-lab` running/healthy.
- `postgres-replica-lab` running/healthy.
- Primary: `pg_is_in_recovery() = false`.
- Replica: `pg_is_in_recovery() = true`.
- `pg_stat_replication` muestra replica en `streaming`.
- La escritura directa en replica es rechazada.

## Correcciones incluidas en esta fase

- `enrollment-service` evita confirmar el mismo cupo por dos caminos simultaneos mediante transiciones idempotentes con lock pesimista.
- `EnrollmentPaymentTransitionService` limpia el contexto JPA antes de bloquear y transicionar la inscripcion para leer estado fresco de PostgreSQL.
- `gateway-smoke-ci.ps1` reinicia de forma no destructiva el gateway despues de levantar/recrear servicios para refrescar upstream DNS de Docker Compose.
- `gateway-smoke-ci.ps1` usa `paymentReference` como `paymentId` para validar notificaciones.
- `k6-gateway-ci.ps1` y `gateway-smoke-ci.ps1` soportan gateway en puerto alterno mediante URL.
- El frontend consulta health por servicio y no solo el health general del gateway.
- `.gitignore` ignora artefactos de smoke/k6 generados localmente.

## Lo que NO representa produccion HA

- No hay failover automatico.
- No hay Kubernetes ni Docker Swarm.
- RabbitMQ, Redis, Nginx y Prometheus siguen siendo instancia unica.
- PostgreSQL HA Lab esta aislado; los microservicios siguen usando la base normal del stack local.
- No existe separacion read/write para trafico de aplicacion.
- No hay outbox transaccional (todavia). DLQ + retries basicos ya existen para eventos de pago/notificacion (ver `docs/rabbitmq-resilience-plan.md`).
- Las pruebas smoke y k6 crean datos reales de prueba en la base configurada.

## Riesgos pendientes

- La confirmacion de enrollment depende de eventos RabbitMQ; falta patron outbox/idempotencia completa para produccion.
- El gateway con Nginx OSS no tiene health checks activos nativos.
- El laboratorio PostgreSQL primary/replica no cubre failover automatico ni reconfiguracion transparente de clientes.
- Los scripts de reset del laboratorio deben usarse solo con banderas explicitas y nunca contra volumenes reales.
- Las pruebas k6 actuales son smoke de una iteracion, no pruebas de carga.

## Siguiente fase recomendada

1. Formalizar outbox, DLQ e idempotencia en billing/enrollment/notification.
2. Diseñar separacion read/write antes de conectar servicios al PostgreSQL HA Lab.
3. Agregar automatizacion controlada para reconstruccion post-promocion del lab.
4. Planificar HA real de gateway, RabbitMQ y Redis antes de hablar de produccion.
