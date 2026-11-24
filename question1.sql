-- ICT371 Q1 Pharmacy - PostgreSQL
-- (a)
CREATE TABLE medicines (medicine_id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY, medicine_name VARCHAR(100) NOT NULL, unit_price NUMERIC(10,2) NOT NULL CHECK (unit_price > 0), stock_qty INT NOT NULL DEFAULT 0 CHECK (stock_qty >= 0));
CREATE TABLE sales (sale_id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY, medicine_id INT NOT NULL REFERENCES medicines(medicine_id), quantity INT NOT NULL CHECK (quantity > 0), unit_price NUMERIC(10,2) NOT NULL CHECK (unit_price > 0), sold_on DATE NOT NULL);
CREATE TABLE stock_audit (audit_id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY, medicine_id INT NOT NULL REFERENCES medicines(medicine_id), old_qty INT NOT NULL, new_qty INT NOT NULL, changed_at TIMESTAMP NOT NULL DEFAULT NOW());
CREATE TABLE daily_sales (sales_date DATE PRIMARY KEY, total_qty INT NOT NULL DEFAULT 0, total_amount NUMERIC(12,2) NOT NULL DEFAULT 0);
INSERT INTO medicines (medicine_name, unit_price, stock_qty) VALUES ('Paracetamol 500mg', 5.00, 100), ('Amoxicillin 250mg', 12.50, 50), ('Ibuprofen 200mg', 8.00, 30);
-- (b)
CREATE OR REPLACE FUNCTION fn_sale_value(p_medicine_id INT, p_quantity INT) RETURNS NUMERIC(12,2) AS $$ DECLARE v_price NUMERIC(10,2); BEGIN IF p_quantity IS NULL OR p_quantity <= 0 THEN RAISE EXCEPTION 'Invalid quantity'; END IF; SELECT unit_price INTO v_price FROM medicines WHERE medicine_id = p_medicine_id; IF v_price IS NULL THEN RAISE EXCEPTION 'Unknown medicine'; END IF; RETURN v_price * p_quantity; END; $$ LANGUAGE plpgsql;
-- (c)
CREATE OR REPLACE PROCEDURE pr_record_sale(p_medicine_id INT, p_quantity INT, p_sold_on DATE) AS $$ DECLARE v_stock INT; v_price NUMERIC(10,2); BEGIN IF p_quantity IS NULL OR p_quantity <= 0 THEN RAISE EXCEPTION 'Invalid quantity'; END IF; SELECT stock_qty, unit_price INTO v_stock, v_price FROM medicines WHERE medicine_id = p_medicine_id FOR UPDATE; IF v_price IS NULL THEN RAISE EXCEPTION 'Unknown medicine'; END IF; IF v_stock < p_quantity THEN RAISE EXCEPTION 'Insufficient stock'; END IF; INSERT INTO sales (medicine_id, quantity, unit_price, sold_on) VALUES (p_medicine_id, p_quantity, v_price, p_sold_on); UPDATE medicines SET stock_qty = stock_qty - p_quantity WHERE medicine_id = p_medicine_id; END; $$ LANGUAGE plpgsql;
-- (d) Trigger must exist before sales so audit is created
CREATE OR REPLACE FUNCTION trg_medicines_stock_audit_fn() RETURNS TRIGGER AS $$ BEGIN IF OLD.stock_qty IS DISTINCT FROM NEW.stock_qty THEN INSERT INTO stock_audit (medicine_id, old_qty, new_qty, changed_at) VALUES (NEW.medicine_id, OLD.stock_qty, NEW.stock_qty, NOW()); END IF; RETURN NEW; END; $$ LANGUAGE plpgsql;
CREATE TRIGGER trg_medicines_stock_audit AFTER UPDATE ON medicines FOR EACH ROW EXECUTE FUNCTION trg_medicines_stock_audit_fn();
-- Seed sales through procedure
CALL pr_record_sale(1, 5, '2026-11-24'); CALL pr_record_sale(1, 3, '2026-11-24'); CALL pr_record_sale(2, 2, '2026-11-24'); CALL pr_record_sale(2, 4, '2026-11-23'); CALL pr_record_sale(3, 2, '2026-11-24'); CALL pr_record_sale(3, 1, '2026-11-23');
-- (e)
CREATE VIEW v_low_stock AS SELECT medicine_id, medicine_name, unit_price, stock_qty FROM medicines WHERE stock_qty < 10;
SELECT * FROM v_low_stock;
-- (f) Composite index: equality on medicine_id + range on sold_on. PostgreSQL can use both parts, avoids full scan.
CREATE INDEX idx_sales_med_date ON sales (medicine_id, sold_on);
EXPLAIN SELECT * FROM sales WHERE medicine_id = 1 AND sold_on BETWEEN '2026-11-01' AND '2026-11-30';
-- (g)
CREATE OR REPLACE PROCEDURE pr_refresh_sales(p_day DATE) AS $$ BEGIN INSERT INTO daily_sales (sales_date, total_qty, total_amount) SELECT p_day, COALESCE(SUM(quantity),0), COALESCE(SUM(quantity * unit_price),0) FROM sales WHERE sold_on = p_day ON CONFLICT (sales_date) DO UPDATE SET total_qty = EXCLUDED.total_qty, total_amount = EXCLUDED.total_amount; END; $$ LANGUAGE plpgsql;
CREATE EXTENSION IF NOT EXISTS pg_cron;
SELECT cron.schedule('refresh_daily_sales', '15 0 * * *', $$CALL pr_refresh_sales(CURRENT_DATE - INTERVAL '1 day')$$);
