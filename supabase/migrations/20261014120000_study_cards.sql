create table public.study_cards (
  id uuid primary key default gen_random_uuid(),
  book_id uuid not null references public.books (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  chapter_id uuid references public.chapters (id) on delete set null,
  page_number integer,
  kind text not null check (kind in ('note', 'qa', 'summary', 'review', 'explain', 'capture')),
  source text not null check (source in ('chat', 'assist', 'capture')),
  title text not null,
  body text not null,
  back text,
  quote text,
  preview_url text,
  context_question text,
  assist_mode text,
  reviewed boolean not null default false,
  review_again boolean not null default false,
  created_at timestamptz not null default now()
);

create index study_cards_book_idx on public.study_cards (book_id, created_at desc);
create index study_cards_chapter_idx on public.study_cards (book_id, chapter_id);

alter table public.study_cards enable row level security;

create policy study_cards_own on public.study_cards
  for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
