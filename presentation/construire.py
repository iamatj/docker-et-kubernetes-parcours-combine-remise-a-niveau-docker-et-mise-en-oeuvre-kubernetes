"""Assemble les slides de presentation/slides/ en une page autonome presentation/index.html.

Usage : python presentation/construire.py
La page s'ouvre dans un navigateur : flèches pour naviguer, F pour le plein écran.
"""
import html
import json
import pathlib
import re

ICI = pathlib.Path(__file__).parent
deck = json.loads((ICI / "deck.json").read_text(encoding="utf-8"))

# Équivalents texte des icônes de l'éditeur de slides
ICONES = {
    "Clock": "◷", "Warning": "⚠", "Lightbulb": "✦", "Code": "</>", "Wrench": "⚒",
    "CheckCircle": "✔", "Check": "✓", "Star": "★", "Book": "▤", "Activity": "∿",
    "Chart": "▥", "Database": "⛁", "Settings": "⚙", "Cloud": "☁", "Chat": "✉",
    "Home": "⌂", "Coffee": "☕", "Server": "▣", "Refresh": "↻", "Lock": "⚿", "Ticket": "◈",
}

slides = []
for ident in deck["order"]:
    s = (ICI / "slides" / f"{ident}.html").read_text(encoding="utf-8").strip()
    s = re.sub(
        r'<x-icon name="(\w+)"([^>]*)></x-icon>',
        lambda m: f'<x-icon data-g="{html.escape(ICONES.get(m.group(1), "•"))}"{m.group(2)}></x-icon>',
        s,
    )
    slides.append(s)

# Code et styles communs à plusieurs slides (stratégies de déploiement)
commun = "<style>\n" + (ICI / "trafic.css").read_text(encoding="utf-8") + "</style>\n<script>\n" + (ICI / "trafic.js").read_text(encoding="utf-8") + "</script>"

polices = "\n".join(
    f'<link rel="stylesheet" href="{f["href"]}">' for f in deck["faces"].values() if "href" in f
)

page = f"""<!doctype html>
<html lang="fr">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{html.escape(deck["title"])}</title>
{polices}
{commun}
<style>
  html, body {{ margin: 0; height: 100%; background: #111; overflow: hidden; }}
  #scene {{ position: absolute; left: 50%; top: 50%; width: 1920px; height: 1080px; transform-origin: center; }}
  /* les slides portent leur propre display en ligne : on masque avec visibility */
  section {{ position: absolute; inset: 0; box-sizing: border-box; overflow: hidden; visibility: hidden; }}
  section.active {{ visibility: visible; }}
  section * {{ margin: 0; box-sizing: border-box; }}
  section ul, section ol {{ padding-left: 1.2em; }}
  section table {{ border-collapse: collapse; width: 100%; }}
  section th, section td {{ border-bottom: 2px solid rgba(0,0,0,.15); padding: .35em .6em; text-align: left; }}
  section th {{ font-weight: 700; }}
  x-shape {{ display: block; flex: none; }}
  x-shape[kind="arrow-right"] {{ clip-path: polygon(0 30%, 60% 30%, 60% 0, 100% 50%, 60% 100%, 60% 70%, 0 70%); }}
  x-shape[kind="arrow-left"] {{ clip-path: polygon(100% 30%, 40% 30%, 40% 0, 0 50%, 40% 100%, 40% 70%, 100% 70%); }}
  x-icon {{ display: inline-flex; align-items: center; justify-content: center; flex: none; font-family: 'DejaVu Sans', 'Segoe UI Symbol', sans-serif; }}
  x-icon::before {{ content: attr(data-g); font-size: 0.8em; line-height: 1; }}
  #compteur {{ position: fixed; right: 14px; bottom: 10px; color: #999; font: 14px Arial, sans-serif; }}
</style>
</head>
<body>
<div id="scene">
{chr(10).join(slides)}
</div>
<div id="compteur"></div>
<script>
  const slides = [...document.querySelectorAll('section')];
  const scene = document.getElementById('scene');
  // la taille des icônes vient de leur largeur
  document.querySelectorAll('x-icon').forEach(i => {{ i.style.fontSize = i.style.width || '48px'; }});
  let n = Math.max(0, slides.findIndex(s => '#' + s.id === location.hash));
  function afficher() {{
    slides.forEach((s, i) => s.classList.toggle('active', i === n));
    document.getElementById('compteur').textContent = (n + 1) + ' / ' + slides.length;
    history.replaceState(null, '', '#' + slides[n].id);
  }}
  function ajuster() {{
    const k = Math.min(innerWidth / 1920, innerHeight / 1080);
    scene.style.transform = 'translate(-50%, -50%) scale(' + k + ')';
  }}
  // Une slide à étapes (window.etapes[id]) consomme les flèches avant de passer à la suivante.
  const etapes = () => (window.etapes || {{}})[slides[n].id];
  function avancer() {{
    if (etapes() && etapes().suivant()) return;
    n = Math.min(n + 1, slides.length - 1);
    if (etapes()) etapes().debut();
  }}
  function reculer() {{
    if (etapes() && etapes().precedent()) return;
    n = Math.max(n - 1, 0);
    if (etapes()) etapes().fin();
  }}
  addEventListener('keydown', e => {{
    if (['ArrowRight', 'PageDown', ' '].includes(e.key)) avancer();
    else if (['ArrowLeft', 'PageUp'].includes(e.key)) reculer();
    else if (e.key === 'Home') n = 0;
    else if (e.key === 'End') n = slides.length - 1;
    else if (e.key === 'f' || e.key === 'F') document.fullscreenElement ? document.exitFullscreen() : document.documentElement.requestFullscreen();
    else return;
    e.preventDefault(); afficher();
  }});
  addEventListener('click', () => {{ avancer(); afficher(); }});
  addEventListener('resize', ajuster);
  ajuster(); afficher();
</script>
</body>
</html>
"""
(ICI / "index.html").write_text(page, encoding="utf-8")
print(f"{len(slides)} slides -> {ICI / 'index.html'}")
