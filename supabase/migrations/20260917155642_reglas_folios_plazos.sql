-- 002 · Reglas automáticas: folios, plazos estatutarios, prevención única, autorización del SG, bitácora, directorio.

-- ===== Identidad del usuario (para RLS y bitácora) =====
create or replace function mi_rol() returns rol_usuario language sql stable security definer set search_path = public as $$
  select rol from usuarios_roles where user_id = auth.uid() and activo limit 1;
$$;
create or replace function mi_seccion() returns uuid language sql stable security definer set search_path = public as $$
  select seccion_id from usuarios_roles where user_id = auth.uid() and activo limit 1;
$$;
create or replace function es_cen() returns boolean language sql stable as $$
  select mi_rol() in ('cen_organizacion','sg','cen_lectura');
$$;
create or replace function es_org() returns boolean language sql stable as $$
  select mi_rol() = 'cen_organizacion';
$$;

-- Vincular usuarios de auth con su rol por correo (al crearse el usuario)
create or replace function vincular_usuario_rol() returns trigger language plpgsql security definer set search_path = public as $$
begin
  update usuarios_roles set user_id = new.id where lower(email) = lower(new.email) and user_id is null;
  return new;
end $$;
create trigger trg_auth_users_vincular after insert on auth.users for each row execute function vincular_usuario_rol();

-- ===== Folios =====
create or replace function siguiente_folio(p_serie text) returns int language plpgsql security definer set search_path = public as $$
declare n int;
begin
  insert into folios(serie, ultimo) values (p_serie, 1)
  on conflict (serie) do update set ultimo = folios.ultimo + 1
  returning ultimo into n;
  return n;
end $$;

-- ===== Bitácora =====
create or replace function bitacora(p_tabla text, p_id uuid, p_folio text, p_campo text, p_ant text, p_nuevo text) returns void
language plpgsql security definer set search_path = public as $$
begin
  insert into bitacora_sistema(tabla, registro_id, folio, campo, valor_anterior, valor_nuevo, usuario_id, usuario_email)
  values (p_tabla, p_id, p_folio, p_campo, p_ant, p_nuevo, auth.uid(), (select email from usuarios_roles where user_id = auth.uid()));
end $$;

-- ===== Solicitudes de afiliación: folio, plazos y reglas =====
create or replace function solicitudes_reglas() returns trigger language plpgsql security definer set search_path = public as $$
declare v_num int; v_restantes int;
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
    -- Una sola prevención por solicitud (regla estatutaria)
    if old.fecha_prevencion is not null and new.fecha_prevencion is distinct from old.fecha_prevencion then
      raise exception 'Solo se permite una prevención por solicitud (folio %).', old.folio;
    end if;
    -- Solo el Secretario General autoriza; y solo toca los campos de autorización
    if new.fecha_autorizacion_sg is distinct from old.fecha_autorizacion_sg and new.fecha_autorizacion_sg is not null then
      if auth.uid() is not null and mi_rol() <> 'sg' then
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

  -- Plazos (días hábiles)
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

  -- Estados derivados de fechas (si no los puso la aplicación)
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
create trigger trg_solicitudes_reglas before insert or update on solicitudes_afiliacion for each row execute function solicitudes_reglas();

create or replace function solicitudes_bitacora() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.estado is distinct from old.estado then perform bitacora('solicitudes_afiliacion', new.id, new.folio, 'estado', old.estado::text, new.estado::text); end if;
  if new.sentido is distinct from old.sentido then perform bitacora('solicitudes_afiliacion', new.id, new.folio, 'sentido', old.sentido::text, new.sentido::text); end if;
  if new.fecha_autorizacion_sg is distinct from old.fecha_autorizacion_sg then perform bitacora('solicitudes_afiliacion', new.id, new.folio, 'fecha_autorizacion_sg', old.fecha_autorizacion_sg::text, new.fecha_autorizacion_sg::text); end if;
  return new;
end $$;
create trigger trg_solicitudes_bitacora after update on solicitudes_afiliacion for each row execute function solicitudes_bitacora();

-- Expediente completo = los 5 documentos del Paquete de Afiliación v1.0 presentes
create or replace function recalcular_documentos_completos() returns trigger language plpgsql security definer set search_path = public as $$
declare v_id uuid; v_ok boolean;
begin
  v_id := coalesce(new.solicitud_id, old.solicitud_id);
  select count(distinct tipo) filter (where tipo <> 'otro' and archivo_url is not null) = 5 into v_ok
    from solicitud_documentos where solicitud_id = v_id;
  update solicitudes_afiliacion set documentos_completos = coalesce(v_ok, false) where id = v_id;
  return null;
end $$;
create trigger trg_documentos_completos after insert or update or delete on solicitud_documentos for each row execute function recalcular_documentos_completos();

-- ===== Padrón: número de afiliación consecutivo nacional y cierre de la solicitud =====
create or replace function padron_reglas() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' then
    new.created_by := coalesce(new.created_by, auth.uid());
    if new.numero_afiliacion is null then new.numero_afiliacion := siguiente_folio('PADRON'); end if;
    if new.solicitud_id is not null then
      update solicitudes_afiliacion set afiliado_id = new.id, fecha_ejecucion_padron = coalesce(fecha_ejecucion_padron, new.fecha_alta)
      where id = new.solicitud_id;
    end if;
  end if;
  if tg_op = 'UPDATE' then
    if new.estatus is distinct from old.estatus then
      if new.estatus = 'Baja' and auth.uid() is not null and mi_rol() not in ('sg','cen_organizacion') then
        raise exception 'Las bajas solo las autoriza el Secretario General y las ejecuta Organización.';
      end if;
      perform bitacora('padron', new.id, new.folio, 'estatus', old.estatus::text, new.estatus::text);
    end if;
  end if;
  return new;
end $$;
create trigger trg_padron_reglas before insert or update on padron for each row execute function padron_reglas();

-- ===== Movimientos: folio MV-AAAA-#### y actualización del directorio =====
create or replace function movimientos_reglas() returns trigger language plpgsql security definer set search_path = public as $$
declare v_cargo cargos_seccionales%rowtype;
begin
  if tg_op = 'INSERT' then
    new.created_by := coalesce(new.created_by, auth.uid());
    if new.folio is null then
      new.folio := format('MV-%s-%s', extract(year from new.fecha_recepcion)::int, lpad(siguiente_folio('MV-' || extract(year from new.fecha_recepcion)::int)::text, 4, '0'));
    end if;
  end if;
  if tg_op = 'UPDATE' and new.estado = 'Registros actualizados' and old.estado <> 'Registros actualizados' then
    select * into v_cargo from cargos_seccionales where seccion_id = new.seccion_id and cargo = new.cargo;
    if found then
      insert into cargos_historial(cargo_id, seccion_id, cargo, persona_nombre, estatus, periodo_inicio, periodo_fin, documento_sustento_url, movimiento_id)
      values (v_cargo.id, v_cargo.seccion_id, v_cargo.cargo, v_cargo.persona_nombre, v_cargo.estatus, v_cargo.periodo_inicio, coalesce(new.fecha_formalizacion, current_date), v_cargo.documento_sustento_url, new.id);
      update cargos_seccionales set
        persona_nombre = new.persona_entrante,
        estatus = case when new.persona_entrante is null then 'Vacante' when new.tipo = 'Licencia' then 'Suplente' else 'Vigente' end,
        periodo_inicio = case when new.persona_entrante is null then null else coalesce(new.fecha_formalizacion, current_date) end,
        periodo_fin = null,
        documento_sustento_url = new.documento_sustento_url,
        fecha_actualizacion = current_date
      where id = v_cargo.id;
    end if;
    perform bitacora('movimientos', new.id, new.folio, 'estado', old.estado::text, new.estado::text);
  elsif tg_op = 'UPDATE' and new.estado is distinct from old.estado then
    perform bitacora('movimientos', new.id, new.folio, 'estado', old.estado::text, new.estado::text);
  end if;
  return new;
end $$;
create trigger trg_movimientos_reglas before insert or update on movimientos for each row execute function movimientos_reglas();

-- ===== Incidencias: folio IN-AAAA-#### =====
create or replace function incidencias_reglas() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' then
    new.created_by := coalesce(new.created_by, auth.uid());
    if new.folio is null then
      new.folio := format('IN-%s-%s', extract(year from new.fecha_recepcion)::int, lpad(siguiente_folio('IN-' || extract(year from new.fecha_recepcion)::int)::text, 4, '0'));
    end if;
  elsif new.momento is distinct from old.momento then
    perform bitacora('incidencias', new.id, new.folio, 'momento', old.momento::text, new.momento::text);
  end if;
  return new;
end $$;
create trigger trg_incidencias_reglas before insert or update on incidencias for each row execute function incidencias_reglas();

-- ===== Constituciones: folio CS-AAAA-## y plazo de convocatoria (30 días hábiles) =====
create or replace function constituciones_reglas() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' then
    new.created_by := coalesce(new.created_by, auth.uid());
    if new.folio is null then
      new.folio := format('CS-%s-%s', extract(year from current_date)::int, lpad(siguiente_folio('CS-' || extract(year from current_date)::int)::text, 2, '0'));
    end if;
  elsif new.estado is distinct from old.estado then
    perform bitacora('constituciones', new.id, new.folio, 'estado', old.estado::text, new.estado::text);
  end if;
  new.limite_convocatoria := case when new.fecha_acuerdo_cen is null then null else dias_habiles(new.fecha_acuerdo_cen, 30) end;
  return new;
end $$;
create trigger trg_constituciones_reglas before insert or update on constituciones for each row execute function constituciones_reglas();

-- ===== Secciones y cargos: bitácora de cambios de situación / estatus =====
create or replace function secciones_bitacora() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.situacion is distinct from old.situacion then perform bitacora('secciones', new.id, new.denominacion, 'situacion', old.situacion::text, new.situacion::text); end if;
  if new.semaforo is distinct from old.semaforo then perform bitacora('secciones', new.id, new.denominacion, 'semaforo', old.semaforo::text, new.semaforo::text); end if;
  return new;
end $$;
create trigger trg_secciones_bitacora after update on secciones for each row execute function secciones_bitacora();

create or replace function cargos_reglas() returns trigger language plpgsql security definer set search_path = public as $$
begin
  -- Un contacto editado por la Sección queda "pendiente de validar" hasta que el CEN lo confirme
  if tg_op = 'UPDATE' and auth.uid() is not null and mi_rol() = 'seccion_organizacion' then
    if (to_jsonb(new) - array['telefono','correo','contacto_validado','updated_at','fecha_actualizacion']) <> (to_jsonb(old) - array['telefono','correo','contacto_validado','updated_at','fecha_actualizacion']) then
      raise exception 'La Sección solo puede actualizar teléfono y correo de su directorio; los cargos se cambian con un movimiento documentado.';
    end if;
    new.contacto_validado := false;
  end if;
  if tg_op = 'UPDATE' and (new.persona_nombre is distinct from old.persona_nombre or new.estatus is distinct from old.estatus) then
    perform bitacora('cargos_seccionales', new.id, new.cargo, 'persona/estatus', concat_ws(' · ', old.persona_nombre, old.estatus::text), concat_ws(' · ', new.persona_nombre, new.estatus::text));
  end if;
  return new;
end $$;
create trigger trg_cargos_reglas before update on cargos_seccionales for each row execute function cargos_reglas();
