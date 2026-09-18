-- 011 · Recrear v_solicitudes (incluye la columna canal agregada en 008) y v_tablero, que depende de ella.
drop view if exists v_tablero; drop view if exists v_solicitudes;
create or replace view v_solicitudes with (security_invoker = true) as
select s.*,
       sec.denominacion as seccion, sec.numero as seccion_numero, sec.slug as seccion_slug,
       exists (
         select 1 from padron p where p.estatus <> 'Baja' and (
           (s.curp is not null and p.curp = s.curp) or lower(p.correo) = lower(s.correo))
       ) or exists (
         select 1 from solicitudes_afiliacion o where o.id <> s.id and o.estado not in ('Dictaminada desfavorable','Desistida') and (
           (s.curp is not null and o.curp = s.curp) or lower(o.correo) = lower(s.correo))
       ) as duplicado,
       case
         when s.estado in ('Ejecutada en padrón','Dictaminada desfavorable','Desistida') then 'cerrada'
         when s.es_confianza then 'rojo'
         when exists (select 1 from padron p where p.estatus <> 'Baja' and ((s.curp is not null and p.curp = s.curp) or lower(p.correo) = lower(s.correo))) then 'rojo'
         when not s.documentos_completos then 'amarillo'
         else 'verde' end as semaforo,
       case
         when s.fecha_dictamen is null and s.estado in ('Recibida','Subsanada') and current_date > s.limite_dictamen then true
         when s.fecha_dictamen is not null and s.fecha_dictamen > s.limite_dictamen then true
         when s.estado = 'Prevenida' and current_date > s.limite_subsanacion then true
         when s.fecha_autorizacion_sg is not null and s.fecha_ejecucion_padron is null and current_date > s.limite_ejecucion then true
         when s.fecha_ejecucion_padron is not null and s.limite_ejecucion is not null and s.fecha_ejecucion_padron > s.limite_ejecucion then true
         else false end as fuera_de_plazo,
       case when s.fecha_dictamen is null and s.estado in ('Recibida','Subsanada') then s.limite_dictamen - current_date else null end as dias_para_dictamen,
       case when s.fecha_autorizacion_sg is not null and s.fecha_ejecucion_padron is null then s.limite_ejecucion - current_date else null end as dias_para_ejecutar
from solicitudes_afiliacion s
join secciones sec on sec.id = s.seccion_id;

create or replace view v_tablero with (security_invoker = true) as
with t as (
  select date_trunc('quarter', current_date)::date as ini_trim
)
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
union all select 6, 3, 'Asambleas programadas (próximos 30 días)', (select count(*) from asambleas where fecha between now() and now() + interval '30 days'), 'Preparar padrón al corte, gafetes y lista de asistencia.';
