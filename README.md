# Magneto

Dictée vocale pour macOS, dans la barre de menus. Un raccourci démarre l'enregistrement, le même l'arrête, et le texte transcrit puis nettoyé arrive directement au curseur, dans n'importe quelle application.

## Installation

1. Télécharger le `.dmg` de la [dernière version](https://github.com/hkabache/Magneto/releases/latest)
2. Ouvrir le DMG et glisser Magneto dans Applications
3. Lancer l'app : une icône apparaît dans la barre de menus, en haut à droite
4. Autoriser le microphone, puis l'accessibilité, quand l'app les demande

macOS 26 minimum, Mac Apple Silicon. L'app est signée et notarisée par Apple : elle s'ouvre normalement, sans avertissement ni détour par les Réglages Système.

L'accessibilité sert au collage automatique. Sans elle Magneto fonctionne quand même, mais le texte se contente d'arriver dans le presse-papiers et il faut faire Cmd+V soi-même.

Pour mettre à jour, **Vérifier les mises à jour** en bas du popover : Magneto interroge GitHub, propose la nouvelle version s'il y en a une, l'installe et se relance. Rien ne part sans ce clic, il n'y a aucune vérification en arrière-plan.

Une mise à jour n'est installée que si elle est signée par une clé privée qui ne quitte jamais mes secrets, la clé publique correspondante étant compilée dans l'app. Quelqu'un qui prendrait le contrôle du dépôt pourrait publier ce qu'il veut, Magneto refuserait de l'installer.

## Pourquoi

**Gratuite, et elle le restera.** La licence interdit de la vendre.

**Sans aucune clé, ton audio ne quitte pas ta machine.** Le moteur de transcription d'Apple et le nettoyage par règles tournent en local. Seule exception, une fois : si le modèle de dictée française n'est pas déjà installé sur le Mac, macOS le télécharge chez Apple à la première utilisation. Une clé API n'est utile que pour monter en qualité, et reste facultative.

**Tu paies l'usage, pas un abonnement.** Les services équivalents se facturent au mois, que tu dictes ou non. Ici tu règles directement le fournisseur, au tarif public et pour les secondes que tu as réellement dictées, sans intermédiaire qui prend sa marge au passage.

**Tes clés, ton audio.** Les clés sont les tiennes et vivent dans le trousseau macOS. L'audio part de ton Mac vers le fournisseur que tu as choisi, et nulle part ailleurs : aucun serveur intermédiaire, aucun compte à créer, aucune télémétrie, aucun outil d'analytique. Pour dicter, les seules adresses contactées sont `api.elevenlabs.io`, `api.mistral.ai` et `api.anthropic.com`. S'y ajoutent Apple, une seule fois et seulement si le modèle de dictée local doit être installé, et GitHub, uniquement quand tu cliques sur « Vérifier les mises à jour », le temps de lire le fichier qui décrit la dernière version et de télécharger le DMG. Le code est public pour que tu puisses le vérifier plutôt que me croire.

C'est la différence de fond avec un service qui mutualise ses propres clés : au lieu d'ignorer ce que devient ta voix, tu contractes directement avec le fournisseur, tu lis ses conditions, et tu révoques ta clé quand tu veux.

## Fonctionnement

```
Option+Espace → enregistrement micro (Échap pour annuler)
Option+Espace → transcription :
  1. ElevenLabs Scribe v2 (principal, no_verbatim + keyterms)
  2. Voxtral Mistral (fallback si clé présente)
  3. Apple SpeechAnalyzer (fallback local, hors-ligne)
→ passe de nettoyage par règles (artefacts "...", typographie française)
→ passe LLM optionnelle (Mistral Small ou Claude Haiku) : tics de langage, ponctuation, vocabulaire
→ collage au curseur (Cmd+V synthétique, presse-papiers restauré)
```

## Réglages

Tout se passe dans le popover de la barre de menus :

- **Général** : raccourci, position de la fenêtre d'enregistrement, délai Caps Lock, lancement au démarrage, nettoyage par IA, typographie française
- **Vocabulaire** : mots et termes techniques envoyés au moteur de transcription et au LLM de nettoyage. À cette liste s'ajoute un vocabulaire intégré, non affiché et non modifiable, qui couvre les noms propres du produit lui-même (Magneto, ElevenLabs, Voxtral, Mistral, Anthropic, Claude) pour qu'on puisse parler de l'app à l'app sans rien configurer
- **Clés API** : groupées par usage. Transcription (ElevenLabs, Mistral) et nettoyage (Anthropic, plus la clé Mistral qui sert aux deux)

Sans aucune clé, Magneto fonctionne, avec le seul moteur Apple hors ligne et le nettoyage par règles. Le nettoyage par IA est alors grisé, puisqu'il demande une clé Mistral ou Anthropic.

Les clés vivent dans le trousseau macOS, sous le service `com.hkabache.magneto` et les comptes `elevenlabs`, `mistral`, `anthropic`. Elles ne sont donc pas dans le bundle : supprimer l'app ne les efface pas, et une réinstallation les retrouve.

« Caps Lock sans délai » supprime le délai d'activation d'environ 100 ms que macOS impose sur la touche, et qui fait qu'un appui rapide ne l'active pas. Le réglage passe par `hidutil` et vaut pour tout le système, pas seulement pour Magneto. L'override ne survit pas à une déconnexion, donc Magneto le repose à chaque lancement tant que l'option est active. `hidutil` sait écrire une propriété mais pas l'effacer : désactiver l'option réécrit le délai d'origine au lieu de retirer l'override.

## Signaler un problème

Le bouton **Diagnostic**, en bas du popover, copie le déroulé des dictées faites depuis le lancement de l'app : moteurs disponibles, celui qui a répondu, raison de chaque repli, durées, et ce que la passe de nettoyage a fait ou n'a pas fait. Il n'y a plus qu'à le coller dans un message.

Ce déroulé vient du journal système de macOS, où Magneto écrit au fil de l'eau. Il ne quitte la machine que si on l'y colle soi-même, et il ne contient ni le texte dicté, ni le vocabulaire, ni les clés.

## Développement

Xcode 26 et [xcodegen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`), qui génère `Magneto.xcodeproj` à partir de `project.yml`.

```bash
./scripts/dev.sh       # build Debug + installation dans /Applications + lancement
./scripts/install.sh   # build Release + installation dans /Applications + lancement
xcodebuild test -project Magneto.xcodeproj -scheme Magneto -destination 'platform=macOS'
```

Les tests couvrent ce qui décide du texte livré sans passer par le réseau : le nettoyage par règles, la mise en forme du vocabulaire attendue par chaque moteur, et le garde-fou qui accepte ou rejette la sortie du LLM.

Les deux scripts compilent dans `~/Library/Developer/Xcode/DerivedData/Magneto` et suppriment la copie intermédiaire de l'app : Spotlight indexe tout `.app` qu'il trouve, et une recherche « Magneto » dans le Finder doit renvoyer une seule icône.

Un tag `v*` déclenche la release : tests, DMG signé, notarisation par Apple, agrafage du ticket, signature du flux Sparkle, publication du DMG et de l'`appcast.xml` que l'app viendra lire.

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
