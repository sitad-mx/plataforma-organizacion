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
export const DOCS = [
  { tipo: 'solicitud', nombre: 'Solicitud de afiliación firmada (Anexo 12 y 13: manifestación y aviso de privacidad, dos firmas de puño y letra)', corto: 'Solicitud (Anexo 12-13)', ayuda: 'El sistema te la entrega prellenada; imprímela, fírmala en las dos hojas y súbela escaneada o fotografiada completa.' },
  { tipo: 'cedula', nombre: 'Cédula de afiliación firmada (Anexo 23), con todos los campos', corto: 'Cédula (Anexo 23)', ayuda: 'También te la entrega prellenada el sistema; fírmala y súbela.' },
  { tipo: 'identificacion', nombre: 'Identificación oficial vigente (credencial para votar INE), frente y reverso', corto: 'INE', ayuda: 'Legible, sin recortes.' },
  { tipo: 'curp', nombre: 'Constancia de la CURP', corto: 'CURP', ayuda: 'Impresa desde el portal oficial (gob.mx).' },
  { tipo: 'constancia_fiscal', nombre: 'Constancia de Situación Fiscal (SAT), reciente y con RFC completo', corto: 'Constancia fiscal', ayuda: 'Se descarga del portal del SAT. Se usa para la emisión de tus recibos.' },
];
export const DOCS_TRANSPORTE = [
  { tipo: 'tarjeta_circulacion', nombre: 'Tarjeta de circulación (solo transporte de pasajeros o última milla)', corto: 'Tarjeta de circulación' },
  { tipo: 'poliza', nombre: 'Póliza de seguro del vehículo (solo transporte)', corto: 'Póliza de seguro' },
  { tipo: 'licencia', nombre: 'Licencia de manejo (solo transporte)', corto: 'Licencia de manejo' },
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
  'Dictaminada favorable': { etiqueta: 'verde', persona: 'Tu solicitud fue dictaminada favorable. Está en espera de la autorización del Secretario General.' },
  'Dictaminada desfavorable': { etiqueta: 'rojo', persona: 'Tu solicitud fue dictaminada desfavorable. Revisa el motivo en el correo que recibiste; puedes presentar una nueva solicitud cuando reúnas el requisito.' },
  'Enviada al SG': { etiqueta: 'verde', persona: 'Tu solicitud fue dictaminada favorable y está con el Secretario General para autorizar tu alta.' },
  'Autorizada': { etiqueta: 'verde', persona: 'El Secretario General autorizó tu alta. En breve quedarás registrado(a) en el Padrón.' },
  'Ejecutada en padrón': { etiqueta: 'verde', persona: 'Ya formas parte del Sindicato. Tu alta en el Padrón está registrada.' },
  'Desistida': { etiqueta: 'carbon', persona: 'La solicitud quedó sin efectos por desistimiento.' },
};
export const SEMAFORO_TXT = { verde: 'Lista para dictamen', amarillo: 'Expediente incompleto', rojo: 'Revisar: duplicado o confianza', cerrada: 'Concluida' };
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
  const usuario = p ? `<span class="usuario">${esc(p.nombre || p.email)}${p.secciones ? ' · ' + esc(p.secciones.denominacion) : ''} · <a href="#" id="salir-enlace">Salir</a></span>` : `<a href="${ROOT}entrar/">Entrar</a>`;
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
export function mailto(para, asunto, cuerpo, cc = '') {
  const q = new URLSearchParams(); if (cc) q.set('cc', cc); q.set('subject', asunto); q.set('body', cuerpo);
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
  const lista = faltantes.map((f, i) => `${['PRIMERO','SEGUNDO','TERCERO','CUARTO','QUINTO','SEXTO'][i] || (i + 1) + '.'}. ${f}`).join('\n\n');
  const recibidos = (s.documentos || []).map(d => DOC_CORTO[d.tipo] || d.tipo).join(', ') || 'la documentación que obra en el expediente';
  return { asunto: `SITAD · Prevención · Folio ${s.folio} · Documentos faltantes`,
    cuerpo: `${CFG.LUGAR_EXPEDICION}, a ${fechaLarga(s.fecha_prevencion || hoy())}\n\nAsunto: Afiliación. Prevención de documentos faltantes.\n\nVista la solicitud de afiliación presentada el ${fechaLarga(s.fecha_recepcion)} por ${s.nombre_completo.toUpperCase()}, para su adscripción a la ${s.seccion}, con la siguiente documentación: ${recibidos}.\n\nDe su revisión se advierte que el expediente está incompleto en lo siguiente:\n\n${lista}\n\nEn consecuencia, y por una sola vez, se le previene para que remita lo señalado a más tardar el ${fechaLarga(s.limite_subsanacion)} por el mismo medio, indicando su folio (puede subirlo directamente en ${ROOT}estado/ con su folio y su correo). Recibida la documentación, la Secretaría continuará la revisión por los días hábiles que quedaron pendientes del plazo para dictaminar. Si la prevención no se atiende en tiempo, la solicitud se resolverá con los elementos que obren en el expediente.\n\n${FIRMA}` };
}
export function correoFavorable(s) {
  return { asunto: `SITAD · Dictamen favorable de afiliación · Folio ${s.folio}`,
    cuerpo: `${CFG.LUGAR_EXPEDICION}, a ${fechaLarga(s.fecha_dictamen || hoy())}\n\nAsunto: Afiliación. Dictamen.\n\nVista la solicitud de afiliación presentada el ${fechaLarga(s.fecha_recepcion)} por ${s.nombre_completo.toUpperCase()}, quien se identifica con credencial para votar, manifiesta expresamente su aceptación del Estatuto y declara ser trabajador(a) en activo de la Empresa, adjuntando en formato digital la documentación que integra su expediente.\n\nDel análisis de la documentación, esta Secretaría advierte que la persona solicitante reúne los requisitos de ingreso establecidos en el Estatuto. En consecuencia, se determina:\n\nPRIMERO. Se dictamina FAVORABLE la solicitud de afiliación de ${s.nombre_completo.toUpperCase()}, con adscripción a la ${s.seccion}.\n\nSEGUNDO. Remítase el presente dictamen al Secretario General para la autorización del alta en el Padrón de Afiliados y la expedición de la credencial correspondiente.\n\nTERCERO. Autorizada el alta, expídase la Constancia de Registro de Afiliación y notifíquese a la Sección y a la Secretaría de Finanzas para los efectos de su competencia.\n\nCUARTO. Remítase a la persona solicitante un ejemplar de los Documentos Básicos del Sindicato para su conocimiento.\n\nNotifíquese.\n\n${FIRMA}` };
}
export function correoDesfavorable(s) {
  return { asunto: `SITAD · Dictamen de afiliación · Folio ${s.folio}`,
    cuerpo: `${CFG.LUGAR_EXPEDICION}, a ${fechaLarga(s.fecha_dictamen || hoy())}\n\nVista la solicitud de afiliación presentada el ${fechaLarga(s.fecha_recepcion)} por ${s.nombre_completo.toUpperCase()} y la documentación que obra en el expediente, esta Secretaría advierte que no se acredita el siguiente requisito de ingreso: ${s.motivo_desfavorable || '[requisito y motivo]'}.\n\nEn consecuencia, se dictamina DESFAVORABLE la solicitud. La persona interesada podrá presentar una nueva solicitud cuando reúna el requisito señalado, y puede solicitar aclaraciones a esta Secretaría por este medio.\n\nNotifíquese.\n\n${FIRMA}` };
}
// Correo 5 (AF-04) o correo 4 (AF-04b, sedes en constitución: incluye la información para la asamblea)
export function correoAlta(p, s) {
  const nombre = p.nombre_completo.split(' ')[0]; const seccion = p.seccion || s?.seccion;
  const asamblea = p.asamblea_fecha_hora || s?.asamblea_fecha_hora; const dir = p.asamblea_direccion || s?.asamblea_direccion; const conv = p.convocatoria_url || s?.convocatoria_url;
  const enConstitucion = !!asamblea;
  const bloqueAsamblea = enConstitucion ? `\n\nInformación para la asamblea. Fecha: ${fechaHoraLarga(asamblea)}. Lugar: ${dir || '[dirección]'}. Llega una hora antes del inicio con tu gafete impreso o en el teléfono y tu identificación oficial vigente; sin identificación no es posible registrar tu asistencia. El código QR del gafete y esta liga te llevan a los Documentos Básicos del Sindicato: ${LIGA_DOCS}.${conv ? ' Convocatoria: ' + conv + '.' : ''}` : '';
  return { asunto: `SITAD · Bienvenido(a) · Alta en el Padrón · Folio ${p.folio}`,
    cuerpo: `Hola, ${nombre}:\n\nEl Secretario General autorizó tu alta en el Padrón de Afiliados el ${fechaLarga(p.fecha_autorizacion_sg || s?.fecha_autorizacion_sg)}. A partir de hoy formas parte del ${CFG.SINDICATO}, ${enConstitucion ? 'con adscripción a la ' + seccion + ', y quedas registrado(a) para participar en su Asamblea Constitutiva' : 'adscrito(a) a la ' + seccion}. Tu número de afiliación es ${p.numero_afiliacion}.\n\nAdjuntamos tu Constancia de Registro${enConstitucion ? ' (con la información de la asamblea) y tu gafete' : ' de Afiliación y tu credencial'}.${bloqueAsamblea}\n\nLa Secretaría de Finanzas te ${enConstitucion ? 'enviará por separado' : 'envía adjunta'} la información para cubrir tu cuota sindical ordinaria (cuenta, monto y cómo enviar tu comprobante). También puedes registrar tu pago en ${ROOT}pagos/.\n\n${enConstitucion ? '' : 'Te invitamos a leer los Documentos Básicos: ' + LIGA_DOCS + '. Tu Sección te contactará para integrarte a sus actividades.\n\n'}${enConstitucion ? 'Atentamente,\nMESA DE REGISTRO · ' : ''}${FIRMA}`,
    finanzas: `Se informa el alta de ${p.nombre_completo}, número de afiliación ${p.numero_afiliacion}, folio ${p.folio}, ${seccion}, para la gestión de su cuota sindical ordinaria.` };
}
export function correoAlSG(lista) {
  const filas = lista.map(s => `• ${s.folio} · ${s.nombre_completo} · ${s.seccion} · dictamen del ${fecha(s.fecha_dictamen)}`).join('\n');
  return { asunto: `SITAD · Dictámenes favorables para autorización de alta (${lista.length})`,
    cuerpo: `Secretario General:\n\nSe remiten para su autorización las siguientes solicitudes de afiliación dictaminadas favorables:\n\n${filas}\n\nPuede autorizarlas directamente en la plataforma: ${ROOT}sg/\n\n${FIRMA}` };
}
