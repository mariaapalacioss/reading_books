-- Extensión incremental del workspace por libro (no altera tablas existentes).

alter table public.books
  add column if not exists workspace_profile jsonb;

alter table public.study_cards
  add column if not exists metadata jsonb not null default '{}'::jsonb;

create table if not exists public.book_concepts (
  id uuid primary key default gen_random_uuid(),
  book_id uuid not null references public.books (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  label text not null,
  summary text,
  page_refs integer[] not null default '{}',
  related_concept_ids uuid[] not null default '{}',
  created_at timestamptz not null default now()
);

create index if not exists book_concepts_book_idx
  on public.book_concepts (book_id, created_at desc);

alter table public.book_concepts enable row level security;

create policy book_concepts_own on public.book_concepts
  for all to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());
