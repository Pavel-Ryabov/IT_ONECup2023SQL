CREATE OR REPLACE PROCEDURE sign_contracts_old(_current_time DOUBLE PRECISION) LANGUAGE PLPGSQL AS $$
DECLARE
  _number INTEGER = constants.ships_per_player!;
  _item INTEGER;
  _vendor_id INTEGER;
  _customer_id INTEGER;
  _vendor_island INTEGER;
  _customer_island INTEGER;
  _quantity DOUBLE PRECISION;
  _contract_quantity DOUBLE PRECISION;
  _vendor_quantity DOUBLE PRECISION;
  _offer_id INTEGER;
  _vendor_offer_id INTEGER;
  _profit DOUBLE PRECISION;
  _ship RECORD;
  _storage_quantity DOUBLE PRECISION;
  _cust_vend_distance DOUBLE PRECISION;
  _vend_ship_distance DOUBLE PRECISION;
  _time_comp DOUBLE PRECISION;
  _time_diff DOUBLE PRECISION;
BEGIN
  -- IF _current_time = 0 THEN 
  --   _number = _number * 0.6;
  -- END IF;
  FOR _ship IN 
    SELECT ship, island, speed, capacity FROM my_parked_ships LIMIT _number
  LOOP
    SELECT c.item, c.id, c.island, v.id, v.island, LEAST(c.quantity, v.quantity, _ship.capacity) as item_quantity,
      public.profit_per_unit_of_time(c.price_per_unit, v.price_per_unit, LEAST(c.quantity, v.quantity, _ship.capacity), _ship.speed,
      public.distance(si.x, si.y, vi.x, vi.y), public.distance(ci.x, ci.y, vi.x, vi.y)) as profit,
      public.distance(si.x, si.y, vi.x, vi.y), public.distance(ci.x, ci.y, vi.x, vi.y)
    INTO _item, _customer_id, _customer_island, _vendor_id, _vendor_island, _quantity, _profit, _vend_ship_distance, _cust_vend_distance
    FROM world.contractors c
    JOIN world.contractors v ON v."type" = 'vendor' AND c.item = v.item
    LEFT JOIN public.contracts oc ON c.id = oc.customer_id
    JOIN world.islands si ON si.id = _ship.island
    JOIN world.islands vi ON vi.id = v.island
    JOIN world.islands ci ON ci.id = c.island
    WHERE c."type" = 'customer' AND oc.ship is null
    ORDER BY profit DESC
    LIMIT 1;

    raise notice 'ship % island: % vendor island: % customer island: % item: % vendor: % customer: % quantity: % profit: %',
      _ship.ship, _ship.island, _vendor_island, _customer_island, _item, _vendor_id, _customer_id, _quantity, _profit;
    IF _vendor_id IS NOT NULL AND _customer_id IS NOT NULL THEN
      _time_comp = public.get_ex_time(_quantity, _ship.speed, _cust_vend_distance + _vend_ship_distance) + _current_time;
      raise notice '_time_comp: %', _time_comp;
      IF _time_comp + constants.reserved_time! > constants.max_time! THEN
        _time_diff = _time_comp + constants.reserved_time! - constants.max_time!;
        raise notice '_time_diff: %', _time_diff;
        IF _quantity > _time_diff / constants.transfer_time_per_unit! THEN
          _quantity = _quantity - _time_diff / constants.transfer_time_per_unit!;
          raise notice 'quantity changed to: %', _quantity;
        ELSE
          raise notice 'cancel contract';
          CONTINUE;
        END IF;
      END IF;

      _vendor_quantity = _quantity;
      SELECT quantity INTO _storage_quantity FROM public.storage WHERE island = _vendor_island AND item = _item;
      raise notice '_quantity: %', _quantity;
      raise notice '_storage_quantity: %', _storage_quantity;
      IF _storage_quantity IS NOT NULL AND THEN
        _vendor_quantity = _quantity - _storage_quantity;
        raise notice '_quantity aft sub: %', _quantity;
        IF _storage_quantity - _quantity > 0 THEN
          UPDATE public.storage SET quantity = quantity - _quantity WHERE island = _vendor_island AND item = _item;
        ELSE 
          DELETE FROM public.storage WHERE island = _vendor_island AND item = _item;
        END IF;
      END IF;
      IF _vendor_quantity > 0 THEN
        INSERT INTO actions.offers (contractor, quantity) VALUES (_vendor_id, _vendor_quantity) RETURNING id INTO _vendor_offer_id;
        UPDATE world.contractors SET quantity = quantity - _vendor_quantity WHERE id = _vendor_id;
      END IF;
      _contract_quantity = _quantity - 1e-12;
      INSERT INTO actions.offers (contractor, quantity) VALUES (_customer_id, _contract_quantity) RETURNING id INTO _offer_id;
      INSERT INTO public.contracts (ship, status, item, vendor_id, vendor_island, customer_id, customer_island, quantity, offer, vendor_offer)
        VALUES (_ship.ship, 'pending'::public.contract_status, _item, _vendor_id, _vendor_island, _customer_id, _customer_island, _contract_quantity, _offer_id, _vendor_offer_id);
      raise notice 'ship % isalnd % offer % vendor offer %', _ship.ship, _ship.island, _offer_id, _vendor_offer_id;
    END IF;
  END LOOP;
END $$;

CREATE OR REPLACE PROCEDURE sign_contracts(_current_time DOUBLE PRECISION) LANGUAGE PLPGSQL AS $$
DECLARE
  _number INTEGER;
  _item INTEGER;
  _vendor_id INTEGER;
  _customer_id INTEGER;
  _vendor_island INTEGER;
  _customer_island INTEGER;
  _quantity DOUBLE PRECISION;
  _contract_quantity DOUBLE PRECISION;
  _vendor_quantity DOUBLE PRECISION;
  _offer_id INTEGER;
  _vendor_offer_id INTEGER;
  _profit DOUBLE PRECISION;
  _nearest_ship INTEGER;
  _nearest_ship_island INTEGER;
  _nearest_ship_speed DOUBLE PRECISION;
  _cust_vend_distance DOUBLE PRECISION;
  _vend_ship_distance DOUBLE PRECISION;
  _time_comp DOUBLE PRECISION;
  _time_diff DOUBLE PRECISION;
  _storage_quantity DOUBLE PRECISION;
  --_ship RECORD;
BEGIN
  SELECT count(ship) INTO _number FROM my_parked_ships;
  -- IF _current_time = 0 THEN 
  --   _number = _number * 0.6;
  -- END IF;
  raise notice 'sign_contracts: %', _number;

  --for _ship in select s.ship, s.island, s.speed, s.capacity from my_parked_ships s loop
  --  raise notice 'ship: % % % %', _ship.ship, _ship.island, _ship.speed, _ship.capacity;
  --end loop;

  FOR i IN 1.._number LOOP
    _nearest_ship = NULL;
    SELECT c.item, c.id, c.island, v.id, v.island, LEAST(c.quantity, v.quantity) as item_quantity,
      public.profit_per_unit_of_time(c.price_per_unit, v.price_per_unit, LEAST(c.quantity, v.quantity), public.distance(ci.x, ci.y, vi.x, vi.y)) as profit,
      public.distance(ci.x, ci.y, vi.x, vi.y) as distance
    INTO _item, _customer_id, _customer_island, _vendor_id, _vendor_island, _quantity, _profit, _cust_vend_distance
    FROM world.contractors c
    JOIN world.contractors v ON v."type" = 'vendor' AND c.item = v.item
    LEFT JOIN public.contracts oc ON c.id = oc.customer_id
    JOIN world.islands ci ON ci.id = c.island
    JOIN world.islands vi ON vi.id = v.island
    WHERE c."type" = 'customer' AND oc.ship IS NULL
    ORDER BY profit DESC
    LIMIT 1;

    raise notice 'vendor island: % customer island: % item: % vendor: % customer: % quantity: % profit: %',
      _vendor_island, _customer_island, _item, _vendor_id, _customer_id, _quantity, _profit;

    IF _vendor_id IS NOT NULL AND _customer_id IS NOT NULL THEN
      SELECT s.ship, s.island, s.speed, LEAST(s.capacity, _quantity) as quantity, public.distance(si.x, si.y, vi.x, vi.y) as distance,
        public.profit_per_unit_of_time(s.capacity, _quantity, s.speed, public.distance(si.x, si.y, vi.x, vi.y), _profit) as profit
      INTO _nearest_ship, _nearest_ship_island, _nearest_ship_speed, _quantity, _vend_ship_distance
      FROM my_parked_ships s
      JOIN world.islands si ON si.id = s.island
      JOIN world.islands vi ON vi.id = _vendor_island
      ORDER BY profit DESC
      LIMIT 1;

      _time_comp = public.get_ex_time(_quantity, _nearest_ship_speed, _cust_vend_distance + _vend_ship_distance) + _current_time;
      raise notice '_time_comp: %', _time_comp;
      IF _time_comp + constants.reserved_time! > constants.max_time! THEN
        _time_diff = _time_comp + constants.reserved_time! - constants.max_time!;
        raise notice '_time_diff: %', _time_diff;
        IF _quantity > _time_diff / constants.transfer_time_per_unit! THEN
          _quantity = _quantity - _time_diff / constants.transfer_time_per_unit!;
          raise notice 'quantity changed to: %', _quantity;
        ELSE
          raise notice 'cancel contract';
          RETURN;
        END IF;
      END IF; 

      _vendor_quantity = _quantity;
      SELECT quantity INTO _storage_quantity FROM public.storage WHERE island = _vendor_island AND item = _item;
      raise notice '_quantity: %', _quantity;
      raise notice '_storage_quantity: %', _storage_quantity;
      IF _storage_quantity IS NOT NULL AND THEN
        _vendor_quantity = _quantity - _storage_quantity;
        raise notice '_quantity aft sub: %', _quantity;
        IF _storage_quantity - _quantity > 0 THEN
          UPDATE public.storage SET quantity = quantity - _quantity WHERE island = _vendor_island AND item = _item;
        ELSE 
          DELETE FROM public.storage WHERE island = _vendor_island AND item = _item;
        END IF;
      END IF;
      IF _vendor_quantity > 0 THEN
        INSERT INTO actions.offers (contractor, quantity) VALUES (_vendor_id, _vendor_quantity) RETURNING id INTO _vendor_offer_id;
        UPDATE world.contractors SET quantity = quantity - _vendor_quantity WHERE id = _vendor_id;
      END IF;
      _contract_quantity = _quantity - 1e-12;
      INSERT INTO actions.offers (contractor, quantity) VALUES (_customer_id, _contract_quantity) RETURNING id INTO _offer_id;
      raise notice 'ship % isalnd % offer % vendor offer %', _nearest_ship, _nearest_ship_island, _offer_id, _vendor_offer_id;
      INSERT INTO public.contracts (ship, status, item, vendor_id, vendor_island, customer_id, customer_island, quantity, offer, vendor_offer)
        VALUES (_nearest_ship, 'pending'::public.contract_status, _item, _vendor_id, _vendor_island, _customer_id, _customer_island, _contract_quantity, _offer_id, _vendor_offer_id);
      DELETE FROM my_parked_ships WHERE ship = _nearest_ship;
    END IF;
  END LOOP;
END $$;


CREATE OR REPLACE PROCEDURE find_vendor(_ship INTEGER, _item INTEGER, _customer_island INTEGER, _quantity DOUBLE PRECISION) LANGUAGE PLPGSQL AS $$
DECLARE
   _ship_island INTEGER;
  _vendor_id INTEGER;
  _vendor_island INTEGER;
  _vendor_offer_id INTEGER;
BEGIN
  SELECT island FROM world.parked_ships s INTO _ship_island WHERE s.ship = _ship;

  SELECT v.id, v.island, public.profit_per_unit_of_time(v.price_per_unit, 0, _quantity, public.distance(si.x, si.y, vi.x, vi.y)) as profit
    INTO _vendor_id, _vendor_island
    FROM world.contractors v
    JOIN world.islands si ON si.id = _ship_island
    JOIN world.islands vi ON vi.id = v.island
    WHERE v."type" = 'vendor' AND v.item = _item AND v.quantity >= _quantity
    ORDER BY profit DESC
    LIMIT 1;

    IF _vendor_id IS NOT NULL THEN
      INSERT INTO actions.offers (contractor, quantity) VALUES (_vendor_id, _quantity) RETURNING id INTO _vendor_offer_id;
      UPDATE public.contracts SET vendor_id = _vendor_id, vendor_island = _vendor_island, status = 'pending'::public.contract_status, vendor_offer = _vendor_offer_id
        WHERE ship = _ship;
      UPDATE world.contractors SET quantity = quantity - _quantity WHERE id = _vendor_id;
      raise notice 'found vendor ship % island % vendor_island % vendor offer %', _ship, _ship_island, _vendor_island, _vendor_offer_id;
    END IF;
END $$;

CREATE OR REPLACE PROCEDURE find_customer(_ship INTEGER, _item INTEGER, _vendor_island INTEGER, _quantity DOUBLE PRECISION) LANGUAGE PLPGSQL AS $$
DECLARE
  _customer_id INTEGER;
  _customer_island INTEGER;
  _found_quantity DOUBLE PRECISION;
  _offer_id INTEGER;
BEGIN
raise notice 'find_customer';
  SELECT c.id, c.island, LEAST(c.quantity, _quantity) as quantity, public.profit_per_unit_of_time(c.price_per_unit, 0, LEAST(c.quantity, _quantity),
    public.distance(ci.x, ci.y, vi.x, vi.y)) as profit
  INTO _customer_id, _customer_island, _found_quantity
  FROM world.contractors c
  LEFT JOIN public.contracts oc ON c.id = oc.customer_id
  JOIN world.islands ci ON ci.id = c.island
  JOIN world.islands vi ON vi.id = _vendor_island
  WHERE c."type" = 'customer' AND c.item = _item AND oc.ship IS NULL
  ORDER BY profit DESC
  LIMIT 1;

  IF _customer_id IS NOT NULL THEN
  raise notice 'found';
    INSERT INTO actions.offers (contractor, quantity) VALUES (_customer_id, _found_quantity) RETURNING id INTO _offer_id;
    UPDATE public.contracts SET customer_id = _customer_id, customer_island = _customer_island, status = 'pending'::public.contract_status, offer = _offer_id
      WHERE ship = _ship;
    raise notice 'found customer ship % vendor_island % customer id % customer_island % found quantity % offer %',
      _ship, _vendor_island, _customer_id, _customer_island, _found_quantity, _offer_id;
  ELSE
  raise notice 'notfound';
    INSERT INTO public.storage (island, item, quantity)
      VALUES(_vendor_island, _item, _quantity) 
      ON CONFLICT ON CONSTRAINT pkey_storage DO UPDATE SET quantity = public.storage.quantity + _quantity; 
    DELETE FROM public.contracts WHERE ship = _ship;
  END IF;
END $$;