ALTER TABLE campusenroll.enrollments
    ADD CONSTRAINT chk_enrollments_status
    CHECK (status IN ('PENDING_PAYMENT', 'CONFIRMED', 'PAYMENT_FAILED', 'CANCELLED')) NOT VALID;

ALTER TABLE campusenroll.payments
    ADD CONSTRAINT chk_payments_status
    CHECK (status IN ('PENDING', 'APPROVED', 'FAILED')) NOT VALID;

ALTER TABLE campusenroll.payments
    ADD CONSTRAINT fk_payments_enrollment_id
    FOREIGN KEY (enrollment_id) REFERENCES campusenroll.enrollments (id) NOT VALID;
