-- 020 · La regla "el SG solo autoriza" ignoraba los campos que el propio sistema recalcula en esa misma transacción
--       (alta automática → afiliado_id, fecha_ejecucion_padron, trimestre; novedades). Se amplía la lista de columnas toleradas.
create or replace function solicitudes_reglas() returns trigger language plpgsql security definer set search_path = public as $$
declare v_sec secciones%rowtype; v_serie text; v_restantes int; v_externa boolean := coalesce(current_setting('sitad.autorizacion_externa', true), '') = '1';
  v_tolerados text[] := array['fecha_autorizacion_sg','autorizacion_sg_ref','autorizado_por','estado','limite_ejecucion','updated_at','notas','fecha_envio_sg',
                              'afiliado_id','fecha_ejecucion_padron','trimestre_reporte','documentos_completos','novedad_at','revisado_at','limite_dictamen','limite_prevencion','limite_subsanacion'];
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
      if (to_jsonb(new) - v_tolerados) <> (to_jsonb(old) - v_tolerados) then
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
-- El padrón se crea desde un trigger con el usuario del SG: la política de insert del padrón exige Organización.
-- alta_automatica es security definer, pero RLS se evalúa con el rol de sesión: se permite el insert cuando lo hace el propio sistema.
drop policy if exists ins_padron_sistema on padron;
create policy ins_padron_sistema on padron for insert to authenticated with check (coalesce(current_setting('sitad.alta_automatica', true), '') = '1');
create or replace function alta_automatica() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.estado = 'Autorizada' and old.estado is distinct from 'Autorizada' and new.sentido = 'Favorable'
     and not exists (select 1 from padron p where p.solicitud_id = new.id) then
    perform set_config('sitad.alta_automatica', '1', true);
    insert into padron (folio, solicitud_id, seccion_id, tipo_movimiento, nombre_completo, curp, rfc, fecha_nacimiento, estado_civil, genero, domicilio, colonia, cp, municipio, estado_domicilio,
      correo, telefono, nss, unidad_medica, unidad_medica_ciudad, escolaridad, escolaridad_estado, carrera, puesto, empresa, fecha_inicio_relacion, domicilio_fiscal, frecuencia_pago, telefono_empresa, jefe_laboral,
      seguro_aseguradora, seguro_poliza, seguro_vigencia, conyuge_nombre, conyuge_domicilio, conyuge_telefono, dependientes, identificacion_tipo, patron, actividad_transporte, ciudad_firma, centro_trabajo,
      fecha_dictamen, fecha_autorizacion_sg, autorizacion_sg_ref, expediente_url, fecha_alta)
    values (new.folio, new.id, new.seccion_id, new.tipo_movimiento, new.nombre_completo, new.curp, new.rfc, new.fecha_nacimiento, new.estado_civil, new.genero, new.domicilio, new.colonia, new.cp, new.municipio, new.estado_domicilio,
      new.correo, new.telefono, new.nss, new.unidad_medica, new.unidad_medica_ciudad, new.escolaridad, new.escolaridad_estado, new.carrera, new.puesto, new.empresa, new.fecha_inicio_relacion, new.domicilio_fiscal, new.frecuencia_pago, new.telefono_empresa, new.jefe_laboral,
      new.seguro_aseguradora, new.seguro_poliza, new.seguro_vigencia, new.conyuge_nombre, new.conyuge_domicilio, new.conyuge_telefono, new.dependientes, new.identificacion_tipo, new.patron, new.actividad_transporte, new.ciudad_firma, new.centro_trabajo,
      new.fecha_dictamen, new.fecha_autorizacion_sg, new.autorizacion_sg_ref, new.expediente_url, current_date);
    perform set_config('sitad.alta_automatica', '', true);
  end if;
  return null;
end $$;
revoke execute on function alta_automatica() from public, anon, authenticated;
-- La liga solicitud→padrón (padron_vincular_solicitud) actualiza la solicitud con el usuario del SG: permitido por la política upd_solicitudes (sg) y tolerado arriba.
