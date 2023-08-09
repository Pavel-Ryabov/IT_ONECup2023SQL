CREATE OR REPLACE PROCEDURE think(player_id INTEGER) LANGUAGE PLPGSQL AS $$
declare
  currentTime DOUBLE PRECISION;
  myMoney DOUBLE PRECISION;
  ship RECORD;
  econtract RECORD;
  mcontract RECORD;
BEGIN
  select game_time into currentTime from world.global;
  --select money into myMoney from world.players where id=player_id;
  raise notice '[PLAYER %] time: %', player_id, currentTime;

  if currentTime = 0 then
    call public.init();
  end if;

  raise notice 'contract_started: %', (select count(*) from events.contract_started s);
  for econtract in
    select s.offer, s.contract
    from events.contract_started s
    where s.contract is not null
    loop
      raise notice 'loading contract: % offer: %', econtract.contract, econtract.offer;
      UPDATE public.contracts SET status = 'load'::public.contract_status, contract = econtract.contract WHERE offer = econtract.offer AND status = 'pending';
    end loop;

  raise notice 'offer_rejected: %', (select count(*) from events.offer_rejected r);
  for econtract in
    select r.offer
    from events.offer_rejected r
    loop
      raise notice 'reject offer: %', econtract.offer;
      DELETE FROM public.contracts WHERE offer = econtract.offer;
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
    loop
      case mcontract.status
        when 'load'::public.contract_status then
          raise notice 'load status ship: %', mcontract.ship;
          call load_unload(mcontract.ship, mcontract.item, mcontract.quantity, 'load'::actions.transfer_direction);
          UPDATE public.contracts SET status = 'loading' WHERE contracts.ship = mcontract.ship;
        when 'unload'::public.contract_status then
          raise notice 'unload status ship: %', mcontract.ship;
          call load_unload(mcontract.ship, mcontract.item, mcontract.quantity, 'unload'::actions.transfer_direction);
          UPDATE public.contracts SET status = 'unloading' WHERE contracts.ship = mcontract.ship;
        when 'moveToCustomer'::public.contract_status, 'moveToVendor'::public.contract_status then
          raise notice 'moveToCustomer moveToVendor status ship: %', mcontract.ship;
          call move_ship(mcontract.ship, public.get_target_island(mcontract.status, mcontract.vendor_island, mcontract.customer_island));
          UPDATE public.contracts SET status = public.get_next_status(mcontract.status) WHERE contracts.ship = mcontract.ship;
        when 'completed'::public.contract_status then
          raise notice 'completed status ship: %', mcontract.ship;
          DELETE FROM public.contracts WHERE contracts.ship = mcontract.ship;
          call wait(currentTime + 0.01) ;
        else
          raise notice 'ignored status: % ship: %', mcontract.status, mcontract.ship;
		  end case;
    end loop;

  for ship in
    select
        ships.id as ship,
        parked_ships.island
    from world.ships
    join world.parked_ships
        on ships.id=parked_ships.ship
        and ships.player=player_id
    left join public.contracts
        on contracts.ship = parked_ships.ship
    where contracts.ship is null
    loop
        call sign_contract(ship.ship, ship.island);
        if (SELECT contracts.ship FROM public.contracts WHERE contracts.ship = ship.ship) is null then
          call move_ship(ship.ship, ship.island % 10 + 1);
        end if;
    end loop;
    if (SELECT count(contracts.ship) FROM public.contracts) = 0 then
      call wait(currentTime + 0.01) ;
    end if;
END $$;