create or replace procedure move_ship(ship_id integer, island_id integer) as $$
begin
  raise notice 'move_ship ship: % island: %', ship_id, island_id;
  insert into actions.ship_moves (ship, destination) values (ship_id, island_id);
end
$$ language plpgsql;