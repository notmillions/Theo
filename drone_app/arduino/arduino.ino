#include <Wire.h>
#include <Servo.h>
#include <SoftwareSerial.h>
#include <Adafruit_MPU6050.h>
#include <TinyGPS++.h>
#include <DFRobot_BMM150.h>

// --- CONFIGURATION ---
// Bluetooth: D2 (RX Arduino) <-> TX Module | D5 (TX Arduino) <-> RX Module
SoftwareSerial btSerial(2, 5);

// GPS
SoftwareSerial gpsSerial(4, 3);
TinyGPSPlus gps;

// MOTEURS
Servo motor1; // D6
Servo motor2; // D9
Servo motor3; // D10 (VOTRE MOTEUR TEST)
Servo motor4; // D11

// Capteurs
Adafruit_MPU6050 mpu;
// DFRobot_BMM150_I2C bmm(&Wire, 0x13); // Désactivé pour alléger

// Variables Vol
float gyro_roll_input = 0, gyro_pitch_input = 0, gyro_yaw_input = 0;
float gyro_roll, gyro_pitch, gyro_yaw;
float gyro_roll_cal, gyro_pitch_cal, gyro_yaw_cal;
float altitudeRel = 0;

// PID (Gains standards)
float pid_p_gain_roll=1.3, pid_i_gain_roll=0.04, pid_d_gain_roll=18.0;
float pid_p_gain_pitch=1.3, pid_i_gain_pitch=0.04, pid_d_gain_pitch=18.0;
float pid_p_gain_yaw=4.0,  pid_i_gain_yaw=0.02,  pid_d_gain_yaw=0.0;

// PID Memoire
float pid_i_mem_roll, pid_last_roll_d_error, pid_output_roll;
float pid_i_mem_pitch, pid_last_pitch_d_error, pid_output_pitch;
float pid_i_mem_yaw, pid_last_yaw_d_error, pid_output_yaw;

// GAZ
int input_THROTTLE = 1000;
int esc_1, esc_2, esc_3, esc_4;
unsigned long loop_timer;
unsigned long telemetry_timer = 0;
bool mpu_ok = false;
bool armed = false;
// Debug moteur: active des impressions lorsque writeMotors est appelé
const bool MOTOR_DEBUG = true;

// Multiplexeur
void tcaselect(uint8_t i) {
  if (i > 7) return;
  Wire.beginTransmission(0x70);
  Wire.write(1 << i);
  Wire.endTransmission();
}

// --- PROTOTYPES (Pour aider le compilateur) ---
void calculate_pid();
void reset_pid();
void read_mpu_raw();
void writeMotors(int m1, int m2, int m3, int m4);

void setup() {
  Serial.begin(9600);
  btSerial.begin(9600);
  gpsSerial.begin(9600);
  Wire.begin();

  // 1. MOTEURS
  motor1.attach(6);  motor2.attach(9);
  motor3.attach(10); motor4.attach(11); // Moteur Test sur D10
 
  // 2. INITIALISATION AM32 (Signal 1000)
  Serial.println(F("--- INIT MOTEUR (STOP) ---"));
  writeMotors(1000, 1000, 1000, 1000);

  // 3. COMPTE A REBOURS 15s (Armement)
  Serial.println(F("ATTENTE 15s (Armement)..."));
  for(int i=0; i<15; i++) {
    delay(1000);
    btSerial.print(".");
    Serial.print(".");
  }
  Serial.println(F("\nPRET ! DEMARRAGE RALENTI."));
 
  // 4. DEMARRAGE AUTOMATIQUE (Idle)
  input_THROTTLE = 1150;
  armed = true;

  // 5. CAPTEURS
  tcaselect(0);
  if (!mpu.begin()) {
    Serial.println(F("! MPU MANQUANT ! Mode Simulation"));
    mpu_ok = false;
  } else {
    Serial.println(F("MPU OK. Calibration..."));
    mpu_ok = true;
    for (int i = 0; i < 2000 ; i++){
      read_mpu_raw();
      gyro_roll_cal += gyro_roll;
      gyro_pitch_cal += gyro_pitch;
      gyro_yaw_cal += gyro_yaw;
      delay(3);
    }
    gyro_roll_cal /= 2000; gyro_pitch_cal /= 2000; gyro_yaw_cal /= 2000;
  }
 
  loop_timer = micros();
}

void loop() {
  // --- 1. BLUETOOTH (GAZ PUISSANTS) ---
  btSerial.listen();
  while (btSerial.available() > 0) {
    char ch = (char)btSerial.read();

    // Debug trace
    Serial.print("BT ch: "); Serial.println(ch);

    if (!btReceiving) {
      // Début de trame ou commande simple
      if (ch == '<') {
        btReceiving = true;
        btFramePos = 0;
        btFrameBuf[btFramePos++] = ch;
      } else if (ch == 'U') {
        input_THROTTLE += 50;
        if (input_THROTTLE > 1800) input_THROTTLE = 1800;
      } else if (ch == 'D') {
        input_THROTTLE -= 50;
        if (input_THROTTLE < 1100 && armed) input_THROTTLE = 1100;
      } else if (ch == 'S') {
        input_THROTTLE = 1000;
        armed = false;
        reset_pid();
      } else if (ch == 'T') {
        // Test moteur via Bluetooth - retirer les hélices avant d'exécuter
        Serial.println("BT: motor test requested (T)");
        // Lance une séquence de test courte
        bool prevArmed = armed;
        armed = true;
        for (int p = 1100; p <= 1400; p += 100) {
          writeMotors(p, p, p, p);
          delay(400);
        }
        writeMotors(1000, 1000, 1000, 1000);
        armed = prevArmed;
      } else if (ch == 'A') {
        input_THROTTLE = 1150;
        armed = true;
      } else {
        // ignore other single bytes (newline, carriage return, etc.)
      }
    } else {
      // En cours de réception d'une trame
      if (ch == '>') {
        if (btFramePos < sizeof(btFrameBuf) - 1) btFrameBuf[btFramePos++] = ch;
        btFrameBuf[btFramePos] = '\0';
        processBtFrame(btFrameBuf);
        btReceiving = false;
        btFramePos = 0;
      } else {
        if (btFramePos < sizeof(btFrameBuf) - 1) {
          btFrameBuf[btFramePos++] = ch;
        } else {
          // overflow: abandonner cette trame
          btReceiving = false;
          btFramePos = 0;
          Serial.println("BT frame overflow - discarded");
        }
      }
    }
  }

  // --- 2. LECTURE MPU ---
  if(mpu_ok) {
    tcaselect(0);
    read_mpu_raw();
    gyro_roll -= gyro_roll_cal;
    gyro_pitch -= gyro_pitch_cal;
    gyro_yaw -= gyro_yaw_cal;
   
    // Filtre
    gyro_roll_input = (gyro_roll_input * 0.7) + ((gyro_roll / 65.5) * 0.3);
    gyro_pitch_input = (gyro_pitch_input * 0.7) + ((gyro_pitch / 65.5) * 0.3);
    gyro_yaw_input = (gyro_yaw_input * 0.7) + ((gyro_yaw / 65.5) * 0.3);
  } else {
    gyro_pitch_input = 10.0; // Simulation
  }

  // GPS
  gpsSerial.listen();
  while (gpsSerial.available() > 0) gps.encode(gpsSerial.read());
  if (gps.altitude.isValid()) altitudeRel = gps.altitude.meters();

  // --- 3. PID ---
  calculate_pid();

  // --- 4. MIXAGE ---
  int throttle = input_THROTTLE;

  if (throttle < 1050) {
    esc_1=1000; esc_2=1000; esc_3=1000; esc_4=1000;
    reset_pid(); // Et ici aussi !
  } else {
    // Quad X
    esc_3 = throttle - pid_output_roll + pid_output_pitch - pid_output_yaw; // D10
   
    esc_1 = throttle + pid_output_roll - pid_output_pitch - pid_output_yaw;
    esc_2 = throttle - pid_output_roll - pid_output_pitch + pid_output_yaw;
    esc_4 = throttle + pid_output_roll + pid_output_pitch + pid_output_yaw;

    esc_1 = constrain(esc_1, 1000, 2000);
    esc_2 = constrain(esc_2, 1000, 2000);
    esc_3 = constrain(esc_3, 1000, 2000);
    esc_4 = constrain(esc_4, 1000, 2000);
  }

  writeMotors(esc_1, esc_2, esc_3, esc_4);

  // --- 5. TELEMETRIE ---
  if (millis() - telemetry_timer > 200) {
    telemetry_timer = millis();
   
    int p = map(throttle, 1000, 2000, 0, 100);
    int r = (int)gyro_roll_input;
    int a = (int)gyro_pitch_input;
    int c = (int)gyro_yaw_input;
   
    btSerial.print("P:"); btSerial.print(p);
    btSerial.print("|R:"); btSerial.print(r);
    btSerial.print("|A:"); btSerial.print(a);
    btSerial.print("|C:"); btSerial.print(c);
    btSerial.print("|H:"); btSerial.println(altitudeRel, 1);
  }

  while(micros() - loop_timer < 4000);
  loop_timer = micros();
}

// --- OUTILS ---
// C'est cette fonction qui manquait !
void reset_pid() {
  pid_i_mem_roll = 0;
  pid_i_mem_pitch = 0;
  pid_i_mem_yaw = 0;
  pid_last_roll_d_error = 0;
  pid_last_pitch_d_error = 0;
  pid_last_yaw_d_error = 0;
  pid_output_roll = 0;
  pid_output_pitch = 0;
  pid_output_yaw = 0;
}

// --- Parser Bluetooth: support des trames <th,pit,rol,yaw> et des commandes simples A/D/S/U
char btFrameBuf[128];
size_t btFramePos = 0;
bool btReceiving = false;

void processBtFrame(const char* frame) {
  // frame attendu: <1000,1513,1410,1500>
  int v1, v2, v3, v4;
  int matched = sscanf(frame, "<%d,%d,%d,%d>", &v1, &v2, &v3, &v4);
  if (matched == 4) {
    // Si armé, appliquer directement les commandes (mode direct)
    if (armed) {
      // Sécurité: clamp
      v1 = constrain(v1, 1000, 2000);
      v2 = constrain(v2, 1000, 2000);
      v3 = constrain(v3, 1000, 2000);
      v4 = constrain(v4, 1000, 2000);
      // Appliquer
      writeMotors(v1, v2, v3, v4);
      Serial.print("OK: "); Serial.println(frame);
      btSerial.print("OK:"); btSerial.println(frame);
    } else {
      Serial.print("IGNORED (disarmed): "); Serial.println(frame);
      btSerial.print("BAD:DISARMED"); btSerial.println(frame);
    }
  } else {
    Serial.print("BAD: "); Serial.println(frame);
    btSerial.print("BAD:"); btSerial.println(frame);
  }
}

void calculate_pid(){
  // PITCH
  float error = gyro_pitch_input - 0;
  pid_i_mem_pitch += pid_i_gain_pitch * error;
  pid_i_mem_pitch = constrain(pid_i_mem_pitch, -400, 400);
  pid_output_pitch = pid_p_gain_pitch * error + pid_i_mem_pitch + pid_d_gain_pitch * (error - pid_last_pitch_d_error);
  pid_output_pitch = constrain(pid_output_pitch, -400, 400);
  pid_last_pitch_d_error = error;
 
  // ROLL
  error = gyro_roll_input - 0;
  pid_i_mem_roll += pid_i_gain_roll * error;
  pid_i_mem_roll = constrain(pid_i_mem_roll, -400, 400);
  pid_output_roll = pid_p_gain_roll * error + pid_i_mem_roll + pid_d_gain_roll * (error - pid_last_roll_d_error);
  pid_output_roll = constrain(pid_output_roll, -400, 400);
  pid_last_roll_d_error = error;

  // YAW
  error = gyro_yaw_input - 0;
  pid_i_mem_yaw += pid_i_gain_yaw * error;
  pid_i_mem_yaw = constrain(pid_i_mem_yaw, -400, 400);
  pid_output_yaw = pid_p_gain_yaw * error + pid_i_mem_yaw + pid_d_gain_yaw * (error - pid_last_yaw_d_error);
  pid_output_yaw = constrain(pid_output_yaw, -400, 400);
  pid_last_yaw_d_error = error;
}

void read_mpu_raw(){
  Wire.beginTransmission(0x68); Wire.write(0x43); Wire.endTransmission();
  Wire.requestFrom(0x68,6);
  while(Wire.available() < 6);
  gyro_roll = Wire.read()<<8|Wire.read();
  gyro_pitch = Wire.read()<<8|Wire.read();
  gyro_yaw = Wire.read()<<8|Wire.read();
  gyro_pitch *= -1; gyro_roll *= -1;
}

void writeMotors(int m1, int m2, int m3, int m4){
   motor1.writeMicroseconds(m1); motor2.writeMicroseconds(m2);
   motor3.writeMicroseconds(m3); motor4.writeMicroseconds(m4);
  if (MOTOR_DEBUG) {
    Serial.print("MOTOR DEBUG -> ");
    Serial.print(m1); Serial.print(',');
    Serial.print(m2); Serial.print(',');
    Serial.print(m3); Serial.print(',');
    Serial.println(m4);
  }
}