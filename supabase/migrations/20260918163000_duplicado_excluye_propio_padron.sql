-- 021 · "Duplicado" no debe contar el registro del padrón que nació de la propia solicitud (v_solicitudes recreada con p.solicitud_id is distinct from s.id).
create or replace view v_solicitudes with (security_invoker = true) as
select s.*,
       sec.denominacion as seccion, sec.numero as seccion_numero, sec.clave as seccion_clave, sec.slug as seccion_slug,
       sec.asamblea_fecha_hora, sec.asamblea_direccion, sec.convocatoria_url,
       (s.novedad_at is not null and (s.revisado_at is null or s.novedad_at > s.revisado_at)) as con_novedad,
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
grant select on v_solicitudes to authenticated;
