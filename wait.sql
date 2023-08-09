create or replace procedure wait(until DOUBLE PRECISION) as $$
begin
  raise notice 'wait until: %', until;
  insert into actions.wait (until) values (until);
end
$$ language plpgsql;