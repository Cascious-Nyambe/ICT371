-- ICT371 Q9 Farmer Cooperative Maize Deliveries - PostgreSQL
-- (a)
CREATE TABLE farmers (farmer_id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY, farmer_number VARCHAR(20) NOT NULL UNIQUE, full_name VARCHAR(100) NOT NULL);
CREATE TABLE deliveries (delivery_id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY, farmer_id INT NOT NULL REFERENCES farmers(farmer_id), grade CHAR(1) NOT NULL, weight_kg NUMERIC(12,2) NOT NULL, unit_rate NUMERIC(10,2) NOT NULL DEFAULT 0, total_value NUMERIC(12,2) NOT NULL DEFAULT 0, delivered_on DATE NOT NULL, is_paid BOOLEAN NOT NULL DEFAULT FALSE);
CREATE TABLE daily_purchases (purchase_date DATE PRIMARY KEY, total_weight NUMERIC(12,2) NOT NULL DEFAULT 0, total_value NUMERIC(12,2) NOT NULL DEFAULT 0);
INSERT INTO farmers (farmer_number, full_name) VALUES ('F001','Alice Banda'), ('F002','Brian Phiri'), ('F003','Chanda Mwale');
-- (b)
CREATE OR REPLACE FUNCTION fn_maize_rate(p_grade TEXT) RETURNS NUMERIC(10,2) AS $$ BEGIN IF p_grade IS NULL THEN RAISE EXCEPTION 'Grade is NULL'; END IF; IF UPPER(p_grade) = 'A' THEN RETURN 5; ELSIF UPPER(p_grade) = 'B' THEN RETURN 4; ELSIF UPPER(p_grade) = 'C' THEN RETURN 3; ELSE RAISE EXCEPTION 'Unsupported grade'; END IF; END; $$ LANGUAGE plpgsql;
-- (c) Procedure inserts basic fields only, trigger supplies rate/value
CREATE OR REPLACE PROCEDURE pr_receive_delivery(p_farmer_id INT, p_grade TEXT, p_weight NUMERIC, p_date DATE) AS $$ BEGIN IF NOT EXISTS (SELECT 1 FROM farmers WHERE farmer_id = p_farmer_id) THEN RAISE EXCEPTION 'Unknown farmer'; END IF; IF p_weight IS NULL OR p_weight <= 0 THEN RAISE EXCEPTION 'Invalid weight'; END IF; PERFORM fn_maize_rate(p_grade); INSERT INTO deliveries (farmer_id, grade, weight_kg, delivered_on, is_paid) VALUES (p_farmer_id, UPPER(p_grade), p_weight, p_date, FALSE); END; $$ LANGUAGE plpgsql;
-- (d)
CREATE OR REPLACE FUNCTION trg_deliveries_fn() RETURNS TRIGGER AS $$ BEGIN IF NEW.weight_kg IS NULL OR NEW.weight_kg <= 0 THEN RAISE EXCEPTION 'Invalid weight'; END IF; NEW.unit_rate := fn_maize_rate(NEW.grade); NEW.total_value := ROUND(NEW.weight_kg * NEW.unit_rate, 2); RETURN NEW; END; $$ LANGUAGE plpgsql;
CREATE TRIGGER trg_deliveries BEFORE INSERT OR UPDATE ON deliveries FOR EACH ROW EXECUTE FUNCTION trg_deliveries_fn();
-- Seed 6 deliveries: all grades A/B/C, both paid/unpaid
CALL pr_receive_delivery(1, 'A', 100, '2026-11-24'); CALL pr_receive_delivery(1, 'B', 50, '2026-11-24'); CALL pr_receive_delivery(2, 'C', 80, '2026-11-24'); CALL pr_receive_delivery(2, 'A', 60, '2026-11-23'); CALL pr_receive_delivery(3, 'B', 70, '2026-11-23'); CALL pr_receive_delivery(3, 'C', 40, '2026-11-24');
UPDATE deliveries SET is_paid = TRUE WHERE delivery_id IN (1, 3);
-- (e) LEFT JOIN keeps farmers with no unpaid, COALESCE to 0
CREATE VIEW v_farmer_amount_due AS SELECT f.farmer_number, f.full_name, COALESCE(SUM(d.total_value) FILTER (WHERE d.is_paid = FALSE),0) AS total_unpaid FROM farmers f LEFT JOIN deliveries d ON d.farmer_id = f.farmer_id GROUP BY f.farmer_id, f.farmer_number, f.full_name;
SELECT * FROM v_farmer_amount_due;
-- (f) Composite: equality on farmer_id + range on delivered_on
CREATE INDEX idx_deliveries_farmer_date ON deliveries (farmer_id, delivered_on);
EXPLAIN SELECT * FROM deliveries WHERE farmer_id = 1 AND delivered_on BETWEEN '2026-11-01' AND '2026-11-30';
-- (g)
CREATE OR REPLACE PROCEDURE pr_refresh_purchases(p_day DATE) AS $$ BEGIN INSERT INTO daily_purchases (purchase_date, total_weight, total_value) SELECT p_day, COALESCE(SUM(weight_kg),0), COALESCE(SUM(total_value),0) FROM deliveries WHERE delivered_on = p_day ON CONFLICT (purchase_date) DO UPDATE SET total_weight = EXCLUDED.total_weight, total_value = EXCLUDED.total_value; END; $$ LANGUAGE plpgsql;
CREATE EXTENSION IF NOT EXISTS pg_cron;
SELECT cron.schedule('refresh_purchases', '30 1 * * *', $$CALL pr_refresh_purchases(CURRENT_DATE - INTERVAL '1 day')$$);
