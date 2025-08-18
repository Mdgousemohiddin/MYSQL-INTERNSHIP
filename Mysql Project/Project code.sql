-- ====== Reset (safe for local dev) ======
DROP DATABASE IF EXISTS airline_reservation;
CREATE DATABASE airline_reservation;
USE airline_reservation;

-- ====== Core Tables ======

-- Aircraft master
CREATE TABLE aircraft (
  aircraft_id      INT PRIMARY KEY AUTO_INCREMENT,
  model            VARCHAR(50) NOT NULL,
  code             VARCHAR(10) NOT NULL UNIQUE,  -- e.g., A320-01
  notes            VARCHAR(255)
);

-- Seats per aircraft (physical seats reused across many flights of same aircraft)
CREATE TABLE seats (
  seat_id          INT PRIMARY KEY AUTO_INCREMENT,
  aircraft_id      INT NOT NULL,
  seat_no          VARCHAR(5) NOT NULL,          -- e.g., 1A, 12C
  class            ENUM('ECONOMY','BUSINESS','FIRST') NOT NULL DEFAULT 'ECONOMY',
  FOREIGN KEY (aircraft_id) REFERENCES aircraft(aircraft_id) ON DELETE CASCADE,
  UNIQUE (aircraft_id, seat_no)
);

-- Flights (instance of an aircraft operating a route at a specific time)
CREATE TABLE flights (
  flight_id        INT PRIMARY KEY AUTO_INCREMENT,
  flight_no        VARCHAR(10) NOT NULL,         -- e.g., AI501
  aircraft_id      INT NOT NULL,
  origin           VARCHAR(3) NOT NULL,          -- IATA code e.g., HYD
  destination      VARCHAR(3) NOT NULL,          -- e.g., DEL
  dep_time         DATETIME NOT NULL,
  arr_time         DATETIME NOT NULL,
  base_fare        DECIMAL(10,2) NOT NULL DEFAULT 3000.00,
  FOREIGN KEY (aircraft_id) REFERENCES aircraft(aircraft_id) ON DELETE RESTRICT,
  INDEX (origin, destination, dep_time),
  INDEX (dep_time),
  INDEX (flight_no)
);

-- Customers
CREATE TABLE customers (
  customer_id      INT PRIMARY KEY AUTO_INCREMENT,
  full_name        VARCHAR(100) NOT NULL,
  email            VARCHAR(120) NOT NULL,
  phone            VARCHAR(20),
  UNIQUE (email)
);

-- Bookings
CREATE TABLE bookings (
  booking_id       INT PRIMARY KEY AUTO_INCREMENT,
  booking_ref      VARCHAR(12) NOT NULL UNIQUE,  -- e.g., PNR-like code
  flight_id        INT NOT NULL,
  customer_id      INT NOT NULL,
  booking_time     DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  status           ENUM('CONFIRMED','CANCELLED') NOT NULL DEFAULT 'CONFIRMED',
  total_amount     DECIMAL(10,2) NOT NULL DEFAULT 0.00,
  FOREIGN KEY (flight_id) REFERENCES flights(flight_id) ON DELETE CASCADE,
  FOREIGN KEY (customer_id) REFERENCES customers(customer_id) ON DELETE CASCADE,
  INDEX (status)
);

-- Seats assigned within a booking (one or more seats)
CREATE TABLE booking_seats (
  booking_id       INT NOT NULL,
  flight_id        INT NOT NULL,
  seat_id          INT NOT NULL,
  PRIMARY KEY (booking_id, seat_id),
  FOREIGN KEY (booking_id) REFERENCES bookings(booking_id) ON DELETE CASCADE,
  FOREIGN KEY (flight_id) REFERENCES flights(flight_id) ON DELETE CASCADE,
  FOREIGN KEY (seat_id) REFERENCES seats(seat_id) ON DELETE RESTRICT,
  -- prevent double-assigning the same seat on the same flight
  UNIQUE (flight_id, seat_id)
);

-- Optional history table (captures released seats on cancellation)
CREATE TABLE booking_seats_history (
  hist_id          BIGINT PRIMARY KEY AUTO_INCREMENT,
  booking_id       INT NOT NULL,
  flight_id        INT NOT NULL,
  seat_id          INT NOT NULL,
  action           ENUM('ALLOCATED','RELEASED') NOT NULL,
  action_time      DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- ====== Seed Data ======

INSERT INTO aircraft (model, code, notes)
VALUES ('Airbus A320', 'A320-01', 'Single aisle'), ('Boeing 737-800', 'B738-02', 'Single aisle');

-- Create a small seat map for A320-01: Rows 1–5, seats A–D (20 seats)
WITH RECURSIVE nums AS (
  SELECT 1 n
  UNION ALL
  SELECT n+1 FROM nums WHERE n < 5
)
SELECT * FROM nums;

-- Insert seats for A320-01
INSERT INTO seats (aircraft_id, seat_no, class)
SELECT a.aircraft_id,
       CONCAT(n.n, s.letter) AS seat_no,
       CASE WHEN n.n <= 2 THEN 'BUSINESS' ELSE 'ECONOMY' END AS class
FROM aircraft a
JOIN (SELECT 1 n UNION SELECT 2 UNION SELECT 3 UNION SELECT 4 UNION SELECT 5) n
JOIN (SELECT 'A' letter UNION SELECT 'B' UNION SELECT 'C' UNION SELECT 'D') s
WHERE a.code = 'A320-01';

-- Create seats for B738-02: Rows 1–3 A–C (9 seats)
INSERT INTO seats (aircraft_id, seat_no, class)
SELECT a.aircraft_id,
       CONCAT(n.n, s.letter),
       CASE WHEN n.n = 1 THEN 'BUSINESS' ELSE 'ECONOMY' END
FROM aircraft a
JOIN (SELECT 1 n UNION SELECT 2 UNION SELECT 3) n
JOIN (SELECT 'A' letter UNION SELECT 'B' UNION SELECT 'C') s
WHERE a.code = 'B738-02';

-- Flights
INSERT INTO flights (flight_no, aircraft_id, origin, destination, dep_time, arr_time, base_fare)
SELECT 'AI501', a.aircraft_id, 'HYD','DEL','2025-09-10 08:30:00','2025-09-10 10:40:00', 4200.00
FROM aircraft a WHERE a.code='A320-01';

INSERT INTO flights (flight_no, aircraft_id, origin, destination, dep_time, arr_time, base_fare)
SELECT 'AI502', a.aircraft_id, 'DEL','HYD','2025-09-10 18:30:00','2025-09-10 20:40:00', 4400.00
FROM aircraft a WHERE a.code='A320-01';

INSERT INTO flights (flight_no, aircraft_id, origin, destination, dep_time, arr_time, base_fare)
SELECT '6E111', a.aircraft_id, 'HYD','BLR','2025-09-10 07:00:00','2025-09-10 08:15:00', 3200.00
FROM aircraft a WHERE a.code='B738-02';

-- Customers
INSERT INTO customers (full_name, email, phone)
VALUES ('Aarav Kumar','aarav@example.com','9000000011'),
       ('Saanvi Reddy','saanvi@example.com','9000000022');

-- ====== Helper: fare by class (simple multiplier) ======
CREATE TABLE fare_rules (
  class  ENUM('ECONOMY','BUSINESS','FIRST') PRIMARY KEY,
  multiplier DECIMAL(5,2) NOT NULL
);
INSERT INTO fare_rules VALUES
  ('ECONOMY', 1.00), ('BUSINESS', 2.00), ('FIRST', 3.50);

-- ====== Views ======

-- Total seats per flight (based on aircraft seat map)
CREATE OR REPLACE VIEW v_flight_total_seats AS
SELECT f.flight_id, COUNT(s.seat_id) AS total_seats
FROM flights f
JOIN seats s ON s.aircraft_id = f.aircraft_id
GROUP BY f.flight_id;

-- Booked seats per flight (active bookings only)
CREATE OR REPLACE VIEW v_flight_booked_seats AS
SELECT bs.flight_id, COUNT(*) AS booked_seats
FROM booking_seats bs
JOIN bookings b ON b.booking_id = bs.booking_id
WHERE b.status = 'CONFIRMED'
GROUP BY bs.flight_id;

-- Availability per flight
CREATE OR REPLACE VIEW v_flight_availability AS
SELECT f.flight_id, f.flight_no, f.origin, f.destination, f.dep_time, f.arr_time, f.base_fare,
       COALESCE(t.total_seats,0) AS total_seats,
       COALESCE(t.total_seats,0) - COALESCE(b.booked_seats,0) AS available_seats
FROM flights f
LEFT JOIN v_flight_total_seats t ON t.flight_id = f.flight_id
LEFT JOIN v_flight_booked_seats b ON b.flight_id = f.flight_id;

-- Booking summary (amount, seats, status)
CREATE OR REPLACE VIEW v_booking_summary AS
SELECT b.booking_id, b.booking_ref, b.status, b.booking_time,
       c.full_name, f.flight_no, f.origin, f.destination, f.dep_time,
       COUNT(bs.seat_id) AS seats_count, b.total_amount
FROM bookings b
JOIN customers c ON c.customer_id = b.customer_id
JOIN flights f   ON f.flight_id = b.flight_id
LEFT JOIN booking_seats bs ON bs.booking_id = b.booking_id
GROUP BY b.booking_id;

-- ====== Triggers ======

-- 1) Prevent assigning a seat from a different aircraft than the flight's aircraft
DELIMITER $$
CREATE TRIGGER trg_booking_seats_before_insert
BEFORE INSERT ON booking_seats
FOR EACH ROW
BEGIN
  DECLARE v_flight_aircraft INT;
  DECLARE v_seat_aircraft   INT;

  SELECT aircraft_id INTO v_flight_aircraft FROM flights WHERE flight_id = NEW.flight_id;
  SELECT aircraft_id INTO v_seat_aircraft   FROM seats   WHERE seat_id   = NEW.seat_id;

  IF v_flight_aircraft IS NULL OR v_seat_aircraft IS NULL OR v_flight_aircraft <> v_seat_aircraft THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Seat does not belong to the flight aircraft';
  END IF;

  -- Reject overbooking (no free seats)
  IF (SELECT available_seats FROM v_flight_availability WHERE flight_id = NEW.flight_id) <= 0 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'No seats available on this flight';
  END IF;
END$$
DELIMITER ;

-- 2) Auto-update total_amount when seats are allocated/released
DELIMITER $$
CREATE TRIGGER trg_booking_seats_after_insert
AFTER INSERT ON booking_seats
FOR EACH ROW
BEGIN
  DECLARE v_class ENUM('ECONOMY','BUSINESS','FIRST');
  DECLARE v_base DECIMAL(10,2);
  DECLARE v_mult DECIMAL(5,2);

  -- record history
  INSERT INTO booking_seats_history (booking_id, flight_id, seat_id, action) 
  VALUES (NEW.booking_id, NEW.flight_id, NEW.seat_id, 'ALLOCATED');

  SELECT f.base_fare INTO v_base
  FROM bookings b JOIN flights f ON f.flight_id = b.flight_id
  WHERE b.booking_id = NEW.booking_id;

  SELECT s.class INTO v_class FROM seats s WHERE s.seat_id = NEW.seat_id;
  SELECT multiplier INTO v_mult FROM fare_rules WHERE class = v_class;

  UPDATE bookings
  SET total_amount = total_amount + (v_base * v_mult)
  WHERE booking_id = NEW.booking_id;
END$$
DELIMITER ;

DELIMITER $$
CREATE TRIGGER trg_booking_seats_after_delete
AFTER DELETE ON booking_seats
FOR EACH ROW
BEGIN
  DECLARE v_class ENUM('ECONOMY','BUSINESS','FIRST');
  DECLARE v_base DECIMAL(10,2);
  DECLARE v_mult DECIMAL(5,2);

  INSERT INTO booking_seats_history (booking_id, flight_id, seat_id, action) 
  VALUES (OLD.booking_id, OLD.flight_id, OLD.seat_id, 'RELEASED');

  SELECT f.base_fare INTO v_base
  FROM bookings b JOIN flights f ON f.flight_id = b.flight_id
  WHERE b.booking_id = OLD.booking_id;

  SELECT s.class INTO v_class FROM seats s WHERE s.seat_id = OLD.seat_id;
  SELECT multiplier INTO v_mult FROM fare_rules WHERE class = v_class;

  UPDATE bookings
  SET total_amount = GREATEST(0, total_amount - (v_base * v_mult))
  WHERE booking_id = OLD.booking_id;
END$$
DELIMITER ;

-- 3) When a booking is cancelled, free its seats automatically
DELIMITER $$
CREATE TRIGGER trg_bookings_after_update
AFTER UPDATE ON bookings
FOR EACH ROW
BEGIN
  IF OLD.status = 'CONFIRMED' AND NEW.status = 'CANCELLED' THEN
    DELETE FROM booking_seats WHERE booking_id = NEW.booking_id;
  END IF;
END$$
DELIMITER ;

-- ====== Demo: Make a booking (transaction example) ======

-- Create booking shell
INSERT INTO bookings (booking_ref, flight_id, customer_id)
SELECT 'PNR12345HYD', f.flight_id, c.customer_id
FROM flights f, customers c
WHERE f.flight_no='AI501' AND c.email='aarav@example.com'
LIMIT 1;

-- Allocate 2 seats (will compute total automatically via triggers)
-- Choose any two available seats for the flight's aircraft, here 3A and 3B
INSERT INTO booking_seats (booking_id, flight_id, seat_id)
SELECT b.booking_id, b.flight_id, s.seat_id
FROM bookings b
JOIN seats s ON s.aircraft_id = (SELECT aircraft_id FROM flights WHERE flight_id = b.flight_id)
WHERE b.booking_ref='PNR12345HYD' AND s.seat_no IN ('3A','3B');

-- Verify
SELECT * FROM v_booking_summary WHERE booking_ref='PNR12345HYD';
SELECT * FROM v_flight_availability WHERE flight_no='AI501';

-- Cancel booking demo (uncomment to test):
-- UPDATE bookings SET status='CANCELLED' WHERE booking_ref='PNR12345HYD';
-- SELECT * FROM v_flight_availability WHERE flight_no='AI501';

            -- output ---
            
           -- Flight Availability
SELECT * FROM v_flight_availability;

      
	 -- Booking Summary
SELECT * FROM v_booking_summary;


    -- Available Seats for a Flight
SELECT s.seat_no, s.class
FROM flights f
JOIN seats s ON s.aircraft_id = f.aircraft_id
LEFT JOIN booking_seats bs
  ON bs.flight_id = f.flight_id AND bs.seat_id = s.seat_id
LEFT JOIN bookings b ON b.booking_id = bs.booking_id AND b.status='CONFIRMED'
WHERE f.flight_no = 'AI501' AND b.booking_id IS NULL
ORDER BY s.class, s.seat_no;
 