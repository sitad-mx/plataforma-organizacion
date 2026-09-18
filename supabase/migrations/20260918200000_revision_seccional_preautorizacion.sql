-- 023 · Revisión seccional (decisión de Manuel, 18-sep tarde): la Sección revisa el expediente, observa, da seguimiento
--       y PREAUTORIZA; al CEN llegan las preautorizadas (etapa "Lista para el CEN"). El CEN puede regresarla a la Sección.

alter table solicitudes_afiliacion
  add column if not exists preautorizada_at timestamptz,
  add column if not exists preautorizada_por uuid,
  add column if not exists preautorizacion_nota text;

-- La Sección puede validar/observar documentos de sus solicitudes abiertas
drop policy if exists upd_docs_seccion on solicitud_documentos;
create policy upd_docs_seccion on solicitud_documentos for update to authenticated
  using (mi_rol() = 'seccion_organizacion' and exists (select 1 from solicitudes_afiliacion s where s.id = solicitud_id and s.seccion_id = mi_seccion() and s.estado in ('Recibida','Prevenida','Subsanada')))
  with check (exists (select 1 from solicitudes_afiliacion s where s.id = solicitud_id and s.seccion_id = mi_seccion()));
-- La Sección puede registrar seguimientos (no prevenciones formales)
drop policy if exists ins_seg_seccion on solicitud_seguimientos;
create policy ins_seg_seccion on solicitud_seguimientos for insert to authenticated
  with check (mi_rol() = 'seccion_organizacion' and tipo <> 'prevencion' and exists (select 1 from solicitudes_afiliacion s where s.id = solicitud_id and s.seccion_id = mi_seccion() and s.estado in ('Recibida','Prevenida','Subsanada')));

-- Campos que la Sección puede tocar en la solicitud
create or replace function seccion_solo_subsana() returns trigger language plpgsql security definer set search_path = public as $$
declare v_tol text[] := array['fecha_subsanacion','novedad_at','revisado_at','updated_at','limite_dictamen','limite_prevencion','limite_subsanacion','estado','documentos_completos','trimestre_reporte','limite_ejecucion','preautorizada_at','preautorizada_por','preautorizacion_nota'];
begin
  if auth.uid() is not null and mi_rol() = 'seccion_organizacion' then
    if (to_jsonb(new) - v_tol) <> (to_jsonb(old) - v_tol) then
      raise exception 'La Sección solo puede revisar, dar seguimiento y preautorizar; el resto lo lleva la Secretaría de Organización del CEN.';
    end if;
  end if;
  return new;
end $$;

-- Preautorizar (Sección) y regresar a la Sección (CEN)
create or replace function preautorizar_seccion(p_id uuid, p_nota text default null) returns void language plpgsql security definer set search_path = public as $$
declare v_s solicitudes_afiliacion%rowtype; v_obs int;
begin
  select * into v_s from solicitudes_afiliacion where id = p_id;
  if not found then raise exception 'Solicitud no encontrada.'; end if;
  if not (es_org() or (mi_rol() = 'seccion_organizacion' and v_s.seccion_id = mi_seccion())) then raise exception 'Solo la Secretaría de Organización de la Sección (o el CEN) puede preautorizar.'; end if;
  if v_s.estado not in ('Recibida','Prevenida','Subsanada') then raise exception 'La solicitud ya no está en revisión (estado: %).', v_s.estado; end if;
  if not v_s.documentos_completos then raise exception 'El expediente no está completo; no se puede preautorizar.'; end if;
  select count(*) into v_obs from solicitud_documentos where solicitud_id = p_id and validado = false;
  if v_obs > 0 then raise exception 'Hay % documento(s) con observación sin corregir; no se puede preautorizar.', v_obs; end if;
  update solicitudes_afiliacion set preautorizada_at = now(), preautorizada_por = auth.uid(), preautorizacion_nota = nullif(trim(coalesce(p_nota,'')),''), revisado_at = now() where id = p_id;
  perform bitacora('solicitudes_afiliacion', p_id, v_s.folio, 'preautorizacion', null, 'Preautorizada por la Sección' || coalesce(': ' || p_nota, ''));
end $$;
grant execute on function preautorizar_seccion(uuid, text) to authenticated;

create or replace function regresar_a_seccion(p_id uuid, p_motivo text) returns void language plpgsql security definer set search_path = public as $$
declare v_s solicitudes_afiliacion%rowtype;
begin
  if not es_org() then raise exception 'Solo Organización del CEN puede regresar una solicitud a la Sección.'; end if;
  select * into v_s from solicitudes_afiliacion where id = p_id;
  update solicitudes_afiliacion set preautorizada_at = null, preautorizada_por = null, preautorizacion_nota = null where id = p_id;
  insert into solicitud_seguimientos (solicitud_id, tipo, puntos, texto) values (p_id, 'mensaje', '{}', 'Regresada por el CEN a revisión de la Sección: ' || coalesce(p_motivo, ''));
  perform bitacora('solicitudes_afiliacion', p_id, v_s.folio, 'preautorizacion', 'Preautorizada', 'Regresada a la Sección: ' || coalesce(p_motivo, ''));
end $$;
grant execute on function regresar_a_seccion(uuid, text) to authenticated;

-- Los seguimientos de la Sección quedan firmados por ella (para la consulta pública)
alter table solicitud_seguimientos add column if not exists origen text not null default 'cen' check (origen in ('cen','seccion'));
create or replace function seguimientos_reglas() returns trigger language plpgsql security definer set search_path = public as $$
begin
  new.created_by := coalesce(new.created_by, auth.uid());
  new.creado_por_email := coalesce(new.creado_por_email, (select email from usuarios_roles where user_id = auth.uid()));
  if mi_rol() = 'seccion_organizacion' then new.origen := 'seccion'; end if;
  update solicitudes_afiliacion set revisado_at = now() where id = new.solicitud_id;
  perform bitacora('solicitudes_afiliacion', new.solicitud_id, (select folio from solicitudes_afiliacion where id = new.solicitud_id), 'seguimiento', null, new.origen || ' · ' || new.tipo || ': ' || coalesce(array_to_string(new.puntos, ' | '), new.texto));
  return new;
end $$;
drop function if exists seguimientos_publicos(text, text);
create or replace function seguimientos_publicos(p_folio text, p_correo text)
returns table (fecha date, tipo text, puntos text[], texto text, origen text)
language sql stable security definer set search_path = public as $$
  select g.fecha, g.tipo, g.puntos, g.texto, g.origen from solicitud_seguimientos g
  where g.solicitud_id = solicitud_por_clave(p_folio, p_correo) order by g.created_at desc;
$$;
grant execute on function seguimientos_publicos(text, text) to anon, authenticated;

-- Consulta pública: etapa
drop function if exists consultar_solicitud(text, text);
create or replace function consultar_solicitud(p_folio text, p_correo text)
returns table (folio text, estado estado_solicitud, seccion text, fecha_recepcion date, fecha_prevencion date, limite_subsanacion date, fecha_dictamen date, sentido sentido_dictamen, fecha_alta date, mensaje_publico text, nombre text, etapa text)
language sql stable security definer set search_path = public as $$
  select s.folio, s.estado, sec.denominacion, s.fecha_recepcion, s.fecha_prevencion, s.limite_subsanacion, s.fecha_dictamen, s.sentido, s.fecha_ejecucion_padron, s.mensaje_publico, s.nombre_completo,
         case when s.estado in ('Recibida','Prevenida','Subsanada') then (case when s.preautorizada_at is null then 'Revisión en tu Sección' else 'Revisión en la Secretaría de Organización del CEN' end) else s.estado::text end
  from solicitudes_afiliacion s join secciones sec on sec.id = s.seccion_id
  where s.id = solicitud_por_clave(p_folio, p_correo);
$$;
grant execute on function consultar_solicitud(text, text) to anon, authenticated;

-- v_solicitudes: etapa
drop view if exists v_tablero; drop view if exists v_solicitudes;
create view v_solicitudes with (security_invoker = true) as
select s.*,
       sec.denominacion as seccion, sec.numero as seccion_numero, sec.clave as seccion_clave, sec.slug as seccion_slug,
       sec.asamblea_fecha_hora, sec.asamblea_direccion, sec.convocatoria_url,
       case when s.estado in ('Recibida','Prevenida','Subsanada') then (case when s.preautorizada_at is null then 'Revisión seccional' else 'Lista para el CEN' end)
            when s.estado in ('Dictaminada favorable','Enviada al SG') then 'Con el SG'
            when s.estado = 'Autorizada' then 'Alta pendiente'
            else 'Concluida' end as etapa,
       (s.novedad_at is not null and (s.revisado_at is null or s.novedad_at > s.revisado_at)) as con_novedad,
       exists (select 1 from padron p where p.solicitud_id = s.id and p.alta_enviada_at is null) as alta_por_enviar,
       exists (select 1 from padron p where p.estatus <> 'Baja' and p.solicitud_id is distinct from s.id and ((s.curp is not null and p.curp = s.curp) or lower(p.correo) = lower(s.correo)))
       or exists (select 1 from solicitudes_afiliacion o where o.id <> s.id and o.estado not in ('Dictaminada desfavorable','Desistida') and ((s.curp is not null and o.curp = s.curp) or lower(o.correo) = lower(s.correo))) as duplicado,
       case when s.estado in ('Ejecutada en padrón','Dictaminada desfavorable','Desistida') then 'cerrada'
            when s.es_confianza then 'rojo'
            when exists (select 1 from padron p where p.estatus <> 'Baja' and p.solicitud_id is distinct from s.id and ((s.curp is not null and p.curp = s.curp) or lower(p.correo) = lower(s.correo))) then 'rojo'
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
union all select 3, 2, 'En revisión seccional (sin preautorizar)', (select count(*) from v_solicitudes where etapa = 'Revisión seccional'), 'Las atiende la Secretaría de Organización de cada Sección.'
union all select 3, 3, 'Listas para el CEN (preautorizadas, sin dictamen)', (select count(*) from v_solicitudes where etapa = 'Lista para el CEN'), 'Pendientes de dictaminar dentro de 10 días hábiles.'
union all select 3, 4, 'Solicitudes fuera de plazo', (select count(*) from v_solicitudes where fuera_de_plazo), 'Cada una es un incumplimiento estatutario: atender hoy.'
union all select 3, 5, 'Solicitudes con novedades (documentos nuevos por revisar)', (select count(*) from v_solicitudes where con_novedad), 'La persona subió algo después de la revisión: volver a revisar.'
union all select 3, 6, 'Autorizaciones del SG pendientes', (select count(*) from solicitudes_afiliacion where estado = 'Enviada al SG'), 'Recordar al SG si pasan de 3 días.'
union all select 3, 7, 'Altas autorizadas por enviar (constancia, gafete, carta)', (select count(*) from padron where alta_enviada_at is null), 'El SG ya autorizó; Organización envía los documentos con un clic y marca enviado.'
union all select 3, 8, 'Altas ejecutadas en el trimestre en curso', (select count(*) from solicitudes_afiliacion, t where fecha_ejecucion_padron >= t.ini_trim and fecha_ejecucion_padron <= current_date), 'Insumo de la relación trimestral a Asuntos Jurídicos.'
union all select 3, 9, 'Bajas registradas en el trimestre en curso', (select count(*) from padron, t where fecha_baja >= t.ini_trim and fecha_baja <= current_date), 'Insumo de la relación trimestral.'
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

-- La Sección necesita leer configuración pública para su manual y sus mensajes: ya tiene config_publica. Nada más.
