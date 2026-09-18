-- 017 · El padrón copia todos los datos de la solicitud (Anexo 12-13 y 23): faltaban domicilio, empresa e ingreso.
alter table padron
  add column if not exists domicilio text,
  add column if not exists empresa text not null default 'REEDCAM',
  add column if not exists fecha_inicio_relacion date;
drop view if exists v_pagos; drop view if exists v_padron;
create view v_padron with (security_invoker = true) as
select p.*, sec.denominacion as seccion, sec.numero as seccion_numero, sec.clave as seccion_clave, sec.slug as seccion_slug,
       sec.asamblea_fecha_hora, sec.asamblea_direccion, sec.convocatoria_url, sec.situacion as seccion_situacion
from padron p join secciones sec on sec.id = p.seccion_id;
create view v_pagos with (security_invoker = true) as
select pg.*, p.nombre_completo as afiliado_nombre, p.folio as afiliado_folio, sec.denominacion as seccion, sec.numero as seccion_numero
from pagos_cuota pg left join padron p on p.id = pg.afiliado_id left join secciones sec on sec.id = p.seccion_id;
grant select on v_padron, v_pagos to authenticated;
