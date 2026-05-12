CREATE TABLE IF NOT EXISTS campusenroll.enrollments (
    id BIGSERIAL PRIMARY KEY,
    student_id BIGINT NOT NULL,
    section_id BIGINT NOT NULL,
    status VARCHAR(30) NOT NULL,
    payment_reference VARCHAR(255),
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP,
    version BIGINT,
    CONSTRAINT uq_enrollments_student_section UNIQUE (student_id, section_id)
);