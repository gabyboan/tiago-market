begin;
insert into auth.users (id, aud, role) values
  ('a424e8c7-7ff8-4c2b-83ea-04a849b71201', 'authenticated', 'authenticated'),
  ('a424e8c7-7ff8-4c2b-83ea-04a849b71202', 'authenticated', 'authenticated');
set local role authenticated;
set local request.jwt.claim.sub = 'a424e8c7-7ff8-4c2b-83ea-04a849b71201';
insert into public.shopping_carts(user_id, items)
values ('a424e8c7-7ff8-4c2b-83ea-04a849b71201', '[{"quantity":2}]');
update public.shopping_carts set items = '[{"quantity":3}]'
where user_id = 'a424e8c7-7ff8-4c2b-83ea-04a849b71201';
do $$ begin
  if (select items from public.shopping_carts where user_id = auth.uid())
     <> '[{"quantity":3}]'::jsonb then
    raise exception 'Owner cannot restore their cart';
  end if;
  begin
    update public.shopping_carts
      set user_id = 'a424e8c7-7ff8-4c2b-83ea-04a849b71202';
    raise exception 'Owner was allowed to reassign their cart';
  exception when insufficient_privilege then null;
  end;
end $$;
set local request.jwt.claim.sub = 'a424e8c7-7ff8-4c2b-83ea-04a849b71202';
do $$ declare affected integer; begin
  if exists(select 1 from public.shopping_carts) then
    raise exception 'Another account can read private carts';
  end if;
  update public.shopping_carts set items = '[]';
  get diagnostics affected = row_count;
  if affected <> 0 then raise exception 'Another account changed a cart'; end if;
  delete from public.shopping_carts;
  get diagnostics affected = row_count;
  if affected <> 0 then raise exception 'Another account deleted a cart'; end if;
  begin
    insert into public.shopping_carts(user_id)
      values ('a424e8c7-7ff8-4c2b-83ea-04a849b71201');
    raise exception 'Another account can insert carts for an owner';
  exception when insufficient_privilege then null;
  end;
end $$;
set local role anon;
do $$ begin
  begin
    perform * from public.shopping_carts;
    raise exception 'Guests can read carts';
  exception when insufficient_privilege then null;
  end;
end $$;
reset role;
select 'Owner CRUD and account/guest isolation passed' as result;
rollback;
