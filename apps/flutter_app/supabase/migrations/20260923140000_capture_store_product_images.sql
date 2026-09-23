create or replace function public.capture_store_product_image()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if nullif(trim(new.image_url), '') is not null then
    insert into public.product_images (
      store_product_id,
      image_url,
      canonical_url,
      source,
      is_primary,
      validation_status,
      checked_at
    ) values (
      new.id,
      new.image_url,
      new.image_url,
      coalesce(nullif(trim(new.source), ''), 'unknown'),
      true,
      'unverified',
      coalesce(new.last_seen_at, now())
    )
    on conflict (store_product_id, image_url) do update set
      source = excluded.source,
      is_primary = true,
      checked_at = excluded.checked_at;
  end if;

  return new;
end;
$$;

drop trigger if exists store_product_image_capture on public.store_products;
create trigger store_product_image_capture
after insert or update of image_url on public.store_products
for each row execute function public.capture_store_product_image();

revoke all on function public.capture_store_product_image() from public, anon, authenticated;
grant execute on function public.capture_store_product_image() to service_role;