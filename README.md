# Magneto

Application macOS de dictée vocale en barre de menus. Un raccourci (Option+Espace par défaut) démarre l'enregistrement, le même raccourci l'arrête, le texte transcrit et nettoyé est collé au curseur.

Successeur minimaliste du fork Handy (conservé dans `legacy/` comme référence, non versionné dans ce repo).

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

## Prérequis

- macOS 26 minimum (Apple Silicon)
- Xcode 26+
- [xcodegen](https://github.com/yonaskolb/XcodeGen) : `brew install xcodegen`

## Build et installation

```bash
./scripts/install.sh   # build Release + installation dans /Applications + lancement
./scripts/dev.sh       # build Debug + installation dans /Applications + lancement
```

Les deux scripts compilent dans `~/Library/Developer/Xcode/DerivedData/Magneto` et suppriment la copie intermédiaire de l'app : Spotlight indexe tout `.app` qu'il trouve, et une recherche « Magneto » dans le Finder doit renvoyer une seule icône.

## Configuration

Tout se passe dans le popover de la barre de menus :

- **Général** : raccourci, position de la fenêtre d'enregistrement, délai Caps Lock, lancement au démarrage, post-traitement IA, typographie française
- **Vocabulaire** : mots et termes techniques envoyés au moteur de transcription (keyterms) et au LLM de nettoyage. À cette liste s'ajoute un vocabulaire intégré, non affiché et non modifiable, qui couvre les noms propres du produit lui-même (Magneto, ElevenLabs, Voxtral, Mistral, Anthropic, Claude) pour qu'on puisse parler de l'app à l'app sans rien configurer
- **Clés API** : groupées par usage. Transcription (ElevenLabs, Mistral) et nettoyage (Anthropic, plus la clé Mistral qui sert aux deux)

« Caps Lock sans délai » supprime le délai d'activation d'environ 100 ms que macOS impose sur la touche, et qui fait qu'un appui rapide ne l'active pas. Le réglage passe par `hidutil` et vaut pour tout le système, pas seulement pour Magneto. L'override ne survit pas à une déconnexion, donc Magneto le repose à chaque lancement tant que l'option est active. `hidutil` sait écrire une propriété mais pas l'effacer : désactiver l'option réécrit le délai d'origine au lieu de retirer l'override.

Les clés vivent dans le trousseau macOS, sous le service `com.hkabache.magneto` et les comptes `elevenlabs`, `mistral`, `anthropic`. Elles ne sont donc pas dans le bundle : supprimer l'app ne les efface pas, et une réinstallation les retrouve.

Sans aucune clé, Magneto fonctionne quand même, avec le seul moteur Apple hors ligne et le nettoyage par règles. Le nettoyage par IA est alors désactivé dans l'onglet Général, puisqu'il demande une clé Mistral ou Anthropic.

## Permissions

- **Microphone** : demandé au premier enregistrement
- **Accessibilité** : nécessaire pour le collage automatique (Cmd+V synthétique). Sans elle, le texte est copié dans le presse-papiers et un message invite à coller manuellement.

Ces autorisations survivent aux rebuilds, ce qui suppose un certificat en place.

TCC ne mémorise pas « cette app est autorisée » mais une exigence de signature, revérifiée à chaque appel. Signée en ad-hoc, l'exigence porte sur le `cdhash` du binaire : elle est invalidée à chaque compilation, et macOS refuse alors que la case reste cochée dans les Réglages Système. Magneto est donc signée avec un certificat auto-signé, ce qui déplace l'exigence sur le certificat.

Pour recréer ce certificat sur une autre machine : Trousseau d'accès → Assistant de certification → Créer un certificat, nom `Magneto Code Signing`, type d'identité « Racine auto-signée », type de certificat « Signature de code ». Aucun compte développeur nécessaire, et aucun réglage de confiance à poser, `codesign` accepte la racine auto-signée telle quelle.

`install.sh` affiche l'exigence obtenue en fin d'installation. Si `cdhash` y apparaît, le certificat est absent et les autorisations sauteront au prochain build.

## Licence

MIT augmentée de la [Commons Clause](https://commonsclause.com/).

Concrètement : tu peux utiliser Magneto librement, y compris au travail, l'étudier, le modifier et le partager. La seule chose interdite est de le vendre, ou de vendre un produit ou un service dont la valeur vient pour l'essentiel de Magneto.

Ce n'est donc pas une licence open source au sens de l'Open Source Initiative, mais une licence à source visible. Le code est fourni tel quel, sans garantie.
