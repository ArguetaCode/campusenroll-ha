CREATE SCHEMA IF NOT EXISTS campusenroll;

CREATE TABLE IF NOT EXISTS campusenroll.infrastructure_check (
    id SERIAL PRIMARY KEY,
    component VARCHAR(100) NOT NULL,
    status VARCHAR(50) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO campusenroll.infrastructure_check (component, status)
VALUES 
('postgresql', 'READY'),
('redis', 'CONFIGURED'),
('rabbitmq', 'CONFIGURED'),
('prometheus', 'CONFIGURED'),
('grafana', 'CONFIGURED');