import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'drone_link.dart';
import 'debug_terminal/terminal_page.dart';

// ============================================================================
// ÉQUIVALENCES PYTHON/KIVY → FLUTTER (Documentation)
// ============================================================================
//
// KIVY (Python 3 + Kivy 2.3.0 + KivyMD 1.2.0)          FLUTTER (Dart)
// ──────────────────────────────────────────────────────────────────────────
// Config.set('input','wm_touch','disable')      →   N/A (Flutter n'a pas besoin)
// Config.set('input','wm_pen','disable')        →   N/A (todo: spécifique Kivy/Windows)
// MDScreen                                       →   Scaffold
// MDBoxLayout(orientation='vertical')            →   Column
// MDRaisedButton                                 →   ElevatedButton
// MDIcon                                         →   Icon (Material Icons)
// Clock.schedule_interval(update_telemetry, 0.5) →  Timer.periodic(Duration(ms:500), ...)
// RelativeLayout + canvas drawing                →   Stack + CustomPainter
// Joystick(RelativeLayout) + clamp               →   Custom JoystickWidget
// ============================================================================

void main() {
  // TODO: Config.set from Kivy (Python)
  // En Kivy on faisait:
  //   Config.set('input', 'wm_touch', 'disable')
  //   Config.set('input', 'wm_pen', 'disable')
  // C'est un contournement spécifique à Kivy sous Windows (Spyder).
  // Flutter n'a pas d'équivalent car il gère nativement le multi-touch.

  runApp(const DroneControlApp());
}

class DroneControlApp extends StatelessWidget {
  const DroneControlApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Drone Control',
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.teal,
          brightness: Brightness.dark,
        ),
      ),
      home: const DroneControlScreen(),
    );
  }
}

class DroneControlScreen extends StatefulWidget {
  const DroneControlScreen({Key? key}) : super(key: key);

  @override
  State<DroneControlScreen> createState() => _DroneControlScreenState();
}

class _DroneControlScreenState extends State<DroneControlScreen> {
  // ========================================================================
  // ÉTAT GLOBAL (équivalent des variables d'instance Kivy)
  // ========================================================================

  // Moteurs
  bool moteursArmes = false; // Start disarmed by default

  // Télémétrie (lue depuis DroneLink)
  double roll = 0.0; // Roulis: -45..+45
  double pitch = 0.0; // Tangage: -45..+45
  double heading = 0.0; // Nord magnétique: 0..360
  double power = 0.0; // Puissance moteur: 0..100 %

  // Joysticks (valeurs normalisées -1..+1)
  double leftX = 0.0; // Gauche: Lacet (Yaw)
  double leftY = 0.0; // Gauche: Gaz (Throttle)
  double rightX = 0.0; // Droite: Roulis (Roll)
  double rightY = 0.0; // Droite: Tangage (Pitch)

  // ========================================================================
  // DroneLink Service (communication BT avec Arduino)
  // ========================================================================
  late DroneLink _droneLink;
  StreamSubscription<TelemetryData>? _telemetrySubscription;
  // Throttle command timer (rate-limiter)
  Timer? _throttleTimer;
  String? _throttlePendingCmd;

  @override
  void initState() {
    super.initState();

    // Initialiser DroneLink
    _droneLink = DroneLink();
    _droneLink.onConnectionChanged = _onDroneConnectionChanged;
    _droneLink.onArmChanged = _onDroneArmChanged;

    // S'abonner aux mises à jour de télémétrie
    _telemetrySubscription = _droneLink.onTelemetryUpdated.listen(
      _onTelemetryReceived,
    );

    // TODO: Connecter au drone Arduino via Bluetooth
    // Exemple:
    //   _droneLink.connect(deviceAddress: '00:1A:7D:DA:71:13')
    // Pour l'instant: simulation avec mock data

    // Dans le vrai déploiement, appeler:
    // _droneLink.connect(deviceAddress: 'XX:XX:XX:XX:XX:XX');

    debugPrint('[MAIN] DroneLink initialisé (mode simulation)');
  }

  @override
  void dispose() {
    _telemetrySubscription?.cancel();
    _throttleTimer?.cancel();
    _droneLink.dispose();
    super.dispose();
  }

  // --- Callbacks DroneLink ---

  void _onDroneConnectionChanged(bool connected) {
    debugPrint('[MAIN] Connexion drone: $connected');
    if (mounted) {
      setState(() {
        // Mise à jour UI si nécessaire
      });
    }
  }

  void _onDroneArmChanged(bool armed) {
    debugPrint('[MAIN] Drone armed: $armed');
    if (mounted) {
      setState(() {
        moteursArmes = armed;
      });
    }
  }

  /// Appelé quand une nouvelle télémétrie arrive du drone
  void _onTelemetryReceived(TelemetryData telem) {
    if (mounted) {
      setState(() {
        // Mapper les données Arduino vers l'affichage
        // If power looks like percent (0..100) use it directly, otherwise
        // assume PWM-like (0..255) and convert to percent.
        if (telem.power >= 0 && telem.power <= 100) {
          power = telem.power.toDouble();
        } else {
          power = (telem.power / 255.0) * 100.0;
        }

        // Arduino firmware sends pitch in the 'rotation' field of TelemetryData
        pitch = telem.rotation; // degrees
        heading = telem.heading;

        // Roll remains unavailable in this firmware (keep at 0)
        roll = 0.0;
      });
    }
  }

  void _handleArmDisarm() {
    setState(() {
      moteursArmes = !moteursArmes;
      // Si on désarme: reset joysticks au centre
      if (!moteursArmes) {
        leftX = 0.0;
        leftY = 0.0;
        rightX = 0.0;
        rightY = 0.0;
        // Send immediate safe STOP ('S') to comply with Arduino char protocol
        _sendS();
      } else {
        // Envoyer arm au drone
        _sendA_raw();
      }
    });
  }

  void _handleAutoLanding() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('🚁 Atterrissage automatique engagé'),
        duration: Duration(seconds: 2),
      ),
    );
    // Send 'A' as the firmware placeholder for auto-land
    _sendA_raw();
    debugPrint('[MAIN] Auto-landing triggered');
  }

  void _handleLeftJoystickChange(Offset offset) {
    setState(() {
      leftX = offset.dx;
      leftY = offset.dy;
    });
    // For this firmware we only control throttle with leftY
    if (!moteursArmes || !_droneLink.isConnected) return;

    // leftY: -1..+1 ; upward (negative) -> increase throttle (send 'U')
    const deadzone = 0.2;
    String? cmd;
    if (leftY < -deadzone) {
      cmd = 'U';
    } else if (leftY > deadzone) {
      cmd = 'D';
    } else {
      cmd = null;
    }

    // If there's a requested command, start/continue a rate-limited timer
    _throttlePendingCmd = cmd;
    if (cmd == null) {
      // stop timer
      _throttleTimer?.cancel();
      _throttleTimer = null;
    } else {
      // start timer if not already running (10Hz = 100ms)
      _throttleTimer ??= Timer.periodic(const Duration(milliseconds: 100), (_) {
        final c = _throttlePendingCmd;
        if (c == 'U') {
          _sendU();
        } else if (c == 'D') {
          _sendD();
        }
      });
    }
  }

  void _handleRightJoystickChange(Offset offset) {
    setState(() {
      rightX = offset.dx;
      rightY = offset.dy;
    });

    if (moteursArmes) {
      // Envoyer les commandes normalisées au drone
      final cmd = DroneCommand(
        throttle: 0.0, // Not controlled by right joystick
        yaw: 0.0, // Not controlled by right joystick
        pitch: rightY, // [-1, 1]
        roll: rightX, // [-1, 1]
      );
      _droneLink.sendCommand(cmd);
      debugPrint('[MAIN-JOY-R] $cmd');
    }
  }

  // ------------------------------------------------------------------
  // Firmware single-byte send helpers (Arduino HC-06 protocol)
  // ------------------------------------------------------------------
  void _sendU() {
    if (!_droneLink.isConnected) {
      debugPrint('[MAIN-TX] Not connected - _sendU aborted');
      return;
    }
    debugPrint('[MAIN-TX] -> U');
    _droneLink.sendRawByte('U');
  }

  void _sendD() {
    if (!_droneLink.isConnected) {
      debugPrint('[MAIN-TX] Not connected - _sendD aborted');
      return;
    }
    debugPrint('[MAIN-TX] -> D');
    _droneLink.sendRawByte('D');
  }

  void _sendS() {
    if (!_droneLink.isConnected) {
      debugPrint('[MAIN-TX] Not connected - _sendS aborted');
      return;
    }
    debugPrint('[MAIN-TX] -> S');
    _droneLink.sendRawByte('S');
  }

  void _sendA_raw() {
    if (!_droneLink.isConnected) {
      debugPrint('[MAIN-TX] Not connected - _sendA_raw aborted');
      return;
    }
    debugPrint('[MAIN-TX] -> A');
    _droneLink.sendRawByte('A');
  }

  // ------------------------------------------------------------------
  // Bluetooth device picker dialog
  // ------------------------------------------------------------------
  Future<void> _showBluetoothDevicesDialog() async {
    final devices = await _droneLink.getAvailableDevices();

    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Bluetooth - Appareils appairés'),
          content: SizedBox(
            width: double.maxFinite,
            child: devices.isEmpty
                ? const Text(
                    'Aucun appareil appairé trouvé. Assurez-vous d\'avoir appairé le HC-06 dans les paramètres Android.',
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: devices.length,
                    itemBuilder: (context, index) {
                      final d = devices[index];
                      return ListTile(
                        title: Text(d.name),
                        subtitle: Text(d.address),
                        trailing: _droneLink.isConnected
                            ? TextButton(
                                child: const Text('Déconnecter'),
                                onPressed: () async {
                                  await _droneLink.disconnect();
                                  Navigator.of(context).pop();
                                },
                              )
                            : TextButton(
                                child: const Text('Connecter'),
                                onPressed: () async {
                                  Navigator.of(context).pop();
                                  final ok = await _droneLink.connect(
                                    deviceAddress: d.address,
                                  );
                                  if (!ok && mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Connexion échouée'),
                                      ),
                                    );
                                  }
                                },
                              ),
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Fermer'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '🚁 Drone Control',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            tooltip: 'Bluetooth',
            icon: Icon(
              _droneLink.isConnected
                  ? Icons.bluetooth_connected
                  : Icons.bluetooth,
              color: _droneLink.isConnected ? Colors.tealAccent : Colors.white,
            ),
            onPressed: _showBluetoothDevicesDialog,
          ),
          IconButton(
            tooltip: 'Terminal Debug',
            icon: const Icon(Icons.code),
            onPressed: () {
              Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const TerminalPage()));
            },
          ),
        ],
        centerTitle: true,
        elevation: 0,
      ),
      body: Column(
        children: [
          // ====================================================================
          // 1) SECTION TÉLÉMÉTRIE (Haut)
          // ====================================================================
          Expanded(
            flex: 1,
            child: Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Theme.of(context).colorScheme.outline,
                  width: 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'TÉLÉMÉTRIE',
                    style: Theme.of(
                      context,
                    ).textTheme.labelLarge?.copyWith(color: Colors.teal),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        TelemetryItem(
                          icon: Icons.redo,
                          label: 'Roll',
                          value: '${roll.toStringAsFixed(1)}°',
                          color: Colors.cyan,
                        ),
                        TelemetryItem(
                          icon: Icons.undo,
                          label: 'Pitch',
                          value: '${pitch.toStringAsFixed(1)}°',
                          color: Colors.cyan,
                        ),
                        TelemetryItem(
                          icon: Icons.bolt,
                          label: 'Power',
                          value: '${power.toStringAsFixed(0)}%',
                          color: Colors.amber,
                        ),
                        TelemetryItem(
                          icon: Icons.explore,
                          label: 'Heading',
                          value: '${heading.toStringAsFixed(0)}°',
                          color: Colors.lightBlue,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ====================================================================
          // 2) SECTION COMMANDES (Milieu)
          // ====================================================================
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                // Bouton ARM / EMERGENCY
                Expanded(
                  child: ElevatedButton(
                    onPressed: _handleArmDisarm,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      backgroundColor: moteursArmes ? Colors.red : Colors.green,
                      foregroundColor: Colors.white,
                    ),
                    child: Text(
                      moteursArmes
                          ? '🔴 COUPURE D\'URGENCE'
                          : '🟢 ARMER LES MOTEURS',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // Bouton ATTERRISSAGE AUTOMATIQUE
                Expanded(
                  child: ElevatedButton(
                    onPressed: moteursArmes ? _handleAutoLanding : null,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: Colors.grey[700],
                    ),
                    child: const Text(
                      '⬇ ATTERRISSAGE AUTO',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // ====================================================================
          // 3) SECTION JOYSTICKS (Bas)
          // ====================================================================
          Expanded(
            flex: 2,
            child: Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Theme.of(context).colorScheme.outline,
                  width: 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'JOYSTICKS',
                    style: Theme.of(
                      context,
                    ).textTheme.labelLarge?.copyWith(color: Colors.teal),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: Row(
                      children: [
                        // Joystick Gauche (Gaz + Lacet)
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Expanded(
                                child: JoystickWidget(
                                  label: 'GAUCHE\n(Gaz/Lacet)',
                                  enabled: moteursArmes,
                                  onChanged: _handleLeftJoystickChange,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'x:${leftX.toStringAsFixed(2)} y:${leftY.toStringAsFixed(2)}',
                                style: Theme.of(context).textTheme.labelSmall,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        // Joystick Droite (Tangage + Roulis)
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Expanded(
                                child: JoystickWidget(
                                  label: 'DROITE\n(Tangage/Roulis)',
                                  enabled: moteursArmes,
                                  onChanged: _handleRightJoystickChange,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'x:${rightX.toStringAsFixed(2)} y:${rightY.toStringAsFixed(2)}',
                                style: Theme.of(context).textTheme.labelSmall,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// WIDGET: TelemetryItem
// Affiche un item télémétrie (icône + valeur + libellé)
// ============================================================================
class TelemetryItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const TelemetryItem({
    Key? key,
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 32),
          const SizedBox(height: 8),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: Colors.grey[400]),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// WIDGET: JoystickWidget (Custom)
// Équivalent de Joystick(RelativeLayout) en Kivy
//
// Comportement:
// - Cercle de fond, petit cercle (knob) qui suit le doigt
// - Knob confiné dans le cercle (mathématique clamp)
// - Callback onChanged avec Offset normalisé (-1..+1)
// - Retour au centre (0,0) au relâchement
// - disabled: grisé + pas de touch
// ============================================================================
class JoystickWidget extends StatefulWidget {
  final String label;
  final bool enabled;
  final Function(Offset) onChanged;

  const JoystickWidget({
    Key? key,
    required this.label,
    required this.enabled,
    required this.onChanged,
  }) : super(key: key);

  @override
  State<JoystickWidget> createState() => _JoystickWidgetState();
}

class _JoystickWidgetState extends State<JoystickWidget> {
  Offset _knobOffset = Offset.zero;
  bool _isDragging = false;

  // Calcul de l'Offset normalisé (-1..+1) depuis la position du knob
  Offset _getNormalizedOffset(Offset position, Size containerSize) {
    final double radius = min(containerSize.width, containerSize.height) / 2;
    final Offset center = Offset(
      containerSize.width / 2,
      containerSize.height / 2,
    );

    // Vecteur du centre vers la position du doigt
    final Offset relative = position - center;

    // Distance du centre
    final double distance = relative.distance;

    // Si le doigt dépasse le cercle, on le projette sur le périmètre (clamp)
    Offset clamped;
    if (distance > radius) {
      final double ratio = radius / distance;
      clamped = relative * ratio;
    } else {
      clamped = relative;
    }

    // Normaliser entre -1 et +1
    return Offset(clamped.dx / radius, clamped.dy / radius);
  }

  void _onPanStart(DragStartDetails details) {
    if (!widget.enabled) return;
    setState(() {
      _isDragging = true;
    });
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (!widget.enabled) return;

    final RenderBox renderBox = context.findRenderObject() as RenderBox;
    final Size containerSize = renderBox.size;
    final Offset localPosition = details.localPosition;

    final Offset normalized = _getNormalizedOffset(
      localPosition,
      containerSize,
    );

    setState(() {
      _knobOffset = normalized;
    });

    widget.onChanged(normalized);
  }

  void _onPanEnd(DragEndDetails details) {
    if (!widget.enabled) return;

    // Retour EXACT au centre (0,0)
    setState(() {
      _isDragging = false;
      _knobOffset = Offset.zero;
    });

    widget.onChanged(Offset.zero);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onPanStart: _onPanStart,
      onPanUpdate: _onPanUpdate,
      onPanEnd: _onPanEnd,
      child: Container(
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(12)),
        child: Opacity(
          opacity: widget.enabled ? 1.0 : 0.4,
          child: Stack(
            children: [
              // CustomPainter pour le joystick
              CustomPaint(
                painter: JoystickPainter(
                  knobOffset: _knobOffset,
                  isDragging: _isDragging,
                  enabled: widget.enabled,
                ),
                size: Size.infinite,
              ),
              // Label au centre/haut
              Center(
                child: Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    widget.label,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Colors.teal,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// CUSTOM PAINTER: JoystickPainter
// Dessine le joystick (cercle background + knob)
// ============================================================================
class JoystickPainter extends CustomPainter {
  final Offset knobOffset;
  final bool isDragging;
  final bool enabled;

  JoystickPainter({
    required this.knobOffset,
    required this.isDragging,
    required this.enabled,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final double radius = min(size.width, size.height) / 2;
    final Offset center = Offset(size.width / 2, size.height / 2);

    // Cercle de fond (background)
    final Paint bgPaint = Paint()
      ..color = Colors.teal.withValues(alpha: enabled ? 0.2 : 0.1)
      ..style = PaintingStyle.fill;

    canvas.drawCircle(center, radius, bgPaint);

    // Bordure du cercle
    final Paint borderPaint = Paint()
      ..color = Colors.teal.withValues(alpha: enabled ? 0.5 : 0.2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    canvas.drawCircle(center, radius, borderPaint);

    // Petit cercle (knob) qui suit le doigt
    final Offset knobPosition = center + (knobOffset * (radius * 0.7));

    final Paint knobPaint = Paint()
      ..color = isDragging ? Colors.teal : Colors.teal.withValues(alpha: 0.7)
      ..style = PaintingStyle.fill;

    canvas.drawCircle(knobPosition, radius * 0.25, knobPaint);

    // Bordure du knob
    final Paint knobBorderPaint = Paint()
      ..color = Colors.teal
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    canvas.drawCircle(knobPosition, radius * 0.25, knobBorderPaint);

    // Ligne du centre au knob (au moment d'un drag)
    if (isDragging) {
      final Paint linePaint = Paint()
        ..color = Colors.teal.withValues(alpha: 0.4)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;

      canvas.drawLine(center, knobPosition, linePaint);
    }
  }

  @override
  bool shouldRepaint(JoystickPainter oldDelegate) {
    return knobOffset != oldDelegate.knobOffset ||
        isDragging != oldDelegate.isDragging ||
        enabled != oldDelegate.enabled;
  }
}
