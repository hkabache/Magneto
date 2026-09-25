<h1 align="center">Magneto</h1>

<p align="center">
  Dictée vocale pour macOS, dans la barre de menus.<br>
  Un raccourci démarre l'enregistrement, le même l'arrête, et le texte transcrit arrive
  directement au curseur, dans n'importe quelle application.
</p>

<p align="center">
  <a href="https://github.com/hkabache/Magneto/releases/latest/download/Magneto.dmg">
    <img src="docs/download.svg" width="240" alt="Télécharger Magneto">
  </a>
</p>

<p align="center">
  <sub>macOS 26 minimum · Mac Apple Silicon · signée et notarisée par Apple</sub>
</p>

## Utilisation

Magneto n'ouvre aucune fenêtre : son icône s'installe dans la barre de menus, en haut à droite de l'écran. Au premier lancement, elle demande le microphone, puis l'accessibilité.

- **Option+Espace** démarre la dictée, **Option+Espace** l'arrête et colle le texte
- **Échap** annule l'enregistrement en cours
- l'**icône de la barre de menus** ouvre les réglages, et un bouton y recopie la dernière dictée

L'accessibilité sert au collage automatique. Sans elle Magneto fonctionne quand même, mais le texte se contente d'arriver dans le presse-papiers et il faut faire Cmd+V soi-même.

Une fois par semaine, Magneto regarde s'il existe une version plus récente, et n'ouvre aucune fenêtre pour le dire : quand il y en a une, le bas du popover propose **Mettre à jour vers…**. Le clic ouvre la fenêtre de mise à jour, avec la liste de ce qui change, et c'est là que l'installation se décide. Rien ne s'installe tout seul, et **Vérifier les mises à jour** reste là pour forcer le contrôle sans attendre.

## Pourquoi

**Gratuite, et elle le restera.** La licence interdit de la vendre.

**Sans clé, ton audio ne quitte pas ta machine.** Le moteur de transcription d'Apple tourne en local. Seule exception, une fois : si le modèle de dictée française n'est pas déjà installé sur le Mac, macOS le télécharge chez Apple à la première utilisation. Une clé API n'est utile que pour monter en qualité, et reste facultative.

**Tu paies l'usage, pas un abonnement.** Les services équivalents se facturent au mois, que tu dictes ou non. Ici tu règles directement le fournisseur, au tarif public et pour les secondes que tu as réellement dictées, sans intermédiaire qui prend sa marge au passage.

**Tes clés, ton audio.** Les clés sont les tiennes et vivent dans le trousseau macOS. L'audio part de ton Mac vers le fournisseur que tu as choisi, et nulle part ailleurs : aucun serveur intermédiaire, aucun compte à créer, aucune télémétrie, aucun outil d'analytique.

Pour dicter, la seule adresse contactée est `api.elevenlabs.io`, et un seul appel réseau par dictée. S'y ajoutent Apple, une seule fois et seulement si le modèle de dictée local doit être installé, et GitHub, une fois par semaine et à chaque clic sur « Vérifier les mises à jour », le temps de lire le fichier qui décrit la dernière version, puis de télécharger le DMG si tu acceptes la mise à jour. Le code est public pour que tu puisses le vérifier plutôt que me croire.

C'est la différence de fond avec un service qui mutualise ses propres clés : au lieu d'ignorer ce que devient ta voix, tu contractes directement avec le fournisseur, tu lis ses conditions, et tu révoques ta clé quand tu veux.

**Une mise à jour ne s'installe que si je l'ai signée.** La clé privée qui signe le flux ne quitte jamais mes secrets, la clé publique correspondante est compilée dans l'app. Quelqu'un qui prendrait le contrôle du dépôt pourrait publier ce qu'il veut, Magneto refuserait de l'installer.

## Fonctionnement

```
Option+Espace → enregistrement micro (Échap pour annuler)
Option+Espace → transcription :
  1. ElevenLabs Scribe v2 (principal, no_verbatim + keyterms)
  2. Apple SpeechAnalyzer (fallback local, hors-ligne)
→ guillemets « » remplacés par des " (désactivable, seule modification du texte)
→ collage au curseur (Cmd+V synthétique, presse-papiers restauré)
```

## iPhone

La même dictée, sans fenêtre : un raccourci la démarre, le même l'arrête, et le texte arrive dans le presse-papiers, que le clavier propose alors de coller. Magneto ne s'ouvre jamais pendant une dictée.

- **Bouton Action** ou **Toucher le dos** lancent le raccourci « Dicter » : un appui démarre, le suivant arrête et copie
- la **pilule** de la Dynamic Island montre l'enregistrement et son chrono, puis la transcription, puis « Texte prêt »
- l'**app** ne sert qu'aux réglages, clé, vocabulaire et journal, plus une dictée de secours qui copie directement

Installation : depuis Xcode sur le téléphone, cible `MagnetoIOS`, l'app n'est pas distribuée. Dans l'app, **Installer le raccourci Dicter** l'ajoute à Raccourcis en deux touches, puis Réglages > Bouton Action > Raccourci > Dicter, et Réglages > Accessibilité > Toucher > Toucher le dos > Dicter. Au premier passage, Raccourcis demande deux fois « toujours autoriser », pour le micro et pour le collage.

Pourquoi un raccourci et pas l'app seule : iOS n'ouvre pas le presse-papiers à un processus qui tourne en arrière-plan, l'écriture est ignorée sans erreur. L'action « Dicter » rend donc le texte, et c'est Raccourcis, qui a ce droit, qui le copie. Le raccourci tient en trois actions : « Dicter », « Si Texte a une valeur », « Copier dans le presse-papiers ».

Écran éteint, le bouton Action réveille l'écran et rien de plus : iOS ne lance pas de raccourci tiers depuis là. Écran allumé, verrouillé ou non, tout fonctionne.

Le journal des dictées s'écrit dans Fichiers > Sur mon iPhone > Magneto. Les adresses contactées sont les mêmes que sur Mac, moins GitHub : pas de mise à jour automatique, l'app se réinstalle depuis Xcode.

## Réglages

Tout se passe dans le popover de la barre de menus :

- **Général** : raccourci, position de la fenêtre d'enregistrement, délai Caps Lock, lancement au démarrage, guillemets droits, journal des dictées
- **Vocabulaire** : mots et termes techniques envoyés au moteur de transcription comme keyterms. À cette liste s'ajoute un vocabulaire intégré, non affiché et non modifiable, qui couvre les noms propres du produit lui-même (Magneto, ElevenLabs) pour qu'on puisse parler de l'app à l'app sans rien configurer
- **Clés API** : la clé ElevenLabs, seule clé de l'app. Elle vit dans le trousseau macOS, sous le service `com.hkabache.magneto` et le compte `elevenlabs` : supprimer l'app ne l'efface pas, et une réinstallation la retrouve

Sans clé, Magneto fonctionne avec le moteur Apple hors ligne.

**Guillemets droits** est la seule modification que Magneto apporte au texte du moteur : les `« »` et les guillemets courbes deviennent des `"` droits. Décoché, le texte est collé exactement tel que le moteur l'a rendu.

**Caps Lock sans délai** supprime le délai d'activation d'environ 100 ms que macOS impose sur la touche, et qui fait qu'un appui rapide ne l'active pas. Le réglage passe par `hidutil` et vaut pour tout le système, pas seulement pour Magneto. L'override ne survit pas à une déconnexion, donc Magneto le repose à chaque lancement tant que l'option est active. `hidutil` sait écrire une propriété mais pas l'effacer : désactiver l'option réécrit le délai d'origine au lieu de retirer l'override.

## Signaler un problème

Magneto écrit au fil de l'eau dans le journal système de macOS : le moteur qui a répondu, la raison de chaque repli, les durées, la latence d'ouverture du micro et ses éventuelles relances. Rien n'en sort tout seul, et il ne contient ni le texte dicté, ni le vocabulaire, ni les clés.

```bash
log show --predicate 'subsystem == "com.hkabache.magneto"' --last 1d --style compact
```

Le réglage **Journal des dictées** répond à une autre question : ce que valent les moteurs les uns contre les autres, et ce que la normalisation des guillemets a changé. Il écrit dans `~/Library/Application Support/Magneto` chaque dictée, son audio, et son texte avant et après, avec le nombre de mots modifiés. Contrairement au journal système, **ces fichiers contiennent le texte dicté en clair et les enregistrements**, soit environ 2 Mo par minute dictée. Il est désactivé par défaut : on l'active le temps d'une comparaison, puis on supprime le dossier.

## Développement

Xcode 26 et [xcodegen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`), qui génère `Magneto.xcodeproj` à partir de `project.yml`.

```bash
./scripts/dev.sh       # build Debug + installation dans /Applications + lancement
./scripts/install.sh   # build Release + installation dans /Applications + lancement
xcodebuild test -project Magneto.xcodeproj -scheme Magneto -destination 'platform=macOS'
```

Les tests couvrent ce qui décide du texte livré sans passer par le réseau : la normalisation des guillemets et ce qu'elle ne doit pas toucher, la mise en forme des keyterms attendue par Scribe, et l'état de la capture audio.

La cible iPhone se compile et s'installe depuis le terminal, téléphone branché et déverrouillé, son identifiant venant de `xcrun devicectl list devices` :

```bash
xcodebuild -project Magneto.xcodeproj -scheme MagnetoIOS -destination 'id=<UDID>' \
  -derivedDataPath ~/Library/Developer/Xcode/DerivedData/Magneto -allowProvisioningUpdates build
xcrun devicectl device install app --device <UDID> \
  ~/Library/Developer/Xcode/DerivedData/Magneto/Build/Products/Debug-iphoneos/Magneto.app
```

Les deux scripts compilent dans `~/Library/Developer/Xcode/DerivedData/Magneto` et suppriment la copie intermédiaire de l'app : Spotlight indexe tout `.app` qu'il trouve, et une recherche « Magneto » dans le Finder doit renvoyer une seule icône.

Un tag `v*` déclenche la release : tests, DMG signé, notarisation par Apple, agrafage du ticket, signature du flux Sparkle, publication du DMG et de l'`appcast.xml` que l'app viendra lire. Le DMG est publié sous un nom sans version, `Magneto.dmg`, pour que le bouton de téléchargement du README pointe sur une URL permanente.

### Clés de mise à jour

La paire EdDSA de Sparkle est indépendante du certificat Apple : la clé publique est dans `project.yml`, donc compilée dans chaque copie de l'app, et la clé privée n'apparaît nulle part dans le dépôt.

La perdre n'est pas fatal tant que le certificat Developer ID est intact : Sparkle sait faire tourner les clés, en publiant une version qui change soit le certificat Apple, soit la paire EdDSA, jamais les deux d'un coup. Perdre les deux en même temps, en revanche, obligerait tout le monde à réinstaller l'app à la main. Une seule paire suffit pour toutes les apps qu'on signerait avec Sparkle.

### Signature et permissions

TCC ne mémorise pas « cette app est autorisée » mais une exigence de signature, revérifiée à chaque appel. En ad-hoc, cette exigence porte sur le `cdhash` du binaire : invalidée à chaque compilation, elle fait refuser l'app alors que la case reste cochée dans les Réglages Système. Magneto est signée avec un certificat Developer ID, ce qui déplace l'exigence sur l'identifiant d'équipe du certificat : elle survit aux rebuilds, et au renouvellement du certificat.

Compiler sans ce certificat demande de remplacer `CODE_SIGN_IDENTITY` par `-` dans `project.yml`. L'app fonctionne, mais microphone et accessibilité sont à re-cocher après chaque build.

`install.sh` affiche l'exigence obtenue en fin d'installation. Si `cdhash` y apparaît, le certificat est absent et les autorisations sauteront au prochain build.

## Licence

MIT augmentée de la [Commons Clause](https://commonsclause.com/).

Concrètement : tu peux utiliser Magneto librement, y compris au travail, l'étudier, le modifier et le partager. La seule chose interdite est de le vendre, ou de vendre un produit ou un service dont la valeur vient pour l'essentiel de Magneto.

Ce n'est donc pas une licence open source au sens de l'Open Source Initiative, mais une licence à source visible. Le code est fourni tel quel, sans garantie.
