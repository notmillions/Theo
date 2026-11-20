# Installation et développement de Theo

## Outils nécessaires

Sur macOS, installez Flutter stable depuis https://docs.flutter.dev/get-started/install/macos/mobile-ios, Android Studio avec Android SDK, Platform-Tools et Build-Tools. Pour les cibles Apple, installez Xcode Command Line Tools (`xcode-select --install`). Vérifiez l’environnement :
```bash
flutter doctor
flutter doctor --android-licenses
```
La liaison HC-06 utilise Bluetooth série classique. Testez avec un appareil Android appairé; le support iOS du profil Bluetooth requis par le plugin actuel n’est pas garanti.

## Packages Flutter
Depuis le dossier application :
```bash
cd drone_app
flutter pub get
```
Les dépendances se trouvent dans `pubspec.yaml`; `pubspec.lock` consigne les versions résolues. Le projet n’utilise pas Python.

## Démarrer et compiler
```bash
cd drone_app
flutter devices
flutter run
flutter build apk --release
```
L’APK sort dans `build/app/outputs/flutter-apk/app-release.apk`. Pour distribuer une version signée, configurez un keystore privé, à conserver hors de Git.

## Bluetooth Android
- Appairez le HC-06 depuis les réglages Bluetooth du téléphone.
- Accordez les permissions Bluetooth demandées; selon Android, la découverte peut demander la localisation.
- Le firmware initialise Bluetooth à 9600 bauds.
- Brochage indiqué : Arduino D2 (RX) ← TX du module, D5 (TX) → RX du module. Vérifiez les tensions et l’alimentation.

## Firmware Arduino
Le sketch est `arduino/arduino.ino`. Bibliothèques externes : Adafruit MPU6050, TinyGPSPlus et DFRobot_BMM150. Wire, Servo et SoftwareSerial proviennent du cœur de carte sélectionné.

Dans Arduino IDE, installez les bibliothèques via Library Manager. Avec Arduino CLI, après avoir installé le cœur correspondant et identifié FQBN/port :
```bash
arduino-cli lib install "Adafruit MPU6050" "TinyGPSPlus" "DFRobot_BMM150"
arduino-cli board list
arduino-cli compile --fqbn <FQBN> arduino
arduino-cli upload -p <PORT> --fqbn <FQBN> arduino
```
Remplacez les valeurs entre chevrons selon la carte. Broches du sketch : moteurs D6/D9/D10/D11, Bluetooth D2/D5, GPS D4/D3 et MPU6050 sur I²C.

## Sécurité des essais
Le firmware attend 15 secondes dans `setup()`, puis règle le throttle à 1150 et arme automatiquement les moteurs. Une commande de test moteurs existe aussi. Retirez les hélices pendant les essais, gardez une coupure physique accessible et validez toutes les commandes sur banc avant tout vol.

## Dépannage
- Flutter introuvable : ajoutez Flutter au PATH et rouvrez le terminal.
- SDK/licences Android manquants : configurez Android Studio puis relancez `flutter doctor`.
- Module Bluetooth invisible : appairez-le et vérifiez alimentation, RX/TX et débit.
- Erreur Arduino : contrôlez cœur de carte, FQBN, port et bibliothèques.
