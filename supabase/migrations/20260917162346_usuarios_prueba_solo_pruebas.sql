-- 009 · USUARIOS DE PRUEBA (temporales). NO replicar en producción: se borran cuando existan los usuarios reales.
-- Contraseña común: Sitad-Prueba-2026  (ver ENV.md). Correos ficticios en el dominio sitad.test (no reciben correo).
-- Crea el usuario en auth.users + auth.identities y su rol en usuarios_roles (el trigger vincular_usuario_rol los liga).

create or replace function crear_usuario_prueba(p_email text, p_password text, p_rol rol_usuario, p_seccion_slug text default null, p_nombre text default null)
returns uuid language plpgsql security definer set search_path = public, auth, extensions as $$
declare v_id uuid := gen_random_uuid(); v_sec uuid;
begin
  if p_seccion_slug is not null then select id into v_sec from secciones where slug = p_seccion_slug; end if;
  insert into usuarios_roles (email, rol, seccion_id, nombre) values (lower(p_email), p_rol, v_sec, p_nombre)
  on conflict (email) do update set rol = excluded.rol, seccion_id = excluded.seccion_id, nombre = excluded.nombre, activo = true;
  insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
    created_at, updated_at, confirmation_token, recovery_token, email_change, email_change_token_new, email_change_token_current, phone_change, phone_change_token, reauthentication_token, is_sso_user, is_anonymous)
  values (v_id, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', lower(p_email), extensions.crypt(p_password, extensions.gen_salt('bf')), now(),
    '{"provider":"email","providers":["email"]}'::jsonb, jsonb_build_object('nombre', p_nombre), now(), now(), '', '', '', '', '', '', '', '', false, false);
  insert into auth.identities (id, user_id, provider_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
  values (gen_random_uuid(), v_id, v_id::text, jsonb_build_object('sub', v_id::text, 'email', lower(p_email), 'email_verified', true), 'email', now(), now(), now());
  return v_id;
end $$;
revoke execute on function crear_usuario_prueba(text,text,rol_usuario,text,text) from public, anon, authenticated;

select crear_usuario_prueba('prueba.sg@sitad.test',         'Sitad-Prueba-2026', 'sg',                   null,            'PRUEBA Secretario General');
select crear_usuario_prueba('prueba.lectura@sitad.test',    'Sitad-Prueba-2026', 'cen_lectura',          null,            'PRUEBA Asuntos Jurídicos (lectura)');
select crear_usuario_prueba('prueba.jalisco@sitad.test',    'Sitad-Prueba-2026', 'seccion_organizacion', 'jalisco',       'PRUEBA Organización Sección Jalisco');
select crear_usuario_prueba('prueba.jalisco.sg@sitad.test', 'Sitad-Prueba-2026', 'seccion_sg',           'jalisco',       'PRUEBA SG Sección Jalisco');
select crear_usuario_prueba('prueba.juarez@sitad.test',     'Sitad-Prueba-2026', 'seccion_organizacion', 'ciudad-juarez', 'PRUEBA Organización Sección Ciudad Juárez');
-- Manuel de prueba con rol de Organización del CEN (su correo real queda registrado y se liga cuando entre)
select crear_usuario_prueba('prueba.cen@sitad.test',        'Sitad-Prueba-2026', 'cen_organizacion',     null,            'PRUEBA Organización del CEN');
