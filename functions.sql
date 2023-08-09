CREATE OR REPLACE FUNCTION public.distance(x1 DOUBLE PRECISION, y1 DOUBLE PRECISION, x2 DOUBLE PRECISION, y2 DOUBLE PRECISION) RETURNS DOUBLE PRECISION AS $$
  BEGIN
    RETURN ABS(x1 - x2) + ABS(y1 - y2);
  END
$$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION public.profit_per_unit_of_time(price DOUBLE PRECISION, quantity DOUBLE PRECISION, speed DOUBLE PRECISION, distnace1 DOUBLE PRECISION, distnace2 DOUBLE PRECISION) RETURNS DOUBLE PRECISION AS $$
  BEGIN
    RETURN price * quantity / ((distnace1 + distnace2) * speed + quantity * constants.transfer_time_per_unit!);
  END
$$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION public.get_target_island(status public.contract_status, vendor_island INTEGER, customer_island INTEGER) RETURNS INTEGER AS $$
  declare target_island INTEGER;
  BEGIN
    if status = 'moveToVendor'::public.contract_status then
      target_island = vendor_island;
    else
      target_island = customer_island;
    end if;
    RETURN target_island;
  END
$$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION public.get_next_status(status public.contract_status) RETURNS public.contract_status AS $$
  DECLARE
	  next_status public.contract_status;
  BEGIN
    case status
      when 'moveToVendor'::public.contract_status then
        next_status = 'movingToVendor'::public.contract_status;
		  when 'moveToCustomer'::public.contract_status then
        next_status = 'movingToCustomer'::public.contract_status;
		  when 'movingToVendor'::public.contract_status then
        next_status = 'load'::public.contract_status;
		  when 'movingToCustomer'::public.contract_status then
        next_status = 'unload'::public.contract_status;
      when 'loading'::public.contract_status then
        next_status = 'moveToCustomer'::public.contract_status;
		  when 'unloading'::public.contract_status then
        next_status = 'completed'::public.contract_status;
		  else
	    	next_status = 'pending'::public.contract_status;
		end case;
    RETURN next_status;
  END
$$ LANGUAGE plpgsql;
