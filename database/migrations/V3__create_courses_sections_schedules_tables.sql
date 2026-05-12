CREATE TABLE IF NOT EXISTS campusenroll.courses (
    id BIGSERIAL PRIMARY KEY,
    code VARCHAR(30),
    course_code VARCHAR(30) NOT NULL,
    name VARCHAR(150) NOT NULL,
    description TEXT,
    status VARCHAR(20) NOT NULL DEFAULT 'ACTIVE',
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uq_courses_course_code UNIQUE (course_code),
    CONSTRAINT uq_courses_code UNIQUE (code)
);

CREATE TABLE IF NOT EXISTS campusenroll.course_sections (
    id BIGSERIAL PRIMARY KEY,
    course_id BIGINT NOT NULL,
    section_code VARCHAR(30) NOT NULL,
    capacity INT,
    max_capacity INT NOT NULL,
    reserved_seats INT NOT NULL DEFAULT 0,
    enrolled_seats INT,
    confirmed_seats INT NOT NULL DEFAULT 0,
    status VARCHAR(20) NOT NULL DEFAULT 'ACTIVE',
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uq_course_section UNIQUE (course_id, section_code)
);

CREATE TABLE IF NOT EXISTS campusenroll.section_schedules (
    id BIGSERIAL PRIMARY KEY,
    section_id BIGINT NOT NULL,
    day_of_week VARCHAR(20) NOT NULL,
    start_time TIME NOT NULL,
    end_time TIME NOT NULL,
    classroom VARCHAR(80),
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);