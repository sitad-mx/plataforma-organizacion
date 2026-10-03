-- 134 · Asamblea Constitutiva SIN PADRÓN (indicación del Secretario General, 2/3-oct-2026)
-- En una Sección nueva no hay padrón ni corte: la Sección se constituye con las personas que acuden y se registran
-- a mano en la lista de asistencia del SG (Anexo 05). La plataforma ya no congela padrón ni registra asistencia
-- en una Constitutiva; solo imprime el Anexo 05 en blanco y registra el resultado (cuántas personas firmaron la lista).

-- 1. Candados: en una Constitutiva no se arma padrón al corte ni se registra asistencia contra un padrón.
create or replace function public.asamblea_no_constitutiva()
returns trigger language plpgsql security definer set search_path to 'public' as $$
begin
  if exists (select 1 from asambleas where id = new.asamblea_id and tipo = 'Constitutiva') then
    raise exception 'En la Asamblea Constitutiva no hay padrón (indicación del Secretario General): la asistencia se registra a mano en la lista de asistencia (Anexo 05).';
  end if;
  return new;
end $$;

drop trigger if exists trg_padron_no_constitutiva on public.asamblea_padron;
create trigger trg_padron_no_constitutiva before insert on public.asamblea_padron
  for each row execute function public.asamblea_no_constitutiva();
drop trigger if exists trg_asistencia_no_constitutiva on public.asistencias;
create trigger trg_asistencia_no_constitutiva before insert on public.asistencias
  for each row execute function public.asamblea_no_constitutiva();

-- 2. Resultado de una Constitutiva: Organización del CEN anota cuántas personas firmaron la lista y, si la hay, la liga del acta.
create or replace function public.concluir_constitutiva(p_asamblea uuid, p_registradas integer, p_acta_url text default null)
returns asambleas language plpgsql security definer set search_path to 'public' as $$
declare a asambleas;
begin
  if not es_org() then raise exception 'Solo Organización del CEN registra el resultado de una Asamblea Constitutiva.'; end if;
  if p_registradas is null or p_registradas < 0 then raise exception 'Indica cuántas personas firmaron la lista de asistencia.'; end if;
  update asambleas set estado = 'Concluida', concluida_at = now(), presentes_al_instalar = p_registradas, acta_url = coalesce(p_acta_url, acta_url)
   where id = p_asamblea and tipo = 'Constitutiva' and estado in ('En preparación', 'Convocada')
  returning * into a;
  if a.id is null then raise exception 'Solo se registra así una Asamblea Constitutiva en preparación o convocada.'; end if;
  perform bitacora('asambleas', p_asamblea, null, 'constitutiva_celebrada', null, p_registradas::text || ' personas en la lista de asistencia (Anexo 05)');
  return a;
end $$;
revoke all on function public.concluir_constitutiva(uuid, integer, text) from public, anon;
grant execute on function public.concluir_constitutiva(uuid, integer, text) to authenticated;

-- 3. Constancia en las asambleas constitutivas ya capturadas (Tijuana, Sonora, Tlaxcala). Las notas viejas se conservan.
update public.asambleas
   set notas = coalesce(notas, '') || E'\n[03-oct-2026] SIN PADRÓN NI CORTE por indicación del Secretario General: la Sección se constituye con quienes se registran en la lista de asistencia (Anexo 05). Las menciones anteriores al corte quedan sin efecto.'
 where tipo = 'Constitutiva' and estado <> 'Cancelada';
update public.asambleas
   set notas = notas || E'\n[03-oct-2026] El padrón congelado el 02-oct (34 personas) quedó sin efecto; se conserva solo como antecedente.'
 where tipo = 'Constitutiva' and corte_congelado_at is not null;
