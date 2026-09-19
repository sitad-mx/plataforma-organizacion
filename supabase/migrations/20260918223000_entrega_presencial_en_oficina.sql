-- 024 · Entrega presencial en la oficina seccional (decisión de Manuel con los secretarios seccionales, 18-sep-2026 noche)
-- La persona NO recibe por medios digitales su credencial ni su número de afiliación. Al autorizar el SG recibe una carta
-- de aceptación (constancia, gafete si hay asamblea, Documentos Básicos) que la cita en la oficina de su Sección; ahí entrega
-- su papelería en original (resguardo físico) y recibe su credencial y su número final de afiliado.

-- ===== 1. Oficina de atención de cada Sección (la llena la propia Sección o el CEN) =====
alter table secciones
  add column if not exists oficina_domicilio text,
  add column if not exists oficina_horario text,
  add column if not exists oficina_contacto_nombre text,
  add column if not exists oficina_contacto_telefono text;

create or replace function actualizar_oficina_seccion(p_seccion uuid, p_domicilio text, p_horario text, p_nombre text, p_telefono text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not (es_org() or (mi_rol() = 'seccion_organizacion' and mi_seccion() = p_seccion)) then
    raise exception 'Solo Organización del CEN o la Secretaría de Organización de la propia Sección actualizan la oficina de atención.';
  end if;
  update secciones set oficina_domicilio = nullif(trim(p_domicilio), ''), oficina_horario = nullif(trim(p_horario), ''),
         oficina_contacto_nombre = nullif(trim(p_nombre), ''), oficina_contacto_telefono = nullif(trim(p_telefono), ''), updated_at = now()
  where id = p_seccion;
  perform bitacora('secciones', p_seccion, null, 'oficina_atencion', null, coalesce(p_domicilio, '') || ' · ' || coalesce(p_nombre, '') || ' ' || coalesce(p_telefono, ''));
end $$;
grant execute on function actualizar_oficina_seccion(uuid, text, text, text, text) to authenticated;

-- ===== 2. Entrega presencial en el padrón =====
alter table padron
  add column if not exists entrega_at timestamptz,
  add column if not exists entrega_por uuid,
  add column if not exists entrega_lugar text,
  add column if not exists entrega_papeleria boolean,
  add column if not exists entrega_credencial boolean,
  add column if not exists entrega_nota text;

create or replace function registrar_entrega_presencial(p_padron uuid, p_papeleria boolean, p_credencial boolean, p_nota text default null)
returns void language plpgsql security definer set search_path = public as $$
declare v_sec uuid; v_folio text; v_lugar text;
begin
  select seccion_id, folio into v_sec, v_folio from padron where id = p_padron;
  if v_sec is null then raise exception 'No existe ese registro del padrón.'; end if;
  if es_org() then v_lugar := 'CEN';
  elsif mi_rol() in ('seccion_organizacion','seccion_sg') and mi_seccion() = v_sec then v_lugar := 'Sección';
  else raise exception 'Solo la Sección de adscripción u Organización del CEN registran la entrega presencial.'; end if;
  if not coalesce(p_papeleria, false) or not coalesce(p_credencial, false) then
    raise exception 'Para cerrar la entrega deben quedar marcadas la papelería original recibida (resguardo físico) y la credencial entregada.';
  end if;
  update padron set entrega_at = now(), entrega_por = auth.uid(), entrega_lugar = v_lugar, entrega_papeleria = true, entrega_credencial = true,
         entrega_nota = nullif(trim(p_nota), '') where id = p_padron;
  perform bitacora('padron', p_padron, v_folio, 'entrega_presencial', null, v_lugar || coalesce(' · ' || nullif(trim(p_nota), ''), ''));
end $$;
grant execute on function registrar_entrega_presencial(uuid, boolean, boolean, text) to authenticated;

-- El CEN puede reabrir una entrega registrada por error
create or replace function anular_entrega_presencial(p_padron uuid) returns void language plpgsql security definer set search_path = public as $$
begin
  if not es_org() then raise exception 'Solo Organización del CEN anula una entrega.'; end if;
  update padron set entrega_at = null, entrega_por = null, entrega_lugar = null, entrega_papeleria = null, entrega_credencial = null, entrega_nota = null where id = p_padron;
  perform bitacora('padron', p_padron, (select folio from padron where id = p_padron), 'entrega_presencial', 'registrada', 'anulada');
end $$;
grant execute on function anular_entrega_presencial(uuid) to authenticated;

-- ===== 3. Vistas (v_pagos y v_cobranza no dependen de estas; se quedan) =====
drop view if exists v_tablero; drop view if exists v_solicitudes; drop view if exists v_padron; drop view if exists v_secciones;

create view v_secciones with (security_invoker = true) as
select s.*,
       (select count(*) from padron p where p.seccion_id = s.id and p.estatus = 'Activo') as afiliados_adscritos,
       (select count(*) from cargos_seccionales c where c.seccion_id = s.id and c.estatus = 'Vigente') as cargos_vigentes,
       (select count(*) from solicitudes_afiliacion q where q.seccion_id = s.id and q.estado not in ('Ejecutada en padrón','Dictaminada desfavorable','Desistida')) as solicitudes_en_tramite,
       (select count(*) from padron p where p.seccion_id = s.id and p.estatus = 'Activo' and p.entrega_at is null) as entregas_pendientes,
       case when s.ultimo_contacto is null then null else current_date - s.ultimo_contacto end as dias_sin_contacto
from secciones s;

create view v_padron with (security_invoker = true) as
select p.*, sec.denominacion as seccion, sec.numero as seccion_numero, sec.clave as seccion_clave, sec.slug as seccion_slug,
       sec.asamblea_fecha_hora, sec.asamblea_direccion, sec.convocatoria_url, sec.situacion as seccion_situacion,
       sec.oficina_domicilio, sec.oficina_horario, sec.oficina_contacto_nombre, sec.oficina_contacto_telefono
from padron p join secciones sec on sec.id = p.seccion_id;

create view v_solicitudes with (security_invoker = true) as
select s.*,
       sec.denominacion as seccion, sec.numero as seccion_numero, sec.clave as seccion_clave, sec.slug as seccion_slug,
       sec.asamblea_fecha_hora, sec.asamblea_direccion, sec.convocatoria_url,
       sec.oficina_domicilio, sec.oficina_horario, sec.oficina_contacto_nombre, sec.oficina_contacto_telefono,
       case when s.estado in ('Recibida','Prevenida','Subsanada') then (case when s.preautorizada_at is null then 'Revisión seccional' else 'Lista para el CEN' end)
            when s.estado in ('Dictaminada favorable','Enviada al SG') then 'Con el SG'
            when s.estado = 'Autorizada' then 'Alta pendiente'
            when s.estado = 'Ejecutada en padrón' and exists (select 1 from padron p where p.solicitud_id = s.id and p.entrega_at is null) then 'Entrega en oficina'
            else 'Concluida' end as etapa,
       (s.novedad_at is not null and (s.revisado_at is null or s.novedad_at > s.revisado_at)) as con_novedad,
       exists (select 1 from padron p where p.solicitud_id = s.id and p.alta_enviada_at is null) as alta_por_enviar,
       exists (select 1 from padron p where p.solicitud_id = s.id and p.entrega_at is null) as entrega_pendiente,
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
union all select 2, 7, 'Secciones con liga activa sin oficina de atención capturada', (select count(*) from secciones where liga_activa and oficina_domicilio is null), 'Sin domicilio la carta de aceptación no puede citar a la persona: pedir a la Sección que lo capture.'
union all select 3, 1, 'Solicitudes recibidas', (select count(*) from solicitudes_afiliacion), 'Total histórico.'
union all select 3, 2, 'En revisión seccional (sin preautorizar)', (select count(*) from v_solicitudes where etapa = 'Revisión seccional'), 'Las atiende la Secretaría de Organización de cada Sección.'
union all select 3, 3, 'Listas para el CEN (preautorizadas, sin dictamen)', (select count(*) from v_solicitudes where etapa = 'Lista para el CEN'), 'Pendientes de dictaminar dentro de 10 días hábiles.'
union all select 3, 4, 'Solicitudes fuera de plazo', (select count(*) from v_solicitudes where fuera_de_plazo), 'Cada una es un incumplimiento estatutario: atender hoy.'
union all select 3, 5, 'Solicitudes con novedades (documentos nuevos por revisar)', (select count(*) from v_solicitudes where con_novedad), 'La persona subió algo después de la revisión: volver a revisar.'
union all select 3, 6, 'Autorizaciones del SG pendientes', (select count(*) from solicitudes_afiliacion where estado = 'Enviada al SG'), 'Recordar al SG si pasan de 3 días.'
union all select 3, 7, 'Altas autorizadas por enviar (carta de aceptación)', (select count(*) from padron where alta_enviada_at is null), 'El SG ya autorizó; Organización envía la carta de aceptación con un clic y marca enviado.'
union all select 3, 8, 'Afiliados por atender en oficina (papelería original y credencial)', (select count(*) from padron where estatus = 'Activo' and entrega_at is null), 'La Sección recibe la papelería en original, la resguarda y entrega credencial y número de afiliado.'
union all select 3, 9, 'Altas ejecutadas en el trimestre en curso', (select count(*) from solicitudes_afiliacion, t where fecha_ejecucion_padron >= t.ini_trim and fecha_ejecucion_padron <= current_date), 'Insumo de la relación trimestral a Asuntos Jurídicos.'
union all select 3, 10, 'Bajas registradas en el trimestre en curso', (select count(*) from padron, t where fecha_baja >= t.ini_trim and fecha_baja <= current_date), 'Insumo de la relación trimestral.'
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
grant select on v_secciones, v_padron, v_solicitudes, v_tablero to authenticated;

-- ===== 4. Lo que ve la persona en su consulta: la oficina donde recoge su credencial y si ya la recibió =====
create or replace function solicitud_publica_datos(p_folio text, p_correo text)
returns jsonb language sql stable security definer set search_path = public as $$
  select to_jsonb(s) - array['ip_captura','notas','created_by','autorizado_por','dictamen_pdf_url','motivo_desfavorable','novedad_at','revisado_at','preautorizacion_nota','preautorizada_por']
         || jsonb_build_object('seccion', sec.denominacion, 'seccion_numero', sec.numero, 'seccion_clave', sec.clave, 'seccion_slug', sec.slug,
                               'asamblea_fecha_hora', sec.asamblea_fecha_hora, 'asamblea_direccion', sec.asamblea_direccion, 'convocatoria_url', sec.convocatoria_url,
                               'oficina_domicilio', sec.oficina_domicilio, 'oficina_horario', sec.oficina_horario,
                               'oficina_contacto_nombre', sec.oficina_contacto_nombre, 'oficina_contacto_telefono', sec.oficina_contacto_telefono,
                               'entrega_at', (select p.entrega_at from padron p where p.solicitud_id = s.id limit 1))
  from solicitudes_afiliacion s join secciones sec on sec.id = s.seccion_id
  where s.id = solicitud_por_clave(p_folio, p_correo);
$$;

-- Configuración: cómo se entrega la credencial (documenta la decisión)
insert into configuracion (clave, valor, descripcion) values ('entrega_credencial_modo', 'presencial', 'presencial = la credencial y el número de afiliado se entregan en la oficina de la Sección contra la papelería en original (decisión 18-sep-2026); digital = se envían con la carta de aceptación')
on conflict (clave) do nothing;

-- ===== 5. v_cobranza: Finanzas ve si la persona ya recibió su credencial (la carta AF-09 lleva el número; se envía después de la entrega) =====
create or replace view v_cobranza with (security_invoker = true) as
select p.id, p.numero_afiliacion, p.folio, p.nombre_completo, p.curp, p.correo, p.telefono, p.fecha_alta, p.estatus,
       sec.denominacion as seccion, sec.numero as seccion_numero,
       (select max(fecha_operacion) from pagos_cuota g where g.afiliado_id = p.id and g.estado = 'Verificado') as ultimo_pago,
       (select periodo from pagos_cuota g where g.afiliado_id = p.id and g.estado = 'Verificado' order by fecha_operacion desc limit 1) as ultimo_periodo,
       (select count(*) from pagos_cuota g where g.afiliado_id = p.id and g.estado = 'Verificado') as pagos_verificados,
       (select count(*) from pagos_cuota g where g.afiliado_id = p.id and g.estado = 'Recibido') as pagos_por_verificar,
       p.entrega_at
from padron p join secciones sec on sec.id = p.seccion_id;
grant select on v_cobranza to authenticated;
