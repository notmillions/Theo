# 📌 CHECKLIST MIGRATION KIVY → FLUTTER

## ✅ Livrables complétés

- [x] **lib/main.dart** - Code complet compilable du projet Flutter
- [x] **Pas de dépendances externes** - Utilise uniquement Material 3
- [x] **Configuration Dark Theme + Teal** - Material 3 avec seedColor Teal
- [x] **AppBar** - Titre "🚁 Drone Control"

### Section Télémétrie
- [x] Row de 4 items (Roll, Pitch, Power, Heading)
- [x] Mise à jour automatique toutes les 500ms (équivalent Clock.schedule_interval)
- [x] Affichage avec icônes et couleurs
- [x] Simulation valeurs aléatoires

### Section Commandes  
- [x] Bouton ARM (vert) → change à EMERGENCY (rouge)
- [x] Bouton ATTERRISSAGE AUTO (bleu, disabled si désarmé)
- [x] Reset joysticks au centre lors du désarmement
- [x] SnackBar sur action AutoLanding

### Section Joysticks
- [x] 2 joysticks côte à côte (Gauche + Droite)
- [x] CustomPainter pour joystick (cercle + knob teal)
- [x] GestureDetector pour drag (onPanStart, onPanUpdate, onPanEnd)
- [x] Clamp mathématique (distance > rayon → projette sur périmètre)
- [x] Normalisation Offset -1..+1
- [x] Retour exact au centre (0.0, 0.0) au relâchement
- [x] Joysticks grisés (opacity 0.4) si moteurs désarmés
- [x] Affichage debug: x:0.00 y:0.00 (2 décimales)
- [x] Callbacks onChanged

## 📌 Équivalences documentées dans le code

### 1. Config.set (Kivy)
**Fichier**: [lib/main.dart, lignes 32-38](lib/main.dart#L32-L38)

```dart
// TODO: Config.set from Kivy (Python)
// En Kivy on faisait:
//   Config.set('input', 'wm_touch', 'disable')
//   Config.set('input', 'wm_pen', 'disable')
// C'est un contournement spécifique à Kivy sous Windows (Spyder).
// Flutter n'a pas d'équivalent car il gère nativement le multi-touch.
```

**Conclusion**: aucun équivalent Flutter nécessaire ✓

### 2. Clock.schedule_interval (Kivy)
**Fichier**: [lib/main.dart, lignes 87-105](lib/main.dart#L87-L105)

**Kivy**:
```python
Clock.schedule_interval(update_telemetry, 0.5)
```

**Flutter/Dart**:
```dart
_telemetryTimer = Timer.periodic(
  const Duration(milliseconds: 500),
  (_) {
    setState(() { /* update */ });
  }
);
```

### 3. Widgets KivyMD → Flutter Material 3

| **KivyMD** | **Flutter** |
|---|---|
| MDScreen | Scaffold |
| MDBoxLayout | Column |
| MDRaisedButton | ElevatedButton |
| MDIcon | Icon |
| RelativeLayout | Stack + CustomPainter |
| Joystick(RelativeLayout) | JoystickWidget (custom) |

**Commentaire**: [lib/main.dart, lignes 6-18](lib/main.dart#L6-L18)

## 🔧 Points d'intégration pour capteurs/commandes réels

### Point 1: Capteurs (Télémétrie)
**Fichier**: [lib/main.dart, ligne 97-104](lib/main.dart#L97-L104)

```dart
// TODO: Connecter les vrais capteurs ici (Bluetooth/Arduino/UART)
// Actuellement: valeurs aléatoires pour simulation
```

À remplacer par:
```dart
final data = await bluetoothService.readTelemetry();
roll = data.roll;
pitch = data.pitch;
heading = data.heading;
power = data.power;
```

### Point 2: Commandes Joystick (vers drone)
**Fichier**: [lib/main.dart, lignes 125-140](lib/main.dart#L125-L140)

```dart
// TODO: Envoyer les commandes joystick au drone ici (Bluetooth/Arduino/UART)
```

À remplacer par:
```dart
bluetoothService.sendCommand({
  'throttle': leftY,
  'yaw': leftX,
  'pitch': rightY,
  'roll': rightX,
});
```

## 📊 État global (State)

```dart
// Moteurs
bool moteursArmes = false;

// Télémétrie (simulée actuellement)
double roll = 0.0;      // -45..+45
double pitch = 0.0;     // -45..+45
double heading = 0.0;   // 0..360
double power = 0.0;     // 0..100 %

// Joysticks (normalisés)
double leftX = 0.0;     // Gauche X (Lacet/Yaw)
double leftY = 0.0;     // Gauche Y (Gaz/Throttle)
double rightX = 0.0;    // Droite X (Roulis/Roll)
double rightY = 0.0;    // Droite Y (Tangage/Pitch)

// Timer pour update télémétrie
late Timer _telemetryTimer;
```

## 🎯 Architecture du Joystick

### JoystickWidget
- **StatefulWidget** custom
- Props: `label`, `enabled`, `onChanged` callback
- State contient: `_knobOffset`, `_isDragging`

### Logique du clamp (normalement compliqué en Kivy, simple ici)
```dart
Offset _getNormalizedOffset(Offset position, Size containerSize) {
  final radius = min(width, height) / 2;
  final center = Offset(width/2, height/2);
  final relative = position - center;
  final distance = relative.distance;
  
  // CLAMP: si distance > radius, projette sur le périmètre
  Offset clamped = (distance > radius)
    ? relative * (radius / distance)
    : relative;
  
  // Normaliser -1..+1
  return Offset(clamped.dx / radius, clamped.dy / radius);
}
```

### JoystickPainter (CustomPainter)
- Dessine cercle background (teal 0.2 opacity)
- Dessine knob (petit cercle) à la position clamped
- Dessine ligne du centre au knob pendant drag
- Supporte `enabled` (opacity réduite si désactivé)

## 🚀 Comment compiler et lancer

### Compilation
```bash
cd C:\Users\isaac\Theo\drone_app
flutter pub get
flutter analyze  # Vérifier (warnings ok)
```

### Lancer
```bash
flutter run
```

### Tests
```bash
flutter test
```

## ⚠️ Points importants

1. **Pas de dépendances externes** - Code 100% Flutter standard ✓
2. **Compilable immédiatement** - Aucun import missing ✓
3. **Code complet** - Pas de pseudo-code ✓
4. **Commentaires TODO** - Bien marqués pour intégration future ✓
5. **Équivalences documentées** - Python/Kivy mapées en commentaires ✓

## 📝 Fichiers modifiés

- ✅ `lib/main.dart` - Implémentation complète (880 lignes)
- ✅ `test/widget_test.dart` - Tests actualisés
- ✅ `README_DRONE.md` - Documentation complète (ce fichier)

## 🎓 Apprentissages clés

### Kivy → Flutter
- **Config.set** n'existe pas en Flutter (gère multi-touch nativement)
- **Clock.schedule_interval** → **Timer.periodic**
- **RelativeLayout** → **Stack + CustomPainter**
- **Joystick(RelativeLayout)** → **Custom JoystickWidget**
- **KivyMD styling** → **Material 3 ThemeData**

### CustomPainter vs KivyMD Canvas
- Plus simple et performant en Flutter
- Support natif du redraw automatique via `shouldRepaint`
- Clamp math identique (distance/radius)

### GestureDetector vs KivyMD Touch
- Plus simple en Flutter
- `onPanStart`, `onPanUpdate`, `onPanEnd` clairement définis
- Support natif du multi-touch

---

**Status**: ✅ Projet complet et prêt à être testé/compilé.
