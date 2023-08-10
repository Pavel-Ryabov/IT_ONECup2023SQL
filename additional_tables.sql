CREATE TYPE public.contract_status AS ENUM ('pending', 'completed', 'load', 'loading', 'unload', 'unloading', 'moveToVendor', 'movingToVendor', 'moveToCustomer', 'movingToCustomer');
CREATE TABLE public.contracts (
  "ship" INTEGER PRIMARY KEY NOT NULL,
  "status" contract_status,
  "item" INTEGER,
  "vendor_island" INTEGER,
  "customer_id" INTEGER,
  "customer_island" INTEGER,
  "quantity" DOUBLE PRECISION,
  "offer" INTEGER,
  "contract" INTEGER
);

CREATE TABLE public.distances (
  "island1" INTEGER,
  "island2" INTEGER,
  "distance" INTEGER,
  PRIMARY KEY("island1", "island2", "distance")
);