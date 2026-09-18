// Componente compartido: tarjeta de carga de un documento con instrucciones, botón "Elegir archivo" y botón "Tomar foto".
// Lo usan afiliate/ (registro) y estado/ (consulta y corrección). Cada parte del documento (p. ej. INE frente/reverso) es una ranura.
import { esc, REGLAS_FOTO, REGLAS_FIRMA, validarArchivo } from './app.js';

export function ranuras(doc) { return doc.partes ? doc.partes.map(([parte, nombre]) => ({ parte, nombre })) : [{ parte: null, nombre: null }]; }
export function idRanura(doc, parte) { return `f_${doc.tipo}${parte ? '_' + parte : ''}`; }

// existentes: { 'tipo|parte': { nombre_archivo, validado, observacion } } ; ligas: { tipo: url del PDF prellenado } (solo para documentos generados)
export function tarjetaDoc(doc, { existentes = {}, ligas = {}, abierta = true } = {}) {
  const pasos = (doc.pasos || []).map(p => `<li>${esc(p)}</li>`).join('');
  const reglas = doc.firma ? REGLAS_FIRMA + ' ' + REGLAS_FOTO : REGLAS_FOTO;
  const liga = doc.generado && ligas[doc.tipo] ? `<a class="btn chico" href="${ligas[doc.tipo]}" target="_blank">Descargar PDF para firmar</a>` : '';
  const slots = ranuras(doc).map(r => {
    const clave = doc.tipo + '|' + (r.parte || ''); const ex = existentes[clave]; const id = idRanura(doc, r.parte);
    const estado = ex ? `<span class="punto ${ex.validado === false ? 'amarillo' : ex.validado ? 'verde' : 'azul'}"></span><span class="small">${ex.validado ? 'Revisado y correcto' : ex.validado === false ? 'Con observación' : 'Recibido'}${ex.nombre_archivo ? ' · ' + esc(ex.nombre_archivo) : ''}</span>${ex.observacion ? `<div class="small" style="color:var(--ambar)"><b>Observación de la Mesa de Registro:</b> ${esc(ex.observacion)}</div>` : ''}` : `<span class="punto rojo"></span><span class="small muted">Pendiente</span>`;
    return `<div class="ranura" data-tipo="${doc.tipo}" data-parte="${r.parte || ''}">
      ${r.nombre ? `<div class="ranura-titulo">${esc(r.nombre)}</div>` : ''}
      <div class="ranura-estado">${estado}</div>
      ${abierta ? `<div class="ranura-botones">
        <label class="btn secundario chico">📁 Elegir archivo<input type="file" class="oculto" id="${id}" accept="application/pdf,image/jpeg,image/png"></label>
        <label class="btn secundario chico">📷 Tomar foto<input type="file" class="oculto" id="${id}_cam" accept="image/*" capture="environment"></label>
        <span class="ranura-elegido small muted"></span></div>` : ''}
    </div>`;
  }).join('');
  return `<div class="doc-tarjeta" id="doc_${doc.tipo}">
    <div class="doc-cabeza"><b>${esc(doc.nombre)}</b>${doc.firma ? ' <span class="etiqueta rojo">se firma con tinta azul</span>' : ''}</div>
    ${doc.ayuda ? `<p class="small muted mb-0">${esc(doc.ayuda)}</p>` : ''}
    <details class="doc-instr"><summary>Cómo debe venir (instrucciones)</summary><ol>${pasos}</ol><p class="small"><b>Regla:</b> ${esc(reglas)}</p></details>
    ${liga ? `<div class="mt-1">${liga}</div>` : ''}
    ${slots}
  </div>`;
}

// Enlaza previsualización del nombre elegido y devuelve una función que recoge los archivos elegidos: [{tipo, parte, f}]
export function activarTarjetas(raiz = document) {
  raiz.querySelectorAll('.ranura').forEach(r => {
    const inputs = r.querySelectorAll('input[type=file]'); const etiqueta = r.querySelector('.ranura-elegido');
    inputs.forEach(inp => inp.addEventListener('change', () => {
      const f = inp.files[0]; if (!f) return;
      inputs.forEach(o => { if (o !== inp) o.value = ''; });
      const err = validarArchivo(f);
      if (etiqueta) etiqueta.innerHTML = err ? `<span style="color:var(--rojo)">${esc(err)}</span>` : `✓ ${esc(f.name)} (${(f.size / 1024 / 1024).toFixed(1)} MB)`;
      if (err) inp.value = '';
    }));
  });
  return () => {
    const out = [];
    raiz.querySelectorAll('.ranura').forEach(r => {
      const f = Array.from(r.querySelectorAll('input[type=file]')).map(i => i.files[0]).find(Boolean);
      if (f) out.push({ tipo: r.dataset.tipo, parte: r.dataset.parte || null, f });
    });
    return out;
  };
}
