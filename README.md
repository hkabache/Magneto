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

- **Général** : raccourci, position de la fenêtre d'enregistrement, post-traitement IA, typographie française, lancement au démarrage
- **Vocabulaire** : mots et termes techniques envoyés au moteur de transcription (keyterms) et au LLM de nettoyage
- **Clés API** : ElevenLabs, Mistral, Anthropic (stockées dans le trousseau macOS)

Au premier lancement, Magneto importe automatiquement le vocabulaire et les clés Mistral/Anthropic depuis l'installation Handy existante si elle est présente.

## Permissions

- **Microphone** : demandé au premier enregistrement
- **Accessibilité** : nécessaire pour le collage automatique (Cmd+V synthétique). Sans elle, le texte est copié dans le presse-papiers et un message invite à coller manuellement.

Ces autorisations survivent aux rebuilds, ce qui suppose un certificat en place.

TCC ne mémorise pas « cette app est autorisée » mais une exigence de signature, revérifiée à chaque appel. Signée en ad-hoc, l'exigence porte sur le `cdhash` du binaire : elle est invalidée à chaque compilation, et macOS refuse alors que la case reste cochée dans les Réglages Système. Magneto est donc signée avec un certificat auto-signé, ce qui déplace l'exigence sur le certificat.

Pour recréer ce certificat sur une autre machine : Trousseau d'accès → Assistant de certification → Créer un certificat, nom `Magneto Code Signing`, type d'identité « Racine auto-signée », type de certificat « Signature de code ». Aucun compte développeur nécessaire, et aucun réglage de confiance à poser, `codesign` accepte la racine auto-signée telle quelle.

`install.sh` affiche l'exigence obtenue en fin d'installation. Si `cdhash` y apparaît, le certificat est absent et les autorisations sauteront au prochain build.
