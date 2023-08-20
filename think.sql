CREATE OR REPLACE PROCEDURE think(player_id INTEGER) LANGUAGE PLPGSQL AS $$
DECLARE
  _current_time DOUBLE PRECISION;
  _event RECORD;
  _contract RECORD;
  _ship_island INTEGER;
  _ship_x DOUBLE PRECISION;
  _ship_y DOUBLE PRECISION;
  _ship_capacity DOUBLE PRECISION;
  _result BOOLEAN;
  _result_island INTEGER;
  _contract_id INTEGER;
  _vendor_id INTEGER;
  _vendor_island INTEGER;
  _vendor_island_x DOUBLE PRECISION;
  _vendor_island_y DOUBLE PRECISION;
  _vendor_item INTEGER;
  _vendor_quantity DOUBLE PRECISION;
  _customer_island_x DOUBLE PRECISION;
  _customer_island_y DOUBLE PRECISION;
  _ship RECORD;
  _start_time TIMESTAMP;
  _end_time TIMESTAMP;
BEGIN
  _start_time = clock_timestamp();
  SELECT game_time INTO _current_time FROM world.global;
  INSERT INTO public.ticks(time) VALUES (_current_time);
  raise notice '[PLAYER %] time: %', player_id, _current_time;
  -- if _current_time < 250 then
  -- raise notice 'ticktime: %', _current_time;
  -- end if;

  IF _current_time = 0 THEN 
    raise notice 'sign_vendor_contracts';
    CALL sign_contracts_with_vendors(player_id);
    RETURN;
  END IF;

  -- CREATE TEMPORARY TABLE my_parked_ships ON COMMIT DROP AS
  --   SELECT p.ship, p.island, s.speed, s.capacity
  --   FROM world.parked_ships p
  --   JOIN world.ships s ON p.ship = s.id
  --   LEFT JOIN public.contracts c ON p.ship = c.ship
  --   WHERE s.player = player_id AND c.ship IS NULL
  --   ORDER BY s.capacity * s.speed DESC;

  -- for ship in select s.ship, s.island, s.speed, s.capacity from my_parked_ships s order by s.ship loop
  --   raise notice 'ship: % % % %', ship.ship, ship.island, ship.speed, ship.capacity;
  -- end loop;

  -- for mcontract in select c.ship, c.status, c.item, c.vendor_island, c.customer_island, c.quantity, c.contract, c.offer, c.vendor_offer
  --   from public.contracts c order by c.ship loop
  --   raise notice 'ship: % % % % % % % % %', mcontract.ship, mcontract.status, mcontract.item, mcontract.vendor_island, mcontract.customer_island,
  --     mcontract.quantity, mcontract.contract, mcontract.offer, mcontract.vendor_offer;
  -- end loop;

  raise notice 'offer_rejected: %', (SELECT count(*) FROM events.offer_rejected);
  FOR _event IN SELECT e.offer from events.offer_rejected e LOOP
    raise notice 'reject offer: %', _event.offer;
    UPDATE public.contracts SET status = public.get_next_status_after_reject(status) WHERE vendor_offer = _event.offer;
  END LOOP;

  raise notice 'transfer_completed: %', (SELECT count(*) FROM events.transfer_completed);
  FOR _event IN SELECT e.ship FROM events.transfer_completed e LOOP
    raise notice 'transfer_completed ship: %', _event.ship;
    UPDATE public.contracts SET status = public.get_next_status(contracts.status) WHERE ship = _event.ship AND status <> 'pending'::public.contract_status;
  END LOOP;

  raise notice 'ship_move_finished: %', (SELECT count(*) FROM events.ship_move_finished);
  FOR _event IN SELECT e.ship FROM events.ship_move_finished e LOOP
    raise notice 'move finished ship: %', _event.ship;
    UPDATE public.contracts SET status = public.get_next_status(contracts.status) WHERE ship = _event.ship AND status <> 'pending'::public.contract_status;
  END LOOP;

  raise notice 'contracts';
  FOR _contract IN
    SELECT id, ship, status, item, vendor_island, vendor_island_x, vendor_island_y,
      customer_island, customer_island_x, customer_island_y, quantity
    FROM public.contracts
    WHERE status <> 'pending'::public.contract_status
  LOOP
    CASE _contract.status
      WHEN 'moveToVendor'::public.contract_status THEN
          raise notice 'moveToVendor status ship: %', _contract.ship;
          CALL move_ship(_contract.ship, _contract.vendor_island);
          UPDATE public.contracts SET status = 'movingToVendor' WHERE id = _contract.id;
      WHEN 'moveToCustomer'::public.contract_status THEN
        raise notice 'moveToCustomer status ship: %', _contract.ship;
        IF _contract.customer_island IS NOT NULL THEN
          CALL move_ship(_contract.ship, _contract.customer_island);
          UPDATE public.contracts SET status = 'movingToCustomer' WHERE id = _contract.id;
        ELSE
          CALL find_customer(player_id, _current_time, _contract.id, _contract.item, _result_island);
          IF _result_island IS NOT NULL THEN
            CALL move_ship(_contract.ship, _result_island);
            UPDATE public.contracts SET status = 'movingToCustomer' WHERE id = _contract.id;
          ELSE
            UPDATE public.contracts SET status = 'needCustomer' WHERE id = _contract.id;
          END IF;
          _result_island = NULL;
        END IF;
      WHEN 'needVendorOnIsland'::public.contract_status, 'needVendorOnIslandAndLoad'::public.contract_status THEN
        raise notice 'needVendorOnIsland status: % ship: %', _contract.status, _contract.ship;
        SELECT capacity INTO _ship_capacity FROM world.ships WHERE id = _contract.ship;
        CALL find_vendor_on_island(_contract.id, _contract.ship, _contract.vendor_island, _ship_capacity, _contract.status, _result);
        _result = NULL;
      WHEN 'needCustomer'::public.contract_status then
          raise notice 'needCustomer status ship: %', _contract.ship;
          CALL find_customer(player_id, _current_time, _contract.id, _contract.item, _result_island);
          IF _result_island IS NOT NULL THEN
            CALL move_ship(_contract.ship, _result_island);
            UPDATE public.contracts SET status = 'movingToCustomer' WHERE id = _contract.id;
          ELSE
            CALL wait(1);
          END IF;
          _result_island = NULL;
      WHEN 'load'::public.contract_status THEN
        raise notice 'load status ship: %', _contract.ship;
        CALL load_unload(_contract.ship, _contract.item, _contract.quantity, 'load'::actions.transfer_direction);
        UPDATE public.contracts SET status = 'loading' WHERE id = _contract.id;
      WHEN 'unload'::public.contract_status THEN
        raise notice 'unload status ship: %', _contract.ship;
        CALL load_unload(_contract.ship, _contract.item, _contract.quantity, 'unload'::actions.transfer_direction);
        UPDATE public.contracts SET status = 'unloading' WHERE id = _contract.id;
      WHEN 'completed'::public.contract_status THEN
        raise notice 'completed status ship: %', _contract.ship;
        DELETE FROM public.contracts WHERE id = _contract.id;
        SELECT id, vendor_id, vendor_island, item, quantity INTO _contract_id, _vendor_id, _vendor_island, _vendor_item, _vendor_quantity
        FROM public.contracts WHERE ship = _contract.ship AND status = 'pending'::public.contract_status;
        IF _contract_id IS NOT NULL THEN
          IF _contract.customer_island = _vendor_island THEN
            CALL load_unload(_contract.ship, _vendor_item, _vendor_quantity, 'load'::actions.transfer_direction);
            UPDATE public.contracts SET status = 'loading' WHERE id = _contract_id;
          ELSE
            CALL move_ship(_contract.ship, _vendor_island);
            UPDATE public.contracts SET status = 'movingToVendor' WHERE id = _contract_id;
          END IF;
        END IF;
        _contract_id = NULL;
      WHEN 'rejected'::public.contract_status THEN
        raise notice 'rejected status ship: %', _contract.ship;
        DELETE FROM public.contracts WHERE id = _contract.id;
      WHEN 'unloading'::public.contract_status, 'movingToCustomer'::public.contract_status THEN
        raise notice 'unloading status ship: %', _contract.ship;
        SELECT id, customer_island_x, customer_island_y INTO _contract_id, _customer_island_x, _customer_island_y
        FROM public.contracts WHERE ship = _contract.ship AND status = 'pending'::public.contract_status;
        SELECT capacity INTO _ship_capacity FROM world.ships WHERE id = _contract.ship;
        IF _contract_id IS NULL THEN
          CALL find_vendor(player_id, _current_time, _contract.ship, _customer_island_x, _customer_island_y, _ship_capacity, _result);
          _result = NULL;
        END IF;
      WHEN 'loading'::public.contract_status, 'movingToVendor'::public.contract_status THEN
        raise notice 'loading status ship: %', _contract.ship;
        IF _contract.customer_island IS NULL THEN
          CALL find_customer(player_id, _current_time, _contract.id, _contract.item, _result_island);
        END IF;
      ELSE
        raise notice 'ignored status: % ship: %', _contract.status, _contract.ship;
    END CASE;
  END LOOP;

  raise notice 'parked_ships';
  FOR _ship IN
    SELECT s.id, p.island, si.x, si.y, s.speed, s.capacity
    FROM world.parked_ships p
    JOIN world.ships s ON p.ship = s.id
    JOIN world.islands si ON p.island = si.id
    LEFT JOIN public.contracts c ON p.ship = c.ship
    WHERE s.player = player_id AND c.ship IS NULL
  LOOP
    CALL find_vendor(player_id, _current_time, _ship.id, _ship.x, _ship.y, _ship.capacity, _result);
    IF _result = FALSE THEN
      CALL wait(1);
    END IF;
  END LOOP;

  CALL sign_contracts_with_customers(player_id, _current_time);

  _end_time = clock_timestamp();
  INSERT INTO public.ex_times(time) VALUES (EXTRACT(EPOCH FROM (_end_time - _start_time)));
  IF _current_time = 0 OR _current_time > 9750 THEN
    FOR _ship IN SELECT min(t.time) AS mint, max(t.time) AS maxt, avg(t.time) AS avgt FROM public.ex_times t LOOP
      raise notice 'extime: % % % ', _ship.mint, _ship.maxt, _ship.avgt;
    END LOOP;
  END IF;
END $$;