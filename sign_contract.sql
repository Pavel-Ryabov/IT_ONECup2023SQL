create or replace procedure sign_contract(ship_id INTEGER, island_id INTEGER) LANGUAGE PLPGSQL AS $$
declare
  capacity DOUBLE PRECISION;
  speed DOUBLE PRECISION;
  item INTEGER;
  vendor_id INTEGER;
  customer_id INTEGER;
  vendor_island INTEGER;
  customer_island INTEGER;
  quantity DOUBLE PRECISION;
  offer_id INTEGER;
  status public.contract_status;
BEGIN
  SELECT s.capacity, s.speed INTO capacity, speed FROM world.ships s WHERE s.id = ship_id;
  SELECT c.item, c.id, c.island, v.id, v.island, LEAST(c.quantity, v.quantity, capacity) as item_quantity,
    public.profit_per_unit_of_time(c.price_per_unit, LEAST(c.quantity, v.quantity, capacity), speed, vd.distance, cd.distance) as profit
  INTO item, customer_id, customer_island, vendor_id, vendor_island, quantity
  FROM world.contractors c
  JOIN world.contractors v ON v."type" = 'vendor' AND c.item = v.item
  LEFT JOIN public.contracts o ON c.id = o.customer_id
  LEFT JOIN public.distances vd ON vd.island1 = island_id AND vd.island2 = v.island
  LEFT JOIN public.distances cd ON cd.island1 = v.island AND cd.island2 = c.island
  WHERE
    c."type" = 'customer' AND o.ship is null
  GROUP BY c.item, c.id, c.island, v.id, v.island, item_quantity, vd.distance, cd.distance
  ORDER BY profit DESC
  LIMIT 1;
  raise notice 'ship % island: % vendor island: % customer island: % item: % vendor: % customer: % quantity: %',
    ship_id, island_id, vendor_island, customer_island, item, vendor_id, customer_id, quantity;
  if vendor_id is not null and customer_id is not null then
    if (vendor_island = island_id) then
      status = 'pending'::public.contract_status;
    else
      status = 'moveToVendor'::public.contract_status;
    end if;
    INSERT INTO actions.offers (contractor, quantity) VALUES (vendor_id, quantity);
    INSERT INTO actions.offers (contractor, quantity) VALUES (customer_id, quantity) RETURNING id INTO offer_id;
    INSERT INTO public.contracts (ship, status, item, vendor_island, customer_id, customer_island, quantity, offer)
      VALUES (ship_id, status, item, vendor_island, customer_id, customer_island, quantity, offer_id);
    raise notice 'offer % status %', offer_id, status;
  end if;
END $$;