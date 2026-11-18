-- Cold catalog reads can exceed the anon role's default three seconds.
-- Scope the exception to these read RPCs; retain their contracts and ACLs.
alter function public.online_prices_v4(text,integer,integer,text,boolean,text)
  set statement_timeout = '8s';
alter function public.catalog_categories_v3(double precision,double precision,double precision)
  set statement_timeout = '20s';

notify pgrst, 'reload schema';
