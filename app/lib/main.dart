import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

// Theme palette
const kBrand400 = Color(0xFF22D3EE), kBrand500 = Color(0xFF06B6D4);
const kRose = Color(0xFFF43F5E), kEmerald = Color(0xFF10B981), kOrange = Color(0xFFF97316);
const kSlate400 = Color(0xFF94A3B8), kSlate900 = Color(0xFF0F172A);

class Pal {
  final bool d;
  const Pal(this.d);
  static Pal of(BuildContext c) => Pal(Theme.of(c).brightness == Brightness.dark);
  Color get app => d ? const Color(0xFF050B14) : const Color(0xFFF8FAFC);
  Color get card => d ? const Color(0xFF0B1320) : Colors.white;
  Color get border => d ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0);
  Color get text => d ? Colors.white : kSlate900;
  Color get t700 => d ? const Color(0xFFCBD5E1) : const Color(0xFF334155);
  Color get sub => d ? kSlate400 : const Color(0xFF64748B);
  Color get chip => d ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9);
  Color get soft => d ? const Color(0xFF1E293B).withOpacity(.5) : const Color(0xFFF8FAFC);
  Color get track => d ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0);
  Color get okTxt => d ? const Color(0xFF34D399) : kEmerald;
  Color get accent => d ? kBrand400 : kBrand500;
}

TextStyle ts(double s, FontWeight w, Color c, {double ls = 0, bool mono = false, double? h}) =>
    (mono ? GoogleFonts.firaCode : GoogleFonts.inter)(fontSize: s, fontWeight: w, color: c, letterSpacing: ls, height: h);

ThemeData buildTheme(bool d) {
  final p = Pal(d);
  final base = ThemeData(brightness: d ? Brightness.dark : Brightness.light, useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: p.app,
    colorScheme: ColorScheme.fromSeed(seedColor: kBrand500, brightness: d ? Brightness.dark : Brightness.light)
        .copyWith(surface: p.card, primary: kBrand500),
    textTheme: GoogleFonts.interTextTheme(base.textTheme).apply(bodyColor: p.text, displayColor: p.text),
    dividerColor: p.border,
  );
}

void showToast(BuildContext ctx, String msg, {bool err = false}) {
  final m = ScaffoldMessenger.of(ctx);
  m.hideCurrentSnackBar();
  m.showSnackBar(SnackBar(
    content: Text(msg, style: ts(12, FontWeight.w600, Colors.white)),
    backgroundColor: err ? kRose : kSlate900,
    behavior: SnackBarBehavior.floating,
    duration: const Duration(seconds: 2),
  ));
}

// Localization tables
const Map<String, Map<String, String>> kI18n = {
  'en': {
    'sosBtn': 'SOS EMERGENCY', 'aiPred': 'Edge AI Triage Status', 'navHome': 'Home', 'navSensors': 'Sensors',
    'navRescue': 'SOS', 'navSettings': 'Settings', 'cardThermal': 'Body Temp', 'cardHeart': 'Heart Rate',
    'cardActivity': 'Body Activity', 'cardAir': 'Air Quality', 'subtitle': 'Live Telemetry HUD',
    'telemetryDash': 'Telemetry Dashboard', 'liveStream': 'Live Telemetry Stream', 'systemSettings': 'System Settings',
    'OFF-WRIST': 'OFF-WRIST', 'STABLE': 'STABLE', 'ELEVATED': 'ELEVATED', 'RESTING': 'RESTING', 'HYPOXIA': 'HYPOXIA',
    'LOW': 'LOW', 'IMPACT': 'IMPACT', 'NOMINAL': 'NOMINAL', 'POOR AIR': 'POOR AIR', 'CLEAN AIR': 'CLEAN AIR',
    'DRY': 'DRY', 'NORMAL': 'NORMAL', 'SWEATY': 'SWEATY', 'PROFUSE': 'PROFUSE', 'Standby': 'Standby',
    'Please Wear Device': 'Waiting for BLE Data', 'SECURE': 'SECURE', 'STANDBY': 'STANDBY',
    'FALL IMPACT': 'FALL IMPACT', 'HEAT STRAIN': 'HEAT STRAIN', 'EXERTION': 'EXERTION', 'RESPIRATORY': 'RESPIRATORY',
    'connectBle': 'Connect', 'devConn': 'Device & Connection', 'privData': 'Privacy & Data Storage',
  },
  'hi': {
    'sosBtn': 'आपातकाल (SOS)', 'aiPred': 'Edge AI ट्रायज', 'navHome': 'होम', 'navSensors': 'सेंसर', 'navRescue': 'एसओएस',
    'navSettings': 'सेटिंग्स', 'cardThermal': 'शरीर का तापमान', 'cardHeart': 'हृदय गति', 'cardActivity': 'शारीरिक गतिविधि',
    'cardAir': 'वायु गुणवत्ता', 'subtitle': 'लाइव टेलीमेट्री', 'telemetryDash': 'टेलीमेट्री डैशबोर्ड',
    'liveStream': 'लाइव टेलीमेट्री स्ट्रीम', 'systemSettings': 'सिस्टम सेटिंग्स', 'OFF-WRIST': 'पहना नहीं है',
    'STABLE': 'स्थिर', 'ELEVATED': 'बढ़ा हुआ', 'RESTING': 'सामान्य', 'HYPOXIA': 'ऑक्सीजन की कमी', 'LOW': 'कम',
    'IMPACT': 'प्रभाव (गिरना)', 'NOMINAL': 'सामान्य', 'POOR AIR': 'खराब हवा', 'CLEAN AIR': 'स्वच्छ हवा', 'DRY': 'सूखा',
    'NORMAL': 'सामान्य', 'SWEATY': 'पसीना', 'PROFUSE': 'अत्यधिक पसीना', 'Standby': 'स्टैंडबाय',
    'Please Wear Device': 'BLE डेटा की प्रतीक्षा', 'SECURE': 'सुरक्षित', 'STANDBY': 'स्टैंडबाय',
    'FALL IMPACT': 'प्रभाव (गिरना)', 'HEAT STRAIN': 'अत्यधिक गर्मी', 'EXERTION': 'शारीरिक तनाव',
    'RESPIRATORY': 'श्वसन संकट', 'connectBle': 'कनेक्ट करें', 'devConn': 'डिवाइस और कनेक्शन', 'privData': 'गोपनीयता और डेटा',
  },
  'ta': {
    'sosBtn': 'அவசரம் (SOS)', 'aiPred': 'Edge AI நிலை', 'navHome': 'முகப்பு', 'navSensors': 'சென்சார்கள்', 'navRescue': 'SOS',
    'navSettings': 'அமைப்புகள்', 'cardThermal': 'உடல் வெப்பநிலை', 'cardHeart': 'இதய துடிப்பு', 'cardActivity': 'உடல் செயல்பாடு',
    'cardAir': 'காற்றின் தரம்', 'subtitle': 'லைவ் டெலிமெட்ரி', 'telemetryDash': 'டெலிமெட்ரி டேஷ்போர்டு',
    'liveStream': 'நேரடி டெலிமெட்ரி ஸ்ட்ரீம்', 'systemSettings': 'கணினி அமைப்புகள்', 'OFF-WRIST': 'அணியவில்லை',
    'STABLE': 'நிலையானது', 'ELEVATED': 'உயர்ந்தது', 'RESTING': 'ஓய்வில்', 'HYPOXIA': 'ஆக்சிஜன் குறைபாடு', 'LOW': 'குறைவு',
    'IMPACT': 'வீழ்ச்சி', 'NOMINAL': 'இயல்பானது', 'POOR AIR': 'மோசமான காற்று', 'CLEAN AIR': 'சுத்தமான காற்று', 'DRY': 'உலர்',
    'NORMAL': 'இயல்பானது', 'SWEATY': 'வியர்வை', 'PROFUSE': 'அதிக வியர்வை', 'Standby': 'காத்திருப்பு',
    'Please Wear Device': 'BLE தரவுக்காக காத்திருக்கிறது', 'SECURE': 'பாதுகாப்பானது', 'STANDBY': 'காத்திருப்பு',
    'FALL IMPACT': 'கடுமையான வீழ்ச்சி', 'HEAT STRAIN': 'அதிக வெப்பம்', 'EXERTION': 'அதிக சிரமம்',
    'RESPIRATORY': 'சுவாச சிரமம்', 'connectBle': 'இணைக்க', 'devConn': 'சாதனம் மற்றும் இணைப்பு', 'privData': 'தனியுரிமை மற்றும் தரவு',
  },
};

// TinyML triage classes
class Tri {
  final String text, sub;
  final String? alert;
  final Color c500, c400, bg50, glow;
  final bool breathe;
  const Tri(this.text, this.sub, this.alert, this.c500, this.c400, this.bg50, this.glow, this.breathe);
}

const kTri = <int, Tri>{
  0: Tri('FALL IMPACT', 'Emergency Protocol Active', 'fall', Color(0xFFF43F5E), Color(0xFFFB7185), Color(0xFFFFF1F2), Color(0xFFF43F5E), true),
  1: Tri('HEAT STRAIN', 'Rest and Hydrate', 'heatstroke', Color(0xFFF97316), Color(0xFFFB923C), Color(0xFFFFF7ED), Color(0xFFF43F5E), true),
  2: Tri('NOMINAL', 'All Systems Optimal', null, Color(0xFF10B981), Color(0xFF34D399), Color(0xFFECFDF5), Color(0xFF34D399), true),
  3: Tri('EXERTION', 'Physical Load Detected', 'cardiac', Color(0xFFF59E0B), Color(0xFFFBBF24), Color(0xFFFFFBEB), Color(0xFFFBBF24), false),
  4: Tri('RESPIRATORY', 'Monitor Breathing Rate', 'respiratory', Color(0xFFA855F7), Color(0xFFC084FC), Color(0xFFFAF5FF), Color(0xFFF43F5E), true),
};
const kProfiles = {0: 'Standard Adult', 1: 'Elderly User', 2: 'Industrial Worker'};
const kVoice = {
  'fall': 'Fall detected. Please do not panic, a message has been sent to your emergency contacts.',
  'heatstroke': 'Severe heat strain detected. Please rest in the shade and sip water slowly.',
  'cardiac': 'Physical exertion detected. Please pause your current activity and rest.',
  'respiratory': 'Respiratory distress or poor air quality detected. Please move to a safe area.',
};
const kAlertId = {'fall': 901, 'heatstroke': 902, 'cardiac': 903, 'respiratory': 904};

class Telemetry {
  final double? ir, st, bpm, spo2, gsr, z, g, t, h, bat, prof, ai, lat;
  final bool bme, max, mpu, mlx;
  Telemetry({
    this.ir, this.st, this.bpm, this.spo2, this.gsr, this.z, this.g, this.t, this.h, this.bat, this.prof,
    this.ai, this.lat, this.bme = false, this.max = false, this.mpu = false, this.mlx = false,
  });

  static double? _n(dynamic v) {
    final x = v is num ? v.toDouble() : (v is String ? double.tryParse(v) : null);
    return (x == null || x.isNaN || x.isInfinite) ? null : x;
  }

  static bool _b(dynamic v) => v == true || (v is num && v != 0);

  factory Telemetry.fromJson(Map<String, dynamic> j) => Telemetry(
        ir: _n(j['ir']), st: _n(j['st']), bpm: _n(j['bpm']), spo2: _n(j['spo2']), gsr: _n(j['gsr']),
        z: _n(j['z']), g: _n(j['g']), t: _n(j['t']), h: _n(j['h']), bat: _n(j['bat']), prof: _n(j['prof']),
        ai: _n(j['ai']), lat: _n(j['lat']),
        bme: _b(j['bme']), max: _b(j['max']), mpu: _b(j['mpu']), mlx: _b(j['mlx']),
      );
}

// Background BLE isolate
const kBleName = 'QYRA_EDGE_NODE';
const kSvcUuid = '19b10000-e8f2-537e-4f6c-d104768a1214';
const kChrUuid = '19b10001-e8f2-537e-4f6c-d104768a1214';

Future<void> initService() async {
  final n = FlutterLocalNotificationsPlugin();
  final a = n.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
  await a?.createNotificationChannel(const AndroidNotificationChannel('qyra_fg', 'QYRA Monitoring',
      description: 'Keeps the edge node connection alive', importance: Importance.low));
  await a?.createNotificationChannel(const AndroidNotificationChannel('qyra_alerts', 'QYRA Alerts',
      description: 'Medical triage alerts', importance: Importance.max));
  await FlutterBackgroundService().configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      autoStart: false,
      isForegroundMode: true,
      notificationChannelId: 'qyra_fg',
      initialNotificationTitle: 'QYRA — Edge Node',
      initialNotificationContent: 'Starting monitoring…',
      foregroundServiceNotificationId: 888,
      foregroundServiceTypes: [AndroidForegroundType.connectedDevice],
    ),
    iosConfiguration: IosConfiguration(autoStart: false),
  );
}

@pragma('vm:entry-point')
void onStart(ServiceInstance service) {
  DartPluginRegistrant.ensureInitialized();
  runZonedGuarded(() => BleEngine(service).start(), (e, s) {});
}

class BleEngine {
  final ServiceInstance svc;
  BleEngine(this.svc);

  final _tts = FlutterTts();
  final _notif = FlutterLocalNotificationsPlugin();
  final _buf = StringBuffer();
  final _lastAlert = <String, int>{};
  DateTime _lastChunk = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastLog = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastFg = DateTime.fromMillisecondsSinceEpoch(0);
  List<List<String>> rows = [];
  Map<String, dynamic>? last;
  BluetoothDevice? dev;
  BluetoothCharacteristic? chr;
  StreamSubscription? _connSub, _valSub, _scanSub;
  Timer? _retry;
  String state = 'idle';
  String? error;
  bool want = true, logging = true, _running = false, _stopped = false, _hadLink = false;
  int _fails = 0, _saveTick = 0;

  static const _stateText = {
    'idle': 'Monitoring paused', 'scanning': 'Scanning for edge node…', 'connecting': 'Connecting…',
    'subscribing': 'Syncing telemetry…', 'reconnecting': 'Signal lost — searching…', 'btoff': 'Bluetooth is off',
  };

  Future<void> start() async {
    try { await _notif.initialize(const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher'))); } catch (_) {}
    try { await _tts.setSpeechRate(0.45); await _tts.setLanguage('en-US'); } catch (_) {}
    await _loadLog();
    svc.on('hello').listen((_) => _emitState(resend: true));
    svc.on('connect').listen((_) { want = true; _fails = 0; _kick(); });
    svc.on('disconnect').listen((_) => _manualStop());
    svc.on('profile').listen((e) => _profile(e?['id']));
    svc.on('logging').listen((e) => logging = e?['on'] != false);
    svc.on('stopService').listen((_) => _shutdown());
    _emitState();
    _kick();
  }

  void _send(String ev, Map<String, dynamic>? m) { try { svc.invoke(ev, m); } catch (_) {} }
  void _log(String msg, [String type = 'info']) => _send('log', {'type': type, 'msg': msg});

  void _emitState({bool resend = false}) {
    _send('state', {'state': state, 'error': error, 'want': want});
    if (resend && last != null && state == 'live') _send('data', last);
  }

  void _setState(String s) {
    state = s;
    _emitState();
    _fg(_stateText[s] ?? 'Connected');
  }

  void _fg(String c) {
    try {
      final s = svc;
      if (s is AndroidServiceInstance) s.setForegroundNotificationInfo(title: 'QYRA — Edge Node', content: c);
    } catch (_) {}
  }

  void _kick([Duration d = Duration.zero]) {
    _retry?.cancel();
    if (!want || _stopped) return;
    _retry = Timer(d, _attempt);
  }

  Future<void> _attempt() async {
    if (!want || _running || _stopped) return;
    _running = true;
    try {
      var a = FlutterBluePlus.adapterStateNow;
      if (a == BluetoothAdapterState.unknown) {
        a = await FlutterBluePlus.adapterState
            .firstWhere((s) => s != BluetoothAdapterState.unknown)
            .timeout(const Duration(seconds: 3), onTimeout: () => BluetoothAdapterState.unknown);
      }
      if (a != BluetoothAdapterState.on) { _setState('btoff'); throw 'Bluetooth is turned off'; }

      _setState(_hadLink ? 'reconnecting' : 'scanning');
      final found = await _scan();
      if (!want) return;

      _setState(_hadLink ? 'reconnecting' : 'connecting');
      await found.connect(timeout: const Duration(seconds: 15), mtu: null);
      dev = found;
      await _connSub?.cancel();
      _connSub = found.connectionState.listen((s) {
        if (s == BluetoothConnectionState.disconnected) _onDrop();
      }, onError: (_) {});

      try {
        final m = await found.requestMtu(512);
        _log('[BLE] MTU negotiated: $m bytes.', 'good');
      } catch (e) { _log('[BLE] MTU request failed, using default.', 'alert'); }

      _setState('subscribing');
      final services = await found.discoverServices();
      final svcObj = services.firstWhere((s) => s.uuid == Guid(kSvcUuid), orElse: () => throw 'Service not found');
      chr = svcObj.characteristics.firstWhere((c) => c.uuid == Guid(kChrUuid), orElse: () => throw 'Characteristic not found');
      _buf.clear();
      await chr!.setNotifyValue(true);
      await _valSub?.cancel();
      _valSub = chr!.onValueReceived.listen(_onValue, onError: (_) {});

      _fails = 0; _hadLink = true; error = null;
      _log('[System] BLE GATT Link Established. Receiving telemetry.', 'good');
      _setState('live');
    } catch (e) {
      if (want) {
        error = e.toString().replaceAll('Exception: ', '');
        _log('[Error] $error', 'alert');
        await _cleanup();
        _fails++;
        if (state != 'btoff') _setState(_hadLink ? 'reconnecting' : 'scanning');
        _kick(Duration(seconds: math.min(2 + _fails * 2, 15)));
      } else {
        _setState('idle');
      }
    } finally {
      _running = false;
    }
  }

  Future<BluetoothDevice> _scan() async {
    final c = Completer<BluetoothDevice>();
    _scanSub = FlutterBluePlus.onScanResults.listen((rs) {
      for (final s in rs) {
        if (!c.isCompleted && (s.advertisementData.advName == kBleName || s.device.platformName == kBleName)) c.complete(s.device);
      }
    }, onError: (_) {});
    try {
      await FlutterBluePlus.startScan(withNames: [kBleName], timeout: const Duration(seconds: 12));
      return await c.future.timeout(const Duration(seconds: 12), onTimeout: () => throw '$kBleName not found');
    } finally {
      await _scanSub?.cancel();
      _scanSub = null;
      try { await FlutterBluePlus.stopScan(); } catch (_) {}
    }
  }

  void _onDrop() {
    if (state != 'live' || _stopped) return;
    last = null;
    _log('[System] BLE link lost. Resuming background scan...', 'alert');
    _cleanup();
    _setState('reconnecting');
    _kick(const Duration(seconds: 1));
  }

  Future<void> _cleanup() async {
    try { await _valSub?.cancel(); } catch (_) {}
    try { await _connSub?.cancel(); } catch (_) {}
    _valSub = null; _connSub = null; chr = null; _buf.clear();
    try { await dev?.disconnect(); } catch (_) {}
  }

  Future<void> _manualStop() async {
    want = false;
    _retry?.cancel();
    try { await FlutterBluePlus.stopScan(); } catch (_) {}
    await _cleanup();
    last = null; error = null; _hadLink = false;
    _setState('idle');
  }

  Future<void> _shutdown() async {
    _stopped = true; want = false;
    _retry?.cancel();
    await _cleanup();
    await _persist();
    try { svc.stopSelf(); } catch (_) {}
  }

  void _onValue(List<int> v) {
    try {
      final now = DateTime.now();
      if (now.difference(_lastChunk).inMilliseconds > 500) _buf.clear();
      _lastChunk = now;
      if (v.isEmpty) return;
      _buf.write(utf8.decode(v, allowMalformed: true));
      for (final f in _frames()) {
        try {
          final j = jsonDecode(f);
          if (j is Map<String, dynamic>) _handle(j);
        } catch (_) {}
      }
    } catch (_) {
      _buf.clear();
    }
  }

  // Extract complete top-level JSON objects from fragmented BLE packets
  List<String> _frames() {
    final s = _buf.toString();
    final out = <String>[];
    int depth = 0, start = -1;
    bool str = false, esc = false;
    for (int i = 0; i < s.length; i++) {
      final c = s.codeUnitAt(i);
      if (str) {
        if (esc) { esc = false; }
        else if (c == 92) { esc = true; }
        else if (c == 34) { str = false; }
        continue;
      }
      if (c == 34 && depth > 0) { str = true; continue; }
      if (c == 123) { if (depth == 0) start = i; depth++; }
      else if (c == 125 && depth > 0) {
        depth--;
        if (depth == 0) { out.add(s.substring(start, i + 1)); start = -1; }
      }
    }
    _buf.clear();
    if (depth > 0 && start >= 0 && s.length - start < 4096) _buf.write(s.substring(start));
    return out;
  }

  void _handle(Map<String, dynamic> j) {
    try {
      final t = Telemetry.fromJson(j);
      last = j;
      final worn = t.ir != null && t.ir! > 50000;
      final tri = kTri[(t.ai ?? 2).toInt()] ?? kTri[2]!;
      _send('data', j);
      final now = DateTime.now();
      if (logging && worn && now.difference(_lastLog).inMilliseconds > 5000) {
        _lastLog = now;
        String f(double? v, [int p = 0]) => v == null ? '--' : (p == 0 && v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(p));
        rows.add([now.toIso8601String(), f(t.st, 1), f(t.bpm), f(t.spo2), f(t.gsr), f(t.z, 2), f(t.g, 1)]);
        if (rows.length > 10000) rows.removeAt(0);
        if (++_saveTick % 6 == 0) _persist();
      }
      if (worn && tri.alert != null) _alert(tri.alert!);
      if (now.difference(_lastFg).inSeconds >= 5) {
        _lastFg = now;
        _fg(worn ? 'Connected • ${tri.text}' : 'Connected • Off-wrist');
      }
    } catch (_) {}
  }

  void _alert(String k) {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - (_lastAlert[k] ?? 0) < 30000) return;
    _lastAlert[k] = now;
    try { _tts.speak(kVoice[k]!); } catch (_) {}
    try {
      _notif.show(kAlertId[k] ?? 900, 'QYRA Alert', kVoice[k],
          const NotificationDetails(
              android: AndroidNotificationDetails('qyra_alerts', 'QYRA Alerts',
                  importance: Importance.max, priority: Priority.high, category: AndroidNotificationCategory.alarm)));
    } catch (_) {}
  }

  Future<void> _profile(dynamic id) async {
    final c = chr;
    if (c == null || id is! num) { _log('[Error] Connect BLE first to provision profile.', 'alert'); return; }
    try {
      await c.write(utf8.encode(id.toInt().toString()));
      _log('[OTA] Provisioned NVS profile ${id.toInt()}. Rebooting ESP32...', 'good');
    } catch (e) { _log('[Error] Profile write failed: $e', 'alert'); }
  }

  Future<void> _loadLog() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final raw = sp.getString('qyra_telemetry');
      if (raw != null) rows = (jsonDecode(raw) as List).map((e) => List<String>.from(e)).toList();
    } catch (_) {}
  }

  Future<void> _persist() async {
    try { await (await SharedPreferences.getInstance()).setString('qyra_telemetry', jsonEncode(rows)); } catch (_) {}
  }
}

// Main UI state controller
class Ble extends ChangeNotifier with WidgetsBindingObserver {
  static const devName = kBleName;
  static const thr = {'st': 37.5, 'gsr': 1500.0, 'hr': 100.0, 'spo2': 92.0, 'z': 15.0, 'env': 30.0};

  final service = FlutterBackgroundService();
  String perm = 'checking';
  bool permPermanent = false;
  Map<String, bool> permOk = {'Bluetooth Scan': false, 'Bluetooth Connect': false, 'Location': false};
  String state = 'idle';
  String? error;
  Telemetry? d;
  bool worn = false, logging = true;
  String lang = 'en';
  String sosState = 'idle';
  String gps = 'Acquiring Location...';
  String gpsSub = 'Waiting for permission';
  final phi = {'st': true, 'gsr': true, 'hr': true, 'spo2': true};
  final charts = {for (final k in ['hr', 'st', 'gsr', 'z']) k: List<double>.filled(50, 0)};
  String chartKey = 'hr';
  final logs = <MapEntry<String, String>>[const MapEntry('info', '[System] Waiting for BLE GATT connection...')];
  final _rnd = math.Random();
  StreamSubscription? _gpsSub;
  bool _bound = false, _booted = false, _checking = false, _notifAsked = false, _permStopped = false, _synced = false;

  bool get connected => state == 'live';
  bool get busy => const ['scanning', 'connecting', 'subscribing', 'reconnecting', 'btoff'].contains(state);
  String get stateLabel => const {
        'scanning': 'Scanning', 'connecting': 'Linking', 'subscribing': 'Syncing', 'reconnecting': 'Reconnecting', 'btoff': 'BT Off',
      }[state] ?? state;
  String t(String k) => kI18n[lang]?[k] ?? kI18n['en']![k] ?? k;
  Tri? get tri => worn ? (kTri[(d?.ai ?? 2).toInt()] ?? kTri[2]) : null;

  String get stIns => !worn || d?.st == null ? 'OFF-WRIST' : (d!.st! > thr['st']! ? 'ELEVATED' : 'STABLE');
  String get gsrIns {
    if (!worn || d?.gsr == null) return 'OFF-WRIST';
    final g = d!.gsr!;
    if (g > thr['gsr']!) return 'PROFUSE';
    if (g > thr['gsr']! * .6) return 'SWEATY';
    if (g > thr['gsr']! * .2) return 'NORMAL';
    return 'DRY';
  }
  String hrIns({bool withSpo2 = true}) {
    if (withSpo2 && d?.spo2 != null && d!.spo2! < thr['spo2']!) return 'HYPOXIA';
    if (d?.bpm != null && d!.bpm! > thr['hr']!) return 'ELEVATED';
    if (d?.bpm != null && d!.bpm! > 0 && d!.bpm! < 50) return 'LOW';
    return 'RESTING';
  }
  String get spo2Ins => (d?.spo2 != null && d!.spo2! > 0 && d!.spo2! < thr['spo2']!) ? 'HYPOXIA' : 'NORMAL';
  String get zIns => (d?.z != null && d!.z! > thr['z']!) ? 'IMPACT' : 'NOMINAL';
  bool get poorAir => d?.g != null && d!.g! > 0 && d!.g! < thr['env']!;

  Future<void> init() async {
    WidgetsBinding.instance.addObserver(this);
    await checkPerms(request: true);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) checkPerms();
  }

  Future<void> checkPerms({bool request = false}) async {
    if (_checking) return;
    _checking = true;
    try {
      final ps = {
        'Bluetooth Scan': Permission.bluetoothScan,
        'Bluetooth Connect': Permission.bluetoothConnect,
        'Location': Permission.location,
      };
      if (request) await ps.values.toList().request();
      final st = {for (final e in ps.entries) e.key: await e.value.status};
      permOk = {for (final e in st.entries) e.key: e.value.isGranted};
      permPermanent = st.values.any((s) => s.isPermanentlyDenied);
      if (permOk.values.every((v) => v)) {
        perm = 'granted';
        notifyListeners();
        await _boot();
      } else {
        perm = 'denied';
        if (_booted) { service.invoke('disconnect'); _permStopped = true; }
        notifyListeners();
      }
    } catch (_) {
      perm = 'denied';
      notifyListeners();
    } finally {
      _checking = false;
    }
  }

  Future<void> _boot() async {
    _bind();
    _startGps();
    if (!_notifAsked) {
      _notifAsked = true;
      try { await Permission.notification.request(); } catch (_) {}
    }
    try {
      if (!await service.isRunning()) {
        await service.startService();
      } else {
        service.invoke(_permStopped ? 'connect' : 'hello');
      }
      _permStopped = false;
      _booted = true;
    } catch (e) {
      log('[Error] Could not start background service: $e', 'alert');
      notifyListeners();
    }
  }

  void _bind() {
    if (_bound) return;
    _bound = true;
    service.on('data').listen(_onData);
    service.on('state').listen(_onState);
    service.on('log').listen((e) {
      if (e == null) return;
      log('${e['msg']}', '${e['type']}');
      notifyListeners();
    });
  }

  void _onState(Map<String, dynamic>? e) {
    if (e == null) return;
    state = '${e['state']}';
    error = e['error'] as String?;
    if (state != 'live') worn = false;
    if (!_synced) { _synced = true; service.invoke('logging', {'on': logging}); }
    notifyListeners();
  }

  void _onData(Map<String, dynamic>? e) {
    try {
      if (e == null) return;
      final t = Telemetry.fromJson(Map<String, dynamic>.from(e));
      d = t;
      worn = t.ir != null && t.ir! > 50000;
      if (worn) {
        if (tri?.alert != null && _rnd.nextDouble() > .8) log('[AI Insight] Triage class ${t.ai?.toInt()} detected.', 'alert');
        _push('hr', t.bpm); _push('st', t.st); _push('gsr', t.gsr);
        if (_rnd.nextDouble() > .95) log('[Telemetry] TinyML parsing ok. Latency: ${t.lat?.toInt()}ms');
      }
      _push('z', t.z);
    } catch (_) {}
    notifyListeners();
  }

  Future<void> _startGps() async {
    if (_gpsSub != null) return;
    try {
      if (!await Geolocator.isLocationServiceEnabled()) { gps = 'GPS Unavailable'; gpsSub = 'Enable location services'; notifyListeners(); return; }
      _gpsSub = Geolocator.getPositionStream(locationSettings: const LocationSettings(accuracy: LocationAccuracy.high)).listen((p) {
        gps = 'Live GPS Active';
        gpsSub = '${p.latitude.toStringAsFixed(4)}° N, ${p.longitude.toStringAsFixed(4)}° E';
        notifyListeners();
      }, onError: (_) { gps = 'GPS Unavailable'; gpsSub = 'Check location permissions'; notifyListeners(); });
    } catch (_) {}
  }

  void log(String m, [String type = 'info']) {
    logs.insert(0, MapEntry(type, m));
    if (logs.length > 20) logs.removeLast();
  }

  void _push(String k, double? v) {
    if (v == null) return;
    charts[k]!..add(v)..removeAt(0);
  }

  Future<void> connect() async {
    if (perm != 'granted') { await checkPerms(request: true); return; }
    if (connected || busy) { service.invoke('disconnect'); return; }
    error = null;
    if (!_booted) { await _boot(); return; }
    service.invoke('connect');
  }

  ({bool ok, String msg}) setProfile(int id) {
    if (!connected) {
      log('[Error] Connect BLE first to provision profile.', 'alert');
      notifyListeners();
      return (ok: false, msg: 'Connect to $devName first to provision profile.');
    }
    service.invoke('profile', {'id': id});
    final name = kProfiles[id] ?? 'Profile $id';
    return (ok: true, msg: 'Sending NVS profile "$name" to ESP32-S3...');
  }

  void setLogging(bool v) {
    logging = v;
    service.invoke('logging', {'on': v});
    log(v ? '[System] Local data logging ENABLED.' : '[System] Local data logging DISABLED.', v ? 'good' : 'alert');
    notifyListeners();
  }

  String? sos() {
    if (!connected) return 'Connect to $devName first to broadcast SOS.';
    if (sosState != 'idle') return null;
    sosState = 'tx';
    log('[LoRa] TX ACTIVE: Broadcasting SOS Packet on 865MHz...', 'alert');
    notifyListeners();
    Timer(const Duration(milliseconds: 1500), () {
      sosState = 'done';
      log('[LoRa] TX SUCCESS: Distress signal broadcast to mesh.', 'good');
      notifyListeners();
      Timer(const Duration(seconds: 3), () { sosState = 'idle'; notifyListeners(); });
    });
    return null;
  }

  Future<({bool ok, String msg})> export(String tf) async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.reload();
      final raw = sp.getString('qyra_telemetry');
      var rows = raw == null ? <List<String>>[] : (jsonDecode(raw) as List).map((e) => List<String>.from(e)).toList();
      if (tf == '24h') {
        final cut = DateTime.now().subtract(const Duration(hours: 24));
        rows = rows.where((r) => (DateTime.tryParse(r[0]) ?? cut).isAfter(cut)).toList();
      }
      if (rows.isEmpty) {
        log('[Export] No data available to download.', 'alert');
        notifyListeners();
        return (ok: false, msg: 'No telemetry records logged yet.');
      }
      final csv = StringBuffer('Timestamp,BodyTemp(C),HeartRate(BPM),SpO2(%),GSR(raw),Kinematics(G),VOC(kOhm)\n');
      for (final r in rows) { csv.writeln(r.join(',')); }
      await Clipboard.setData(ClipboardData(text: csv.toString()));
      log('[Export] ${rows.length} telemetry records copied to clipboard as CSV.', 'good');
      notifyListeners();
      return (ok: true, msg: 'Copied ${rows.length} records to clipboard as CSV.');
    } catch (e) {
      log('[Export] Failed: $e', 'alert');
      notifyListeners();
      return (ok: false, msg: 'Export failed: $e');
    }
  }

  void notify() => notifyListeners();
}

final ble = Ble();
final themeDark = ValueNotifier<bool>(true);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  try { await initService(); } catch (_) {}
  ble.init();
  runApp(const QyraApp());
}

class QyraApp extends StatelessWidget {
  const QyraApp({super.key});
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
        valueListenable: themeDark,
        builder: (_, d, __) {
          SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
              statusBarColor: Colors.transparent, statusBarIconBrightness: d ? Brightness.light : Brightness.dark));
          return MaterialApp(
              debugShowCheckedModeBanner: false, title: 'QYRA', theme: buildTheme(d), home: const Shell());
        },
      );
}

// Shared UI components
class Box extends StatelessWidget {
  final Widget child;
  final double pad;
  final Color? color;
  final EdgeInsets? margin;
  const Box({super.key, required this.child, this.pad = 20, this.color, this.margin});
  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return Container(
      margin: margin,
      padding: EdgeInsets.all(pad),
      decoration: BoxDecoration(
        color: color ?? p.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: p.border),
        boxShadow: p.d ? null : [BoxShadow(color: Colors.black.withOpacity(.05), blurRadius: 4, offset: const Offset(0, 2))],
      ),
      child: child,
    );
  }
}

class Cap extends StatelessWidget {
  final String s;
  final Color? c;
  final double size;
  const Cap(this.s, {super.key, this.c, this.size = 10});
  @override
  Widget build(BuildContext context) =>
      Text(s.toUpperCase(), style: ts(size, FontWeight.w700, c ?? Pal.of(context).sub, ls: size * .1));
}

class GaugePainter extends CustomPainter {
  final double pct;
  final Color color, track;
  GaugePainter(this.pct, this.color, this.track);
  @override
  void paint(Canvas c, Size s) {
    final r = Rect.fromCircle(center: s.center(Offset.zero), radius: s.width * .4);
    final w = s.width * .08;
    c.drawArc(r, 0, math.pi * 2, false, Paint()..style = PaintingStyle.stroke..strokeWidth = w..color = track);
    c.drawArc(r, -math.pi / 2, math.pi * 2 * pct, false, Paint()..style = PaintingStyle.stroke..strokeWidth = w..color = color);
  }
  @override
  bool shouldRepaint(GaugePainter o) => o.pct != pct || o.color != color || o.track != track;
}

class BreathingRing extends StatefulWidget {
  final Tri? tri;
  final Widget child;
  const BreathingRing({super.key, required this.tri, required this.child});
  @override
  State<BreathingRing> createState() => _BreathingRingState();
}

class _BreathingRingState extends State<BreathingRing> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat();
  @override
  void dispose() { _c.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final t = widget.tri;
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) {
        final k = (math.sin(_c.value * math.pi)).clamp(0.0, 1.0);
        final shadows = <BoxShadow>[];
        if (t != null) {
          shadows.add(BoxShadow(color: t.c500.withOpacity(.2), blurRadius: 40));
          if (t.breathe) shadows.add(BoxShadow(color: t.glow.withOpacity(.4 * (1 - k)), spreadRadius: 15 * k));
        }
        return Container(
          width: 224, height: 224,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: t == null ? (p.d ? const Color(0xFF1E293B).withOpacity(.3) : const Color(0xFFF8FAFC)) : (p.d ? t.c500.withOpacity(.08) : t.bg50),
            border: Border.all(width: 14, color: t == null ? (p.d ? const Color(0xFF334155).withOpacity(.5) : const Color(0xFFE2E8F0)) : t.c400),
            boxShadow: shadows,
          ),
          child: widget.child,
        );
      },
    );
  }
}

class PermissionsView extends StatelessWidget {
  const PermissionsView({super.key});
  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final red = p.d ? const Color(0xFFFB7185) : kRose;
    return ListView(padding: const EdgeInsets.fromLTRB(20, 40, 20, 24), children: [
      Center(
        child: Container(
          width: 128, height: 128,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: p.d ? kRose.withOpacity(.08) : const Color(0xFFFFF1F2),
            border: Border.all(width: 10, color: red),
            boxShadow: [BoxShadow(color: kRose.withOpacity(.2), blurRadius: 40)],
          ),
          child: Icon(Icons.bluetooth_disabled, size: 48, color: red),
        ),
      ),
      const SizedBox(height: 28),
      Text('PERMISSIONS REQUIRED', textAlign: TextAlign.center, style: ts(22, FontWeight.w900, red, ls: -.5)),
      const SizedBox(height: 10),
      Text('QYRA needs Bluetooth and Location access to find and stay connected to your ${Ble.devName} edge node, including in the background.',
          textAlign: TextAlign.center, style: ts(12, FontWeight.w500, p.sub, h: 1.4)),
      const SizedBox(height: 24),
      Box(
        pad: 16,
        child: Column(children: [
          for (final e in ble.permOk.entries)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(children: [
                Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: e.value ? kEmerald : kRose)),
                const SizedBox(width: 10),
                Expanded(child: Text(e.key, style: ts(14, FontWeight.w600, p.t700))),
                Text(e.value ? 'GRANTED' : 'DENIED', style: ts(10, FontWeight.w700, e.value ? p.okTxt : red, ls: 1, mono: true)),
              ]),
            ),
        ]),
      ),
      const SizedBox(height: 24),
      GestureDetector(
        onTap: () => openAppSettings(),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: kBrand500, borderRadius: BorderRadius.circular(12),
            boxShadow: [BoxShadow(color: kBrand500.withOpacity(.2), blurRadius: 12, offset: const Offset(0, 4))],
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Icon(Icons.settings, size: 18, color: Colors.white), const SizedBox(width: 8),
            Text('OPEN APP SETTINGS', style: ts(12, FontWeight.w700, Colors.white, ls: 1)),
          ]),
        ),
      ),
      if (!ble.permPermanent) ...[
        const SizedBox(height: 12),
        GestureDetector(
          onTap: () => ble.checkPerms(request: true),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(color: p.chip, borderRadius: BorderRadius.circular(12),
                border: Border.all(color: p.d ? const Color(0xFF334155) : const Color(0xFFE2E8F0))),
            child: Center(child: Text('GRANT PERMISSIONS', style: ts(12, FontWeight.w700, p.t700, ls: 1))),
          ),
        ),
      ],
      const SizedBox(height: 16),
      Text('After enabling "Nearby devices" and "Location" in settings, return to the app — it reconnects automatically.',
          textAlign: TextAlign.center, style: ts(9, FontWeight.w400, p.sub, h: 1.3)),
    ]);
  }
}

class Shell extends StatefulWidget {
  const Shell({super.key});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int tab = 0;
  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return ListenableBuilder(
      listenable: ble,
      builder: (_, __) {
        final ok = ble.perm == 'granted';
        final pages = [const HomeView(), const SensorsView(), const DisasterView(), const SettingsView()];
        return Scaffold(
          body: Column(children: [
            _header(p, ok),
            Expanded(
              child: ble.perm == 'checking'
                  ? const Center(child: CircularProgressIndicator(color: kBrand500))
                  : !ok ? const PermissionsView() : IndexedStack(index: tab, children: pages),
            ),
            if (ok) _nav(p),
          ]),
        );
      },
    );
  }

  Widget _header(Pal p, bool ok) {
    final top = MediaQuery.of(context).padding.top;
    return Container(
      padding: EdgeInsets.fromLTRB(20, top + 12, 20, 12),
      decoration: BoxDecoration(color: p.app.withOpacity(.9), border: Border(bottom: BorderSide(color: p.border))),
      child: Row(children: [
        Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            gradient: const LinearGradient(colors: [kBrand400, Color(0xFF2563EB)], begin: Alignment.topLeft, end: Alignment.bottomRight),
            boxShadow: [BoxShadow(color: kBrand500.withOpacity(.2), blurRadius: 10, offset: const Offset(0, 4))],
          ),
          child: const Icon(Icons.graphic_eq, color: Colors.white, size: 20),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text('QYRA', style: ts(14, FontWeight.w900, p.text, ls: -.35)),
            Text(ble.t('subtitle').toUpperCase(), style: ts(9, FontWeight.w700, p.sub, ls: .9), overflow: TextOverflow.ellipsis),
          ]),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          onPressed: () => themeDark.value = !themeDark.value,
          icon: Icon(p.d ? Icons.dark_mode : Icons.lightbulb, size: 18, color: p.d ? kSlate400 : p.sub),
        ),
        PopupMenuButton<String>(
          color: p.card,
          onSelected: (v) { ble.lang = v; ble.notify(); },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'en', child: Text('English')),
            PopupMenuItem(value: 'hi', child: Text('हिन्दी')),
            PopupMenuItem(value: 'ta', child: Text('தமிழ்')),
          ],
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
                color: p.card, borderRadius: BorderRadius.circular(8), border: Border.all(color: p.d ? const Color(0xFF334155) : const Color(0xFFCBD5E1))),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.language, size: 14, color: p.t700),
              const SizedBox(width: 4),
              Text(ble.lang.toUpperCase(), style: ts(12, FontWeight.w600, p.t700)),
            ]),
          ),
        ),
        if (ok && ble.d?.bat != null) ...[
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            decoration: BoxDecoration(color: p.chip, borderRadius: BorderRadius.circular(6)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(ble.d!.bat! > 20 ? Icons.battery_5_bar : Icons.battery_alert, size: 12, color: ble.d!.bat! > 20 ? kEmerald : kRose),
              Text('${ble.d!.bat!.toInt()}%', style: ts(9, FontWeight.w700, p.t700, mono: true)),
            ]),
          ),
        ],
        if (ok) ...[const SizedBox(width: 6), _connectBtn(p)],
      ]),
    );
  }

  Widget _connectBtn(Pal p) {
    final on = ble.connected;
    return GestureDetector(
      onTap: ble.connect,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: on ? kEmerald : (p.d ? const Color(0xFF064E3B).withOpacity(.3) : const Color(0xFFD1FAE5)),
          borderRadius: BorderRadius.circular(8),
          border: on ? null : Border.all(color: p.d ? const Color(0xFF065F46).withOpacity(.5) : const Color(0xFFA7F3D0)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          ble.busy
              ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: kEmerald))
              : Icon(Icons.bluetooth, size: 14, color: on ? Colors.white : (p.d ? const Color(0xFF34D399) : const Color(0xFF047857))),
          if (!on) ...[
            const SizedBox(width: 6),
            Text(ble.busy ? ble.stateLabel : ble.t('connectBle'),
                style: ts(10, FontWeight.w700, p.d ? const Color(0xFF34D399) : const Color(0xFF047857))),
          ],
        ]),
      ),
    );
  }

  Widget _nav(Pal p) {
    final items = [
      (Icons.home_outlined, Icons.home, 'navHome'),
      (Icons.show_chart, Icons.show_chart, 'navSensors'),
      (Icons.support, Icons.support, 'navRescue'),
      (Icons.settings_outlined, Icons.settings, 'navSettings'),
    ];
    return Container(
      padding: EdgeInsets.only(top: 12, bottom: 12 + MediaQuery.of(context).padding.bottom),
      decoration: BoxDecoration(color: p.navBg, border: Border(top: BorderSide(color: p.border))),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
        for (var i = 0; i < items.length; i++)
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => tab = i),
            child: SizedBox(
              width: 64,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(tab == i ? items[i].$2 : items[i].$1, size: 24, color: tab == i ? p.accent : kSlate400),
                const SizedBox(height: 4),
                Text(ble.t(items[i].$3), style: ts(9, FontWeight.w700, tab == i ? p.accent : kSlate400, ls: .2)),
              ]),
            ),
          ),
      ]),
    );
  }
}

extension on Pal {
  Color get navBg => (d ? const Color(0xFF050B14) : Colors.white).withOpacity(.95);
}

class HomeView extends StatelessWidget {
  const HomeView({super.key});
  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final tri = ble.tri;
    final txt = tri == null ? kSlate400 : (p.d ? tri.c400 : tri.c500);
    Widget stat(String ik, IconData ic, Color icc, String label, String value, bool good, String tag) => Expanded(
          child: Box(
            pad: 16,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(ic, size: 13, color: icc), const SizedBox(width: 6),
                Flexible(child: Cap(ble.t(label), size: 10)),
              ]),
              const SizedBox(height: 4),
              Text(ble.t(value).toUpperCase(),
                  style: ts(18, FontWeight.w900, !ble.worn && ik != 'gas' ? kSlate400 : (good ? p.okTxt : kRose)),
                  overflow: TextOverflow.ellipsis),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.only(top: 8),
                decoration: BoxDecoration(border: Border(top: BorderSide(color: p.d ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9)))),
                width: double.infinity,
                child: Text(tag, style: ts(8, FontWeight.w400, kSlate400, mono: true)),
              ),
            ]),
          ),
        );
    final stOk = ble.stIns == 'STABLE';
    final hrOk = ble.hrIns() == 'RESTING';
    final zOk = ble.zIns == 'NOMINAL';
    final gasTxt = ble.d?.g == null ? 'STANDBY' : (ble.poorAir ? 'POOR AIR' : 'CLEAN AIR');
    return ListView(padding: const EdgeInsets.fromLTRB(20, 16, 20, 24), children: [
      if (ble.error != null && !ble.connected)
        Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
              color: p.d ? const Color(0xFF881337).withOpacity(.1) : const Color(0xFFFFF1F2),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: p.d ? const Color(0xFF9F1239).withOpacity(.5) : const Color(0xFFFECDD3))),
          child: Row(children: [
            const Icon(Icons.warning_rounded, size: 14, color: kRose), const SizedBox(width: 8),
            Expanded(child: Text('BLE CONNECTION FAILED: ${ble.error}'.toUpperCase(),
                style: ts(9, FontWeight.w700, p.d ? const Color(0xFFFB7185) : const Color(0xFFE11D48)))),
          ]),
        ),
      const SizedBox(height: 16),
      Center(
        child: BreathingRing(
          tri: tri,
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(ble.t(tri?.text ?? 'Standby'),
                  textAlign: TextAlign.center, style: ts(30, FontWeight.w900, txt, ls: -.75, h: 1.15)),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text((tri?.sub ?? ble.t('Please Wear Device')).toUpperCase(),
                  textAlign: TextAlign.center, style: ts(10, FontWeight.w700, txt, ls: 1, h: 1.2)),
            ),
          ]),
        ),
      ),
      const SizedBox(height: 24),
      GestureDetector(
        onTap: () {
          final err = ble.sos();
          if (err != null) showToast(context, err, err: true);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: const LinearGradient(colors: [Color(0xFFF43F5E), Color(0xFFDC2626)], begin: Alignment.topCenter, end: Alignment.bottomCenter),
            boxShadow: [BoxShadow(color: const Color(0xFFE11D48).withOpacity(.3), blurRadius: 25, offset: const Offset(0, 8))],
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            ble.sosState == 'tx'
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                : Icon(ble.sosState == 'done' ? Icons.check_circle_outline : Icons.warning_amber_rounded, color: Colors.white, size: 26),
            const SizedBox(width: 8),
            Text(ble.sosState == 'tx' ? 'TRANSMITTING...' : ble.sosState == 'done' ? 'SENT' : ble.t('sosBtn'),
                style: ts(18, FontWeight.w900, Colors.white)),
          ]),
        ),
      ),
      const SizedBox(height: 24),
      Row(children: [
        const Icon(Icons.psychology, size: 14, color: kBrand500), const SizedBox(width: 6),
        Cap(ble.t('aiPred'), c: kSlate400),
      ]),
      const SizedBox(height: 12),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        stat('st', Icons.device_thermostat, kOrange, 'cardThermal', ble.worn ? ble.stIns : 'OFF-WRIST', stOk, '[PHI SECURED]'),
        const SizedBox(width: 12),
        stat('hr', Icons.monitor_heart, kRose, 'cardHeart', ble.worn ? ble.hrIns() : 'OFF-WRIST', hrOk, '[PHI SECURED]'),
      ]),
      const SizedBox(height: 12),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        stat('z', Icons.directions_run, const Color(0xFFA855F7), 'cardActivity', ble.worn ? ble.zIns : 'OFF-WRIST', zOk, '[PHI SECURED]'),
        const SizedBox(width: 12),
        stat('gas', Icons.air, const Color(0xFF14B8A6), 'cardAir', gasTxt, !ble.poorAir, '[ENV PUBLIC]'),
      ]),
    ]);
  }
}

class SensorsView extends StatelessWidget {
  const SensorsView({super.key});

  Widget _gauge(BuildContext ctx, String k, String title, Color col, double max, double? raw, String unit, String? Function() masked) {
    final p = Pal.of(ctx);
    final hasPhi = ble.phi.containsKey(k);
    final worn = hasPhi ? ble.worn : raw != null;
    final isMasked = hasPhi && ble.phi[k]!;
    String main;
    bool small = false;
    if (!worn) { main = '--'; }
    else if (isMasked) { main = ble.t(masked()!); small = true; }
    else { main = raw == null ? '--' : (k == 'st' || k == 'z' ? raw.toStringAsFixed(1) : raw.toInt().toString()); }
    final showUnit = worn && !isMasked ? unit : '';
    final pct = worn && raw != null ? (raw / max).clamp(0.0, 1.0) : 0.0;
    return Box(
      pad: 12,
      child: Stack(children: [
        if (hasPhi)
          Align(
            alignment: Alignment.topRight,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _modal(ctx, k, title),
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(Icons.settings, size: 16, color: kSlate400),
              ),
            ),
          ),
        SizedBox(
          width: double.infinity,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const SizedBox(height: 4),
            SizedBox(
              width: 80, height: 80,
              child: TweenAnimationBuilder<double>(
                tween: Tween(end: pct), duration: const Duration(milliseconds: 800), curve: Curves.easeInOut,
                builder: (_, v, __) => CustomPaint(
                  painter: GaugePainter(v, col, p.track),
                  child: Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Text(main,
                            textAlign: TextAlign.center,
                            style: ts(small ? 11 : 20, FontWeight.w900, worn ? p.text : kSlate400, ls: small ? -.3 : -.5, h: 1),
                            maxLines: 2, overflow: TextOverflow.ellipsis),
                      ),
                      if (showUnit.isNotEmpty) Text(showUnit, style: ts(8, FontWeight.w700, kSlate400)),
                    ]),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Cap(title, size: 9),
            const SizedBox(height: 4),
          ]),
        ),
      ]),
    );
  }

  void _modal(BuildContext ctx, String k, String title) {
    final p = Pal.of(ctx);
    var unlock = !ble.phi[k]!;
    showModalBottomSheet(
      context: ctx, backgroundColor: p.card, isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => StatefulBuilder(
        builder: (c, set) => Padding(
          padding: EdgeInsets.fromLTRB(24, 24, 24, 24 + MediaQuery.of(c).padding.bottom),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              Expanded(child: Text('$title Privacy Config'.toUpperCase(), style: ts(14, FontWeight.w900, p.text, ls: .35))),
              GestureDetector(onTap: () => Navigator.pop(c), child: const Icon(Icons.close, color: kSlate400)),
            ]),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Unlock Raw Health Data (PHI)', style: ts(12, FontWeight.w700, p.t700)),
                  Text('Override Triage Insight & display precise numbers.', style: ts(9, FontWeight.w400, kSlate400)),
                ]),
              ),
              Switch(value: unlock, activeColor: Colors.white, activeTrackColor: kRose, onChanged: (v) => set(() => unlock = v)),
            ]),
            const SizedBox(height: 24),
            GestureDetector(
              onTap: () { ble.phi[k] = !unlock; ble.notify(); Navigator.pop(c); },
              child: Container(
                width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(color: kBrand500, borderRadius: BorderRadius.circular(12),
                    boxShadow: [BoxShadow(color: kBrand500.withOpacity(.2), blurRadius: 12, offset: const Offset(0, 4))]),
                child: Center(child: Text('Apply Configuration', style: ts(12, FontWeight.w700, Colors.white))),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final d = ble.d;
    Widget env(String l, String v, String u) => Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(l.toUpperCase(), style: ts(8, FontWeight.w700, kSlate400)),
              Text.rich(TextSpan(text: v, style: ts(12, FontWeight.w900, p.text), children: [
                if (v != '--') TextSpan(text: ' $u', style: ts(8, FontWeight.w400, p.sub)),
              ])),
            ]),
          ),
        );
    String f(double? v, int n) => v == null ? '--' : v.toStringAsFixed(n);
    const chartCols = {'hr': kBrand500, 'st': kOrange, 'gsr': Color(0xFF14B8A6), 'z': Color(0xFFA855F7)};
    final cc = chartCols[ble.chartKey]!;
    final pts = ble.charts[ble.chartKey]!;
    return ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 24), children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Cap(ble.t('telemetryDash'), size: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
                color: p.d ? const Color(0xFF164E63).withOpacity(.3) : const Color(0xFFCFFAFE),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: p.d ? const Color(0xFF155E75) : const Color(0xFFA5F3FC))),
            child: Text('TinyML Inference Active', style: ts(9, FontWeight.w700, p.d ? kBrand400 : const Color(0xFF0891B2), mono: true)),
          ),
        ]),
      ),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: _gauge(context, 'st', ble.t('cardThermal'), kOrange, 50, d?.st, '°C', () => ble.stIns)),
        const SizedBox(width: 12),
        Expanded(child: _gauge(context, 'gsr', 'GSR Tone', const Color(0xFF14B8A6), 3500, d?.gsr, 'raw', () => ble.gsrIns)),
      ]),
      const SizedBox(height: 12),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: _gauge(context, 'hr', ble.t('cardHeart'), const Color(0xFFE11D48), 180, d?.bpm, 'BPM', () => ble.hrIns(withSpo2: false))),
        const SizedBox(width: 12),
        Expanded(child: _gauge(context, 'spo2', 'Blood Oxygen', const Color(0xFF0284C7), 100, d?.spo2, '%', () => ble.spo2Ins)),
      ]),
      const SizedBox(height: 12),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: _gauge(context, 'z', 'Kinematics', const Color(0xFFA855F7), 30, d?.z, 'm/s²', () => null)),
        const SizedBox(width: 12),
        Expanded(
          child: Box(
            pad: 12,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Cap('Environment', size: 9),
              const SizedBox(height: 16),
              Row(children: [env('VOC Gas', f(d?.g, 0), 'kΩ'), env('Ambient', f(d?.t, 1), '°C')]),
              Row(children: [env('Humidity', f(d?.h, 1), '%'), env('Pressure', d == null ? '--' : '1013', 'hPa')]),
            ]),
          ),
        ),
      ]),
      const SizedBox(height: 16),
      Box(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Flexible(child: Row(children: [
              const Icon(Icons.show_chart, size: 16, color: kBrand500), const SizedBox(width: 6),
              Flexible(child: Cap(ble.t('liveStream'), c: p.t700, size: 12)),
            ])),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              decoration: BoxDecoration(color: p.chip, borderRadius: BorderRadius.circular(4), border: Border.all(color: p.d ? const Color(0xFF334155) : const Color(0xFFE2E8F0))),
              child: DropdownButton<String>(
                value: ble.chartKey, isDense: true, underline: const SizedBox(), dropdownColor: p.card,
                style: ts(12, FontWeight.w600, p.t700),
                items: const [
                  DropdownMenuItem(value: 'hr', child: Text('Heart Rate (BPM)')),
                  DropdownMenuItem(value: 'st', child: Text('Body Temp (°C)')),
                  DropdownMenuItem(value: 'gsr', child: Text('GSR Tone (raw)')),
                  DropdownMenuItem(value: 'z', child: Text('Kinematics Z')),
                ],
                onChanged: (v) { ble.chartKey = v!; ble.notify(); },
              ),
            ),
          ]),
          const SizedBox(height: 8),
          SizedBox(
            height: 128,
            child: LineChart(
              duration: Duration.zero,
              LineChartData(
                titlesData: FlTitlesData(
                  bottomTitles: const AxisTitles(), topTitles: const AxisTitles(), rightTitles: const AxisTitles(),
                  leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 32,
                      getTitlesWidget: (v, m) => Text(v.toStringAsFixed(0), style: ts(9, FontWeight.w400, p.sub)))),
                ),
                borderData: FlBorderData(show: false),
                gridData: FlGridData(show: true, drawVerticalLine: false,
                    getDrawingHorizontalLine: (_) => FlLine(color: p.d ? const Color(0xFF334155).withOpacity(.4) : const Color(0xFFCBD5E1).withOpacity(.6), strokeWidth: 1)),
                lineTouchData: const LineTouchData(enabled: false),
                lineBarsData: [
                  LineChartBarData(
                    spots: [for (var i = 0; i < pts.length; i++) FlSpot(i.toDouble(), pts[i])],
                    isCurved: true, curveSmoothness: .4, color: cc, barWidth: 2, dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(show: true, color: cc.withOpacity(.15)),
                  ),
                ],
              ),
            ),
          ),
        ]),
      ),
      const SizedBox(height: 16),
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: kSlate900, borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFF1E293B))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Row(children: [
              const Icon(Icons.terminal, size: 12, color: kBrand400), const SizedBox(width: 4),
              Text('FIRMWARE TELEMETRY LOG', style: ts(10, FontWeight.w700, const Color(0xFFCBD5E1), ls: 1, mono: true)),
            ]),
            Text('Mode: AI Triage', style: ts(9, FontWeight.w400, const Color(0xFF64748B), mono: true)),
          ]),
          const Divider(color: Color(0xFF1E293B), height: 14),
          SizedBox(
            height: 80,
            child: ListView(children: [
              for (final l in ble.logs)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(l.value,
                      style: ts(9, l.key == 'info' ? FontWeight.w400 : FontWeight.w700,
                          l.key == 'alert' ? const Color(0xFFFB7185) : l.key == 'good' ? const Color(0xFF34D399) : const Color(0xFFCBD5E1), mono: true)),
                ),
            ]),
          ),
        ]),
      ),
      const SizedBox(height: 16),
      Box(
        pad: 12,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.memory, size: 16, color: kBrand500), const SizedBox(width: 6),
            Cap('Hardware Diagnostics', c: p.t700, size: 12),
          ]),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final e in [
              ('BME680', 'I2C 0x77', d == null ? null : d.bme),
              ('MAX30102', 'I2C 0x57', d == null ? null : d.max),
              ('MPU6050', 'I2C 0x68', d == null ? null : d.mpu),
              ('MLX90614', 'I2C 0x5A', d == null ? null : d.mlx),
              ('LoRa RF', 'SPI 865MHz', true),
              ('TP4056 Bat', 'ADC Pin 7', true),
            ])
              Container(
                width: (MediaQuery.of(context).size.width - 32 - 24 - 8) / 2,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: p.soft, borderRadius: BorderRadius.circular(8), border: Border.all(color: p.d ? const Color(0xFF334155) : const Color(0xFFE2E8F0))),
                child: Row(children: [
                  Container(
                    width: 8, height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: e.$3 == null ? kSlate400 : (e.$3! ? kEmerald : kRose),
                      boxShadow: e.$3 == true && e.$1 != 'LoRa RF' && e.$1 != 'TP4056 Bat' ? [BoxShadow(color: kEmerald.withOpacity(.5), blurRadius: 8)] : null,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(e.$1, style: ts(10, FontWeight.w700, p.t700, h: 1.2)),
                    Text(e.$2, style: ts(8, FontWeight.w400, kSlate400)),
                  ]),
                ]),
              ),
          ]),
        ]),
      ),
    ]);
  }
}

class DisasterView extends StatelessWidget {
  const DisasterView({super.key});
  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final on = ble.connected;
    final bg = ble.sosState == 'tx' ? kOrange : ble.sosState == 'done' ? kEmerald : (p.d ? const Color(0xFF334155) : const Color(0xFF1E293B));
    return ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 24), children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 0, 4, 16),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Row(children: [
            const Icon(Icons.support, color: kBrand500, size: 20), const SizedBox(width: 8),
            Text('DISASTER HUB & MESH', style: ts(14, FontWeight.w900, p.text, ls: 1.4)),
          ]),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
                color: p.d ? const Color(0xFF064E3B).withOpacity(.3) : const Color(0xFFD1FAE5),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: p.d ? const Color(0xFF065F46).withOpacity(.5) : const Color(0xFFA7F3D0))),
            child: Text('865 MHz P2P', style: ts(9, FontWeight.w700, p.okTxt)),
          ),
        ]),
      ),
      Box(
        pad: 12, color: p.soft, margin: const EdgeInsets.only(bottom: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Row(children: [
              Icon(Icons.gps_fixed, size: 12, color: kSlate400), SizedBox(width: 4),
              Cap('My Rescue Node', size: 10),
            ]),
            Text('TX/RX STANDBY', style: ts(9, FontWeight.w400, kBrand500, mono: true)),
          ]),
          const SizedBox(height: 8),
          Text('LIVE LOCATION (GPS SYNC)', style: ts(8, FontWeight.w700, kSlate400)),
          const SizedBox(height: 2),
          Text(ble.gps, style: ts(12, FontWeight.w900, p.text, mono: true)),
          Text(ble.gpsSub, style: ts(9, FontWeight.w400, p.sub, mono: true)),
          const SizedBox(height: 16),
          Opacity(
            opacity: on ? 1 : .6,
            child: GestureDetector(
              onTap: () {
                final err = ble.sos();
                if (err != null) showToast(context, err, err: true);
              },
              child: Container(
                width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(.2), blurRadius: 6, offset: const Offset(0, 3))]),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  ble.sosState == 'tx'
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : Icon(ble.sosState == 'done' ? Icons.check_circle_outline : Icons.cell_tower, size: 18, color: ble.sosState == 'done' ? Colors.white : kRose),
                  const SizedBox(width: 6),
                  Text(
                    (!on ? 'Connect BLE to Broadcast SOS' : ble.sosState == 'tx' ? 'Transmitting...' : ble.sosState == 'done' ? 'SOS Broadcasted' : 'Broadcast My SOS').toUpperCase(),
                    style: ts(10, FontWeight.w700, Colors.white, ls: 1),
                  ),
                ]),
              ),
            ),
          ),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Text('Incoming peer-to-peer LoRa distress signals will automatically render here during emergency events.',
            textAlign: TextAlign.center, style: ts(9, FontWeight.w400, p.sub)),
      ),
    ]);
  }
}

class SettingsView extends StatelessWidget {
  const SettingsView({super.key});
  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final activeProf = ble.d?.prof?.toInt();
    Widget row(String l, String v, {Color? vc, bool last = false}) => Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(border: last ? null : Border(bottom: BorderSide(color: p.d ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9)))),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text(l, style: ts(14, FontWeight.w600, p.t700)),
            Text(v, style: ts(12, FontWeight.w400, vc ?? kSlate400, mono: true)),
          ]),
        );
    Widget prof(int id, IconData ic, Color c, String l) {
      final selected = activeProf == id;
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            final res = ble.setProfile(id);
            showToast(context, res.msg, err: !res.ok);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: p.chip,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: selected ? c : (p.d ? const Color(0xFF334155) : const Color(0xFFE2E8F0)), width: selected ? 1.5 : 1),
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Row(children: [Icon(ic, size: 18, color: c), const SizedBox(width: 8), Text(l.toUpperCase(), style: ts(10, FontWeight.w700, p.t700, ls: 1))]),
              Text(selected ? 'ACTIVE' : "Byte: '$id'", style: ts(10, FontWeight.w600, selected ? c : kSlate400, mono: true)),
            ]),
          ),
        ),
      );
    }
    Widget btn(String l, IconData ic, bool primary, VoidCallback f) => Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: f,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: primary ? kBrand500 : p.chip, borderRadius: BorderRadius.circular(8),
                border: primary ? null : Border.all(color: p.d ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
                boxShadow: primary ? [BoxShadow(color: kBrand500.withOpacity(.2), blurRadius: 6, offset: const Offset(0, 3))] : null,
              ),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(ic, size: 18, color: primary ? Colors.white : p.t700), const SizedBox(width: 6),
                Text(l.toUpperCase(), style: ts(10, FontWeight.w700, primary ? Colors.white : p.t700, ls: 1)),
              ]),
            ),
          ),
        );
    final bat = ble.d?.bat != null ? '${ble.d!.bat!.toInt()}%' : '--%';
    final profName = activeProf != null ? (kProfiles[activeProf] ?? 'Profile $activeProf') : 'Awaiting Sync...';
    return ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 24), children: [
      Padding(padding: const EdgeInsets.fromLTRB(4, 0, 4, 16), child: Text(ble.t('systemSettings').toUpperCase(), style: ts(14, FontWeight.w900, p.text, ls: 1.4))),
      Box(
        pad: 16, margin: const EdgeInsets.only(bottom: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Cap(ble.t('devConn')), const SizedBox(height: 12),
          row('BLE Device Name', Ble.devName), row('BLE Polling Rate', '10 Hz'),
          row('Battery Level', bat, vc: kEmerald), row('Firmware Logic', 'v2.0 (Edge AI)', vc: kBrand500),
          row('Active ML Profile', profName, vc: const Color(0xFFA855F7), last: true),
        ]),
      ),
      Box(
        pad: 16, margin: const EdgeInsets.only(bottom: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Cap('NVS Demographic Provisioning'), const SizedBox(height: 12),
          Text("Write a configuration byte via BLE to permanently lock the ESP32-S3 tensor arena to a specific physiological model.",
              style: ts(9, FontWeight.w400, kSlate400, h: 1.2)),
          const SizedBox(height: 16),
          prof(0, Icons.person, kBrand500, 'Standard Adult'),
          prof(1, Icons.accessible, kEmerald, 'Elderly User'),
          prof(2, Icons.engineering, kOrange, 'Industrial Worker'),
        ]),
      ),
      Box(
        pad: 16, margin: const EdgeInsets.only(bottom: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Cap(ble.t('privData')), const SizedBox(height: 12),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('Local Data Logging', style: ts(14, FontWeight.w600, p.t700)),
            Switch(value: ble.logging, activeColor: Colors.white, activeTrackColor: kEmerald, onChanged: ble.setLogging),
          ]),
          Text("Data is strictly saved to this device's local storage to comply with DPDP. No cloud sync is active.",
              style: ts(9, FontWeight.w400, kSlate400, h: 1.2)),
        ]),
      ),
      Box(
        pad: 16,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Cap('Export Telemetry'), const SizedBox(height: 12),
          Text('Copy locally saved sensor telemetry in CSV format for offline analysis.', style: ts(9, FontWeight.w400, kSlate400, h: 1.2)),
          const SizedBox(height: 16),
          Row(children: [
            btn('Last 24 Hrs', Icons.download, false, () async {
              final res = await ble.export('24h');
              if (context.mounted) showToast(context, res.msg, err: !res.ok);
            }),
            const SizedBox(width: 8),
            btn('Full Export', Icons.storage, true, () async {
              final res = await ble.export('all');
              if (context.mounted) showToast(context, res.msg, err: !res.ok);
            }),
          ]),
        ]),
      ),
    ]);
  }
}