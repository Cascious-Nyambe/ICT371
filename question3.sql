-- ICT371 Q3 Library Returns - PostgreSQL
-- (a)
CREATE TABLE books (book_id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY, title VARCHAR(200) NOT NULL);
CREATE TABLE loans (loan_id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY, book_id INT NOT NULL REFERENCES books(book_id), borrower_name VARCHAR(100) NOT NULL, borrowed_on DATE NOT NULL, due_on DATE NOT NULL CHECK (due_on >= borrowed_on), returned_on DATE, fine_amount NUMERIC(10,2) NOT NULL DEFAULT 0 CHECK (fine_amount >= 0));
CREATE TABLE loan_audit (audit_id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY, loan_id INT NOT NULL REFERENCES loans(loan_id), old_returned_on DATE, new_returned_on DATE, changed_at TIMESTAMP NOT NULL DEFAULT NOW());
CREATE TABLE overdue_summary (snapshot_date DATE PRIMARY KEY, overdue_count INT NOT NULL DEFAULT 0, total_fine NUMERIC(12,2) NOT NULL DEFAULT 0);
INSERT INTO books (title) VALUES ('Database Systems'), ('Data Structures'), ('Operating Systems');
-- (b)
CREATE OR REPLACE FUNCTION fn_loan_fine(p_loan_id INT, p_as_of DATE) RETURNS NUMERIC(10,2) AS $$ DECLARE v_due DATE; v_ret DATE; v_end DATE; v_days INT; BEGIN SELECT due_on, returned_on INTO v_due, v_ret FROM loans WHERE loan_id = p_loan_id; IF v_due IS NULL THEN RAISE EXCEPTION 'Unknown loan'; END IF; IF p_as_of IS NULL THEN RAISE EXCEPTION 'Invalid date'; END IF; v_end := LEAST(p_as_of, COALESCE(v_ret, p_as_of)); v_days := GREATEST(0, v_end - v_due); RETURN (v_days * 2)::NUMERIC(10,2); END; $$ LANGUAGE plpgsql;
-- (c)
CREATE OR REPLACE PROCEDURE pr_return_loan(p_loan_id INT, p_returned_on DATE) AS $$ DECLARE v_borrowed DATE; v_ret DATE; v_fine NUMERIC(10,2); BEGIN SELECT borrowed_on, returned_on INTO v_borrowed, v_ret FROM loans WHERE loan_id = p_loan_id FOR UPDATE; IF v_borrowed IS NULL THEN RAISE EXCEPTION 'Unknown loan'; END IF; IF v_ret IS NOT NULL THEN RAISE EXCEPTION 'Already returned'; END IF; IF p_returned_on < v_borrowed THEN RAISE EXCEPTION 'Return before borrowed'; END IF; v_fine := fn_loan_fine(p_loan_id, p_returned_on); UPDATE loans SET returned_on = p_returned_on, fine_amount = v_fine WHERE loan_id = p_loan_id; END; $$ LANGUAGE plpgsql;
-- (d)
CREATE OR REPLACE FUNCTION trg_loan_audit_fn() RETURNS TRIGGER AS $$ BEGIN IF OLD.returned_on IS DISTINCT FROM NEW.returned_on THEN INSERT INTO loan_audit (loan_id, old_returned_on, new_returned_on, changed_at) VALUES (NEW.loan_id, OLD.returned_on, NEW.returned_on, NOW()); END IF; RETURN NEW; END; $$ LANGUAGE plpgsql;
CREATE TRIGGER trg_loan_audit AFTER UPDATE ON loans FOR EACH ROW EXECUTE FUNCTION trg_loan_audit_fn();
-- Seed 6 loans: 1=open overdue, 3=on-time via procedure, 5=returned late via procedure, others open
INSERT INTO loans (book_id, borrower_name, borrowed_on, due_on) VALUES (1, 'Alice Banda', '2026-11-01', '2026-11-10'), (1, 'Brian Phiri', '2026-11-01', '2026-11-20'), (2, 'Chanda Mwale', '2026-11-05', '2026-11-12'), (2, 'D Mwanza', '2026-11-05', '2026-11-15'), (3, 'E Banda', '2026-11-02', '2026-11-09'), (3, 'F Phiri', '2026-11-02', '2026-11-09');
CALL pr_return_loan(3, '2026-11-12'); CALL pr_return_loan(5, '2026-11-09');
-- (e)
CREATE VIEW v_overdue_loans AS SELECT b.title, l.borrower_name, l.due_on, fn_loan_fine(l.loan_id, CURRENT_DATE) AS fine FROM loans l JOIN books b ON b.book_id = l.book_id WHERE l.returned_on IS NULL AND l.due_on < CURRENT_DATE;
SELECT * FROM v_overdue_loans;
-- (f) Partial index: only unreturned loans, supports book lookup
CREATE INDEX idx_loans_book_unreturned ON loans (book_id) WHERE returned_on IS NULL;
EXPLAIN SELECT * FROM loans WHERE book_id = 1 AND returned_on IS NULL;
-- (g)
CREATE OR REPLACE PROCEDURE pr_refresh_overdue(p_as_of DATE) AS $$ BEGIN INSERT INTO overdue_summary (snapshot_date, overdue_count, total_fine) SELECT p_as_of, COUNT(*), COALESCE(SUM(fn_loan_fine(loan_id, p_as_of)),0) FROM loans WHERE returned_on IS NULL AND due_on < p_as_of ON CONFLICT (snapshot_date) DO UPDATE SET overdue_count = EXCLUDED.overdue_count, total_fine = EXCLUDED.total_fine; END; $$ LANGUAGE plpgsql;
CREATE EXTENSION IF NOT EXISTS pg_cron;
SELECT cron.schedule('refresh_overdue', '10 0 * * *', $$CALL pr_refresh_overdue(CURRENT_DATE)$$);
