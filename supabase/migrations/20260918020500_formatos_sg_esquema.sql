-- 016 · Formatos del SG en la base (ORDEN DE TRABAJO 2026-09-18, paso 1): campos del Anexo 23 y de la manifestación,
--       expediente nuevo (5 + 3 condicionales), secciones con acuerdo (Tlaxcala 35), folio por clave de entidad,
--       configuración de Finanzas y Módulo 5 (pagos de cuota).

-- ===== 1. Columnas del Anexo 23 y del Anexo 12-13 en solicitudes y padrón =====
do $$ declare t text;
begin
  foreach t in array array['solicitudes_afiliacion','padron'] loop
    execute format($f$
      alter table %I
        add column if not exists tipo_movimiento text not null default 'Alta' check (tipo_movimiento in ('Alta','Modificación')),
        add column if not exists estado_civil text,
        add column if not exists rfc text,
        add column if not exists colonia text,
        add column if not exists cp text,
        add column if not exists municipio text,
        add column if not exists estado_domicilio text,
        add column if not exists nss text,
        add column if not exists unidad_medica text,
        add column if not exists unidad_medica_ciudad text,
        add column if not exists escolaridad text,
        add column if not exists escolaridad_estado text check (escolaridad_estado in ('Trunca','Concluida')),
        add column if not exists carrera text,
        add column if not exists domicilio_fiscal text,
        add column if not exists frecuencia_pago text,
        add column if not exists telefono_empresa text,
        add column if not exists jefe_laboral text,
        add column if not exists seguro_aseguradora text,
        add column if not exists seguro_poliza text,
        add column if not exists seguro_vigencia text,
        add column if not exists conyuge_nombre text,
        add column if not exists conyuge_domicilio text,
        add column if not exists conyuge_telefono text,
        add column if not exists dependientes jsonb not null default '[]'::jsonb,
        add column if not exists identificacion_tipo text,
        add column if not exists patron text not null default 'REEDCAM',
        add column if not exists actividad_transporte boolean not null default false,
        add column if not exists ciudad_firma text
    $f$, t);
  end loop;
end $$;
comment on column solicitudes_afiliacion.puesto is 'Ocupación (Anexo 23, Información de la empresa)';
comment on column solicitudes_afiliacion.fecha_inicio_relacion is 'Ingreso (fecha de ingreso a la empresa, Anexo 23)';
comment on column solicitudes_afiliacion.dependientes is 'Hasta tres: [{"nombre","parentesco","edad"}] (Anexo 23)';

-- ===== 2. Expediente nuevo: migrar los tipos viejos y recalcular "completo" =====
update solicitud_documentos set tipo = 'identificacion' where tipo = 'identificacion_oficial_ine';
update solicitud_documentos set tipo = 'solicitud' where tipo = 'solicitud_afiliacion_firmada';
update solicitud_documentos set tipo = 'cedula' where tipo = 'cedula_afiliacion_anexo23';
delete from solicitud_documentos where tipo = 'aviso_privacidad_firmado';  -- el aviso va dentro del Anexo 12-13

create or replace function documentos_requeridos(p_transporte boolean) returns tipo_documento_afiliacion[]
language sql immutable as $$
  select case when p_transporte
    then array['solicitud','cedula','identificacion','curp','constancia_fiscal','tarjeta_circulacion','poliza','licencia']::tipo_documento_afiliacion[]
    else array['solicitud','cedula','identificacion','curp','constancia_fiscal']::tipo_documento_afiliacion[] end;
$$;

create or replace function recalcular_documentos_completos() returns trigger language plpgsql security definer set search_path = public as $$
declare v_id uuid; v_ok boolean; v_transporte boolean;
begin
  v_id := coalesce(new.solicitud_id, old.solicitud_id);
  select actividad_transporte into v_transporte from solicitudes_afiliacion where id = v_id;
  select coalesce(bool_and(exists (select 1 from solicitud_documentos d where d.solicitud_id = v_id and d.tipo = r and d.archivo_url is not null)), false)
    into v_ok from unnest(documentos_requeridos(coalesce(v_transporte, false))) r;
  update solicitudes_afiliacion set documentos_completos = coalesce(v_ok, false) where id = v_id;
  return null;
end $$;

-- Si cambia la bandera de transporte, se recalcula el expediente
create or replace function solicitudes_recalcular_por_transporte() returns trigger language plpgsql security definer set search_path = public as $$
declare v_ok boolean;
begin
  if new.actividad_transporte is distinct from old.actividad_transporte then
    select coalesce(bool_and(exists (select 1 from solicitud_documentos d where d.solicitud_id = new.id and d.tipo = r and d.archivo_url is not null)), false)
      into v_ok from unnest(documentos_requeridos(new.actividad_transporte)) r;
    new.documentos_completos := coalesce(v_ok, false);
  end if;
  return new;
end $$;
drop trigger if exists trg_solicitudes_transporte on solicitudes_afiliacion;
create trigger trg_solicitudes_transporte before update on solicitudes_afiliacion for each row execute function solicitudes_recalcular_por_transporte();
revoke execute on function solicitudes_recalcular_por_transporte() from public, anon, authenticated;
revoke execute on function documentos_requeridos(boolean) from anon;
update solicitudes_afiliacion s set documentos_completos = (
  select coalesce(bool_and(exists (select 1 from solicitud_documentos d where d.solicitud_id = s.id and d.tipo = r and d.archivo_url is not null)), false)
  from unnest(documentos_requeridos(s.actividad_transporte)) r);

-- ===== 3. Secciones: acuerdo del CEN, clave de entidad, liga activa, asamblea =====
alter table secciones
  add column if not exists clave text unique,
  add column if not exists liga_activa boolean not null default false,
  add column if not exists representante_facultado text,
  add column if not exists sede text,
  add column if not exists asamblea_fecha_hora timestamptz,
  add column if not exists asamblea_direccion text,
  add column if not exists convocatoria_url text,
  add column if not exists acuerdo_url text;
update secciones set clave = c.clave from (values
 ('aguascalientes','AGS'),('baja-california','BCN'),('baja-california-sur','BCS'),('coahuila','COA'),('colima','COL'),('chiapas','CHP'),('chihuahua','CHH'),
 ('ciudad-de-mexico','CMX'),('durango','DGO'),('guanajuato','GTO'),('jalisco','JAL'),('estado-de-mexico','MEX'),('michoacan','MIC'),('morelos','MOR'),('nayarit','NAY'),
 ('nuevo-leon','NLE'),('puebla','PUE'),('queretaro','QRO'),('quintana-roo','ROO'),('san-luis-potosi','SLP'),('sinaloa','SIN'),('sonora','SON'),('tabasco','TAB'),
 ('tamaulipas','TAM'),('tlaxcala','TLX'),('veracruz','VER'),('yucatan','YUC'),('ciudad-juarez','JUA')) as c(slug, clave) where secciones.slug = c.slug;
alter table secciones alter column clave set not null;

-- Ciudad Juárez: sin número hasta ver su acuerdo (se retira el 22 provisional). Folios: SITAD-JUA-######.
update secciones set numero = null, liga_activa = true,
  notas = 'Sección constituida en la práctica del SG (piloto). Número de Sección PENDIENTE: lo asigna el CEN en el acuerdo de creación (Manuel lo pide al SG). Mientras, folios SITAD-JUA-######. Capturar el CES electo con el acta.'
where slug = 'ciudad-juarez';
update secciones set liga_activa = true where slug = 'jalisco';
-- Tlaxcala: Sección 35 por acuerdo del CEN del 11-sep-2026; constitutiva 10-oct-2026 10:30.
update secciones set numero = 35, situacion = 'Acuerdo del CEN', liga_activa = true,
  fecha_acuerdo_cen = '2026-09-11', fecha_asamblea_constitutiva = '2026-10-10',
  asamblea_fecha_hora = '2026-10-10 10:30-06', asamblea_direccion = 'Calle Insurgentes #5, Col. Santa María Acuitlapilco, C.P. 90110, Tlaxcala, Tlaxcala',
  representante_facultado = 'Lic. Morayma Nahime Venegas Molina', sede = 'Ciudad de Tlaxcala, Tlaxcala', circunscripcion = 'Tlaxcala, Tlaxcala (por definir en la convocatoria)',
  notas = 'Sección 35 creada por acuerdo del CEN del 11-sep-2026 (AS-10 · Anexo 09). En constitución: Asamblea Constitutiva 10-oct-2026 10:30. Enlace facultado: Lic. Morayma Nahime Venegas Molina.'
where slug = 'tlaxcala';
-- Sonora: en constitución, liga activa, sin acuerdo aún (folios SITAD-SON-######).
update secciones set liga_activa = true, notas = coalesce(notas,'') || ' En constitución (práctica del SG); liga de afiliación activa; folios SITAD-SON-###### hasta que el CEN asigne número.' where slug = 'sonora';

alter table constituciones
  add column if not exists numero_asignado int,
  add column if not exists representante_facultado text,
  add column if not exists circunscripcion text,
  add column if not exists sede text,
  add column if not exists asamblea_fecha_hora timestamptz,
  add column if not exists asamblea_direccion text,
  add column if not exists acuerdo_url text,
  add column if not exists convocatoria_url text;
insert into constituciones (seccion_id, responsable_expediente, fecha_acuerdo_cen, fecha_asamblea, estado, numero_asignado, representante_facultado, sede, asamblea_fecha_hora, asamblea_direccion, notas)
select id, 'Secretaría de Organización del CEN', '2026-09-11', '2026-10-10', 'Convocada', 35, 'Lic. Morayma Nahime Venegas Molina', 'Ciudad de Tlaxcala, Tlaxcala', '2026-10-10 10:30-06',
  'Calle Insurgentes #5, Col. Santa María Acuitlapilco, C.P. 90110, Tlaxcala, Tlaxcala', 'Primer caso real. Acuerdo AS-10 (Anexo 09) del 11-sep-2026; convocatoria AS-02 (Anexo 01).'
from secciones where slug = 'tlaxcala' and not exists (select 1 from constituciones c where c.seccion_id = secciones.id);

-- Folio: número de Sección si lo hay; si no, clave de entidad (AF-04b). Sección habilitada = liga_activa.
create or replace function solicitudes_reglas() returns trigger language plpgsql security definer set search_path = public as $$
declare v_sec secciones%rowtype; v_serie text; v_restantes int; v_externa boolean := coalesce(current_setting('sitad.autorizacion_externa', true), '') = '1';
begin
  if tg_op = 'INSERT' then
    new.created_by := coalesce(new.created_by, auth.uid());
    if new.folio is null then
      select * into v_sec from secciones where id = new.seccion_id;
      v_serie := coalesce(v_sec.numero::text, v_sec.clave);
      if v_serie is null then raise exception 'La sección no tiene número ni clave; no se puede generar el folio.'; end if;
      new.folio := format('SITAD-%s-%s', v_serie, lpad(siguiente_folio('AF-' || v_serie)::text, 6, '0'));
    end if;
    if new.acepta_estatuto and new.acepta_estatuto_at is null then new.acepta_estatuto_at := now(); end if;
  end if;
  if tg_op = 'UPDATE' then
    if old.fecha_prevencion is not null and new.fecha_prevencion is distinct from old.fecha_prevencion then
      raise exception 'Solo se permite una prevención por solicitud (folio %).', old.folio;
    end if;
    if new.fecha_autorizacion_sg is distinct from old.fecha_autorizacion_sg and new.fecha_autorizacion_sg is not null then
      if auth.uid() is not null and mi_rol() <> 'sg' and not v_externa then
        raise exception 'Solo el Secretario General puede autorizar altas (folio %).', old.folio;
      end if;
      new.autorizado_por := coalesce(auth.uid(), new.autorizado_por);
      if new.estado in ('Enviada al SG','Dictaminada favorable') then new.estado := 'Autorizada'; end if;
    end if;
    if auth.uid() is not null and mi_rol() = 'sg' then
      if (to_jsonb(new) - array['fecha_autorizacion_sg','autorizacion_sg_ref','autorizado_por','estado','limite_ejecucion','updated_at','notas','fecha_envio_sg'])
         <> (to_jsonb(old) - array['fecha_autorizacion_sg','autorizacion_sg_ref','autorizado_por','estado','limite_ejecucion','updated_at','notas','fecha_envio_sg']) then
        raise exception 'El Secretario General solo puede autorizar o denegar; no editar la solicitud.';
      end if;
    end if;
  end if;
  new.limite_prevencion := dias_habiles(new.fecha_recepcion, 5);
  if new.fecha_prevencion is not null then new.limite_subsanacion := dias_habiles(new.fecha_prevencion, 10); end if;
  if new.fecha_prevencion is not null and new.fecha_subsanacion is not null then
    v_restantes := greatest(10 - dias_habiles_entre(new.fecha_recepcion, new.fecha_prevencion), 0);
    new.limite_dictamen := dias_habiles(new.fecha_subsanacion, v_restantes);
  else
    new.limite_dictamen := dias_habiles(new.fecha_recepcion, 10);
  end if;
  new.limite_ejecucion := case when new.fecha_autorizacion_sg is null then null else dias_habiles(new.fecha_autorizacion_sg, 2) end;
  new.trimestre_reporte := case when new.fecha_ejecucion_padron is null then null
    else format('T%s %s', ceil(extract(month from new.fecha_ejecucion_padron) / 3.0)::int, extract(year from new.fecha_ejecucion_padron)::int) end;
  if tg_op = 'UPDATE' then
    if new.fecha_prevencion is not null and old.fecha_prevencion is null and new.estado = 'Recibida' then new.estado := 'Prevenida'; end if;
    if new.fecha_subsanacion is not null and old.fecha_subsanacion is null and new.estado = 'Prevenida' then new.estado := 'Subsanada'; end if;
    if new.fecha_dictamen is not null and old.fecha_dictamen is null then
      if new.sentido = 'Favorable' then new.estado := 'Dictaminada favorable';
      elsif new.sentido = 'Desfavorable' then new.estado := 'Dictaminada desfavorable';
      elsif new.sentido = 'Desistimiento' then new.estado := 'Desistida'; end if;
    end if;
    if new.fecha_envio_sg is not null and old.fecha_envio_sg is null and new.estado = 'Dictaminada favorable' then new.estado := 'Enviada al SG'; end if;
    if new.fecha_ejecucion_padron is not null and old.fecha_ejecucion_padron is null then new.estado := 'Ejecutada en padrón'; end if;
  end if;
  return new;
end $$;
revoke execute on function solicitudes_reglas() from public, anon, authenticated;

-- Liga pública: sección con liga activa (tenga o no número)
create or replace function seccion_publica(p_slug text)
returns table (slug text, denominacion text, entidad text, numero int, clave text, situacion situacion_seccion, asamblea_fecha_hora timestamptz, asamblea_direccion text, convocatoria_url text)
language sql stable security definer set search_path = public as $$
  select s.slug, s.denominacion, s.entidad, s.numero, s.clave, s.situacion, s.asamblea_fecha_hora, s.asamblea_direccion, s.convocatoria_url
  from secciones s where s.slug = lower(trim(p_slug)) and s.liga_activa and s.situacion not in ('Suspendida','Suprimida');
$$;

-- Captura pública con los campos del Anexo 23 y de la manifestación (un solo JSON de datos)
create or replace function crear_solicitud_publica_v2(p_slug text, p_datos jsonb)
returns table (folio text, seccion text)
language plpgsql security definer set search_path = public as $$
declare v_sec secciones%rowtype; v_folio text; d jsonb := p_datos;
begin
  select * into v_sec from secciones where slug = lower(trim(p_slug)) and liga_activa and situacion not in ('Suspendida','Suprimida');
  if not found then raise exception 'La liga de afiliación no es válida o la Sección no está habilitada.'; end if;
  if not coalesce((d->>'acepta_estatuto')::boolean, false) then raise exception 'Es necesario aceptar los Estatutos y Documentos Básicos.'; end if;
  if not coalesce((d->>'acepta_aviso')::boolean, false) then raise exception 'Es necesario aceptar el Aviso de Privacidad.'; end if;
  if coalesce(d->>'correo','') !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then raise exception 'Correo electrónico no válido.'; end if;
  if length(trim(coalesce(d->>'nombre_completo',''))) < 5 then raise exception 'Escribe tu nombre completo.'; end if;
  insert into solicitudes_afiliacion (seccion_id, canal, tipo_movimiento, nombre_completo, curp, rfc, fecha_nacimiento, estado_civil, genero,
    domicilio, colonia, cp, municipio, estado_domicilio, correo, telefono, nss, unidad_medica, unidad_medica_ciudad,
    escolaridad, escolaridad_estado, carrera, puesto, empresa, fecha_inicio_relacion, domicilio_fiscal, frecuencia_pago, telefono_empresa, jefe_laboral,
    seguro_aseguradora, seguro_poliza, seguro_vigencia, conyuge_nombre, conyuge_domicilio, conyuge_telefono, dependientes,
    identificacion_tipo, patron, actividad_transporte, ciudad_firma, centro_trabajo, es_confianza, acepta_estatuto, acepta_estatuto_at, aviso_privacidad_at, ip_captura)
  values (v_sec.id, 'publico', coalesce(d->>'tipo_movimiento','Alta'), trim(d->>'nombre_completo'), nullif(upper(trim(d->>'curp')),''), nullif(upper(trim(d->>'rfc')),''),
    nullif(d->>'fecha_nacimiento','')::date, d->>'estado_civil', nullif(d->>'genero','')::genero,
    d->>'domicilio', d->>'colonia', d->>'cp', d->>'municipio', d->>'estado_domicilio', lower(trim(d->>'correo')), d->>'telefono', d->>'nss', d->>'unidad_medica', d->>'unidad_medica_ciudad',
    d->>'escolaridad', nullif(d->>'escolaridad_estado',''), d->>'carrera', d->>'puesto', coalesce(nullif(d->>'empresa',''),'REEDCAM'), nullif(d->>'fecha_inicio_relacion','')::date, d->>'domicilio_fiscal', d->>'frecuencia_pago', d->>'telefono_empresa', d->>'jefe_laboral',
    d->>'seguro_aseguradora', d->>'seguro_poliza', d->>'seguro_vigencia', d->>'conyuge_nombre', d->>'conyuge_domicilio', d->>'conyuge_telefono', coalesce(d->'dependientes','[]'::jsonb),
    d->>'identificacion_tipo', coalesce(nullif(d->>'patron',''),'REEDCAM'), coalesce((d->>'actividad_transporte')::boolean,false), d->>'ciudad_firma', coalesce(d->>'centro_trabajo', d->>'municipio'),
    coalesce((d->>'es_confianza')::boolean,false), true, now(), now(), nullif(d->>'ip','')::inet)
  returning solicitudes_afiliacion.folio into v_folio;
  return query select v_folio, v_sec.denominacion;
end $$;
grant execute on function crear_solicitud_publica_v2(text, jsonb) to anon, authenticated;

-- La persona recupera sus datos (folio + correo) para que el sistema le entregue el Anexo 12-13 y el Anexo 23 prellenados
create or replace function solicitud_publica_datos(p_folio text, p_correo text)
returns jsonb language sql stable security definer set search_path = public as $$
  select to_jsonb(s) - array['ip_captura','notas','created_by','autorizado_por','dictamen_pdf_url','motivo_desfavorable']
         || jsonb_build_object('seccion', sec.denominacion, 'seccion_numero', sec.numero, 'seccion_clave', sec.clave, 'seccion_slug', sec.slug,
                               'asamblea_fecha_hora', sec.asamblea_fecha_hora, 'asamblea_direccion', sec.asamblea_direccion, 'convocatoria_url', sec.convocatoria_url)
  from solicitudes_afiliacion s join secciones sec on sec.id = s.seccion_id
  where upper(trim(s.folio)) = upper(trim(p_folio)) and lower(trim(s.correo)) = lower(trim(p_correo));
$$;
grant execute on function solicitud_publica_datos(text, text) to anon, authenticated;

-- documentos_publicos: también devuelve si la solicitud es de transporte (para pedir los tres extra)
create or replace function documentos_publicos(p_folio text, p_correo text)
returns table (slug text, tipo tipo_documento_afiliacion, nombre_archivo text, validado boolean, observacion text, actividad_transporte boolean)
language sql stable security definer set search_path = public as $$
  select sec.slug, d.tipo, d.nombre_archivo, d.validado, d.observacion, s.actividad_transporte
  from solicitudes_afiliacion s
  join secciones sec on sec.id = s.seccion_id
  left join solicitud_documentos d on d.solicitud_id = s.id
  where upper(trim(s.folio)) = upper(trim(p_folio)) and lower(trim(s.correo)) = lower(trim(p_correo));
$$;

-- ===== 4. Configuración: cuota, datos bancarios (no van al repo público), Finanzas, ligas del SG =====
insert into configuracion (clave, valor, descripcion) values
 ('cuota_monto', '360', 'Monto de la cuota sindical en pesos (AF-09; lo fija Finanzas)'),
 ('cuota_periodicidad', 'mensual', 'Periodicidad de la cuota (AF-09 habla de "mes o período"; confirmar con Finanzas)'),
 ('banco_institucion', 'BANORTE', 'Cuenta oficial del Sindicato (AF-09)'),
 ('banco_titular', 'Sindicato de Trabajadores Digitales y Empleados de la Empresa Reedcam', 'Titular de la cuenta (AF-09)'),
 ('banco_cuenta', '1376586732', 'Número de cuenta (AF-09)'),
 ('banco_clabe', '072 180 01376586732 6', 'CLABE interbancaria (AF-09)'),
 ('correo_finanzas', 'enlace@sindicatodigital.org', 'Correo oficial de la Secretaría de Finanzas (AF-09)'),
 ('finanzas_titular', 'Luz Elena González Rubio', 'Secretaria de Finanzas del CEN (firma la AF-09)'),
 ('telefono_contacto', '55 21 623 756', 'Teléfono de contacto del Sindicato (aviso de privacidad del Anexo 13)'),
 ('domicilio_sg', 'Antonio Ancona 1, Piso 3, Col. Cuajimalpa, CP 05000, Cuajimalpa de Morelos, CDMX', 'Domicilio tal como lo escriben los anexos del SG (Piso 3)'),
 ('liga_documentos_basicos', 'https://drive.google.com/drive/folders/1xr1K4I2Cij4UK3G6_bNN73I2FU2wXLVj', 'Carpeta del SG con los Documentos Básicos (QR del gafete Anexo 14); confirmar vigencia'),
 ('secretario_general', 'Lic. Jesús Noé Grijalva Dueñas', 'Secretario General del CEN (firma acuerdos)')
on conflict (clave) do update set valor = excluded.valor, descripcion = excluded.descripcion;

-- Configuración pública mínima (para las pantallas sin usuario): solo claves no sensibles
create or replace function config_publica() returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_object_agg(clave, valor), '{}'::jsonb) from configuracion
  where clave in ('cuota_monto','cuota_periodicidad','correo_finanzas','correo_organizacion','liga_documentos_basicos','telefono_contacto','denominacion','lema');
$$;
grant execute on function config_publica() to anon, authenticated;

-- ===== 5. Módulo 5 · Pagos de cuota (según AF-09) =====
create table if not exists pagos_cuota (
  id uuid primary key default gen_random_uuid(),
  comprobante_folio text unique,
  afiliado_id uuid references padron(id),
  folio_solicitud text,
  curp text,
  nombre text not null,
  numero_afiliacion int,
  telefono text,
  periodo text not null,
  monto numeric(10,2) not null check (monto > 0),
  fecha_operacion date not null,
  comprobante_url text,
  comprobante_nombre text,
  estado text not null default 'Recibido' check (estado in ('Recibido','Verificado','Rechazado')),
  observacion text,
  verificado_por uuid,
  verificado_at timestamptz,
  canal text not null default 'publico' check (canal in ('publico','finanzas')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid
);
create index if not exists pagos_cuota_afiliado_idx on pagos_cuota (afiliado_id);
create index if not exists pagos_cuota_curp_idx on pagos_cuota (curp);
create index if not exists pagos_cuota_estado_idx on pagos_cuota (estado, fecha_operacion);
drop trigger if exists trg_pagos_cuota_updated on pagos_cuota;
create trigger trg_pagos_cuota_updated before update on pagos_cuota for each row execute function set_updated_at();

create or replace function pagos_reglas() returns trigger language plpgsql security definer set search_path = public as $$
declare v_p padron%rowtype;
begin
  if tg_op = 'INSERT' then
    new.created_by := coalesce(new.created_by, auth.uid());
    -- Ligar al afiliado por número de afiliación, CURP o folio de solicitud
    if new.afiliado_id is null then
      select * into v_p from padron where (new.numero_afiliacion is not null and numero_afiliacion = new.numero_afiliacion)
        or (new.curp is not null and curp = new.curp) or (new.folio_solicitud is not null and folio = new.folio_solicitud) limit 1;
      if found then new.afiliado_id := v_p.id; new.numero_afiliacion := v_p.numero_afiliacion; new.curp := coalesce(new.curp, v_p.curp); end if;
    end if;
    if new.afiliado_id is null and new.folio_solicitud is null and new.curp is not null then
      select folio into new.folio_solicitud from solicitudes_afiliacion where curp = new.curp and estado not in ('Dictaminada desfavorable','Desistida') order by created_at desc limit 1;
    end if;
  end if;
  if tg_op = 'UPDATE' and new.estado is distinct from old.estado then
    if new.estado = 'Verificado' then
      if new.comprobante_folio is null then
        new.comprobante_folio := format('CP-%s-%s', extract(year from current_date)::int, lpad(siguiente_folio('CP-' || extract(year from current_date)::int)::text, 4, '0'));
      end if;
      new.verificado_por := coalesce(auth.uid(), new.verificado_por); new.verificado_at := now();
    end if;
    perform bitacora('pagos_cuota', new.id, new.comprobante_folio, 'estado', old.estado, new.estado);
  end if;
  return new;
end $$;
drop trigger if exists trg_pagos_reglas on pagos_cuota;
create trigger trg_pagos_reglas before insert or update on pagos_cuota for each row execute function pagos_reglas();
revoke execute on function pagos_reglas() from public, anon, authenticated;

alter table pagos_cuota enable row level security;
revoke all on pagos_cuota from anon;
grant select, insert, update, delete on pagos_cuota to authenticated;
create or replace function es_finanzas() returns boolean language sql stable set search_path = public as $$ select mi_rol() in ('finanzas','cen_organizacion'); $$;
revoke execute on function es_finanzas() from public, anon;
drop policy if exists sel_pagos on pagos_cuota;
create policy sel_pagos on pagos_cuota for select to authenticated using (
  es_finanzas() or mi_rol() in ('sg','cen_lectura')
  or (mi_rol() in ('seccion_organizacion','seccion_sg') and afiliado_id in (select id from padron where seccion_id = mi_seccion())));
drop policy if exists adm_pagos on pagos_cuota;
create policy adm_pagos on pagos_cuota for all to authenticated using (es_finanzas()) with check (es_finanzas());

-- La persona registra su pago (antes o después del alta) con los siete datos de la AF-09
create or replace function registrar_pago_publico(p_nombre text, p_numero_afiliacion int, p_curp text, p_telefono text, p_periodo text, p_monto numeric, p_fecha date, p_comprobante_url text, p_comprobante_nombre text)
returns table (id uuid, ligado boolean)
language plpgsql security definer set search_path = public as $$
declare v_id uuid; v_lig boolean;
begin
  if p_numero_afiliacion is null and nullif(trim(coalesce(p_curp,'')),'') is null then raise exception 'Indica tu número de afiliación o tu CURP.'; end if;
  if length(trim(coalesce(p_nombre,''))) < 5 then raise exception 'Escribe tu nombre completo.'; end if;
  if p_comprobante_url is null then raise exception 'Adjunta el comprobante bancario.'; end if;
  insert into pagos_cuota (nombre, numero_afiliacion, curp, telefono, periodo, monto, fecha_operacion, comprobante_url, comprobante_nombre, canal)
  values (trim(p_nombre), p_numero_afiliacion, nullif(upper(trim(p_curp)),''), p_telefono, p_periodo, p_monto, p_fecha, p_comprobante_url, p_comprobante_nombre, 'publico')
  returning pagos_cuota.id, pagos_cuota.afiliado_id is not null into v_id, v_lig;
  return query select v_id, v_lig;
end $$;
grant execute on function registrar_pago_publico(text,int,text,text,text,numeric,date,text,text) to anon, authenticated;

-- Storage: los comprobantes van al mismo buzón, carpeta pagos/
drop policy if exists exp_subir_pagos on storage.objects;
create policy exp_subir_pagos on storage.objects for insert to anon, authenticated with check (bucket_id = 'expedientes' and name like 'pagos/%');
drop policy if exists exp_leer_finanzas on storage.objects;
create policy exp_leer_finanzas on storage.objects for select to authenticated using (bucket_id = 'expedientes' and name like 'pagos/%' and es_finanzas());

create or replace view v_pagos with (security_invoker = true) as
select pg.*, p.nombre_completo as afiliado_nombre, p.folio as afiliado_folio, sec.denominacion as seccion, sec.numero as seccion_numero
from pagos_cuota pg left join padron p on p.id = pg.afiliado_id left join secciones sec on sec.id = p.seccion_id;
grant select on v_pagos to authenticated;

-- ===== 6. Vistas: recrear v_solicitudes/v_padron/v_secciones para incluir las columnas nuevas =====
drop view if exists v_tablero; drop view if exists v_solicitudes; drop view if exists v_padron; drop view if exists v_secciones;
create view v_solicitudes with (security_invoker = true) as
select s.*,
       sec.denominacion as seccion, sec.numero as seccion_numero, sec.clave as seccion_clave, sec.slug as seccion_slug,
       sec.asamblea_fecha_hora, sec.asamblea_direccion, sec.convocatoria_url,
       exists (select 1 from padron p where p.estatus <> 'Baja' and ((s.curp is not null and p.curp = s.curp) or lower(p.correo) = lower(s.correo)))
       or exists (select 1 from solicitudes_afiliacion o where o.id <> s.id and o.estado not in ('Dictaminada desfavorable','Desistida') and ((s.curp is not null and o.curp = s.curp) or lower(o.correo) = lower(s.correo))) as duplicado,
       case when s.estado in ('Ejecutada en padrón','Dictaminada desfavorable','Desistida') then 'cerrada'
            when s.es_confianza then 'rojo'
            when exists (select 1 from padron p where p.estatus <> 'Baja' and ((s.curp is not null and p.curp = s.curp) or lower(p.correo) = lower(s.correo))) then 'rojo'
            when not s.documentos_completos then 'amarillo' else 'verde' end as semaforo,
       case when s.fecha_dictamen is null and s.estado in ('Recibida','Subsanada') and current_date > s.limite_dictamen then true
            when s.fecha_dictamen is not null and s.fecha_dictamen > s.limite_dictamen then true
            when s.estado = 'Prevenida' and current_date > s.limite_subsanacion then true
            when s.fecha_autorizacion_sg is not null and s.fecha_ejecucion_padron is null and current_date > s.limite_ejecucion then true
            when s.fecha_ejecucion_padron is not null and s.limite_ejecucion is not null and s.fecha_ejecucion_padron > s.limite_ejecucion then true
            else false end as fuera_de_plazo,
       case when s.fecha_dictamen is null and s.estado in ('Recibida','Subsanada') then s.limite_dictamen - current_date else null end as dias_para_dictamen,
       case when s.fecha_autorizacion_sg is not null and s.fecha_ejecucion_padron is null then s.limite_ejecucion - current_date else null end as dias_para_ejecutar
from solicitudes_afiliacion s join secciones sec on sec.id = s.seccion_id;
create view v_padron with (security_invoker = true) as
select p.*, sec.denominacion as seccion, sec.numero as seccion_numero, sec.clave as seccion_clave, sec.slug as seccion_slug,
       sec.asamblea_fecha_hora, sec.asamblea_direccion, sec.convocatoria_url, sec.situacion as seccion_situacion
from padron p join secciones sec on sec.id = p.seccion_id;
create view v_secciones with (security_invoker = true) as
select s.*,
       (select count(*) from padron p where p.seccion_id = s.id and p.estatus = 'Activo') as afiliados_adscritos,
       (select count(*) from cargos_seccionales c where c.seccion_id = s.id and c.estatus = 'Vigente') as cargos_vigentes,
       (select count(*) from solicitudes_afiliacion q where q.seccion_id = s.id and q.estado not in ('Ejecutada en padrón','Dictaminada desfavorable','Desistida')) as solicitudes_en_tramite,
       case when s.ultimo_contacto is null then null else current_date - s.ultimo_contacto end as dias_sin_contacto
from secciones s;
create view v_tablero with (security_invoker = true) as
with t as (select date_trunc('quarter', current_date)::date as ini_trim)
select 1 as bloque, 1 as orden, 'Secciones registradas' as indicador, (select count(*) from secciones)::numeric as valor, 'Universo de estructuras que la Secretaría atiende.' as lectura
union all select 1, 2, 'Secciones constituidas', (select count(*) from secciones where situacion = 'Constituida'), 'Las únicas con Comité Ejecutivo Seccional electo.'
union all select 1, 3, 'Secciones en proceso (presencia sin constitución)', (select count(*) from secciones where situacion in ('En proceso','Dictamen emitido','Acuerdo del CEN')), 'Candidatas a proceso de constitución.'
union all select 1, 4, 'Afiliados activos en el Padrón', (select count(*) from padron where estatus = 'Activo'), 'Base de la cobertura organizativa.'
union all select 1, 5, 'Afiliados adscritos a una sección constituida', (select count(*) from padron p join secciones s on s.id = p.seccion_id where p.estatus = 'Activo' and s.situacion = 'Constituida'), 'Personas afiliadas integradas a una estructura territorial constituida.'
union all select 1, 6, 'Cobertura organizativa (%)', (select case when count(*) = 0 then null else round(100.0 * count(*) filter (where s.situacion = 'Constituida') / count(*), 1) end from padron p join secciones s on s.id = p.seccion_id where p.estatus = 'Activo'), 'Meta: tender a 100%.'
union all select 2, 1, 'Secciones en condición NORMAL', (select count(*) from secciones where semaforo = 'Normal'), 'Dirigencia vigente, comunicación, funcionamiento y datos actualizados.'
union all select 2, 2, 'Secciones en SEGUIMIENTO', (select count(*) from secciones where semaforo = 'Seguimiento'), 'Revisar en la sesión mensual.'
union all select 2, 3, 'Secciones en INTERVENCIÓN', (select count(*) from secciones where semaforo = 'Intervención'), 'Requieren plan específico de recuperación.'
union all select 2, 4, 'Secciones sin contacto en más de 45 días', (select count(*) from secciones where ultimo_contacto is not null and current_date - ultimo_contacto > 45), 'Programar contacto esta semana.'
union all select 2, 5, 'Secciones constituidas con directorio completo (12 vigentes)', (select count(*) from secciones s where s.situacion = 'Constituida' and (select count(*) from cargos_seccionales c where c.seccion_id = s.id and c.estatus = 'Vigente') = 12), 'Indicador de actualización estructural.'
union all select 2, 6, 'Actualización estructural (%)', (select case when count(*) = 0 then null else round(100.0 * count(*) filter (where (select count(*) from cargos_seccionales c where c.seccion_id = s.id and c.estatus = 'Vigente') = 12) / count(*), 1) end from secciones s where s.situacion = 'Constituida'), 'Secciones constituidas con datos completos y vigentes.'
union all select 3, 1, 'Solicitudes recibidas', (select count(*) from solicitudes_afiliacion), 'Total histórico.'
union all select 3, 2, 'Solicitudes sin dictamen', (select count(*) from solicitudes_afiliacion where fecha_dictamen is null and estado not in ('Desistida')), 'Pendientes de dictaminar dentro de 10 días hábiles.'
union all select 3, 3, 'Solicitudes fuera de plazo', (select count(*) from v_solicitudes where fuera_de_plazo), 'Cada una es un incumplimiento estatutario: atender hoy.'
union all select 3, 4, 'Dictámenes favorables pendientes de ejecutar en el Padrón', (select count(*) from solicitudes_afiliacion where sentido = 'Favorable' and fecha_ejecucion_padron is null), 'Ejecutar en 2 días hábiles tras la autorización del SG.'
union all select 3, 5, 'Autorizaciones del SG pendientes', (select count(*) from solicitudes_afiliacion where estado = 'Enviada al SG'), 'Recordar al SG si pasan de 3 días.'
union all select 3, 6, 'Altas ejecutadas en el trimestre en curso', (select count(*) from solicitudes_afiliacion, t where fecha_ejecucion_padron >= t.ini_trim and fecha_ejecucion_padron <= current_date), 'Insumo de la relación trimestral a Asuntos Jurídicos.'
union all select 3, 7, 'Bajas registradas en el trimestre en curso', (select count(*) from padron, t where fecha_baja >= t.ini_trim and fecha_baja <= current_date), 'Insumo de la relación trimestral.'
union all select 4, 1, 'Movimientos abiertos', (select count(*) from movimientos where estado <> 'Cerrado'), 'Renuncias, vacantes y sustituciones en trámite.'
union all select 4, 2, 'Movimientos abiertos con más de 30 días', (select count(*) from movimientos where estado <> 'Cerrado' and current_date - fecha_recepcion > 30), 'Revisar por qué no cierran.'
union all select 4, 3, 'Movimientos formalizados sin registros actualizados', (select count(*) from movimientos where estado = 'Formalizado'), 'Actualizar REGISTRO/DIRECTORIO.'
union all select 5, 1, 'Incidencias abiertas', (select count(*) from incidencias where momento <> 'Cierre'), 'Todo asunto que altera el funcionamiento de una estructura.'
union all select 5, 2, 'Incidencias de prioridad ALTA abiertas', (select count(*) from incidencias where momento <> 'Cierre' and prioridad = 'Alta'), 'Atender esta semana.'
union all select 5, 3, 'Incidencias con compromiso vencido', (select count(*) from incidencias where momento <> 'Cierre' and fecha_compromiso < current_date), 'Compromisos incumplidos con secciones.'
union all select 5, 4, 'Incidencias canalizadas sin confirmación', (select count(*) from incidencias where canalizado_a is not null and canalizado_confirmado_at is null and momento <> 'Cierre'), 'Confirmar recepción con la instancia competente.'
union all select 6, 1, 'Procesos de constitución abiertos', (select count(*) from constituciones where estado not in ('Concluida','Detenida')), 'Secciones en nacimiento.'
union all select 6, 2, 'Constituciones fuera de plazo de convocatoria', (select count(*) from constituciones where fecha_acuerdo_cen is not null and fecha_convocatoria is null and current_date > limite_convocatoria), 'Convocar dentro de 30 días hábiles tras el acuerdo del CEN.'
union all select 6, 3, 'Asambleas programadas (próximos 30 días)', (select count(*) from secciones where asamblea_fecha_hora between now() and now() + interval '30 days'), 'Preparar padrón al corte, gafetes y lista de asistencia.'
union all select 7, 1, 'Pagos de cuota por verificar', (select count(*) from pagos_cuota where estado = 'Recibido'), 'Finanzas verifica la operación bancaria y emite el comprobante.'
union all select 7, 2, 'Pagos verificados en el trimestre', (select count(*) from pagos_cuota, t where estado = 'Verificado' and fecha_operacion >= t.ini_trim), 'Padrón financiero del trimestre.';
grant select on v_solicitudes, v_padron, v_secciones, v_tablero to authenticated;

-- Usuario de prueba de Finanzas
select crear_usuario_prueba('prueba.finanzas@sitad.test', 'Sitad-Prueba-2026', 'finanzas', null, 'PRUEBA Secretaría de Finanzas');
