-- PDFs académicos escaneados suelen superar 50–100 MB. Sube el tope del bucket `books`.
-- En el plan Free de Supabase puede seguir aplicando un límite global (~50 MB): en ese caso
-- la app guarda el PDF en el dispositivo (ruta local/…) y mantiene metadatos en Postgres.

update storage.buckets
set file_size_limit = 524288000, -- 500 MiB
    allowed_mime_types = array['application/pdf']
where id = 'books';

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('books', 'books', false, 524288000, array['application/pdf'])
on conflict (id) do update
set file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;
