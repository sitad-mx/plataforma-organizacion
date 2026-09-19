-- 025 · Módulo 3 (v1): asambleas seccionales, padrón al corte, registro de asistencia (QR o búsqueda) y quórum
-- Reglas (Decisiones-clave 19-sep (2) y (3)): corte del padrón con derecho a voto = fecha de la asamblea menos tres días,
-- congelado desde el padrón adscrito; nada se agrega ni se quita después. Convocatoria con al menos 10 días hábiles
-- (Ordinaria) o 5 (Extraordinaria); 10 si hay elección. El derecho a votar lo da el padrón; el gafete lo acredita.
-- Quórum: mitad más uno de los afiliados adscritos con derecho a voto al corte (Estatuto, capítulo de la Asamblea Seccional).

do $$ begin
  if not exists (select 1 from pg_type where typname = 'tipo_asamblea') then
    create type tipo_asamblea as enum ('Constitutiva','Ordinaria','Extraordinaria');
  end if;
  if not exists (select 1 from pg_type where typname = 'estado_asamblea') then
    create type estado_asamblea as enum ('En preparación','Convocada','Instalada','Concluida','Sin quórum','Cancelada');
  end if;
end $$;

-- Las tablas asambleas/asistencias del esquema base (17-sep) estaban vacías y con otra forma: se sustituyen.
drop table if exists asistencias; drop table if exists asamblea_verificaciones; drop table if exists asamblea_padron; drop table if exists asambleas cascade;

create table asambleas (
  id uuid primary key default gen_random_uuid(),
  seccion_id uuid not null references secciones(id),
  tipo tipo_asamblea not null,
  fecha date not null,
  hora time not null default '10:00',
  hora_registro time,                                  -- apertura de la mesa de registro (por defecto una hora antes)
  lugar text,
  modalidad text not null default 'Presencial',        -- Presencial · Híbrida · Remota
  medio_remoto text,
  incluye_eleccion boolean not null default false,     -- si el orden del día incluye una elección, manda la regla electoral (10 días)
  orden_del_dia jsonb not null default '[]'::jsonb,    -- [{"asunto":"…","caracter":"Informativo|Deliberativo|Resolutivo"}]
  fecha_expedicion date,                               -- de la convocatoria
  fecha_acuerdo_comite date,                           -- acuerdo del Comité Ejecutivo Seccional para convocar (no aplica a la Constitutiva)
  convocatoria_url text,
  constancia_publicacion_url text,
  acta_url text,
  corte_fecha date generated always as (fecha - 3) stored,
  corte_congelado_at timestamptz,
  total_con_derecho int,
  quorum_requerido int,
  estado estado_asamblea not null default 'En preparación',
  instalada_at timestamptz,
  presentes_al_instalar int,
  concluida_at timestamptz,
  notas text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid default auth.uid()
);
create index if not exists asambleas_seccion_fecha on asambleas (seccion_id, fecha);
drop trigger if exists trg_asambleas_updated on asambleas;
create trigger trg_asambleas_updated before update on asambleas for each row execute function set_updated_at();

-- Padrón al corte: foto fija de las personas con derecho a voto (se congela una vez; el CEN puede volver a congelar mientras no esté instalada)
create table asamblea_padron (
  asamblea_id uuid not null references asambleas(id) on delete cascade,
  afiliado_id uuid not null references padron(id),
  numero_afiliacion int,
  folio text,
  nombre_completo text not null,
  curp text,
  credencial_qr_token text,
  primary key (asamblea_id, afiliado_id)
);

-- Asistencias: personas del padrón (con derecho a voto) y observadores (sin voz ni voto)
create table asistencias (
  id uuid primary key default gen_random_uuid(),
  asamblea_id uuid not null references asambleas(id) on delete cascade,
  afiliado_id uuid references padron(id),
  nombre text not null,
  con_derecho boolean not null default true,
  metodo text not null default 'busqueda',             -- qr · busqueda · manual
  identificacion text,                                 -- INE · Otra
  gafete boolean,
  modalidad text not null default 'P',                 -- P presencial · R remota
  incidencia text,
  motivo_observador text,
  checkin_at timestamptz not null default now(),
  registrado_por uuid default auth.uid(),
  unique (asamblea_id, afiliado_id)
);
create index if not exists asistencias_asamblea on asistencias (asamblea_id);

-- Conservación del quórum en votaciones (AS-06 parte 3)
create table asamblea_verificaciones (
  id uuid primary key default gen_random_uuid(),
  asamblea_id uuid not null references asambleas(id) on delete cascade,
  punto text not null,
  presentes int not null,
  conserva boolean not null,
  verificado_at timestamptz not null default now(),
  verificado_por uuid default auth.uid()
);

-- ===== RLS =====
alter table asambleas enable row level security;
alter table asamblea_padron enable row level security;
alter table asistencias enable row level security;
alter table asamblea_verificaciones enable row level security;

drop policy if exists sel_asambleas on asambleas;
create policy sel_asambleas on asambleas for select to authenticated using (es_cen() or es_finanzas() or seccion_id = mi_seccion());
drop policy if exists adm_asambleas on asambleas;
create policy adm_asambleas on asambleas for all to authenticated
  using (es_org() or (mi_rol() = 'seccion_organizacion' and seccion_id = mi_seccion()))
  with check (es_org() or (mi_rol() = 'seccion_organizacion' and seccion_id = mi_seccion()));

drop policy if exists sel_asamblea_padron on asamblea_padron;
create policy sel_asamblea_padron on asamblea_padron for select to authenticated
  using (exists (select 1 from asambleas a where a.id = asamblea_id and (es_cen() or a.seccion_id = mi_seccion())));
drop policy if exists sel_asistencias on asistencias;
create policy sel_asistencias on asistencias for select to authenticated
  using (exists (select 1 from asambleas a where a.id = asamblea_id and (es_cen() or a.seccion_id = mi_seccion())));
drop policy if exists sel_asamblea_verificaciones on asamblea_verificaciones;
create policy sel_asamblea_verificaciones on asamblea_verificaciones for select to authenticated
  using (exists (select 1 from asambleas a where a.id = asamblea_id and (es_cen() or a.seccion_id = mi_seccion())));
-- Las escrituras de padrón al corte, asistencias y verificaciones van por RPC (security definer)

-- ===== Reglas =====
create or replace function asamblea_puede_operar(p_asamblea uuid) returns uuid language plpgsql stable security definer set search_path = public as $$
declare v_sec uuid;
begin
  select seccion_id into v_sec from asambleas where id = p_asamblea;
  if v_sec is null then raise exception 'No existe esa asamblea.'; end if;
  if es_org() then return v_sec; end if;
  if mi_rol() in ('seccion_organizacion','seccion_sg') and mi_seccion() = v_sec then return v_sec; end if;
  raise exception 'Solo la Secretaría de Organización de la Sección u Organización del CEN operan esta asamblea.';
end $$;
revoke execute on function asamblea_puede_operar(uuid) from public, anon;

-- Anticipación de la convocatoria en días hábiles y si cumple el criterio (10 Ordinaria/Constitutiva/con elección; 5 Extraordinaria)
create or replace function asamblea_anticipacion(p_tipo tipo_asamblea, p_incluye_eleccion boolean, p_expedicion date, p_fecha date)
returns table (dias_habiles int, requeridos int, cumple boolean) language sql stable set search_path = public as $$
  select dias_habiles_entre(p_expedicion, p_fecha),
         case when p_tipo = 'Extraordinaria' and not coalesce(p_incluye_eleccion, false) then 5 else 10 end,
         p_expedicion is not null and dias_habiles_entre(p_expedicion, p_fecha) >= (case when p_tipo = 'Extraordinaria' and not coalesce(p_incluye_eleccion, false) then 5 else 10 end);
$$;
grant execute on function asamblea_anticipacion(tipo_asamblea, boolean, date, date) to authenticated;

-- Congelar el padrón al corte: personas activas del padrón adscritas a la Sección con alta en o antes del corte
create or replace function congelar_padron_asamblea(p_asamblea uuid) returns int language plpgsql security definer set search_path = public as $$
declare v_sec uuid; v_a asambleas%rowtype; n int;
begin
  v_sec := asamblea_puede_operar(p_asamblea);
  select * into v_a from asambleas where id = p_asamblea;
  if v_a.estado in ('Instalada','Concluida','Sin quórum','Cancelada') then raise exception 'La asamblea ya está %: el padrón al corte no se modifica.', v_a.estado; end if;
  if v_a.corte_congelado_at is not null and not es_org() then raise exception 'El padrón al corte ya está congelado; solo Organización del CEN puede volver a congelarlo.'; end if;
  delete from asamblea_padron where asamblea_id = p_asamblea;
  insert into asamblea_padron (asamblea_id, afiliado_id, numero_afiliacion, folio, nombre_completo, curp, credencial_qr_token)
  select p_asamblea, p.id, p.numero_afiliacion, p.folio, p.nombre_completo, p.curp, p.credencial_qr_token
  from padron p where p.seccion_id = v_sec and p.estatus = 'Activo' and p.fecha_alta <= v_a.corte_fecha;
  get diagnostics n = row_count;
  update asambleas set corte_congelado_at = now(), total_con_derecho = n, quorum_requerido = (n / 2) + 1 where id = p_asamblea;
  perform bitacora('asambleas', p_asamblea, null, 'padron_corte', null, n::text || ' con derecho a voto al ' || v_a.corte_fecha::text);
  return n;
end $$;
grant execute on function congelar_padron_asamblea(uuid) to authenticated;

-- Registrar asistencia de una persona del padrón (por QR o búsqueda). Quien está en el corte vota aunque no traiga gafete.
create or replace function registrar_asistencia(p_asamblea uuid, p_afiliado uuid, p_metodo text default 'busqueda', p_identificacion text default 'INE', p_gafete boolean default true, p_modalidad text default 'P', p_incidencia text default null)
returns asistencias language plpgsql security definer set search_path = public as $$
declare v_a asambleas%rowtype; v_p asamblea_padron%rowtype; r asistencias;
begin
  perform asamblea_puede_operar(p_asamblea);
  select * into v_a from asambleas where id = p_asamblea;
  if v_a.corte_congelado_at is null then raise exception 'Primero congela el padrón al corte.'; end if;
  if v_a.estado in ('Concluida','Sin quórum','Cancelada') then raise exception 'La asamblea ya está %.', v_a.estado; end if;
  select * into v_p from asamblea_padron where asamblea_id = p_asamblea and afiliado_id = p_afiliado;
  if not found then raise exception 'La persona no está en el padrón al corte: puede entrar como observadora, sin voz ni voto.'; end if;
  if exists (select 1 from asistencias where asamblea_id = p_asamblea and afiliado_id = p_afiliado) then raise exception 'Esa persona ya está registrada.'; end if;
  insert into asistencias (asamblea_id, afiliado_id, nombre, con_derecho, metodo, identificacion, gafete, modalidad, incidencia)
  values (p_asamblea, p_afiliado, v_p.nombre_completo, true, coalesce(p_metodo, 'busqueda'), p_identificacion, p_gafete, coalesce(p_modalidad, 'P'),
          case when coalesce(p_gafete, true) then p_incidencia else concat_ws(' · ', 'Sin gafete impreso; en el padrón e identificada: se registra y vota', p_incidencia) end)
  returning * into r;
  return r;
end $$;
grant execute on function registrar_asistencia(uuid, uuid, text, text, boolean, text, text) to authenticated;

-- Registrar por QR: el token es el de la credencial/gafete (credencial_qr_token)
create or replace function registrar_asistencia_qr(p_asamblea uuid, p_token text, p_identificacion text default 'INE')
returns asistencias language plpgsql security definer set search_path = public as $$
declare v_af uuid;
begin
  perform asamblea_puede_operar(p_asamblea);
  select afiliado_id into v_af from asamblea_padron where asamblea_id = p_asamblea and credencial_qr_token = p_token;
  if v_af is null then raise exception 'Ese código no corresponde a una persona del padrón al corte de esta asamblea.'; end if;
  return registrar_asistencia(p_asamblea, v_af, 'qr', p_identificacion, true, 'P', null);
end $$;
grant execute on function registrar_asistencia_qr(uuid, text, text) to authenticated;

create or replace function registrar_observador(p_asamblea uuid, p_nombre text, p_motivo text default null)
returns asistencias language plpgsql security definer set search_path = public as $$
declare r asistencias;
begin
  perform asamblea_puede_operar(p_asamblea);
  insert into asistencias (asamblea_id, afiliado_id, nombre, con_derecho, metodo, motivo_observador) values (p_asamblea, null, trim(p_nombre), false, 'manual', p_motivo) returning * into r;
  return r;
end $$;
grant execute on function registrar_observador(uuid, text, text) to authenticated;

create or replace function quitar_asistencia(p_asistencia uuid) returns void language plpgsql security definer set search_path = public as $$
declare v_a uuid;
begin
  select asamblea_id into v_a from asistencias where id = p_asistencia;
  perform asamblea_puede_operar(v_a);
  delete from asistencias where id = p_asistencia;
end $$;
grant execute on function quitar_asistencia(uuid) to authenticated;

-- Cómputo de quórum en vivo
create or replace function computo_quorum(p_asamblea uuid)
returns table (total_con_derecho int, quorum_requerido int, presentes int, remotos int, observadores int, hay_quorum boolean)
language sql stable security definer set search_path = public as $$
  select a.total_con_derecho, a.quorum_requerido,
         (select count(*)::int from asistencias s where s.asamblea_id = a.id and s.con_derecho),
         (select count(*)::int from asistencias s where s.asamblea_id = a.id and s.con_derecho and s.modalidad = 'R'),
         (select count(*)::int from asistencias s where s.asamblea_id = a.id and not s.con_derecho),
         a.quorum_requerido is not null and (select count(*) from asistencias s where s.asamblea_id = a.id and s.con_derecho) >= a.quorum_requerido
  from asambleas a where a.id = p_asamblea and (es_cen() or es_finanzas() or a.seccion_id = mi_seccion());
$$;
grant execute on function computo_quorum(uuid) to authenticated;

-- Instalar (informe al Secretario General Seccional): solo con quórum. Sin quórum, queda constancia.
create or replace function instalar_asamblea(p_asamblea uuid) returns asambleas language plpgsql security definer set search_path = public as $$
declare q record; a asambleas;
begin
  perform asamblea_puede_operar(p_asamblea);
  select * into q from computo_quorum(p_asamblea);
  if q.quorum_requerido is null then raise exception 'Primero congela el padrón al corte.'; end if;
  if q.hay_quorum then
    update asambleas set estado = 'Instalada', instalada_at = now(), presentes_al_instalar = q.presentes where id = p_asamblea returning * into a;
    perform bitacora('asambleas', p_asamblea, null, 'instalada', null, q.presentes::text || ' de ' || q.total_con_derecho::text);
  else
    update asambleas set estado = 'Sin quórum', presentes_al_instalar = q.presentes where id = p_asamblea returning * into a;
    perform bitacora('asambleas', p_asamblea, null, 'sin_quorum', null, q.presentes::text || ' de ' || q.total_con_derecho::text || ' (requeridos ' || q.quorum_requerido::text || ')');
  end if;
  return a;
end $$;
grant execute on function instalar_asamblea(uuid) to authenticated;

create or replace function verificar_quorum(p_asamblea uuid, p_punto text) returns asamblea_verificaciones language plpgsql security definer set search_path = public as $$
declare q record; r asamblea_verificaciones;
begin
  perform asamblea_puede_operar(p_asamblea);
  select * into q from computo_quorum(p_asamblea);
  insert into asamblea_verificaciones (asamblea_id, punto, presentes, conserva) values (p_asamblea, trim(p_punto), q.presentes, q.hay_quorum) returning * into r;
  return r;
end $$;
grant execute on function verificar_quorum(uuid, text) to authenticated;

create or replace function concluir_asamblea(p_asamblea uuid, p_acta_url text default null) returns asambleas language plpgsql security definer set search_path = public as $$
declare a asambleas;
begin
  perform asamblea_puede_operar(p_asamblea);
  update asambleas set estado = 'Concluida', concluida_at = now(), acta_url = coalesce(p_acta_url, acta_url) where id = p_asamblea and estado = 'Instalada' returning * into a;
  if a.id is null then raise exception 'Solo se concluye una asamblea instalada.'; end if;
  perform bitacora('asambleas', p_asamblea, null, 'concluida', null, null);
  return a;
end $$;
grant execute on function concluir_asamblea(uuid, text) to authenticated;

-- ===== Vista =====
drop view if exists v_asambleas;
create view v_asambleas with (security_invoker = true) as
select a.*, sec.denominacion as seccion, sec.numero as seccion_numero, sec.slug as seccion_slug, sec.clave as seccion_clave,
       (select count(*)::int from asistencias s where s.asamblea_id = a.id and s.con_derecho) as presentes,
       (select count(*)::int from asistencias s where s.asamblea_id = a.id and not s.con_derecho) as observadores,
       (select count(*)::int from padron p where p.seccion_id = a.seccion_id and p.estatus = 'Activo' and p.fecha_alta <= a.corte_fecha) as con_derecho_hoy,
       dias_habiles_entre(a.fecha_expedicion, a.fecha) as anticipacion_habiles,
       case when a.tipo = 'Extraordinaria' and not a.incluye_eleccion then 5 else 10 end as anticipacion_requerida,
       a.fecha_expedicion is not null and dias_habiles_entre(a.fecha_expedicion, a.fecha) >= (case when a.tipo = 'Extraordinaria' and not a.incluye_eleccion then 5 else 10 end) as anticipacion_cumple,
       a.corte_fecha <= current_date as corte_vencido
from asambleas a join secciones sec on sec.id = a.seccion_id;
grant select on v_asambleas to authenticated;

-- ===== Semilla real: Asamblea Seccional Constitutiva de la Sección 35 (Tlaxcala), 10-oct-2026 10:30 (acuerdo del CEN 11-sep-2026) =====
insert into asambleas (seccion_id, tipo, fecha, hora, hora_registro, lugar, modalidad, incluye_eleccion, estado, orden_del_dia, notas)
select s.id, 'Constitutiva', '2026-10-10', '10:30', '09:30', coalesce(s.asamblea_direccion, ''), 'Presencial', true, 'Convocada',
       '[{"asunto":"Registro de asistencia y verificación del quórum","caracter":"Informativo"},{"asunto":"Declaratoria de instalación","caracter":"Informativo"},{"asunto":"Elección de la Mesa de Debates","caracter":"Resolutivo"},{"asunto":"Lectura del acuerdo del Comité Ejecutivo Nacional que crea la Sección","caracter":"Informativo"},{"asunto":"Conocimiento y protesta de los Documentos Básicos","caracter":"Informativo"},{"asunto":"Designación de la Comisión Electoral","caracter":"Resolutivo"},{"asunto":"Registro de planillas y elección del Comité Ejecutivo Seccional y de la Comisión Seccional de Vigilancia","caracter":"Resolutivo"},{"asunto":"Toma de protesta","caracter":"Informativo"},{"asunto":"Lectura y firma del acta · Clausura","caracter":"Resolutivo"}]'::jsonb,
       'Convocatoria del SG (Anexo 01) ya publicada; corte del padrón: 7 de octubre de 2026.'
from secciones s where s.slug = 'tlaxcala' and not exists (select 1 from asambleas a where a.seccion_id = s.id and a.fecha = '2026-10-10');
