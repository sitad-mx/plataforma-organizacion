-- 022 · Decisiones de Manuel (18-sep, tarde): (3) seguimiento a la persona cuantas veces sea necesario, además de la prevención
--       formal única; (4) al autorizar el SG, el alta aparece en la bandeja del CEN como "por enviar" y se marca enviada con un clic.

-- ===== Seguimientos (rondas de corrección y mensajes por folio) =====
create table if not exists solicitud_seguimientos (
  id uuid primary key default gen_random_uuid(),
  solicitud_id uuid not null references solicitudes_afiliacion(id) on delete cascade,
  tipo text not null default 'seguimiento' check (tipo in ('prevencion','seguimiento','mensaje')),
  puntos text[] not null default '{}',
  texto text,
  fecha date not null default current_date,
  created_at timestamptz not null default now(),
  created_by uuid,
  creado_por_email text
);
create index if not exists solicitud_seguimientos_sol_idx on solicitud_seguimientos (solicitud_id, created_at);
alter table solicitud_seguimientos enable row level security;
revoke all on solicitud_seguimientos from anon;
grant select, insert, update, delete on solicitud_seguimientos to authenticated;
drop policy if exists sel_seg on solicitud_seguimientos;
create policy sel_seg on solicitud_seguimientos for select to authenticated using (
  es_cen() or exists (select 1 from solicitudes_afiliacion s where s.id = solicitud_id and s.seccion_id = mi_seccion()));
drop policy if exists adm_seg on solicitud_seguimientos;
create policy adm_seg on solicitud_seguimientos for all to authenticated using (es_org()) with check (es_org());
create or replace function seguimientos_reglas() returns trigger language plpgsql security definer set search_path = public as $$
begin
  new.created_by := coalesce(new.created_by, auth.uid());
  new.creado_por_email := coalesce(new.creado_por_email, (select email from usuarios_roles where user_id = auth.uid()));
  -- cada seguimiento cuenta como revisión: apaga la novedad
  update solicitudes_afiliacion set revisado_at = now() where id = new.solicitud_id;
  perform bitacora('solicitudes_afiliacion', new.solicitud_id, (select folio from solicitudes_afiliacion where id = new.solicitud_id), 'seguimiento', null, new.tipo || ': ' || coalesce(array_to_string(new.puntos, ' | '), new.texto));
  return new;
end $$;
drop trigger if exists trg_seguimientos_reglas on solicitud_seguimientos;
create trigger trg_seguimientos_reglas before insert on solicitud_seguimientos for each row execute function seguimientos_reglas();
revoke execute on function seguimientos_reglas() from public, anon, authenticated;

-- La persona ve sus seguimientos en la consulta (folio + nombre o correo)
create or replace function seguimientos_publicos(p_folio text, p_correo text)
returns table (fecha date, tipo text, puntos text[], texto text)
language sql stable security definer set search_path = public as $$
  select g.fecha, g.tipo, g.puntos, g.texto from solicitud_seguimientos g
  where g.solicitud_id = solicitud_por_clave(p_folio, p_correo) order by g.created_at desc;
$$;
grant execute on function seguimientos_publicos(text, text) to anon, authenticated;

-- ===== Altas por enviar (cola del CEN tras la autorización del SG) =====
alter table padron add column if not exists alta_enviada_at timestamptz, add column if not exists alta_enviada_por uuid, add column if not exists alta_enviada_medio text;
drop view if exists v_padron;
create view v_padron with (security_invoker = true) as
select p.*, sec.denominacion as seccion, sec.numero as seccion_numero, sec.clave as seccion_clave, sec.slug as seccion_slug,
       sec.asamblea_fecha_hora, sec.asamblea_direccion, sec.convocatoria_url, sec.situacion as seccion_situacion
from padron p join secciones sec on sec.id = p.seccion_id;
grant select on v_padron to authenticated;

-- v_solicitudes: bandera "alta por enviar"
drop view if exists v_tablero; drop view if exists v_solicitudes;
create view v_solicitudes with (security_invoker = true) as
select s.*,
       sec.denominacion as seccion, sec.numero as seccion_numero, sec.clave as seccion_clave, sec.slug as seccion_slug,
       sec.asamblea_fecha_hora, sec.asamblea_direccion, sec.convocatoria_url,
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
union all select 3, 2, 'Solicitudes sin dictamen', (select count(*) from solicitudes_afiliacion where fecha_dictamen is null and estado not in ('Desistida')), 'Pendientes de dictaminar dentro de 10 días hábiles.'
union all select 3, 3, 'Solicitudes fuera de plazo', (select count(*) from v_solicitudes where fuera_de_plazo), 'Cada una es un incumplimiento estatutario: atender hoy.'
union all select 3, 4, 'Solicitudes con novedades (documentos nuevos por revisar)', (select count(*) from v_solicitudes where con_novedad), 'La persona o la Sección subió algo después de la revisión: volver a revisar.'
union all select 3, 5, 'Autorizaciones del SG pendientes', (select count(*) from solicitudes_afiliacion where estado = 'Enviada al SG'), 'Recordar al SG si pasan de 3 días.'
union all select 3, 6, 'Altas autorizadas por enviar (constancia, gafete, carta)', (select count(*) from padron where alta_enviada_at is null), 'El SG ya autorizó; Organización envía los documentos con un clic y marca enviado.'
union all select 3, 7, 'Altas ejecutadas en el trimestre en curso', (select count(*) from solicitudes_afiliacion, t where fecha_ejecucion_padron >= t.ini_trim and fecha_ejecucion_padron <= current_date), 'Insumo de la relación trimestral a Asuntos Jurídicos.'
union all select 3, 8, 'Bajas registradas en el trimestre en curso', (select count(*) from padron, t where fecha_baja >= t.ini_trim and fecha_baja <= current_date), 'Insumo de la relación trimestral.'
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

-- Marcar alta enviada (Organización)
create or replace function marcar_alta_enviada(p_padron uuid, p_medio text) returns void language plpgsql security definer set search_path = public as $$
begin
  if not es_org() then raise exception 'Solo Organización del CEN marca el envío del alta.'; end if;
  update padron set alta_enviada_at = now(), alta_enviada_por = auth.uid(), alta_enviada_medio = p_medio where id = p_padron;
  perform bitacora('padron', p_padron, (select folio from padron where id = p_padron), 'alta_enviada', null, coalesce(p_medio, 'manual'));
end $$;
grant execute on function marcar_alta_enviada(uuid, text) to authenticated;

-- Configuración: cómo se envía el alta (hoy manual a un clic; 'automatico' cuando exista Resend)
insert into configuracion (clave, valor, descripcion) values ('envio_alta_modo', 'manual', 'manual = Organización envía con un clic desde la bandeja "Altas por enviar"; automatico = el sistema envía por correo al autorizar el SG y avisa a Organización (requiere Resend y buzón institucional)')
on conflict (clave) do nothing;
