// Utilidades compartidas entre la página de reservas y el panel del comercio
window.TU = (() => {
  const $ = s => document.querySelector(s);
  const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const money = n => '$' + Number(n || 0).toLocaleString('es-AR');
  const pad = n => String(n).padStart(2, '0');
  const dk = d => d.getFullYear() + '-' + pad(d.getMonth() + 1) + '-' + pad(d.getDate());
  const hm = m => pad(Math.floor(m / 60)) + ':' + pad(m % 60);
  const toMin = s => { const [h, m] = String(s).split(':').map(Number); return h * 60 + (m || 0); };
  const pday = k => { const [y, mo, d] = k.split('-').map(Number); return new Date(y, mo - 1, d); };
  const days = n => { const b = new Date(); b.setHours(0, 0, 0, 0); return Array.from({ length: n }, (_, i) => { const x = new Date(b); x.setDate(b.getDate() + i); return x; }); };
  const DIAS = ['Dom', 'Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb'];
  const DIAL = ['domingo', 'lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado'];
  const MES = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];
  // Convierte un celular argentino a formato wa.me (549 + área + número)
  const waAR = t => {
    let d = String(t || '').replace(/\D/g, '');
    if (d.startsWith('54')) d = d.slice(2);
    if (d.startsWith('9')) d = d.slice(1);
    if (d.startsWith('0')) d = d.slice(1);
    d = d.replace(/^(\d{2,4})15/, '$1');
    return '549' + d;
  };
  return { $, esc, money, pad, dk, hm, toMin, pday, days, DIAS, DIAL, MES, waAR };
})();
