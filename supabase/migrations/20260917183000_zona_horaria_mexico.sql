-- 014 · La base calcula fechas (current_date en triggers y RPC) en hora de México, no en UTC.
alter database postgres set timezone to 'America/Mexico_City';
alter role authenticated set timezone to 'America/Mexico_City';
alter role anon set timezone to 'America/Mexico_City';
alter role postgres set timezone to 'America/Mexico_City';
