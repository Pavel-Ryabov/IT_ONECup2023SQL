CREATE OR REPLACE PROCEDURE sign_contracts_with_customers(_player INTEGER, _current_time DOUBLE PRECISION) LANGUAGE PLPGSQL AS $$
DECLARE
  _contractor RECORD;
  _contract RECORD;
  _quantity DOUBLE PRECISION;
  _min_price DOUBLE PRECISION;
  _max_price DOUBLE PRECISION;
BEGIN
  IF _current_time < 9000 THEN
    _min_price = 20;
    _max_price = 25;
  ELSE
    _min_price = 15;
    _max_price = 20;
  END IF;
  FOR _contractor IN 
    SELECT c.id, c.quantity as customer_quantity, s.quantity as storage_quantity, c.price_per_unit as price
    FROM world.contractors c
    LEFT JOIN world.contracts co ON co.contractor = c.id
    LEFT JOIN world.storage s ON s.player = _player AND s.island = c.island AND s.item = c.item
    WHERE co.contractor IS NULL AND c.type = 'customer' AND c.price_per_unit > _min_price
  LOOP
    raise notice 'customer price: % customer_quantity: % storage_quantity: %', _contractor.price, _contractor.customer_quantity, _contractor.storage_quantity;
    IF _contractor.price >= _max_price THEN
      _quantity = _contractor.customer_quantity;
    ELSEIF _contractor.storage_quantity > 0 THEN
      _quantity = LEAST(_contractor.customer_quantity, _contractor.storage_quantity);
    END IF;
    IF _quantity IS NOT NULL THEN
      INSERT INTO actions.offers (contractor, quantity) VALUES (_contractor.id, _quantity);
      DELETE FROM world.contractors WHERE id = _contractor.id;
      raise notice 'customer contract id: % quantity: %', _contractor.id, _quantity;
    END IF;
  END LOOP;
END $$;

CREATE OR REPLACE PROCEDURE find_customer(_player INTEGER, _current_time DOUBLE PRECISION, _contract_id INTEGER, _item INTEGER, INOUT _island INTEGER) LANGUAGE PLPGSQL AS $$
DECLARE
  _customer_island INTEGER;
  _customer_island_x DOUBLE PRECISION;
  _customer_island_y DOUBLE PRECISION;
  _price DOUBLE PRECISION;
BEGIN
  SELECT c.island INTO _customer_island
  FROM world.contracts co
  JOIN world.contractors c ON c.id = co.contractor
  LEFT JOIN world.storage st ON st.player = _player AND st.island = c.island AND st.item = _item
  WHERE c.item = _item AND (st.quantity IS NULL OR st.quantity < 1000)
  ORDER BY c.price_per_unit DESC
  LIMIT 1;

  IF _customer_island IS NULL THEN
    IF _current_time < 8000 THEN
      _price = 20;
    ELSE
      _price = 15;
    END IF;
    SELECT c.island INTO _customer_island
    FROM world.contractors c
    LEFT JOIN world.storage st ON st.player = _player AND st.island = c.island AND st.item = _item
    WHERE c.type = 'customer' AND c.item = _item AND c.price_per_unit > _price AND (st.quantity IS NULL OR st.quantity < 1000)
    ORDER BY c.price_per_unit DESC
    LIMIT 1;
  END IF;

  IF _customer_island IS NOT NULL THEN
    SELECT x, y INTO _customer_island_x, _customer_island_y FROM world.islands WHERE id = _customer_island;
    UPDATE public.contracts SET customer_island = _customer_island, customer_island_x = _customer_island_x, customer_island_y = _customer_island_y
    WHERE id = _contract_id;
    raise notice 'found customer: island %', _customer_island;
    _island = _customer_island;
  ELSE
    _island =  NULL;
  END IF;
END $$;