-- 012 · Autorización del SG recibida por otro medio (correo, oficio, mensaje): Organización la asienta con referencia.
-- El trigger de solicitudes sigue reservando la autorización al rol sg, salvo cuando la asienta esta función (marca de sesión).
create or replace function registrar_autorizacion_externa(p_id uuid, p_fecha date, p_ref text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not es_org() then raise exception 'Solo Organización del CEN puede asentar una autorización recibida por otro medio.'; end if;
  if p_ref is null or length(trim(p_ref)) < 5 then raise exception 'Indica la referencia de la autorización (oficio, correo o mensaje y fecha).'; end if;
  perform set_config('sitad.autorizacion_externa', '1', true);
  update solicitudes_afiliacion set fecha_autorizacion_sg = p_fecha, autorizacion_sg_ref = 'Recibida por otro medio: ' || trim(p_ref)
   where id = p_id and sentido = 'Favorable' and fecha_autorizacion_sg is null;
  if not found then raise exception 'La solicitud no está en condiciones de autorizarse (debe tener dictamen favorable y no estar autorizada).'; end if;
  perform set_config('sitad.autorizacion_externa', '', true);
end $$;
grant execute on function registrar_autorizacion_externa(uuid, date, text) to authenticated;

create or replace function solicitudes_reglas() returns trigger language plpgsql security definer set search_path = public as $$
declare v_num int; v_restantes int; v_externa boolean := coalesce(current_setting('sitad.autorizacion_externa', true), '') = '1';
begin
  if tg_op = 'INSERT' then
    new.created_by := coalesce(new.created_by, auth.uid());
    if new.folio is null then
      select numero into v_num from secciones where id = new.seccion_id;
      if v_num is null then
        raise exception 'La sección no tiene número asignado; no se puede generar el folio SITAD-[sección]-######.';
      end if;
      new.folio := format('SITAD-%s-%s', v_num, lpad(siguiente_folio('AF-' || v_num)::text, 6, '0'));
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
  if new.fecha_prevencion is not null then
    new.limite_subsanacion := dias_habiles(new.fecha_prevencion, 10);
  end if;
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
