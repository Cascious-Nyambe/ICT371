-- ICT371 Q7 Water Meter Readings and Billing - PostgreSQL
-- (a)
CREATE TABLE customers (customer_id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY, full_name VARCHAR(100) NOT NULL);
CREATE TABLE readings (reading_id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY, customer_id INT NOT NULL REFERENCES customers(customer_id), reading_month DATE NOT NULL, previous_reading NUMERIC(12,2) NOT NULL CHECK (previous_reading >= 0), current_reading NUMERIC(12,2) NOT NULL CHECK (current_reading >= 0), UNIQUE (customer_id, reading_month));
CREATE TABLE bills (bill_id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY, reading_id INT NOT NULL UNIQUE REFERENCES readings(reading_id), charge NUMERIC(12,2) NOT NULL CHECK (charge >= 0), amount_paid NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK (amount_paid >= 0), due_on DATE NOT NULL, CHECK (amount_paid <= charge));
CREATE TABLE receivable_snapshot (snapshot_date DATE PRIMARY KEY, total_due NUMERIC(12,2) NOT NULL DEFAULT 0);
INSERT INTO customers (full_name) VALUES ('Alice Banda'), ('Brian Phiri'), ('Chanda Mwale');
-- (b)
CREATE OR REPLACE FUNCTION fn_water_charge(p_units NUMERIC) RETURNS NUMERIC(12,2) AS $$ BEGIN IF p_units IS NULL OR p_units < 0 THEN RAISE EXCEPTION 'Invalid consumption'; END IF; IF p_units <= 10 THEN RETURN ROUND(p_units * 5, 2); ELSE RETURN ROUND(50 + (p_units - 10) * 8, 2); END IF; END; $$ LANGUAGE plpgsql;
-- (c)
CREATE OR REPLACE PROCEDURE pr_generate_bill(p_reading_id INT, p_due_on DATE) AS $$ DECLARE v_units NUMERIC(12,2); v_charge NUMERIC(12,2); BEGIN SELECT current_reading - previous_reading INTO v_units FROM readings WHERE reading_id = p_reading_id; IF v_units IS NULL THEN RAISE EXCEPTION 'Unknown reading'; END IF; IF EXISTS (SELECT 1 FROM bills WHERE reading_id = p_reading_id) THEN RAISE EXCEPTION 'Bill already exists'; END IF; v_charge := fn_water_charge(v_units); INSERT INTO bills (reading_id, charge, amount_paid, due_on) VALUES (p_reading_id, v_charge, 0, p_due_on); END; $$ LANGUAGE plpgsql;
-- (d)
CREATE OR REPLACE FUNCTION trg_readings_fn() RETURNS TRIGGER AS $$ BEGIN IF NEW.current_reading < NEW.previous_reading THEN RAISE EXCEPTION 'Current below previous'; END IF; RETURN NEW; END; $$ LANGUAGE plpgsql;
CREATE TRIGGER trg_readings BEFORE INSERT OR UPDATE ON readings FOR EACH ROW EXECUTE FUNCTION trg_readings_fn();
-- Seed 6 readings: 0 units, exactly 10, above 10
INSERT INTO readings (customer_id, reading_month, previous_reading, current_reading) VALUES (1, '2026-10-01', 100, 100), (1, '2026-11-01', 100, 110), (2, '2026-10-01', 50, 65), (2, '2026-11-01', 65, 70), (3, '2026-10-01', 200, 200), (3, '2026-11-01', 200, 215);
CALL pr_generate_bill(1, '2026-11-20'); CALL pr_generate_bill(2, '2026-11-20'); CALL pr_generate_bill(3, '2026-11-20'); CALL pr_generate_bill(4, '2026-11-20'); CALL pr_generate_bill(5, '2026-11-20'); CALL pr_generate_bill(6, '2026-11-20');
-- (e)
CREATE VIEW v_overdue_bills AS SELECT c.full_name, b.due_on, (b.charge - b.amount_paid) AS outstanding FROM bills b JOIN readings r ON r.reading_id = b.reading_id JOIN customers c ON c.customer_id = r.customer_id WHERE b.due_on < CURRENT_DATE AND b.amount_paid < b.charge;
SELECT * FROM v_overdue_bills;
-- (f) Index on due_on supports date range for overdue search
CREATE INDEX idx_bills_due_on ON bills (due_on);
EXPLAIN SELECT * FROM bills WHERE due_on < CURRENT_DATE AND amount_paid < charge;
-- (g)
CREATE OR REPLACE PROCEDURE pr_refresh_receivables() AS $$ BEGIN INSERT INTO receivable_snapshot (snapshot_date, total_due) SELECT CURRENT_DATE, COALESCE(SUM(charge - amount_paid),0) FROM bills WHERE amount_paid < charge ON CONFLICT (snapshot_date) DO UPDATE SET total_due = EXCLUDED.total_due; END; $$ LANGUAGE plpgsql;
CREATE EXTENSION IF NOT EXISTS pg_cron;
SELECT cron.schedule('refresh_receivables', '30 0 * * *', $$CALL pr_refresh_receivables()$$);
