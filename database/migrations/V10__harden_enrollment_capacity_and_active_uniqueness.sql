ALTER TABLE campusenroll.enrollments
    DROP CONSTRAINT IF EXISTS uq_enrollments_student_section;

CREATE UNIQUE INDEX IF NOT EXISTS uq_enrollments_student_section_active
    ON campusenroll.enrollments (student_id, section_id)
    WHERE status IN ('PENDING_PAYMENT', 'CONFIRMED');

ALTER TABLE campusenroll.course_sections
    DROP CONSTRAINT IF EXISTS chk_course_sections_capacity_totals;

ALTER TABLE campusenroll.course_sections
    ADD CONSTRAINT chk_course_sections_capacity_totals
    CHECK (
        max_capacity >= 0
        AND reserved_seats >= 0
        AND confirmed_seats >= 0
        AND reserved_seats + confirmed_seats <= max_capacity
    ) NOT VALID;
