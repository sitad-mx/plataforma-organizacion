-- 003 · Permisos (RLS) por rol y sección + funciones públicas (RPC) de respuesta mínima.
-- Roles: cen_organizacion (Manuel) todo salvo autorizar; sg autoriza; cen_lectura lee; seccion_organizacion su sección; seccion_sg su sección en lectura.

-- Nada para anon en las tablas; lo público entra solo por RPC.
revoke all on all tables in schema public from anon;
alter default privileges in schema public revoke all on tables from anon;

do $$ declare t text;
begin
  foreach t in array array['configuracion','festivos','usuarios_roles','secciones','cargos_seccionales','cargos_historial','folios','solicitudes_afiliacion','solicitud_documentos','padron','movimientos','incidencias','incidencia_acciones','constituciones','constitucion_checklist','asambleas','asistencias','bitacora_sistema'] loop
    execute format('alter table %I enable row level security', t);
  end loop;
end $$;

-- Catálogos y configuración: lectura para cualquier usuario con rol; escritura Organización del CEN
create policy sel_configuracion on configuracion for select to authenticated using (mi_rol() is not null);
create policy adm_configuracion on configuracion for all to authenticated using (es_org()) with check (es_org());
create policy sel_festivos on festivos for select to authenticated using (mi_rol() is not null);
create policy adm_festivos on festivos for all to authenticated using (es_org()) with check (es_org());

-- Usuarios: cada quien ve su fila; el CEN ve todas; Organización administra
create policy sel_usuarios on usuarios_roles for select to authenticated using (user_id = auth.uid() or es_cen());
create policy adm_usuarios on usuarios_roles for all to authenticated using (es_org()) with check (es_org());

-- Secciones: todos los roles ven el registro nacional; Organización escribe
create policy sel_secciones on secciones for select to authenticated using (mi_rol() is not null);
create policy adm_secciones on secciones for all to authenticated using (es_org()) with check (es_org());

-- Directorio: CEN todo; la Sección lo suyo (y puede corregir teléfono/correo, queda pendiente de validar)
create policy sel_cargos on cargos_seccionales for select to authenticated using (es_cen() or seccion_id = mi_seccion());
create policy adm_cargos on cargos_seccionales for all to authenticated using (es_org()) with check (es_org());
create policy upd_cargos_seccion on cargos_seccionales for update to authenticated using (mi_rol() = 'seccion_organizacion' and seccion_id = mi_seccion()) with check (seccion_id = mi_seccion());
create policy sel_cargos_hist on cargos_historial for select to authenticated using (es_cen() or seccion_id = mi_seccion());

-- Solicitudes: CEN todo; la Sección las de su gente y puede registrarlas; el SG solo actualiza (el trigger limita a autorizar)
create policy sel_solicitudes on solicitudes_afiliacion for select to authenticated using (es_cen() or seccion_id = mi_seccion());
create policy ins_solicitudes on solicitudes_afiliacion for insert to authenticated with check (es_org() or (mi_rol() = 'seccion_organizacion' and seccion_id = mi_seccion()));
create policy upd_solicitudes on solicitudes_afiliacion for update to authenticated using (es_org() or mi_rol() = 'sg') with check (es_org() or mi_rol() = 'sg');
create policy del_solicitudes on solicitudes_afiliacion for delete to authenticated using (es_org());

create policy sel_docs on solicitud_documentos for select to authenticated using (
  es_cen() or exists (select 1 from solicitudes_afiliacion s where s.id = solicitud_id and s.seccion_id = mi_seccion()));
create policy ins_docs on solicitud_documentos for insert to authenticated with check (
  es_org() or (mi_rol() = 'seccion_organizacion' and exists (select 1 from solicitudes_afiliacion s where s.id = solicitud_id and s.seccion_id = mi_seccion() and s.estado in ('Recibida','Prevenida'))));
create policy adm_docs on solicitud_documentos for all to authenticated using (es_org()) with check (es_org());

-- Padrón: CEN todo; la Sección ve sus adscritos; solo Organización escribe (las bajas las valida el trigger con el SG)
create policy sel_padron on padron for select to authenticated using (es_cen() or seccion_id = mi_seccion());
create policy adm_padron on padron for all to authenticated using (es_org()) with check (es_org());

-- Movimientos e incidencias: la Sección registra y ve lo suyo; Organización administra
create policy sel_movimientos on movimientos for select to authenticated using (es_cen() or seccion_id = mi_seccion());
create policy ins_movimientos on movimientos for insert to authenticated with check (es_org() or (mi_rol() = 'seccion_organizacion' and seccion_id = mi_seccion()));
create policy adm_movimientos on movimientos for all to authenticated using (es_org()) with check (es_org());

create policy sel_incidencias on incidencias for select to authenticated using (es_cen() or seccion_id = mi_seccion());
create policy ins_incidencias on incidencias for insert to authenticated with check (es_org() or (mi_rol() = 'seccion_organizacion' and seccion_id = mi_seccion()));
create policy adm_incidencias on incidencias for all to authenticated using (es_org()) with check (es_org());
create policy sel_inc_acciones on incidencia_acciones for select to authenticated using (
  es_cen() or exists (select 1 from incidencias i where i.id = incidencia_id and i.seccion_id = mi_seccion()));
create policy adm_inc_acciones on incidencia_acciones for all to authenticated using (es_org()) with check (es_org());

-- Constituciones y asambleas: CEN; la Sección ve lo suyo
create policy sel_constituciones on constituciones for select to authenticated using (es_cen() or seccion_id = mi_seccion());
create policy adm_constituciones on constituciones for all to authenticated using (es_org()) with check (es_org());
create policy sel_checklist on constitucion_checklist for select to authenticated using (
  es_cen() or exists (select 1 from constituciones c where c.id = constitucion_id and c.seccion_id = mi_seccion()));
create policy adm_checklist on constitucion_checklist for all to authenticated using (es_org()) with check (es_org());
create policy sel_asambleas on asambleas for select to authenticated using (es_cen() or seccion_id = mi_seccion());
create policy adm_asambleas on asambleas for all to authenticated using (es_org()) with check (es_org());
create policy sel_asistencias on asistencias for select to authenticated using (
  es_cen() or exists (select 1 from asambleas a where a.id = asamblea_id and a.seccion_id = mi_seccion()));
create policy adm_asistencias on asistencias for all to authenticated using (es_org()) with check (es_org());

-- Bitácora: solo lectura del CEN (se escribe por funciones del sistema)
create policy sel_bitacora on bitacora_sistema for select to authenticated using (es_cen());
-- folios: sin políticas (solo funciones security definer)

-- ===== RPC públicas (respuesta mínima) =====
-- Estado de una solicitud por folio + correo (puerta pública /estado)
create or replace function consultar_solicitud(p_folio text, p_correo text)
returns table (folio text, estado estado_solicitud, seccion text, fecha_recepcion date, fecha_prevencion date, limite_subsanacion date, fecha_dictamen date, sentido sentido_dictamen, fecha_alta date)
language sql stable security definer set search_path = public as $$
  select s.folio, s.estado, sec.denominacion, s.fecha_recepcion, s.fecha_prevencion, s.limite_subsanacion, s.fecha_dictamen, s.sentido, s.fecha_ejecucion_padron
  from solicitudes_afiliacion s join secciones sec on sec.id = s.seccion_id
  where upper(trim(s.folio)) = upper(trim(p_folio)) and lower(trim(s.correo)) = lower(trim(p_correo));
$$;
grant execute on function consultar_solicitud(text, text) to anon, authenticated;

-- Verificación de credencial por token QR (sin datos personales)
create or replace function verificar_credencial(p_token text)
returns table (vigente boolean, seccion text, numero_afiliacion int)
language sql stable security definer set search_path = public as $$
  select p.estatus = 'Activo', sec.denominacion, p.numero_afiliacion
  from padron p join secciones sec on sec.id = p.seccion_id
  where p.credencial_qr_token = p_token;
$$;
grant execute on function verificar_credencial(text) to anon, authenticated;

-- Las funciones internas no se exponen a anon
revoke execute on function siguiente_folio(text) from anon, authenticated;
revoke execute on function bitacora(text, uuid, text, text, text, text) from anon, authenticated;
