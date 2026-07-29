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

  testWidgets('home network count opens the networks list', (tester) async {
    await tester.pumpWidget(const LanMapperApp());
    await tester.pumpAndSettle();

    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      0,
    );
    await tester.tap(find.text('NETWORKS'));
    await tester.pumpAndSettle();

    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      2,
    );
    expect(find.text('No networks saved yet.'), findsOneWidget);
  });

  testWidgets(
    'nearby access point double-tap opens the Android connection handoff',
    (tester) async {
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(statusChannel, (call) async {
            calls.add(call);
            return switch (call.method) {
              'requestPermissions' => <String, dynamic>{},
              'getNearbyAccessPoints' => <Map<String, dynamic>>[
                {
                  'ssid': 'Lab WiFi',
                  'bssid': 'AA:BB:CC:DD:EE:FF',
                  'level': -48,
                  'frequency': 5180,
                  'channel': 36,
                  'security': 'WPA2-PSK',
                },
              ],
              'connectToAccessPoint' => <String, dynamic>{
                'status': 'settings_opened',
                'confirmationRequired': true,
                'message':
                    'Android Wi-Fi controls opened. Select Lab WiFi and confirm to connect.',
              },
              _ => null,
            };
          });

      await tester.pumpWidget(
        const MaterialApp(
          home: NearbyAccessPointsPage(androidPlatformOverride: true),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Lab WiFi'), findsOneWidget);
      expect(find.byTooltip('Connect to Lab WiFi'), findsOneWidget);

      await tester.tap(find.text('Lab WiFi'));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.text('Lab WiFi'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final connectCall = calls.singleWhere(
        (call) => call.method == 'connectToAccessPoint',
      );
      expect(connectCall.arguments, {
        'ssid': 'Lab WiFi',
        'bssid': 'AA:BB:CC:DD:EE:FF',
      });
      expect(
        find.text(
          'Android Wi-Fi controls opened. Select Lab WiFi and confirm to connect.',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets('secret navigation sequence opens notes and close resets it', (
    tester,
  ) async {
    await tester.pumpWidget(const LanMapperApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Home'));
    await tester.tap(find.text('Networks'));
    await tester.tap(find.text('Networks'));
    await tester.tap(find.text('Tools'));
    await tester.tap(find.text('Tools'));
    await tester.tap(find.text('Tools'));
    await tester.pumpAndSettle();

    expect(find.text('Private files'), findsOneWidget);
    expect(find.text('NEW NOTE'), findsNothing);
    expect(find.byType(NavigationBar), findsNothing);

    await tester.longPress(
      find.text('This folder is empty. Hold here to add something.'),
    );
    await tester.pumpAndSettle();
    expect(find.text('New note'), findsOneWidget);
    expect(find.text('New folder'), findsOneWidget);
    expect(find.text('Add images'), findsOneWidget);
    expect(find.text('Take photo'), findsOneWidget);
    await tester.tap(find.text('New note'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Title *'),
      'Private reminder',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Note'),
      'Remember this text.',
    );
    await tester.tap(find.text('SAVE'));
    await tester.pumpAndSettle();
    expect(find.text('Private reminder'), findsOneWidget);

    await tester.tap(find.text('Private reminder'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Edit note'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is SelectableText && widget.data == 'Remember this text.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.byTooltip('Close viewer'));
    await tester.pumpAndSettle();

    await tester.longPressAt(const Offset(700, 450));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New folder'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Folder name *'),
      'Pictures',
    );
    await tester.tap(find.text('CREATE'));
    await tester.pumpAndSettle();
    expect(find.text('Pictures'), findsOneWidget);

    await tester.longPress(find.text('Pictures'));
    await tester.pump();
    expect(find.text('1 selected'), findsOneWidget);
    await tester.tap(find.text('Private reminder'));
    await tester.pump();
    expect(find.text('2 selected'), findsOneWidget);
    expect(find.byTooltip('Move selected'), findsOneWidget);
    expect(find.byTooltip('Delete selected'), findsOneWidget);
    await tester.tap(find.byTooltip('Cancel selection'));
    await tester.pump();

    await tester.tap(find.text('Pictures'));
    await tester.pumpAndSettle();
    expect(find.text('Pictures'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Private files'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      0,
    );

    await tester.tap(find.text('Tools'));
    await tester.pumpAndSettle();
    expect(find.text('NEW NOTE'), findsNothing);
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

  test('neighbor MAC parser supports Linux, macOS, and Windows output', () {
    final parsed = parseNeighborMacs('''
192.168.1.1 dev wlan0 lladdr aa:bb:cc:dd:ee:01 REACHABLE
? (192.168.1.20) at AA:BB:CC:DD:EE:20 on en0 ifscope
  192.168.1.30          11-22-33-44-55-66     dynamic
192.168.1.40 dev wlan0 INCOMPLETE
192.168.1.50 dev wlan0 lladdr 00:00:00:00:00:00 STALE
192.168.1.60 dev wlan0 lladdr ff:ff:ff:ff:ff:ff STALE
''');

    expect(parsed, {
      '192.168.1.1': 'AA:BB:CC:DD:EE:01',
      '192.168.1.20': 'AA:BB:CC:DD:EE:20',
      '192.168.1.30': '11:22:33:44:55:66',
    });
  });

  test('port observations retain the previously discovered identity', () {
    final merged = mergePortScanObservation(
      const ScannedHost('192.168.1.20', '192.168.1.20', [22, 443]),
      previous: const ScannedHost('192.168.1.20', 'printer.local', [
        80,
      ], mac: 'AA:BB:CC:DD:EE:FF'),
    );

    expect(merged.hostname, 'printer.local');
    expect(merged.mac, 'AA:BB:CC:DD:EE:FF');
    expect(merged.ports, [22, 443]);
  });

  test('partial port observations preserve ports that were not checked', () {
    final saved = DeviceRecord(
      ip: '192.168.1.20',
      name: 'Printer',
      ports: [22, 80, 443],
    );

    final opened = mergePortScanObservation(
      const ScannedHost(
        '192.168.1.20',
        '192.168.1.20',
        [5555],
        checkedPorts: [5555],
      ),
      saved: saved,
    );
    final closed = mergePortScanObservation(
      const ScannedHost('192.168.1.20', '192.168.1.20', [], checkedPorts: [80]),
      previous: opened,
      saved: saved,
    );

    expect(opened.ports, [22, 80, 443, 5555]);
    expect(opened.checkedPorts, [5555]);
    expect(closed.ports, [22, 443, 5555]);
    expect(closed.checkedPorts, [80, 5555]);
  });

  test(
    'partial port observations preserve saved ports newer than prior results',
    () {
      final merged = mergePortScanObservation(
        const ScannedHost(
          '192.168.1.20',
          '192.168.1.20',
          [22],
          checkedPorts: [22],
        ),
        previous: const ScannedHost(
          '192.168.1.20',
          'printer.local',
          [80],
          checkedPorts: [80],
        ),
        saved: DeviceRecord(
          ip: '192.168.1.20',
          name: 'Printer',
          ports: [80, 443],
        ),
      );

      expect(merged.ports, [22, 80, 443]);
      expect(merged.checkedPorts, [22, 80]);
    },
  );

  test('newly observed open ports are added without removing saved ports', () {
    final originalLastSeen = DateTime.utc(2026, 1, 1);
    final observedAt = DateTime.utc(2026, 2, 2);
    final device = DeviceRecord(
      ip: '192.168.1.20',
      ports: [80, 443],
      lastSeen: originalLastSeen,
    );

    final changed = addObservedOpenPorts(
      device,
      const ScannedHost(
        '192.168.1.20',
        '192.168.1.20',
        [443, 5555],
        checkedPorts: [443, 5555],
      ),
      observedAt: observedAt,
    );
    final unchanged = addObservedOpenPorts(
      device,
      const ScannedHost(
        '192.168.1.20',
        '192.168.1.20',
        [5555],
        checkedPorts: [5555],
      ),
      observedAt: DateTime.utc(2026, 3, 3),
    );

    expect(changed, isTrue);
    expect(unchanged, isFalse);
    expect(device.ports, [80, 443, 5555]);
    expect(device.lastSeen, observedAt);
  });

  test('port scan summaries emphasize positive hosts', () {
    expect(
      formatPortScanSummary(
        addressesChecked: 254,
        checkedPorts: const [5555],
        hostsWithOpenPorts: 3,
      ),
      'TCP 5555 open on 3 of 254 addresses checked.',
    );
    expect(
      formatPortScanSummary(
        addressesChecked: 1,
        checkedPorts: const [80, 443],
        hostsWithOpenPorts: 1,
      ),
      '1 of 1 address had at least one selected TCP port open.',
    );
  });

  test('DNS lookup failures distinguish missing reverse DNS', () {
    expect(
      dnsLookupFailureMessage('192.168.4.30'),
      contains('No reverse DNS hostname was found for 192.168.4.30'),
    );
    expect(
      dnsLookupFailureMessage('missing-device.local'),
      contains('Could not resolve “missing-device.local”'),
    );
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

  test('refreshing known ports replaces rather than discovers ports', () {
    final inventory = LiveInventory()
      ..observePorts('192.168.1.25', [22, 80, 443]);

    inventory.replacePorts('192.168.1.25', [22, 443]);

    expect(inventory.forIp('192.168.1.25')!.ports, [22, 443]);
  });

  testWidgets('same IP discovered elsewhere does not affect a saved LAN', (
    tester,
  ) async {
    final network = NetworkMap(
      id: 'lan-a',
      name: 'LAN A',
      devices: [
        DeviceRecord(ip: '192.168.1.25', name: 'LAN A camera', ports: [80]),
      ],
    );
    final inventory = LiveInventory()
      ..observeHost(
        const ScannedHost('192.168.1.25', 'LAN-B-printer', [443, 9100]),
      );

    await tester.pumpWidget(
      MaterialApp(
        home: NetworkWorkspace(
          network: network,
          liveInventory: inventory,
          onChanged: () async {},
        ),
      ),
    );

    final tile = tester.widget<DeviceTile>(find.byType(DeviceTile));
    expect(tile.status, DeviceStatus.saved);
    expect(network.devices.single.name, 'LAN A camera');
    expect(network.devices.single.ports, [80]);
  });

  testWidgets(
    'swiping right checks an inactive device without reviving an unreachable host',
    (tester) async {
      final originalLastSeen = DateTime.utc(2026, 1, 2, 3, 4, 5);
      final device = DeviceRecord(
        ip: '192.168.1.25',
        name: 'Offline camera',
        ports: [80, 443],
        isDead: true,
        lastSeen: originalLastSeen,
      );
      String? checkedIp;
      List<int>? checkedPorts;
      var saveCalls = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: NetworkWorkspace(
            network: NetworkMap(id: 'lan-a', name: 'LAN A', devices: [device]),
            liveInventory: LiveInventory(),
            onChanged: () async => saveCalls++,
            deviceChecker: (ip, listedPorts) async {
              checkedIp = ip;
              checkedPorts = List.of(listedPorts);
              return DeviceCheckResult(
                ip: ip,
                reachable: false,
                openPorts: const [],
                checkedPorts: List.of(listedPorts),
              );
            },
          ),
        ),
      );

      expect(
        tester.widget<DeviceTile>(find.byType(DeviceTile)).status,
        DeviceStatus.dead,
      );
      expect(find.text('Red — marked inactive'), findsOneWidget);

      await tester.drag(find.byType(DeviceTile), const Offset(500, 0));
      await tester.pumpAndSettle();

      expect(checkedIp, device.ip);
      expect(checkedPorts, [80, 443]);
      expect(device.isDead, isTrue);
      expect(device.lastSeen, originalLastSeen);
      expect(saveCalls, 0);
      expect(
        tester.widget<DeviceTile>(find.byType(DeviceTile)).status,
        DeviceStatus.dead,
      );
      expect(find.text('Red — marked inactive'), findsOneWidget);
    },
  );

  testWidgets(
    'saved device popup checks alive, adds reachable ports, and persists',
    (tester) async {
      final originalLastSeen = DateTime.utc(2026, 1, 2, 3, 4, 5);
      final device = DeviceRecord(
        ip: '192.168.1.25',
        name: 'Inactive camera',
        ports: [80, 443],
        isDead: true,
        lastSeen: originalLastSeen,
      );
      String? checkedIp;
      List<int>? checkedPorts;
      var saveCalls = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: NetworkWorkspace(
            network: NetworkMap(id: 'lan-a', name: 'LAN A', devices: [device]),
            liveInventory: LiveInventory(),
            onChanged: () async => saveCalls++,
            deviceChecker: (ip, listedPorts) async {
              checkedIp = ip;
              checkedPorts = List.of(listedPorts);
              return DeviceCheckResult(
                ip: ip,
                reachable: true,
                openPorts: const [80, 443, 8080],
                checkedPorts: const [80, 443, 8080],
              );
            },
          ),
        ),
      );

      await tester.tap(find.text('Inactive camera'));
      await tester.pumpAndSettle();

      expect(find.text('REFRESH LISTED PORTS / CHECK ALIVE'), findsOneWidget);
      await tester.tap(find.text('REFRESH LISTED PORTS / CHECK ALIVE'));
      await tester.pumpAndSettle();

      expect(checkedIp, device.ip);
      expect(checkedPorts, [80, 443]);
      expect(device.isDead, isFalse);
      expect(device.ports, [80, 443, 8080]);
      expect(device.lastSeen.isAfter(originalLastSeen), isTrue);
      expect(saveCalls, 1);
      expect(find.textContaining('8080'), findsWidgets);
    },
  );

  testWidgets('global findings feed the shared unsaved LAN list', (
    tester,
  ) async {
    final inventory = LiveInventory();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: QuickLanScanPanel(
            networks: const [],
            liveInventory: inventory,
            currentSsid: 'Test WiFi',
            onOpen: (_) {},
            onChanged: () async {},
          ),
        ),
      ),
    );

    expect(find.byType(DeviceTile), findsNothing);
    inventory.observePorts('192.168.4.30', [80, 443]);
    inventory.observeMac('192.168.4.30', 'AA:BB:CC:DD:EE:FF');
    await tester.pump();

    expect(find.byType(DeviceTile), findsOneWidget);
    expect(find.text('Web-enabled device'), findsOneWidget);
    expect(find.text('192.168.4.30'), findsOneWidget);
    expect(find.text('AA:BB:CC:DD:EE:FF'), findsOneWidget);
    expect(
      find.byTooltip('Refresh listed ports for 192.168.4.30'),
      findsOneWidget,
    );

    await tester.tap(find.text('Web-enabled device'));
    await tester.pumpAndSettle();
    expect(find.text('AA:BB:CC:DD:EE:FF'), findsNWidgets(2));
    expect(find.text('REFRESH LISTED PORTS / CHECK ALIVE'), findsOneWidget);
    expect(find.text('PORT SCANNER'), findsOneWidget);
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();

    await tester.tap(find.text('SAVE AS NEW'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.widgetWithText(TextField, 'Wi-Fi SSID'))
          .controller!
          .text,
      'Test WiFi',
    );
    expect(
      tester
          .widget<TextField>(find.widgetWithText(TextField, 'Network name *'))
          .controller!
          .text,
      'Test WiFi LAN',
    );
    await tester.tap(find.text('CANCEL'));
    await tester.pumpAndSettle();

    inventory.clear();
    await tester.pump();
    expect(find.byType(DeviceTile), findsNothing);
  });

  test('network merge combines matching devices and preserves originals', () {
    final first = NetworkMap(
      id: 'first',
      name: 'Office',
      devices: [
        DeviceRecord(
          ip: '192.168.1.20',
          mac: 'AA:BB:CC:DD:EE:FF',
          name: 'Printer',
          ports: [80],
        ),
      ],
    );
    final second = NetworkMap(
      id: 'second',
      name: 'Office WiFi',
      devices: [
        DeviceRecord(
          ip: '192.168.1.99',
          mac: 'AA:BB:CC:DD:EE:FF',
          ports: [443, 9100],
        ),
        DeviceRecord(
          ip: '192.168.1.20',
          mac: '11:22:33:44:55:66',
          name: 'Different device',
          ports: [22],
        ),
      ],
    );

    final merged = mergeNetworks(first, second);

    expect(merged.devices, hasLength(2));
    expect(
      merged.devices
          .firstWhere((device) => device.mac == 'AA:BB:CC:DD:EE:FF')
          .ports,
      [80, 443, 9100],
    );
    expect(first.devices.single.ports, [80]);
    expect(second.devices, hasLength(2));
  });

  test(
    'network merge backfills a same-IP device MAC without duplicating it',
    () {
      final target = NetworkMap(
        id: 'home',
        name: 'Home',
        devices: [DeviceRecord(ip: '192.168.1.20', name: 'Printer')],
      );

      mergeDevicesInto(target, [
        DeviceRecord(
          ip: '192.168.1.20',
          mac: 'aa-bb-cc-dd-ee-ff',
          ports: [80, 9100],
        ),
      ]);

      expect(target.devices, hasLength(1));
      expect(target.devices.single.mac, 'AA:BB:CC:DD:EE:FF');
      expect(target.devices.single.ports, [80, 9100]);
    },
  );

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
    expect(
      find.textContaining('${discoveryPorts.length} common ports selected'),
      findsOneWidget,
    );
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

  testWidgets('port results show numbers and retire the copy tip', (
    tester,
  ) async {
    const copyTip =
        'Tip: Hold the port list to copy all ports, or hold one port to copy it.';
    String? clipboardText;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        clipboardText =
            (call.arguments as Map<dynamic, dynamic>)['text'] as String?;
      }
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: PortScanResults(
            results: {
              '192.168.1.10': [22, 80, 443],
              '192.168.1.11': [],
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(copyTip), findsOneWidget);
    expect(find.text('22, 80, 443'), findsOneWidget);
    expect(find.text('3 open ports · Hold to copy all'), findsNothing);
    expect(find.text('192.168.1.11'), findsNothing);

    await tester.longPress(find.text('22, 80, 443'));
    await tester.pumpAndSettle();
    expect(clipboardText, '22, 80, 443');
    expect(find.text('Copied all 3 open ports'), findsOneWidget);
    expect(find.text(copyTip), findsNothing);
    expect(
      (await SharedPreferences.getInstance()).getBool(
        portScanCopyTipPreferenceKey,
      ),
      isTrue,
    );

    await tester.tap(find.text('192.168.1.10'));
    await tester.pumpAndSettle();
    expect(find.text('SSH'), findsNothing);
    expect(find.text('HTTP'), findsNothing);
    await tester.longPress(find.text('80'));
    await tester.pumpAndSettle();
    expect(clipboardText, '80');
    expect(find.text('Copied port 80'), findsOneWidget);

    await tester.pumpWidget(
      MaterialApp(
        key: UniqueKey(),
        home: const Scaffold(
          body: PortScanResults(
            results: {
              '192.168.1.10': [22, 80, 443],
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text(copyTip), findsNothing);
  });

  testWidgets('device card long presses copy IP or all information', (
    tester,
  ) async {
    String? clipboardText;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        clipboardText =
            (call.arguments as Map<dynamic, dynamic>)['text'] as String?;
      }
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DeviceTile(
            device: DeviceRecord(
              ip: '192.168.4.30',
              mac: 'AA:BB:CC:DD:EE:FF',
              name: 'Printer',
              product: 'Likely printer',
              ports: [80, 9100],
            ),
            status: DeviceStatus.active,
            onTap: () {},
            onTools: () {},
          ),
        ),
      ),
    );

    await tester.longPress(find.text('192.168.4.30'));
    await tester.pump();
    expect(clipboardText, '192.168.4.30');

    await tester.longPress(find.text('Printer'));
    await tester.pump();
    expect(clipboardText, contains('MAC: AA:BB:CC:DD:EE:FF'));
    expect(clipboardText, contains('Ports: 80, 9100'));
  });

  testWidgets('saved ports show still-open, new, and closed states', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: PortStatusReview(saved: [22, 80, 445], latest: [22, 443, 445]),
        ),
      ),
    );

    expect(find.text('STILL OPEN'), findsOneWidget);
    expect(find.text('NEW · NOT SAVED'), findsOneWidget);
    expect(find.text('NO LONGER OPEN · STILL SAVED'), findsOneWidget);
    expect(find.text('22'), findsOneWidget);
    expect(find.text('445'), findsOneWidget);
    expect(find.text('443'), findsOneWidget);
    expect(find.text('80'), findsOneWidget);
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

  testWidgets(
    'saved device rename closes without using a disposed controller',
    (tester) async {
      final device = DeviceRecord(ip: '192.168.1.10', name: 'Old name');
      var saveCalls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: NetworkWorkspace(
            network: NetworkMap(
              id: 'home',
              name: 'Home LAN',
              devices: [device],
            ),
            liveInventory: LiveInventory(),
            onChanged: () async => saveCalls++,
          ),
        ),
      );

      await tester.tap(find.text('Old name'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Old name').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Device name'),
        'New name',
      );
      await tester.tap(find.text('SAVE'));
      await tester.pumpAndSettle();

      expect(device.name, 'New name');
      expect(saveCalls, 1);
      expect(find.text('New name'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('a discovered MAC is visible and can be saved explicitly', (
    tester,
  ) async {
    final device = DeviceRecord(ip: '192.168.1.20', name: 'Printer');
    var applied = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showDevice(
                context,
                device,
                fresh: const ScannedHost('192.168.1.20', 'printer.local', [
                  80,
                  9100,
                ], mac: 'AA:BB:CC:DD:EE:FF'),
                onApplyMac: () {
                  device.mac = 'AA:BB:CC:DD:EE:FF';
                  applied = true;
                },
                onScanAllPorts: () {},
              ),
              child: const Text('OPEN DEVICE'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('OPEN DEVICE'));
    await tester.pumpAndSettle();

    expect(find.text('Not documented'), findsOneWidget);
    expect(
      find.textContaining('DISCOVERED MAC\nAA:BB:CC:DD:EE:FF'),
      findsOneWidget,
    );
    expect(find.text('SAVE DISCOVERED MAC'), findsOneWidget);

    await tester.tap(find.text('SAVE DISCOVERED MAC'));
    await tester.pumpAndSettle();
    expect(applied, isTrue);
    expect(device.mac, 'AA:BB:CC:DD:EE:FF');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'device details can hand off to rename without lifecycle errors',
    (tester) async {
      final device = DeviceRecord(ip: '192.168.1.10', name: 'Old name');
      var scannedAllPorts = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showDevice(
                  context,
                  device,
                  onRename: () {
                    showDialog<void>(
                      context: context,
                      builder: (dialogContext) => AlertDialog(
                        title: const Text('Name this device'),
                        actions: [
                          FilledButton(
                            onPressed: () => Navigator.pop(dialogContext),
                            child: const Text('SAVE'),
                          ),
                        ],
                      ),
                    );
                  },
                  onEdit: () {},
                  onScanAllPorts: () => scannedAllPorts = true,
                  onDelete: () {},
                ),
                child: const Text('192.168.1.10'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('192.168.1.10'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Old name'));
      await tester.pumpAndSettle();

      expect(find.text('Name this device'), findsOneWidget);
      await tester.tap(find.text('SAVE'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('192.168.1.10'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('PORT SCANNER'));
      await tester.pumpAndSettle();
      expect(scannedAllPorts, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('saved-network hostname findings require approval', (
    tester,
  ) async {
    var approved = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showDevice(
                context,
                DeviceRecord(ip: '192.168.1.30', name: 'Camera'),
                fresh: const ScannedHost('192.168.1.30', 'camera.local', []),
                onScanAllPorts: () {},
                onApplyHostname: () => approved = true,
              ),
              child: const Text('OPEN DEVICE'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('OPEN DEVICE'));
    await tester.pumpAndSettle();
    expect(find.textContaining('camera.local'), findsOneWidget);
    await tester.tap(find.text('USE DISCOVERED HOSTNAME'));
    await tester.pumpAndSettle();
    expect(approved, isTrue);
  });

  testWidgets(
    'saved network can be long-pressed and deleted after confirmation',
    (tester) async {
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

      await tester.longPress(find.text('Home LAN'));
      await tester.pumpAndSettle();
      expect(find.text('Delete saved network?'), findsOneWidget);
      await tester.tap(find.text('DELETE'));
      await tester.pumpAndSettle();

      expect(networks, isEmpty);
      expect(saved, isTrue);
      expect(find.text('No networks saved yet.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('import notes can merge devices into a saved network', (
    tester,
  ) async {
    final networks = [
      NetworkMap(
        id: 'home',
        name: 'Home LAN',
        devices: [
          DeviceRecord(
            ip: '192.168.1.20',
            mac: 'AA:BB:CC:DD:EE:FF',
            name: 'Office PC',
            ports: [22],
          ),
        ],
      ),
    ];
    var saved = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NetworksPage(
            networks: networks,
            liveInventory: LiveInventory(),
            currentSsid: 'Home WiFi',
            onOpen: (_) {},
            onCreate: () {},
            onChanged: () async => saved = true,
          ),
        ),
      ),
    );

    await tester.tap(find.text('IMPORT NOTES'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField).last,
      'Office PC 192.168.1.20 AA:BB:CC:DD:EE:FF ports 22,445',
    );
    await tester.tap(find.text('IMPORT DEVICES'));
    await tester.pumpAndSettle();
    expect(find.text('Where should these devices go?'), findsOneWidget);
    await tester.tap(find.text('ADD TO SAVED'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Home LAN').last);
    await tester.pumpAndSettle();

    expect(networks.single.devices.single.ports, [22, 445]);
    expect(networks.single.notes, contains('Imported scan notes'));
    expect(saved, isTrue);
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
