-- ICT371 Q4 Clinic Appointment Scheduling - PostgreSQL
-- (a)
CREATE TABLE patients (patient_id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY, full_name VARCHAR(100) NOT NULL);
CREATE TABLE doctors (doctor_id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY, full_name VARCHAR(100) NOT NULL);
CREATE TABLE appointments (appointment_id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY, patient_id INT NOT NULL REFERENCES patients(patient_id), doctor_id INT NOT NULL REFERENCES doctors(doctor_id), appointment_day DATE NOT NULL, slot_time TIME NOT NULL, status VARCHAR(10) NOT NULL DEFAULT 'BOOKED' CHECK (status IN ('BOOKED','ATTENDED','CANCELLED')));
CREATE TABLE clinic_summary (summary_date DATE PRIMARY KEY, booked_count INT NOT NULL DEFAULT 0, attended_count INT NOT NULL DEFAULT 0, cancelled_count INT NOT NULL DEFAULT 0);
INSERT INTO patients (full_name) VALUES ('Alice Banda'), ('Brian Phiri'), ('Chanda Mwale');
INSERT INTO doctors (full_name) VALUES ('Dr Banda'), ('Dr Phiri'), ('Dr Mwale');
-- (b)
CREATE OR REPLACE FUNCTION fn_daily_load(p_doctor_id INT, p_day DATE) RETURNS INT AS $$ DECLARE v_cnt INT; BEGIN IF NOT EXISTS (SELECT 1 FROM doctors WHERE doctor_id = p_doctor_id) THEN RAISE EXCEPTION 'Unknown doctor'; END IF; SELECT COUNT(*) INTO v_cnt FROM appointments WHERE doctor_id = p_doctor_id AND appointment_day = p_day AND status <> 'CANCELLED'; RETURN v_cnt; END; $$ LANGUAGE plpgsql;
-- (c)
CREATE OR REPLACE PROCEDURE pr_book_appointment(p_patient_id INT, p_doctor_id INT, p_day DATE, p_slot TIME) AS $$ BEGIN IF NOT EXISTS (SELECT 1 FROM patients WHERE patient_id = p_patient_id) THEN RAISE EXCEPTION 'Unknown patient'; END IF; IF NOT EXISTS (SELECT 1 FROM doctors WHERE doctor_id = p_doctor_id) THEN RAISE EXCEPTION 'Unknown doctor'; END IF; IF p_day < CURRENT_DATE THEN RAISE EXCEPTION 'Past date'; END IF; IF p_slot NOT IN ('09:00','10:00','11:00','12:00') THEN RAISE EXCEPTION 'Unsupported slot'; END IF; INSERT INTO appointments (patient_id, doctor_id, appointment_day, slot_time, status) VALUES (p_patient_id, p_doctor_id, p_day, p_slot, 'BOOKED'); END; $$ LANGUAGE plpgsql;
-- (d) Trigger enforces clash for direct SQL too, excludes row being updated
CREATE OR REPLACE FUNCTION trg_appointment_clash_fn() RETURNS TRIGGER AS $$ BEGIN IF NEW.status <> 'CANCELLED' AND EXISTS (SELECT 1 FROM appointments WHERE doctor_id = NEW.doctor_id AND appointment_day = NEW.appointment_day AND slot_time = NEW.slot_time AND status <> 'CANCELLED' AND appointment_id IS DISTINCT FROM NEW.appointment_id) THEN RAISE EXCEPTION 'Slot clash'; END IF; RETURN NEW; END; $$ LANGUAGE plpgsql;
CREATE TRIGGER trg_appointment_clash BEFORE INSERT OR UPDATE ON appointments FOR EACH ROW EXECUTE FUNCTION trg_appointment_clash_fn();
-- Seed 6 appointments, no clash
CALL pr_book_appointment(1, 1, '2026-11-25', '09:00'); CALL pr_book_appointment(2, 1, '2026-11-25', '10:00'); CALL pr_book_appointment(3, 1, '2026-11-25', '11:00'); CALL pr_book_appointment(1, 2, '2026-11-25', '09:00'); CALL pr_book_appointment(2, 2, '2026-11-25', '10:00'); CALL pr_book_appointment(3, 3, '2026-11-26', '09:00');
-- (e)
CREATE VIEW v_today_appointments AS SELECT p.full_name AS patient_name, d.full_name AS doctor_name, a.slot_time FROM appointments a JOIN patients p ON p.patient_id = a.patient_id JOIN doctors d ON d.doctor_id = a.doctor_id WHERE a.appointment_day = CURRENT_DATE AND a.status = 'BOOKED';
SELECT * FROM v_today_appointments;
-- (f) Non-unique index: day + doctor, matches query order
CREATE INDEX idx_appointments_day_doctor ON appointments (appointment_day, doctor_id);
EXPLAIN SELECT * FROM appointments WHERE appointment_day = '2026-11-25' AND doctor_id = 1;
-- (g)
CREATE OR REPLACE PROCEDURE pr_refresh_clinic_summary(p_day DATE) AS $$ BEGIN INSERT INTO clinic_summary (summary_date, booked_count, attended_count, cancelled_count) SELECT p_day, COUNT(*) FILTER (WHERE status='BOOKED'), COUNT(*) FILTER (WHERE status='ATTENDED'), COUNT(*) FILTER (WHERE status='CANCELLED') FROM appointments WHERE appointment_day = p_day ON CONFLICT (summary_date) DO UPDATE SET booked_count = EXCLUDED.booked_count, attended_count = EXCLUDED.attended_count, cancelled_count = EXCLUDED.cancelled_count; END; $$ LANGUAGE plpgsql;
CREATE EXTENSION IF NOT EXISTS pg_cron;
SELECT cron.schedule('refresh_clinic', '0 1 * * *', $$CALL pr_refresh_clinic_summary(CURRENT_DATE - INTERVAL '1 day')$$);
