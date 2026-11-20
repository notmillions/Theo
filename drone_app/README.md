# Theo — contrôle de drone

Application Flutter pour le pilotage et la télémétrie d’un drone via Bluetooth série classique (HC-06/SPP), avec firmware Arduino associé.

> **Précaution essentielle :** le firmware actuel arme automatiquement les moteurs après une attente de 15 secondes et règle le throttle à 1150 µs. Retirez les hélices pour tout essai au sol et gardez une coupure électrique accessible. Vérifiez le montage et les sécurités avant alimentation ou essai en vol. Ce logiciel n’est pas certifié pour la sécurité aéronautique.

## Contenu
- `lib/` : application Flutter, commandes, Bluetooth et terminal de diagnostic.
- `arduino/arduino.ino` : firmware de contrôle, moteurs, IMU, GPS et PID.
- `pubspec.yaml` / `pubspec.lock` : dépendances Flutter/Dart.
- `docs/INSTALLATION.md` : guide d’installation et de compilation.
- `requirements.txt` : inventaire indicatif des outils et bibliothèques.

## Prérequis
- Flutter stable et Dart conforme à la contrainte `^3.10.4` de `pubspec.yaml`.
- Android Studio et Android SDK pour compiler Android.
- Appareil Android avec Bluetooth classique pour la liaison HC-06. Le support iOS du plugin actuel n’est pas garanti.
- Arduino IDE ou Arduino CLI et une carte compatible avec le sketch.

Docker n’est pas requis : il ne fournit pas l’accès Bluetooth du téléphone et ne remplace pas Xcode pour les cibles Apple. L’app n’a pas de dépendances Python; `requirements.txt` est informatif et ne s’installe pas avec pip.

## Installer et lancer
```bash
cd drone_app
flutter doctor
flutter pub get
flutter run
```

Compiler l’APK :
```bash
flutter build apk --release
```
Résultat : `build/app/outputs/flutter-apk/app-release.apk`.

## Dépendances Flutter
Les paquets sont déclarés dans `pubspec.yaml` et leurs versions résolues sont fixées par `pubspec.lock` :
- `flutter_bluetooth_serial` — Bluetooth série classique.
- `permission_handler` — demandes d’autorisations Android.
- `cupertino_icons` — icônes.
- Développement : `flutter_test`, `flutter_lints`.

## Vérifications
```bash
cd drone_app
flutter analyze
flutter test
```

Voir [docs/INSTALLATION.md](docs/INSTALLATION.md) pour les étapes détaillées.

