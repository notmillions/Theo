# 🚁 Drone Control - Migration Kivy → Flutter

## 📋 Contexte

Application de contrôle de drone originalement développée en **Python 3 + Kivy 2.3.0 + KivyMD 1.2.0**, migré vers **Flutter (Dart)**.

### Équivalences Python/Kivy → Flutter

| **Kivy (Python)** | **Flutter (Dart)** |
|---|---|
| `Config.set('input','wm_touch','disable')` | N/A (Flutter gère nativement) |
| `Config.set('input','wm_pen','disable')` | N/A (TODO: spécifique Kivy/Windows) |
| `MDScreen` | `Scaffold` |
| `MDBoxLayout(orientation='vertical')` | `Column` |
| `MDRaisedButton` | `ElevatedButton` |
| `MDIcon` | `Icon` (Material Icons) |
| `Clock.schedule_interval(func, 0.5)` | `Timer.periodic(Duration(ms:500), ...)` |
| `RelativeLayout` + drawing | `Stack` + `CustomPainter` |
| `Joystick(RelativeLayout)` + clamp | Custom `JoystickWidget` |

---

## 📁 Structure du projet

```
drone_app/
├── lib/
│   └── main.dart              # Code complet de l'application
├── test/
│   └── widget_test.dart       # Tests unitaires (smoke tests)
├── pubspec.yaml               # Configuration Flutter (dépendances)
└── android/                   # Configuration Android
```

---

## ⚙️ Spécifications techniques

- **Framework** : Flutter (Dart)
- **Theme** : Material 3, Dark Mode
- **Couleur seed** : Teal (`Colors.teal`)
- **Cible** : Android (nécessite Android SDK)

### Dépendances

**Aucune dépendance externe requise.** Le projet utilise uniquement:
- `flutter/material.dart` (Material Design 3)
- `dart:async` (Timer)
- `dart:math` (calculs géométriques)

---

## 🎨 Interface utilisateur

### Layout (3 sections)

```
┌─────────────────────────────────────────┐
│  🚁 Drone Control                       │ ← AppBar
├─────────────────────────────────────────┤
│  TÉLÉMÉTRIE                             │
│  [Roll] [Pitch] [Power] [Heading]       │
├─────────────────────────────────────────┤
│  [ARMER LES MOTEURS] [ATTERRISSAGE AUTO]│
├─────────────────────────────────────────┤
│  JOYSTICKS                              │
│  [Gauche(Gaz/Yaw)] [Droite(Pitch/Roll)]│
│  x:0.00 y:0.00        x:0.00 y:0.00    │
└─────────────────────────────────────────┘
```

### 1. Télémétrie (Haut)

Affiche 4 items mis à jour en temps réel (tous les 500ms):
- **Roll** (Roulis): -45°..+45°
- **Pitch** (Tangage): -45°..+45°
- **Heading** (Nord magnétique): 0°..360°
- **Power** (Puissance moteur): 0%..100%

### 2. Commandes (Milieu)

Deux boutons côte à côte:

**A) Bouton ARM/EMERGENCY**
- État désarmé: 🟢 "ARMER LES MOTEURS" (Vert)
  - Au clic: active les moteurs + joysticks
- État armé: 🔴 "COUPURE D'URGENCE" (Rouge)
  - Au clic: coupe les moteurs + reset joysticks au centre

**B) Bouton ATTERRISSAGE AUTO**
- Bleu, affiché mais **désactivé si moteurs désarmés**
- Au clic: affiche SnackBar + log debug

### 3. Joysticks (Bas)

Deux joysticks identiques côte à côte (cercles avec knob teal):

**Joystick Gauche** (Throttle + Yaw)
- Commande: Gaz (Throttle) + Lacet (Yaw)
- Si Motors OFF: opacity 0.4, aucun drag

**Joystick Droite** (Pitch + Roll)
- Commande: Tangage (Pitch) + Roulis (Roll)
- Si Motors OFF: opacity 0.4, aucun drag

**Logique du joystick:**
- Cercle de fond (teal 0.2 opacity)
- Petit cercle (knob) suit le doigt
- **Clamp mathématique**: si distance > rayon → projete sur le périmètre
- Valeurs normalisées: `-1.0` à `+1.0` (axe X, axe Y)
- Au relâchement: retour EXACT au centre `(0.0, 0.0)`
- Affichage debug: `x:0.00 y:0.00` (2 décimales)

---

## 🔧 État global (State)

```dart
// Moteurs
bool moteursArmes = false;

// Télémétrie
double roll, pitch, heading, power;

// Joysticks (normalisés -1..+1)
double leftX, leftY;   // Gauche (Yaw, Throttle)
double rightX, rightY; // Droite (Roll, Pitch)

// Timer pour simulation telemetry (équivalent Clock.schedule_interval)
late Timer _telemetryTimer;
```

---

## 📡 Points d'intégration

### 1. Capteurs (Simulation → Réel)

**Fichier**: [lib/main.dart](lib/main.dart#L87-L105)

Actuellement: valeurs aléatoires (simulation)

```dart
// TODO: Connecter les vrais capteurs ici (Bluetooth/Arduino/UART)
roll = _random.nextDouble() * 90 - 45;    // À remplacer par capteur
pitch = _random.nextDouble() * 90 - 45;   // À remplacer par capteur
heading = _random.nextDouble() * 360;     // À remplacer par capteur
power = _random.nextDouble() * 100;       // À remplacer par capteur
```

**Implémentation Bluetooth/UART** (exemple pseudocode):
```dart
// Remplacer le bloc setState ci-dessus par:
final sensorData = await bluetoothService.readTelemetry();
setState(() {
  roll = sensorData.roll;
  pitch = sensorData.pitch;
  heading = sensorData.heading;
  power = sensorData.power;
});
```

### 2. Commandes Joystick (Flutter → Drone)

**Fichier**: [lib/main.dart](lib/main.dart#L125-L140)

Actuellement: log debug (`debugPrint`)

```dart
// TODO: Envoyer les commandes joystick au drone ici (Bluetooth/Arduino/UART)
void _handleLeftJoystickChange(Offset offset) {
  setState(() {
    leftX = offset.dx;
    leftY = offset.dy;
  });
  debugPrint('[JOYSTICK-L] x=$leftX, y=$leftY');
  // À remplacer par: bluetoothService.sendCommand({throttle: leftY, yaw: leftX});
}
```

---

## 🏃 Exécution

### Prérequis

- Flutter SDK (stable)
- Android emulator ou appareil Android connecté

### Lancer l'app

```bash
cd drone_app
flutter run
```

### Run en mode release (optimisé)

```bash
flutter run --release
```

### Tests

```bash
flutter test
```

---

## 🐛 Debugging

### Affichage des valeurs joystick

Les valeurs joysticks sont affichées en temps réel sous chaque joystick:
```
x:0.42 y:-0.65
```

### Logs debug

```bash
# Dans VS Code, regarder la console "Debug Console"
[JOYSTICK-L] x=0.42, y=-0.65
[JOYSTICK-R] x=-0.12, y=0.88
[DRONE] Auto-landing sequence started
```

### Hot Reload

```bash
flutter run
# Puis appuyer sur 'r' dans le terminal pour hot reload
```

---

## 📝 Notes importantes

### Config.set (Kivy)

En Kivy, on utilisait:
```python
Config.set('input', 'wm_touch', 'disable')
Config.set('input', 'wm_pen', 'disable')
```

C'est un contournement spécifique à Kivy sous Windows (problèmes de crash dans Spyder).

**Flutter n'a pas besoin de cela** car il gère nativement le multi-touch de manière robuste. Voir [main.dart ligne 32-38](lib/main.dart#L32-L38).

### Clock.schedule_interval (Kivy)

En Kivy:
```python
Clock.schedule_interval(update_telemetry, 0.5)
```

En Flutter/Dart:
```dart
_telemetryTimer = Timer.periodic(
  const Duration(milliseconds: 500),
  (_) { /* update */ }
);
```

Voir [main.dart ligne 87-105](lib/main.dart#L87-L105).

### Material 3 & Dark Theme

Le projet utilise Material 3 avec un thème sombre et couleur seed Teal. C'est configuré dans `DroneControlApp`:

```dart
colorScheme: ColorScheme.fromSeed(
  seedColor: Colors.teal,
  brightness: Brightness.dark,
),
```

---

## 🔄 Roadmap intégration

1. **Phase 1** (Actuellement): App Flutter compilable, layout complet, simulation
 Phase 2**: Intégration Bluetooth (flutter_blue)
3. **Phase 3**: Implémentation protocole UART/Serial
4. **Phase 4**: Calibrage joysticks et réglages PID
5. **Phase 5**: Tests avec drone réel

---

## 📚 Ressources

- [Flutter Documentation](https://flutter.dev/docs)
- [Dart API Reference](https://api.dart.dev/)
- [Material 3 Design](https://m3.material.io/)
- [GestureDetector API](https://api.flutter.dev/flutter/widgets/GestureDetector-class.html)
- [CustomPainter API](https://api.flutter.dev/flutter/rendering/CustomPainter-class.html)

---

## 👤 Auteur

Migré de Python/Kivy vers Flutter/Dart pour meilleure compatibilité mobile et performance.

**Date**: Février 2026
