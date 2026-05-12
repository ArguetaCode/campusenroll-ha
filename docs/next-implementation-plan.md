# Next Implementation Plan

Fecha de plan: 2026-05-08

## Estado incremental completado

Se completo de forma incremental `student-service` y `course-service` sin reescritura ni cambios destructivos.

### student-service completado

- `GET /health`
- `GET /students/{id}/status`
- `PATCH /students/{id}/status`
- Actuator Prometheus habilitado (`/actuator/prometheus`)

### course-service completado

- `GET /health`
- `GET /courses/{id}`
- `GET /sections/{id}/schedule`
- Actuator Prometheus habilitado (`/actuator/prometheus`)

## Que sigue ahora (siguiente foco)

1. `enrollment-service` hardening tecnico:
   - corregir ruta real del proyecto para compose profile `future`
   - alinear puerto `8085` en log/app/dockerfile
   - agregar `GET /health`
2. Implementar validacion de traslape horario en enrollment.
3. Ejecutar pruebas E2E del flujo de inscripcion con pago y notificacion.

## Riesgos tecnicos vigentes

- Estructura anidada y package con underscore en enrollment.
- Desalineacion de contratos HTTP finales entre rutas legacy `/api` y rutas planas.

## Comandos de prueba

```bash
cd D:/Proyectos/proyectos_propios/proyecto_BD/student-service
mvn clean compile

cd D:/Proyectos/proyectos_propios/proyecto_BD/course-service
mvn clean compile
```

```bash
cd D:/Proyectos/proyectos_propios/proyecto_BD/campusenroll-ha
docker compose up -d --build

# activar servicios pendientes
# docker compose --profile future up -d --build student-service course-service
```
