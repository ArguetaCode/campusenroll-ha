CREATE INDEX IF NOT EXISTS idx_students_email ON campusenroll.students (email);
CREATE INDEX IF NOT EXISTS idx_students_status ON campusenroll.students (status);

CREATE INDEX IF NOT EXISTS idx_courses_code ON campusenroll.courses (code);
CREATE INDEX IF NOT EXISTS idx_courses_course_code ON campusenroll.courses (course_code);

CREATE INDEX IF NOT EXISTS idx_course_sections_course_id ON campusenroll.course_sections (course_id);

CREATE INDEX IF NOT EXISTS idx_section_schedules_section_id ON campusenroll.section_schedules (section_id);

CREATE INDEX IF NOT EXISTS idx_enrollments_student_id ON campusenroll.enrollments (student_id);
CREATE INDEX IF NOT EXISTS idx_enrollments_section_id ON campusenroll.enrollments (section_id);
CREATE INDEX IF NOT EXISTS idx_enrollments_student_status ON campusenroll.enrollments (student_id, status);
CREATE INDEX IF NOT EXISTS idx_enrollments_student_section ON campusenroll.enrollments (student_id, section_id);

CREATE INDEX IF NOT EXISTS idx_payments_enrollment_id ON campusenroll.payments (enrollment_id);
CREATE INDEX IF NOT EXISTS idx_payments_student_id ON campusenroll.payments (student_id);

CREATE INDEX IF NOT EXISTS idx_notifications_student_id ON campusenroll.notifications (student_id);
CREATE INDEX IF NOT EXISTS idx_notifications_event_id ON campusenroll.notifications (event_id);