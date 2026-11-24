-- ICT371 Q10 Scholarship Application Assessment - PostgreSQL
-- (a)
CREATE TABLE students (student_id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY, student_number VARCHAR(20) NOT NULL UNIQUE, full_name VARCHAR(100) NOT NULL);
CREATE TABLE applications (application_id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY, student_id INT NOT NULL REFERENCES students(student_id), age_at_application INT NOT NULL CHECK (age_at_application > 0), monthly_income NUMERIC(12,2) NOT NULL CHECK (monthly_income >= 0), average_mark NUMERIC(5,2) NOT NULL CHECK (average_mark BETWEEN 0 AND 100), submitted_on DATE NOT NULL, status VARCHAR(10) NOT NULL DEFAULT 'PENDING' CHECK (status IN ('PENDING','APPROVED','REJECTED')));
CREATE TABLE decision_audit (audit_id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY, application_id INT NOT NULL REFERENCES applications(application_id), old_status VARCHAR(10) NOT NULL, new_status VARCHAR(10) NOT NULL, changed_at TIMESTAMP NOT NULL DEFAULT NOW());
INSERT INTO students (student_number, full_name) VALUES ('STU001','Alice Banda'), ('STU002','Brian Phiri'), ('STU003','Chanda Mwale');
INSERT INTO applications (student_id, age_at_application, monthly_income, average_mark, submitted_on, status) VALUES (1, 20, 2500, 80, '2026-11-20', 'PENDING'), (1, 18, 3000, 70, '2026-11-20', 'PENDING'), (2, 25, 3000, 70, '2026-11-20', 'PENDING'), (2, 26, 2000, 85, '2026-11-20', 'PENDING'), (3, 22, 3001, 90, '2026-11-20', 'PENDING'), (3, 19, 2000, 69.99, '2026-11-20', 'PENDING');
-- (b)
CREATE OR REPLACE FUNCTION fn_scholarship_eligible(p_age INT, p_income NUMERIC, p_mark NUMERIC) RETURNS BOOLEAN AS $$ BEGIN IF p_age IS NULL OR p_income IS NULL OR p_mark IS NULL THEN RAISE EXCEPTION 'NULL input'; END IF; IF p_age <= 0 THEN RAISE EXCEPTION 'Invalid age'; END IF; IF p_income < 0 THEN RAISE EXCEPTION 'Negative income'; END IF; IF p_mark < 0 OR p_mark > 100 THEN RAISE EXCEPTION 'Mark out of range'; END IF; RETURN p_age BETWEEN 18 AND 25 AND p_income <= 3000 AND p_mark >= 70; END; $$ LANGUAGE plpgsql;
-- (c)
CREATE OR REPLACE PROCEDURE pr_assess_application(p_application_id INT) AS $$ DECLARE v_age INT; v_inc NUMERIC; v_mark NUMERIC; v_status VARCHAR(10); BEGIN SELECT age_at_application, monthly_income, average_mark, status INTO v_age, v_inc, v_mark, v_status FROM applications WHERE application_id = p_application_id; IF v_status IS NULL THEN RAISE EXCEPTION 'Unknown application'; END IF; IF v_status <> 'PENDING' THEN RAISE EXCEPTION 'Already assessed'; END IF; IF fn_scholarship_eligible(v_age, v_inc, v_mark) THEN UPDATE applications SET status = 'APPROVED' WHERE application_id = p_application_id; ELSE UPDATE applications SET status = 'REJECTED' WHERE application_id = p_application_id; END IF; END; $$ LANGUAGE plpgsql;
-- (d)
CREATE OR REPLACE FUNCTION trg_decision_audit_fn() RETURNS TRIGGER AS $$ BEGIN IF OLD.status IS DISTINCT FROM NEW.status THEN INSERT INTO decision_audit (application_id, old_status, new_status, changed_at) VALUES (NEW.application_id, OLD.status, NEW.status, NOW()); END IF; RETURN NEW; END; $$ LANGUAGE plpgsql;
CREATE TRIGGER trg_decision_audit AFTER UPDATE ON applications FOR EACH ROW EXECUTE FUNCTION trg_decision_audit_fn();
-- (e) No income exposed
CREATE VIEW v_approved_applicants AS SELECT s.student_number, s.full_name, a.average_mark, a.status FROM applications a JOIN students s ON s.student_id = a.student_id WHERE a.status = 'APPROVED';
SELECT * FROM v_approved_applicants;
-- (f) Composite: equality on status + range on submitted_on
CREATE INDEX idx_applications_status_date ON applications (status, submitted_on);
EXPLAIN SELECT * FROM applications WHERE status = 'PENDING' AND submitted_on BETWEEN '2026-11-01' AND '2026-11-30';
-- (g) FOR loop only PENDING, rerun safe because assessed rows are no longer PENDING
CREATE OR REPLACE PROCEDURE pr_assess_pending() AS $$ DECLARE r RECORD; BEGIN FOR r IN SELECT application_id FROM applications WHERE status = 'PENDING' ORDER BY application_id LOOP CALL pr_assess_application(r.application_id); END LOOP; END; $$ LANGUAGE plpgsql;
CREATE EXTENSION IF NOT EXISTS pg_cron;
SELECT cron.schedule('assess_pending', '0 8 * * 1', $$CALL pr_assess_pending()$$);
