// Puente launcher <-> Claude Code (corre dentro de proot Debian, como root).
// Protocolo y contrato: docs/terminal.md, sección "Puente". Solo stdlib de Node (>=18).
const net = require('net'), fs = require('fs'), os = require('os'), path = require('path');
const { spawn } = require('child_process');
const { randomUUID, timingSafeEqual } = require('crypto');

// Las env vars son solo para probar en otro lado (PC); en producción valen los defaults.
const DIR = process.env.PIXEL_DIR || path.join(os.homedir(), '.pixel');
const CLAUDE_DIR = process.env.CLAUDE_CONFIG_DIR || path.join(os.homedir(), '.claude');
const PORT = +process.env.PORT || 8765;
// El chat del launcher muestra `description` al frente de cada tool: que siempre diga la razón, cortita.
const STYLE = 'En este chat cada comando se ve en una sola línea. Al usar Bash (o cualquier tool con campo `description`) completá siempre `description` con 3 a 6 palabras en español que digan PARA QUÉ es (ej. "Instalar dependencias", "Ver qué ocupa espacio"), no qué hace el comando. Todo script que escribas a un archivo o pases en varias líneas empieza con un comentario de una línea con esa misma aclaración corta.';
const EXTRA = (process.env.CLAUDE_BRIDGE_ARGS || '').split(/\s+/).filter(Boolean); // ej. "--model haiku" (solo test)
// Sube este número cuando cambie el protocolo: el launcher reinicia solo el puente viejo.
const VERSION = 4;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

fs.mkdirSync(DIR, { recursive: true });
const log = fs.createWriteStream(path.join(DIR, 'bridge.log'), { flags: 'a' });
const say = (...a) => log.write(`${new Date().toISOString()} ${a.join(' ')}\n`);
process.on('uncaughtException', e => say('uncaught', e.stack || e)); // un bug no tiene que tirar las sesiones

let TOKEN;
try { TOKEN = fs.readFileSync(path.join(DIR, 'token'), 'utf8').trim(); } catch { TOKEN = ''; }
if (!TOKEN) { say('falta', path.join(DIR, 'token')); console.error('falta el token'); process.exit(1); }
const tokenOk = t => {
  const a = Buffer.from(String(t)), b = Buffer.from(TOKEN);
  return a.length === b.length && timingSafeEqual(a, b);
};

// Registro de sesiones {id,cwd,title,updated} en ~/.pixel/sessions.json.
const REG = path.join(DIR, 'sessions.json');
const sessions = new Map();
try { for (const s of JSON.parse(fs.readFileSync(REG, 'utf8'))) sessions.set(s.id, s); } catch {}
const save = () => {
  try { fs.writeFileSync(REG + '.tmp', JSON.stringify([...sessions.values()])); fs.renameSync(REG + '.tmp', REG); }
  catch (e) { say('no pude guardar sessions.json', e.message); }
};

const procs = new Map(); // id -> { child }
const subs = new Map();  // id -> Set<socket> suscriptos

const send = (sock, msg) => {
  try { if (sock.writable) sock.write(JSON.stringify(msg) + '\n'); } catch (e) { say('write', e.message); }
}; // ponytail: sin backpressure; si un cliente lento se atrasa, Node bufferea en memoria
const broadcast = (id, msg) => subs.get(id)?.forEach(s => send(s, msg));
const subscribe = (id, sock) => {
  if (!subs.has(id)) subs.set(id, new Set());
  subs.get(id).add(sock);
};

// Parte un stream en líneas (maneja líneas partidas entre chunks). Las streams van en utf8.
const lines = cb => {
  let buf = '';
  return chunk => {
    buf += chunk;
    for (let i; (i = buf.indexOf('\n')) >= 0;) {
      const l = buf.slice(0, i).trim(); buf = buf.slice(i + 1);
      if (l) cb(l);
    }
  };
};

// Transcript de Claude: ~/.claude/projects/<cwd con todo no-alfanumérico -> '-'>/<id>.jsonl.
// Si el escapado no coincide (paths largos, symlinks) busca el id en todas las carpetas.
const transcript = (id, cwd) => {
  const root = path.join(CLAUDE_DIR, 'projects'), f = id + '.jsonl';
  const p = path.join(root, cwd.replace(/[^a-zA-Z0-9]/g, '-'), f);
  if (fs.existsSync(p)) return p;
  try { for (const d of fs.readdirSync(root)) if (fs.existsSync(path.join(root, d, f))) return path.join(root, d, f); } catch {}
};

function start(s) {
  fs.mkdirSync(s.cwd, { recursive: true });
  const mcp = { mcpServers: { launcher: { type: 'http', url: `http://127.0.0.1:8766/mcp?session=${s.id}&cwd=${encodeURIComponent(s.cwd)}`, headers: { Authorization: 'Bearer ' + TOKEN } } } };
  const args = ['-p', '--input-format', 'stream-json', '--output-format', 'stream-json', '--verbose', '--include-partial-messages', // texto en vivo (stream_event)
    '--append-system-prompt', STYLE,
    '--mcp-config', JSON.stringify(mcp), '--permission-prompt-tool', 'mcp__launcher__approve',
    '--add-dir', path.join(DIR, 'attachments'), // adjuntos: Claude los lee desde ahí sin pedir permiso de carpeta
    ...(transcript(s.id, s.cwd) ? ['--resume', s.id] : ['--session-id', s.id]), ...EXTRA];
  const child = spawn('claude', args, { cwd: s.cwd, stdio: ['pipe', 'pipe', 'pipe'] });
  const p = { child, busy: false }; // busy: turno en curso
  procs.set(s.id, p);
  const gone = () => { if (procs.get(s.id) === p) procs.delete(s.id); };
  child.stdin.on('error', e => say(s.id, 'stdin', e.message));
  child.stderr.pipe(log, { end: false });
  child.stdout.setEncoding('utf8');
  child.stdout.on('data', lines(l => {
    let event; try { event = JSON.parse(l); } catch { return say(s.id, 'stdout no-JSON:', l.slice(0, 200)); }
    if (event.type === 'result') p.busy = false;
    broadcast(s.id, { op: 'event', id: s.id, event });
    if (event.type === 'result' && p.stale) child.kill(); // ver el reconectar del launcher, abajo
  }));
  child.on('error', e => { gone(); say(s.id, 'spawn', e.message); broadcast(s.id, { op: 'error', id: s.id, message: 'no pude lanzar claude: ' + e.message }); });
  child.on('close', (code, sig) => {
    gone(); say(s.id, 'exit', code, sig || '');
    code ??= -1; // muerto por señal (close): que el cliente reciba siempre un entero
    const r = sessions.get(s.id); if (r) { r.updated = Date.now(); save(); }
    broadcast(s.id, { op: 'exit', id: s.id, code });
  });
  return p;
}

function handle(sock, m) {
  const { op, id } = m;
  if (op === 'sessions') {
    const list = [...sessions.values()].sort((a, b) => b.updated - a.updated).map(s => ({ ...s, running: procs.has(s.id) }));
    return send(sock, { op: 'sessions', list });
  }
  if (op === 'hello') return send(sock, { op: 'hello', version: VERSION });
  if (op === 'file') {
    // Un archivo que generó Claude (en Debian), para que el launcher lo abra con otra app. Tope de 25 MB.
    const reply = o => send(sock, { op: 'file', req: m.req, path: m.path, ...o });
    try {
      const f = path.resolve(os.homedir(), String(m.path || ''));
      const st = fs.statSync(f);
      if (!st.isFile()) return reply({ error: 'no es un archivo' });
      if (st.size > 25 << 20) return reply({ error: 'pesa más de 25 MB' });
      return reply({ name: path.basename(f), data: fs.readFileSync(f).toString('base64') });
    } catch (e) { return reply({ error: e.code === 'ENOENT' ? 'no existe (¿lo borraron?)' : e.message }); }
  }
  if (!['open', 'send', 'stop', 'close', 'delete'].includes(op)) return send(sock, { op: 'error', message: 'op desconocida: ' + op });
  if (!UUID.test(id)) return send(sock, { op: 'error', message: 'id inválido' });
  const known = sessions.get(id);
  if (op === 'open') {
    const f = transcript(id, path.resolve(os.homedir(), known?.cwd || m.cwd || ''));
    if (f) for (const l of fs.readFileSync(f, 'utf8').split('\n')) {
      let o; try { o = JSON.parse(l); } catch { continue; }
      if ((o.type === 'user' || o.type === 'assistant') && !o.isMeta && !o.isSidechain)
        send(sock, { op: 'event', id, event: { type: o.type, message: o.message } });
    }
    subscribe(id, sock); // en el mismo tick que la historia: no se pierde ningún evento en vivo
  } else if (op === 'send') {
    let text = typeof m.text === 'string' ? m.text : '';
    // Adjuntos {name, data: base64}: se guardan en ~/.pixel/attachments/<id>/ y el mensaje lleva las rutas
    // (Claude lee imágenes y PDFs con Read). Solo el nombre base: nada de rutas que vengan del cliente.
    const saved = [];
    if (Array.isArray(m.files)) for (const f of m.files) {
      if (!f || typeof f.data !== 'string') continue;
      const dir = path.join(DIR, 'attachments', id);
      fs.mkdirSync(dir, { recursive: true });
      const name = path.basename(String(f.name || 'archivo')).replace(/[^\w.\- ]/g, '_') || 'archivo';
      const file = path.join(dir, Date.now() + '-' + name);
      fs.writeFileSync(file, Buffer.from(f.data, 'base64'));
      saved.push(file);
    }
    if (saved.length) text += (text ? '\n\n' : '') + 'Archivos adjuntos:\n' + saved.map(f => '- ' + f).join('\n');
    const cwd = known?.cwd || (typeof m.cwd === 'string' && m.cwd && path.resolve(os.homedir(), m.cwd));
    if (!text || !cwd) return send(sock, { op: 'error', id, message: 'send necesita text (o files) y cwd' });
    const s = known || { id, cwd, title: text.replace(/\s+/g, ' ').slice(0, 60), updated: 0 };
    s.updated = Date.now(); sessions.set(id, s); save();
    subscribe(id, sock); // quien manda sin haber hecho open igual ve las respuestas
    const p = procs.get(id) || start(s);
    p.busy = true;
    p.child.stdin.write(JSON.stringify({ type: 'user', message: { role: 'user', content: text } }) + '\n');
  } else if (op === 'stop') {
    procs.get(id)?.child.stdin.write(JSON.stringify({ type: 'control_request', request_id: randomUUID(), request: { subtype: 'interrupt' } }) + '\n');
  } else if (op === 'delete') {
    // Borra la sesión: mata el proceso, la saca del registro y borra transcript y adjuntos.
    const p = procs.get(id);
    if (p) { p.child.kill(); procs.delete(id); }
    const f = transcript(id, path.resolve(os.homedir(), known?.cwd || ''));
    try { if (f) fs.rmSync(f); } catch (e) { say('delete transcript', e.message); }
    try { fs.rmSync(path.join(DIR, 'attachments', id), { recursive: true, force: true }); } catch {}
    sessions.delete(id); subs.delete(id); save();
    handle(sock, { op: 'sessions' });
  } else {
    procs.get(id)?.child.kill(); // la sesión queda en disco; el 'close' del hijo avisa con op:exit
  }
}

net.createServer(sock => {
  sock.setEncoding('utf8');
  sock.on('error', e => say('cliente', e.message));
  sock.on('close', () => subs.forEach(set => set.delete(sock)));
  let ok = false;
  const feed = lines(l => {
    let m; try { m = JSON.parse(l); } catch { m = null; }
    if (!ok) {
      if (!m || !tokenOk(m.token)) return sock.destroy();
      ok = true;
      // Volvió el launcher (lo mataron o se reinstaló): su MCP es otro proceso y los claude ya no lo
      // ven ("mcp__launcher__approve not found"). Se cierran (los que están en un turno, al terminarlo);
      // el próximo send los retoma con --resume y un MCP nuevo.
      for (const p of procs.values()) if (p.busy) p.stale = true; else p.child.kill();
      return;
    }
    if (!m || typeof m !== 'object') return send(sock, { op: 'error', message: 'JSON inválido' });
    try { handle(sock, m); } catch (e) { say('handle', e.stack); send(sock, { op: 'error', id: m.id, message: e.message }); }
  });
  sock.on('data', c => { feed(c); if (!ok && sock.bytesRead > 4096) sock.destroy(); }); // sin token no hay buffer infinito
}).on('error', e => { say('server', e.message); process.exit(1); })
  .listen(PORT, '127.0.0.1', () => say('escuchando en 127.0.0.1:' + PORT));
