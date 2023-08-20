-- CREATE INDEX IF NOT EXISTS parked_ships_idx ON world.parked_ships(ship);
CREATE INDEX IF NOT EXISTS contractors_type_price_idx ON world.contractors(type, price_per_unit);
-- CREATE INDEX IF NOT EXISTS contractors_island_idx ON world.contractors(island);