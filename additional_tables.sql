CREATE TYPE public.contract_status AS ENUM ('pending', 'rejected', 'completed', 'load', 'loading', 'unload', 'unloading', 
'moveToVendor', 'movingToVendor', 'moveToCustomer', 'movingToCustomer', 'needVendor', 'needCustomer');
CREATE TABLE public.contracts (
  "ship" INTEGER PRIMARY KEY NOT NULL,
  "status" contract_status,
  "item" INTEGER,
  "vendor_id" INTEGER,
  "vendor_island" INTEGER,
  "customer_id" INTEGER,
  "customer_island" INTEGER,
  "quantity" DOUBLE PRECISION,
  "offer" INTEGER,
  "vendor_offer" INTEGER,
  "contract" INTEGER
);

-- CREATE TABLE public.distances (
--   "island1" INTEGER NOT NULL,
--   "island2" INTEGER NOT NULL,
--   "distance" INTEGER NOT NULL,
--   PRIMARY KEY("island1", "island2", "distance")
-- );

CREATE TABLE public.storage (
  "island" INTEGER NOT NULL,
  "item" INTEGER NOT NULL,
  "quantity" DOUBLE PRECISION NOT NULL,
  CONSTRAINT pkey_storage PRIMARY KEY("island", "item")
);

CREATE TABLE public.ticks (
  "tick" SERIAL PRIMARY KEY NOT NULL,
  "time" DOUBLE PRECISION NOT NULL
);

CREATE TABLE public.ex_times (
  "tick" SERIAL PRIMARY KEY NOT NULL,
  "time" DOUBLE PRECISION NOT NULL
);