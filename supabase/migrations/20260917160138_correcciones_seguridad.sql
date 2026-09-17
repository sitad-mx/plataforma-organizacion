-- 006 · Corrección del alta en padrón (liga a la solicitud en AFTER INSERT) y cierre de advertencias del linter de seguridad.

-- 1) Padrón: el número consecutivo va en BEFORE; la liga a la solicitud va en AFTER (la fila ya existe)
drop trigger if exists trg_padron_reglas on padron;
create or replace function padron_reglas() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' then
    new.created_by := coalesce(new.created_by, auth.uid());
    if new.numero_afiliacion is null then new.numero_afiliacion := siguiente_folio('PADRON'); end if;
  end if;
  if tg_op = 'UPDATE' and new.estatus is distinct from old.estatus then
    if new.estatus = 'Baja' and auth.uid() is not null and mi_rol() not in ('sg','cen_organizacion') then
      raise exception 'Las bajas solo las autoriza el Secretario General y las ejecuta Organización.';
    end if;
    perform bitacora('padron', new.id, new.folio, 'estatus', old.estatus::text, new.estatus::text);
  end if;
  return new;
end $$;
create trigger trg_padron_reglas before insert or update on padron for each row execute function padron_reglas();

create or replace function padron_vincular_solicitud() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.solicitud_id is not null then
    update solicitudes_afiliacion
       set afiliado_id = new.id,
           fecha_ejecucion_padron = coalesce(fecha_ejecucion_padron, new.fecha_alta)
     where id = new.solicitud_id;
  end if;
  return null;
end $$;
create trigger trg_padron_vincular after insert on padron for each row execute function padron_vincular_solicitud();

-- 2) search_path fijo en las funciones que faltaban
alter function es_habil(date) set search_path = public;
alter function dias_habiles(date, int) set search_path = public;
alter function dias_habiles_entre(date, date) set search_path = public;
alter function set_updated_at() set search_path = public;
alter function es_cen() set search_path = public;
alter function es_org() set search_path = public;

-- 3) Funciones internas: no se exponen por la API (los triggers siguen disparando; el permiso se verifica al crearlos)
revoke execute on function set_updated_at() from public, anon, authenticated;
revoke execute on function vincular_usuario_rol() from public, anon, authenticated;
revoke execute on function siguiente_folio(text) from public, anon, authenticated;
revoke execute on function bitacora(text, uuid, text, text, text, text) from public, anon, authenticated;
revoke execute on function solicitudes_reglas() from public, anon, authenticated;
revoke execute on function solicitudes_bitacora() from public, anon, authenticated;
revoke execute on function recalcular_documentos_completos() from public, anon, authenticated;
revoke execute on function padron_reglas() from public, anon, authenticated;
revoke execute on function padron_vincular_solicitud() from public, anon, authenticated;
revoke execute on function movimientos_reglas() from public, anon, authenticated;
revoke execute on function incidencias_reglas() from public, anon, authenticated;
revoke execute on function constituciones_reglas() from public, anon, authenticated;
revoke execute on function secciones_bitacora() from public, anon, authenticated;
revoke execute on function cargos_reglas() from public, anon, authenticated;

-- Funciones de identidad y de calendario: las usan las políticas RLS (usuario autenticado); nunca anon
revoke execute on function mi_rol() from public, anon;
revoke execute on function mi_seccion() from public, anon;
revoke execute on function es_cen() from public, anon;
revoke execute on function es_org() from public, anon;
revoke execute on function es_habil(date) from public, anon;
revoke execute on function dias_habiles(date, int) from public, anon;
revoke execute on function dias_habiles_entre(date, date) from public, anon;

-- Las funciones nuevas nacen sin permiso público; se otorga expresamente cuando sean RPC
alter default privileges in schema public revoke execute on functions from public, anon;

-- Públicas a propósito (respuesta mínima): consultar_solicitud(folio, correo) y verificar_credencial(token).
