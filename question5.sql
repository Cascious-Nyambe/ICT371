-- ICT371 Q5 Hostel Room Allocation - PostgreSQL
-- (a)
CREATE TABLE students (student_id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY, student_number VARCHAR(20) NOT NULL UNIQUE, full_name VARCHAR(100) NOT NULL);
CREATE TABLE rooms (room_id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY, room_number VARCHAR(20) NOT NULL UNIQUE, capacity INT NOT NULL CHECK (capacity > 0));
CREATE TABLE allocations (allocation_id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY, student_id INT NOT NULL REFERENCES students(student_id), room_id INT NOT NULL REFERENCES rooms(room_id), allocated_on DATE NOT NULL, released_on DATE, status VARCHAR(10) NOT NULL CHECK (status IN ('ACTIVE','ENDED')), CHECK ((status='ACTIVE' AND released_on IS NULL) OR (status='ENDED' AND released_on IS NOT NULL)));
CREATE TABLE occupancy_snapshot (snapshot_date DATE NOT NULL, room_id INT NOT NULL REFERENCES rooms(room_id), occupied_beds INT NOT NULL DEFAULT 0, free_beds INT NOT NULL DEFAULT 0, PRIMARY KEY (snapshot_date, room_id));
INSERT INTO students (student_number, full_name) VALUES ('STU001','Alice Banda'), ('STU002','Brian Phiri'), ('STU003','Chanda Mwale'), ('STU004','D Mwanza'), ('STU005','E Banda');
INSERT INTO rooms (room_number, capacity) VALUES ('R101', 2), ('R102', 2), ('R103', 2);
-- (b)
CREATE OR REPLACE FUNCTION fn_free_beds(p_room_id INT) RETURNS INT AS $$ DECLARE v_cap INT; v_occ INT; BEGIN SELECT capacity INTO v_cap FROM rooms WHERE room_id = p_room_id; IF v_cap IS NULL THEN RAISE EXCEPTION 'Unknown room'; END IF; SELECT COUNT(*) INTO v_occ FROM allocations WHERE room_id = p_room_id AND status = 'ACTIVE'; RETURN v_cap - v_occ; END; $$ LANGUAGE plpgsql;
-- (c)
CREATE OR REPLACE PROCEDURE pr_allocate_room(p_student_id INT, p_room_id INT, p_allocated_on DATE) AS $$ BEGIN IF NOT EXISTS (SELECT 1 FROM students WHERE student_id = p_student_id) THEN RAISE EXCEPTION 'Unknown student'; END IF; IF NOT EXISTS (SELECT 1 FROM rooms WHERE room_id = p_room_id) THEN RAISE EXCEPTION 'Unknown room'; END IF; IF EXISTS (SELECT 1 FROM allocations WHERE student_id = p_student_id AND status = 'ACTIVE') THEN RAISE EXCEPTION 'Student already has ACTIVE allocation'; END IF; IF fn_free_beds(p_room_id) <= 0 THEN RAISE EXCEPTION 'Room full'; END IF; INSERT INTO allocations (student_id, room_id, allocated_on, released_on, status) VALUES (p_student_id, p_room_id, p_allocated_on, NULL, 'ACTIVE'); END; $$ LANGUAGE plpgsql;
-- (d) Trigger also enforces for direct SQL, excludes row being updated
CREATE OR REPLACE FUNCTION trg_allocations_fn() RETURNS TRIGGER AS $$ DECLARE v_cap INT; v_occ INT; BEGIN IF NEW.status = 'ACTIVE' THEN IF EXISTS (SELECT 1 FROM allocations WHERE student_id = NEW.student_id AND status = 'ACTIVE' AND allocation_id IS DISTINCT FROM NEW.allocation_id) THEN RAISE EXCEPTION 'Student already ACTIVE'; END IF; SELECT capacity INTO v_cap FROM rooms WHERE room_id = NEW.room_id; SELECT COUNT(*) INTO v_occ FROM allocations WHERE room_id = NEW.room_id AND status = 'ACTIVE' AND allocation_id IS DISTINCT FROM NEW.allocation_id; IF v_occ >= v_cap THEN RAISE EXCEPTION 'Room full'; END IF; END IF; RETURN NEW; END; $$ LANGUAGE plpgsql;
CREATE TRIGGER trg_allocations BEFORE INSERT OR UPDATE ON allocations FOR EACH ROW EXECUTE FUNCTION trg_allocations_fn();
-- Seed: R101 full (2), R102 partly (1), R103 empty
CALL pr_allocate_room(1, 1, '2026-11-01'); CALL pr_allocate_room(2, 1, '2026-11-01'); CALL pr_allocate_room(3, 2, '2026-11-01');
-- (e)
CREATE VIEW v_room_occupancy AS SELECT r.room_id, r.room_number, r.capacity, COUNT(a.allocation_id) FILTER (WHERE a.status='ACTIVE')::INT AS occupied_beds, (r.capacity - COUNT(a.allocation_id) FILTER (WHERE a.status='ACTIVE'))::INT AS free_beds FROM rooms r LEFT JOIN allocations a ON a.room_id = r.room_id GROUP BY r.room_id, r.room_number, r.capacity;
SELECT * FROM v_room_occupancy;
-- (f) Partial index: only ACTIVE, supports room filter
CREATE INDEX idx_allocations_room_active ON allocations (room_id) WHERE status = 'ACTIVE';
EXPLAIN SELECT * FROM allocations WHERE room_id = 1 AND status = 'ACTIVE';
-- (g)
CREATE OR REPLACE PROCEDURE pr_refresh_occupancy() AS $$ BEGIN INSERT INTO occupancy_snapshot (snapshot_date, room_id, occupied_beds, free_beds) SELECT CURRENT_DATE, room_id, occupied_beds, free_beds FROM v_room_occupancy ON CONFLICT (snapshot_date, room_id) DO UPDATE SET occupied_beds = EXCLUDED.occupied_beds, free_beds = EXCLUDED.free_beds; END; $$ LANGUAGE plpgsql;
CREATE EXTENSION IF NOT EXISTS pg_cron;
SELECT cron.schedule('refresh_occupancy', '55 23 * * *', $$CALL pr_refresh_occupancy()$$);
