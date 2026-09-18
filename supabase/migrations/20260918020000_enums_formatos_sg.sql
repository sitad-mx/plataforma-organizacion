-- 015 · Valores nuevos de catálogo para los formatos del SG (ORDEN DE TRABAJO 2026-09-18, paso 1).
-- Van solos en esta migración: Postgres no permite usar un valor de enum recién agregado en la misma transacción.
alter type tipo_documento_afiliacion add value if not exists 'solicitud';            -- Anexo 12 y 13 firmado (manifestación + aviso)
alter type tipo_documento_afiliacion add value if not exists 'cedula';               -- Anexo 23 firmado
alter type tipo_documento_afiliacion add value if not exists 'identificacion';       -- INE por ambos lados
alter type tipo_documento_afiliacion add value if not exists 'constancia_fiscal';    -- Constancia de Situación Fiscal (SAT)
alter type tipo_documento_afiliacion add value if not exists 'tarjeta_circulacion';  -- solo transporte
alter type tipo_documento_afiliacion add value if not exists 'poliza';               -- solo transporte
alter type tipo_documento_afiliacion add value if not exists 'licencia';             -- solo transporte
alter type rol_usuario add value if not exists 'finanzas';                           -- Secretaría de Finanzas (Módulo 5)
