// Moteur des slides de stratégies de déploiement (c7b-*) : des utilisateurs, un routeur,
// deux versions, et des requêtes animées qui vont là où l'étape en cours les envoie.
// Inclus dans <head> par construire.py. Une slide l'utilise ainsi :
//   Trafic('c7b-canary', { routeur: 'HTTPRoute api', etapes: [ { texte, v1: [...], v2: [...], poids: [90, 10] }, ... ] })
// v1 / v2 : un état par pod : 'ok' (sert), 'demarre', 'arret'.
// poids : part du trafic [v1, v2] ; sans poids, comme un Service : chaque pod prêt reçoit autant que les autres ; segments: true (A/B : les utilisateurs du groupe B vont en v2) ;
// miroir: true (shadow : chaque requête est copiée vers v2, la réponse est ignorée).
function Trafic(id, cfg) {
  const S = document.getElementById(id);
  const zone = S.querySelector('.trafic');
  const W = 1180, H = 740, NB_UTIL = 8;
  const UTIL_X = 70, ROUT_X = 400, ROUT_Y = H / 2, VOIE_X = 700, VOIE_W = 470, VOIE_H = 330;
  const VOIES = [{ y: 20, nom: 'v1.0', coul: '#2F4858' }, { y: H - 20 - VOIE_H, nom: 'v1.1', coul: '#2E7D6B' }];
  const POD_W = 96, POD_H = 112, POD_G = 14;
  const POD_Y = 150;

  const util = [...Array(NB_UTIL)].map((_, k) => ({ x: UTIL_X, y: 40 + k * ((H - 80) / (NB_UTIL - 1)), b: k % 2 === 1 }));
  const svgUtil = c => `<svg width="46" height="46" viewBox="0 0 46 46"><circle cx="23" cy="15" r="10" fill="${c}"/><path d="M5,44 C5,30 13,26 23,26 C33,26 41,30 41,44 Z" fill="${c}"/></svg>`;

  const lignes = util.map(u => `<line x1="${u.x + 26}" y1="${u.y}" x2="${ROUT_X - 110}" y2="${ROUT_Y}"/>`).join('')
    + VOIES.map(v => `<path d="M${ROUT_X + 110},${ROUT_Y} C${ROUT_X + 200},${ROUT_Y} ${VOIE_X - 90},${v.y + VOIE_H / 2} ${VOIE_X},${v.y + VOIE_H / 2}"/>`).join('');
  zone.innerHTML = `
    <svg class="t-lignes" width="${W}" height="${H}">${lignes}</svg>
    <div class="t-util">${util.map((u, k) => `<span class="t-u" data-k="${k}" style="left:${u.x - 23}px;top:${u.y - 23}px">${svgUtil('#5B6676')}</span>`).join('')}
      <span class="t-legende" style="left:${UTIL_X - 60}px;top:${H + 6}px">utilisateurs</span></div>
    <div class="t-rout" style="left:${ROUT_X - 110}px;top:${ROUT_Y - 62}px"><i>routeur</i><b>${cfg.routeur}</b><span class="t-err">0 erreur</span></div>
    ${VOIES.map((v, n) => `<div class="t-voie" data-n="${n}" style="left:${VOIE_X}px;top:${v.y}px;width:${VOIE_W}px;height:${VOIE_H}px;border-color:${v.coul}">
      <p class="t-tete"><b style="color:${v.coul}">${v.nom}</b><span class="t-pct" style="color:${v.coul}"></span></p><div class="t-pods"></div></div>`).join('')}
    <div class="t-points"></div>`;
  const pts = zone.querySelector('.t-points');
  const errEl = zone.querySelector('.t-err');
  const num = S.querySelector('[data-r="num"]'), texte = S.querySelector('[data-r="texte"]');
  let i = 0, erreurs = 0;

  function podXY(n, k) {
    return [VOIE_X + 20 + k * (POD_W + POD_G) + POD_W / 2, VOIES[n].y + POD_Y + POD_H / 2];
  }
  function rendre() {
    const e = cfg.etapes[i];
    num.textContent = (i + 1) + ' / ' + cfg.etapes.length;
    texte.innerHTML = e.texte;
    [e.v1 || [], e.v2 || []].forEach((pods, n) => {
      const voie = zone.querySelector(`.t-voie[data-n="${n}"]`);
      voie.querySelector('.t-pods').innerHTML = pods.map(p => `<span class="t-pod ${p}" style="background:${p === 'ok' ? VOIES[n].coul : ''};border-color:${VOIES[n].coul}">
        <small>${p === 'ok' ? 'sert' : p === 'demarre' ? 'démarre' : 'arrêt'}</small></span>`).join('');
      voie.classList.toggle('vide', !pods.length);
      const pct = e.miroir && n === 1 ? 'copie' : (e.segments ? (n ? 'groupe B' : 'groupe A') : (poids(e)[n] + ' %'));
      voie.querySelector('.t-pct').textContent = pods.length ? pct : '';
    });
    zone.querySelectorAll('.t-u').forEach((u, k) => u.innerHTML = svgUtil(e.segments ? (util[k].b ? '#E4572E' : '#2F4858') : '#5B6676'));
    erreurs = 0; errEl.textContent = '0 erreur'; errEl.classList.remove('on');
  }

  function trajet(el, etapes, duree, fin) {
    const a = el.animate(etapes.map(([x, y]) => ({ transform: `translate(${x - 9}px, ${y - 9}px)` })), { duration: duree, easing: 'linear', fill: 'forwards' });
    a.onfinish = fin;
  }
  function poids(e) {
    if (e.poids) return e.poids;
    const a = (e.v1 || []).filter(p => p === 'ok').length, b = (e.v2 || []).filter(p => p === 'ok').length;
    return a + b ? [Math.round(100 * a / (a + b)), Math.round(100 * b / (a + b))] : [0, 0];
  }
  function requete() {
    if (!S.classList.contains('active') && !S.dataset.toujours) return;
    const e = cfg.etapes[i];
    const k = Math.floor(Math.random() * NB_UTIL), u = util[k];
    let n;
    if (e.segments) n = u.b ? 1 : 0;
    else n = Math.random() * 100 < poids(e)[0] ? 0 : 1;
    const servants = (n ? e.v2 : e.v1 || []).map((p, j) => [p, j]).filter(([p]) => p === 'ok');
    const coul = e.segments ? (u.b ? '#E4572E' : '#2F4858') : '#F2C14E';
    const d = document.createElement('span'); d.className = 't-pt'; d.style.background = coul; pts.appendChild(d);
    if (!servants.length) {
      trajet(d, [[u.x + 24, u.y], [ROUT_X - 110, ROUT_Y]], 700, () => {
        d.textContent = '✕'; d.classList.add('ko'); erreurs++;
        errEl.textContent = erreurs + (erreurs > 1 ? ' erreurs' : ' erreur'); errEl.classList.add('on');
        setTimeout(() => d.remove(), 500);
      });
      return;
    }
    const [, j] = servants[Math.floor(Math.random() * servants.length)];
    trajet(d, [[u.x + 24, u.y], [ROUT_X, ROUT_Y], podXY(n, j)], 1300, () => d.remove());
    if (e.miroir) {
      const s2 = (e.v2 || []).map((p, j2) => [p, j2]).filter(([p]) => p === 'ok');
      if (!s2.length) return;
      const g = document.createElement('span'); g.className = 't-pt fantome'; pts.appendChild(g);
      const cible = podXY(1, s2[Math.floor(Math.random() * s2.length)][1]);
      trajet(g, [[ROUT_X, ROUT_Y], [ROUT_X, ROUT_Y], cible], 1300, () => { g.textContent = '∅'; setTimeout(() => g.remove(), 400); });
    }
  }
  setInterval(requete, 260);

  (window.etapes = window.etapes || {})[id] = {
    suivant() { if (i < cfg.etapes.length - 1) { i++; rendre(); return true; } return false; },
    precedent() { if (i > 0) { i--; rendre(); return true; } return false; },
    debut() { i = 0; rendre(); },
    fin() { i = cfg.etapes.length - 1; rendre(); },
  };
  rendre();
}
