-- Drop search_public_routes: no client calls it (decisions § 1925, § 1926).
--
-- Web `searchPublicRoutes` and mobile `ApiClient.searchPublicRoutes` read the
-- `public_routes` view directly — the function's own source, with the same
-- visibility and the same anon + authenticated SELECT grant — by keyset
-- cursor. The function paged by `p_offset`, which repeats or skips a route
-- whenever one is published or unpublished between two reads, and none of its
-- orders was total. Left in place it is a SECURITY DEFINER entry point granted
-- to anon that nothing uses.
--
-- The three partial sort indexes 20270326_001 built for it
-- (routes_public_{popular,featured,newest}_sort) stay: they serve the prefix
-- of the view read's order. routes_name_trgm stays too; it serves the view
-- read's `name ~*` filter.
--
-- The exact signature, without `if exists`: a drift in the live signature
-- should fail this migration rather than leave the function behind.

drop function public.search_public_routes(
  text, numeric, numeric, text, text[], boolean, text, integer, integer
);
