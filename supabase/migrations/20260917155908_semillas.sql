-- 004 · Semillas: configuración, festivos 2026-2027 (LFT art. 74), 27 sedes + Ciudad Juárez, 12 cargos por sección, usuario inicial.
-- Fuente: SIO v1.0 (hoja REGISTRO/DIRECTORIO), Contexto-SITAD, CAMBIOS 2026-09-15 (3).

insert into configuracion (clave, valor, descripcion) values
 ('denominacion', 'Sindicato de Trabajadores Digitales de REEDCAM (SITAD)', 'Denominación en pantallas y PDF'),
 ('denominacion_registrada', 'SINDICATO DE TRABAJADORES Y EMPLEADOS DE LA EMPRESA REEDCAM', 'Denominación para actos con efectos legales antes de la constancia del CFCRL (cotejar contra la toma de nota)'),
 ('lema', 'Por un futuro digital, al servicio de México', 'Lema institucional'),
 ('domicilio', 'C. Antonio Ancona No. 1, Interior 3, Col. Cuajimalpa, C.P. 05000, Alcaldía Cuajimalpa de Morelos, Ciudad de México', 'Domicilio del CEN'),
 ('correo_organizacion', 'sitadorganizacion@gmail.com', 'Buzón de la Secretaría de Organización (provisional hasta buzón en sindicatodigital.org)'),
 ('dominio', 'sindicatodigital.org', 'Dominio del sindicato'),
 ('clausula_pie', 'Este documento orienta. En caso de duda o diferencia prevalecen la Ley Federal del Trabajo, el Estatuto y las resoluciones válidamente emitidas por los órganos competentes.', 'Pie de todo documento generado'),
 ('plazo_prevencion_dias_habiles', '5', 'Prevención dentro de los 5 días hábiles siguientes a la recepción'),
 ('plazo_subsanacion_dias_habiles', '10', 'Días hábiles para subsanar la prevención'),
 ('plazo_dictamen_dias_habiles', '10', 'Dictamen en 10 días hábiles desde la recepción (se reanuda al subsanar)'),
 ('plazo_ejecucion_padron_dias_habiles', '2', 'Alta en el Padrón dentro de los 2 días hábiles siguientes a la autorización del SG'),
 ('plazo_convocatoria_constitutiva_dias_habiles', '30', 'Convocatoria a Asamblea Seccional Constitutiva tras el acuerdo del CEN'),
 ('plazo_relacion_trimestral_dias_habiles', '5', 'Relación trimestral de altas y bajas a Asuntos Jurídicos tras el cierre del trimestre'),
 ('cuota_porcentaje', '1', 'Cuota: 1% del salario (referencia; no la gestiona Organización)'),
 ('cuota_piso_mensual', '360', 'Piso mensual de la cuota en pesos (referencia)'),
 ('expediente_documentos_requeridos', '5', 'INE + CURP + AF-01 firmada + Anexo 23 (AF-08) + Aviso de privacidad AF-03');

insert into festivos (fecha, descripcion) values
 ('2026-01-01','Año Nuevo'), ('2026-02-02','Aniversario de la Constitución (primer lunes de febrero)'), ('2026-03-16','Natalicio de Benito Juárez (tercer lunes de marzo)'),
 ('2026-05-01','Día del Trabajo'), ('2026-09-16','Independencia'), ('2026-11-16','Revolución Mexicana (tercer lunes de noviembre)'), ('2026-12-25','Navidad'),
 ('2027-01-01','Año Nuevo'), ('2027-02-01','Aniversario de la Constitución (primer lunes de febrero)'), ('2027-03-15','Natalicio de Benito Juárez (tercer lunes de marzo)'),
 ('2027-05-01','Día del Trabajo'), ('2027-09-16','Independencia'), ('2027-11-15','Revolución Mexicana (tercer lunes de noviembre)'), ('2027-12-25','Navidad');

-- 27 sedes del SIO (presencia territorial 2026, "En proceso") + Ciudad Juárez (constituida, CAMBIOS 2026-09-15)
with sedes(orden, entidad, slug, lider) as (values
 (1,'Aguascalientes','aguascalientes','Esther Hernández'), (2,'Baja California','baja-california','Carlos Nafarrate'), (3,'Baja California Sur','baja-california-sur','Aaron Osuna'),
 (4,'Coahuila','coahuila','Ana María Kelly'), (5,'Colima','colima','Sergio Gutiérrez'), (6,'Chiapas','chiapas','Daniel Villatoro'), (7,'Chihuahua','chihuahua','Alejandro Pérez'),
 (8,'Ciudad de México','ciudad-de-mexico','Francisco Saldívar'), (9,'Durango','durango','Julián Salvador'), (10,'Guanajuato','guanajuato','Armando Ojeda'), (11,'Jalisco','jalisco','Eduardo Álvarez'),
 (12,'Estado de México','estado-de-mexico','Eduardo Cerón'), (13,'Michoacán','michoacan','José Reyes'), (14,'Morelos','morelos','Jorge Argüelles'), (15,'Nayarit','nayarit','Eugenia Lara'),
 (16,'Nuevo León','nuevo-leon','Adriana Ángeles'), (17,'Puebla','puebla','Alberto Cruz'), (18,'Querétaro','queretaro','Arturo Angulo'), (19,'Quintana Roo','quintana-roo','Salvador Hernández'),
 (20,'San Luis Potosí','san-luis-potosi','Francisco Torres'), (21,'Sinaloa','sinaloa','Fernando González'), (22,'Sonora','sonora','Eduardo López'), (23,'Tabasco','tabasco','Dulio Camacho'),
 (24,'Tamaulipas','tamaulipas','Alberto Estban'), (25,'Tlaxcala','tlaxcala','Mauricio Cruz'), (26,'Veracruz','veracruz','Renato Rosado'), (27,'Yucatán','yucatan','Juan Carlos Ortiz'))
insert into secciones (numero, denominacion, entidad, slug, situacion, semaforo, notas)
select case when entidad = 'Jalisco' then 21 else null end,
       'Sección ' || entidad, entidad, slug,
       case when entidad = 'Jalisco' then 'Constituida'::situacion_seccion else 'En proceso' end,
       'Sin dato',
       case when entidad = 'Jalisco'
            then 'Sección constituida (piloto). Número 21 según la práctica del SG (folios SITAD-21-######); confirmar. Capturar el CES electo con el acta y las fechas de asamblea y periodo. Responsable de sede reportado en 2026: ' || lider || '.'
            else 'Presencia territorial reportada en 2026; responsable de sede: ' || lider || '. Verificar contacto y afiliados.' end
from sedes order by orden;

insert into secciones (numero, denominacion, entidad, slug, circunscripcion, situacion, semaforo, notas) values
 (null, 'Sección Ciudad Juárez', 'Chihuahua', 'ciudad-juarez', 'Ciudad Juárez, Chihuahua', 'Constituida', 'Sin dato',
  'Sección constituida (piloto). NÚMERO DE SECCIÓN POR CONFIRMAR con Manuel (sin número no se generan folios). Capturar el CES electo con el acta y las fechas de asamblea y periodo.');

-- 12 cargos por sección; el responsable de sede va en Secretaría General como "En proceso" (no electo)
with cargos(orden, cargo) as (values
 (1,'Secretaría General'), (2,'Secretaría Técnica'), (3,'Secretaría de Actas y Acuerdos'), (4,'Secretaría de Organización'),
 (5,'Secretaría de Trabajo y Conflictos'), (6,'Secretaría de Previsión Social'), (7,'Secretaría de Administración y Finanzas'),
 (8,'Secretaría de Asuntos Jurídicos'), (9,'Secretaría de Expansión Digital'), (10,'Secretaría de Desarrollo Profesional'),
 (11,'Secretaría de Servicios Integrales a la Familia'), (12,'Comisión Seccional de Vigilancia (Presidencia)')),
lideres(entidad, lider) as (values
 ('Aguascalientes','Esther Hernández'), ('Baja California','Carlos Nafarrate'), ('Baja California Sur','Aaron Osuna'), ('Coahuila','Ana María Kelly'), ('Colima','Sergio Gutiérrez'),
 ('Chiapas','Daniel Villatoro'), ('Chihuahua','Alejandro Pérez'), ('Ciudad de México','Francisco Saldívar'), ('Durango','Julián Salvador'), ('Guanajuato','Armando Ojeda'),
 ('Jalisco','Eduardo Álvarez'), ('Estado de México','Eduardo Cerón'), ('Michoacán','José Reyes'), ('Morelos','Jorge Argüelles'), ('Nayarit','Eugenia Lara'), ('Nuevo León','Adriana Ángeles'),
 ('Puebla','Alberto Cruz'), ('Querétaro','Arturo Angulo'), ('Quintana Roo','Salvador Hernández'), ('San Luis Potosí','Francisco Torres'), ('Sinaloa','Fernando González'),
 ('Sonora','Eduardo López'), ('Tabasco','Dulio Camacho'), ('Tamaulipas','Alberto Estban'), ('Tlaxcala','Mauricio Cruz'), ('Veracruz','Renato Rosado'), ('Yucatán','Juan Carlos Ortiz'))
insert into cargos_seccionales (seccion_id, cargo, persona_nombre, estatus, notas)
select s.id, c.cargo,
       case when c.cargo = 'Secretaría General' and s.slug <> 'ciudad-juarez' then l.lider else null end,
       case when c.cargo = 'Secretaría General' and s.slug <> 'ciudad-juarez' then 'En proceso'::estatus_cargo else 'Vacante' end,
       case when c.cargo = 'Secretaría General' and s.slug <> 'ciudad-juarez' then 'Responsable de sede reportado en 2026 (no electo). Se sustituye por el resultado de la Asamblea Constitutiva.' else null end
from secciones s
cross join cargos c
left join lideres l on l.entidad = s.entidad and s.slug <> 'ciudad-juarez'
order by s.denominacion, c.orden;

-- Usuarios iniciales (el SG y las Secciones de Jalisco y Ciudad Juárez se agregan cuando Manuel confirme sus correos)
insert into usuarios_roles (email, rol, nombre) values
 ('menyacosta.28@gmail.com', 'cen_organizacion', 'Manuel Acosta Ruiz · Secretaría Nacional de Organización');
