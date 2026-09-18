-- 013 · Las vistas recreadas en 011 nacieron sin privilegios para authenticated. Grants explícitos (RLS sigue mandando).
grant select on v_solicitudes, v_padron, v_secciones, v_tablero to authenticated;
grant select, insert, update, delete on all tables in schema public to authenticated;
revoke all on folios from authenticated;
revoke all on all tables in schema public from anon;
alter default privileges for role postgres in schema public grant select, insert, update, delete on tables to authenticated;
