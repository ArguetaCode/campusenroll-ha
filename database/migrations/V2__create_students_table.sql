CREATE TABLE IF NOT EXISTS campusenroll.students (
    id BIGSERIAL PRIMARY KEY,
    student_code VARCHAR(30) NOT NULL,
    full_name VARCHAR(150) NOT NULL,
    email VARCHAR(120) NOT NULL,
    status VARCHAR(20) NOT NULL DEFAULT 'ACTIVE',
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uq_students_student_code UNIQUE (student_code),
    CONSTRAINT uq_students_email UNIQUE (email)
);