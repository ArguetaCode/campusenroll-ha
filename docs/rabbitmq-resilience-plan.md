# RabbitMQ Resilience Plan (DLQ + Retries)

Scope: lab/academic resilience for payment events. This is not production-grade HA for RabbitMQ.

## What is implemented

- Durable queues for payment events.
- Dead Letter Exchange (DLX): `campusenroll.dlx`.
- DLQ queues:
  - Notification: `campusenroll.notifications.payments.dlq`
  - Enrollment: `enrollment.payment.approved.dlq`, `enrollment.payment.failed.dlq`
- Consumer retry policy (Spring AMQP): 3 attempts, then reject (no requeue) so the message is dead-lettered.

## Where

- Notification service:
  - `notification/src/main/java/com/campusenroll/notification/config/RabbitMqConfig.java`
- Enrollment service:
  - `enrollment-service/enrollment-service/enrollment-service/src/main/java/com/campusenroll/enrollment_service/config/RabbitMqConfig.java`
  - `enrollment-service/enrollment-service/enrollment-service/src/main/resources/application.yaml`

## Operational checklist

- If you already ran the stack before DLQ was introduced, RabbitMQ may already have queues created *without* DLX arguments. In that case, Spring will fail declaring the new queue arguments with `PRECONDITION_FAILED - inequivalent arg 'x-dead-letter-exchange'`.
  - Lab-safe fix: delete the affected queues (and their bindings) in RabbitMQ UI, then restart the consumer services so they re-declare them with DLQ settings.
  - Alternative: use a fresh vhost for the lab environment.

- Confirm DLQ queues exist:
  - RabbitMQ UI: `http://<RABBITMQ_HOST>:15672`
- Validate consumer behavior:
  1. Force a controlled failure in a consumer (lab-only).
  2. Verify the message is not stuck in an infinite retry loop.
  3. Verify it appears in the corresponding `*.dlq` queue.
- Triage DLQ:
  - Inspect message payload + headers.
  - Identify the root cause (schema mismatch, idempotency bug, missing referenced data, etc.).
  - Decide: replay after fix vs. discard with justification.
