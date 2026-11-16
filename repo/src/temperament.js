/* ═══════════════════════════════════════════════════════════════════
   TEMPERAMENT · the eye as a creature rather than a tracker.
   Runs once, called by the engine just before its first build, so the
   lexicon and the hour are settled before a single glyph is inscribed.

   Every behaviour has a URL switch (1 on, 0 off):
     light      pupil answers the brightness of the room
     sleep      no face for a while and it dozes     &sleepafter=600 (seconds)
     duo        a second face makes it dart between you
     contest    staring contest, needs the landmark model   &contestsecs=30
     speak      a line of words lifts out of the iris
     micro      fine text resolves when you lean in
     circadian  palette and vocabulary follow the hour     &hour=23 to preview
   And three that take a value:
     lex=name       load lexicons/name.json over the built-in vocabulary
     eye=left|right one half of a pair on two machines
     seed=today     the same plate on every machine, new each day
     poster=24x36   print render (inches)   &dpi=150
   ═══════════════════════════════════════════════════════════════════ */
window.OCULUS_TEMPERAMENT = function(C){
"use strict";
const T = C.T, G = C.G, F = C.F, P = C.P, LEX = C.LEX;
const TAU = Math.PI * 2;
const BANDS = ["PUPIL","INNER","MID","OUTER","LIMBUS","SCLERA","FIELD"];
const clamp = function(v,a,b){ return v<a?a:v>b?b:v; };
const sstep = function(a,b,v){ const t = clamp((v-a)/(b-a),0,1); return t*t*(3-2*t); };
const ms = function(){ return performance.now(); };

let Q;
try { Q = new URLSearchParams(location.search); }
catch(e){ Q = { get:function(){ return null; } }; }
const KIOSK  = Q.get("kiosk") === "1";
const POSTER = !!T.poster;
const LATIN  = !!(LEX.PUPIL && LEX.PUPIL.indexOf("AIN SOPH") >= 0);

function flag(name, dflt){
  const v = Q.get(name);
  return v === null ? dflt : (v !== "0" && v !== "off");
}
function num(name, dflt){
  const v = Number(Q.get(name));
  return Q.get(name) !== null && Number.isFinite(v) && v > 0 ? v : dflt;
}
const O = {
  light:     flag("light", true),
  sleep:     flag("sleep", true),
  duo:       flag("duo", true),
  /* the landmark model is a second network running beside the detector, so an
     all-day wallpaper has to ask for it; a browser tab gets it by default */
  contest:   flag("contest", !KIOSK),
  speak:     flag("speak", true),
  micro:     flag("micro", true),
  circadian: flag("circadian", true),
  sleepAfter:  num("sleepafter", 600),
  contestSecs: num("contestsecs", 30)
};
if(POSTER){ O.light = O.sleep = O.duo = O.contest = O.speak = O.micro = false; O.circadian = flag("circadian", false); }

/* ── what it says ─────────────────────────────────────────────────── */
const LINES = LATIN ? {
  see:"VIDEO TE", lost:"NOLI ABIRE", wake:"VIGILO", sleep:"QVIESCO",
  win:"VICISTI", blinked:"NICTAVISTI", closer:"PROPIVS"
} : {
  see:"I SEE YOU", lost:"DON'T LOOK AWAY", wake:"THERE YOU ARE", sleep:"REST NOW",
  win:"YOU WIN", blinked:"YOU BLINKED", closer:"CLOSER"
};
let MICRO_TEXT = LATIN
  ? "QVOD EST INFERIVS EST SICVT QVOD EST SVPERIVS · ET QVOD EST SVPERIVS EST SICVT QVOD EST INFERIVS · "
  : "THE CLOSER YOU LOOK THE MORE IT LOOKS BACK · EVERY WORD HERE IS WATCHING YOU READ IT · ";

const SP = { text:"", words:[], t0:-1e9, total:0, lastKey:{}, nextAmbient: ms() + 70000 + Math.random()*90000 };
/* One word at a time: each lifts out of its own ring, glows, and settles,
   the next following half a second behind, until the line stands complete. */
const WORD_STEP = 0.52, LIFT = 0.55, HOLD = 2.4, FADE_OUT = 1.1;

function speaking(){ return SP.text && (ms() - SP.t0)/1000 < SP.total; }

/* `gapMs` is the least time between two uses of the same line */
function say(key, gapMs, force){
  if(!O.speak && !force) return false;
  const now = ms();
  const text = String(LINES[key] !== undefined ? LINES[key] : key).toUpperCase().slice(0, 48);
  const words = text.split(/\s+/).filter(Boolean).slice(0, 6);
  if(!words.length) return false;
  if(gapMs && SP.lastKey[key] && now - SP.lastKey[key] < gapMs) return false;
  if(speaking() && !force) return false;
  SP.lastKey[key] = now;
  SP.text = text; SP.words = words; SP.t0 = now;
  SP.total = (words.length - 1)*WORD_STEP + LIFT + HOLD + FADE_OUT;
  return true;
}

function ambientLine(){
  const pool = [];
  ["FIELD","SCLERA","LIMBUS"].forEach(function(b){
    (LEX[b] || []).forEach(function(w){
      if(w.indexOf(" ") > 0 && w.length >= 8 && w.length <= 26) pool.push(w);
    });
  });
  return pool.length ? pool[(Math.random()*pool.length)|0] : null;
}

/* The line is set across the rings, not along one: first word on the outermost
   ring it uses, each later word one ring further in, all centred over the
   pupil so it reads top to bottom. Every word drifts with its ring, alternate
   rings in opposite directions, the way the lexicon itself turns. */
function drawSpeech(ctx, R, pr){
  const e = (ms() - SP.t0)/1000;
  if(!SP.words.length || e >= SP.total || T.lid > 0.6) return;
  const words = SP.words, n = words.length;
  const out = clamp((SP.total - e)/FADE_OUT, 0, 1);
  const inner = Math.max(pr*1.5, R*0.44);
  let fs = R*0.054;
  let gap = fs*1.42;
  const room = R*0.94 - inner;
  if((n-1)*gap > room){ gap = room/Math.max(1, n-1); fs = gap/1.42; }

  ctx.save();
  ctx.textAlign = "center"; ctx.textBaseline = "middle";
    for(let w=0; w<n; w++){
    const local = e - w*WORD_STEP;
    if(local <= 0) continue;
    const k = clamp(local/LIFT, 0, 1);
    const rise = 1 - Math.pow(1 - k, 3);                 /* ease-out */
    const alpha = rise * out;
    if(alpha < 0.01) continue;
    /* the lift: it arrives a little large and bright, then settles */
    const swell = 1 + 0.07*Math.sin(Math.PI*k)*(1 - k*0.4);
    const rr = inner + (n - 1 - w)*gap + (1 - rise)*fs*-0.35;
    const size = fs*swell;
    /* tinted by the ring it stands on, so it reads as that ring catching the
       light rather than a caption laid over the eye */
    const hsl = C.color ? C.color(rr/R, -Math.PI/2) : [40, 30, 60];
    const hue = hsl[0].toFixed(0), sat = clamp(hsl[1]*0.55, 8, 46).toFixed(0);
    const text = words[w];
    ctx.font = "600 " + size.toFixed(2) + "px 'Arial Narrow','Helvetica Neue',Arial,sans-serif";
    const widths = []; let total = 0;
    for(let i=0;i<text.length;i++){
      const cw = ctx.measureText(text[i]).width + size*0.22;
      widths.push(cw); total += cw;
    }
    const drift = (w % 2 ? -1 : 1) * 0.022 * local;
    let a = -Math.PI/2 - (total/rr)/2 + drift;
    for(let i=0;i<text.length;i++){
      const half = widths[i]/rr/2;
      a += half;
      ctx.save();
      ctx.translate(Math.cos(a)*rr, Math.sin(a)*rr);
      ctx.rotate(a + Math.PI/2);
      /* a soft shadow clears a little room behind the letter; no outline */
      ctx.shadowColor = "rgba(4,3,7," + (alpha*0.80).toFixed(3) + ")";
      ctx.shadowBlur = size*0.55;
      ctx.fillStyle = "rgba(6,5,9," + (alpha*0.30).toFixed(3) + ")";
      ctx.fillText(text[i], 0, 0);
      ctx.shadowColor = "hsla(" + hue + "," + sat + "%,74%," + (alpha*(0.30 + 0.45*(1 - k))).toFixed(3) + ")";
      ctx.shadowBlur = size*(0.22 + 0.5*(1 - k));
      ctx.fillStyle = "hsla(" + hue + "," + sat + "%,88%," + (alpha*0.90).toFixed(3) + ")";
      ctx.fillText(text[i], 0, 0);
      ctx.restore();
      a += half;
    }
  }
  ctx.restore();
}

/* ── reading distance: a layer too fine to read from your chair ───── */
let microCv = null, microAmt = 0;
function bakeMicro(){
  microCv = null;
  if(!O.micro) return;
  const g = C.geom();
  const px = Math.ceil(g.R * 2 * g.LDPR);
  if(px < 64) return;
  const cv = document.createElement("canvas");
  cv.width = cv.height = px;
  const c = cv.getContext("2d");
  c.setTransform(g.LDPR, 0, 0, g.LDPR, px/2, px/2);
  const fs = Math.max(2.6, 3.3 * g.sc);
  c.font = "600 " + fs.toFixed(2) + "px 'Helvetica Neue',Arial,sans-serif";
  c.textAlign = "center"; c.textBaseline = "middle";
  c.fillStyle = "rgba(255,244,220,.92)";
  const text = MICRO_TEXT, adv = fs * 0.66;
  let k = 0;
  for(let r = g.R*0.36; r < g.R*0.975; r += fs*2.7, k++){
    const count = Math.floor(TAU*r/adv), da = TAU/count;
    let a = (k*1.913) % TAU;
    const off = (k*7) % text.length;
    for(let i=0;i<count;i++, a+=da){
      const ch = text[(off+i) % text.length];
      if(ch === " ") continue;
      c.save(); c.rotate(a); c.fillText(ch, 0, -r); c.restore();
    }
  }
  microCv = cv;
}
function drawMicro(ctx, R){
  if(!microCv || microAmt < 0.012) return;
  ctx.save();
  ctx.globalCompositeOperation = "lighter";
  ctx.globalAlpha = microAmt * 0.80;
  ctx.rotate(-C.time()*0.012);
  ctx.drawImage(microCv, -R, -R, R*2, R*2);
  ctx.restore();
}

T.iris = function(ctx, R, pr){
  drawMicro(ctx, R);
  drawSpeech(ctx, R, pr);
};

/* ── the hour ─────────────────────────────────────────────────────── */
const GRADE = {
  night:"brightness(.80) saturate(.82) hue-rotate(-10deg)",
  dawn: "brightness(1.05) saturate(.90) sepia(.10)",
  day:  "none",
  dusk: "brightness(.95) saturate(1.08) sepia(.16)"
};
/* Share of words borrowed from another stratum. The coin is cut from the same
   random draw the engine already makes, so the seed still fixes the layout. */
const BORROW = { night:["PUPIL",0.30], dawn:["SCLERA",0.28], dusk:["LIMBUS",0.20], day:null };
function period(){
  const hq = Q.get("hour");
  const h = (hq !== null && hq !== "" && Number.isFinite(Number(hq))) ? Number(hq) : new Date().getHours();
  return h < 5 ? "night" : h < 9 ? "dawn" : h < 17 ? "day" : h < 21 ? "dusk" : "night";
}
let curPeriod = null;
function applyPeriod(){
  const p = O.circadian ? period() : "day";
  if(p === curPeriod) return false;
  curPeriod = p;
  C.canvas.style.transition = "filter 12s linear";
  C.canvas.style.filter = GRADE[p];
  const b = BORROW[p];
  T.bandMap = b ? function(band, coin){
    return (band !== "FIELD" && band !== b[0] && coin < b[1]) ? b[0] : band;
  } : null;
  return true;
}
applyPeriod();

/* ── custom lexicons ──────────────────────────────────────────────── */
function applyLex(obj){
  let hit = 0;
  BANDS.forEach(function(k){
    const arr = obj && obj[k];
    if(Array.isArray(arr)){
      const clean = arr.map(function(s){ return String(s).toUpperCase().trim(); }).filter(Boolean);
      if(clean.length){ LEX[k] = clean; hit++; }
    }
  });
  if(obj && obj.SPEAK && typeof obj.SPEAK === "object")
    Object.keys(LINES).forEach(function(k){ if(obj.SPEAK[k]) LINES[k] = String(obj.SPEAK[k]); });
  if(obj && typeof obj.MICRO === "string" && obj.MICRO.trim())
    MICRO_TEXT = obj.MICRO.toUpperCase().trim() + " · ";
  return hit;
}
/* Plain text: "[PUPIL]" style headers, then one term per line or comma-separated.
   With no headers at all the terms are dealt across every band in turn. */
function parseLexText(txt){
  const out = {}, loose = [];
  let band = null;
  String(txt).split(/\r?\n/).forEach(function(line){
    const s = line.trim();
    if(!s || s[0] === "#") return;
    const h = s.match(/^\[([A-Za-z]+)\]$/);
    if(h){ band = h[1].toUpperCase(); if(!out[band]) out[band] = []; return; }
    s.split(",").forEach(function(w){
      w = w.trim(); if(!w) return;
      if(band) out[band].push(w); else loose.push(w);
    });
  });
  if(!Object.keys(out).length && loose.length)
    loose.forEach(function(w, i){ const k = BANDS[i % BANDS.length]; (out[k] = out[k] || []).push(w); });
  return out;
}
function parseLex(txt){
  try { return JSON.parse(txt); } catch(e){ return parseLexText(txt); }
}
function loadLex(src){
  if(src && typeof src === "object"){ const n = applyLex(src); if(n) C.rebuild(); return Promise.resolve(n); }
  const name = String(src || "");
  if(!/^[A-Za-z0-9_-]+$/.test(name)) return Promise.resolve(0);
  return fetch("lexicons/" + name + ".json", {cache:"no-store"})
    .then(function(r){ if(!r.ok) throw new Error("no such lexicon"); return r.text(); })
    .then(function(t){ return applyLex(parseLex(t)); })
    .catch(function(){ return 0; });
}
const lexName = Q.get("lex");
if(lexName){
  /* hold the first build until the vocabulary has arrived, or failed to */
  T.defer = true;
  loadLex(lexName).then(function(){ T.defer = false; C.rebuild(); });
}
if(!KIOSK && !POSTER){
  window.addEventListener("dragover", function(e){ e.preventDefault(); });
  window.addEventListener("drop", function(e){
    e.preventDefault();
    const f = e.dataTransfer && e.dataTransfer.files && e.dataTransfer.files[0];
    if(!f) return;
    f.text().then(function(t){ if(applyLex(parseLex(t))) C.rebuild(); });
  });
}

/* ── the pair ─────────────────────────────────────────────────────── */
const EYE = (Q.get("eye") || "").toLowerCase();
const VERGE = EYE === "left" ? 0.11 : EYE === "right" ? -0.11 : 0;

/* ── presence, sleep, light ───────────────────────────────────────── */
const S = {
  camOn:false, present:false, lastFace:0, presentSince:0, absentSince:ms(),
  state:"awake", opening:null, forceSleep:false,
  lum:0.45, base:0.45, lumAt:0, closeSince:0
};
let lumCv = null, lumCtx = null;
function sampleLight(now){
  const cam = window.OCULUS_CAM;
  if(!cam || !cam.running() || !cam.vid || cam.vid.readyState < 2) return false;
  if(now - S.lumAt < 400) return true;
  const dt = Math.min(2, (now - S.lumAt)/1000);
  S.lumAt = now;
  try{
    if(!lumCv){
      lumCv = document.createElement("canvas"); lumCv.width = 16; lumCv.height = 12;
      lumCtx = lumCv.getContext("2d", {willReadFrequently:true});
    }
    lumCtx.drawImage(cam.vid, 0, 0, 16, 12);
    const d = lumCtx.getImageData(0, 0, 16, 12).data;
    let sum = 0;
    for(let i=0;i<d.length;i+=4) sum += d[i]*0.2126 + d[i+1]*0.7152 + d[i+2]*0.0722;
    const lum = sum / (16*12*255);
    S.lum += (lum - S.lum) * 0.55;
    /* the baseline follows over about half a minute, as the camera's own
       exposure does, so what survives is the change: a lamp, a cloud, a door */
    S.base += (S.lum - S.base) * (1 - Math.exp(-dt/30));
  }catch(e){ return false; }
  return true;
}

function wake(now, flare){
  S.state = "awake"; S.forceSleep = false;
  S.absentSince = now;
  if(flare){ C.flare(0.12); say("wake", 0, false); }
}

T.tick = function(dt){
  const now = ms();
  const fresh = F.on && (now - F.last < 900);

  if(F.on !== S.camOn){
    S.camOn = F.on;
    S.absentSince = now; S.present = false;
    if(!F.on && S.state !== "awake" && !S.forceSleep) S.state = "awake";
  }

  if(fresh){
    if(!S.present){
      S.present = true; S.presentSince = now;
      const gap = now - S.absentSince;
      if(S.state !== "awake") wake(now, true);
      else if(gap > 6000) say("see", 20000);
    }
    S.lastFace = now;
  } else if(S.present && now - S.lastFace > 2500){
    S.present = false; S.absentSince = S.lastFace;
    if(now - S.presentSince > 5000) say("lost", 30000);
  }

  /* sleep: only with the camera running, since that is the only way to know
     nobody is there. A wandering eye with the camera off never dozes. */
  if(S.forceSleep){
    if(S.state === "awake") S.state = "asleep";
  } else if(O.sleep && F.on && !S.present){
    const idle = (now - S.absentSince)/1000;
    if(idle > O.sleepAfter + 45){ S.state = "asleep"; }
    else if(idle > O.sleepAfter){
      if(S.state === "awake"){ S.state = "drowsy"; say("sleep", 0); }
    }
  } else if(S.state !== "awake" && (!F.on || !O.sleep)){
    S.state = "awake";
  }

  let lidT = 0, spinT = 1;
  if(S.state === "drowsy"){ lidT = 0.50; spinT = 0.45; }
  else if(S.state === "asleep"){ lidT = 0.88 + 0.03*Math.sin(now/2100); spinT = 0.12; }
  const rising = lidT < T.lid;
  let lid = T.lid + (lidT - T.lid) * (1 - Math.exp(-dt * (rising ? 7 : 0.45)));
  if(S.opening){
    const k = (now - S.opening.t0) / S.opening.ms;
    if(k >= 1) S.opening = null;
    else { const e = 1 - k; lid = Math.max(lid, e*e*(3 - 2*e)); }
  }
  T.lid = lid < 0.001 ? 0 : lid;
  T.spinK += (spinT - T.spinK) * (1 - Math.exp(-dt * 0.8));

  /* light reflex */
  let pupilT = 0;
  if(O.light && sampleLight(now)){
    pupilT = clamp(-(S.lum - 0.45)*0.05 - (S.lum - S.base)*0.24, -0.075, 0.065);
  }
  T.pupil += (pupilT - T.pupil) * (1 - Math.exp(-dt * 4));

  /* the pair: each eye turns in a little, more as you come closer */
  T.verge = VERGE ? VERGE * (1 + (fresh ? sstep(0.18, 0.48, F.size) : 0)) : 0;

  /* reading distance */
  let microT = 0;
  if(O.micro && S.state === "awake"){
    if(fresh) microT = sstep(0.33, 0.47, F.size);
    else if(!F.on){
      const p = C.pointer(), g = C.geom();
      if(p.has && now - p.last < 5000)
        microT = 1 - sstep(g.R*0.30, g.R*0.85, Math.hypot(p.x - g.EX, p.y - g.EY));
    }
  }
  microAmt += (microT - microAmt) * (1 - Math.exp(-dt * 2.2));
  if(fresh && F.size > 0.47){
    if(!S.closeSince) S.closeSince = now;
    else if(now - S.closeSince > 2500) say("closer", 180000);
  } else S.closeSince = 0;

  /* now and then it says something nobody asked for */
  if(O.speak && S.state === "awake" && now > SP.nextAmbient){
    SP.nextAmbient = now + 110000 + Math.random()*190000;
    if(fresh || !F.on){ const line = ambientLine(); if(line) say(line, 0); }
  }

  contestTick(now, fresh);
};

/* ── two faces ────────────────────────────────────────────────────── */
const D = { since:-1e9, lastTwo:-1e9, idx:0, next:0, lock:-1 };
/* BlazeFace hands back six landmarks: right eye, left eye, nose tip, mouth and
   the two ears. The nose sliding off the midpoint between the eyes is a turn
   of the head, measured in eye-widths so distance from the lens cancels out. */
const HT = { since:0 };
function headTurn(det, now){
  const kp = det && det.keypoints;
  if(!kp || kp.length < 3){ HT.since = 0; return; }
  const eyes = Math.abs(kp[1].x - kp[0].x);
  if(!(eyes > 0.005)){ HT.since = 0; return; }
  const yaw = Math.abs(kp[2].x - (kp[0].x + kp[1].x)/2) / eyes;
  HT.yaw = yaw;
  if(yaw > 0.42){
    if(!HT.since) HT.since = now;
    else if(now - HT.since > 650 && S.state === "awake") say("lost", 30000);
  } else if(yaw < 0.30) HT.since = 0;
}
function pick(dets, vid, now){
  const det = choose(dets, vid, now);
  headTurn(det, now);
  return det;
}
function choose(dets, vid, now){
  const list = [];
  for(let i=0;i<dets.length;i++) if(dets[i] && dets[i].boundingBox) list.push(dets[i]);
  if(!list.length) return undefined;
  if(!O.duo || list.length < 2){ return list[0]; }
  list.sort(function(a,b){ return a.boundingBox.originX - b.boundingBox.originX; });
  if(now - D.lastTwo > 6000){
    D.since = now; D.next = 0; D.idx = 0; D.lock = -1;
  }
  D.lastTwo = now;
  if(now - D.since < 4400){
    if(now >= D.next){
      D.idx = (D.idx + 1) % list.length;
      D.next = now + 480 + Math.random()*560;
    }
    return list[Math.min(D.idx, list.length-1)];
  }
  let big = 0;
  for(let i=1;i<list.length;i++) if(list[i].boundingBox.width > list[big].boundingBox.width) big = i;
  if(D.lock < 0 || D.lock >= list.length
     || list[big].boundingBox.width > list[D.lock].boundingBox.width * 1.15) D.lock = big;
  return list[D.lock];
}

/* ── staring contest ──────────────────────────────────────────────── */
const K = { lm:null, loading:false, failed:false, last:0, ts:0, start:0, cooldown:0, blinks:0 };
const LM_REMOTE = "https://storage.googleapis.com/mediapipe-models/face_landmarker/"
                + "face_landmarker/float16/1/face_landmarker.task";
function ensureLandmarker(){
  const cam = window.OCULUS_CAM;
  if(K.lm || K.loading || K.failed || !cam) return;
  K.loading = true;
  const model = cam.local ? cam.local + "/face_landmarker.task" : LM_REMOTE;
  import(cam.bundle).then(function(mod){
    return mod.FilesetResolver.forVisionTasks(cam.wasm).then(function(fileset){
      const opts = {
        baseOptions:{ modelAssetPath:model, delegate:"GPU" },
        runningMode:"VIDEO", numFaces:1, outputFaceBlendshapes:true
      };
      return mod.FaceLandmarker.createFromOptions(fileset, opts).catch(function(){
        opts.baseOptions.delegate = "CPU";
        return mod.FaceLandmarker.createFromOptions(fileset, opts);
      });
    });
  }).then(function(lm){ K.lm = lm; K.loading = false; })
    .catch(function(){ K.failed = true; K.loading = false; });
}
function blinkScore(res){
  const shapes = res && res.faceBlendshapes && res.faceBlendshapes[0];
  const cats = shapes && shapes.categories;
  if(!cats) return -1;
  let l = 0, r = 0;
  for(let i=0;i<cats.length;i++){
    if(cats[i].categoryName === "eyeBlinkLeft") l = cats[i].score;
    else if(cats[i].categoryName === "eyeBlinkRight") r = cats[i].score;
  }
  return (l + r) / 2;
}
function contestWin(now){
  K.cooldown = now + 120000; K.start = 0;
  T.glance = { x:(Math.random() < 0.5 ? -0.9 : 0.9), y:0.28, until: now + 2200 };
  say("win", 0, true);
  setTimeout(function(){ C.transmute(); }, 2900);
}
function contestTick(now, fresh){
  if(!O.contest || !fresh || S.state !== "awake" || now < K.cooldown){ K.start = 0; return; }
  ensureLandmarker();
  const cam = window.OCULUS_CAM;
  if(!K.lm || !cam || cam.vid.readyState < 2) return;
  if(!K.start) K.start = now;
  if(now - K.last > 110){
    K.last = now;
    K.ts = now > K.ts ? now : K.ts + 1;
    let score = -1;
    try { score = blinkScore(K.lm.detectForVideo(cam.vid, K.ts)); } catch(e){}
    if(score < 0){ K.start = now; }
    else if(score > 0.55){
      K.blinks++;
      if(now - K.start > 8000) say("blinked", 15000);
      K.start = now + 900;
    }
  }
  if(K.start && now - K.start > O.contestSecs*1000) contestWin(now);
}

/* ── after every build ────────────────────────────────────────────── */
T.built = function(){
  bakeMicro();
  if(POSTER) posterReady();
};

/* ── housekeeping once a minute: the hour, and the date ───────────── */
let lastDaily = C.daily() ? C.dailySeed() : 0;
setInterval(function(){
  let rebuild = false;
  if(O.circadian && !POSTER){
    const before = T.bandMap ? curPeriod : "plain";
    if(applyPeriod()){
      const after = T.bandMap ? curPeriod : "plain";
      if(before !== after) rebuild = true;
    }
  }
  if(C.daily()){
    const d = C.dailySeed();
    if(d !== lastDaily){ lastDaily = d; C.seed(d); rebuild = true; }
  }
  if(rebuild && C.ready()) C.rebuild();
}, 60000);

/* ── poster ───────────────────────────────────────────────────────── */
function posterName(){
  return "oculus-" + C.seed() + "-" + T.poster.label + "in-" + T.poster.dpi + "dpi.png";
}
function posterBlob(){
  return new Promise(function(res){ C.canvas.toBlob(res, "image/png"); });
}
function posterReady(){
  if(document.getElementById("poster-bar")) return;
  const g = C.geom();
  const bar = document.createElement("div");
  bar.id = "poster-bar";
  bar.style.cssText = "position:fixed;left:50%;bottom:18px;transform:translateX(-50%);z-index:50;"
    + "font:12px/1.4 -apple-system,'Helvetica Neue',Arial,sans-serif;color:#e9dcc3;"
    + "background:rgba(12,9,10,.86);border:1px solid rgba(201,178,138,.4);border-radius:6px;"
    + "padding:10px 14px;display:flex;gap:14px;align-items:center";
  const info = document.createElement("span");
  info.textContent = T.poster.label + " in · " + Math.round(g.W*g.DPR) + " × " + Math.round(g.H*g.DPR)
    + " px · seed " + C.seed();
  const btn = document.createElement("button");
  btn.textContent = "Save PNG";
  btn.style.cssText = "font:inherit;color:#120d0e;background:#c9b28a;border:0;border-radius:4px;"
    + "padding:6px 12px;cursor:pointer";
  btn.addEventListener("click", function(){
    btn.disabled = true; btn.textContent = "Rendering…";
    posterBlob().then(function(blob){
      const a = document.createElement("a");
      a.href = URL.createObjectURL(blob); a.download = posterName();
      document.body.appendChild(a); a.click(); a.remove();
      setTimeout(function(){ URL.revokeObjectURL(a.href); }, 20000);
      btn.disabled = false; btn.textContent = "Save PNG";
    });
  });
  bar.appendChild(info); bar.appendChild(btn);
  document.body.appendChild(bar);
}
if(POSTER){
  document.documentElement.classList.add("poster");
  const css = document.createElement("style");
  css.textContent =
    "html.poster #panel,html.poster #dock,html.poster #title,html.poster #motto{display:none!important}" +
    "html.poster canvas#c{width:auto!important;height:auto!important;max-width:100vw;max-height:100vh;" +
    "margin:auto;filter:none!important}";
  document.head.appendChild(css);
  /* a print looks straight out, lids open, nothing mid-gesture */
  P.follow = false; P.blink = false;
  T.glance = { x:0, y:0, until:Infinity };
}

if(!KIOSK && !POSTER){
  window.addEventListener("keydown", function(e){
    if(e.metaKey || e.ctrlKey || e.altKey) return;
    if((e.key || "").toLowerCase() !== "p") return;
    try{
      const u = new URL(location.href);
      u.searchParams.set("seed", String(C.seed()));
      u.searchParams.set("poster", "24x36");
      u.searchParams.delete("kiosk");
      window.open(u.toString(), "_blank");
    }catch(err){}
  });
}

/* ── what a host, or a curious console, may call ──────────────────── */
window.OCULUS_T = {
  opts:O, state:S, contest:K, lines:LINES, head:HT,
  pick:pick,
  say:function(text){ return say(text, 0, true); },
  /* x,y in gaze space: −1…1, right and down positive */
  glance:function(x, y, dur){
    if(S.state !== "awake") return;
    const m = Math.hypot(x, y), s = m > 1 ? 1/m : 1;
    T.glance = { x:x*s, y:y*s, until: ms() + (dur || 900) };
  },
  /* the lid lifts: used when the screensaver rises */
  open:function(dur){ S.opening = { t0:ms(), ms:dur || 1400 }; T.lid = 1; },
  sleep:function(){ S.forceSleep = true; S.state = "asleep"; },
  wake:function(){ wake(ms(), true); },
  set:function(key, on){
    if(!(key in O)) return;
    O[key] = typeof O[key] === "number" ? Number(on) : !!on;
    if(key === "circadian"){ curPeriod = null; if(applyPeriod() && C.ready()) C.rebuild(); }
    if(key === "micro") bakeMicro();
  },
  loadLex:function(src){
    if(typeof src === "string") return loadLex(src).then(function(n){ if(n) C.rebuild(); return n; });
    return loadLex(src);
  },
  period:function(){ return curPeriod; },
  posterBlob:posterBlob
};
};
