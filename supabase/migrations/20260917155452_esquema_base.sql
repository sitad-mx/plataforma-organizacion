-- 001 · Esquema base de la Plataforma de Organización SITAD (Módulo 0)
-- Fuente: BRIEF §3 y §12 (2026-09-15), SIO v1.0 (catálogos), AF-01/AF-07.

-- ===== Catálogos (valores exactos del SIO) =====
create type situacion_seccion as enum ('En proceso','Dictamen emitido','Acuerdo del CEN','Constituida','Suspendida','Suprimida');
create type semaforo_seccion as enum ('Normal','Seguimiento','Intervención','Sin dato');
create type estatus_cargo as enum ('En proceso','Vigente','Vacante','Suplente','Concluido');
create type tipo_movimiento as enum ('Renuncia','Vacante','Sustitución','Fallecimiento','Vencimiento de periodo','Licencia','Otro');
create type estado_movimiento as enum ('Recibido','En verificación','Procedimiento en curso','Formalizado','Registros actualizados','Cerrado');
create type tipo_incidencia as enum ('Falta de comunicación','Inactividad del Comité','Renuncias múltiples','Conflicto de representación','Solicitud de información','Asunto laboral (canalizar)','Asunto disciplinario (canalizar)','Asunto electoral (canalizar)','Otro');
create type prioridad as enum ('Alta','Media','Baja');
create type competencia as enum ('Organización','Secretaría General','Secretaría del Trabajo','Actas y Acuerdos','Finanzas','Asuntos Jurídicos','Comisión Electoral','Comité de Honor y Justicia','Comité de Fiscalización','Otra Secretaría');
create type momento_asunto as enum ('Recepción','Análisis','Asignación','Intervención','Seguimiento','Cierre');
create type estado_constitucion as enum ('Diagnóstico','Dictamen elaborado','Acuerdo del CEN','Convocada','Asamblea celebrada','Cierre organizativo','Acompañamiento 90 días','Concluida','Detenida');
create type sentido_dictamen as enum ('Favorable','Desfavorable','Prevenido','Desistimiento');
create type estado_solicitud as enum ('Recibida','Prevenida','Subsanada','Dictaminada favorable','Dictaminada desfavorable','Enviada al SG','Autorizada','Ejecutada en padrón','Desistida');
create type estatus_afiliado as enum ('Activo','Suspendido','Baja');
create type causa_baja as enum ('Separación voluntaria','Terminación de la relación de trabajo','Confianza','Expulsión','Fallecimiento');
create type tipo_documento_afiliacion as enum ('identificacion_oficial_ine','curp','solicitud_afiliacion_firmada','cedula_afiliacion_anexo23','aviso_privacidad_firmado','otro');
create type rol_usuario as enum ('cen_organizacion','sg','cen_lectura','seccion_organizacion','seccion_sg');
create type tipo_asamblea as enum ('Constitutiva','Ordinaria','Extraordinaria');
create type genero as enum ('Mujer','Hombre');

-- ===== Configuración y festivos =====
create table configuracion (
  clave text primary key,
  valor text not null,
  descripcion text,
  updated_at timestamptz not null default now()
);

create table festivos (
  fecha date primary key,
  descripcion text not null
);

-- ===== Días hábiles =====
create or replace function es_habil(d date) returns boolean language sql stable as $$
  select extract(isodow from d) < 6 and not exists (select 1 from festivos f where f.fecha = d);
$$;

-- Suma n días hábiles a partir de "desde" (el día "desde" no cuenta). n=0 devuelve "desde".
create or replace function dias_habiles(desde date, n int) returns date language plpgsql stable as $$
declare d date := desde; k int := 0;
begin
  if desde is null then return null; end if;
  while k < n loop
    d := d + 1;
    if es_habil(d) then k := k + 1; end if;
  end loop;
  return d;
end $$;

-- Días hábiles transcurridos entre a (exclusivo) y b (inclusivo).
create or replace function dias_habiles_entre(a date, b date) returns int language plpgsql stable as $$
declare d date := a; k int := 0;
begin
  if a is null or b is null or b <= a then return 0; end if;
  while d < b loop
    d := d + 1;
    if es_habil(d) then k := k + 1; end if;
  end loop;
  return k;
end $$;

create or replace function set_updated_at() returns trigger language plpgsql as $$
begin new.updated_at := now(); return new; end $$;

-- ===== Usuarios y roles =====
create table usuarios_roles (
  id uuid primary key default gen_random_uuid(),
  email text not null unique,
  user_id uuid unique references auth.users(id) on delete set null,
  rol rol_usuario not null,
  seccion_id uuid,
  nombre text,
  activo boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- ===== Secciones (Registro Nacional de Estructura) =====
create table secciones (
  id uuid primary key default gen_random_uuid(),
  numero int unique,
  denominacion text not null unique,
  entidad text not null,
  slug text not null unique,
  circunscripcion text,
  situacion situacion_seccion not null default 'En proceso',
  fecha_dictamen date,
  fecha_acuerdo_cen date,
  fecha_asamblea_constitutiva date,
  periodo_ces_inicio date,
  periodo_ces_fin date generated always as (case when periodo_ces_inicio is null then null else (periodo_ces_inicio + interval '4 years')::date end) stored,
  semaforo semaforo_seccion not null default 'Sin dato',
  enlace_responsable text,
  ultimo_contacto date,
  carpeta_url text,
  notas text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid
);
alter table usuarios_roles add constraint usuarios_roles_seccion_fk foreign key (seccion_id) references secciones(id);

-- ===== Directorio de dirigentes seccionales (12 cargos por sección) =====
create table cargos_seccionales (
  id uuid primary key default gen_random_uuid(),
  seccion_id uuid not null references secciones(id) on delete cascade,
  cargo text not null,
  persona_nombre text,
  genero genero,
  estatus estatus_cargo not null default 'Vacante',
  periodo_inicio date,
  periodo_fin date,
  telefono text,
  correo text,
  documento_sustento_url text,
  contacto_validado boolean not null default true,
  fecha_actualizacion date,
  notas text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid,
  unique (seccion_id, cargo)
);

create table cargos_historial (
  id uuid primary key default gen_random_uuid(),
  cargo_id uuid not null references cargos_seccionales(id) on delete cascade,
  seccion_id uuid not null,
  cargo text not null,
  persona_nombre text,
  estatus estatus_cargo,
  periodo_inicio date,
  periodo_fin date,
  documento_sustento_url text,
  movimiento_id uuid,
  registrado_at timestamptz not null default now()
);

-- ===== Folios (consecutivos por serie) =====
create table folios (
  serie text primary key,
  ultimo int not null default 0
);

-- ===== Solicitudes de afiliación =====
create table solicitudes_afiliacion (
  id uuid primary key default gen_random_uuid(),
  folio text unique,
  seccion_id uuid not null references secciones(id),
  nombre_completo text not null,
  curp text,
  fecha_nacimiento date,
  genero genero,
  domicilio text,
  correo text not null,
  telefono text,
  empresa text not null default 'REEDCAM',
  puesto text,
  centro_trabajo text,
  fecha_inicio_relacion date,
  es_trabajador_activo boolean not null default true,
  es_confianza boolean not null default false,
  acepta_estatuto boolean not null default false,
  acepta_estatuto_at timestamptz,
  ip_captura inet,
  aviso_privacidad_at timestamptz,
  fecha_recepcion date not null default current_date,
  documentos_completos boolean not null default false,
  estado estado_solicitud not null default 'Recibida',
  fecha_prevencion date,
  limite_prevencion date,
  limite_subsanacion date,
  fecha_subsanacion date,
  limite_dictamen date,
  fecha_dictamen date,
  sentido sentido_dictamen,
  motivo_desfavorable text,
  dictamen_pdf_url text,
  fecha_envio_sg date,
  fecha_autorizacion_sg date,
  autorizacion_sg_ref text,
  autorizado_por uuid,
  limite_ejecucion date,
  fecha_ejecucion_padron date,
  afiliado_id uuid,
  trimestre_reporte text,
  expediente_url text,
  notas text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid,
  constraint curp_formato check (curp is null or curp ~ '^[A-Z]{4}[0-9]{6}[HM][A-Z]{5}[0-9A-Z][0-9]$')
);
create index on solicitudes_afiliacion (seccion_id, estado);
create index on solicitudes_afiliacion (lower(correo));
create index on solicitudes_afiliacion (curp);

create table solicitud_documentos (
  id uuid primary key default gen_random_uuid(),
  solicitud_id uuid not null references solicitudes_afiliacion(id) on delete cascade,
  tipo tipo_documento_afiliacion not null,
  archivo_url text,
  nombre_archivo text,
  validado boolean,
  observacion text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid
);
create index on solicitud_documentos (solicitud_id);

-- ===== Padrón de Afiliados (único y nacional) =====
create table padron (
  id uuid primary key default gen_random_uuid(),
  numero_afiliacion int unique,
  folio text not null unique,
  solicitud_id uuid unique references solicitudes_afiliacion(id),
  seccion_id uuid not null references secciones(id),
  nombre_completo text not null,
  curp text,
  fecha_nacimiento date,
  genero genero,
  correo text,
  telefono text,
  puesto text,
  centro_trabajo text,
  fecha_dictamen date,
  fecha_autorizacion_sg date,
  autorizacion_sg_ref text,
  fecha_alta date not null default current_date,
  estatus estatus_afiliado not null default 'Activo',
  fecha_baja date,
  causa_baja causa_baja,
  documento_baja_url text,
  constancia_url text,
  credencial_url text,
  credencial_qr_token text unique default encode(gen_random_bytes(16),'hex'),
  expediente_url text,
  notas text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid,
  constraint baja_completa check (estatus <> 'Baja' or (fecha_baja is not null and causa_baja is not null))
);
create index on padron (seccion_id, estatus);
create index on padron (curp);
alter table solicitudes_afiliacion add constraint solicitud_afiliado_fk foreign key (afiliado_id) references padron(id);

-- ===== Movimientos en cargos seccionales =====
create table movimientos (
  id uuid primary key default gen_random_uuid(),
  folio text unique,
  seccion_id uuid not null references secciones(id),
  cargo text not null,
  tipo tipo_movimiento not null,
  fecha_recepcion date not null default current_date,
  persona_saliente text,
  persona_entrante text,
  documento_sustento_url text,
  fecha_documento date,
  procedimiento_aplicado text,
  estado estado_movimiento not null default 'Recibido',
  fecha_formalizacion date,
  actas_informada boolean not null default false,
  requiere_cfcrl boolean not null default false,
  fecha_cierre date,
  notas text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid,
  constraint documento_para_avanzar check (estado = 'Recibido' or documento_sustento_url is not null)
);

-- ===== Incidencias =====
create table incidencias (
  id uuid primary key default gen_random_uuid(),
  folio text unique,
  seccion_id uuid references secciones(id),
  fecha_recepcion date not null default current_date,
  quien_plantea text,
  asunto text not null,
  tipo tipo_incidencia not null,
  prioridad prioridad not null default 'Media',
  competencia competencia not null default 'Organización',
  canalizado_a text,
  canalizado_confirmado_at timestamptz,
  responsable text,
  momento momento_asunto not null default 'Recepción',
  proxima_accion text,
  fecha_compromiso date,
  fecha_cierre date,
  resultado text,
  evidencia_url text,
  criterio_reutilizable text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid
);

create table incidencia_acciones (
  id uuid primary key default gen_random_uuid(),
  incidencia_id uuid not null references incidencias(id) on delete cascade,
  fecha date not null default current_date,
  accion text not null,
  resultado text,
  proxima_accion text,
  created_at timestamptz not null default now(),
  created_by uuid
);

-- ===== Constituciones de secciones =====
create table constituciones (
  id uuid primary key default gen_random_uuid(),
  folio text unique,
  seccion_id uuid not null references secciones(id),
  afiliados_territorio int,
  centros_trabajo text,
  responsable_expediente text,
  fecha_dictamen date,
  fecha_acuerdo_cen date,
  limite_convocatoria date,
  fecha_convocatoria date,
  fecha_asamblea date,
  estado estado_constitucion not null default 'Diagnóstico',
  dia_30 date generated always as (case when fecha_asamblea is null then null else fecha_asamblea + 30 end) stored,
  dia_60 date generated always as (case when fecha_asamblea is null then null else fecha_asamblea + 60 end) stored,
  dia_90 date generated always as (case when fecha_asamblea is null then null else fecha_asamblea + 90 end) stored,
  notas text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid
);

create table constitucion_checklist (
  id uuid primary key default gen_random_uuid(),
  constitucion_id uuid not null references constituciones(id) on delete cascade,
  formato text not null,
  orden int not null,
  item text not null,
  listo boolean not null default false,
  responsable text,
  evidencia_url text,
  updated_at timestamptz not null default now()
);

-- ===== Asambleas (módulo 3) =====
create table asambleas (
  id uuid primary key default gen_random_uuid(),
  seccion_id uuid not null references secciones(id),
  tipo tipo_asamblea not null,
  fecha timestamptz not null,
  modalidad text,
  lugar text,
  convocatoria_url text,
  constancia_publicacion_url text,
  padron_corte_at timestamptz,
  total_con_derecho int,
  asistentes int,
  quorum_alcanzado boolean,
  acta_url text,
  notas text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid
);

create table asistencias (
  id uuid primary key default gen_random_uuid(),
  asamblea_id uuid not null references asambleas(id) on delete cascade,
  afiliado_id uuid not null references padron(id),
  checkin_at timestamptz not null default now(),
  metodo text not null default 'QR',
  unique (asamblea_id, afiliado_id)
);

-- ===== Bitácora del sistema (trazabilidad) =====
create table bitacora_sistema (
  id bigint generated always as identity primary key,
  tabla text not null,
  registro_id uuid not null,
  folio text,
  campo text not null,
  valor_anterior text,
  valor_nuevo text,
  usuario_id uuid,
  usuario_email text,
  registrado_at timestamptz not null default now()
);
create index on bitacora_sistema (tabla, registro_id);

-- updated_at en todas las tablas que lo tienen
do $$ declare t text;
begin
  foreach t in array array['configuracion','usuarios_roles','secciones','cargos_seccionales','solicitudes_afiliacion','solicitud_documentos','padron','movimientos','incidencias','constituciones','constitucion_checklist','asambleas'] loop
    execute format('create trigger trg_%s_updated before update on %I for each row execute function set_updated_at()', t, t);
  end loop;
end $$;
