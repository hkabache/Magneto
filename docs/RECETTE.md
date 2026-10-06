# Recette de non-régression

La liste des vérifications manuelles à rejouer pour s'assurer qu'une fonctionnalité qui marchait
marche encore. Les tests unitaires (`MagnetoTests/`) couvrent la logique pure ; cette recette couvre
ce qu'ils ne voient pas : l'écran, le micro, le collage dans une autre app, le système.

## Quand la passer

| Occasion | Périmètre |
|---|---|
| Avant chaque tag `v*` | Toute la recette Mac, et la partie iPhone si la version touche `Shared/` |
| Après une mise à jour de macOS | Toute la recette Mac |
| Après une mise à jour d'iOS | Toute la partie iPhone |
| Après une mise à jour de KeyboardShortcuts ou Sparkle | Les cas marqués **Socle** plus ceux de la dépendance |
| Après chaque modification, une fois installée | Les cas **Socle** plus ceux de la zone touchée |

Les cas **Socle** forment le passage rapide, une dizaine de minutes : s'ils échouent, inutile d'aller plus loin.

## Comment la passer

- Claude la passe avec computer use. Le popover n'est visible dans les captures qu'avec la build Debug
  (`./scripts/dev.sh`, voir CLAUDE.md) ; `./scripts/install.sh` remet la build Release à la fin.
- Sans voix humaine, la dictée se fait en jouant une phrase par les haut-parleurs vers le micro intégré :
  `say -v "Eddy (Français (France))" "Bonjour, ceci est un essai de dictée."`. Pour que le collage soit
  vérifiable, ouvrir un document TextEdit vide et y placer le curseur avant de lancer la dictée.
- La voix de synthèse ne prononce pas les guillemets : D-06 se dicte à la voix. Et pendant que Claude dicte,
  ne parlez pas près du Mac : le micro vous enregistre aussi et votre phrase se mêle à la sienne.
- Les cas marqués **Vous** demandent une main ou un appareil que Claude n'a pas (AirPods, iPhone, bouton
  Action), ou une touche que sa saisie simulée ne reproduit pas (Échap dans le champ Raccourci, Caps Lock) :
  Claude les liste à la fin et vous les passez.
- Un cas échoué se note avec ce qui a été observé, pas seulement « KO », et se corrige avant le tag.
- Chaque passage s'ajoute au tableau en bas de ce fichier.

La recette suit le code, dans le même commit que la modification : une fonctionnalité nouvelle ajoute
son cas, un comportement modifié réécrit le sien, une fonctionnalité retirée perd le sien, et un bug
corrigé devient un cas pour ne pas revenir.

## Mac

### Installation et lancement

| ID | Socle | Étapes | Résultat attendu |
|---|---|---|---|
| M-01 | ✓ | `./scripts/install.sh` | L'app se lance, l'icône d'onde apparaît dans la barre des menus. La signature affichée cite `AQ7LZD44WD`, pas de `cdhash` |
| M-02 | ✓ | Ouvrir le popover | Onglet Général affiché, état « Prêt », version correcte en bas |
| M-03 | | Ouvrir le DMG publié | Fenêtre d'installation avec fond, flèche, icône Magneto à gauche et Applications à droite |
| M-04 | | Retirer l'autorisation Accessibilité, relancer | Le popover affiche « Autorisation requise » ; la cocher fait passer à l'onglet Général tout seul ; « Continuer sans » y passe aussi |

### Popover

| ID | Socle | Étapes | Résultat attendu |
|---|---|---|---|
| P-01 | ✓ | Ouvrir le popover | Le champ Raccourci n'est **pas** sélectionné (régression de la 0.4.2) |
| P-02 | ✓ | Cliquer le champ Raccourci, taper ⌥Espace | Le champ s'encadre en gardant le raccourci affiché (« Saisir un raccourci » seulement s'il est vide), puis affiche ⌥Espace sans cadre ; aucune dictée ne démarre |
| P-03 | **Vous** | Cliquer le champ, taper « a » sans modificateur, puis Échap | Bip, raccourci inchangé ; Échap quitte le champ sans rien changer (la touche Échap simulée par Claude n'y arrive pas, la vraie oui) |
| P-04 | | Passer sur Vocabulaire puis Clés API, fermer, rouvrir | Chaque onglet s'affiche sans barre de défilement ; à la réouverture, retour sur Général |
| P-05 | | Survoler chaque ⓘ | La bulle d'aide apparaît tout de suite |
| P-06 | | Changer « Fenêtre d'enregistrement » (En haut, En bas, Masquée) puis dicter | La pastille suit le réglage, aucune en Masquée |
| P-07 | | Basculer « Lancer au démarrage » | Magneto apparaît puis disparaît dans Réglages > Général > Ouverture |
| P-08 | | Basculer « Caps Lock sans délai » | Activé, un appui bref sur Caps Lock l'allume ; désactivé, il faut le délai habituel |

### Dictée

| ID | Socle | Étapes | Résultat attendu |
|---|---|---|---|
| D-01 | ✓ | Curseur dans TextEdit, raccourci, phrase, raccourci | Pastille rouge pendant l'enregistrement, sablier, puis le texte est collé au curseur |
| D-02 | ✓ | Après D-01, vérifier le presse-papiers | Il contient ce qu'il contenait avant la dictée, pas le texte dicté |
| D-03 | ✓ | Popover, bouton « Copier » | La dernière dictée est copiée, le bouton affiche « Copié » |
| D-04 | | Lancer une dictée, Échap | Enregistrement annulé, rien n'est collé, retour à « Prêt » |
| D-05 | | Lancer une dictée depuis le bouton « Dicter » du popover | Même résultat que D-01 |
| D-06 | | Dicter « il a dit « bonjour » » avec Guillemets droits activé, puis désactivé | Activé : `"bonjour"` ; désactivé : les guillemets du moteur restent |
| D-07 | | Dicter une phrase avec un mot du vocabulaire (Vocabulaire > Ajouter) | Le mot sort avec l'orthographe enregistrée |
| D-08 | | Dicter environ une minute | Texte complet, sans coupure au milieu |
| D-09 | | Dicter dans une autre app (Notes, un champ web) | Collé au curseur pareil |
| D-12 | | Popover ouvert, « Dicter », parler, « Arrêter » dans le popover | Le texte n'est collé nulle part, le popover ayant le focus ; « Copier » le récupère |
| D-10 | **Vous** | Dicter avec des AirPods connectés | L'enregistrement démarre en quelques secondes, texte correct |
| D-11 | **Vous** | Débrancher ou couper le micro externe pendant une dictée | La dictée continue ou se termine proprement, jamais un blocage en « Enregistrement… » |

### Moteurs et clés

| ID | Socle | Étapes | Résultat attendu |
|---|---|---|---|
| E-01 | ✓ | Onglet Clés API | Les deux clés affichent un voyant vert |
| E-02 | | Moteur « Course », dicter | Texte reçu ; le journal système (`log show`, voir README) dit quel moteur a gagné |
| E-03 | | Moteur Microsoft seul, puis ElevenLabs seul, dicter | Texte reçu de chacun |
| E-04 | | Couper le Wi-Fi, dicter | Le moteur Apple prend le relais, le texte arrive quand même |
| E-05 | | Consommation « Ce mois-ci » après une dictée | Le compteur a augmenté |

### Diagnostic et mises à jour

| ID | Socle | Étapes | Résultat attendu |
|---|---|---|---|
| J-01 | | Journal des dictées activé, dicter | `~/Library/Application Support/Magneto/` contient l'audio et le texte du jour |
| J-02 | | Journal désactivé, dicter | Rien de nouveau dans ce dossier |
| U-01 | | « Vérifier les mises à jour » | Une fenêtre au premier plan répond : « Votre logiciel est à jour ! », ou propose la nouvelle version. Seule la vérification automatique reste silencieuse |
| U-02 | **Vous** | Après la publication, depuis la version précédente installée | La mise à jour s'installe et l'app relancée affiche la nouvelle version |

## iPhone

| ID | Socle | Étapes | Résultat attendu |
|---|---|---|---|
| I-01 | **Vous** | Installer depuis Xcode, ouvrir l'app | Réglages affichés, clés et voyants corrects |
| I-02 | **Vous** | Bouton « Dicter » dans l'app, parler, « Arrêter » | « Texte copié », la dictée apparaît dans l'historique |
| I-03 | **Vous** | Dans une autre app, bouton Action (raccourci Dicter), parler, rappuyer | Live Activity pendant l'enregistrement, le texte est dans le presse-papiers |
| I-04 | **Vous** | Lancer une dictée pendant une musique | La musique continue, la dictée aboutit |
| I-05 | **Vous** | Toucher une ancienne dictée de l'historique | Elle est recopiée |
| I-06 | **Vous** | Journal des dictées activé, dicter | Le fichier apparaît dans Fichiers > Sur mon iPhone > Magneto |

## Passages

| Date | Version | macOS / iOS | Périmètre | Résultat | Notes |
|---|---|---|---|---|---|
| 2026-10-06 | 0.4.3 (avant tag) | macOS 27.2 | Toute la recette Mac, avant le tag v0.4.3 | Tout bon, quatre cas réécrits | Claude : M-01, M-02, P-01, P-02, P-04 à P-07, D-01 à D-05, D-07 à D-09, E-01 à E-03, E-05, J-01, J-02, U-01. Vous : P-03 (Échap à la vraie touche). P-02 et U-01 réécrits (attendus périmés, pas des régressions), P-03 passé en **Vous**, D-12 ajouté. Restent à vous : M-04, P-08, D-06, D-10, D-11, E-04 ; après publication, M-03 et U-02 |
