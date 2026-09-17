-- 008 · Decisión de Manuel 2026-09-17: DOS caminos para la papelería.
--   (a) la Sección recibe por correo y sube al portal;  (b) el trabajador sube directo desde la liga de su Sección (/afiliate/[slug]).
-- Además: Ciudad Juárez = 22 provisional; usuario del SG; buzón de archivos (Storage) como entrada; Drive sigue siendo el archivo definitivo tras el alta.

-- 1) Canal de la solicitud
alter table solicitudes_afiliacion add column canal text not null default 'seccion' check (canal in ('seccion','publico'));

-- 2) Ciudad Juárez: número provisional 22 (siguiente consecutivo tras Jalisco 21). CONFIRMAR con el SG antes de emitir folios reales.
update secciones set numero = 22,
  notas = 'Sección constituida (piloto). NÚMERO 22 PROVISIONAL (siguiente consecutivo tras Jalisco 21; el vault no registra otro esquema de numeración) — confirmar con el SG antes de emitir folios reales. Capturar el CES electo con el acta y las fechas de asamblea y periodo.'
where slug = 'ciudad-juarez';

-- 3) Usuario del Secretario General (rol sg): se vincula solo cuando entre por primera vez con ese correo
insert into usuarios_roles (email, rol, nombre) values ('noehdegrijalva@icloud.com', 'sg', 'Secretario General del CEN')
on conflict (email) do update set rol = excluded.rol, activo = true;

-- 4) Datos públicos de una Sección para la página de la liga (solo secciones con número, es decir, habilitadas para recibir solicitudes)
create or replace function seccion_publica(p_slug text)
returns table (slug text, denominacion text, entidad text, numero int, situacion situacion_seccion)
language sql stable security definer set search_path = public as $$
  select s.slug, s.denominacion, s.entidad, s.numero, s.situacion
  from secciones s where s.slug = lower(trim(p_slug)) and s.numero is not null and s.situacion not in ('Suspendida','Suprimida');
$$;
grant execute on function seccion_publica(text) to anon, authenticated;

-- 5) Captura pública: el trabajador crea su solicitud desde la liga de su Sección (queda ligada a esa Sección, canal = publico)
create or replace function crear_solicitud_publica(
  p_slug text, p_nombre_completo text, p_correo text, p_telefono text,
  p_curp text default null, p_fecha_nacimiento date default null, p_genero genero default null, p_domicilio text default null,
  p_puesto text default null, p_centro_trabajo text default null, p_fecha_inicio_relacion date default null,
  p_es_confianza boolean default false, p_acepta_estatuto boolean default false, p_acepta_aviso boolean default false, p_ip inet default null)
returns table (folio text, seccion text)
language plpgsql security definer set search_path = public as $$
declare v_sec secciones%rowtype; v_folio text;
begin
  select * into v_sec from secciones where slug = lower(trim(p_slug)) and numero is not null and situacion not in ('Suspendida','Suprimida');
  if not found then raise exception 'La liga de afiliación no es válida o la Sección no está habilitada.'; end if;
  if not p_acepta_estatuto then raise exception 'Es necesario manifestar la aceptación del Estatuto.'; end if;
  if not p_acepta_aviso then raise exception 'Es necesario aceptar el Aviso de Privacidad.'; end if;
  if p_correo !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then raise exception 'Correo electrónico no válido.'; end if;
  if length(trim(p_nombre_completo)) < 5 then raise exception 'Escribe tu nombre completo.'; end if;
  insert into solicitudes_afiliacion (seccion_id, canal, nombre_completo, curp, fecha_nacimiento, genero, domicilio, correo, telefono, puesto, centro_trabajo,
    fecha_inicio_relacion, es_confianza, acepta_estatuto, acepta_estatuto_at, aviso_privacidad_at, ip_captura)
  values (v_sec.id, 'publico', trim(p_nombre_completo), nullif(upper(trim(p_curp)),''), p_fecha_nacimiento, p_genero, p_domicilio, lower(trim(p_correo)), p_telefono, p_puesto, p_centro_trabajo,
    p_fecha_inicio_relacion, coalesce(p_es_confianza,false), true, now(), now(), p_ip)
  returning solicitudes_afiliacion.folio into v_folio;
  return query select v_folio, v_sec.denominacion;
end $$;
grant execute on function crear_solicitud_publica(text,text,text,text,text,date,genero,text,text,text,date,boolean,boolean,boolean,inet) to anon, authenticated;

-- 6) El trabajador registra un documento de su expediente (alta o subsanación) con folio + correo
create or replace function registrar_documento_publico(p_folio text, p_correo text, p_tipo tipo_documento_afiliacion, p_archivo_url text, p_nombre_archivo text)
returns table (folio text, documentos_completos boolean, estado estado_solicitud)
language plpgsql security definer set search_path = public as $$
declare v_s solicitudes_afiliacion%rowtype;
begin
  select * into v_s from solicitudes_afiliacion s
   where upper(trim(s.folio)) = upper(trim(p_folio)) and lower(trim(s.correo)) = lower(trim(p_correo));
  if not found then raise exception 'Folio o correo incorrectos.'; end if;
  if v_s.estado not in ('Recibida','Prevenida') then raise exception 'Esta solicitud ya no admite documentos (estado: %).', v_s.estado; end if;
  -- un documento por tipo: el nuevo sustituye al anterior
  delete from solicitud_documentos where solicitud_id = v_s.id and tipo = p_tipo and p_tipo <> 'otro';
  insert into solicitud_documentos (solicitud_id, tipo, archivo_url, nombre_archivo) values (v_s.id, p_tipo, p_archivo_url, p_nombre_archivo);
  if v_s.estado = 'Prevenida' and v_s.fecha_subsanacion is null then
    update solicitudes_afiliacion set fecha_subsanacion = current_date where id = v_s.id;
  end if;
  return query select s.folio, s.documentos_completos, s.estado from solicitudes_afiliacion s where s.id = v_s.id;
end $$;
grant execute on function registrar_documento_publico(text,text,tipo_documento_afiliacion,text,text) to anon, authenticated;

-- 7) Buzón de archivos (Storage): bucket privado "expedientes". Entrada = aquí; archivo definitivo = Drive del sindicato tras el alta.
--    Rutas: solicitudes/<slug-seccion>/<folio>/<tipo>.<ext>   (PDF/JPG/PNG, máx 5 MB)
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('expedientes', 'expedientes', false, 5242880, array['application/pdf','image/jpeg','image/png'])
on conflict (id) do nothing;

-- El público solo puede SUBIR (no listar ni leer) dentro de solicitudes/…; nunca sobrescribir
create policy exp_subir_publico on storage.objects for insert to anon, authenticated
  with check (bucket_id = 'expedientes' and name like 'solicitudes/%');
-- El CEN lee todo; la Sección lee solo su carpeta
create policy exp_leer_cen on storage.objects for select to authenticated
  using (bucket_id = 'expedientes' and es_cen());
create policy exp_leer_seccion on storage.objects for select to authenticated
  using (bucket_id = 'expedientes' and mi_rol() in ('seccion_organizacion','seccion_sg')
         and name like 'solicitudes/' || (select slug from secciones where id = mi_seccion()) || '/%');
-- Solo Organización del CEN borra o mueve (al pasar el expediente a Drive)
create policy exp_borrar_org on storage.objects for delete to authenticated
  using (bucket_id = 'expedientes' and es_org());
create policy exp_actualizar_org on storage.objects for update to authenticated
  using (bucket_id = 'expedientes' and es_org()) with check (bucket_id = 'expedientes' and es_org());
