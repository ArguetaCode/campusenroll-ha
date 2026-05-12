DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'fk_course_sections_course_id'
          AND connamespace = 'campusenroll'::regnamespace
    ) THEN
        ALTER TABLE campusenroll.course_sections
            ADD CONSTRAINT fk_course_sections_course_id
            FOREIGN KEY (course_id) REFERENCES campusenroll.courses (id) NOT VALID;
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'fk_section_schedules_section_id'
          AND connamespace = 'campusenroll'::regnamespace
    ) THEN
        ALTER TABLE campusenroll.section_schedules
            ADD CONSTRAINT fk_section_schedules_section_id
            FOREIGN KEY (section_id) REFERENCES campusenroll.course_sections (id) NOT VALID;
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'fk_enrollments_student_id'
          AND connamespace = 'campusenroll'::regnamespace
    ) THEN
        ALTER TABLE campusenroll.enrollments
            ADD CONSTRAINT fk_enrollments_student_id
            FOREIGN KEY (student_id) REFERENCES campusenroll.students (id) NOT VALID;
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'fk_enrollments_section_id'
          AND connamespace = 'campusenroll'::regnamespace
    ) THEN
        ALTER TABLE campusenroll.enrollments
            ADD CONSTRAINT fk_enrollments_section_id
            FOREIGN KEY (section_id) REFERENCES campusenroll.course_sections (id) NOT VALID;
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'chk_payments_amount_positive'
          AND connamespace = 'campusenroll'::regnamespace
    ) THEN
        ALTER TABLE campusenroll.payments
            ADD CONSTRAINT chk_payments_amount_positive
            CHECK (amount > 0) NOT VALID;
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'chk_section_schedules_time_window'
          AND connamespace = 'campusenroll'::regnamespace
    ) THEN
        ALTER TABLE campusenroll.section_schedules
            ADD CONSTRAINT chk_section_schedules_time_window
            CHECK (start_time < end_time) NOT VALID;
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'chk_course_sections_capacity_totals'
          AND connamespace = 'campusenroll'::regnamespace
    ) THEN
        ALTER TABLE campusenroll.course_sections
            ADD CONSTRAINT chk_course_sections_capacity_totals
            CHECK (
                COALESCE(enrolled_seats, confirmed_seats, 0) + COALESCE(reserved_seats, 0)
                <= COALESCE(capacity, max_capacity)
            ) NOT VALID;
    END IF;
END $$;
