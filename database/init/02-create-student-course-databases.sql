SELECT 'CREATE DATABASE student_db'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'student_db')\gexec

SELECT 'CREATE DATABASE course_db'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'course_db')\gexec
