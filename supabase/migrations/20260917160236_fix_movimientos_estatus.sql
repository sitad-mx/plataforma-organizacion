-- 007 · Corrección: cast del estatus del cargo al actualizar el directorio desde un movimiento formalizado.
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
        estatus = (case when new.persona_entrante is null then 'Vacante' when new.tipo = 'Licencia' then 'Suplente' else 'Vigente' end)::estatus_cargo,
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
revoke execute on function movimientos_reglas() from public, anon, authenticated;
