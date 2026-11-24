-- ICT371 Q2 University Fee Payments - PostgreSQL
-- (a)
CREATE TABLE students (student_id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY, student_number VARCHAR(20) NOT NULL UNIQUE, full_name VARCHAR(100) NOT NULL, fee_due NUMERIC(12,2) NOT NULL CHECK (fee_due >= 0));
CREATE TABLE payments (payment_id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY, student_id INT NOT NULL REFERENCES students(student_id), amount NUMERIC(12,2) NOT NULL CHECK (amount > 0), paid_on DATE NOT NULL);
CREATE TABLE payment_audit (audit_id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY, payment_id INT NOT NULL REFERENCES payments(payment_id), student_id INT NOT NULL REFERENCES students(student_id), amount NUMERIC(12,2) NOT NULL, logged_at TIMESTAMP NOT NULL DEFAULT NOW());
CREATE TABLE daily_collections (collection_date DATE PRIMARY KEY, payment_count INT NOT NULL DEFAULT 0, total_amount NUMERIC(12,2) NOT NULL DEFAULT 0);
INSERT INTO students (student_number, full_name, fee_due) VALUES ('STU001', 'Alice Banda', 1500.00), ('STU002', 'Brian Phiri', 2000.00), ('STU003', 'Chanda Mwale', 1200.00);
-- (b)
CREATE OR REPLACE FUNCTION fn_fee_balance(p_student_id INT) RETURNS NUMERIC(12,2) AS $$ DECLARE v_due NUMERIC(12,2); v_paid NUMERIC(12,2); BEGIN SELECT fee_due INTO v_due FROM students WHERE student_id = p_student_id; IF v_due IS NULL THEN RAISE EXCEPTION 'Unknown student'; END IF; SELECT COALESCE(SUM(amount),0) INTO v_paid FROM payments WHERE student_id = p_student_id; RETURN v_due - v_paid; END; $$ LANGUAGE plpgsql;
-- (c)
CREATE OR REPLACE PROCEDURE pr_receive_payment(p_student_id INT, p_amount NUMERIC(12,2), p_paid_on DATE) AS $$ DECLARE v_balance NUMERIC(12,2); BEGIN IF p_amount IS NULL OR p_amount <= 0 THEN RAISE EXCEPTION 'Invalid amount'; END IF; v_balance := fn_fee_balance(p_student_id); IF p_amount > v_balance THEN RAISE EXCEPTION 'Payment exceeds balance'; END IF; INSERT INTO payments (student_id, amount, paid_on) VALUES (p_student_id, p_amount, p_paid_on); END; $$ LANGUAGE plpgsql;
-- (d) Trigger does audit, procedure does NOT
CREATE OR REPLACE FUNCTION trg_payments_audit_fn() RETURNS TRIGGER AS $$ BEGIN INSERT INTO payment_audit (payment_id, student_id, amount, logged_at) VALUES (NEW.payment_id, NEW.student_id, NEW.amount, NOW()); RETURN NEW; END; $$ LANGUAGE plpgsql;
CREATE TRIGGER trg_payments_audit AFTER INSERT ON payments FOR EACH ROW EXECUTE FUNCTION trg_payments_audit_fn();
-- Seed: STU003 initially has no payments, then 6 payments for STU001/STU002
CALL pr_receive_payment(1, 500.00, '2026-11-24'); CALL pr_receive_payment(1, 300.00, '2026-11-24'); CALL pr_receive_payment(1, 200.00, '2026-11-23'); CALL pr_receive_payment(2, 1000.00, '2026-11-24'); CALL pr_receive_payment(2, 500.00, '2026-11-23'); CALL pr_receive_payment(2, 250.00, '2026-11-23');
-- (e)
CREATE VIEW v_fee_balances AS SELECT s.student_number, s.full_name, s.fee_due - COALESCE(SUM(p.amount),0) AS outstanding_balance FROM students s LEFT JOIN payments p ON p.student_id = s.student_id GROUP BY s.student_id, s.student_number, s.full_name, s.fee_due HAVING s.fee_due - COALESCE(SUM(p.amount),0) > 0;
SELECT * FROM v_fee_balances;
-- (f) Composite index: equality on student_id + range on paid_on
CREATE INDEX idx_payments_student_date ON payments (student_id, paid_on);
EXPLAIN SELECT * FROM payments WHERE student_id = 1 AND paid_on BETWEEN '2026-11-01' AND '2026-11-30';
-- (g)
CREATE OR REPLACE PROCEDURE pr_refresh_collections(p_day DATE) AS $$ BEGIN INSERT INTO daily_collections (collection_date, payment_count, total_amount) SELECT p_day, COUNT(*), COALESCE(SUM(amount),0) FROM payments WHERE paid_on = p_day ON CONFLICT (collection_date) DO UPDATE SET payment_count = EXCLUDED.payment_count, total_amount = EXCLUDED.total_amount; END; $$ LANGUAGE plpgsql;
CREATE EXTENSION IF NOT EXISTS pg_cron;
SELECT cron.schedule('refresh_daily_collections', '0 1 * * *', $$CALL pr_refresh_collections(CURRENT_DATE - INTERVAL '1 day')$$);
