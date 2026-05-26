# Demo Local Segura

Esta guia muestra el flujo recomendado para demostrar CampusEnroll HA en una sola maquina usando Docker Compose y el gateway Nginx.

## 1. Preparar stack

Desde `campusenroll-ha`:

```powershell
docker compose config --quiet
docker compose up -d campusenroll-postgres campusenroll-redis campusenroll-rabbitmq
docker compose --profile db-migration run --rm campusenroll-flyway
docker compose up -d --build
docker compose ps
```

No usar `docker compose down -v`; ese comando borra volumenes y puede eliminar datos de PostgreSQL.

## 2. Verificar gateway y servicios

```powershell
curl http://localhost:8080/health
curl http://localhost:8080/health/student-service
curl http://localhost:8080/health/course-service
curl http://localhost:8080/health/enrollment-service
curl http://localhost:8080/health/billing-service
curl http://localhost:8080/health/notification-service
```

Resultado esperado: respuestas con estado `UP`.

## 3. Crear datos base

Crear estudiante:

```powershell
$student = Invoke-RestMethod -Uri "http://localhost:8080/students" -Method POST -ContentType "application/json" -Body '{"fullName":"Demo Student","email":"demo.student@campusenroll.local","status":"ACTIVE"}'
```

Crear curso:

```powershell
$course = Invoke-RestMethod -Uri "http://localhost:8080/courses" -Method POST -ContentType "application/json" -Body '{"courseCode":"DEMO-DB2","name":"Base de Datos 2 Demo","description":"Curso demo","status":"ACTIVE"}'
```

Crear seccion:

```powershell
$sectionBody = @{
  courseId = $course.id
  sectionCode = "A"
  maxCapacity = 2
  status = "ACTIVE"
  schedules = @(
    @{
      dayOfWeek = "MONDAY"
      startTime = "08:00:00"
      endTime = "09:00:00"
      classroom = "LAB-1"
    }
  )
} | ConvertTo-Json -Depth 5

$section = Invoke-RestMethod -Uri "http://localhost:8080/sections" -Method POST -ContentType "application/json" -Body $sectionBody
```

## 4. Probar pago aprobado

```powershell
$approvedBody = @{
  studentId = $student.id
  sectionId = $section.id
  amount = 250.00
  simulatePaymentFailure = $false
} | ConvertTo-Json

$approvedEnrollment = Invoke-RestMethod -Uri "http://localhost:8080/api/enrollments" -Method POST -ContentType "application/json" -Body $approvedBody
$approvedEnrollment
```

Resultado esperado: `status` igual a `CONFIRMED`.

## 5. Probar notificacion

```powershell
Start-Sleep -Seconds 2
Invoke-RestMethod -Uri "http://localhost:8080/students/$($student.id)/notifications" -Method GET
```

Resultado esperado: una notificacion relacionada con el pago aprobado.

## 6. Probar pago fallido

Crear otra seccion para evitar duplicado activo:

```powershell
$failedSectionBody = @{
  courseId = $course.id
  sectionCode = "B"
  maxCapacity = 1
  status = "ACTIVE"
  schedules = @()
} | ConvertTo-Json -Depth 5

$failedSection = Invoke-RestMethod -Uri "http://localhost:8080/sections" -Method POST -ContentType "application/json" -Body $failedSectionBody

$failedBody = @{
  studentId = $student.id
  sectionId = $failedSection.id
  amount = 250.00
  simulatePaymentFailure = $true
} | ConvertTo-Json

$failedEnrollment = Invoke-RestMethod -Uri "http://localhost:8080/api/enrollments" -Method POST -ContentType "application/json" -Body $failedBody
$failedEnrollment
```

Resultado esperado: `status` igual a `PAYMENT_FAILED` y cupo liberado.

## 7. Evidencia complementaria

- PostgreSQL: revisar tablas `enrollments`, `payments` y `notifications`.
- RabbitMQ UI: `http://localhost:15672`.
- Prometheus targets: `http://localhost:9090/targets`.
- Grafana: `http://localhost:3000`.

Para una lista completa, usar `docs/evidence-checklist.md`.
