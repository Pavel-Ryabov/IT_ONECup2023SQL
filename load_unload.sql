create or replace procedure load_unload(ship INTEGER, item INTEGER, quantity DOUBLE PRECISION, direction actions.transfer_direction) as $$
begin
  raise notice 'load_unload ship: % item: % quantity: % direction: %', ship, item, quantity, direction;
  insert into actions.transfers values (ship, item, quantity, direction);
end
$$ language plpgsql;
