-- 018 · Finanzas necesita leer el padrón (y las solicitudes) para ligar pagos y mostrar la sección en v_pagos.
drop policy if exists sel_padron_finanzas on padron;
create policy sel_padron_finanzas on padron for select to authenticated using (mi_rol() = 'finanzas');
drop policy if exists sel_solicitudes_finanzas on solicitudes_afiliacion;
create policy sel_solicitudes_finanzas on solicitudes_afiliacion for select to authenticated using (mi_rol() = 'finanzas');
