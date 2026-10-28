// =========================================================================
// 🚀 KORRETURNOS PWA (iOS / iPhone & Web) - 100% SQLite (.db) Compatible
// =========================================================================

let db = null;
let SQL = null;

const urlParams = new URLSearchParams(window.location.search);
const esFamiliar = urlParams.get('modo') === 'familiar';

const MESES_EU = [
  "Urtarrila", "Otsaila", "Martxoa", "Apirila", "Maiatza", "Ekaina",
  "Uztaila", "Abuztua", "Iraila", "Urria", "Azaroa", "Abendua"
];

const PALETA_COLORES = [
  0xFFD32F2F, 0xFFB71C1C, 0xFFEF5350, 0xFF880E4F,
  0xFFE91E63, 0xFFC2185B, 0xFFFF4081, 0xFFF48FB1,
  0xFF9C27B0, 0xFF7B1FA2, 0xFF673AB7, 0xFF512DA8, 0xFF7E57C2, 0xFFB388FF,
  0xFF3F51B5, 0xFF283593, 0xFF1A237E, 0xFF303F9F,
  0xFF1E88E5, 0xFF1565C0, 0xFF0288D1, 0xFF03A9F4, 0xFF4FC3F7, 0xFF00B0FF,
  0xFF00BCD4, 0xFF00838F, 0xFF009688, 0xFF004D40, 0xFF26A69A, 0xFF80CBC4,
  0xFF4CAF50, 0xFF2E7D32, 0xFF1B5E20, 0xFF81C784, 0xFF00E676, 0xFF69F0AE,
  0xFF8BC34A, 0xFF558B2F, 0xFFCDDC39, 0xFF9E9D24, 0xFFFFEB3B, 0xFFFBC02D,
  0xFFFFC107, 0xFFFFA000, 0xFFFF9800, 0xFFF57C00, 0xFFFF5722, 0xFFD84315,
  0xFF795548, 0xFF4E342E, 0xFF8D6E63, 0xFFA1887F,
  0xFF607D8B, 0xFF37474F, 0xFF78909C, 0xFF9E9E9E, 0xFF424242, 0xFF263238
];

// Estado de navegación y vista
let state = {
  screen: 'calendario', // 'calendario', 'detalle', 'incidencia', 'ajustes', 'semanas', 'colores', 'copia', 'bru', 'busqueda', 'festivos', 'nuevo_turno'
  fechaVista: new Date(new Date().getFullYear(), new Date().getMonth(), 1),
  fechaFestivosVista: new Date(new Date().getFullYear(), new Date().getMonth(), 1),
  detalleParams: null, // { turno, tipo, fecha, soloLectura }
  incidenciaParams: null, // { fecha, turno, tipo }
  nuevoTurnoParams: null, // { turnoExistente, onSaved }
  coloresTab: 'LAB',
  busquedaQuery: '',
  busquedaResultados: []
};

// Cachés en memoria sincronizadas con SQLite
let cache = {
  registros: {},
  turnos: {},
  turnosLista: [],
  colores: {},
  calendarioOrientativo: {},
  semanasConfig: null,
  alarmasFechas: new Set(),
  adjuntosFechas: new Set(),
  festivosFechas: new Set()
};

// =========================================================================
// 💾 INDEXEDDB PERSISTENCE PARA SQLITE (.db)
// =========================================================================
const IDB_NAME = 'korreturnos_sqlite_store';
const IDB_STORE = 'databases';
const IDB_KEY = 'datos.db';

function openIDB() {
  return new Promise((resolve, reject) => {
    const req = indexedDB.open(IDB_NAME, 1);
    req.onupgradeneeded = (e) => {
      e.target.result.createObjectStore(IDB_STORE);
    };
    req.onsuccess = (e) => resolve(e.target.result);
    req.onerror = (e) => reject(e.target.error);
  });
}

async function cargarBytesDesdeIDB() {
  try {
    const idb = await openIDB();
    return await new Promise((resolve, reject) => {
      const tx = idb.transaction(IDB_STORE, 'readonly');
      const req = tx.objectStore(IDB_STORE).get(IDB_KEY);
      req.onsuccess = () => resolve(req.result || null);
      req.onerror = () => reject(req.error);
    });
  } catch (_) {
    return null;
  }
}

async function guardarDBEnIDB() {
  if (!db) return;
  try {
    const bytes = db.export();
    const idb = await openIDB();
    await new Promise((resolve, reject) => {
      const tx = idb.transaction(IDB_STORE, 'readwrite');
      tx.objectStore(IDB_STORE).put(bytes, IDB_KEY);
      tx.oncomplete = () => resolve();
      tx.onerror = () => reject(tx.error);
    });
  } catch (e) {
    console.error("Error guardando en IndexedDB:", e);
  }
}

// =========================================================================
// 🔧 UTILIDADES DE SQLITE Y MIGRACIONES
// =========================================================================
function queryAll(sql, params = []) {
  const stmt = db.prepare(sql);
  stmt.bind(params);
  const rows = [];
  while (stmt.step()) {
    rows.push(stmt.getAsObject());
  }
  stmt.free();
  return rows;
}

function runSQL(sql, params = []) {
  db.run(sql, params);
}

function asegurarEsquema() {
  // 1. Columnas de registro_diario
  const colsReg = new Set(queryAll("PRAGMA table_info(registro_diario)").map(c => c.name));
  if (!colsReg.has('observaciones')) runSQL("ALTER TABLE registro_diario ADD COLUMN observaciones TEXT DEFAULT ''");
  if (!colsReg.has('ajuste_minutos')) runSQL("ALTER TABLE registro_diario ADD COLUMN ajuste_minutos INTEGER DEFAULT 0");
  if (!colsReg.has('hasiera')) runSQL("ALTER TABLE registro_diario ADD COLUMN hasiera TEXT DEFAULT ''");
  if (!colsReg.has('amaiera')) runSQL("ALTER TABLE registro_diario ADD COLUMN amaiera TEXT DEFAULT ''");
  if (!colsReg.has('lan_orduak')) runSQL("ALTER TABLE registro_diario ADD COLUMN lan_orduak INTEGER DEFAULT 0");
  if (!colsReg.has('es_bru')) runSQL("ALTER TABLE registro_diario ADD COLUMN es_bru INTEGER DEFAULT 0");

  // Congelar horario en días existentes
  runSQL(`
    UPDATE registro_diario
    SET
      hasiera = COALESCE(
        NULLIF(hasiera, ''),
        (SELECT t.hasiera FROM turnos t WHERE t.turno = registro_diario.turno AND t.tipo = registro_diario.tipo LIMIT 1),
        (SELECT t.hasiera FROM turnos t WHERE t.turno = registro_diario.turno LIMIT 1),
        ''
      ),
      amaiera = COALESCE(
        NULLIF(amaiera, ''),
        (SELECT t.amaiera FROM turnos t WHERE t.turno = registro_diario.turno AND t.tipo = registro_diario.tipo LIMIT 1),
        (SELECT t.amaiera FROM turnos t WHERE t.turno = registro_diario.turno LIMIT 1),
        ''
      ),
      lan_orduak = COALESCE(
        CASE WHEN lan_orduak IS NOT NULL AND lan_orduak > 0 THEN lan_orduak ELSE NULL END,
        (SELECT t.lan_orduak FROM turnos t WHERE t.turno = registro_diario.turno AND t.tipo = registro_diario.tipo LIMIT 1),
        (SELECT t.lan_orduak FROM turnos t WHERE t.turno = registro_diario.turno LIMIT 1),
        0
      )
    WHERE hasiera IS NULL OR hasiera = '' OR amaiera IS NULL OR amaiera = '' OR lan_orduak IS NULL OR lan_orduak = 0
  `);

  // 2. Columna es_manual en turnos
  const colsTurnos = new Set(queryAll("PRAGMA table_info(turnos)").map(c => c.name));
  if (!colsTurnos.has('es_manual')) {
    runSQL("ALTER TABLE turnos ADD COLUMN es_manual INTEGER DEFAULT 0");
    runSQL(`
      UPDATE turnos SET es_manual = 1
      WHERE NOT EXISTS (
        SELECT 1 FROM servicios
        WHERE servicios.turno = turnos.turno AND servicios.tipo = turnos.tipo
      )
    `);
  }

  // 3. Tabla config_colores con clave compuesta
  const infoColores = queryAll("PRAGMA table_info(config_colores)");
  const pkColores = new Set(infoColores.filter(c => c.pk > 0).map(c => c.name));
  const hasTipo = infoColores.some(c => c.name === 'tipo');
  if (!pkColores.has('letra') || !pkColores.has('tipo')) {
    runSQL(`CREATE TABLE IF NOT EXISTS config_colores_new (letra TEXT, tipo TEXT DEFAULT '', color INTEGER, PRIMARY KEY (letra, tipo))`);
    if (hasTipo) {
      runSQL(`INSERT OR REPLACE INTO config_colores_new (letra, tipo, color) SELECT letra, COALESCE(tipo, ''), color FROM config_colores`);
    } else {
      runSQL(`INSERT OR REPLACE INTO config_colores_new (letra, tipo, color) SELECT letra, '', color FROM config_colores`);
    }
    runSQL(`DROP TABLE config_colores`);
    runSQL(`ALTER TABLE config_colores_new RENAME TO config_colores`);
  }

  // 4. Tabla alarmas_activadas
  runSQL(`
    CREATE TABLE IF NOT EXISTS alarmas_activadas (
      fecha TEXT,
      servicio TEXT,
      hora TEXT,
      hora_alarma TEXT DEFAULT '',
      fecha_disparo TEXT DEFAULT '',
      PRIMARY KEY (fecha, servicio, hora)
    )
  `);
  const colsAlarmas = new Set(queryAll("PRAGMA table_info(alarmas_activadas)").map(c => c.name));
  if (!colsAlarmas.has('hora_alarma')) runSQL("ALTER TABLE alarmas_activadas ADD COLUMN hora_alarma TEXT DEFAULT ''");
  if (!colsAlarmas.has('fecha_disparo')) runSQL("ALTER TABLE alarmas_activadas ADD COLUMN fecha_disparo TEXT DEFAULT ''");

  // 5. Tabla adjuntos_incidencia
  runSQL(`
    CREATE TABLE IF NOT EXISTS adjuntos_incidencia (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      fecha TEXT,
      nombre TEXT,
      tipo TEXT,
      ruta_local TEXT,
      datos BLOB,
      creado_en TEXT
    )
  `);

  // 6. Tabla festivos_anuales
  runSQL(`
    CREATE TABLE IF NOT EXISTS festivos_anuales (
      fecha TEXT PRIMARY KEY
    )
  `);
}

function recargarCaches() {
  // Semanas
  const sem = queryAll("SELECT * FROM config_semanas WHERE id = 1");
  cache.semanasConfig = sem.length > 0 ? sem[0] : null;

  // Registros
  cache.registros = {};
  for (const r of queryAll("SELECT * FROM registro_diario")) {
    if (r.fecha) cache.registros[r.fecha] = r;
  }

  // Turnos
  cache.turnos = {};
  cache.turnosLista = queryAll("SELECT * FROM turnos");
  for (const t of cache.turnosLista) {
    const key = `${t.turno}-${t.tipo || ''}`;
    cache.turnos[key] = t;
    if (!cache.turnos[t.turno]) cache.turnos[t.turno] = t;
  }

  // Colores
  cache.colores = {};
  for (const c of queryAll("SELECT * FROM config_colores")) {
    if (c.letra != null && c.color != null) {
      cache.colores[`${c.letra}-${c.tipo || ''}`] = Number(c.color);
      if (cache.colores[c.letra] === undefined) {
        cache.colores[c.letra] = Number(c.color);
      }
    }
  }

  // Calendario orientativo
  cache.calendarioOrientativo = {};
  for (const row of queryAll("SELECT * FROM calendario_orientativo")) {
    if (row.semana != null && row.dia_semana != null && row.tipo != null) {
      cache.calendarioOrientativo[`${row.semana}-${row.dia_semana}`] = String(row.tipo);
    }
  }

  // Adjuntos fechas
  cache.adjuntosFechas = new Set(
    queryAll("SELECT DISTINCT fecha FROM adjuntos_incidencia WHERE fecha IS NOT NULL").map(r => String(r.fecha))
  );

  // Festivos fechas
  cache.festivosFechas = new Set(
    queryAll("SELECT fecha FROM festivos_anuales").map(r => String(r.fecha))
  );

  // Purgar alarmas sonadas y cargar fechas activas
  purgarAlarmasSonadasGlobal();
}

function purgarAlarmasSonadasGlobal() {
  const ahora = new Date();
  const hoyStr = fechaStr(ahora);
  const ahoraMin = ahora.getHours() * 60 + ahora.getMinutes();
  const rows = queryAll("SELECT * FROM alarmas_activadas");
  const activas = new Set();

  for (const r of rows) {
    const f = String(r.fecha || '');
    if (!f) continue;
    let sonada = false;
    if (r.fecha_disparo) {
      const fd = new Date(r.fecha_disparo);
      if (!isNaN(fd.getTime()) && ahora >= fd) sonada = true;
    }
    if (!sonada) {
      if (f < hoyStr) sonada = true;
      else if (f === hoyStr) {
        const he = (r.hora_alarma || r.hora || '').split(':');
        if (he.length >= 2) {
          const m = parseInt(he[0], 10) * 60 + parseInt(he[1], 10);
          if (ahoraMin >= m) sonada = true;
        }
      }
    }
    if (sonada) {
      runSQL("DELETE FROM alarmas_activadas WHERE fecha = ? AND servicio = ? AND hora = ?", [r.fecha, r.servicio, r.hora]);
    } else {
      activas.add(f);
    }
  }
  cache.alarmasFechas = activas;
}

// =========================================================================
// 🎨 HELPERS DE FECHA Y COLOR
// =========================================================================
function pad2(n) { return String(n).padStart(2, '0'); }

function fechaStr(d) {
  return `${d.getFullYear()}-${pad2(d.getMonth() + 1)}-${pad2(d.getDate())}`;
}

function horaCorta(h) {
  if (!h) return '';
  const s = String(h);
  return s.length >= 5 ? s.substring(0, 5) : s;
}

function argbToCss(argb) {
  if (argb === undefined || argb === null) return '#546e7a';
  const unsigned = argb >>> 0;
  const hex = (unsigned & 0xFFFFFF).toString(16).padStart(6, '0');
  return `#${hex}`;
}

function luminance(argb) {
  const unsigned = (argb || 0xFF546E7A) >>> 0;
  const r = ((unsigned >> 16) & 0xFF) / 255;
  const g = ((unsigned >> 8) & 0xFF) / 255;
  const b = (unsigned & 0xFF) / 255;
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

function contrasteTexto(argb) {
  return luminance(argb) > 0.5 ? '#1e1e1e' : '#ffffff';
}

function calcularSemanaISO(d) {
  const utc = new Date(Date.UTC(d.getFullYear(), d.getMonth(), d.getDate()));
  const dayNum = utc.getUTCDay() || 7;
  utc.setUTCDate(utc.getUTCDate() + 4 - dayNum);
  const yearStart = new Date(Date.UTC(utc.getUTCFullYear(), 0, 1));
  return Math.ceil((((utc - yearStart) / 86400000) + 1) / 7);
}

function calcularSemanaOrientativa(d) {
  if (!cache.semanasConfig || !cache.semanasConfig.fecha_base || !cache.semanasConfig.semana_orientativa_base) {
    return null;
  }
  const parts = String(cache.semanasConfig.fecha_base).split('-');
  if (parts.length < 3) return null;
  const bUtc = Date.UTC(parseInt(parts[0], 10), parseInt(parts[1], 10) - 1, parseInt(parts[2], 10));
  const fUtc = Date.UTC(d.getFullYear(), d.getMonth(), d.getDate());
  const dias = Math.round((fUtc - bUtc) / 86400000);
  const semanas = Math.floor(dias / 7);
  const base = Number(cache.semanasConfig.semana_orientativa_base);
  return (((base - 1 + semanas) % 18) + 18) % 18 + 1;
}

function calcularMinutosDia(r) {
  let diaMin = 0;
  const regH = String(r.hasiera || '');
  const regA = String(r.amaiera || '');
  if (r.lan_orduak && Number(r.lan_orduak) > 0) {
    diaMin = Number(r.lan_orduak);
  } else if (regH && regA) {
    diaMin = diffMinutos(regH, regA);
  } else {
    const tInfo = cache.turnos[`${r.turno}-${r.tipo || ''}`] || cache.turnos[r.turno];
    if (tInfo && Number(tInfo.lan_orduak) > 0) {
      diaMin = Number(tInfo.lan_orduak);
    } else if (tInfo && tInfo.hasiera && tInfo.amaiera) {
      diaMin = diffMinutos(tInfo.hasiera, tInfo.amaiera);
    }
  }
  diaMin += Number(r.ajuste_minutos || 0);
  return diaMin > 0 ? diaMin : 0;
}

function diffMinutos(h1, h2) {
  const p1 = String(h1).split(':');
  const p2 = String(h2).split(':');
  if (p1.length < 2 || p2.length < 2) return 0;
  const m1 = parseInt(p1[0], 10) * 60 + parseInt(p1[1], 10);
  let m2 = parseInt(p2[0], 10) * 60 + parseInt(p2[1], 10);
  if (m2 < m1) m2 += 24 * 60;
  return m2 - m1;
}

function formatearHorasMin(min) {
  const signo = min < 0 ? '-' : '';
  const abs = Math.abs(min);
  const h = Math.floor(abs / 60);
  const m = abs % 60;
  if (h > 0 && m > 0) return `${signo}${h}h ${m}min`;
  if (h > 0) return `${signo}${h}h`;
  return `${signo}${m}min`;
}

function showToast(msg, bg = '#323232') {
  const existing = document.querySelector('.toast');
  if (existing) existing.remove();
  const el = document.createElement('div');
  el.className = 'toast';
  el.style.background = bg;
  el.textContent = msg;
  document.body.appendChild(el);
  setTimeout(() => el.remove(), 2600);
}

// =========================================================================
// 📅 1. PANTALLA PRINCIPAL: CALENDARIO MENSUAL
// =========================================================================
function renderCalendario() {
  const app = document.getElementById('app');
  const anio = state.fechaVista.getFullYear();
  const mes = state.fechaVista.getMonth(); // 0..11
  const nombreMes = MESES_EU[mes];

  // Calcular horas totales del mes (descontando BRU)
  let totalMin = 0;
  let totalAjuste = 0;
  const prefixMes = `${anio}-${pad2(mes + 1)}-`;

  for (const [fStr, r] of Object.entries(cache.registros)) {
    if (fStr.startsWith(prefixMes)) {
      if (Number(r.es_bru || 0) === 1) continue;
      totalMin += calcularMinutosDia(r);
      totalAjuste += Number(r.ajuste_minutos || 0);
    }
  }

  const hMes = Math.floor(totalMin / 60);
  const mMes = totalMin % 60;
  const textoHorasMes = totalAjuste !== 0
    ? `Hileko orduak: ${hMes} h ${pad2(mMes)} min  (${totalAjuste > 0 ? '+' + totalAjuste : totalAjuste} min doik.)`
    : `Hileko orduak: ${hMes} h ${pad2(mMes)} min`;

  // Construir semanas del mes
  const primerDia = new Date(anio, mes, 1);
  const ultimoDia = new Date(anio, mes + 1, 0);
  const diaSem = primerDia.getDay() || 7; // 1=Lun..7=Dom
  let cursor = new Date(anio, mes, 1 - (diaSem - 1));
  const hoyStr = fechaStr(new Date());

  let filasHTML = '';
  while (cursor <= ultimoDia || cursor.getMonth() === mes) {
    const semISO = calcularSemanaISO(cursor);
    const semOri = calcularSemanaOrientativa(cursor);

    let celdasHTML = '';
    for (let i = 0; i < 7; i++) {
      const d = new Date(cursor.getFullYear(), cursor.getMonth(), cursor.getDate() + i);
      const dStr = fechaStr(d);
      const esMesActual = d.getMonth() === mes;
      const esHoy = dStr === hoyStr;
      const reg = cache.registros[dStr];
      const tieneTurno = !!(reg && reg.turno);
      const diaSemana = d.getDay() || 7;
      const tipoOri = semOri ? cache.calendarioOrientativo[`${semOri}-${diaSemana}`] : null;

      const tieneNota = (reg && String(reg.observaciones || '').trim().length > 0) || cache.adjuntosFechas.has(dStr);
      const tieneAlarma = cache.alarmasFechas.has(dStr);
      const esBru = reg && Number(reg.es_bru || 0) === 1;
      const esFestivoAnual = cache.festivosFechas.has(dStr);

      let bgCss = esMesActual ? '#ffffff' : '#f3f4f6';
      let argbFondo = null;
      if (tieneTurno) {
        const colKey = `${reg.turno}-${reg.tipo || ''}`;
        argbFondo = cache.colores[colKey] ?? cache.colores[reg.turno] ?? 0xFF546E7A;
        bgCss = argbToCss(argbFondo);
      } else if (tipoOri) {
        if (tipoOri === 'M') bgCss = 'rgba(255, 152, 0, 0.20)';
        else if (tipoOri === 'T') bgCss = 'rgba(76, 175, 80, 0.20)';
        else if (tipoOri === 'DES') bgCss = 'rgba(244, 67, 54, 0.20)';
        else if (tipoOri === 'ABS') bgCss = 'rgba(33, 150, 243, 0.20)';
      }

      // Color de texto: solo en rojo los días marcados en festivos_anuales
      let txtColor = esMesActual ? '#1e1e1e' : '#bdbdbd';
      if (esFestivoAnual) {
        if (tieneTurno) {
          txtColor = luminance(argbFondo) > 0.4 ? '#c62828' : '#ff4d4d';
        } else {
          txtColor = esMesActual ? '#d32f2f' : '#ef9a9a';
        }
      } else if (tieneTurno) {
        txtColor = contrasteTexto(argbFondo);
      }

      let hIni = '';
      let hFin = '';
      if (tieneTurno) {
        const baseT = cache.turnos[`${reg.turno}-${reg.tipo || ''}`] || cache.turnos[reg.turno];
        hIni = horaCorta(reg.hasiera || (baseT ? baseT.hasiera : ''));
        hFin = horaCorta(reg.amaiera || (baseT ? baseT.amaiera : ''));
      }

      celdasHTML += `
        <div class="cal-cell ${esHoy ? 'hoy' : ''}" data-fecha="${dStr}" style="background:${bgCss};color:${txtColor};">
          <div style="display:flex;justify-content:space-between;align-items:center;">
            <div style="display:flex;align-items:center;gap:2px;">
              <span style="font-size:11px;font-weight:${esHoy || tieneTurno || esFestivoAnual ? '700' : '400'};">${d.getDate()}</span>
              ${tieneNota ? '<span style="font-size:10px;line-height:1;">⭐</span>' : ''}
              ${tieneAlarma ? '<span style="font-size:10px;line-height:1;">🔔</span>' : ''}
            </div>
            ${esBru
              ? `<span style="background:#7b1fa2;color:#fff;font-size:7.5px;font-weight:900;padding:1px 3px;border-radius:3px;">BRU</span>`
              : (!tieneTurno && tipoOri
                  ? `<span style="background:rgba(0,0,0,0.08);color:${esFestivoAnual ? '#c62828' : '#424242'};font-size:8px;font-weight:700;padding:1px 3px;border-radius:3px;">${tipoOri}</span>`
                  : '')}
          </div>
          ${tieneTurno ? `
            <div style="margin-top:2px;">
              <div style="font-size:11px;font-weight:800;line-height:1.15;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;">${reg.turno}</div>
              <div style="font-size:9px;font-weight:600;opacity:0.88;line-height:1.1;">${reg.tipo || ''}</div>
              <div style="font-size:9.5px;font-weight:600;margin-top:2px;line-height:1.1;">${hIni}</div>
              <div style="font-size:9.5px;opacity:0.88;line-height:1.1;">${hFin}</div>
            </div>
          ` : '<div style="height:12px;"></div>'}
        </div>
      `;
    }

    filasHTML += `
      <div class="cal-row">
        <div class="cal-sem-cell">
          <div style="font-size:11px;font-weight:700;color:#212121;">${semISO}</div>
          ${semOri ? `<div style="font-size:9.5px;color:#757575;">(${semOri})</div>` : ''}
        </div>
        ${celdasHTML}
      </div>
    `;

    cursor = new Date(cursor.getFullYear(), cursor.getMonth(), cursor.getDate() + 7);
    if (cursor.getMonth() > mes && (cursor.getDay() || 7) === 1) break;
  }

  app.innerHTML = `
    <div class="appbar">
      <div class="appbar-title">${nombreMes} ${anio}</div>
      <div class="appbar-actions">
        <button class="icon-btn" id="btn-hoy" title="Gaurko egunera joan">📅</button>
        ${esFamiliar
          ? `<button class="icon-btn" id="btn-sync-fam" title="Egutegia eguneratu (kopia kargatu)">🔄</button>`
          : `<button class="icon-btn" id="btn-ajustes" title="Ezarpenak">⚙️</button>`
        }
      </div>
    </div>
    <div class="month-selector">
      <button class="icon-btn" id="btn-mes-ant">❮</button>
      <div class="month-selector-title">${nombreMes.toUpperCase()} ${anio}</div>
      <button class="icon-btn" id="btn-mes-sig">❯</button>
    </div>
    <div class="cal-header">
      <div class="cal-sem-col">AST</div>
      ${["L", "M", "X", "J", "V", "S", "D"].map(d => `
        <div class="cal-day-head" style="color:${d === 'S' || d === 'D' ? '#ef5350' : '#212121'};">${d}</div>
      `).join('')}
    </div>
    <div class="cal-body" id="cal-grid">
      ${filasHTML}
    </div>
    <div class="bottom-bar">${textoHorasMes}</div>
  `;

  document.getElementById('btn-hoy').onclick = () => {
    const ahora = new Date();
    state.fechaVista = new Date(ahora.getFullYear(), ahora.getMonth(), 1);
    render();
  };
  document.getElementById('btn-mes-ant').onclick = () => {
    state.fechaVista = new Date(anio, mes - 1, 1);
    render();
  };
  document.getElementById('btn-mes-sig').onclick = () => {
    state.fechaVista = new Date(anio, mes + 1, 1);
    render();
  };

  if (esFamiliar) {
    document.getElementById('btn-sync-fam').onclick = importarArchivoDB;
  } else {
    document.getElementById('btn-ajustes').onclick = () => {
      state.screen = 'ajustes';
      render();
    };
  }

  // Eventos de celdas (tap y pulsación larga)
  document.querySelectorAll('.cal-cell').forEach(cell => {
    const fStr = cell.getAttribute('data-fecha');
    let pressTimer = null;
    let longPressed = false;

    const startPress = () => {
      longPressed = false;
      pressTimer = setTimeout(() => {
        longPressed = true;
        if (!esFamiliar && cache.registros[fStr]) {
          abrirMenuContextualDia(fStr);
        }
      }, 550);
    };
    const cancelPress = () => {
      if (pressTimer) clearTimeout(pressTimer);
    };

    cell.addEventListener('touchstart', startPress, { passive: true });
    cell.addEventListener('touchend', cancelPress);
    cell.addEventListener('touchmove', cancelPress);
    cell.addEventListener('contextmenu', (e) => {
      e.preventDefault();
      if (!esFamiliar && cache.registros[fStr]) {
        abrirMenuContextualDia(fStr);
      }
    });

    cell.onclick = () => {
      if (longPressed) return;
      const reg = cache.registros[fStr];
      if (reg && reg.turno) {
        state.detalleParams = {
          turno: reg.turno,
          tipo: reg.tipo || '',
          fecha: fStr,
          soloLectura: esFamiliar
        };
        state.screen = 'detalle';
        render();
      } else if (!esFamiliar) {
        abrirModalAsignarTurno(fStr);
      }
    };
  });
}

// =========================================================================
// 🗂️ MODAL ASIGNAR TURNO Y MENÚ CONTEXTUAL
// =========================================================================
function esDiaFestivoOSdf(fStr) {
  const parts = fStr.split('-');
  const d = new Date(parseInt(parts[0], 10), parseInt(parts[1], 10) - 1, parseInt(parts[2], 10));
  const w = d.getDay() || 7;
  return w === 6 || w === 7 || cache.festivosFechas.has(fStr);
}

async function asignarTurnoADia(fStr, turno, tipo) {
  const anterior = cache.registros[fStr];
  const tActual = cache.turnos[`${turno}-${tipo}`] || cache.turnos[turno];
  const hasiera = tActual?.hasiera || '';
  const amaiera = tActual?.amaiera || '';
  let lanOrduak = Number(tActual?.lan_orduak || 0);
  if (lanOrduak <= 0 && hasiera && amaiera) {
    lanOrduak = diffMinutos(hasiera, amaiera);
  }

  runSQL(`
    INSERT OR REPLACE INTO registro_diario
    (fecha, turno, tipo, hasiera, amaiera, lan_orduak, observaciones, ajuste_minutos, es_bru)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
  `, [
    fStr,
    turno,
    tipo,
    hasiera,
    amaiera,
    lanOrduak,
    anterior?.observaciones || '',
    anterior?.ajuste_minutos || 0,
    anterior?.es_bru || 0
  ]);

  await guardarDBEnIDB();
  recargarCaches();
}

function abrirMenuContextualDia(fStr) {
  const reg = cache.registros[fStr];
  if (!reg) return;

  const backdrop = document.createElement('div');
  backdrop.className = 'modal-backdrop';
  backdrop.innerHTML = `
    <div class="modal-box" style="padding:12px;">
      <div style="padding:10px 12px;font-weight:700;font-size:15px;border-bottom:1px solid #eee;">
        ${fStr} · ${reg.turno} (${reg.tipo})
      </div>
      <div class="menu-item" id="ctx-detalle" style="padding:14px 12px;cursor:pointer;display:flex;align-items:center;gap:12px;">
        <span>ℹ️</span> <span>Ikusi xehetasunak: ${reg.turno} (${reg.tipo})</span>
      </div>
      <div class="menu-item" id="ctx-cambiar" style="padding:14px 12px;cursor:pointer;display:flex;align-items:center;gap:12px;">
        <span>🔄</span>
        <div>
          <div style="font-weight:600;">Aldatu egun honetako txanda</div>
          <div style="font-size:12px;color:#666;">Hautatu beste txanda bat okertu bazara</div>
        </div>
      </div>
      <div class="menu-item" id="ctx-borrar" style="padding:14px 12px;cursor:pointer;display:flex;align-items:center;gap:12px;color:#d32f2f;">
        <span>🗑️</span>
        <div>
          <div style="font-weight:600;">Ezabatu egun honetako txanda</div>
          <div style="font-size:12px;color:#666;">Utzi egun hau libre txandarik gabe</div>
        </div>
      </div>
    </div>
  `;
  backdrop.onclick = (e) => { if (e.target === backdrop) backdrop.remove(); };
  document.body.appendChild(backdrop);

  document.getElementById('ctx-detalle').onclick = () => {
    backdrop.remove();
    state.detalleParams = { turno: reg.turno, tipo: reg.tipo || '', fecha: fStr, soloLectura: false };
    state.screen = 'detalle';
    render();
  };
  document.getElementById('ctx-cambiar').onclick = () => {
    backdrop.remove();
    abrirModalAsignarTurno(fStr);
  };
  document.getElementById('ctx-borrar').onclick = async () => {
    backdrop.remove();
    if (confirm(`${fStr} egunari esleitutako txanda ezabatuko da.\n\nJarraitu?`)) {
      runSQL("DELETE FROM registro_diario WHERE fecha = ?", [fStr]);
      await guardarDBEnIDB();
      recargarCaches();
      render();
    }
  };
}

function abrirModalAsignarTurno(fStr, onSelectedCallback = null) {
  const esFestivo = esDiaFestivoOSdf(fStr);
  let tabActiva = 'Negua';
  let filtroInv = esFestivo ? 'SDF' : 'LAB';

  const parts = fStr.split('-');
  const fechaCorta = `${parseInt(parts[2], 10)}/${parseInt(parts[1], 10)}`;

  const backdrop = document.createElement('div');
  backdrop.className = 'modal-backdrop';

  function renderModalContent() {
    const turnosInvierno = [];
    const turnosOtros = [];
    for (const t of cache.turnosLista) {
      const tp = String(t.tipo || '').trim().toUpperCase();
      if (tp === 'LAB' || tp === 'SDF') turnosInvierno.push(t);
      else turnosOtros.push(t);
    }

    const labCount = turnosInvierno.filter(t => String(t.tipo).toUpperCase() === 'LAB').length;
    const sdfCount = turnosInvierno.filter(t => String(t.tipo).toUpperCase() === 'SDF').length;

    let listaMostrar = tabActiva === 'Negua' ? turnosInvierno : turnosOtros;
    if (tabActiva === 'Negua') {
      if (filtroInv === 'LAB') listaMostrar = turnosInvierno.filter(t => String(t.tipo).toUpperCase() === 'LAB');
      else if (filtroInv === 'SDF') listaMostrar = turnosInvierno.filter(t => String(t.tipo).toUpperCase() === 'SDF');
    }

    backdrop.innerHTML = `
      <div class="modal-box" style="height:560px;">
        <div style="padding:14px 18px 8px;display:flex;justify-content:space-between;align-items:center;">
          <div style="font-size:17px;font-weight:700;">Txanda esleitu (${fechaCorta})</div>
          <button class="icon-btn" id="modal-close">✕</button>
        </div>
        <div class="tabs">
          <div class="tab ${tabActiva === 'Negua' ? 'active' : ''}" data-tab="Negua">Negua (${turnosInvierno.length})</div>
          <div class="tab ${tabActiva === 'Besteak' ? 'active' : ''}" data-tab="Besteak">Besteak (${turnosOtros.length})</div>
        </div>
        ${tabActiva === 'Negua' ? `
          <div class="chip-row">
            <div class="chip ${filtroInv === 'TODOS' ? 'active' : ''}" data-chip="TODOS">Denak (${turnosInvierno.length})</div>
            <div class="chip ${filtroInv === 'LAB' ? 'active' : ''}" data-chip="LAB">LAB (${labCount})</div>
            <div class="chip ${filtroInv === 'SDF' ? 'active' : ''}" data-chip="SDF">SDF (${sdfCount})</div>
          </div>
        ` : ''}
        <div style="flex:1;overflow-y:auto;">
          ${listaMostrar.length === 0 ? `
            <div style="padding:32px;text-align:center;color:#757575;font-size:13px;">
              Ez dago txandarik eskuragarri.<br>Beheko 'Txanda berria sortu' erabil dezakezu.
            </div>
          ` : listaMostrar.map((t, idx) => {
            const col = cache.colores[`${t.turno}-${t.tipo}`] ?? cache.colores[t.turno] ?? 0xFF546E7A;
            const bg = argbToCss(col);
            const fg = contrasteTexto(col);
            const h1 = horaCorta(t.hasiera);
            const h2 = horaCorta(t.amaiera);
            const esMan = Number(t.es_manual || 0) === 1;
            return `
              <div class="turno-row" data-idx="${idx}" style="display:flex;align-items:center;justify-content:space-between;padding:10px 16px;border-bottom:1px solid #f0f0f0;cursor:pointer;">
                <div style="display:flex;align-items:center;gap:12px;">
                  <div style="width:30px;height:30px;border-radius:50%;background:${bg};color:${fg};display:flex;align-items:center;justify-content:center;font-weight:700;font-size:12px;">
                    ${String(t.turno || '?')[0]}
                  </div>
                  <div>
                    <div style="display:flex;align-items:center;gap:6px;">
                      <span style="font-weight:700;font-size:15px;">${t.turno}</span>
                      <span style="font-size:10px;font-weight:700;padding:1px 5px;border-radius:4px;background:#eceff1;color:#263238;">${t.tipo}</span>
                      ${esMan ? `<span style="font-size:9px;font-weight:700;padding:1px 4px;border-radius:3px;background:#e3f2fd;color:#1565c0;">Eskuzkoa</span>` : ''}
                    </div>
                    ${h1 && h2 ? `<div style="font-size:12px;color:#666;margin-top:2px;">${h1} - ${h2}</div>` : ''}
                  </div>
                </div>
                <div style="display:flex;align-items:center;gap:6px;">
                  ${esMan ? `<button class="icon-btn edit-manual-btn" data-idx="${idx}" style="font-size:16px;">✏️</button>` : ''}
                  <span style="color:#9e9e9e;font-size:14px;">❯</span>
                </div>
              </div>
            `;
          }).join('')}
        </div>
        <div id="btn-crear-turno-modal" style="padding:12px 16px;border-top:1px solid #e0e0e0;display:flex;align-items:center;gap:10px;color:#1976d2;font-weight:700;cursor:pointer;">
          <span>➕</span> <span>Txanda berria sortu</span>
        </div>
      </div>
    `;

    backdrop.querySelector('#modal-close').onclick = () => backdrop.remove();
    backdrop.querySelectorAll('.tab').forEach(el => {
      el.onclick = () => {
        tabActiva = el.getAttribute('data-tab');
        renderModalContent();
      };
    });
    backdrop.querySelectorAll('.chip').forEach(el => {
      el.onclick = () => {
        filtroInv = el.getAttribute('data-chip');
        renderModalContent();
      };
    });

    backdrop.querySelectorAll('.edit-manual-btn').forEach(btn => {
      btn.onclick = (e) => {
        e.stopPropagation();
        const t = listaMostrar[Number(btn.getAttribute('data-idx'))];
        backdrop.remove();
        state.nuevoTurnoParams = {
          turnoExistente: t,
          onSaved: async (nuevo) => {
            if (nuevo && !nuevo.eliminado) {
              await asignarTurnoADia(fStr, nuevo.turno, nuevo.tipo);
            }
            state.screen = 'calendario';
            render();
          }
        };
        state.screen = 'nuevo_turno';
        render();
      };
    });

    backdrop.querySelectorAll('.turno-row').forEach(row => {
      row.onclick = async () => {
        const t = listaMostrar[Number(row.getAttribute('data-idx'))];
        const esSDF = String(t.tipo || '').toUpperCase() === 'SDF';
        if (esFestivo && !esSDF) {
          const seguir = confirm(
            `⚠️ Gogoratu, egun hori jaieguna da\n\nEgun hau larunbata, igandea edo urteko jaieguna da, eta '${t.turno} (${t.tipo})' txanda ez da SDF motakoa.\n\nTxanda hau esleitu nahi duzu hala ere?`
          );
          if (!seguir) return;
        }
        backdrop.remove();
        await asignarTurnoADia(fStr, t.turno, t.tipo);
        if (onSelectedCallback) onSelectedCallback(t);
        else render();
      };
    });

    backdrop.querySelector('#btn-crear-turno-modal').onclick = () => {
      backdrop.remove();
      state.nuevoTurnoParams = {
        turnoExistente: null,
        onSaved: async (nuevo) => {
          if (nuevo && !nuevo.eliminado) {
            await asignarTurnoADia(fStr, nuevo.turno, nuevo.tipo);
          }
          state.screen = 'calendario';
          render();
        }
      };
      state.screen = 'nuevo_turno';
      render();
    };
  }

  backdrop.onclick = (e) => { if (e.target === backdrop) backdrop.remove(); };
  document.body.appendChild(backdrop);
  renderModalContent();
}

// =========================================================================
// 📋 2. DETALLE DE TURNO Y ALARMAS
// =========================================================================
function renderDetalleTurno() {
  const { turno, tipo, fecha, soloLectura } = state.detalleParams;
  const app = document.getElementById('app');

  const servicios = queryAll(
    "SELECT * FROM servicios WHERE turno = ? AND tipo = ? ORDER BY orden ASC",
    [turno, tipo]
  );
  const tData = cache.turnos[`${turno}-${tipo}`] || cache.turnos[turno] || {};
  const reg = fecha ? cache.registros[fecha] : null;
  const adjuntos = fecha ? queryAll("SELECT id FROM adjuntos_incidencia WHERE fecha = ?", [fecha]) : [];

  const hIni = horaCorta(reg?.hasiera || tData.hasiera);
  const hFin = horaCorta(reg?.amaiera || tData.amaiera);
  const lanBase = Number(reg?.lan_orduak || tData.lan_orduak || (hIni && hFin ? diffMinutos(hIni, hFin) : 0));
  const ajusteMin = Number(reg?.ajuste_minutos || 0);
  const totalMin = lanBase + ajusteMin;
  const tieneNota = (reg && String(reg.observaciones || '').trim().length > 0) || ajusteMin !== 0 || adjuntos.length > 0;
  const esManual = Number(tData.es_manual || 0) === 1;

  // Alarmas activas de esta fecha
  const alarmasMap = {};
  if (fecha) {
    for (const a of queryAll("SELECT * FROM alarmas_activadas WHERE fecha = ?", [fecha])) {
      alarmasMap[`${a.servicio}|||${a.hora}`] = a;
    }
  }

  app.innerHTML = `
    <div class="appbar">
      <div class="appbar-title">
        <button class="icon-btn" id="btn-back-det">⬅️</button>
        <span>${turno} (${tipo})</span>
      </div>
      <div class="appbar-actions">
        ${!soloLectura && fecha ? `
          <button class="icon-btn" id="btn-det-cambiar" title="Aldatu egun honetako txanda">🔄</button>
          <button class="icon-btn" id="btn-det-borrar" title="Ezabatu eguneko txanda">🗑️</button>
          <button class="icon-btn" id="btn-det-nota" title="${tieneNota ? 'Ikusi/Editatu oharra' : 'Gehitu oharra'}">
            ${tieneNota ? '📝⭐' : '📝'}
          </button>
        ` : ''}
        ${!soloLectura && esManual ? `
          <button class="icon-btn" id="btn-det-edit-man" title="Editatu eskuzko txanda">✏️</button>
        ` : ''}
      </div>
    </div>
    <div class="screen-body" style="padding:8px;">
      ${servicios.length === 0 ? `
        <div style="text-align:center;color:#757575;padding:48px 16px;">
          Ez dago zerbitzurik erregistratuta txanda honetarako.
        </div>
      ` : servicios.map((s, idx) => {
        const nom = String(s.servicio || '');
        const esDescanso = nom.toUpperCase().includes('GELTOKIAREN') || nom.toUpperCase().includes('ATSENALDIA');
        const irteeraOrd = horaCorta(s.irteera_ordua);
        const helmugaOrd = horaCorta(s.helmuga_ordua);
        const nombreServ = nom || `Zerbitzua ${idx}`;
        const claveAlarma = `${nombreServ}|||${s.irteera_ordua || ''}`;
        const alarmaInfo = alarmasMap[claveAlarma];

        if (esDescanso) {
          const prevFin = idx > 0 ? horaCorta(servicios[idx - 1].helmuga_ordua) : '';
          const nextIni = idx + 1 < servicios.length ? horaCorta(servicios[idx + 1].irteera_ordua) : '';
          return `
            <div class="card" style="margin-bottom:6px;padding:10px 12px;">
              <div style="display:flex;justify-content:space-between;align-items:center;">
                <div style="font-weight:700;font-size:13px;">☕ ${nom}</div>
                ${s.des ? `<span style="background:#ffebee;color:#d32f2f;border:1px solid #ffcdd2;padding:2px 7px;border-radius:4px;font-weight:700;font-size:12px;">${s.des} min</span>` : ''}
              </div>
              ${prevFin && nextIni ? `<div style="font-size:11.5px;color:#616161;margin-top:4px;">${prevFin} → ${nextIni}  (Atsedenaldia)</div>` : ''}
            </div>
          `;
        }

        return `
          <div class="card" style="margin-bottom:6px;padding:10px 12px;display:flex;align-items:center;justify-content:space-between;">
            <div style="flex:1;min-width:0;">
              <div style="display:flex;justify-content:space-between;align-items:center;">
                <div style="font-weight:700;font-size:13px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;">
                  ${nom}${s.itinerario ? ' - ' + s.itinerario : ''}${s.oharrak ? ' - ' + s.oharrak : ''}
                </div>
                ${s.des ? `<span style="color:#d32f2f;font-weight:700;font-size:15px;margin-left:6px;">${s.des}</span>` : ''}
              </div>
              <div style="font-size:11.5px;color:#555;margin-top:3px;">
                ${irteeraOrd} → ${helmugaOrd} &nbsp; ${s.irteera || ''} → ${s.helmuga || ''}
              </div>
            </div>
            ${!soloLectura && fecha && s.irteera_ordua ? `
              <button class="icon-btn btn-alarma-serv" data-serv="${nombreServ}" data-hora="${s.irteera_ordua}"
                style="${alarmaInfo ? 'background:#ffecb3;border:1.5px solid #ff8f00;' : ''}">
                ${alarmaInfo ? '🔔' : '⏰'}
              </button>
            ` : ''}
          </div>
        `;
      }).join('')}
    </div>
    ${hIni && hFin ? `
      <div style="background:#fff;border-top:1px solid #e0e0e0;padding:10px 16px calc(10px + var(--safe-bottom));display:flex;justify-content:space-between;align-items:center;">
        <div style="font-size:14px;font-weight:700;">Lanaldia: ${hIni} → ${hFin}</div>
        <div style="display:flex;align-items:center;gap:6px;">
          ${totalMin > 0 ? `<span style="font-size:14px;font-weight:700;color:#455a64;">⏱️ ${formatearHorasMin(totalMin)}</span>` : ''}
          ${ajusteMin !== 0 ? `
            <span style="font-size:11px;font-weight:700;padding:2px 6px;border-radius:5px;background:${ajusteMin > 0 ? '#e8f5e9' : '#ffebee'};color:${ajusteMin > 0 ? '#2e7d32' : '#c62828'};">
              ${ajusteMin > 0 ? '+' + ajusteMin : ajusteMin} min
            </span>
          ` : ''}
        </div>
      </div>
    ` : ''}
  `;

  document.getElementById('btn-back-det').onclick = () => {
    state.screen = 'calendario';
    render();
  };

  if (!soloLectura && fecha) {
    document.getElementById('btn-det-cambiar').onclick = () => {
      abrirModalAsignarTurno(fecha, (nuevoT) => {
        state.detalleParams.turno = nuevoT.turno;
        state.detalleParams.tipo = nuevoT.tipo;
        render();
      });
    };
    document.getElementById('btn-det-borrar').onclick = async () => {
      if (confirm(`${fecha} egunari esleitutako txanda ezabatuko da.\n\nJarraitu nahi duzu?`)) {
        runSQL("DELETE FROM registro_diario WHERE fecha = ?", [fecha]);
        await guardarDBEnIDB();
        recargarCaches();
        state.screen = 'calendario';
        render();
      }
    };
    document.getElementById('btn-det-nota').onclick = () => {
      state.incidenciaParams = { fecha, turno, tipo };
      state.screen = 'incidencia';
      render();
    };
  }

  if (!soloLectura && esManual) {
    document.getElementById('btn-det-edit-man').onclick = () => {
      state.nuevoTurnoParams = {
        turnoExistente: { ...tData, turno, tipo, hasiera: hIni, amaiera: hFin, lan_orduak: lanBase },
        onSaved: async (mod) => {
          if (mod && mod.eliminado) {
            state.screen = 'calendario';
            render();
            return;
          }
          if (mod && fecha) {
            await asignarTurnoADia(fecha, mod.turno, mod.tipo);
            state.detalleParams.turno = mod.turno;
            state.detalleParams.tipo = mod.tipo;
          }
          state.screen = 'detalle';
          render();
        }
      };
      state.screen = 'nuevo_turno';
      render();
    };
  }

  document.querySelectorAll('.btn-alarma-serv').forEach(btn => {
    btn.onclick = () => {
      const serv = btn.getAttribute('data-serv');
      const hora = btn.getAttribute('data-hora');
      gestionarAlarmaPWA(fecha, serv, hora);
    };
  });
}

function gestionarAlarmaPWA(fecha, nombreServ, horaServicio) {
  const clave = `${nombreServ}|||${horaServicio}`;
  const existentes = queryAll("SELECT * FROM alarmas_activadas WHERE fecha = ? AND servicio = ? AND hora = ?", [fecha, nombreServ, horaServicio]);

  if (existentes.length > 0) {
    if (confirm(`🔔 Alarma aktiboa (${existentes[0].hora_alarma || horaCorta(horaServicio)})\n\nAlarma ezabatu nahi duzu?`)) {
      runSQL("DELETE FROM alarmas_activadas WHERE fecha = ? AND servicio = ? AND hora = ?", [fecha, nombreServ, horaServicio]);
      guardarDBEnIDB();
      recargarCaches();
      render();
      showToast(`Alarma ezabatuta: ${nombreServ}`);
    }
    return;
  }

  const p = String(horaServicio).split(':');
  if (p.length < 2) return;
  const hBase = parseInt(p[0], 10);
  const mBase = parseInt(p[1], 10);

  const backdrop = document.createElement('div');
  backdrop.className = 'modal-backdrop';

  const calcHora = (minAntes) => {
    let t = hBase * 60 + mBase - minAntes;
    if (t < 0) t += 24 * 60;
    return `${pad2(Math.floor(t / 60))}:${pad2(t % 60)}`;
  };

  backdrop.innerHTML = `
    <div class="modal-box" style="padding:18px;">
      <div style="font-size:17px;font-weight:700;">⏰ Sortu alarma</div>
      <div style="font-size:12.5px;color:#666;margin-top:2px;">${nombreServ} · Irteera: ${horaCorta(horaServicio)}</div>
      <div style="font-size:13px;margin:14px 0 10px;">Zenbat denbora lehenago nahi duzu alarma?</div>
      ${[1, 5, 8].map(m => `
        <div class="opcion-alarma" data-min="${m}" style="background:#fff8e1;border:1px solid #ffca28;border-radius:10px;padding:12px 14px;margin-bottom:8px;display:flex;justify-content:space-between;font-weight:700;cursor:pointer;">
          <span>⏰ ${m} min lehenago</span>
          <span style="color:#ff6f00;">Jo: ${calcHora(m)}</span>
        </div>
      `).join('')}
      <button class="btn btn-outline" id="btn-cancel-al" style="margin-top:6px;">Utzi</button>
    </div>
  `;
  backdrop.onclick = (e) => { if (e.target === backdrop) backdrop.remove(); };
  document.body.appendChild(backdrop);

  document.getElementById('btn-cancel-al').onclick = () => backdrop.remove();
  backdrop.querySelectorAll('.opcion-alarma').forEach(el => {
    el.onclick = async () => {
      const minAntes = Number(el.getAttribute('data-min'));
      const horaStr = calcHora(minAntes);
      const [ha, ma] = horaStr.split(':').map(Number);
      const ahora = new Date();
      let disparo = new Date(ahora.getFullYear(), ahora.getMonth(), ahora.getDate(), ha, ma, 0);
      if (disparo <= ahora) disparo = new Date(disparo.getTime() + 86400000);

      runSQL(`
        INSERT OR REPLACE INTO alarmas_activadas (fecha, servicio, hora, hora_alarma, fecha_disparo)
        VALUES (?, ?, ?, ?, ?)
      `, [fecha, nombreServ, horaServicio, horaStr, disparo.toISOString()]);

      await guardarDBEnIDB();
      recargarCaches();
      backdrop.remove();
      render();
      showToast(`Alarma programatuta: ${horaStr} (${nombreServ})`, '#2e7d32');
    };
  });
}

// =========================================================================
// 📝 3. INCIDENCIAS DEL DÍA (OHARRAK, FOTOS, ARCHIVOS Y AJUSTE)
// =========================================================================
function renderIncidenciaDia() {
  const { fecha, turno, tipo } = state.incidenciaParams;
  const app = document.getElementById('app');

  const reg = cache.registros[fecha] || {};
  const tData = cache.turnos[`${turno}-${tipo}`] || cache.turnos[turno] || {};
  const hIni = horaCorta(reg.hasiera || tData.hasiera);
  const hFin = horaCorta(reg.amaiera || tData.amaiera);
  const minBase = Number(reg.lan_orduak || tData.lan_orduak || (hIni && hFin ? diffMinutos(hIni, hFin) : 0));

  let notasVal = String(reg.observaciones || '');
  let ajusteMin = Number(reg.ajuste_minutos || 0);

  function pintarPantalla() {
    const adjuntos = queryAll("SELECT id, fecha, nombre, tipo, datos, creado_en FROM adjuntos_incidencia WHERE fecha = ? ORDER BY id ASC", [fecha]);
    const minFinales = minBase + ajusteMin;

    app.innerHTML = `
      <div class="appbar">
        <div class="appbar-title">
          <button class="icon-btn" id="btn-back-inc">⬅️</button>
          <div>
            <div style="font-size:16px;font-weight:700;">Eguneko oharrak</div>
            <div style="font-size:12px;color:#666;font-weight:500;">${fecha} · ${turno} (${tipo})</div>
          </div>
        </div>
        <div class="appbar-actions">
          <button class="icon-btn" id="btn-save-inc-top" title="Gorde">✔️</button>
        </div>
      </div>
      <div class="screen-body">
        <div class="card" style="background:#eceff1;border-color:#cfd8dc;display:flex;justify-content:space-between;align-items:center;">
          <div>
            <div style="font-weight:700;font-size:15px;">Txanda: ${turno} (${tipo})</div>
            ${hIni && hFin ? `<div style="font-size:13px;color:#555;">Ordutegia: ${hIni} - ${hFin}</div>` : ''}
          </div>
          ${minBase > 0 ? `<div style="background:#37474f;color:#fff;padding:5px 10px;border-radius:6px;font-weight:700;font-size:13px;">Oinarria: ${formatearHorasMin(minBase)}</div>` : ''}
        </div>

        <div style="font-weight:700;font-size:16px;margin-top:16px;">📝 Zerbait gertatu da gaur?</div>
        <div style="font-size:12.5px;color:#666;margin:4px 0 8px;">Hemen zerbait idazten baduzu, ⭐ bat agertuko da egunaren ondoan egutegian.</div>
        <textarea id="txt-notas" class="input-field" rows="4" placeholder="Adib: Trafiko handia 4. linean (+15 min)...">${notasVal}</textarea>

        <div style="font-weight:700;font-size:15px;margin-top:18px;">📎 Dokumentuak eta argazkiak</div>
        <div style="display:flex;gap:10px;margin-top:8px;">
          <label class="btn btn-outline" style="flex:1;color:#00695c;border-color:#80cbc4;">
            📷 Atera argazkia
            <input type="file" id="input-camara" accept="image/*" capture="environment" style="display:none;">
          </label>
          <label class="btn btn-outline" style="flex:1;color:#283593;border-color:#9fa8da;">
            📄 Erantsi fitxategia
            <input type="file" id="input-archivo" style="display:none;">
          </label>
        </div>

        ${adjuntos.length > 0 ? `
          <div class="card" style="margin-top:10px;padding:4px 8px;">
            ${adjuntos.map(adj => `
              <div style="display:flex;align-items:center;justify-content:space-between;padding:8px 4px;border-bottom:1px solid #eee;">
                <div class="ver-adjunto" data-id="${adj.id}" style="display:flex;align-items:center;gap:10px;flex:1;min-width:0;cursor:pointer;">
                  <span style="font-size:20px;">${adj.tipo === 'imagen' ? '🖼️' : '📄'}</span>
                  <div style="overflow:hidden;text-overflow:ellipsis;white-space:nowrap;">
                    <div style="font-weight:600;font-size:13px;">${adj.nombre}</div>
                    <div style="font-size:11px;color:#666;">Sakatu irekitzeko / partekatzeko</div>
                  </div>
                </div>
                <button class="icon-btn del-adjunto" data-id="${adj.id}" style="color:#d32f2f;">🗑️</button>
              </div>
            `).join('')}
          </div>
        ` : ''}

        <div style="font-weight:700;font-size:16px;margin-top:22px;">⏱️ Lanaldiaren doikuntza (+ / - denbora)</div>
        <div style="font-size:12.5px;color:#666;margin:4px 0 10px;">Gehitu denbora lanaldia luzatu bada edo kendu denbora berandu iritsi bazara edo lehenago irten bazara.</div>

        <div class="card" style="background:${ajusteMin > 0 ? '#e8f5e9' : (ajusteMin < 0 ? '#ffebee' : '#f5f5f5')};display:flex;justify-content:space-between;align-items:center;">
          <div style="font-size:16px;font-weight:700;color:${ajusteMin > 0 ? '#1b5e20' : (ajusteMin < 0 ? '#b71c1c' : '#212121')};">
            ${ajusteMin > 0 ? `+${ajusteMin} min (${formatearHorasMin(ajusteMin)})` : (ajusteMin < 0 ? `${ajusteMin} min (${formatearHorasMin(ajusteMin)})` : '0 min (Doikuntzarik gabe)')}
          </div>
          ${ajusteMin !== 0 ? `<button id="btn-reset-aj" style="background:none;border:none;color:#1976d2;font-weight:700;cursor:pointer;">0-ra jarri</button>` : ''}
        </div>

        <div style="display:flex;align-items:center;gap:6px;flex-wrap:wrap;margin-bottom:8px;">
          <span style="font-weight:700;font-size:12.5px;">Kendu:</span>
          ${[-60, -30, -15, -5].map(d => `<button class="chip btn-delta" data-delta="${d}" style="color:#c62828;border-color:#ef9a9a;background:#ffebee;">${d}m</button>`).join('')}
        </div>
        <div style="display:flex;align-items:center;gap:6px;flex-wrap:wrap;margin-bottom:14px;">
          <span style="font-weight:700;font-size:12.5px;">Gehitu:</span>
          ${[5, 15, 30, 45, 60].map(d => `<button class="chip btn-delta" data-delta="${d}" style="color:#2e7d32;border-color:#a5d6a7;background:#e8f5e9;">+${d}m</button>`).join('')}
        </div>

        ${minBase > 0 ? `
          <div class="card" style="background:#fff8e1;border-color:#ffe082;display:flex;justify-content:space-between;align-items:center;">
            <span style="font-weight:700;font-size:14px;">Azken lanaldia guztira:</span>
            <span style="font-weight:900;font-size:16px;color:#ff6f00;">${formatearHorasMin(minFinales)}</span>
          </div>
        ` : ''}

        <button class="btn btn-primary" id="btn-save-inc" style="margin-top:16px;">💾 Gorde aldaketak</button>
      </div>
    `;

    const txtEl = document.getElementById('txt-notas');
    txtEl.oninput = () => { notasVal = txtEl.value; };

    const guardarSalir = async () => {
      notasVal = txtEl.value.trim();
      runSQL("UPDATE registro_diario SET observaciones = ?, ajuste_minutos = ? WHERE fecha = ?", [notasVal, ajusteMin, fecha]);
      await guardarDBEnIDB();
      recargarCaches();
      showToast("Oharrak eta doikuntza ondo gorde dira", "#2e7d32");
      state.screen = 'detalle';
      render();
    };

    document.getElementById('btn-back-inc').onclick = () => {
      state.screen = 'detalle';
      render();
    };
    document.getElementById('btn-save-inc-top').onclick = guardarSalir;
    document.getElementById('btn-save-inc').onclick = guardarSalir;

    if (document.getElementById('btn-reset-aj')) {
      document.getElementById('btn-reset-aj').onclick = () => {
        ajusteMin = 0;
        pintarPantalla();
      };
    }

    document.querySelectorAll('.btn-delta').forEach(b => {
      b.onclick = () => {
        ajusteMin += Number(b.getAttribute('data-delta'));
        pintarPantalla();
      };
    });

    const manejarArchivo = async (file, forzarImagen) => {
      if (!file) return;
      const buf = await file.arrayBuffer();
      const bytes = new Uint8Array(buf);
      const esImg = forzarImagen || /\.(jpg|jpeg|png|webp|gif|heic)$/i.test(file.name);
      runSQL(
        "INSERT INTO adjuntos_incidencia (fecha, nombre, tipo, ruta_local, datos, creado_en) VALUES (?, ?, ?, ?, ?, ?)",
        [fecha, file.name, esImg ? 'imagen' : 'archivo', '', bytes, new Date().toISOString()]
      );
      await guardarDBEnIDB();
      recargarCaches();
      pintarPantalla();
      showToast(`Erantsita: ${file.name}`, '#00695c');
    };

    document.getElementById('input-camara').onchange = (e) => manejarArchivo(e.target.files[0], true);
    document.getElementById('input-archivo').onchange = (e) => manejarArchivo(e.target.files[0], false);

    document.querySelectorAll('.del-adjunto').forEach(btn => {
      btn.onclick = async () => {
        const id = Number(btn.getAttribute('data-id'));
        if (confirm("Fitxategia ezabatu?")) {
          runSQL("DELETE FROM adjuntos_incidencia WHERE id = ?", [id]);
          await guardarDBEnIDB();
          recargarCaches();
          pintarPantalla();
        }
      };
    });

    document.querySelectorAll('.ver-adjunto').forEach(el => {
      el.onclick = () => {
        const id = Number(el.getAttribute('data-id'));
        const rows = queryAll("SELECT * FROM adjuntos_incidencia WHERE id = ?", [id]);
        if (!rows.length || !rows[0].datos) return;
        const item = rows[0];
        const blob = new Blob([item.datos]);
        const url = URL.createObjectURL(blob);
        const a = document.createElement('a');
        a.href = url;
        a.download = item.nombre || 'fitxategia';
        a.target = '_blank';
        a.click();
      };
    });
  }

  pintarPantalla();
}

// =========================================================================
// ⚙️ 4. PANTALLA DE AJUSTES (EZARPENAK) Y SUBPANTALLAS
// =========================================================================
function renderAjustes() {
  const app = document.getElementById('app');
  const items = [
    { id: 'semanas', icon: '📅', title: 'Orientazio-astea', sub: 'Oinarrizko astea eta txandakatzea konfiguratu (1 - 18)' },
    { id: 'colores', icon: '🎨', title: 'Koloreak konfiguratu', sub: 'Txanda eta mota bakoitzaren kolorea pertsonalizatu' },
    { id: 'copia', icon: '☁️', title: 'Segurtasun kopia', sub: 'Txandak esportatu eta inportatu (.db fitxategia)' },
    { id: 'bru', icon: '⏱️', title: 'BRU orduak', sub: 'Hautatu egun bat bere lan-orduak zenbaketa orokorretik kentzeko' },
    { id: 'busqueda', icon: '🔍', title: 'Zerbitzuaren bilaketa', sub: 'Bilatu zerbitzu zenbaki bat bere ordutegia eta ibilbidea ikusteko' },
    { id: 'festivos', icon: '🎉', title: 'Urteko jaiegunak', sub: 'Markatu urteko jaiegunak egutegian SDF abisuak jasotzeko' }
  ];

  app.innerHTML = `
    <div class="appbar">
      <div class="appbar-title">
        <button class="icon-btn" id="btn-back-aj">⬅️</button>
        <span>Ezarpenak</span>
      </div>
    </div>
    <div class="screen-body">
      ${items.map(it => `
        <div class="card aj-item" data-screen="${it.id}" style="display:flex;align-items:center;justify-content:space-between;cursor:pointer;">
          <div style="display:flex;align-items:center;gap:14px;">
            <span style="font-size:26px;">${it.icon}</span>
            <div>
              <div style="font-weight:700;font-size:15px;">${it.title}</div>
              <div style="font-size:12px;color:#666;margin-top:2px;">${it.sub}</div>
            </div>
          </div>
          <span style="color:#9e9e9e;">❯</span>
        </div>
      `).join('')}
    </div>
  `;

  document.getElementById('btn-back-aj').onclick = () => {
    state.screen = 'calendario';
    render();
  };
  document.querySelectorAll('.aj-item').forEach(el => {
    el.onclick = () => {
      state.screen = el.getAttribute('data-screen');
      render();
    };
  });
}

// 4.1 Configurar Semanas (1-18)
function renderConfigurarSemanas() {
  const app = document.getElementById('app');
  const hoy = new Date();
  const semISO = calcularSemanaISO(hoy);
  const actualOri = calcularSemanaOrientativa(hoy) || 1;

  app.innerHTML = `
    <div class="appbar">
      <div class="appbar-title">
        <button class="icon-btn" id="btn-back-sem">⬅️</button>
        <span>Orientazio-astea</span>
      </div>
    </div>
    <div class="screen-body">
      <div class="card">
        <div style="font-weight:700;font-size:15px;">Gaurko aste erreala (ISO): ${semISO}</div>
        <div style="font-size:13px;color:#666;margin-top:6px;">Aukeratu zein orientazio-aste (1 - 18) dagokion gaurko asteari:</div>
        <select id="sel-sem-ori" class="input-field" style="margin-top:12px;font-weight:700;font-size:16px;">
          ${Array.from({ length: 18 }, (_, i) => i + 1).map(n => `
            <option value="${n}" ${n === actualOri ? 'selected' : ''}>${n}. astea</option>
          `).join('')}
        </select>
        <button class="btn btn-primary" id="btn-save-sem" style="margin-top:18px;">Gorde</button>
      </div>
    </div>
  `;

  document.getElementById('btn-back-sem').onclick = () => { state.screen = 'ajustes'; render(); };
  document.getElementById('btn-save-sem').onclick = async () => {
    const val = Number(document.getElementById('sel-sem-ori').value);
    const w = hoy.getDay() || 7;
    const lunes = new Date(hoy.getFullYear(), hoy.getMonth(), hoy.getDate() - (w - 1));
    runSQL(`
      INSERT OR REPLACE INTO config_semanas (id, semana_real_base, semana_orientativa_base, fecha_base)
      VALUES (1, ?, ?, ?)
    `, [semISO, val, fechaStr(lunes)]);
    await guardarDBEnIDB();
    recargarCaches();
    showToast("Astea ondo gorde da", "#2e7d32");
    state.screen = 'ajustes';
    render();
  };
}

// 4.2 Configurar Colores
function renderColoresTurno() {
  const app = document.getElementById('app');
  const lab = cache.turnosLista.filter(t => String(t.tipo).toUpperCase() === 'LAB');
  const sdf = cache.turnosLista.filter(t => String(t.tipo).toUpperCase() === 'SDF');
  const otros = cache.turnosLista.filter(t => !['LAB', 'SDF'].includes(String(t.tipo).toUpperCase()));

  const lista = state.coloresTab === 'LAB' ? lab : (state.coloresTab === 'SDF' ? sdf : otros);

  app.innerHTML = `
    <div class="appbar">
      <div class="appbar-title">
        <button class="icon-btn" id="btn-back-col">⬅️</button>
        <span>Txanden koloreak</span>
      </div>
    </div>
    <div class="tabs">
      <div class="tab ${state.coloresTab === 'LAB' ? 'active' : ''}" data-t="LAB">LAB (${lab.length})</div>
      <div class="tab ${state.coloresTab === 'SDF' ? 'active' : ''}" data-t="SDF">SDF (${sdf.length})</div>
      ${otros.length ? `<div class="tab ${state.coloresTab === 'OTROS' ? 'active' : ''}" data-t="OTROS">Besteak (${otros.length})</div>` : ''}
    </div>
    <div class="screen-body" style="display:grid;grid-template-columns:repeat(2,1fr);gap:8px;align-content:start;">
      ${lista.map((t, idx) => {
        const key = `${t.turno}-${t.tipo}`;
        const col = cache.colores[key] ?? cache.colores[t.turno] ?? 0xFF546E7A;
        const bg = argbToCss(col);
        const fg = contrasteTexto(col);
        return `
          <div class="col-card" data-idx="${idx}" style="background:${bg};color:${fg};padding:10px;border-radius:8px;cursor:pointer;display:flex;flex-direction:column;justify-content:space-between;min-height:68px;">
            <div style="display:flex;justify-content:space-between;align-items:center;">
              <span style="font-weight:900;font-size:16px;">${t.turno}</span>
              <span style="font-size:10px;font-weight:700;opacity:0.9;">${t.tipo}</span>
            </div>
            <div style="font-size:11px;opacity:0.9;">${horaCorta(t.hasiera)} - ${horaCorta(t.amaiera)}</div>
          </div>
        `;
      }).join('')}
    </div>
  `;

  document.getElementById('btn-back-col').onclick = () => { state.screen = 'ajustes'; render(); };
  document.querySelectorAll('.tab').forEach(el => {
    el.onclick = () => { state.coloresTab = el.getAttribute('data-t'); render(); };
  });
  document.querySelectorAll('.col-card').forEach(card => {
    card.onclick = () => {
      const t = lista[Number(card.getAttribute('data-idx'))];
      abrirSelectorPaleta(t);
    };
  });
}

function abrirSelectorPaleta(t) {
  const backdrop = document.createElement('div');
  backdrop.className = 'modal-backdrop';
  backdrop.innerHTML = `
    <div class="modal-box" style="padding:18px;">
      <div style="font-weight:700;font-size:17px;margin-bottom:12px;">Kolorea: ${t.turno} (${t.tipo})</div>
      <div style="display:flex;flex-wrap:wrap;gap:8px;justify-content:center;max-height:340px;overflow-y:auto;">
        ${PALETA_COLORES.map(c => `
          <div class="swatch" data-col="${c}" style="width:38px;height:38px;border-radius:6px;background:${argbToCss(c)};cursor:pointer;border:1px solid rgba(0,0,0,0.15);"></div>
        `).join('')}
      </div>
      <button class="btn btn-outline" id="close-pal" style="margin-top:14px;">Utzi</button>
    </div>
  `;
  backdrop.onclick = (e) => { if (e.target === backdrop) backdrop.remove(); };
  document.body.appendChild(backdrop);
  document.getElementById('close-pal').onclick = () => backdrop.remove();
  backdrop.querySelectorAll('.swatch').forEach(s => {
    s.onclick = async () => {
      const c = Number(s.getAttribute('data-col'));
      runSQL("INSERT OR REPLACE INTO config_colores (letra, tipo, color) VALUES (?, ?, ?)", [t.turno, t.tipo, c]);
      await guardarDBEnIDB();
      recargarCaches();
      backdrop.remove();
      render();
    };
  });
}

// 4.3 Copia de Seguridad (.db)
function renderCopiaSeguridad() {
  const app = document.getElementById('app');
  app.innerHTML = `
    <div class="appbar">
      <div class="appbar-title">
        <button class="icon-btn" id="btn-back-cop">⬅️</button>
        <span>Segurtasun Kopia</span>
      </div>
    </div>
    <div class="screen-body">
      <div class="card">
        <div style="font-weight:700;font-size:15px;">1. Segurtasun kopia sortu (.db)</div>
        <div style="font-size:12.5px;color:#666;margin:6px 0 14px;">Esportatu zure txandak WhatsAppez, AirDropez edo Fitxategietan gordetzeko.</div>
        <button class="btn btn-primary" id="btn-export-db">⬆️ Esportatu eta Partekatu</button>
      </div>
      <div class="card">
        <div style="font-weight:700;font-size:15px;">2. Segurtasun kopia berreskuratu (.db)</div>
        <div style="font-size:12.5px;color:#666;margin:6px 0 14px;">Kargatu Androidetik edo PCtik sortutako .db fitxategi bat zure egutegia eguneratzeko.</div>
        <button class="btn btn-outline" id="btn-import-db">⬇️ Kopia berreskuratu (Inportatu)</button>
      </div>
    </div>
  `;
  document.getElementById('btn-back-cop').onclick = () => { state.screen = 'ajustes'; render(); };
  document.getElementById('btn-export-db').onclick = exportarArchivoDB;
  document.getElementById('btn-import-db').onclick = importarArchivoDB;
}

async function exportarArchivoDB() {
  const bytes = db.export();
  const ahora = new Date();
  const fileName = `korreturnos_copia_${fechaStr(ahora)}_${pad2(ahora.getHours())}${pad2(ahora.getMinutes())}.db`;
  const file = new File([bytes], fileName, { type: 'application/octet-stream' });

  if (navigator.canShare && navigator.canShare({ files: [file] })) {
    try {
      await navigator.share({ files: [file], title: 'Korreturnos segurtasun kopia' });
      return;
    } catch (_) {}
  }

  const url = URL.createObjectURL(file);
  const a = document.createElement('a');
  a.href = url;
  a.download = fileName;
  a.click();
  showToast("Segurtasun kopia deskargatu da", "#2e7d32");
}

function importarArchivoDB() {
  const input = document.createElement('input');
  input.type = 'file';
  input.onchange = async (e) => {
    const file = e.target.files[0];
    if (!file) return;
    try {
      const buf = await file.arrayBuffer();
      const nuevoDb = new SQL.Database(new Uint8Array(buf));
      const tablas = nuevoDb.exec("SELECT name FROM sqlite_master WHERE type='table'");
      const nombres = new Set((tablas[0]?.values || []).map(v => v[0]));
      if (!nombres.has('turnos') || !nombres.has('registro_diario')) {
        alert("Hautatutako fitxategia ez da baliozko Korreturnos .db kopia bat.");
        return;
      }
      db = nuevoDb;
      asegurarEsquema();
      await guardarDBEnIDB();
      recargarCaches();
      showToast("Segurtasun kopia ondo berreskuratu da!", "#2e7d32");
      state.screen = 'calendario';
      render();
    } catch (err) {
      alert("Errorea fitxategia kargatzean: " + err.message);
    }
  };
  input.click();
}

// 4.4 Horas BRU (BRU orduak)
function renderHorasBru() {
  const app = document.getElementById('app');
  const diasBru = queryAll("SELECT * FROM registro_diario WHERE es_bru = 1 ORDER BY fecha DESC");

  app.innerHTML = `
    <div class="appbar">
      <div class="appbar-title">
        <button class="icon-btn" id="btn-back-bru">⬅️</button>
        <span>BRU orduak</span>
      </div>
    </div>
    <div class="screen-body">
      <div class="card" style="background:#f3e5f5;border-color:#ce93d8;color:#4a148c;font-size:13px;">
        Hautatu egutegiko egun bat BRU gisa markatzeko. Egun horretako lan-orduak ez dira hileko ordu guztien zenbaketan kontuan hartuko.
      </div>
      <div class="card">
        <label style="font-weight:700;font-size:14px;display:block;margin-bottom:8px;">Hautatu egutegiko eguna:</label>
        <div style="display:flex;gap:8px;">
          <input type="date" id="input-fecha-bru" class="input-field" value="${fechaStr(new Date())}">
          <button class="btn btn-primary" id="btn-add-bru" style="width:auto;white-space:nowrap;background:#7b1fa2;">Gehitu</button>
        </div>
      </div>
      <div style="font-weight:700;font-size:15px;margin:16px 0 8px;">Markatutako BRU egunak (${diasBru.length})</div>
      ${diasBru.length === 0 ? `
        <div style="text-align:center;color:#757575;padding:32px;">Ez dago BRU egunik markatuta</div>
      ` : diasBru.map(r => {
        const min = calcularMinutosDia(r);
        return `
          <div class="card" style="display:flex;justify-content:space-between;align-items:center;border-color:#ce93d8;">
            <div>
              <div style="font-weight:700;font-size:14px;">${r.fecha} · Txanda ${r.turno} (${r.tipo})</div>
              <div style="font-size:12.5px;color:#6a1b9a;">Kendutako orduak: -${formatearHorasMin(min)}</div>
            </div>
            <button class="icon-btn del-bru" data-fecha="${r.fecha}" style="color:#d32f2f;">🗑️</button>
          </div>
        `;
      }).join('')}
    </div>
  `;

  document.getElementById('btn-back-bru').onclick = () => { state.screen = 'ajustes'; render(); };
  document.getElementById('btn-add-bru').onclick = async () => {
    const fStr = document.getElementById('input-fecha-bru').value;
    if (!fStr) return;
    const reg = cache.registros[fStr];
    if (!reg || !reg.turno) {
      alert(`Aukeratutako egunak (${fStr}) ez du txandarik esleituta egutegian.`);
      return;
    }
    const min = calcularMinutosDia(reg);
    const hTxt = formatearHorasMin(min);
    if (confirm(`BRU orduak (${fStr} · ${reg.turno})\n\nEgun hau ez da ordu guztien zenbaketan kontuan hartuko, eta egun horretan lan egindako orduak (${hTxt}) zenbaketa orokorretik kenduko dira.\n\nAdos zaude?`)) {
      runSQL("UPDATE registro_diario SET es_bru = 1 WHERE fecha = ?", [fStr]);
      await guardarDBEnIDB();
      recargarCaches();
      render();
      showToast(`${fStr} BRU gisa markatu da (-${hTxt})`, '#7b1fa2');
    }
  };

  document.querySelectorAll('.del-bru').forEach(btn => {
    btn.onclick = async () => {
      const fStr = btn.getAttribute('data-fecha');
      if (confirm(`${fStr} eguneko BRU marka kendu?`)) {
        runSQL("UPDATE registro_diario SET es_bru = 0 WHERE fecha = ?", [fStr]);
        await guardarDBEnIDB();
        recargarCaches();
        render();
      }
    };
  });
}

// 4.5 Búsqueda por Servicio (Zerbitzuaren bilaketa)
function renderBusquedaServicio() {
  const app = document.getElementById('app');

  function ejecutarBusqueda(q) {
    state.busquedaQuery = q;
    const limpio = q.trim();
    if (!limpio) {
      state.busquedaResultados = [];
    } else {
      state.busquedaResultados = queryAll(`
        SELECT id, turno, tipo, orden, servicio, irteera_ordua, irteera, helmuga_ordua, helmuga, oharrak, des, itinerario
        FROM servicios
        WHERE servicio IS NOT NULL AND TRIM(servicio) != ''
          AND UPPER(servicio) NOT LIKE '%GELTOKIAREN%'
          AND UPPER(servicio) NOT LIKE '%ATSENALDIA%'
          AND UPPER(servicio) LIKE ?
        ORDER BY CASE WHEN UPPER(TRIM(servicio)) = UPPER(?) THEN 0 ELSE 1 END, turno ASC, tipo ASC, orden ASC
      `, [`%${limpio}%`, limpio]);
    }
    pintarResultados();
  }

  app.innerHTML = `
    <div class="appbar">
      <div class="appbar-title">
        <button class="icon-btn" id="btn-back-bus">⬅️</button>
        <span>Zerbitzuaren bilaketa</span>
      </div>
    </div>
    <div class="screen-body" style="display:flex;flex-direction:column;">
      <input type="search" id="input-bus-serv" class="input-field" placeholder="Zerbitzu zenbakia (Adib: 101, 204...)" value="${state.busquedaQuery}">
      <div id="bus-results" style="margin-top:14px;flex:1;"></div>
    </div>
  `;

  function pintarResultados() {
    const cont = document.getElementById('bus-results');
    const res = state.busquedaResultados;
    if (!state.busquedaQuery.trim()) {
      cont.innerHTML = `<div style="text-align:center;color:#757575;padding:40px 16px;">Idatzi zerbitzu zenbakia bere ordutegia eta ibilbidea ikusteko.</div>`;
      return;
    }
    if (res.length === 0) {
      cont.innerHTML = `<div style="text-align:center;color:#757575;padding:40px 16px;">Ez da '${state.busquedaQuery.trim()}' zerbitzurik aurkitu.</div>`;
      return;
    }
    cont.innerHTML = `
      <div style="font-size:13px;font-weight:700;color:#455a64;margin-bottom:8px;">Aurkitutako zerbitzuak: ${res.length}</div>
      ${res.map((it, idx) => {
        const col = cache.colores[`${it.turno}-${it.tipo}`] ?? cache.colores[it.turno] ?? 0xFF546E7A;
        return `
          <div class="card bus-card" data-idx="${idx}" style="cursor:pointer;">
            <div style="display:flex;justify-content:space-between;align-items:center;">
              <div style="font-weight:700;font-size:15px;">🚍 Zerbitzua: ${it.servicio}${it.itinerario ? ' · ' + it.itinerario : ''}</div>
              <span style="background:${argbToCss(col)};color:${contrasteTexto(col)};padding:3px 9px;border-radius:6px;font-size:12px;font-weight:700;">
                Txanda ${it.turno} (${it.tipo})
              </span>
            </div>
            <hr style="border:none;border-top:1px solid #eee;margin:10px 0;">
            <div style="font-size:13.5px;margin-bottom:4px;">⏱️ <b>Ordutegia:</b> <span style="color:#00695c;font-weight:700;">${horaCorta(it.irteera_ordua)} - ${horaCorta(it.helmuga_ordua)}</span></div>
            <div style="font-size:13.5px;">📍 <b>Ibilbidea:</b> <b>${it.irteera || ''} → ${it.helmuga || ''}</b></div>
          </div>
        `;
      }).join('')}
    `;

    cont.querySelectorAll('.bus-card').forEach(c => {
      c.onclick = () => {
        const it = res[Number(c.getAttribute('data-idx'))];
        state.detalleParams = { turno: it.turno, tipo: it.tipo, fecha: '', soloLectura: true };
        state.screen = 'detalle';
        render();
      };
    });
  }

  document.getElementById('btn-back-bus').onclick = () => { state.screen = 'ajustes'; render(); };
  const inputEl = document.getElementById('input-bus-serv');
  inputEl.oninput = () => ejecutarBusqueda(inputEl.value);
  pintarResultados();
}

// 4.6 Festivos Anuales (Urteko jaiegunak)
function renderFestivosAnuales() {
  const app = document.getElementById('app');
  const anio = state.fechaFestivosVista.getFullYear();
  const mes = state.fechaFestivosVista.getMonth();
  const nombreMes = MESES_EU[mes];

  const primerDia = new Date(anio, mes, 1);
  const ultimoDia = new Date(anio, mes + 1, 0);
  const diaSem = primerDia.getDay() || 7;
  let cursor = new Date(anio, mes, 1 - (diaSem - 1));
  const hoyStr = fechaStr(new Date());

  let filasHTML = '';
  while (cursor <= ultimoDia || cursor.getMonth() === mes) {
    let celdas = '';
    for (let i = 0; i < 7; i++) {
      const d = new Date(cursor.getFullYear(), cursor.getMonth(), cursor.getDate() + i);
      const dStr = fechaStr(d);
      const esMesActual = d.getMonth() === mes;
      const esFestivo = cache.festivosFechas.has(dStr);
      const esHoy = dStr === hoyStr;

      celdas += `
        <div class="fest-cell" data-fecha="${dStr}" style="flex:1;height:42px;margin:2px;border-radius:8px;display:flex;flex-direction:column;align-items:center;justify-content:center;cursor:pointer;
          background:${esFestivo ? '#e53935' : (esMesActual ? '#fff' : '#f3f4f6')};
          color:${esFestivo ? '#fff' : (esMesActual ? '#212121' : '#bdbdbd')};
          border:${esHoy ? '2px solid #000' : '1px solid #e0e0e0'};font-weight:${esFestivo || esHoy ? '700' : '500'};">
          <span style="font-size:13.5px;">${d.getDate()}</span>
          ${esFestivo ? '<span style="font-size:7px;font-weight:900;">JAI</span>' : ''}
        </div>
      `;
    }
    filasHTML += `<div style="display:flex;padding:0 6px;">${celdas}</div>`;
    cursor = new Date(cursor.getFullYear(), cursor.getMonth(), cursor.getDate() + 7);
    if (cursor.getMonth() > mes && (cursor.getDay() || 7) === 1) break;
  }

  const festivosAnio = Array.from(cache.festivosFechas).filter(f => f.startsWith(`${anio}-`)).sort();

  app.innerHTML = `
    <div class="appbar">
      <div class="appbar-title">
        <button class="icon-btn" id="btn-back-fest">⬅️</button>
        <span>Urteko jaiegunak</span>
      </div>
    </div>
    <div style="background:#ffebee;padding:10px 14px;font-size:12.5px;color:#b71c1c;border-bottom:1px solid #ffcdd2;">
      🎉 Sakatu egutegiko edozein egun jaiegun gisa markatzeko edo kentzeko.
    </div>
    <div class="month-selector">
      <button class="icon-btn" id="fest-ant">❮</button>
      <div class="month-selector-title">${nombreMes.toUpperCase()} ${anio}</div>
      <button class="icon-btn" id="fest-sig">❯</button>
    </div>
    <div class="cal-header" style="padding:5px 6px;">
      ${["L", "M", "X", "J", "V", "S", "D"].map(d => `<div class="cal-day-head">${d}</div>`).join('')}
    </div>
    <div style="padding:6px 0;background:#fff;border-bottom:1px solid #e0e0e0;">
      ${filasHTML}
    </div>
    <div class="screen-body">
      <div style="font-weight:700;font-size:14px;margin-bottom:8px;">${anio}. urteko jaiegunak (${festivosAnio.length})</div>
      ${festivosAnio.map(f => `
        <div class="card" style="padding:10px 14px;margin-bottom:6px;display:flex;justify-content:space-between;align-items:center;border-color:#ffcdd2;">
          <span style="font-weight:700;font-size:13.5px;">🔴 ${f}</span>
          <button class="icon-btn del-fest" data-fecha="${f}" style="color:#d32f2f;">🗑️</button>
        </div>
      `).join('')}
    </div>
  `;

  document.getElementById('btn-back-fest').onclick = () => { state.screen = 'ajustes'; render(); };
  document.getElementById('fest-ant').onclick = () => { state.fechaFestivosVista = new Date(anio, mes - 1, 1); render(); };
  document.getElementById('fest-sig').onclick = () => { state.fechaFestivosVista = new Date(anio, mes + 1, 1); render(); };

  const toggleDia = async (fStr) => {
    if (cache.festivosFechas.has(fStr)) {
      runSQL("DELETE FROM festivos_anuales WHERE fecha = ?", [fStr]);
    } else {
      runSQL("INSERT OR REPLACE INTO festivos_anuales (fecha) VALUES (?)", [fStr]);
    }
    await guardarDBEnIDB();
    recargarCaches();
    render();
  };

  document.querySelectorAll('.fest-cell').forEach(c => {
    c.onclick = () => toggleDia(c.getAttribute('data-fecha'));
  });
  document.querySelectorAll('.del-fest').forEach(b => {
    b.onclick = () => toggleDia(b.getAttribute('data-fecha'));
  });
}

// 4.7 Crear / Editar Turno Manual
function renderNuevoTurno() {
  const { turnoExistente, onSaved } = state.nuevoTurnoParams || {};
  const esEdicion = !!turnoExistente;
  const app = document.getElementById('app');

  app.innerHTML = `
    <div class="appbar">
      <div class="appbar-title">
        <button class="icon-btn" id="btn-back-nt">⬅️</button>
        <span>${esEdicion ? 'Eskuzko txanda aldatu' : 'Txanda berria'}</span>
      </div>
      ${esEdicion ? `<button class="icon-btn" id="btn-del-nt" style="color:#d32f2f;">🗑️</button>` : ''}
    </div>
    <div class="screen-body">
      <div class="card">
        <label style="font-weight:700;font-size:13px;">Txandaren izena</label>
        <input type="text" id="nt-turno" class="input-field" style="margin:6px 0 14px;text-transform:uppercase;" placeholder="Adib. T1, 101..." value="${turnoExistente?.turno || ''}">

        <label style="font-weight:700;font-size:13px;">Mota / Kategoria</label>
        <input type="text" id="nt-tipo" class="input-field" style="margin:6px 0 14px;text-transform:uppercase;" placeholder="Adib. LAB, SDF, BESTEAK..." value="${turnoExistente?.tipo || 'LAB'}">

        <div style="display:flex;gap:12px;margin-top:6px;">
          <div style="flex:1;">
            <label style="font-weight:700;font-size:13px;">Hasiera ordua</label>
            <input type="time" id="nt-hasiera" class="input-field" style="margin-top:6px;" value="${horaCorta(turnoExistente?.hasiera) || '07:00'}">
          </div>
          <div style="flex:1;">
            <label style="font-weight:700;font-size:13px;">Amaiera ordua</label>
            <input type="time" id="nt-amaiera" class="input-field" style="margin-top:6px;" value="${horaCorta(turnoExistente?.amaiera) || '15:00'}">
          </div>
        </div>

        <button class="btn btn-primary" id="btn-save-nt" style="margin-top:24px;">
          ${esEdicion ? 'Aldaketak gorde' : 'Txanda sortu'}
        </button>
      </div>
    </div>
  `;

  document.getElementById('btn-back-nt').onclick = () => {
    state.screen = 'calendario';
    render();
  };

  if (esEdicion && document.getElementById('btn-del-nt')) {
    document.getElementById('btn-del-nt').onclick = async () => {
      if (confirm(`${turnoExistente.turno} (${turnoExistente.tipo}) txanda ezabatu?`)) {
        runSQL("DELETE FROM turnos WHERE turno = ? AND tipo = ? AND es_manual = 1", [turnoExistente.turno, turnoExistente.tipo]);
        await guardarDBEnIDB();
        recargarCaches();
        if (onSaved) onSaved({ eliminado: true });
        else { state.screen = 'calendario'; render(); }
      }
    };
  }

  document.getElementById('btn-save-nt').onclick = async () => {
    const turno = document.getElementById('nt-turno').value.trim().toUpperCase();
    const tipo = document.getElementById('nt-tipo').value.trim().toUpperCase();
    const h = document.getElementById('nt-hasiera').value;
    const a = document.getElementById('nt-amaiera').value;

    if (!turno || !tipo || !h || !a) {
      showToast("Bete eremu guztiak", "#d32f2f");
      return;
    }

    const minutos = diffMinutos(h, a);

    // Si es edición, congelamos primero los días antiguos en registro_diario
    if (esEdicion && turnoExistente.turno) {
      const ant = cache.turnos[`${turnoExistente.turno}-${turnoExistente.tipo}`];
      if (ant) {
        runSQL(`
          UPDATE registro_diario
          SET
            hasiera = CASE WHEN hasiera IS NULL OR hasiera = '' THEN ? ELSE hasiera END,
            amaiera = CASE WHEN amaiera IS NULL OR amaiera = '' THEN ? ELSE amaiera END,
            lan_orduak = CASE WHEN lan_orduak IS NULL OR lan_orduak = 0 THEN ? ELSE lan_orduak END
          WHERE turno = ? AND tipo = ?
        `, [ant.hasiera || '', ant.amaiera || '', ant.lan_orduak || 0, turnoExistente.turno, turnoExistente.tipo]);
      }
      if (turnoExistente.turno !== turno || turnoExistente.tipo !== tipo) {
        runSQL("DELETE FROM turnos WHERE turno = ? AND tipo = ?", [turnoExistente.turno, turnoExistente.tipo]);
      }
    }

    runSQL(`
      INSERT OR REPLACE INTO turnos (turno, tipo, hasiera, amaiera, lan_orduak, gidari_orduak, es_manual)
      VALUES (?, ?, ?, ?, ?, NULL, 1)
    `, [turno, tipo, `${h}:00`, `${a}:00`, minutos]);

    await guardarDBEnIDB();
    recargarCaches();
    showToast(esEdicion ? `${turno} (${tipo}) txanda ondo aldatu da` : `${turno} (${tipo}) txanda ondo sortu da`, "#2e7d32");

    if (onSaved) onSaved({ turno, tipo, hasiera: `${h}:00`, amaiera: `${a}:00`, lan_orduak: minutos });
    else { state.screen = 'calendario'; render(); }
  };
}

// =========================================================================
// 🔄 RENDERIZADOR GLOBAL Y ARRANQUE
// =========================================================================
function render() {
  switch (state.screen) {
    case 'calendario': return renderCalendario();
    case 'detalle': return renderDetalleTurno();
    case 'incidencia': return renderIncidenciaDia();
    case 'ajustes': return renderAjustes();
    case 'semanas': return renderConfigurarSemanas();
    case 'colores': return renderColoresTurno();
    case 'copia': return renderCopiaSeguridad();
    case 'bru': return renderHorasBru();
    case 'busqueda': return renderBusquedaServicio();
    case 'festivos': return renderFestivosAnuales();
    case 'nuevo_turno': return renderNuevoTurno();
    default: return renderCalendario();
  }
}

async function iniciarApp() {
  try {
    SQL = await initSqlJs({ locateFile: file => `./${file}` });
    let bytes = await cargarBytesDesdeIDB();

    if (!bytes) {
      const resp = await fetch('./datos.db');
      const buf = await resp.arrayBuffer();
      bytes = new Uint8Array(buf);
    }

    db = new SQL.Database(bytes);
    asegurarEsquema();
    await guardarDBEnIDB();
    recargarCaches();
    render();

    // Comprobar alarmas sonadas cada 5 segundos
    setInterval(() => {
      const prevSize = cache.alarmasFechas.size;
      purgarAlarmasSonadasGlobal();
      if (cache.alarmasFechas.size !== prevSize && (state.screen === 'calendario' || state.screen === 'detalle')) {
        render();
      }
    }, 5000);

    if ('serviceWorker' in navigator) {
      navigator.serviceWorker.register('./sw.js').catch(() => {});
    }
  } catch (err) {
    document.getElementById('app').innerHTML = `
      <div style="padding:24px;color:#d32f2f;font-weight:700;">
        Errorea Korreturnos abiaraztean: ${err.message}
      </div>
    `;
  }
}

window.addEventListener('DOMContentLoaded', iniciarApp);
