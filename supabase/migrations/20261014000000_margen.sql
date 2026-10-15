-- Margen by Bookifi
-- Libros privados por usuario, texto con referencia de página, resaltados y búsqueda.

create extension if not exists vector with schema extensions;
create extension if not exists pg_trgm with schema extensions;

create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  display_name text,
  theme text not null default 'system' check (theme in ('light', 'dark', 'system')),
  explanation_language text not null default 'es' check (explanation_language in ('es', 'en')),
  created_at timestamptz not null default now()
);

create table public.books (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  title text not null,
  author text,
  language text not null default 'unknown' check (language in ('es', 'en', 'unknown')),
  storage_path text not null,
  page_count integer not null default 0 check (page_count >= 0),
  status text not null default 'ready' check (
    status in ('extracting', 'needs_ocr', 'ready', 'analyzing', 'partial', 'analyzed', 'error')
  ),
  status_detail text,
  highlight_intensity text not null default 'balanced' check (
    highlight_intensity in ('essential', 'balanced', 'detailed')
  ),
  analysis_progress real not null default 0,
  current_page integer not null default 1,
  zoom real not null default 1.15,
  show_ai_highlights boolean not null default true,
  explanation_language text not null default 'es' check (explanation_language in ('es', 'en')),
  last_read_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.chapters (
  id uuid primary key default gen_random_uuid(),
  book_id uuid not null references public.books (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  position integer not null,
  title text not null,
  start_page integer not null,
  end_page integer not null,
  source text not null default 'detected' check (source in ('detected', 'user')),
  analysis_status text not null default 'pending' check (
    analysis_status in ('pending', 'queued', 'processing', 'done', 'failed')
  ),
  analysis_error text,
  summary_es text,
  summary_en text,
  created_at timestamptz not null default now(),
  unique (book_id, position),
  check (end_page >= start_page)
);

create table public.book_pages (
  id uuid primary key default gen_random_uuid(),
  book_id uuid not null references public.books (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  page_number integer not null,
  printed_label text,
  text text not null default '',
  items jsonb not null default '[]'::jsonb,
  char_count integer not null default 0,
  unique (book_id, page_number)
);

create table public.analysis_jobs (
  id uuid primary key default gen_random_uuid(),
  book_id uuid not null references public.books (id) on delete cascade,
  chapter_id uuid not null references public.chapters (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  intensity text not null check (intensity in ('essential', 'balanced', 'detailed')),
  status text not null default 'queued' check (status in ('queued', 'processing', 'done', 'failed')),
  attempt integer not null default 0,
  kept_count integer not null default 0,
  dropped_count integer not null default 0,
  model text,
  error text,
  started_at timestamptz,
  finished_at timestamptz,
  unique (chapter_id, intensity)
);

create table public.highlights (
  id uuid primary key default gen_random_uuid(),
  book_id uuid not null references public.books (id) on delete cascade,
  chapter_id uuid references public.chapters (id) on delete set null,
  user_id uuid not null references auth.users (id) on delete cascade,
  page_number integer not null,
  quote text not null,
  quote_hash text not null,
  category text not null check (
    category in ('idea', 'definicion', 'dato', 'conclusion', 'contexto', 'manual')
  ),
  explanation_es text,
  explanation_en text,
  origin text not null check (origin in ('ai', 'user')),
  intensity text check (intensity in ('essential', 'balanced', 'detailed')),
  reviewed boolean not null default false,
  review_again boolean not null default false,
  dismissed boolean not null default false,
  note text,
  rects jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index highlights_quote_unique
  on public.highlights (chapter_id, intensity, quote_hash);

create table public.chapter_points (
  id uuid primary key default gen_random_uuid(),
  book_id uuid not null references public.books (id) on delete cascade,
  chapter_id uuid not null references public.chapters (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  position integer not null,
  text_es text not null,
  text_en text not null,
  quote text,
  page_number integer,
  printed_label text,
  reviewed boolean not null default false,
  review_again boolean not null default false,
  unique (chapter_id, position)
);

create table public.bookmarks (
  id uuid primary key default gen_random_uuid(),
  book_id uuid not null references public.books (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  page_number integer not null,
  label text,
  created_at timestamptz not null default now(),
  unique (book_id, user_id, page_number)
);

create table public.notes (
  id uuid primary key default gen_random_uuid(),
  book_id uuid not null references public.books (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  page_number integer not null,
  highlight_id uuid references public.highlights (id) on delete cascade,
  body text not null,
  created_at timestamptz not null default now()
);

create table public.search_chunks (
  id uuid primary key default gen_random_uuid(),
  book_id uuid not null references public.books (id) on delete cascade,
  chapter_id uuid references public.chapters (id) on delete set null,
  user_id uuid not null references auth.users (id) on delete cascade,
  page_start integer not null,
  page_end integer not null,
  content text not null,
  embedding extensions.vector(1536),
  unique (book_id, page_start, page_end)
);

create table public.questions (
  id uuid primary key default gen_random_uuid(),
  book_id uuid not null references public.books (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  question text not null,
  answer text not null,
  sufficient boolean not null,
  citations jsonb not null default '[]'::jsonb,
  language text not null check (language in ('es', 'en')),
  created_at timestamptz not null default now()
);

create index books_user_updated_idx on public.books (user_id, updated_at desc);
create index chapters_book_idx on public.chapters (book_id, position);
create index book_pages_book_idx on public.book_pages (book_id, page_number);
create index highlights_book_page_idx on public.highlights (book_id, page_number);
create index chapter_points_book_idx on public.chapter_points (book_id, chapter_id, position);
create index book_pages_text_trgm_idx on public.book_pages using gin (text extensions.gin_trgm_ops);
create index search_chunks_book_idx on public.search_chunks (book_id);

create or replace function public.touch_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger books_touch before update on public.books
for each row execute function public.touch_updated_at();

create trigger highlights_touch before update on public.highlights
for each row execute function public.touch_updated_at();

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, display_name)
  values (
    new.id,
    coalesce(new.raw_user_meta_data ->> 'display_name', split_part(new.email, '@', 1))
  );
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

create or replace function public.match_chunks(
  query_embedding extensions.vector(1536),
  target_book uuid,
  match_count integer default 8
)
returns table (
  chunk_id uuid,
  book_id uuid,
  chapter_id uuid,
  page_start integer,
  page_end integer,
  content text,
  similarity double precision
)
language sql
stable
security invoker
set search_path = public, extensions
as $$
  select
    c.id,
    c.book_id,
    c.chapter_id,
    c.page_start,
    c.page_end,
    c.content,
    1 - (c.embedding <=> query_embedding) as similarity
  from public.search_chunks c
  where c.user_id = auth.uid()
    and c.embedding is not null
    and (target_book is null or c.book_id = target_book)
  order by c.embedding <=> query_embedding
  limit least(coalesce(match_count, 8), 20);
$$;

alter table public.profiles enable row level security;
alter table public.books enable row level security;
alter table public.chapters enable row level security;
alter table public.book_pages enable row level security;
alter table public.analysis_jobs enable row level security;
alter table public.highlights enable row level security;
alter table public.chapter_points enable row level security;
alter table public.bookmarks enable row level security;
alter table public.notes enable row level security;
alter table public.search_chunks enable row level security;
alter table public.questions enable row level security;

create policy profiles_own on public.profiles
  for all to authenticated using (id = auth.uid()) with check (id = auth.uid());

create policy books_own on public.books
  for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

create policy chapters_own on public.chapters
  for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

create policy pages_own on public.book_pages
  for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

create policy jobs_own on public.analysis_jobs
  for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

create policy highlights_own on public.highlights
  for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

create policy points_own on public.chapter_points
  for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

create policy bookmarks_own on public.bookmarks
  for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

create policy notes_own on public.notes
  for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

create policy chunks_own on public.search_chunks
  for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

create policy questions_own on public.questions
  for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

grant usage on schema public to authenticated;
grant all on all tables in schema public to authenticated;
grant execute on function public.match_chunks(extensions.vector, uuid, integer) to authenticated;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('books', 'books', false, 104857600, array['application/pdf'])
on conflict (id) do update
set public = false,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

create policy books_storage_select on storage.objects
  for select to authenticated
  using (
    bucket_id = 'books'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy books_storage_insert on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'books'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy books_storage_update on storage.objects
  for update to authenticated
  using (
    bucket_id = 'books'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy books_storage_delete on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'books'
    and (storage.foldername(name))[1] = auth.uid()::text
  );
