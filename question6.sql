-- ICT371 Q6 Monthly Payroll Processing - PostgreSQL
-- (a)
CREATE TABLE employees (employee_id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY, full_name VARCHAR(100) NOT NULL, basic_salary NUMERIC(12,2) NOT NULL CHECK (basic_salary >= 0), allowance NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK (allowance >= 0), deduction NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK (deduction >= 0), active BOOLEAN NOT NULL DEFAULT TRUE);
CREATE TABLE payroll (payroll_id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY, employee_id INT NOT NULL REFERENCES employees(employee_id), pay_month DATE NOT NULL, gross_pay NUMERIC(12,2) NOT NULL, net_pay NUMERIC(12,2) NOT NULL, UNIQUE (employee_id, pay_month));
CREATE TABLE salary_audit (audit_id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY, employee_id INT NOT NULL REFERENCES employees(employee_id), old_salary NUMERIC(12,2) NOT NULL, new_salary NUMERIC(12,2) NOT NULL, changed_at TIMESTAMP NOT NULL DEFAULT NOW());
INSERT INTO employees (full_name, basic_salary, allowance, deduction, active) VALUES ('Alice Banda', 2000, 500, 200, TRUE), ('Brian Phiri', 1800, 300, 150, TRUE), ('Chanda Mwale', 2200, 400, 300, FALSE);
-- (b)
CREATE OR REPLACE FUNCTION fn_net_pay(p_employee_id INT) RETURNS NUMERIC(12,2) AS $$ DECLARE v_basic NUMERIC(12,2); v_allow NUMERIC(12,2); v_ded NUMERIC(12,2); v_net NUMERIC(12,2); BEGIN SELECT basic_salary, allowance, deduction INTO v_basic, v_allow, v_ded FROM employees WHERE employee_id = p_employee_id; IF v_basic IS NULL THEN RAISE EXCEPTION 'Unknown employee'; END IF; v_net := (v_basic + v_allow) - v_ded; IF v_net < 0 THEN RAISE EXCEPTION 'Negative net pay'; END IF; RETURN v_net; END; $$ LANGUAGE plpgsql;
-- (c) FOR loop, month-start check, existing row unchanged, any error fails whole call
CREATE OR REPLACE PROCEDURE pr_process_payroll(p_month DATE) AS $$ DECLARE r RECORD; BEGIN IF p_month IS NULL OR p_month <> date_trunc('month', p_month)::DATE THEN RAISE EXCEPTION 'Month must be month-start date'; END IF; FOR r IN SELECT * FROM employees WHERE active ORDER BY employee_id LOOP INSERT INTO payroll (employee_id, pay_month, gross_pay, net_pay) VALUES (r.employee_id, p_month, r.basic_salary + r.allowance, fn_net_pay(r.employee_id)) ON CONFLICT (employee_id, pay_month) DO NOTHING; END LOOP; END; $$ LANGUAGE plpgsql;
CALL pr_process_payroll('2026-10-01'); CALL pr_process_payroll('2026-11-01');
-- (d)
CREATE OR REPLACE FUNCTION trg_salary_audit_fn() RETURNS TRIGGER AS $$ BEGIN IF OLD.basic_salary IS DISTINCT FROM NEW.basic_salary THEN INSERT INTO salary_audit (employee_id, old_salary, new_salary, changed_at) VALUES (NEW.employee_id, OLD.basic_salary, NEW.basic_salary, NOW()); END IF; RETURN NEW; END; $$ LANGUAGE plpgsql;
CREATE TRIGGER trg_salary_audit AFTER UPDATE ON employees FOR EACH ROW EXECUTE FUNCTION trg_salary_audit_fn();
-- (e) Join keeps history even if employee later inactive
CREATE VIEW v_payroll_report AS SELECT e.full_name, p.pay_month, p.gross_pay, p.net_pay FROM payroll p JOIN employees e ON e.employee_id = p.employee_id;
SELECT * FROM v_payroll_report;
-- (f) Index on pay_month only. Do NOT duplicate UNIQUE(employee_id,pay_month) - that index starts with employee_id and cannot serve pay_month-only filter efficiently.
CREATE INDEX idx_payroll_pay_month ON payroll (pay_month);
EXPLAIN SELECT * FROM payroll WHERE pay_month = '2026-11-01';
-- (g)
CREATE EXTENSION IF NOT EXISTS pg_cron;
SELECT cron.schedule('process_payroll', '0 2 1 * *', $$CALL pr_process_payroll((date_trunc('month', CURRENT_DATE) - INTERVAL '1 month')::DATE)$$);
SELECT jobid, schedule, command FROM cron.job WHERE command LIKE '%pr_process_payroll%';
SELECT * FROM cron.job_run_details ORDER BY start_time DESC LIMIT 10;
