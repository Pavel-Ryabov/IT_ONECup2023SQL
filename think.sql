CREATE OR REPLACE PROCEDURE think(player_id INTEGER) LANGUAGE PLPGSQL AS $$
declare
  currentTime DOUBLE PRECISION;
  ship RECORD;
  _ship_island INTEGER;
  _vendor_island INTEGER;
  econtract RECORD;
  mcontract RECORD;
  _start_time TIMESTAMP;
  _end_time TIMESTAMP;
BEGIN
  _start_time = clock_timestamp();
  select game_time into currentTime from world.global;
  insert into public.ticks(time) values (currentTime);
  raise notice '[PLAYER %] time: %', player_id, currentTime;
  -- if currentTime < 500 then
  -- raise notice 'ticktime: %', currentTime;
  -- end if;

  -- if currentTime = 0 then
  --   call public.init();
  -- end if;

  CREATE TEMPORARY TABLE my_parked_ships ON COMMIT DROP AS
    SELECT p.ship, p.island, s.speed, s.capacity
    FROM world.parked_ships p
    JOIN world.ships s ON p.ship = s.id
    LEFT JOIN public.contracts c ON p.ship = c.ship
    WHERE s.player = player_id AND c.ship IS NULL
    ORDER BY s.capacity * s.speed DESC;

  if currentTime = 0 then 
    raise notice 'sign_contracts';
    call sign_contracts(currentTime);
    call wait(currentTime + 1);
    return;
  end if;

  -- for ship in select s.ship, s.island, s.speed, s.capacity from my_parked_ships s order by s.ship loop
  --   raise notice 'ship: % % % %', ship.ship, ship.island, ship.speed, ship.capacity;
  -- end loop;

  -- for mcontract in select c.ship, c.status, c.item, c.vendor_island, c.customer_island, c.quantity, c.contract, c.offer, c.vendor_offer
  --   from public.contracts c order by c.ship loop
  --   raise notice 'ship: % % % % % % % % %', mcontract.ship, mcontract.status, mcontract.item, mcontract.vendor_island, mcontract.customer_island,
  --     mcontract.quantity, mcontract.contract, mcontract.offer, mcontract.vendor_offer;
  -- end loop;

  raise notice 'contract_started: %', (select count(*) from events.contract_started s);
  for econtract in
    select s.offer, s.contract
    from events.contract_started s
    loop
      raise notice 'start contract: % offer: %', econtract.contract, econtract.offer;
      SELECT p.island, c.vendor_island
      INTO _ship_island, _vendor_island
      FROM public.contracts c
      JOIN world.parked_ships p ON p.ship = c.ship
      WHERE c.offer = econtract.offer OR c.vendor_offer = econtract.offer;
      raise notice 'start island: % vendor_island %', _ship_island, _vendor_island;
      IF _vendor_island = _ship_island THEN
        UPDATE public.contracts SET
          status = 'load'::public.contract_status,
          contract = CASE WHEN econtract.contract IS NULL THEN contract ELSE econtract.contract END
        WHERE offer = econtract.offer OR vendor_offer = econtract.offer;
      ELSE
        UPDATE public.contracts SET
          status = 'moveToVendor'::public.contract_status,
          contract = CASE WHEN econtract.contract IS NULL THEN contract ELSE econtract.contract END
        WHERE offer = econtract.offer OR vendor_offer = econtract.offer;
      END IF;
    end loop;

  raise notice 'offer_rejected: %', (select count(*) from events.offer_rejected r);
  for econtract in
    select r.offer
    from events.offer_rejected r
    loop
      raise notice 'reject offer: %', econtract.offer;
      UPDATE public.contracts SET
        status = CASE WHEN status = 'needCustomer'::public.contract_status THEN 'rejected'::public.contract_status ELSE 'needVendor'::public.contract_status END
      WHERE vendor_offer = econtract.offer;
      UPDATE public.contracts SET
        status = CASE WHEN status = 'needVendor'::public.contract_status THEN 'rejected'::public.contract_status ELSE 'needCustomer'::public.contract_status END
      WHERE offer = econtract.offer;
    end loop;

  raise notice 'contract_completed: %', (select count(*) from events.contract_completed cc);
  for econtract in
    select cc.contract
    from events.contract_completed cc
    loop
      raise notice 'complete contract: %', econtract.contract;
      DELETE FROM public.contracts WHERE contract = econtract.contract;
    end loop;

  raise notice 'transfer_completed: %', (select count(*) from events.transfer_completed tc);
  for ship in
    select tc.ship
    from events.transfer_completed tc
    loop
      raise notice 'transfer_completed ship: %', ship.ship;
      UPDATE public.contracts SET status = public.get_next_status(contracts.status) WHERE contracts.ship = ship.ship;
    end loop;

  raise notice 'ship_move_finished: %', (select count(*) from events.ship_move_finished mf);
  for ship in
    select mf.ship
    from events.ship_move_finished mf
    loop
      raise notice 'move finished ship: %', ship.ship;
      UPDATE public.contracts SET status = public.get_next_status(contracts.status) WHERE contracts.ship = ship.ship;
    end loop;

  raise notice 'contracts';
  for mcontract in
    select c.ship, c.status, c.item, c.vendor_island, c.customer_island, c.quantity, c.contract
    from public.contracts c
    order by c.ship
    loop
      case mcontract.status
        when 'needVendor'::public.contract_status then
          raise notice 'needVendor status ship: %', mcontract.ship;
          call find_vendor(mcontract.ship, mcontract.item, mcontract.customer_island, mcontract.quantity);
        when 'needCustomer'::public.contract_status then
          raise notice 'needCustomer status ship: %', mcontract.ship;
          call find_customer(mcontract.ship, mcontract.item, mcontract.vendor_island, mcontract.quantity);
        when 'load'::public.contract_status then
          raise notice 'load status ship: %', mcontract.ship;
          raise notice 'storage: %', (select s.quantity from world.storage s where s.player = player_id and s.island = mcontract.vendor_island and s.item = mcontract.item);
          call load_unload(mcontract.ship, mcontract.item, mcontract.quantity, 'load'::actions.transfer_direction);
          UPDATE public.contracts SET status = 'loading' WHERE contracts.ship = mcontract.ship;
        when 'unload'::public.contract_status then
          raise notice 'unload status ship: %', mcontract.ship;
          raise notice 'cargo: %', (select c.quantity from world.cargo c where c.ship = mcontract.ship and c.item = mcontract.item);
          call load_unload(mcontract.ship, mcontract.item, mcontract.quantity, 'unload'::actions.transfer_direction);
          UPDATE public.contracts SET status = 'unloading' WHERE contracts.ship = mcontract.ship;
        when 'moveToCustomer'::public.contract_status, 'moveToVendor'::public.contract_status then
          raise notice 'moveToCustomer moveToVendor status ship: %', mcontract.ship;
          call move_ship(mcontract.ship, public.get_target_island(mcontract.status, mcontract.vendor_island, mcontract.customer_island));
          UPDATE public.contracts SET status = public.get_next_status(mcontract.status) WHERE contracts.ship = mcontract.ship;
        when 'completed'::public.contract_status, 'rejected'::public.contract_status then
          raise notice 'completed rejected status ship: %', mcontract.ship;
          DELETE FROM public.contracts WHERE contracts.ship = mcontract.ship;
        else
          raise notice 'ignored status: % ship: %', mcontract.status, mcontract.ship;
		  end case;
    end loop;

  raise notice 'sign_contracts';
  call sign_contracts(currentTime);

  -- raise notice 'contracts %', (SELECT count(contracts.ship) FROM public.contracts);
  -- raise notice 'parked %', (SELECT count(s.ship) FROM my_parked_ships s);
  -- if (SELECT count(contracts.ship) FROM public.contracts) < (SELECT count(s.ship) FROM my_parked_ships s) then
  if (SELECT count(s.ship) FROM my_parked_ships s) > 0 then
    call wait(currentTime + 1) ;
  end if;
  _end_time = clock_timestamp();
  insert into public.ex_times(time) values (EXTRACT(EPOCH FROM (_end_time - _start_time)));
  if currentTime = 0 OR currentTime > 9750 then
  for ship in select min(t.time) as mint, max(t.time) as maxt, avg(t.time) as avgt from public.ex_times t loop
    raise notice 'extime: % % % ', ship.mint, ship.maxt, ship.avgt;
  end loop;
  end if;
END $$;