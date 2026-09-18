-- 019 · Proceso tal como lo describe Manuel (2026-09-18): consulta por nombre o correo, INE frente/reverso,
--       mensaje al trabajador por folio, aviso de novedades al CEN, alta automática al autorizar el SG,
--       la Sección puede reemplazar documentos, cobranza para Finanzas.
create extension if not exists unaccent;

alter table solicitud_documentos add column if not exists parte text check (parte in ('frente','reverso'));
alter table solicitudes_afiliacion
  add column if not exists mensaje_publico text,
  add column if not exists novedad_at timestamptz,
  add column if not exists revisado_at timestamptz;

-- Localizar una solicitud con folio + (correo o nombre)
create or replace function solicitud_por_clave(p_folio text, p_clave text) returns uuid
language sql stable security definer set search_path = public as $$
  select s.id from solicitudes_afiliacion s
  where upper(trim(s.folio)) = upper(trim(p_folio))
    and (
      (position('@' in coalesce(p_clave,'')) > 0 and lower(trim(s.correo)) = lower(trim(p_clave)))
      or (position('@' in coalesce(p_clave,'')) = 0 and length(trim(coalesce(p_clave,''))) >= 4
          and lower(unaccent(s.nombre_completo)) like '%' || lower(unaccent(trim(p_clave))) || '%')
    )
  limit 1;
$$;
revoke execute on function solicitud_por_clave(text, text) from public, anon, authenticated;

-- Expediente completo: INE necesita frente y reverso (o un solo archivo con ambos lados)
create or replace function documento_presente(p_solicitud uuid, p_tipo tipo_documento_afiliacion) returns boolean
language sql stable security definer set search_path = public as $$
  select case when p_tipo = 'identificacion' then
      (exists (select 1 from solicitud_documentos d where d.solicitud_id = p_solicitud and d.tipo = p_tipo and d.parte = 'frente' and d.archivo_url is not null)
       and exists (select 1 from solicitud_documentos d where d.solicitud_id = p_solicitud and d.tipo = p_tipo and d.parte = 'reverso' and d.archivo_url is not null))
      or exists (select 1 from solicitud_documentos d where d.solicitud_id = p_solicitud and d.tipo = p_tipo and d.parte is null and d.archivo_url is not null)
    else exists (select 1 from solicitud_documentos d where d.solicitud_id = p_solicitud and d.tipo = p_tipo and d.archivo_url is not null) end;
$$;
revoke execute on function documento_presente(uuid, tipo_documento_afiliacion) from public, anon;

create or replace function recalcular_documentos_completos() returns trigger language plpgsql security definer set search_path = public as $$
declare v_id uuid; v_ok boolean; v_transporte boolean;
begin
  v_id := coalesce(new.solicitud_id, old.solicitud_id);
  select actividad_transporte into v_transporte from solicitudes_afiliacion where id = v_id;
  select coalesce(bool_and(documento_presente(v_id, r)), false) into v_ok from unnest(documentos_requeridos(coalesce(v_transporte, false))) r;
  update solicitudes_afiliacion set documentos_completos = coalesce(v_ok, false) where id = v_id;
  return null;
end $$;
create or replace function solicitudes_recalcular_por_transporte() returns trigger language plpgsql security definer set search_path = public as $$
declare v_ok boolean;
begin
  if new.actividad_transporte is distinct from old.actividad_transporte then
    select coalesce(bool_and(documento_presente(new.id, r)), false) into v_ok from unnest(documentos_requeridos(new.actividad_transporte)) r;
    new.documentos_completos := coalesce(v_ok, false);
  end if;
  return new;
end $$;

-- RPC públicas con clave (correo o nombre)
drop function if exists consultar_solicitud(text, text);
create or replace function consultar_solicitud(p_folio text, p_correo text)
returns table (folio text, estado estado_solicitud, seccion text, fecha_recepcion date, fecha_prevencion date, limite_subsanacion date, fecha_dictamen date, sentido sentido_dictamen, fecha_alta date, mensaje_publico text, nombre text)
language sql stable security definer set search_path = public as $$
  select s.folio, s.estado, sec.denominacion, s.fecha_recepcion, s.fecha_prevencion, s.limite_subsanacion, s.fecha_dictamen, s.sentido, s.fecha_ejecucion_padron, s.mensaje_publico, s.nombre_completo
  from solicitudes_afiliacion s join secciones sec on sec.id = s.seccion_id
  where s.id = solicitud_por_clave(p_folio, p_correo);
$$;
grant execute on function consultar_solicitud(text, text) to anon, authenticated;

drop function if exists documentos_publicos(text, text);
create or replace function documentos_publicos(p_folio text, p_correo text)
returns table (slug text, tipo tipo_documento_afiliacion, parte text, nombre_archivo text, validado boolean, observacion text, actividad_transporte boolean, correo text)
language sql stable security definer set search_path = public as $$
  select sec.slug, d.tipo, d.parte, d.nombre_archivo, d.validado, d.observacion, s.actividad_transporte, s.correo
  from solicitudes_afiliacion s join secciones sec on sec.id = s.seccion_id
  left join solicitud_documentos d on d.solicitud_id = s.id
  where s.id = solicitud_por_clave(p_folio, p_correo);
$$;
grant execute on function documentos_publicos(text, text) to anon, authenticated;

create or replace function solicitud_publica_datos(p_folio text, p_correo text)
returns jsonb language sql stable security definer set search_path = public as $$
  select to_jsonb(s) - array['ip_captura','notas','created_by','autorizado_por','dictamen_pdf_url','motivo_desfavorable','novedad_at','revisado_at']
         || jsonb_build_object('seccion', sec.denominacion, 'seccion_numero', sec.numero, 'seccion_clave', sec.clave, 'seccion_slug', sec.slug,
                               'asamblea_fecha_hora', sec.asamblea_fecha_hora, 'asamblea_direccion', sec.asamblea_direccion, 'convocatoria_url', sec.convocatoria_url)
  from solicitudes_afiliacion s join secciones sec on sec.id = s.seccion_id
  where s.id = solicitud_por_clave(p_folio, p_correo);
$$;

drop function if exists registrar_documento_publico(text, text, tipo_documento_afiliacion, text, text);
create or replace function registrar_documento_publico(p_folio text, p_correo text, p_tipo tipo_documento_afiliacion, p_archivo_url text, p_nombre_archivo text, p_parte text default null)
returns table (folio text, documentos_completos boolean, estado estado_solicitud)
language plpgsql security definer set search_path = public as $$
declare v_s solicitudes_afiliacion%rowtype;
begin
  select * into v_s from solicitudes_afiliacion s where s.id = solicitud_por_clave(p_folio, p_correo);
  if not found then raise exception 'Folio, nombre o correo incorrectos.'; end if;
  if v_s.estado not in ('Recibida','Prevenida','Subsanada') then raise exception 'Esta solicitud ya no admite documentos (estado: %).', v_s.estado; end if;
  delete from solicitud_documentos where solicitud_id = v_s.id and tipo = p_tipo and p_tipo <> 'otro' and parte is not distinct from p_parte;
  insert into solicitud_documentos (solicitud_id, tipo, parte, archivo_url, nombre_archivo) values (v_s.id, p_tipo, p_parte, p_archivo_url, p_nombre_archivo);
  -- Aviso al CEN: llegó algo nuevo después del registro inicial o tras una prevención
  if v_s.estado = 'Prevenida' or v_s.created_at < now() - interval '1 hour' then
    update solicitudes_afiliacion set novedad_at = now() where id = v_s.id;
  end if;
  if v_s.estado = 'Prevenida' and v_s.fecha_subsanacion is null then
    update solicitudes_afiliacion set fecha_subsanacion = current_date where id = v_s.id;
  end if;
  return query select s.folio, s.documentos_completos, s.estado from solicitudes_afiliacion s where s.id = v_s.id;
end $$;
grant execute on function registrar_documento_publico(text, text, tipo_documento_afiliacion, text, text, text) to anon, authenticated;

-- Alta automática en el Padrón cuando el Secretario General autoriza (CAMBIOS 2026-09-15 (2))
create or replace function alta_automatica() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.estado = 'Autorizada' and old.estado is distinct from 'Autorizada' and new.sentido = 'Favorable'
     and not exists (select 1 from padron p where p.solicitud_id = new.id) then
    insert into padron (folio, solicitud_id, seccion_id, tipo_movimiento, nombre_completo, curp, rfc, fecha_nacimiento, estado_civil, genero, domicilio, colonia, cp, municipio, estado_domicilio,
      correo, telefono, nss, unidad_medica, unidad_medica_ciudad, escolaridad, escolaridad_estado, carrera, puesto, empresa, fecha_inicio_relacion, domicilio_fiscal, frecuencia_pago, telefono_empresa, jefe_laboral,
      seguro_aseguradora, seguro_poliza, seguro_vigencia, conyuge_nombre, conyuge_domicilio, conyuge_telefono, dependientes, identificacion_tipo, patron, actividad_transporte, ciudad_firma, centro_trabajo,
      fecha_dictamen, fecha_autorizacion_sg, autorizacion_sg_ref, expediente_url, fecha_alta)
    values (new.folio, new.id, new.seccion_id, new.tipo_movimiento, new.nombre_completo, new.curp, new.rfc, new.fecha_nacimiento, new.estado_civil, new.genero, new.domicilio, new.colonia, new.cp, new.municipio, new.estado_domicilio,
      new.correo, new.telefono, new.nss, new.unidad_medica, new.unidad_medica_ciudad, new.escolaridad, new.escolaridad_estado, new.carrera, new.puesto, new.empresa, new.fecha_inicio_relacion, new.domicilio_fiscal, new.frecuencia_pago, new.telefono_empresa, new.jefe_laboral,
      new.seguro_aseguradora, new.seguro_poliza, new.seguro_vigencia, new.conyuge_nombre, new.conyuge_domicilio, new.conyuge_telefono, new.dependientes, new.identificacion_tipo, new.patron, new.actividad_transporte, new.ciudad_firma, new.centro_trabajo,
      new.fecha_dictamen, new.fecha_autorizacion_sg, new.autorizacion_sg_ref, new.expediente_url, current_date);
  end if;
  return null;
end $$;
drop trigger if exists trg_alta_automatica on solicitudes_afiliacion;
create trigger trg_alta_automatica after update on solicitudes_afiliacion for each row execute function alta_automatica();
revoke execute on function alta_automatica() from public, anon, authenticated;

-- La Sección puede reemplazar documentos de sus solicitudes abiertas (borrar el anterior)
drop policy if exists del_docs_seccion on solicitud_documentos;
create policy del_docs_seccion on solicitud_documentos for delete to authenticated using (
  mi_rol() = 'seccion_organizacion' and exists (select 1 from solicitudes_afiliacion s where s.id = solicitud_id and s.seccion_id = mi_seccion() and s.estado in ('Recibida','Prevenida','Subsanada')));
drop policy if exists ins_docs on solicitud_documentos;
create policy ins_docs on solicitud_documentos for insert to authenticated with check (
  es_org() or (mi_rol() = 'seccion_organizacion' and exists (select 1 from solicitudes_afiliacion s where s.id = solicitud_id and s.seccion_id = mi_seccion() and s.estado in ('Recibida','Prevenida','Subsanada'))));
-- La Sección puede marcar subsanación al subir por la persona
drop policy if exists upd_solicitudes_seccion on solicitudes_afiliacion;
create policy upd_solicitudes_seccion on solicitudes_afiliacion for update to authenticated
  using (mi_rol() = 'seccion_organizacion' and seccion_id = mi_seccion() and estado in ('Recibida','Prevenida','Subsanada'))
  with check (seccion_id = mi_seccion());
create or replace function seccion_solo_subsana() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is not null and mi_rol() = 'seccion_organizacion' then
    if (to_jsonb(new) - array['fecha_subsanacion','novedad_at','updated_at','limite_dictamen','limite_prevencion','limite_subsanacion','estado','documentos_completos','trimestre_reporte','limite_ejecucion'])
       <> (to_jsonb(old) - array['fecha_subsanacion','novedad_at','updated_at','limite_dictamen','limite_prevencion','limite_subsanacion','estado','documentos_completos','trimestre_reporte','limite_ejecucion']) then
      raise exception 'La Sección solo puede registrar la subsanación; el resto lo lleva la Secretaría de Organización del CEN.';
    end if;
  end if;
  return new;
end $$;
drop trigger if exists trg_seccion_solo_subsana on solicitudes_afiliacion;
create trigger trg_seccion_solo_subsana before update on solicitudes_afiliacion for each row execute function seccion_solo_subsana();
revoke execute on function seccion_solo_subsana() from public, anon, authenticated;

-- Cobranza: afiliados activos con su último pago verificado
create or replace view v_cobranza with (security_invoker = true) as
select p.id, p.numero_afiliacion, p.folio, p.nombre_completo, p.curp, p.correo, p.telefono, p.fecha_alta, p.estatus,
       sec.denominacion as seccion, sec.numero as seccion_numero,
       (select max(fecha_operacion) from pagos_cuota g where g.afiliado_id = p.id and g.estado = 'Verificado') as ultimo_pago,
       (select periodo from pagos_cuota g where g.afiliado_id = p.id and g.estado = 'Verificado' order by fecha_operacion desc limit 1) as ultimo_periodo,
       (select count(*) from pagos_cuota g where g.afiliado_id = p.id and g.estado = 'Verificado') as pagos_verificados,
       (select count(*) from pagos_cuota g where g.afiliado_id = p.id and g.estado = 'Recibido') as pagos_por_verificar
from padron p join secciones sec on sec.id = p.seccion_id;
grant select on v_cobranza to authenticated;

-- Vistas: recrear v_solicitudes (columnas nuevas) y v_tablero
drop view if exists v_tablero; drop view if exists v_solicitudes;
create view v_solicitudes with (security_invoker = true) as
select s.*,
       sec.denominacion as seccion, sec.numero as seccion_numero, sec.clave as seccion_clave, sec.slug as seccion_slug,
       sec.asamblea_fecha_hora, sec.asamblea_direccion, sec.convocatoria_url,
       (s.novedad_at is not null and (s.revisado_at is null or s.novedad_at > s.revisado_at)) as con_novedad,
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
union all select 3, 4, 'Solicitudes con novedades (documentos nuevos por revisar)', (select count(*) from v_solicitudes where con_novedad), 'La persona o la Sección subió algo después de la revisión: volver a revisar.'
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
union all select 7, 2, 'Pagos verificados en el trimestre', (select count(*) from pagos_cuota, t where estado = 'Verificado' and fecha_operacion >= t.ini_trim), 'Padrón financiero del trimestre.'
union all select 7, 3, 'Afiliados activos sin ningún pago verificado', (select count(*) from padron p where p.estatus = 'Activo' and not exists (select 1 from pagos_cuota g where g.afiliado_id = p.id and g.estado = 'Verificado')), 'Cobranza pendiente de Finanzas.';
grant select on v_solicitudes, v_tablero to authenticated;
