CREATE TABLE IF NOT EXISTS campusenroll.notifications (
    id BIGSERIAL PRIMARY KEY,
    student_id BIGINT NOT NULL,
    event_id VARCHAR(100) NOT NULL,
    event_type VARCHAR(100) NOT NULL,
    payment_id BIGINT NOT NULL,
    enrollment_id BIGINT NOT NULL,
    type VARCHAR(50) NOT NULL,
    message VARCHAR(500) NOT NULL,
    status VARCHAR(20) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uq_notifications_event_id UNIQUE (event_id)
);