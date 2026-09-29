// Módulo compartido de la Plataforma de Organización SITAD
import { createClient } from 'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/+esm';
import * as CFG from './config.js';

export const sb = createClient(CFG.SUPABASE_URL, CFG.SUPABASE_KEY);
export const ROOT = new URL('../', import.meta.url).href; // raíz del sitio (funciona en GitHub Pages y en local)
export { CFG };

// ===== Utilidades de DOM =====
export const $ = (sel, raiz = document) => raiz.querySelector(sel);
export const $$ = (sel, raiz = document) => Array.from(raiz.querySelectorAll(sel));
export function esc(s) { return String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c])); }
export function toast(msg, tipo = '') {
  let caja = $('#avisos'); if (!caja) { caja = document.createElement('div'); caja.id = 'avisos'; document.body.appendChild(caja); }
  const t = document.createElement('div'); t.className = 'toast ' + tipo; t.textContent = msg; caja.appendChild(t);
  setTimeout(() => t.remove(), tipo === 'error' ? 9000 : 5000);
}
export function ocupado(btn, si, texto) {
  if (!btn) return; btn.disabled = si; if (si) { btn.dataset.txt = btn.textContent; btn.textContent = texto || 'Un momento…'; } else if (btn.dataset.txt) btn.textContent = btn.dataset.txt;
}
export function param(n) { return new URLSearchParams(location.search).get(n); }

// ===== Fechas =====
const MESES = ['enero','febrero','marzo','abril','mayo','junio','julio','agosto','septiembre','octubre','noviembre','diciembre'];
export function fecha(d) { if (!d) return '—'; const [a, m, dd] = String(d).slice(0, 10).split('-'); return `${dd}/${m}/${a}`; }
export function fechaLarga(d) { if (!d) return '—'; const [a, m, dd] = String(d).slice(0, 10).split('-'); return `${parseInt(dd)} de ${MESES[parseInt(m) - 1]} de ${a}`; }
// Fecha local (no UTC): en México la noche del 17 sigue siendo 17 aunque en UTC ya sea 18.
export function hoy() { const d = new Date(); return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`; }
export function diasDesde(d) { if (!d) return null; return Math.round((new Date(hoy()) - new Date(d.slice(0, 10))) / 86400000); }

// ===== Catálogos de pantalla =====
// Expediente según AF-02 v1.1 (formatos del SG, 18-sep-2026): cinco documentos; tres más si la actividad es transporte.
// Cada documento trae sus instrucciones para la persona (se muestran al subirlo). Reglas de Manuel (18-sep): firmas con tinta azul, igual que en la INE; fotos legibles, sin reflejos ni sombras.
export const REGLAS_FOTO = 'Foto o escaneo completo y legible: sin recortes, sin reflejos de luz, sin sombras que tapen datos, sin dedos encima.';
export const REGLAS_FIRMA = 'Firma de puño y letra con TINTA AZUL, igual que la firma de tu INE. No se aceptan firmas insertadas como imagen ni tachaduras.';
export const DOCS = [
  { tipo: 'solicitud', nombre: 'Solicitud de afiliación firmada (Anexo 12 y 13)', corto: 'Solicitud (Anexo 12-13)', firma: true, generado: true,
    pasos: ['Descarga el PDF: ya viene lleno con tus datos.', 'Imprímelo (4 hojas).', 'Fírmalo con tinta azul en DOS lugares: al final de la manifestación (hoja 3) y al final del aviso de privacidad (hoja 4).', 'Toma foto de las 4 hojas o escanéalas en un solo PDF y súbelo aquí.'],
    ayuda: 'El sistema te lo entrega prellenado. Lleva dos firmas: manifestación y aviso de privacidad.' },
  { tipo: 'cedula', nombre: 'Cédula de afiliación firmada (Anexo 23)', corto: 'Cédula (Anexo 23)', firma: true, generado: true,
    pasos: ['Descarga el PDF: ya viene lleno con todos tus datos.', 'Imprímelo (2 hojas). Revisa que ningún dato esté vacío o equivocado.', 'Fírmalo con tinta azul al final de la hoja 2.', 'Toma foto de las 2 hojas o escanéalas y súbelo aquí.'],
    ayuda: 'El sistema te la entrega prellenada. Todos los campos son obligatorios.' },
  { tipo: 'identificacion', nombre: 'Identificación oficial vigente (credencial para votar INE)', corto: 'INE', partes: [['frente', 'Frente de la INE'], ['reverso', 'Reverso de la INE']],
    pasos: ['Toma una foto del FRENTE, completa y derecha.', 'Toma otra foto del REVERSO.', 'Revisa que se lea tu nombre, tu foto y la vigencia.'],
    ayuda: 'Debe estar vigente. El nombre debe coincidir con el de tu solicitud.' },
  { tipo: 'curp', nombre: 'Constancia de la CURP', corto: 'CURP',
    pasos: ['Descárgala en gob.mx/curp (es gratis) o toma foto de la impresa.', 'Súbela completa.'],
    ayuda: 'Constancia oficial; el nombre y la fecha de nacimiento deben coincidir con tu INE.' },
  { tipo: 'constancia_fiscal', nombre: 'Constancia de Situación Fiscal (SAT)', corto: 'Constancia fiscal',
    pasos: ['Descárgala del portal del SAT (sat.gob.mx, con tu RFC y contraseña o e.firma) o pídela en tu módulo del SAT.', 'Sube el PDF completo o foto de todas sus hojas.'],
    ayuda: 'Reciente, con tu RFC completo. Se usa para la emisión de tus recibos.' },
];
export const DOCS_TRANSPORTE = [
  { tipo: 'tarjeta_circulacion', nombre: 'Tarjeta de circulación del vehículo', corto: 'Tarjeta de circulación', pasos: ['Foto de la tarjeta completa, por el lado de los datos.'], ayuda: 'Solo transporte de pasajeros o última milla.' },
  { tipo: 'poliza', nombre: 'Póliza de seguro del vehículo', corto: 'Póliza de seguro', pasos: ['Foto o PDF de la carátula de la póliza vigente (número, vigencia y aseguradora).'], ayuda: 'Solo transporte.' },
  { tipo: 'licencia', nombre: 'Licencia de manejo vigente', corto: 'Licencia de manejo', pasos: ['Foto del frente de la licencia, completa y legible.'], ayuda: 'Solo transporte.' },
];
export function docsRequeridos(transporte) { return transporte ? [...DOCS, ...DOCS_TRANSPORTE] : DOCS; }
const TODOS_DOCS = [...DOCS, ...DOCS_TRANSPORTE, { tipo: 'otro', nombre: 'Otro documento', corto: 'Otro' },
  // tipos históricos (antes del 18-sep-2026), por si quedara alguno
  { tipo: 'identificacion_oficial_ine', nombre: 'Identificación oficial (INE)', corto: 'INE' }, { tipo: 'solicitud_afiliacion_firmada', nombre: 'Solicitud AF-01 firmada', corto: 'Solicitud' }, { tipo: 'cedula_afiliacion_anexo23', nombre: 'Cédula Anexo 23', corto: 'Cédula' }, { tipo: 'aviso_privacidad_firmado', nombre: 'Aviso de privacidad firmado', corto: 'Aviso' }];
export const DOC_NOMBRE = Object.fromEntries(TODOS_DOCS.map(d => [d.tipo, d.nombre]));
export const DOC_CORTO = Object.fromEntries(TODOS_DOCS.map(d => [d.tipo, d.corto]));
export const ESTADOS_MX = ['Aguascalientes','Baja California','Baja California Sur','Campeche','Chiapas','Chihuahua','Ciudad de México','Coahuila','Colima','Durango','Estado de México','Guanajuato','Guerrero','Hidalgo','Jalisco','Michoacán','Morelos','Nayarit','Nuevo León','Oaxaca','Puebla','Querétaro','Quintana Roo','San Luis Potosí','Sinaloa','Sonora','Tabasco','Tamaulipas','Tlaxcala','Veracruz','Yucatán','Zacatecas'];
export const ESTADO_INFO = {
  'Recibida': { etiqueta: 'azul', persona: 'Tu solicitud fue recibida y está en revisión.' },
  'Prevenida': { etiqueta: 'amarillo', persona: 'Falta algo en tu expediente. Revisa la lista y sube lo que se indica antes de la fecha límite.' },
  'Subsanada': { etiqueta: 'azul', persona: 'Recibimos lo que faltaba. La revisión continúa.' },
  'Dictaminada favorable': { etiqueta: 'verde', persona: 'Tu solicitud fue dictaminada favorable; tu alta en el Padrón está en proceso.' },
  'Dictaminada desfavorable': { etiqueta: 'rojo', persona: 'Tu solicitud fue dictaminada desfavorable. Revisa el motivo en el correo que recibiste; puedes presentar una nueva solicitud cuando reúnas el requisito.' },
  'Enviada al SG': { etiqueta: 'verde', persona: 'Tu solicitud fue dictaminada favorable; tu alta en el Padrón está en proceso.' },
  'Autorizada': { etiqueta: 'verde', persona: 'Tu solicitud fue aceptada. En breve quedarás registrado(a) en el Padrón.' },
  'Ejecutada en padrón': { etiqueta: 'verde', persona: 'Ya formas parte del Sindicato. Tu alta en el Padrón está registrada.' },
  'Desistida': { etiqueta: 'carbon', persona: 'La solicitud quedó sin efectos por desistimiento.' },
};
export const SEMAFORO_TXT = { verde: 'Lista para dictamen', amarillo: 'Expediente incompleto', rojo: 'Revisar: misma CURP que un afiliado, o confianza', cerrada: 'Concluida' };
export const ROL_NOMBRE = { cen_organizacion: 'Organización del CEN', sg: 'Secretario General', cen_lectura: 'CEN (lectura)', seccion_organizacion: 'Organización de Sección', seccion_sg: 'Secretaría General de Sección', finanzas: 'Secretaría de Finanzas' };
export function fechaHoraLarga(ts) { if (!ts) return '—'; const d = new Date(ts); const f = new Intl.DateTimeFormat('es-MX', { timeZone: 'America/Mexico_City', day: 'numeric', month: 'long', year: 'numeric' }).format(d); const h = new Intl.DateTimeFormat('es-MX', { timeZone: 'America/Mexico_City', hour: '2-digit', minute: '2-digit', hour12: false }).format(d); return `${f} a las ${h} horas`; }
export function dinero(n) { return new Intl.NumberFormat('es-MX', { style: 'currency', currency: 'MXN' }).format(Number(n || 0)); }

// ===== Sesión y perfil =====
let _perfil = null;
export async function perfil(forzar = false) {
  if (_perfil && !forzar) return _perfil;
  const { data: { session } } = await sb.auth.getSession();
  if (!session) return (_perfil = null);
  const { data } = await sb.from('usuarios_roles').select('id, email, rol, seccion_id, nombre, secciones(denominacion, slug, numero)').eq('user_id', session.user.id).eq('activo', true).maybeSingle();
  _perfil = data ? { ...data, user: session.user } : { email: session.user.email, rol: null, user: session.user };
  return _perfil;
}
export async function requerirRol(roles) {
  const p = await perfil();
  if (!p) { location.href = ROOT + 'entrar/?ir=' + encodeURIComponent(location.pathname + location.search); return null; }
  if (!p.rol || (roles && !roles.includes(p.rol))) {
    document.body.innerHTML = `<div class="contenido angosto"><div class="tarjeta"><h2>Sin acceso</h2><p>Tu usuario (${esc(p.email)}) no tiene permiso para esta sección${p.rol ? ' (rol: ' + esc(ROL_NOMBRE[p.rol]) + ')' : ' (sin rol asignado)'}. Escribe a la Secretaría de Organización: ${CFG.CORREO_ORGANIZACION}.</p><p><a class="btn secundario" href="${ROOT}">Ir al inicio</a> <button class="btn discreto" id="salir">Cerrar sesión</button></p></div></div>`;
    $('#salir').onclick = salir; return null;
  }
  return p;
}
export function destinoPorRol(rol) {
  if (rol === 'sg') return ROOT + 'sg/';
  if (rol === 'finanzas') return ROOT + 'finanzas/';
  if (rol === 'cen_organizacion' || rol === 'cen_lectura') return ROOT + 'cen/';
  if (rol === 'seccion_organizacion' || rol === 'seccion_sg') return ROOT + 'seccion/';
  return ROOT;
}
export async function salir() { await sb.auth.signOut(); _perfil = null; location.href = ROOT; }

// ===== Cabecera y pie =====
export async function armazon({ titulo = '', nav = [], activa = '' } = {}) {
  const p = await perfil();
  if (p && p.rol && !nav.length) {
    if (['cen_organizacion', 'cen_lectura', 'sg', 'finanzas'].includes(p.rol)) nav = [{ href: ROOT + 'cen/', texto: 'Bandeja', id: 'cen' }, { href: ROOT + 'sg/', texto: 'Autorizaciones', id: 'sg' }, { href: ROOT + 'finanzas/', texto: 'Finanzas', id: 'finanzas' }];
  } else if (p && ['cen_organizacion', 'cen_lectura', 'sg', 'finanzas'].includes(p.rol) && !nav.some(n => n.id === 'finanzas')) nav = [...nav, { href: ROOT + 'finanzas/', texto: 'Finanzas', id: 'finanzas' }];
  const enlaces = nav.map(n => `<a href="${n.href}" class="${n.id === activa ? 'activa' : ''}">${esc(n.texto)}</a>`).join('');
  const usuario = p ? `<span class="usuario">${esc(p.nombre || p.email)}${p.secciones ? ' · ' + esc(p.secciones.denominacion) : ''} · <a href="${ROOT}cuenta/" title="Cambiar contraseña">Mi cuenta</a> · <a href="#" id="salir-enlace">Salir</a></span>` : `<a href="${ROOT}entrar/">Entrar</a>`;
  const cab = $('#cabecera') || document.body.insertAdjacentElement('afterbegin', Object.assign(document.createElement('header'), { id: 'cabecera' }));
  cab.className = 'cabecera';
  cab.innerHTML = `<div class="interior"><a class="marca" href="${ROOT}"><img src="${ROOT}assets/sitad-mark.png" alt="SITAD"><div><b>${CFG.SINDICATO_CORTO}</b><span>${titulo || 'Secretaría de Organización'}</span></div></a><nav>${enlaces}${usuario}</nav></div>`;
  const s = $('#salir-enlace'); if (s) s.onclick = e => { e.preventDefault(); salir(); };
  let pie = $('#pie'); if (!pie) { pie = document.createElement('footer'); pie.id = 'pie'; document.body.appendChild(pie); }
  pie.className = 'pie';
  pie.innerHTML = `<div class="lema">${CFG.LEMA}</div><div>${CFG.SINDICATO} · ${CFG.SECRETARIA}</div><div>${CFG.DOMICILIO}</div><div class="mt-1">${CFG.CLAUSULA_PIE}</div>`;
  if (typeof document.fonts !== 'undefined') { /* fuente cargada vía <link> en cada página */ }
  return p;
}

// ===== Archivos (buzón de expedientes en Storage) =====
export function extension(nombre) { const m = /\.([a-z0-9]+)$/i.exec(nombre || ''); return m ? m[1].toLowerCase() : 'pdf'; }
export async function subirArchivo(ruta, archivo) {
  const { error } = await sb.storage.from('expedientes').upload(ruta, archivo, { upsert: false, contentType: archivo.type || undefined });
  if (error) throw error; return ruta;
}
export async function urlFirmada(ruta, seg = 600) {
  if (!ruta) return null; if (/^https?:/.test(ruta)) return ruta;
  const { data, error } = await sb.storage.from('expedientes').createSignedUrl(ruta, seg);
  if (error) throw error; return data.signedUrl;
}
export function validarArchivo(f) {
  if (!f) return 'Selecciona un archivo.';
  if (f.size > 5 * 1024 * 1024) return 'El archivo pesa más de 5 MB. Redúcelo o toma una foto más ligera.';
  if (!['application/pdf', 'image/jpeg', 'image/png'].includes(f.type)) return 'Solo se aceptan PDF, JPG o PNG.';
  return null;
}
export function rutaDocumento(slug, folio, tipo, nombre) { return `solicitudes/${slug}/${folio}/${tipo}.${extension(nombre)}`; }

// ===== Correos (textos oficiales AF-04) =====
// Desde el 28-sep-2026 los correos salen del propio buzón enlace@ (Outlook de Manuel): ya no se pone en copia a sí mismo.
// Aire en los correos (petición de Manuel 28-sep): cada liga va sola en su renglón, con línea en blanco antes y después y sin puntuación pegada,
// para que Outlook la reconozca como liga y la persona no tenga que copiarla; los párrafos quedan separados por línea en blanco.
export function airear(texto) {
  return String(texto || '')
    .replace(/[ \t]*(https?:\/\/[^\s]+?)[.,;:)\]]*(?=\s|$)/g, (m, u) => '\n' + u + '\n')
    .replace(/\n(https?:\/\/[^\n]+)\n/g, '\n\n$1\n\n')
    .replace(/[ \t]+\n/g, '\n').replace(/\n{3,}/g, '\n\n').trim();
}
// El mismo texto como HTML (párrafos con espacio y ligas clicables), para pegarlo en Outlook con "Copiar con formato"
export function textoAHtml(texto) {
  const e = s => s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
  // Los puntos de lo que falta (PRIMERO., SEGUNDO., … o "1." "2.") van en negritas para que se distingan (petición de Manuel 28-sep)
  const esPunto = par => /^((PRIMERO|SEGUNDO|TERCERO|CUARTO|QUINTO|SEXTO|SÉPTIMO|OCTAVO|NOVENO|DÉCIMO)\.|\d+\.)\s/.test(par);
  return airear(texto).split(/\n{2,}/).map(par => {
    const cuerpo = e(par).replace(/\n/g, '<br>').replace(/(https?:\/\/[^\s<]+)/g, '<a href="$1">$1</a>');
    return '<p style="margin:0 0 14px;font-family:Arial,sans-serif;font-size:11pt;line-height:1.45">' + (esPunto(par) ? '<b>' + cuerpo + '</b>' : cuerpo) + '</p>';
  }).join('');
}
export async function copiarHtml(texto) {
  const html = textoAHtml(texto), plano = airear(texto);
  if (navigator.clipboard && window.ClipboardItem) await navigator.clipboard.write([new ClipboardItem({ 'text/html': new Blob([html], { type: 'text/html' }), 'text/plain': new Blob([plano], { type: 'text/plain' }) })]);
  else await navigator.clipboard.writeText(plano);
}
export function mailto(para, asunto, cuerpo, cc = '') {
  const q = new URLSearchParams(); if (cc) q.set('cc', cc); q.set('subject', asunto); q.set('body', airear(cuerpo));
  return `mailto:${para}?${q.toString().replace(/\+/g, '%20')}`;
}
const FIRMA = `Secretaría de Organización · Comité Ejecutivo Nacional · ${CFG.SINDICATO}`;
const LIGA_DOCS = CFG.LIGA_DOCUMENTOS_BASICOS || '[liga a los Documentos Básicos]';
export function correoAcuse(s) {
  const nombre = s.nombre_completo.split(' ')[0];
  return { asunto: `SITAD · Solicitud de afiliación recibida · Folio ${s.folio} · ${s.nombre_completo}`,
    cuerpo: `Hola, ${nombre}:\n\nLa Secretaría de Organización del ${CFG.SINDICATO} recibió tu solicitud de afiliación el ${fechaLarga(s.fecha_recepcion)}. Tu folio es ${s.folio}; consérvalo para cualquier consulta.\n\nA partir de hoy la Secretaría revisa tu expediente. Recibirás respuesta en un plazo máximo de diez días hábiles. Si faltara algún documento te lo haremos saber por este medio, una sola vez, con la lista exacta de lo que se necesita.\n\nPuedes consultar el avance con tu folio y tu correo en: ${ROOT}estado/\n\nMientras tanto puedes conocer los Documentos Básicos del Sindicato (Declaración de Principios, Programa de Acción y Estatuto) en: ${LIGA_DOCS}\n\n${FIRMA}` };
}
export function correoPrevencion(s, faltantes) {
  // Cada punto en MAYÚSCULAS (en texto plano no hay negritas); con "Copiar con formato" van además en negritas (petición de Manuel 28-sep)
  const lista = faltantes.map((f, i) => `${['PRIMERO','SEGUNDO','TERCERO','CUARTO','QUINTO','SEXTO','SÉPTIMO','OCTAVO'][i] || (i + 1) + '.'}. ${f.toUpperCase()}`).join('\n\n');
  const recibidos = (s.documentos || []).map(d => DOC_CORTO[d.tipo] || d.tipo).join(', ') || 'la documentación que obra en el expediente';
  return { asunto: `SITAD · Prevención · Folio ${s.folio} · Documentos faltantes`,
    cuerpo: `${CFG.LUGAR_EXPEDICION}, a ${fechaLarga(s.fecha_prevencion || hoy())}\n\nAsunto: Afiliación. Prevención de documentos faltantes.\n\nVista la solicitud de afiliación presentada el ${fechaLarga(s.fecha_recepcion)} por ${s.nombre_completo.toUpperCase()}, para su adscripción a la ${s.seccion}, con la siguiente documentación: ${recibidos}.\n\nDe su revisión se advierte que el expediente está incompleto en lo siguiente:\n\n${lista}\n\nEn consecuencia, y por una sola vez, se le previene para que remita lo señalado a más tardar el ${fechaLarga(s.limite_subsanacion)}. Recibida la documentación, la Secretaría continuará la revisión por los días hábiles que quedaron pendientes del plazo para dictaminar. Si la prevención no se atiende en tiempo, la solicitud se resolverá con los elementos que obren en el expediente.

SU NÚMERO DE REGISTRO (FOLIO) ES: ${s.folio}
Con ese folio y su correo (${s.correo}) puede consultar su trámite y subir lo que falta en: ${ligaTramite(s)}

Puede enviar lo que falta por cualquiera de estas dos vías, escribiendo siempre su folio ${s.folio}:
1. Respondiendo a este correo.
2. Subiéndolo directamente en la plataforma con la liga anterior.

${FIRMA}` };
}
export function correoFavorable(s) {
  return { asunto: `SITAD · Dictamen favorable de afiliación · Folio ${s.folio}`,
    cuerpo: `${CFG.LUGAR_EXPEDICION}, a ${fechaLarga(s.fecha_dictamen || hoy())}\n\nAsunto: Afiliación. Dictamen.\n\nVista la solicitud de afiliación presentada el ${fechaLarga(s.fecha_recepcion)} por ${s.nombre_completo.toUpperCase()}, quien se identifica con credencial para votar, manifiesta expresamente su aceptación del Estatuto y declara ser trabajador(a) en activo de la Empresa, adjuntando en formato digital la documentación que integra su expediente.\n\nDel análisis de la documentación, esta Secretaría advierte que la persona solicitante reúne los requisitos de ingreso establecidos en el Estatuto. En consecuencia, se determina:\n\nPRIMERO. Se dictamina FAVORABLE la solicitud de afiliación de ${s.nombre_completo.toUpperCase()}, con adscripción a la ${s.seccion}.\n\nSEGUNDO. Regístrese el alta de la persona solicitante en el Padrón de Afiliados y expídase la Constancia de Registro de Afiliación y la credencial correspondiente. El Padrón se somete a la firma del Secretario General.\n\nTERCERO. Notifíquese a la Sección y a la Secretaría de Finanzas para los efectos de su competencia.\n\nCUARTO. Remítase a la persona solicitante un ejemplar de los Documentos Básicos del Sindicato para su conocimiento.\n\nNotifíquese.\n\n${FIRMA}` };
}
export function correoDesfavorable(s) {
  return { asunto: `SITAD · Dictamen de afiliación · Folio ${s.folio}`,
    cuerpo: `${CFG.LUGAR_EXPEDICION}, a ${fechaLarga(s.fecha_dictamen || hoy())}\n\nVista la solicitud de afiliación presentada el ${fechaLarga(s.fecha_recepcion)} por ${s.nombre_completo.toUpperCase()} y la documentación que obra en el expediente, esta Secretaría advierte que no se acredita el siguiente requisito de ingreso: ${s.motivo_desfavorable || '[requisito y motivo]'}.\n\nEn consecuencia, se dictamina DESFAVORABLE la solicitud. La persona interesada podrá presentar una nueva solicitud cuando reúna el requisito señalado, y puede solicitar aclaraciones a esta Secretaría por este medio.\n\nNotifíquese.\n\n${FIRMA}` };
}
// Papelería que la persona lleva en original a la oficina de su Sección (resguardo físico)
export const PAPELERIA_ORIGINAL = 'tu solicitud de afiliación y tu cédula firmadas con tinta azul, tu INE, tu constancia de la CURP y tu Constancia de Situación Fiscal (los mismos documentos que subiste)';
// Dónde recoge la persona su credencial y su número de afiliado: la oficina de su Sección (o, mientras no la capture, la persona asignada / el CEN)
export function oficinaTexto(p, s) {
  const seccion = p.seccion || s?.seccion;
  const dom = p.oficina_domicilio || s?.oficina_domicilio, hor = p.oficina_horario || s?.oficina_horario;
  const nom = p.oficina_contacto_nombre || s?.oficina_contacto_nombre, tel = p.oficina_contacto_telefono || s?.oficina_contacto_telefono;
  if (dom) return `Acude personalmente a la oficina de la ${seccion}: ${dom}${hor ? ' (' + hor + ')' : ''}.${nom || tel ? ' Te atiende ' + (nom || 'la Secretaría de Organización de la Sección') + (tel ? ', teléfono ' + tel : '') + '.' : ''}`;
  if (nom || tel) return `Comunícate con ${nom || 'la persona asignada por tu Sección'}${tel ? ', teléfono ' + tel : ''}, para acordar el lugar y la fecha en que te recibe la ${seccion}.`;
  return `Tu Sección (${seccion}) se comunicará contigo para indicarte el lugar y la fecha en que te recibe. Si en una semana no tienes noticias, escribe a ${CFG.CORREO_ORGANIZACION} o llama al ${CFG.TELEFONO_CONTACTO}.`;
}
// Carta de aceptación (correo 5 de AF-04 / correo 4 de AF-04b). Decisión 18-sep-2026: la credencial y el número de afiliado
// NO se envían; se entregan en la oficina de la Sección contra la papelería en original.
export function correoAlta(p, s) {
  const nombre = p.nombre_completo.split(' ')[0]; const seccion = p.seccion || s?.seccion;
  const asamblea = p.asamblea_fecha_hora || s?.asamblea_fecha_hora; const dir = p.asamblea_direccion || s?.asamblea_direccion; const conv = p.convocatoria_url || s?.convocatoria_url;
  const enConstitucion = !!asamblea;
  const bloqueAsamblea = enConstitucion ? `\n\nInformación para la asamblea. Fecha: ${fechaHoraLarga(asamblea)}. Lugar: ${dir || '[dirección]'}. Llega una hora antes del inicio con tu gafete impreso o en el teléfono y tu identificación oficial vigente; sin identificación no es posible registrar tu asistencia.${conv ? ' Convocatoria: ' + conv + '.' : ''}` : '';
  const tok = p.credencial_qr_token; const ligaConst = tok ? `${ROOT}documento.html?tipo=constancia&t=${tok}` : ''; const ligaGaf = tok ? `${ROOT}documento.html?tipo=gafete&t=${tok}` : '';
  const bloqueDocs = tok
    ? `TU CONSTANCIA DE REGISTRO${enConstitucion ? ' Y TU GAFETE' : ''}: descárgalos e imprímelos desde estas ligas (también puedes mostrarlos en el teléfono).\nConstancia de Registro (Anexo 15): ${ligaConst}${enConstitucion ? `\nGafete para la Asamblea Constitutiva (Anexo 14): ${ligaGaf}` : ''}`
    : `Adjuntamos tu Constancia de Registro${enConstitucion ? ' (con la información de la asamblea) y tu gafete' : ''}.`;
  return { asunto: `SITAD · Carta de aceptación · Ya formas parte del Sindicato · Folio ${p.folio}`,
    cuerpo: `Hola, ${nombre}:\n\nNos da mucho gusto informarte que la Secretaría de Organización dictaminó FAVORABLE tu solicitud y quedaste registrado(a) en el Padrón de Afiliados del ${CFG.SINDICATO} el ${fechaLarga(p.fecha_autorizacion_sg || s?.fecha_autorizacion_sg)}. Tu solicitud (folio ${p.folio}) fue ACEPTADA y quedas adscrito(a) a la ${seccion}${enConstitucion ? ', registrado(a) para participar en su Asamblea Constitutiva' : ''}.\n\n${bloqueDocs}\n\nTe invitamos a leer los Documentos Básicos del Sindicato (Declaración de Principios, Programa de Acción y Estatuto): ${LIGA_DOCS}${bloqueAsamblea}\n\nPASO FINAL: RECOGE TU CREDENCIAL Y TU NÚMERO DE AFILIADO EN TU SECCIÓN.\n${oficinaTexto(p, s)}\nLleva en original ${PAPELERIA_ORIGINAL}. La Sección integra tu expediente físico, te entrega tu credencial (impresa o en formato digital) con tu número de afiliado y te explica cómo trabaja tu Sección y a quién acudir para tu representación sindical. Tu afiliación ya está registrada; la credencial se entrega únicamente en persona.\n\nCuota sindical: la Secretaría de Finanzas te ${enConstitucion ? 'enviará por separado' : 'envía adjunta'} la información para cubrirla (cuenta, monto y cómo enviar tu comprobante). También puedes registrar tu pago en ${ROOT}pagos/.\n\n${enConstitucion ? 'Atentamente,\nMESA DE REGISTRO · ' : ''}${FIRMA}`,
    finanzas: `Se informa el alta de ${p.nombre_completo}, número de afiliación ${p.numero_afiliacion}, folio ${p.folio}, ${seccion}, para la gestión de su cuota sindical ordinaria.` };
}
// ===== WhatsApp (se abre WhatsApp Web / la app con el número de la persona y el mensaje escrito) =====
export function telWa(t) { const d = String(t || '').replace(/\D/g, ''); if (!d) return ''; return d.length === 10 ? '52' + d : d; }
export function whatsapp(tel, texto) { return `https://wa.me/${telWa(tel)}?text=${encodeURIComponent(texto)}`; }
export function ligaTramite(s) { return `${ROOT}estado/?f=${encodeURIComponent(s.folio)}&c=${encodeURIComponent(s.correo || '')}`; }
export function waAcuse(s) { return `Hola, ${s.nombre_completo.split(' ')[0]}. La Secretaría de Organización del SITAD recibió tu solicitud de afiliación el ${fechaLarga(s.fecha_recepcion)}. Tu folio es *${s.folio}*. Revisamos tu expediente en un máximo de diez días hábiles; si falta algo te lo pedimos una sola vez por este medio. Consulta tu trámite y sube documentos aquí: ${ligaTramite(s)}`; }
export function waPrevencion(s, faltantes) { return `Hola, ${s.nombre_completo.split(' ')[0]}. Sobre tu solicitud de afiliación al SITAD, folio *${s.folio}*: al revisar tu expediente falta lo siguiente:\n\n${faltantes.map((f, i) => (i + 1) + '. ' + f).join('\n')}\n\nTu número de registro (folio) es *${s.folio}*. Envíalo a más tardar el *${fechaLarga(s.limite_subsanacion)}* por cualquiera de estas dos vías, siempre con tu folio: 1) respondiendo por aquí, 2) subiéndolo en la plataforma (entra con tu folio y tu correo): ${ligaTramite(s)}

Es la única prevención que se hace; si no se atiende en tiempo, la solicitud se resuelve con lo que obre en el expediente.\n\nSecretaría de Organización · CEN · SITAD`; }
export function waFavorable(s) { return `Hola, ${s.nombre_completo.split(' ')[0]}. Tu solicitud de afiliación al SITAD (folio *${s.folio}*) fue dictaminada *FAVORABLE* el ${fechaLarga(s.fecha_dictamen || hoy())}, con adscripción a la ${s.seccion}. Se remitió al Secretario General para autorizar tu alta en el Padrón. Te avisamos en cuanto quede registrada. Puedes seguir tu trámite en ${ligaTramite(s)}\n\nSecretaría de Organización · CEN · SITAD`; }
export function waDesfavorable(s) { return `Hola, ${s.nombre_completo.split(' ')[0]}. Sobre tu solicitud de afiliación al SITAD (folio *${s.folio}*): no se acreditó el siguiente requisito de ingreso: ${s.motivo_desfavorable || '[motivo]'}. Por ello se dictaminó desfavorable. Puedes presentar una nueva solicitud cuando reúnas el requisito, o pedir aclaraciones por este medio.\n\nSecretaría de Organización · CEN · SITAD`; }
export function waAlta(p, s) { const seccion = p.seccion || s?.seccion; const asamblea = p.asamblea_fecha_hora || s?.asamblea_fecha_hora; const dir = p.asamblea_direccion || s?.asamblea_direccion;
  return `¡Bienvenido(a), ${p.nombre_completo.split(' ')[0]}! Tu solicitud (folio ${p.folio}) fue *ACEPTADA* y ya estás en el Padrón de Afiliados del SITAD: y quedas adscrito(a) a la ${seccion}.${asamblea ? '\n\n*Asamblea Constitutiva:* ' + fechaHoraLarga(asamblea) + (dir ? ', en ' + dir : '') + '. Llega una hora antes con tu gafete impreso o en el teléfono y tu identificación oficial.' : ''}\n\n${p.credencial_qr_token ? `*Descarga tu Constancia de Registro:* ${ROOT}documento.html?tipo=constancia&t=${p.credencial_qr_token}${asamblea ? `\n*Descarga tu gafete para la asamblea:* ${ROOT}documento.html?tipo=gafete&t=${p.credencial_qr_token}` : ''}` : `Tu Constancia de Registro${asamblea ? ' y tu gafete' : ''} te ${asamblea ? 'los' : 'la'} enviamos por correo.`}\n\nDocumentos Básicos del Sindicato: ${LIGA_DOCS}\n\n*Paso final: recoge tu credencial y tu número de afiliado en tu Sección.* ${oficinaTexto(p, s)} Lleva en original ${PAPELERIA_ORIGINAL}. La credencial se entrega únicamente en persona.\n\nCuota sindical: la Secretaría de Finanzas te manda la información de pago; también puedes registrar tu pago en ${ROOT}pagos/\n\nSecretaría de Organización · CEN · SITAD`; }
// Recordatorio de la Sección para que la persona pase a la oficina (WhatsApp / correo)
export function waEntrega(p, s, firma) { return `Hola, ${p.nombre_completo.split(' ')[0]}. Tu afiliación al SITAD ya está registrada (folio ${p.folio}). Falta el último paso: ${oficinaTexto(p, s)} Lleva en original ${PAPELERIA_ORIGINAL}; ahí te entregamos tu credencial (impresa o digital) con tu número de afiliado.\n\n${firma || 'Secretaría de Organización · SITAD'}`; }
export function correoEntrega(p, s, firma) { return { asunto: `SITAD · Recoge tu credencial en tu Sección · Folio ${p.folio}`, cuerpo: waEntrega(p, s, firma).replace(/\*/g, '') }; }
// Seguimiento (rondas de corrección adicionales; no es la prevención formal, que es única)
// Seguimiento: dos vías para mandar lo que falta (responder al mensaje o subirlo por la liga), igual que la prevención (petición de Manuel 29-sep)
const puntoLimpio = f => String(f).replace(/;?\s*s[úu]balo por el medio institucional indicando su folio\.?/i, '').replace(/\.\s*$/, '') + '.';
export function waSeguimiento(s, puntos, firma) { const n = puntos.length; return `Hola, ${s.nombre_completo.split(' ')[0]}. Sobre tu solicitud de afiliación al SITAD, folio *${s.folio}*: revisamos lo que nos mandaste y ya casi está. Todavía hace falta lo siguiente:\n\n${puntos.map((f, i) => (n > 1 ? (i + 1) + '. ' : '') + puntoLimpio(f)).join('\n')}\n\nPuedes mandarlo por cualquiera de estas dos vías, siempre con tu folio *${s.folio}*:\n1. Respondiendo a este mismo mensaje con el documento adjunto (foto legible o PDF).\n2. Subiéndolo en esta liga (entra con tu folio y tu nombre o correo): ${ligaTramite(s)}${s.estado === 'Prevenida' && s.limite_subsanacion ? '\n\nRecuerda que la fecha límite es el *' + fechaLarga(s.limite_subsanacion) + '*.' : ''}\n\nSi tienes dudas, responde por aquí${firma ? '' : ' o acude a tu Sección: te ayudan a subirlo'}.\n\n${firma || 'Secretaría de Organización · CEN · SITAD'}`; }
export function correoSeguimiento(s, puntos, firma) { const n = puntos.length; return { asunto: `SITAD · Seguimiento a tu solicitud · Folio ${s.folio} · ${n === 1 ? 'falta un documento' : 'faltan ' + n + ' documentos'}`,
  cuerpo: `Hola, ${s.nombre_completo.split(' ')[0]}:\n\nSobre tu solicitud de afiliación al SITAD, folio ${s.folio}: revisamos lo que nos mandaste y ya casi está. Todavía hace falta lo siguiente:\n\n${puntos.map((f, i) => `${['PRIMERO', 'SEGUNDO', 'TERCERO', 'CUARTO', 'QUINTO', 'SEXTO', 'SÉPTIMO', 'OCTAVO'][i] || (i + 1) + '.'}. ${puntoLimpio(f).toUpperCase()}`).join('\n\n')}\n\nPuedes mandarlo por cualquiera de estas dos vías, escribiendo siempre tu folio ${s.folio}:\n1. Respondiendo a este correo con el documento adjunto (foto legible o PDF).\n2. Subiéndolo directamente en la plataforma con esta liga (entra con tu folio y tu nombre o correo): ${ligaTramite(s)}${s.estado === 'Prevenida' && s.limite_subsanacion ? '\n\nRecuerda que la fecha límite es el ' + fechaLarga(s.limite_subsanacion) + '.' : ''}\n\nSi tienes dudas, responde a este correo${firma ? '' : ' o acude a tu Sección: te ayudan a subirlo'}.\n\n${firma || 'Secretaría de Organización · Comité Ejecutivo Nacional · ' + CFG.SINDICATO}` }; }
// Carta de Finanzas (AF-09) en texto, para correo y WhatsApp
export function correoFinanzas(p, cfg) { const nombre = p.nombre_completo.split(' ')[0]; const sec = p.seccion_numero ? 'SECCIÓN ' + p.seccion_numero : (p.seccion || '').toUpperCase();
  const cuerpo = `Hola, ${nombre}:\n\nLa Secretaría de Finanzas del Sindicato de Trabajadores Digitales (SITAD) te invita a realizar el pago de tu cuota sindical, aportación destinada al fortalecimiento de las actividades, servicios, programas y representación que el Sindicato brinda a todas las personas afiliadas.\n\nDepósito o transferencia a la cuenta oficial del Sindicato:\nInstitución: ${cfg.banco_institucion || ''}\nTitular: ${cfg.banco_titular || ''}\nCuenta: ${cfg.banco_cuenta || ''}\nCLABE: ${cfg.banco_clabe || ''}\nMonto de la cuota: $${cfg.cuota_monto || '360'}.00 MXN (${cfg.cuota_periodicidad || 'mensual'})\n\nEn el concepto de la transferencia escribe: ${p.nombre_completo.toUpperCase()} – ${sec}\n\nDespués registra tu pago aquí (nombre, número de afiliación ${p.numero_afiliacion}, teléfono, periodo, monto, fecha y comprobante): ${ROOT}pagos/?num=${p.numero_afiliacion}\nO envía el comprobante a ${cfg.correo_finanzas || CFG.CORREO_FINANZAS} con el asunto: Comprobante de Pago de Cuota Sindical – ${p.nombre_completo} – ${p.numero_afiliacion}\n\nRecibido el comprobante, Finanzas verifica la operación, registra el pago en el padrón financiero y emite tu comprobante.\n\n“Por un futuro digital, al servicio de México”\n${(cfg.finanzas_titular || '').toUpperCase()} · Secretaría de Finanzas · Comité Ejecutivo Nacional · SITAD`;
  return { asunto: `SITAD · Invitación para realizar el pago de cuota sindical · No. ${p.numero_afiliacion}`, cuerpo }; }
// ===== Finanzas · cobranza mensual (petición de Manuel 29-sep-2026): requisición del mes, recordatorio y recibo con liga pública =====
export function mesTexto(ym) { const [a, m] = String(ym || '').slice(0, 7).split('-'); const n = MESES[parseInt(m) - 1] || ''; return n ? n.charAt(0).toUpperCase() + n.slice(1) + ' ' + a : String(ym || ''); }
export function ligaRecibo(pg) { return pg && pg.recibo_token ? `${ROOT}documento.html?tipo=comprobante&t=${pg.recibo_token}` : ''; }
export function ligaPago(x, ym) { return `${ROOT}pagos/?num=${x.numero_afiliacion}&mes=${String(ym || '').slice(0, 7)}`; }
const firmaFinanzas = cfg => `${(cfg.finanzas_titular || '').toUpperCase()} · Secretaría de Finanzas · Comité Ejecutivo Nacional · SITAD`;
const cuentaTexto = cfg => `Institución: ${cfg.banco_institucion || ''}\nTitular: ${cfg.banco_titular || ''}\nCuenta: ${cfg.banco_cuenta || ''}\nCLABE: ${cfg.banco_clabe || ''}\nMonto de la cuota: $${cfg.cuota_monto || '360'}.00 MXN (${cfg.cuota_periodicidad || 'mensual'})`;
export function correoRequisicion(x, cfg, ym, recordatorio = false) {
  const nombre = x.nombre_completo.split(' ')[0], mes = mesTexto(ym), sec = x.seccion_numero ? 'SECCIÓN ' + x.seccion_numero : (x.seccion || '').toUpperCase();
  const cuerpo = `Hola, ${nombre}:\n\n${recordatorio ? `Te recordamos que sigue pendiente el pago de tu cuota sindical de ${mes}.` : `La Secretaría de Finanzas del Sindicato de Trabajadores Digitales (SITAD) te solicita el pago de tu cuota sindical correspondiente a ${mes}.`} La cuota sostiene las actividades, servicios, programas y representación que el Sindicato brinda a todas las personas afiliadas.\n\nDeposita o transfiere a la cuenta oficial del Sindicato:\n${cuentaTexto(cfg)}\n\nEn el concepto de la transferencia escribe: ${x.nombre_completo.toUpperCase()} – ${sec} – ${mes.toUpperCase()}\n\nDespués envía tu comprobante por cualquiera de estas dos vías, indicando tu número de afiliado ${x.numero_afiliacion}:\n1. Respondiendo a este correo con el comprobante adjunto.\n2. Registrándolo directamente en la plataforma: ${ligaPago(x, ym)}\n\nRecibido el comprobante, Finanzas verifica la operación en el banco, registra tu pago en el padrón financiero y te envía tu comprobante de cuota con número de folio.\n\n“${CFG.LEMA}”\n${firmaFinanzas(cfg)}`;
  return { asunto: `SITAD · ${recordatorio ? 'Recordatorio: cuota' : 'Cuota'} sindical de ${mes} · No. ${x.numero_afiliacion}`, cuerpo };
}
export function waRequisicion(x, cfg, ym, recordatorio = false) {
  const nombre = x.nombre_completo.split(' ')[0], mes = mesTexto(ym), sec = x.seccion_numero ? 'SECCIÓN ' + x.seccion_numero : (x.seccion || '').toUpperCase();
  return `Hola, ${nombre}. ${recordatorio ? `Te recordamos que sigue pendiente tu *cuota sindical de ${mes}*.` : `La Secretaría de Finanzas del SITAD te solicita el pago de tu *cuota sindical de ${mes}*.`}\n\nDeposita o transfiere a la cuenta oficial del Sindicato:\n${cuentaTexto(cfg)}\nConcepto: ${x.nombre_completo.toUpperCase()} – ${sec} – ${mes.toUpperCase()}\n\nLuego mándanos tu comprobante por aquí (con tu número de afiliado *${x.numero_afiliacion}*) o regístralo en la plataforma: ${ligaPago(x, ym)}\n\nVerificado el pago, te enviamos tu comprobante de cuota con folio.\n\n${firmaFinanzas(cfg)}`;
}
export function correoRecibo(pg, cfg) {
  const nombre = (pg.afiliado_nombre || pg.nombre || '').split(' ')[0];
  const cuerpo = `Hola, ${nombre}:\n\nLa Secretaría de Finanzas del Sindicato de Trabajadores Digitales (SITAD) verificó tu pago de cuota sindical y quedó registrado en el padrón financiero:\n\nPeriodo: ${pg.periodo}\nMonto: ${dinero(pg.monto)}\nFecha de la operación: ${fechaLarga(pg.fecha_operacion)}\nNúmero de comprobante: ${pg.comprobante_folio}\n\nDescarga tu comprobante de cuota aquí (puedes guardarlo en PDF o imprimirlo): ${ligaRecibo(pg)}\n\nGracias por cumplir con tu aportación; con ella sostenemos la representación y los servicios del Sindicato.\n\n“${CFG.LEMA}”\n${firmaFinanzas(cfg)}`;
  return { asunto: `SITAD · Comprobante de pago de cuota sindical ${pg.comprobante_folio} · ${pg.periodo}`, cuerpo };
}
export function waRecibo(pg, cfg) { const nombre = (pg.afiliado_nombre || pg.nombre || '').split(' ')[0]; return `Hola, ${nombre}. Finanzas del SITAD *verificó tu pago* de la cuota sindical de *${pg.periodo}* (${dinero(pg.monto)}, operación del ${fechaLarga(pg.fecha_operacion)}). Tu número de comprobante es *${pg.comprobante_folio}*.\n\nDescarga tu comprobante de cuota aquí: ${ligaRecibo(pg)}\n\n¡Gracias por tu aportación!\n${firmaFinanzas(cfg)}`; }
export function correoAlSG(lista) {
  const filas = lista.map(s => `• ${s.folio} · ${s.nombre_completo} · ${s.seccion} · dictamen del ${fecha(s.fecha_dictamen)}`).join('\n');
  return { asunto: `SITAD · Dictámenes favorables para autorización de alta (${lista.length})`,
    cuerpo: `Secretario General:\n\nSe remiten para su autorización las siguientes solicitudes de afiliación dictaminadas favorables:\n\n${filas}\n\nPuede autorizarlas directamente en la plataforma: ${ROOT}sg/\n\n${FIRMA}` };
}
