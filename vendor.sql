CREATE OR REPLACE PROCEDURE sign_contracts_with_vendors(_player INTEGER) LANGUAGE PLPGSQL AS $$
DECLARE
  _vendor_island_x DOUBLE PRECISION;
  _vendor_island_y DOUBLE PRECISION;
  _vendor_offer_id INTEGER;
  _contractor RECORD;
  _ship INTEGER;
  _ship_island INTEGER;
  _status public.contract_status;
BEGIN

  FOR _contractor IN
    SELECT v.id, v.item, v.quantity, v.island, v.price_per_unit as price
    FROM world.contractors v
    WHERE v.type = 'vendor'
    ORDER BY v.price_per_unit
    LIMIT 10
  LOOP
    SELECT x, y INTO _vendor_island_x, _vendor_island_y FROM world.islands WHERE id = _contractor.island;

    SELECT p.ship, p.island, LEAST(_contractor.quantity, s.capacity) as quantity, public.distance(si.x, si.y, _vendor_island_x, _vendor_island_y) as distance
    INTO _ship, _ship_island, _contractor.quantity
    FROM world.parked_ships p
    JOIN world.ships s ON s.player = _player AND s.id = p.ship
    JOIN world.islands si ON si.id = p.island
    ORDER BY distance
    LIMIT 1;

    INSERT INTO actions.offers (contractor, quantity) VALUES (_contractor.id, _contractor.quantity) RETURNING id INTO _vendor_offer_id;
    IF _ship_island = _contractor.island THEN
      CALL load_unload(_ship, _contractor.item, _contractor.quantity, 'load'::actions.transfer_direction);
      _status = 'loading';
    ELSE
      CALL move_ship(_ship, _contractor.island);
      _status = 'movingToVendor';
    END IF;

    INSERT INTO public.contracts (ship, status, item, vendor_id, vendor_island, vendor_island_x, vendor_island_y, vendor_price, quantity, vendor_offer)
      VALUES (_ship, _status, _contractor.item, _contractor.id, _contractor.island, _vendor_island_x, _vendor_island_y,
        _contractor.price, _contractor.quantity, _vendor_offer_id);
    DELETE FROM world.parked_ships WHERE ship = _ship;
    raise notice 'vendor contract ship: % vendor: % vendor island: % item: % quantity: % price: % offer: %',
      _ship, _contractor.id, _contractor.island, _contractor.item, _contractor.quantity, _contractor.price, _vendor_offer_id;
  END LOOP;
END $$;


CREATE OR REPLACE PROCEDURE find_vendor(_player INTEGER, _current_time DOUBLE PRECISION, _ship INTEGER, _ship_x DOUBLE PRECISION, _ship_y DOUBLE PRECISION,
  _ship_capacity DOUBLE PRECISION, INOUT _result BOOLEAN) LANGUAGE PLPGSQL AS $$
DECLARE
  _vendor_id INTEGER;
  _vendor_item INTEGER;
  _vendor_island INTEGER;
  _vendor_island_x DOUBLE PRECISION;
  _vendor_island_y DOUBLE PRECISION;
  _vendor_price INTEGER;
  _vendor_offer_id INTEGER;
  _quantity DOUBLE PRECISION;
BEGIN
  IF _current_time > 9000 THEN
    RETURN;
  END IF;
  SELECT v.id, v.item, v.island, vi.x, vi.y, LEAST(v.quantity, _ship_capacity) as quantity, v.price_per_unit as price,
    public.distance(_ship_x, _ship_y, vi.x, vi.y) / GREATEST(1, (LEAST(v.quantity, _ship_capacity))) as distance
  INTO _vendor_id, _vendor_item, _vendor_island, _vendor_island_x, _vendor_island_y, _quantity, _vendor_price
  FROM world.contractors v
  JOIN world.islands vi ON vi.id = v.island
  WHERE v.type = 'vendor' AND v.quantity > 0 AND v.price_per_unit < 10
    AND (SELECT sum(st.quantity) as sum FROM world.storage st WHERE st.player = _player AND st.item = v.item GROUP BY st.player, st.item) < 2000
  ORDER BY distance
  LIMIT 1;

  IF _vendor_id IS NOT NULL THEN
    INSERT INTO actions.offers (contractor, quantity) VALUES (_vendor_id, _quantity) RETURNING id INTO _vendor_offer_id;
    UPDATE world.contractors SET quantity = quantity - _quantity WHERE id = _vendor_id;
    INSERT INTO public.contracts (ship, status, item, vendor_id, vendor_island, vendor_island_x, vendor_island_y, vendor_price, quantity, vendor_offer)
      VALUES (_ship, 'pending'::public.contract_status, _vendor_item, _vendor_id, _vendor_island, _vendor_island_x, _vendor_island_y,
        _vendor_price, _quantity, _vendor_offer_id);

    raise notice 'found vendor ship: % vendor: % vendor island: % item: % quantity: % price: % offer: %',
        _ship, _vendor_id, _vendor_island, _vendor_item, _quantity, _vendor_price, _vendor_offer_id;
    _result = TRUE;
  ELSE
    _result = FALSE;
  END IF;
END $$;

CREATE OR REPLACE PROCEDURE find_vendor_on_island(_contract_id INTEGER, _ship INTEGER, _ship_island INTEGER,
  _ship_capacity DOUBLE PRECISION, _status public.contract_status) LANGUAGE PLPGSQL AS $$
DECLARE
  _vendor_id INTEGER;
  _vendor_item INTEGER;
  _vendor_price INTEGER;
  _vendor_offer_id INTEGER;
  _quantity DOUBLE PRECISION;
BEGIN
  SELECT v.id, v.item, LEAST(v.quantity, _ship_capacity) as quantity, v.price_per_unit as price
  INTO _vendor_id, _vendor_item, _quantity, _vendor_price
  FROM world.contractors v
  WHERE v.type = 'vendor' AND v.price_per_unit < 10 AND v.island = _ship_island
  ORDER BY v.price_per_unit
  LIMIT 1;

  IF _vendor_id IS NOT NULL THEN
    INSERT INTO actions.offers (contractor, quantity) VALUES (_vendor_id, _quantity) RETURNING id INTO _vendor_offer_id;
    UPDATE world.contractors SET quantity = quantity - _quantity WHERE id = _vendor_id;

    raise notice 'found vendor on island ship: % vendor: % vendor island: % item: % quantity: % price: % offer: %',
        _ship, _vendor_id, _vendor_island, _vendor_item, _quantity, _vendor_price, _vendor_offer_id;

    IF _status = 'needVendorOnIslandAndLoad'::public.contract_status THEN
      CALL load_unload(_ship, _vendor_item, _quantity, 'load'::actions.transfer_direction);
      _status = 'loading';
    ELSE
      CALL move_ship(_ship, _vendor_island);
      _status = 'movingToVendor';
    END IF;

    UPDATE public.contracts SET vendor_id = _vendor_id, item = _vendor_item, quantity = _quantity, vendor_price = _vendor_price, 
      vendor_offer = _vendor_offer_id, status = _status, customer_island = NULL
    WHERE id = _contract_id;
  ELSE
    CALL wait(1);
  END IF;
END $$;