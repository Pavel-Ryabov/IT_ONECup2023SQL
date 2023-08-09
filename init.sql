create or replace procedure public.init() as $$
begin
  raise notice 'init';
  INSERT INTO public.distances (island1, island2, distance)
  SELECT i1.id, i2.id, public.distance(i1.x, i1.y, i2.x, i2.y) FROM world.islands i1, world.islands i2;
end
$$ language plpgsql;