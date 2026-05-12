# Evidence Checklist

- [ ] `docker ps` mostrando contenedores de infraestructura y microservicios clave.
- [ ] Postman `GET http://localhost:8083/health` (billing).
- [ ] Postman `POST http://localhost:8083/payments` con resultado `APPROVED`.
- [ ] Postman `POST http://localhost:8083/payments` con resultado `FAILED`.
- [ ] PostgreSQL con registros en `campusenroll.payments`.
- [ ] Redis con keys `billing:payment:*:status`.
- [ ] RabbitMQ exchange `campusenroll.payments`.
- [ ] RabbitMQ queue `campusenroll.notifications.payments`.
- [ ] Postman `GET http://localhost:8084/health` (notification).
- [ ] Postman `GET http://localhost:8084/students/1/notifications`.
- [ ] PostgreSQL con registros en `campusenroll.notifications`.
- [ ] Prometheus targets (`http://localhost:9090/targets`) con billing y notification en `UP`.
- [ ] Grafana activo (`http://localhost:3000`).
