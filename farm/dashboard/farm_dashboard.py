#!/usr/bin/env python3
"""Farm dashboard — single-file, stdlib-only. Lives on the 3090 server (192.168.1.136:8180).

Nodes push JSON to POST /report every ~30s (see farm_report.sh). The dashboard keeps the
latest snapshot per node in memory, appends samples to a per-day JSONL history for
long-term tuning, and serves a LAN-visible HTML overview:
  GET  /             HTML dashboard (auto-refresh)
  GET  /api/state    latest snapshot per node + upgrade-phase status
  GET  /api/history  ?node=X&hours=N  downsampled GPU history for charts
  POST /report       node snapshot ingest

Phase status comes from phases.json next to this file (synced from the hub's
docs/FARM_UPGRADE_TASKS.md whenever the ledger changes). New farm machines appear
automatically the first time their reporter posts — nothing to configure here.
"""
import json, os, threading, time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs

BASE = os.path.dirname(os.path.abspath(__file__))
HIST_DIR = os.path.join(BASE, "history")
PHASES_FILE = os.path.join(BASE, "phases.json")
PORT = int(os.environ.get("FARM_DASH_PORT", "8180"))
STALE_S = 90            # no report for this long -> node shown as stale
RETAIN_DAYS = 60        # history files older than this are deleted

os.makedirs(HIST_DIR, exist_ok=True)
_lock = threading.Lock()
_latest = {}            # node -> last snapshot (with server-side recv_ts)

def _phases():
    try:
        with open(PHASES_FILE) as f:
            return json.load(f)
    except Exception:
        return {"phases": [], "current_activity": "phases.json missing"}

def _append_history(snap):
    day = time.strftime("%Y%m%d", time.localtime())
    row = {"ts": snap["recv_ts"], "node": snap.get("node", "?"),
           "gpus": [{k: g.get(k) for k in ("idx", "mem_used", "mem_total", "util", "temp", "power")}
                    for g in snap.get("gpus", [])],
           "load1": snap.get("load1"), "ram": snap.get("ram"),
           "svc_ok": sum(1 for s in snap.get("services", []) if s.get("ok")),
           "svc_n": len(snap.get("services", []))}
    with open(os.path.join(HIST_DIR, f"{day}.jsonl"), "a") as f:
        f.write(json.dumps(row) + "\n")

def _cleanup_history():
    cutoff = time.strftime("%Y%m%d", time.localtime(time.time() - RETAIN_DAYS * 86400))
    for fn in os.listdir(HIST_DIR):
        if fn.endswith(".jsonl") and fn[:8] < cutoff:
            try: os.remove(os.path.join(HIST_DIR, fn))
            except OSError: pass

def _history(node, hours):
    out, now = [], time.time()
    days = {time.strftime("%Y%m%d", time.localtime(now - h * 3600)) for h in range(int(hours) + 1)}
    for day in sorted(days):
        p = os.path.join(HIST_DIR, f"{day}.jsonl")
        if not os.path.exists(p): continue
        with open(p) as f:
            for line in f:
                try: row = json.loads(line)
                except ValueError: continue
                if row.get("node") == node and row.get("ts", 0) >= now - hours * 3600:
                    out.append(row)
    step = max(1, len(out) // 400)          # cap points sent to the browser
    return out[::step]

PAGE = """<!doctype html><html><head><meta charset="utf-8"><title>llama farm</title>
<meta name="viewport" content="width=device-width,initial-scale=1">
<style>
 body{background:#0d1117;color:#c9d1d9;font:14px/1.45 system-ui,sans-serif;margin:0;padding:16px}
 h1{font-size:18px;margin:0 0 4px} .sub{color:#8b949e;font-size:12px;margin-bottom:14px}
 .grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(330px,1fr));gap:12px}
 .card{background:#161b22;border:1px solid #30363d;border-radius:8px;padding:12px}
 .card.stale{opacity:.45} .card h2{font-size:15px;margin:0 0 2px} .meta{color:#8b949e;font-size:11px}
 .bar{background:#21262d;border-radius:4px;height:14px;margin:3px 0;position:relative;overflow:hidden}
 .bar>i{display:block;height:100%;border-radius:4px;background:#238636}
 .bar>i.warn{background:#9e6a03} .bar>i.crit{background:#da3633}
 .bar>b{position:absolute;left:6px;top:0;font-size:10px;font-weight:400;color:#e6edf3;line-height:14px}
 .svc{display:inline-block;margin:2px 4px 0 0;padding:1px 7px;border-radius:10px;font-size:11px;background:#1f6feb22;border:1px solid #30363d}
 .svc.ok{border-color:#238636;color:#3fb950} .svc.bad{border-color:#da3633;color:#f85149}
 canvas{width:100%;height:46px;margin-top:6px}
 .phases{background:#161b22;border:1px solid #30363d;border-radius:8px;padding:12px;margin-bottom:14px}
 .phases table{border-collapse:collapse;width:100%;font-size:13px}
 .phases td{padding:2px 8px 2px 0;vertical-align:top} .phases td:first-child{white-space:nowrap}
 .act{color:#d29922}
</style></head><body>
<h1>llama.cpp farm</h1><div class="sub" id="sub">loading…</div>
<div class="phases"><b>Upgrade project</b> — <span class="act" id="activity"></span>
 <table id="phases"></table></div>
<div class="grid" id="grid"></div>
<script>
const fmtGB=m=>(m/1024).toFixed(1);
const hist={};
async function loadHist(n){try{const r=await fetch('/api/history?node='+encodeURIComponent(n)+'&hours=6');hist[n]=await r.json();}catch(e){}}
function spark(cv,rows){if(!rows||rows.length<2)return;const c=cv.getContext('2d'),W=cv.width=cv.clientWidth,H=cv.height=46;
 c.clearRect(0,0,W,H);
 const u=rows.map(r=>r.gpus&&r.gpus[0]?(r.gpus[0].util||0):0);
 const m=rows.map(r=>r.gpus&&r.gpus[0]&&r.gpus[0].mem_total?100*r.gpus[0].mem_used/r.gpus[0].mem_total:0);
 const line=(a,col)=>{c.beginPath();a.forEach((v,i)=>{const x=i/(a.length-1)*W,y=H-2-(v/100)*(H-4);i?c.lineTo(x,y):c.moveTo(x,y)});c.strokeStyle=col;c.lineWidth=1.2;c.stroke()};
 line(m,'#58a6ff');line(u,'#3fb950');}
async function tick(){
 const s=await (await fetch('/api/state')).json();
 document.getElementById('sub').textContent=new Date().toLocaleString()+' — '+Object.keys(s.nodes).length+' nodes reporting — util '+ '\\u2500'.repeat(1)+' green=GPU util, blue=VRAM (6h)';
 document.getElementById('activity').textContent=s.phases.current_activity||'';
 document.getElementById('phases').innerHTML=(s.phases.phases||[]).map(p=>'<tr><td>'+p.icon+' '+p.name+'</td><td>'+p.note+'</td></tr>').join('');
 const g=document.getElementById('grid');g.innerHTML='';
 const now=s.server_ts;
 for(const[name,n] of Object.entries(s.nodes)){
  const stale=now-n.recv_ts>90;
  const card=document.createElement('div');card.className='card'+(stale?' stale':'');
  let h='<h2>'+name+'</h2><div class="meta">'+(stale?'STALE — last seen '+Math.round((now-n.recv_ts)/60)+' min ago':'reported '+Math.round(now-n.recv_ts)+'s ago')+
    (n.load1!=null?' · load '+n.load1:'')+(n.ram?' · RAM '+n.ram.used_gb+'/'+n.ram.total_gb+'G':'')+'</div>';
  for(const gpu of (n.gpus||[])){
   const pct=gpu.mem_total?Math.round(100*gpu.mem_used/gpu.mem_total):0;
   const cls=pct>92?'crit':pct>80?'warn':'';
   h+='<div class="meta">'+gpu.name+' · util '+(gpu.util??'?')+'% · '+(gpu.temp??'?')+'°C · '+(gpu.power??'?')+'W</div>';
   h+='<div class="bar"><i class="'+cls+'" style="width:'+pct+'%"></i><b>VRAM '+fmtGB(gpu.mem_used)+' / '+fmtGB(gpu.mem_total)+' GB ('+pct+'%)</b></div>';
  }
  h+='<div>'+(n.services||[]).map(sv=>'<span class="svc '+(sv.ok?'ok':'bad')+'">'+sv.name+'</span>').join('')+'</div>';
  h+='<canvas data-node="'+name+'"></canvas>';
  card.innerHTML=h;g.appendChild(card);
 }
 for(const cv of document.querySelectorAll('canvas')){const n=cv.dataset.node;if(!hist[n])await loadHist(n);spark(cv,hist[n]);}
}
tick();setInterval(tick,5000);setInterval(()=>{for(const n in hist)loadHist(n)},60000);
</script></body></html>"""

class H(BaseHTTPRequestHandler):
    def log_message(self, *a): pass

    def _send(self, code, body, ctype="application/json"):
        data = body if isinstance(body, bytes) else json.dumps(body).encode()
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        u = urlparse(self.path)
        if u.path == "/":
            self._send(200, PAGE.encode(), "text/html; charset=utf-8")
        elif u.path == "/api/state":
            with _lock:
                nodes = dict(_latest)
            self._send(200, {"server_ts": time.time(), "nodes": nodes, "phases": _phases()})
        elif u.path == "/api/history":
            q = parse_qs(u.query)
            node = q.get("node", [""])[0]
            hours = min(float(q.get("hours", ["6"])[0]), 24 * 14)
            self._send(200, _history(node, hours))
        elif u.path == "/health":
            self._send(200, {"status": "ok"})
        else:
            self._send(404, {"error": "not found"})

    def do_POST(self):
        if urlparse(self.path).path != "/report":
            return self._send(404, {"error": "not found"})
        try:
            n = int(self.headers.get("Content-Length", 0))
            snap = json.loads(self.rfile.read(n))
            node = str(snap.get("node", "")).strip()
            assert node
        except Exception:
            return self._send(400, {"error": "bad payload"})
        snap["recv_ts"] = time.time()
        with _lock:
            _latest[node] = snap
        _append_history(snap)
        self._send(200, {"ok": True})

def main():
    _cleanup_history()
    threading.Thread(target=lambda: (time.sleep(86400), _cleanup_history()), daemon=True).start()
    srv = ThreadingHTTPServer(("0.0.0.0", PORT), H)
    print(f"farm dashboard on :{PORT}")
    srv.serve_forever()

if __name__ == "__main__":
    main()
