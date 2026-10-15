-- Refuerzo multi-usuario: filas hijas deben pertenecer a un libro del mismo auth.uid().

create or replace function public.user_owns_book(target_book uuid)
returns boolean
language sql
stable
security invoker
set search_path = public
as $$
  select exists (
    select 1 from public.books b
    where b.id = target_book and b.user_id = auth.uid()
  );
$$;

drop policy if exists chapters_own on public.chapters;
create policy chapters_own on public.chapters
  for all to authenticated
  using (user_id = auth.uid() and public.user_owns_book(book_id))
  with check (user_id = auth.uid() and public.user_owns_book(book_id));

drop policy if exists pages_own on public.book_pages;
create policy pages_own on public.book_pages
  for all to authenticated
  using (user_id = auth.uid() and public.user_owns_book(book_id))
  with check (user_id = auth.uid() and public.user_owns_book(book_id));

drop policy if exists jobs_own on public.analysis_jobs;
create policy jobs_own on public.analysis_jobs
  for all to authenticated
  using (user_id = auth.uid() and public.user_owns_book(book_id))
  with check (user_id = auth.uid() and public.user_owns_book(book_id));

drop policy if exists highlights_own on public.highlights;
create policy highlights_own on public.highlights
  for all to authenticated
  using (user_id = auth.uid() and public.user_owns_book(book_id))
  with check (user_id = auth.uid() and public.user_owns_book(book_id));

drop policy if exists points_own on public.chapter_points;
create policy points_own on public.chapter_points
  for all to authenticated
  using (user_id = auth.uid() and public.user_owns_book(book_id))
  with check (user_id = auth.uid() and public.user_owns_book(book_id));

drop policy if exists bookmarks_own on public.bookmarks;
create policy bookmarks_own on public.bookmarks
  for all to authenticated
  using (user_id = auth.uid() and public.user_owns_book(book_id))
  with check (user_id = auth.uid() and public.user_owns_book(book_id));

drop policy if exists notes_own on public.notes;
create policy notes_own on public.notes
  for all to authenticated
  using (user_id = auth.uid() and public.user_owns_book(book_id))
  with check (user_id = auth.uid() and public.user_owns_book(book_id));

drop policy if exists chunks_own on public.search_chunks;
create policy chunks_own on public.search_chunks
  for all to authenticated
  using (user_id = auth.uid() and public.user_owns_book(book_id))
  with check (user_id = auth.uid() and public.user_owns_book(book_id));

drop policy if exists questions_own on public.questions;
create policy questions_own on public.questions
  for all to authenticated
  using (user_id = auth.uid() and public.user_owns_book(book_id))
  with check (user_id = auth.uid() and public.user_owns_book(book_id));

drop policy if exists study_cards_own on public.study_cards;
create policy study_cards_own on public.study_cards
  for all to authenticated
  using (user_id = auth.uid() and public.user_owns_book(book_id))
  with check (user_id = auth.uid() and public.user_owns_book(book_id));

grant execute on function public.user_owns_book(uuid) to authenticated;
