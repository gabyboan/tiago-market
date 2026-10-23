-- Legacy readers run through audited SECURITY DEFINER RPCs or the backend's
-- service role. Direct client access must not bypass the tables' RLS.
alter view public.latest_prices set (security_invoker = true);
revoke all on public.latest_prices from public, anon, authenticated;
