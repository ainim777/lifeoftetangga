-- Explicitly deny all client roles direct access to the private ID counter.
create policy customer_code_counters_no_client_access
  on private.customer_code_counters for all to public
  using(false) with check(false);
