-- 010 · RPC pública: lista de documentos de una solicitud (folio + correo) para la pantalla "Consultar mi trámite".
create or replace function documentos_publicos(p_folio text, p_correo text)
returns table (slug text, tipo tipo_documento_afiliacion, nombre_archivo text, validado boolean, observacion text)
language sql stable security definer set search_path = public as $$
  select sec.slug, d.tipo, d.nombre_archivo, d.validado, d.observacion
  from solicitudes_afiliacion s
  join secciones sec on sec.id = s.seccion_id
  left join solicitud_documentos d on d.solicitud_id = s.id
  where upper(trim(s.folio)) = upper(trim(p_folio)) and lower(trim(s.correo)) = lower(trim(p_correo));
$$;
grant execute on function documentos_publicos(text, text) to anon, authenticated;
