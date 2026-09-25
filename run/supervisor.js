// Keeps the Nam Nagaram API + ngrok tunnel running in the background (no
// windows to close by accident). Restarts either one if it stops, health-checks
// the API every 30 s, and writes logs to run/logs/.
//   Start: start-servers.bat   Stop: stop-servers.bat
const { spawn, execSync } = require('child_process');
const fs = require('fs');
const path = require('path');
const http = require('http');

const ROOT = path.resolve(__dirname, '..');
const LOGS = path.join(__dirname, 'logs');
const PID_FILE = path.join(__dirname, 'supervisor.pid');
const NGROK_URL = 'https://trade-skedaddle-previous.ngrok-free.dev';
fs.mkdirSync(LOGS, { recursive: true });

// Only one supervisor at a time.
try {
  const old = Number(fs.readFileSync(PID_FILE, 'utf8'));
  if (old && old !== process.pid) {
    process.kill(old, 0); // throws if not running
    console.log(`Supervisor already running (pid ${old}).`);
    process.exit(0);
  }
} catch { /* not running */ }
fs.writeFileSync(PID_FILE, String(process.pid));

const log = (name) => fs.createWriteStream(path.join(LOGS, `${name}.log`), { flags: 'a' });
const stamp = () => new Date().toISOString();
const sup = log('supervisor');
const note = (msg) => sup.write(`[${stamp()}] ${msg}\n`);

const children = {};
function run(name, cmd, args, opts, delayMs) {
  const out = log(name);
  out.write(`\n[${stamp()}] starting ${cmd} ${args.join(' ')}\n`);
  const child = spawn(cmd, args, { ...opts, windowsHide: true, shell: false });
  child.stdout.pipe(out, { end: false });
  child.stderr.pipe(out, { end: false });
  child.on('exit', (code) => {
    note(`${name} exited (code ${code}); restarting in ${delayMs / 1000}s`);
    delete children[name];
    setTimeout(() => { children[name] = run(name, cmd, args, opts, delayMs); }, delayMs);
  });
  child.on('error', (e) => note(`${name} failed to start: ${e.message}`));
  return child;
}

// ngrok allows one agent per account on the free plan: stop stray agents first.
try { execSync('taskkill /IM ngrok.exe /F', { stdio: 'ignore' }); } catch { /* none running */ }
// Free port 3000 if an old API is still holding it.
try {
  const lines = execSync('netstat -ano', { encoding: 'utf8' }).split('\n').filter((l) => /:3000\s.*LISTENING/.test(l));
  for (const l of lines) execSync(`taskkill /PID ${l.trim().split(/\s+/).pop()} /F`, { stdio: 'ignore' });
} catch { /* nothing on 3000 */ }

children.api = run('api', process.execPath, ['src/index.js'], { cwd: path.join(ROOT, 'server') }, 3000);
setTimeout(() => {
  children.ngrok = run('ngrok', 'ngrok', ['http', '3000', `--url=${NGROK_URL}`, '--log', 'stdout'], { cwd: ROOT }, 5000);
}, 2000);
note(`supervisor started (pid ${process.pid})`);

// Watchdog: if the API stops answering twice in a row, restart it.
let misses = 0;
setInterval(() => {
  const req = http.get('http://127.0.0.1:3000/api/health', { timeout: 5000 }, (res) => {
    misses = res.statusCode === 200 ? 0 : misses + 1;
    res.resume();
  });
  req.on('error', () => { misses++; });
  req.on('timeout', () => { req.destroy(); });
  if (misses >= 2 && children.api) {
    note('API not answering; restarting it');
    misses = 0;
    children.api.kill();
  }
}, 30000);

const shutdown = () => {
  for (const c of Object.values(children)) c.removeAllListeners('exit'), c.kill();
  try { fs.unlinkSync(PID_FILE); } catch { /* ignore */ }
  process.exit(0);
};
process.on('SIGINT', shutdown);
process.on('SIGTERM', shutdown);
