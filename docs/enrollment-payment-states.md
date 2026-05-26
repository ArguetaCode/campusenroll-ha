# Enrollment And Payment States

## Functional States

`enrollment-service` uses:

| Status | Meaning | Terminal |
| --- | --- | --- |
| `PENDING_PAYMENT` | A seat is reserved and the enrollment may receive one payment result. | No |
| `CONFIRMED` | An `APPROVED` payment was accepted and the seat was confirmed. | Yes |
| `PAYMENT_FAILED` | A payment failed or payment processing could not complete; the reserved seat is released. | Yes |
| `CANCELLED` | The enrollment was cancelled by a business operation. | Yes for payment processing |

`billing-service` uses:

| Status | Meaning |
| --- | --- |
| `PENDING` | Reserved for an asynchronous payment provider flow; not produced by the current synchronous endpoint. |
| `APPROVED` | Payment accepted. |
| `FAILED` | Payment rejected or simulated as failed. |

`CONFIRMED` is the current project equivalent of an enrolled/final enrollment. It is intentionally retained to avoid breaking existing API consumers.

## Allowed Transitions

| Current enrollment state | Payment outcome | New state | Seat action |
| --- | --- | --- | --- |
| `PENDING_PAYMENT` | `APPROVED` | `CONFIRMED` | Confirm reserved seat |
| `PENDING_PAYMENT` | `FAILED` | `PAYMENT_FAILED` | Release reserved seat |
| `PENDING_PAYMENT` | Payment processing error | `PAYMENT_FAILED` | Release reserved seat |

Repeated delivery of the same payment result is idempotent. A contradictory result, a different payment identifier for an already processed enrollment, or a payment result for `CANCELLED` is rejected as an invalid transition.

## Consistency Rules

- A new payment is accepted only for an existing enrollment belonging to the same student and currently in `PENDING_PAYMENT`.
- `billing-service` cannot create payments directly for arbitrary enrollment identifiers.
- A `CONFIRMED` enrollment always comes from a valid `APPROVED` payment with a payment reference.
- Database constraints restrict accepted status values and enforce the payment-to-enrollment relationship for new payment rows.

## Service Sequence

1. `enrollment-service` validates student, section, duplicates, schedule, and reserves a seat.
2. It persists `PENDING_PAYMENT` before requesting billing.
3. `billing-service` validates that pending enrollment, persists `APPROVED` or `FAILED`, and publishes the payment event.
4. `enrollment-service` applies the result once; synchronous response and RabbitMQ delivery use the same guarded transition rules.
