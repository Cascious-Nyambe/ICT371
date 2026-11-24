-- ICT371 Q8 Transport Fleet Maintenance - PostgreSQL
-- (a)
CREATE TABLE vehicles (vehicle_id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY, registration VARCHAR(20) NOT NULL UNIQUE, current_odometer NUMERIC(12,2) NOT NULL CHECK (current_odometer >= 0), last_service_odometer NUMERIC(12,2) NOT NULL CHECK (last_service_odometer >= 0), CHECK (last_service_odometer <= current_odometer));
CREATE TABLE trips (trip_id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY, vehicle_id INT NOT NULL REFERENCES vehicles(vehicle_id), trip_on DATE NOT NULL, start_odometer NUMERIC(12,2) NOT NULL, end_odometer NUMERIC(12,2) NOT NULL);
CREATE TABLE service_alerts (vehicle_id INT PRIMARY KEY REFERENCES vehicles(vehicle_id), km_since_service NUMERIC(12,2) NOT NULL, flagged_on DATE NOT NULL DEFAULT CURRENT_DATE);
INSERT INTO vehicles (registration, current_odometer, last_service_odometer) VALUES ('ABC123', 10000, 9000), ('DEF456', 20000, 14000), ('GHI789', 5000, 5000);
-- (b)
CREATE OR REPLACE FUNCTION fn_service_due(p_vehicle_id INT) RETURNS BOOLEAN AS $$ DECLARE v_cur NUMERIC(12,2); v_last NUMERIC(12,2); BEGIN SELECT current_odometer, last_service_odometer INTO v_cur, v_last FROM vehicles WHERE vehicle_id = p_vehicle_id; IF v_cur IS NULL THEN RAISE EXCEPTION 'Unknown vehicle'; END IF; RETURN (v_cur - v_last) >= 5000; END; $$ LANGUAGE plpgsql;
-- (c) Procedure does NOT update vehicle odometer - trigger does
CREATE OR REPLACE PROCEDURE pr_record_trip(p_vehicle_id INT, p_trip_on DATE, p_start NUMERIC, p_end NUMERIC) AS $$ BEGIN IF NOT EXISTS (SELECT 1 FROM vehicles WHERE vehicle_id = p_vehicle_id) THEN RAISE EXCEPTION 'Unknown vehicle'; END IF; IF p_end <= p_start THEN RAISE EXCEPTION 'End must be greater than start'; END IF; INSERT INTO trips (vehicle_id, trip_on, start_odometer, end_odometer) VALUES (p_vehicle_id, p_trip_on, p_start, p_end); END; $$ LANGUAGE plpgsql;
-- (d)
CREATE OR REPLACE FUNCTION trg_trips_fn() RETURNS TRIGGER AS $$ DECLARE v_cur NUMERIC(12,2); BEGIN SELECT current_odometer INTO v_cur FROM vehicles WHERE vehicle_id = NEW.vehicle_id FOR UPDATE; IF v_cur IS NULL THEN RAISE EXCEPTION 'Unknown vehicle'; END IF; IF NEW.start_odometer <> v_cur THEN RAISE EXCEPTION 'Start must equal current odometer'; END IF; IF NEW.end_odometer <= NEW.start_odometer THEN RAISE EXCEPTION 'Invalid mileage'; END IF; UPDATE vehicles SET current_odometer = NEW.end_odometer WHERE vehicle_id = NEW.vehicle_id; RETURN NEW; END; $$ LANGUAGE plpgsql;
CREATE TRIGGER trg_trips BEFORE INSERT ON trips FOR EACH ROW EXECUTE FUNCTION trg_trips_fn();
-- Seed 6 trips through procedure after trigger
CALL pr_record_trip(1, '2026-11-20', 10000, 10500); CALL pr_record_trip(1, '2026-11-21', 10500, 11000); CALL pr_record_trip(2, '2026-11-20', 20000, 20500); CALL pr_record_trip(2, '2026-11-21', 20500, 21000); CALL pr_record_trip(3, '2026-11-20', 5000, 5500); CALL pr_record_trip(3, '2026-11-21', 5500, 6000);
-- (e)
CREATE VIEW v_service_due AS SELECT registration, (current_odometer - last_service_odometer) AS km_since_service FROM vehicles WHERE (current_odometer - last_service_odometer) >= 5000;
SELECT * FROM v_service_due;
-- (f) Composite: equality on vehicle_id + range on trip_on
CREATE INDEX idx_trips_vehicle_date ON trips (vehicle_id, trip_on);
EXPLAIN SELECT * FROM trips WHERE vehicle_id = 1 AND trip_on BETWEEN '2026-11-01' AND '2026-11-30';
-- (g)
CREATE OR REPLACE PROCEDURE pr_refresh_service_alerts() AS $$ BEGIN INSERT INTO service_alerts (vehicle_id, km_since_service, flagged_on) SELECT vehicle_id, current_odometer - last_service_odometer, CURRENT_DATE FROM vehicles WHERE (current_odometer - last_service_odometer) >= 5000 ON CONFLICT (vehicle_id) DO UPDATE SET km_since_service = EXCLUDED.km_since_service, flagged_on = CURRENT_DATE; DELETE FROM service_alerts WHERE vehicle_id IN (SELECT vehicle_id FROM vehicles WHERE (current_odometer - last_service_odometer) < 5000); END; $$ LANGUAGE plpgsql;
CREATE EXTENSION IF NOT EXISTS pg_cron;
SELECT cron.schedule('refresh_service_alerts', '0 6 * * 1', $$CALL pr_refresh_service_alerts()$$);
