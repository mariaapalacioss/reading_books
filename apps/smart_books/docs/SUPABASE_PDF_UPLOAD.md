# Subida de PDFs grandes (Storage)

Flutter y la web suben el PDF al bucket **`books`**. El límite lo define **`storage.buckets.file_size_limit`** en tu proyecto Supabase (no se puede “subir” solo desde la app).

## 1. Aplicar límite 500 MB en tu proyecto (obligatorio una vez)

En [Supabase Dashboard](https://supabase.com/dashboard) → **SQL Editor** → ejecuta:

```sql
update storage.buckets
set file_size_limit = 524288000,
    allowed_mime_types = array['application/pdf']
where id = 'books';
```

Comprueba:

```sql
select id, file_size_limit from storage.buckets where id = 'books';
```

Debe mostrar `524288000` (500 MiB).

También puedes aplicar las migraciones del repo:

```bash
supabase db push
```

## 2. Plan Supabase

En el **plan Free**, Supabase puede imponer un tope global (~50 MB) aunque el bucket diga 500 MB. Si tras el SQL sigues viendo **413**, necesitas **Pro** (o el PDF se guarda en el dispositivo con ruta `local/…`, como en la web).

## 3. Flutter

Opcional en `dart_defines.json`:

```json
"MAX_PDF_CLOUD_MB": "500"
```

Valores mayores (p. ej. `"1024"`) solo tienen efecto si el bucket y tu plan lo permiten.
