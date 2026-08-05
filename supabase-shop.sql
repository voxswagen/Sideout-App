-- ═══════════════════════════════════════════════════════════════════════
-- SHOP — the club's noticeboard for kit
-- ═══════════════════════════════════════════════════════════════════════
-- A copy of what is deployed, not a to-do. Applied 5 August 2026.
--
-- Deliberately not a shop: no checkout, no escrow, no fee. It lists the thing
-- and puts you in touch with the person; holding somebody's money is a
-- different product and a different set of laws.
--
-- Photos are data URLs in a jsonb column, the same as group photos and
-- session covers. That is not the elegant answer — object storage is — but it
-- keeps a listing to one row, works offline, and needs no bucket policy.
--
-- The cost of that choice showed up on the first real listing: 141KB, and the
-- board was returning every photo of every listing on every read. Fifty
-- listings is seven megabytes to look at a grid, on a phone, at a court. So
-- the board carries `thumb` and a count, and the full photos are fetched for
-- one listing when somebody actually opens it.

create table if not exists public.listings (
  id          uuid primary key default gen_random_uuid(),
  club        text not null default 'sideout',
  seller      uuid not null references public.members(id) on delete cascade,
  title       text not null,
  blurb       text,
  price       numeric(10,2),
  currency    text not null default 'AED',
  category    text not null default 'other',   -- paddle | balls | shoes | bag | apparel | other
  condition   text not null default 'used',    -- new | like_new | used | worn
  photos      jsonb not null default '[]'::jsonb,
  thumb       text,                            -- ~320px, what the board shows
  -- whether the seller is happy to be rung, as opposed to messaged in the app
  show_phone  boolean not null default true,
  sold        boolean not null default false,
  sold_at     timestamptz,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create index if not exists listings_club_live on public.listings (club, sold, created_at desc);
create index if not exists listings_seller on public.listings (seller);

alter table public.listings enable row level security;
-- Everything goes through the sideout_* functions, which are security definer
-- and do their own checks. No direct table access from the browser.
revoke all on public.listings from anon, authenticated;


-- Browsing. Sold items stay on the board rather than vanishing: "did that
-- paddle go?" is a question people ask, and an empty space does not answer it.
create or replace function public.sideout_listings(
  p_club text, p_cat text default null, p_sold boolean default false,
  p_mine boolean default false, p_q text default null)
returns table(id uuid, title text, blurb text, price numeric, currency text,
              category text, condition text, thumb text, n_photos int, sold boolean,
              created_at timestamptz, seller uuid, seller_name text,
              seller_photo text, seller_phone text, mine boolean)
language sql
security definer
set search_path = public
as $$
  with me as (select public.sideout_me(p_club) as mid)
  select l.id, l.title, l.blurb, l.price, l.currency, l.category, l.condition,
         l.thumb, jsonb_array_length(coalesce(l.photos,'[]'::jsonb))::int,
         l.sold, l.created_at,
         l.seller, coalesce(m.alias, m.name), m.photo,
         -- the number is only handed out when the seller said it could be
         case when l.show_phone then m.phone else null end,
         (l.seller = (select mid from me))
    from public.listings l
    join public.members m on m.id = l.seller
   where l.club = coalesce(p_club, 'sideout')
     and (p_cat is null or p_cat = 'all' or l.category = p_cat)
     and (p_sold or not l.sold)
     and (not p_mine or l.seller = (select mid from me))
     and (p_q is null or p_q = ''
          or l.title ilike '%' || p_q || '%'
          or coalesce(l.blurb,'') ilike '%' || p_q || '%')
   order by l.sold, l.created_at desc
   limit 200;
$$;

-- The full pictures, for one listing, when somebody opens it.
create or replace function public.sideout_listing_photos(p_club text, p_id uuid)
returns jsonb
language sql
security definer
stable
set search_path = public
as $$
  select coalesce(photos, '[]'::jsonb) from public.listings
   where id = p_id and club = coalesce(p_club, 'sideout');
$$;

-- Putting one up, or changing your own. Anybody in the club can sell; nobody
-- can touch anybody else's row, which is checked here rather than trusted
-- from the client.
create or replace function public.sideout_listing_save(
  p_club text, p_id uuid, p_title text, p_blurb text, p_price numeric,
  p_currency text, p_category text, p_condition text, p_photos jsonb,
  p_show_phone boolean, p_thumb text default null)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare v_me uuid; v_id uuid;
begin
  v_me := public.sideout_me(p_club);
  if v_me is null then raise exception 'sign in first'; end if;
  if coalesce(btrim(p_title),'') = '' then raise exception 'a listing needs a title'; end if;

  if p_id is null then
    insert into public.listings(club, seller, title, blurb, price, currency,
                                category, condition, photos, thumb, show_phone)
    values (coalesce(p_club,'sideout'), v_me, btrim(p_title),
            nullif(btrim(coalesce(p_blurb,'')),''),
            p_price, coalesce(nullif(p_currency,''),'AED'),
            coalesce(nullif(p_category,''),'other'), coalesce(nullif(p_condition,''),'used'),
            coalesce(p_photos,'[]'::jsonb),
            coalesce(p_thumb, p_photos->>0), coalesce(p_show_phone,true))
    returning id into v_id;
    return v_id;
  end if;

  update public.listings
     set title = btrim(p_title),
         blurb = nullif(btrim(coalesce(p_blurb,'')),''),
         price = p_price,
         currency = coalesce(nullif(p_currency,''),'AED'),
         category = coalesce(nullif(p_category,''),'other'),
         condition = coalesce(nullif(p_condition,''),'used'),
         photos = coalesce(p_photos,'[]'::jsonb),
         thumb = coalesce(p_thumb, p_photos->>0),
         show_phone = coalesce(p_show_phone,true),
         updated_at = now()
   where id = p_id and seller = v_me
   returning id into v_id;
  if v_id is null then raise exception 'that is not your listing'; end if;
  return v_id;
end;
$$;

-- Marking it gone, and putting it back if the sale falls through.
create or replace function public.sideout_listing_sold(p_club text, p_id uuid, p_sold boolean)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare v_me uuid; v_id uuid;
begin
  v_me := public.sideout_me(p_club);
  if v_me is null then raise exception 'sign in first'; end if;
  update public.listings
     set sold = coalesce(p_sold,true),
         sold_at = case when coalesce(p_sold,true) then now() else null end,
         updated_at = now()
   where id = p_id and seller = v_me
   returning id into v_id;
  if v_id is null then raise exception 'that is not your listing'; end if;
  return true;
end;
$$;

create or replace function public.sideout_listing_delete(p_club text, p_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare v_me uuid; v_id uuid; v_role text;
begin
  v_me := public.sideout_me(p_club);
  if v_me is null then raise exception 'sign in first'; end if;
  select role into v_role from public.members where id = v_me;
  -- the seller, or an owner clearing something that should not be up
  delete from public.listings
   where id = p_id and (seller = v_me or v_role = 'owner')
   returning id into v_id;
  if v_id is null then raise exception 'that is not your listing'; end if;
  return true;
end;
$$;

grant execute on function public.sideout_listings(text,text,boolean,boolean,text) to anon, authenticated;
grant execute on function public.sideout_listing_photos(text,uuid) to anon, authenticated;
grant execute on function public.sideout_listing_save(text,uuid,text,text,numeric,text,text,text,jsonb,boolean,text) to authenticated;
grant execute on function public.sideout_listing_sold(text,uuid,boolean) to authenticated;
grant execute on function public.sideout_listing_delete(text,uuid) to authenticated;


-- Photos open full size from the listing sheet, and an owner of the club can
-- take anything down — sideout_listing_delete already allowed it; there was
-- simply no button.
