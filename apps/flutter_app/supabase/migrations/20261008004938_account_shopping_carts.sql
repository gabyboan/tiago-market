-- One private cart per authenticated account. Guests never write to this table.
create table public.shopping_carts (
  user_id uuid primary key references auth.users(id) on delete cascade,
  items jsonb not null default '[]'::jsonb
    check (jsonb_typeof(items) = 'array' and jsonb_array_length(items) <= 1000)
);

alter table public.shopping_carts enable row level security;
revoke all on public.shopping_carts from anon, authenticated;
grant select, insert, update, delete on public.shopping_carts to authenticated;

create policy shopping_carts_select on public.shopping_carts
  for select to authenticated using ((select auth.uid()) = user_id);
create policy shopping_carts_insert on public.shopping_carts
  for insert to authenticated with check ((select auth.uid()) = user_id);
create policy shopping_carts_update on public.shopping_carts
  for update to authenticated using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);
create policy shopping_carts_delete on public.shopping_carts
  for delete to authenticated using ((select auth.uid()) = user_id);
