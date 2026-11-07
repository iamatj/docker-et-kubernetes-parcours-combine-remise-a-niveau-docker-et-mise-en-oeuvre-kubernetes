# Les slides

Ouvrez `index.html` dans un navigateur : flèches (ou espace) pour avancer, `N` pour afficher les notes du formateur, `F` pour le plein écran. Le lien `index.html#c7-yaml` ouvre directement une slide.

| Fichier | Rôle |
|---------|------|
| `slides/<id>.html` | une slide par fichier (1920 × 1080), notes du formateur dans `<aside>` |
| `deck.json` | titre, ordre des slides, sections, polices |
| `construire.py` | assemble `index.html`, page autonome |
| `index.html` | généré : ne pas modifier à la main |

Après une modification : `python presentation/construire.py`.

Charte : nuit `#1F2A44` (couverture, incidents, fins de journée), soleil `#F2C14E` (accents sur fond sombre), balise `#E4572E` (pauses), sapin `#2E7D6B` (concepts), ardoise `#2F4858` (TP, déjeuners), neige `#F4F6F8` (fond clair).
