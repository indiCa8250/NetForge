import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netforge/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const statusChannel = MethodChannel('netforge/device_status');

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          statusChannel,
          (_) async => <String, dynamic>{
            'ssid': 'Test WiFi',
            'gateway': '192.168.1.1',
            'bssid': 'AA:BB:CC:DD:EE:FF',
            'permissionsRequired': false,
          },
        );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(statusChannel, null);
  });

  testWidgets('opens directly into the LAN mapping workflow', (tester) async {
    await tester.pumpWidget(const LanMapperApp());
    await tester.pumpAndSettle();

    expect(find.text('LAN MAPPER'), findsOneWidget);
    expect(find.text('Your networks, remembered.'), findsOneWidget);
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Networks'), findsOneWidget);
    expect(find.text('Tools'), findsOneWidget);
    expect(find.text('Test WiFi'), findsOneWidget);
  });

  test('parses pasted scan notes into documented devices', () {
    final devices = parseScanNotes('''
Living Room TV 192.168.1.40 AA:BB:CC:DD:EE:FF ports 80,443
Phone 192.168.1.55 ports: 5555,8080
192.168.1.40 tcp 8080
''');

    expect(devices, hasLength(2));
    final tv = devices.firstWhere((device) => device.ip == '192.168.1.40');
    expect(tv.name, 'Living Room TV');
    expect(tv.mac, 'AA:BB:CC:DD:EE:FF');
    expect(tv.ports, [80, 443, 8080]);
  });

  test('port parser removes duplicates and validates bounds', () {
    expect(parsePorts('443,80,80,8000-8002'), [80, 443, 8000, 8001, 8002]);
    expect(parsePorts('0,65536,nope'), isEmpty);
  });

  test('saved network JSON retains labels, MACs, ports, and notes', () {
    final network = NetworkMap(
      id: 'home',
      name: 'Home LAN',
      ssid: 'My WiFi',
      gateway: '192.168.1.1',
      subnet: '192.168.1.0/24',
      notes: 'Main network',
      devices: [
        DeviceRecord(
          ip: '192.168.1.20',
          mac: 'AA:BB:CC:DD:EE:FF',
          name: 'Office PC',
          product: 'Desktop',
          notes: 'Upstairs',
          ports: [22, 445],
          isDead: true,
        ),
      ],
    );

    final restored = NetworkMap.fromJson(network.toJson());
    expect(restored.name, 'Home LAN');
    expect(restored.devices.single.name, 'Office PC');
    expect(restored.devices.single.mac, 'AA:BB:CC:DD:EE:FF');
    expect(restored.devices.single.ports, [22, 445]);
    expect(restored.devices.single.notes, 'Upstairs');
    expect(restored.devices.single.isDead, isTrue);
  });

  test('readable export contains the complete LAN inventory', () {
    final network = NetworkMap(
      id: 'lab',
      name: 'Lab LAN',
      devices: [
        DeviceRecord(
          ip: '10.0.0.5',
          name: 'Test Phone',
          mac: '11:22:33:44:55:66',
          ports: [5555],
        ),
      ],
    );
    final text = exportNetworkText(network);
    expect(text, contains('LAN MAP: Lab LAN'));
    expect(text, contains('Test Phone — 10.0.0.5'));
    expect(text, contains('11:22:33:44:55:66'));
    expect(text, contains('5555'));
  });

  test('portable NetForge file round-trips the complete network', () {
    final original = NetworkMap(
      id: 'portable-lab',
      name: 'Portable Lab',
      ssid: 'Lab WiFi',
      notes: 'Transfer between Android and Linux',
      devices: [
        DeviceRecord(
          ip: '10.0.0.8',
          name: 'Server',
          mac: 'AA:BB:CC:DD:EE:FF',
          ports: [22, 443],
        ),
      ],
    );

    final file = portableNetworkJson(original);
    final restored = parseNetForgeFile(file);

    expect(restored.id, original.id);
    expect(restored.name, original.name);
    expect(restored.ssid, original.ssid);
    expect(restored.devices.single.name, 'Server');
    expect(restored.devices.single.ports, [22, 443]);
    expect(netForgeFileName(original), 'portable-lab.netforge');
    expect(
      () => parseNetForgeFile('{"network":{}}'),
      throwsA(isA<FormatException>()),
    );
  });

  test('live IP findings merge globally without changing saved networks', () {
    final saved = DeviceRecord(
      ip: '192.168.1.25',
      name: 'Saved camera',
      ports: [80],
    );
    final inventory = LiveInventory();

    inventory.observeHost(
      const ScannedHost('192.168.1.25', 'camera.local', [443, 8080]),
    );
    inventory.observePorts('192.168.1.25', [554]);

    final live = inventory.forIp('192.168.1.25')!;
    expect(live.hostname, 'camera.local');
    expect(live.ports, [443, 554, 8080]);
    expect(saved.name, 'Saved camera');
    expect(saved.ports, [80]);
  });

  test('first LAN scan automatically saves every discovered IP', () {
    final network = NetworkMap(id: 'new', name: 'New LAN');
    final added = addFirstScanHosts(network, const [
      ScannedHost('192.168.1.5', 'printer.local', [80, 443]),
      ScannedHost('192.168.1.20', '192.168.1.20', [5555]),
    ]);

    expect(added, 2);
    expect(network.devices.map((device) => device.ip), [
      '192.168.1.5',
      '192.168.1.20',
    ]);
    expect(network.devices.first.name, 'printer.local');
    expect(network.devices.first.ports, [80, 443]);

    expect(
      addFirstScanHosts(network, const [
        ScannedHost('192.168.1.30', 'new.local', [22]),
      ]),
      0,
    );
    expect(network.devices, hasLength(2));
  });

  test('GitHub release parser finds APK and compares versions', () {
    final release = NetForgeRelease.fromJson({
      'tag_name': 'v1.2.0',
      'name': 'NetForge 1.2.0',
      'body': 'New tools',
      'html_url': 'https://github.com/indiCa8250/NetForge/releases/tag/v1.2.0',
      'assets': [
        {
          'name': 'netforge.apk',
          'browser_download_url':
              'https://github.com/indiCa8250/NetForge/releases/download/v1.2.0/netforge.apk',
        },
        {
          'name': 'netforge-linux.AppImage',
          'browser_download_url':
              'https://github.com/indiCa8250/NetForge/releases/download/v1.2.0/netforge-linux.AppImage',
        },
      ],
    });

    expect(release.version, '1.2.0');
    expect(release.apkUrl, endsWith('/netforge.apk'));
    expect(release.linuxUrl, endsWith('/netforge-linux.AppImage'));
    expect(isNewerVersion(release.version, '1.1.9'), isTrue);
    expect(isNewerVersion(release.version, '1.2.0'), isFalse);
    expect(isNewerVersion('1.1.9', release.version), isFalse);
  });

  testWidgets('port scanner uses LAN and discovered IP dropdown', (
    tester,
  ) async {
    final inventory = LiveInventory()
      ..observePorts('192.168.1.20', [80])
      ..observePorts('192.168.1.5', [443]);

    await tester.pumpWidget(
      MaterialApp(home: SimplePortScanner(liveInventory: inventory)),
    );

    expect(find.text('IP'), findsOneWidget);
    expect(find.text('Scan LAN'), findsOneWidget);
    expect(find.text('Single port'), findsOneWidget);
    expect(find.text('Common ports'), findsOneWidget);
    expect(find.text('All ports'), findsOneWidget);
    expect(find.text('Targets'), findsNothing);

    await tester.tap(find.text('Single port'));
    await tester.pumpAndSettle();
    final portField = tester.widget<TextField>(find.byType(TextField));
    expect(portField.controller!.text, isEmpty);

    await tester.tap(find.text('Scan LAN'));
    await tester.pumpAndSettle();
    expect(find.text('192.168.1.5'), findsOneWidget);
    expect(find.text('192.168.1.20'), findsOneWidget);
  });

  testWidgets('can create and label a network without framework errors', (
    tester,
  ) async {
    await tester.pumpWidget(const LanMapperApp());
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('CREATE FIRST NETWORK'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('CREATE FIRST NETWORK'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Network name *'),
      'My Home LAN',
    );
    await tester.tap(find.text('SAVE'));
    await tester.pumpAndSettle();

    expect(find.text('My Home LAN'), findsOneWidget);
    expect(find.text('REFRESH THIS LAN'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('can edit and save a network without lifecycle errors', (
    tester,
  ) async {
    await tester.pumpWidget(const LanMapperApp());
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('CREATE FIRST NETWORK'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('CREATE FIRST NETWORK'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Network name *'),
      'Original LAN',
    );
    await tester.tap(find.text('SAVE'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Edit network'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Network name *'),
      'Edited LAN',
    );
    await tester.tap(find.text('SAVE'));
    await tester.pumpAndSettle();

    expect(find.text('Edited LAN'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('saved network can be deleted after confirmation', (
    tester,
  ) async {
    final networks = [NetworkMap(id: 'home', name: 'Home LAN')];
    var saved = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SavedNetworksList(
            networks: networks,
            onOpen: (_) {},
            onChanged: () async => saved = true,
          ),
        ),
      ),
    );

    await tester.drag(find.text('Home LAN'), const Offset(-500, 0));
    await tester.pumpAndSettle();
    expect(find.text('Delete saved network?'), findsOneWidget);
    await tester.tap(find.text('DELETE'));
    await tester.pumpAndSettle();

    expect(networks, isEmpty);
    expect(saved, isTrue);
    expect(find.text('No networks saved yet.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('import notes closes cleanly and creates a network', (
    tester,
  ) async {
    await tester.pumpWidget(const LanMapperApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Networks'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('IMPORT NOTES'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField).last,
      'Office PC 192.168.1.20 AA:BB:CC:DD:EE:FF ports 22,445',
    );
    await tester.tap(find.text('IMPORT DEVICES'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Network name *'),
      'Imported Home',
    );
    await tester.tap(find.text('SAVE'));
    await tester.pumpAndSettle();

    expect(find.text('Imported Home'), findsOneWidget);
    expect(find.text('Office PC'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
