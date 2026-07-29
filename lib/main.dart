import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() => runApp(const LanMapperApp());

const background = Color(0xFF071019);
const surface = Color(0xFF101C28);
const border = Color(0xFF223243);
const accent = Color(0xFF7EE787);
const secondary = Color(0xFF91A4B7);
const danger = Color(0xFFFF6B75);
const warning = Color(0xFFFFC857);

int compareIpv4(String left, String right) {
  final leftParts = left.split('.').map(int.tryParse).toList();
  final rightParts = right.split('.').map(int.tryParse).toList();
  if (leftParts.length != 4 ||
      rightParts.length != 4 ||
      leftParts.any((part) => part == null) ||
      rightParts.any((part) => part == null)) {
    return left.compareTo(right);
  }
  for (var index = 0; index < 4; index++) {
    final comparison = leftParts[index]!.compareTo(rightParts[index]!);
    if (comparison != 0) return comparison;
  }
  return 0;
}

class LanMapperApp extends StatelessWidget {
  const LanMapperApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'LAN Mapper',
    theme: ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: background,
      colorScheme: const ColorScheme.dark(
        primary: accent,
        surface: surface,
        outline: border,
      ),
      useMaterial3: true,
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF0A1520),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: border),
        ),
      ),
    ),
    home: const MapperShell(),
  );
}

class DeviceRecord {
  DeviceRecord({
    required this.ip,
    this.mac = '',
    this.name = '',
    this.product = '',
    this.notes = '',
    this.isDead = false,
    List<int>? ports,
    DateTime? firstSeen,
    DateTime? lastSeen,
  }) : ports = ports ?? [],
       firstSeen = firstSeen ?? DateTime.now(),
       lastSeen = lastSeen ?? DateTime.now();

  String ip;
  String mac;
  String name;
  String product;
  String notes;
  bool isDead;
  List<int> ports;
  DateTime firstSeen;
  DateTime lastSeen;

  String get title => name.isNotEmpty
      ? name
      : product.isNotEmpty
      ? product
      : ip;

  factory DeviceRecord.fromJson(Map<String, dynamic> json) => DeviceRecord(
    ip: json['ip'] as String,
    mac: json['mac'] as String? ?? '',
    name: json['name'] as String? ?? '',
    product: json['product'] as String? ?? '',
    notes: json['notes'] as String? ?? '',
    isDead: json['isDead'] as bool? ?? false,
    ports: (json['ports'] as List<dynamic>? ?? const []).cast<int>(),
    firstSeen: DateTime.tryParse(json['firstSeen'] as String? ?? ''),
    lastSeen: DateTime.tryParse(json['lastSeen'] as String? ?? ''),
  );

  Map<String, dynamic> toJson() => {
    'ip': ip,
    'mac': mac,
    'name': name,
    'product': product,
    'notes': notes,
    'isDead': isDead,
    'ports': ports,
    'firstSeen': firstSeen.toIso8601String(),
    'lastSeen': lastSeen.toIso8601String(),
  };
}

class NetworkMap {
  NetworkMap({
    required this.id,
    required this.name,
    this.ssid = '',
    this.gateway = '',
    this.subnet = '',
    this.notes = '',
    List<DeviceRecord>? devices,
    List<DeviceRecord>? removedDevices,
    DateTime? updatedAt,
  }) : devices = devices ?? [],
       removedDevices = removedDevices ?? [],
       updatedAt = updatedAt ?? DateTime.now();

  final String id;
  String name;
  String ssid;
  String gateway;
  String subnet;
  String notes;
  List<DeviceRecord> devices;
  List<DeviceRecord> removedDevices;
  DateTime updatedAt;

  factory NetworkMap.fromJson(Map<String, dynamic> json) => NetworkMap(
    id: json['id'] as String,
    name: json['name'] as String,
    ssid: json['ssid'] as String? ?? '',
    gateway: json['gateway'] as String? ?? '',
    subnet: json['subnet'] as String? ?? '',
    notes: json['notes'] as String? ?? '',
    updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? ''),
    devices: (json['devices'] as List<dynamic>? ?? const [])
        .map((item) => DeviceRecord.fromJson(item as Map<String, dynamic>))
        .toList(),
    removedDevices: (json['removedDevices'] as List<dynamic>? ?? const [])
        .map((item) => DeviceRecord.fromJson(item as Map<String, dynamic>))
        .toList(),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'ssid': ssid,
    'gateway': gateway,
    'subnet': subnet,
    'notes': notes,
    'updatedAt': updatedAt.toIso8601String(),
    'devices': devices.map((device) => device.toJson()).toList(),
    'removedDevices': removedDevices.map((device) => device.toJson()).toList(),
  };
}

void mergeDevicesInto(
  NetworkMap target,
  Iterable<DeviceRecord> incomingDevices,
) {
  for (final incoming in incomingDevices) {
    final normalizedMac = normalizeMacAddress(incoming.mac);
    var index = normalizedMac.isEmpty
        ? -1
        : target.devices.indexWhere(
            (existing) => normalizeMacAddress(existing.mac) == normalizedMac,
          );
    if (index < 0) {
      index = target.devices.indexWhere((existing) {
        if (existing.ip != incoming.ip) return false;
        final existingMac = normalizeMacAddress(existing.mac);
        return existingMac.isEmpty || normalizedMac.isEmpty;
      });
    }
    if (index < 0) {
      final copy = DeviceRecord.fromJson(incoming.toJson());
      if (isUsableMacAddress(normalizedMac)) copy.mac = normalizedMac;
      target.devices.add(copy);
      continue;
    }
    final existing = target.devices[index];
    final mergedPorts = {...existing.ports, ...incoming.ports}.toList()..sort();
    existing.ports = mergedPorts;
    if (existing.name.isEmpty) existing.name = incoming.name;
    if (existing.mac.isEmpty && isUsableMacAddress(normalizedMac)) {
      existing.mac = normalizedMac;
    }
    if (existing.product.isEmpty ||
        existing.product == 'Reachable network device') {
      existing.product = incoming.product;
    }
    if (incoming.notes.isNotEmpty && !existing.notes.contains(incoming.notes)) {
      existing.notes = existing.notes.isEmpty
          ? incoming.notes
          : '${existing.notes}\n${incoming.notes}';
    }
    if (incoming.lastSeen.isAfter(existing.lastSeen)) {
      existing.lastSeen = incoming.lastSeen;
    }
    existing.isDead = existing.isDead && incoming.isDead;
  }
}

NetworkMap mergeNetworks(NetworkMap first, NetworkMap second) {
  final merged = NetworkMap(
    id: DateTime.now().microsecondsSinceEpoch.toString(),
    name: '${first.name} + ${second.name}',
    ssid: first.ssid == second.ssid ? first.ssid : '',
    gateway: first.gateway == second.gateway ? first.gateway : '',
    subnet: first.subnet == second.subnet ? first.subnet : '',
    notes: [
      'Merged from “${first.name}” and “${second.name}”.',
      if (first.notes.isNotEmpty) first.notes,
      if (second.notes.isNotEmpty && second.notes != first.notes) second.notes,
    ].join('\n'),
    devices: first.devices
        .map((device) => DeviceRecord.fromJson(device.toJson()))
        .toList(),
    removedDevices: first.removedDevices
        .map((device) => DeviceRecord.fromJson(device.toJson()))
        .toList(),
  );
  mergeDevicesInto(merged, second.devices);
  final removedMap = NetworkMap(
    id: 'removed',
    name: 'removed',
    devices: merged.removedDevices,
  );
  mergeDevicesInto(removedMap, second.removedDevices);
  merged.removedDevices = removedMap.devices;
  return merged;
}

class LiveDevice {
  LiveDevice({
    required this.ip,
    this.hostname = '',
    this.mac = '',
    List<int>? ports,
    DateTime? lastSeen,
  }) : ports = ports ?? [],
       lastSeen = lastSeen ?? DateTime.now();

  final String ip;
  String hostname;
  String mac;
  List<int> ports;
  DateTime lastSeen;
}

class LiveInventory extends ChangeNotifier {
  final Map<String, LiveDevice> _devices = {};

  List<LiveDevice> get devices {
    final values = _devices.values.toList()
      ..sort((a, b) => b.lastSeen.compareTo(a.lastSeen));
    return values;
  }

  LiveDevice? forIp(String ip) => _devices[ip];

  void observeHost(ScannedHost host) {
    final current = _devices.putIfAbsent(
      host.ip,
      () => LiveDevice(ip: host.ip),
    );
    if (host.hostname.isNotEmpty && host.hostname != host.ip) {
      current.hostname = host.hostname;
    }
    if (host.mac.isNotEmpty) current.mac = host.mac;
    final merged = {...current.ports, ...host.ports}.toList()..sort();
    current
      ..ports = merged
      ..lastSeen = DateTime.now();
    notifyListeners();
  }

  void observeHosts(Iterable<ScannedHost> hosts) {
    for (final host in hosts) {
      final current = _devices.putIfAbsent(
        host.ip,
        () => LiveDevice(ip: host.ip),
      );
      if (host.hostname.isNotEmpty && host.hostname != host.ip) {
        current.hostname = host.hostname;
      }
      if (host.mac.isNotEmpty) current.mac = host.mac;
      final merged = {...current.ports, ...host.ports}.toList()..sort();
      current
        ..ports = merged
        ..lastSeen = DateTime.now();
    }
    notifyListeners();
  }

  void observePorts(String ip, Iterable<int> ports) {
    final current = _devices.putIfAbsent(ip, () => LiveDevice(ip: ip));
    final merged = {...current.ports, ...ports}.toList()..sort();
    current
      ..ports = merged
      ..lastSeen = DateTime.now();
    notifyListeners();
  }

  void replacePorts(String ip, Iterable<int> ports) {
    final current = _devices.putIfAbsent(ip, () => LiveDevice(ip: ip));
    final sortedPorts = ports.toSet().toList()..sort();
    current
      ..ports = sortedPorts
      ..lastSeen = DateTime.now();
    notifyListeners();
  }

  void observeHostname(String ip, String hostname) {
    final current = _devices.putIfAbsent(ip, () => LiveDevice(ip: ip));
    current
      ..hostname = hostname
      ..lastSeen = DateTime.now();
    notifyListeners();
  }

  void observeMac(String ip, String mac) {
    final current = _devices.putIfAbsent(ip, () => LiveDevice(ip: ip));
    current
      ..mac = mac
      ..lastSeen = DateTime.now();
    notifyListeners();
  }

  void clear() {
    _devices.clear();
    notifyListeners();
  }
}

class MapperShell extends StatefulWidget {
  const MapperShell({super.key});

  @override
  State<MapperShell> createState() => _MapperShellState();
}

class _MapperShellState extends State<MapperShell> {
  static const statusChannel = MethodChannel('netforge/device_status');
  static const secretSequence = [0, 2, 2, 1, 1, 1];
  final networks = <NetworkMap>[];
  final liveInventory = LiveInventory();
  Map<String, dynamic> connection = {};
  int tab = 0;
  int secretProgress = 0;
  bool secretOpen = false;
  bool loaded = false;
  bool loadingConnection = false;

  @override
  void initState() {
    super.initState();
    load();
    refreshConnection();
  }

  Future<void> refreshConnection() async {
    if (loadingConnection) return;
    setState(() => loadingConnection = true);
    try {
      final native = await statusChannel
          .invokeMapMethod<String, dynamic>('getStatus')
          .timeout(const Duration(seconds: 3));
      final merged = <String, dynamic>{...?native};
      try {
        final info = NetworkInfo();
        final values = await Future.wait([
          info.getWifiName(),
          info.getWifiBSSID(),
          info.getWifiGatewayIP(),
          info.getWifiIP(),
        ]).timeout(const Duration(seconds: 4));
        final ssid = values[0]?.replaceAll('"', '').trim();
        final bssid = values[1]?.trim();
        final gateway = values[2]?.trim();
        final ip = values[3]?.trim();
        if (ssid != null && ssid.isNotEmpty && ssid != '<unknown ssid>') {
          merged['ssid'] = ssid;
        }
        if (bssid != null && bssid.isNotEmpty && bssid != '02:00:00:00:00:00') {
          merged['bssid'] = bssid.toUpperCase();
        }
        if (gateway != null && gateway.isNotEmpty) {
          merged['gateway'] = gateway;
        }
        if (ip != null && ip.isNotEmpty) merged['wifiIp'] = ip;
      } on MissingPluginException {
        // The native fallback above remains available.
      } on PlatformException {
        // Protected values may remain redacted until permission is granted.
      } on TimeoutException {
        // The native fallback above remains available.
      }
      if (mounted) setState(() => connection = merged);
    } on MissingPluginException {
      // Native connection details are currently Android-specific.
    } on PlatformException {
      // Unavailable values remain omitted.
    } on TimeoutException {
      // A platform that does not answer remains usable.
    } finally {
      if (mounted) setState(() => loadingConnection = false);
    }
  }

  Future<void> requestConnectionPermissions() async {
    try {
      if (Platform.isAndroid) {
        await [
          Permission.locationWhenInUse,
          Permission.nearbyWifiDevices,
        ].request();
      } else if (Platform.isIOS) {
        await Permission.locationWhenInUse.request();
      }
      await refreshConnection();
    } on PlatformException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.message ?? 'Permission was not granted.'),
          ),
        );
      }
    } on TimeoutException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('The permission request timed out.')),
        );
      }
    }
  }

  Future<void> openLocationSettings() async {
    try {
      await statusChannel.invokeMethod<void>('openLocationSettings');
    } on PlatformException {
      // The settings shortcut is Android-specific.
    }
  }

  Future<void> load() async {
    final preferences = await SharedPreferences.getInstance();
    try {
      final data =
          jsonDecode(preferences.getString('lanmapper.networks') ?? '[]')
              as List<dynamic>;
      networks.addAll(
        data.map((item) => NetworkMap.fromJson(item as Map<String, dynamic>)),
      );
    } catch (_) {
      // A damaged local file must not prevent the mapper from opening.
    }
    if (mounted) setState(() => loaded = true);
  }

  Future<void> save() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      'lanmapper.networks',
      jsonEncode(networks.map((network) => network.toJson()).toList()),
    );
    if (mounted) setState(() {});
  }

  Future<void> openNetwork(NetworkMap network) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => NetworkWorkspace(
          network: network,
          onChanged: save,
          liveInventory: liveInventory,
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> createNetwork() async {
    final result = await _editNetworkDialog(
      context,
      initialSsid: connection['ssid'] as String? ?? '',
    );
    if (result == null) return;
    final network = NetworkMap(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: result.name,
      ssid: result.ssid,
      gateway: result.gateway,
      subnet: result.subnet,
      notes: result.notes,
    );
    networks.insert(0, network);
    await save();
    if (mounted) await openNetwork(network);
  }

  void selectMainDestination(int value) {
    if (value == secretSequence[secretProgress]) {
      secretProgress++;
      if (secretProgress == secretSequence.length) {
        setState(() {
          secretProgress = 0;
          secretOpen = true;
          tab = 0;
        });
        return;
      }
    } else {
      secretProgress = value == secretSequence.first ? 1 : 0;
    }
    setState(() => tab = value);
  }

  void closeSecretNotes() {
    setState(() {
      secretOpen = false;
      secretProgress = 0;
      tab = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!loaded) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: accent)),
      );
    }
    if (secretOpen) {
      return SecretNotesPage(onClose: closeSecretNotes);
    }
    final pages = [
      HomePage(
        networks: networks,
        liveInventory: liveInventory,
        connection: connection,
        loadingConnection: loadingConnection,
        onRefreshConnection: refreshConnection,
        onRequestPermissions: requestConnectionPermissions,
        onOpenLocationSettings: openLocationSettings,
        onOpen: openNetwork,
        onCreate: createNetwork,
        onGoToNetworks: () => setState(() => tab = 2),
      ),
      MappingToolsPage(
        liveInventory: liveInventory,
        onCreateNetwork: createNetwork,
        onScanSubnet: () => setState(() => tab = 2),
        onReviewPortResults: () => setState(() => tab = 2),
      ),
      NetworksPage(
        networks: networks,
        liveInventory: liveInventory,
        currentSsid: connection['ssid'] as String? ?? '',
        onOpen: openNetwork,
        onCreate: createNetwork,
        onChanged: save,
      ),
    ];
    // Keep one feature set, but give wide screens a desktop-appropriate
    // navigation pattern. This applies naturally to Linux and tablets without
    // creating a second application to maintain.
    return LayoutBuilder(
      builder: (context, constraints) {
        // A 900 px breakpoint keeps the compact layout useful in narrow
        // desktop windows while moving typical Linux desktop windows to the
        // rail navigation.
        final useNavigationRail = constraints.maxWidth >= 900;
        final content = IndexedStack(index: tab, children: pages);
        if (useNavigationRail) {
          return Scaffold(
            body: Row(
              children: [
                NavigationRail(
                  selectedIndex: tab,
                  onDestinationSelected: selectMainDestination,
                  labelType: NavigationRailLabelType.all,
                  destinations: const [
                    NavigationRailDestination(
                      icon: Icon(Icons.home_rounded),
                      label: Text('Home'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.construction_rounded),
                      label: Text('Tools'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.hub_rounded),
                      label: Text('Networks'),
                    ),
                  ],
                ),
                const VerticalDivider(width: 1, color: border),
                Expanded(child: content),
              ],
            ),
          );
        }
        return Scaffold(
          body: content,
          bottomNavigationBar: NavigationBar(
            selectedIndex: tab,
            onDestinationSelected: selectMainDestination,
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.home_rounded),
                label: 'Home',
              ),
              NavigationDestination(
                icon: Icon(Icons.construction_rounded),
                label: 'Tools',
              ),
              NavigationDestination(
                icon: Icon(Icons.hub_rounded),
                label: 'Networks',
              ),
            ],
          ),
        );
      },
    );
  }
}

class SecretNote {
  SecretNote({
    required this.id,
    required this.title,
    required this.body,
    this.kind = 'text',
    this.parentId,
    this.imagePath = '',
    List<String>? attachments,
    DateTime? updatedAt,
  }) : attachments = attachments ?? [],
       updatedAt = updatedAt ?? DateTime.now();

  final String id;
  String title;
  String body;
  String kind;
  String? parentId;
  String imagePath;
  List<String> attachments;
  DateTime updatedAt;

  factory SecretNote.fromJson(Map<String, dynamic> json) => SecretNote(
    id: json['id'] as String,
    title: json['title'] as String? ?? '',
    body: json['body'] as String? ?? '',
    kind: json['kind'] as String? ?? 'text',
    parentId: json['parentId'] as String?,
    imagePath: json['imagePath'] as String? ?? '',
    attachments: (json['attachments'] as List<dynamic>? ?? const [])
        .cast<String>(),
    updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? ''),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'body': body,
    'kind': kind,
    'parentId': parentId,
    'imagePath': imagePath,
    'attachments': attachments,
    'updatedAt': updatedAt.toIso8601String(),
  };
}

class SecretNotesPage extends StatefulWidget {
  const SecretNotesPage({super.key, required this.onClose});

  final VoidCallback onClose;

  @override
  State<SecretNotesPage> createState() => _SecretNotesPageState();
}

class _SecretNotesPageState extends State<SecretNotesPage> {
  static const storageKey = 'netforge.secret_notes';
  final notes = <SecretNote>[];
  bool loaded = false;
  String? currentFolderId;
  String? copiedEntryId;
  final selectedEntryIds = <String>{};

  List<SecretNote> get visibleEntries =>
      notes.where((entry) => entry.parentId == currentFolderId).toList()
        ..sort((a, b) {
          if (a.kind == 'folder' && b.kind != 'folder') return -1;
          if (a.kind != 'folder' && b.kind == 'folder') return 1;
          return b.updatedAt.compareTo(a.updatedAt);
        });

  SecretNote? get currentFolder => currentFolderId == null
      ? null
      : notes.where((entry) => entry.id == currentFolderId).firstOrNull;

  bool get onlyImagesSelected =>
      selectedEntryIds.isNotEmpty &&
      notes
          .where((entry) => selectedEntryIds.contains(entry.id))
          .every((entry) => entry.kind == 'image');

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final preferences = await SharedPreferences.getInstance();
    try {
      final values =
          jsonDecode(preferences.getString(storageKey) ?? '[]')
              as List<dynamic>;
      notes.addAll(
        values.map(
          (value) => SecretNote.fromJson(value as Map<String, dynamic>),
        ),
      );
      notes.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    } catch (_) {
      // Damaged private notes must not prevent the area from opening.
    }
    if (mounted) setState(() => loaded = true);
  }

  Future<void> save() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      storageKey,
      jsonEncode(notes.map((note) => note.toJson()).toList()),
    );
  }

  Future<void> editNote([SecretNote? existing]) async {
    final result = await showDialog<_SecretNoteDraft>(
      context: context,
      builder: (context) => _SecretNoteEditor(existing: existing),
    );
    if (result == null) return;
    setState(() {
      if (existing == null) {
        notes.insert(
          0,
          SecretNote(
            id: DateTime.now().microsecondsSinceEpoch.toString(),
            title: result.title,
            body: result.body,
            parentId: currentFolderId,
          ),
        );
      } else {
        existing
          ..title = result.title
          ..body = result.body
          ..updatedAt = DateTime.now();
        notes.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      }
    });
    await save();
  }

  Future<Directory> mediaDirectory() async {
    final documents = await getApplicationDocumentsDirectory();
    final directory = Directory('${documents.path}/netforge_private_media');
    if (!await directory.exists()) await directory.create(recursive: true);
    return directory;
  }

  Future<String> copyImageIntoWorkspace(XFile source) async {
    final directory = await mediaDirectory();
    final extension = source.name.contains('.')
        ? '.${source.name.split('.').last.toLowerCase()}'
        : '.jpg';
    final destination =
        '${directory.path}/${DateTime.now().microsecondsSinceEpoch}$extension';
    await File(source.path).copy(destination);
    return destination;
  }

  Future<void> importImages() async {
    final picked = await openFiles(
      acceptedTypeGroups: const [
        XTypeGroup(
          label: 'Images',
          extensions: ['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'],
          mimeTypes: ['image/*'],
        ),
      ],
    );
    if (picked.isEmpty) return;
    final imported = <SecretNote>[];
    for (final image in picked) {
      final path = await copyImageIntoWorkspace(image);
      imported.add(
        SecretNote(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          title: image.name,
          body: '',
          kind: 'image',
          parentId: currentFolderId,
          imagePath: path,
        ),
      );
    }
    if (!mounted) return;
    setState(() => notes.addAll(imported));
    await save();
  }

  Future<void> showCreateMenu() async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: surface,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.note_add_outlined),
              title: const Text('New note'),
              onTap: () => Navigator.pop(context, 'note'),
            ),
            ListTile(
              leading: const Icon(Icons.create_new_folder_outlined),
              title: const Text('New folder'),
              onTap: () => Navigator.pop(context, 'folder'),
            ),
            ListTile(
              leading: const Icon(Icons.add_photo_alternate_outlined),
              title: const Text('Add images'),
              onTap: () => Navigator.pop(context, 'images'),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('Take photo'),
              onTap: () => Navigator.pop(context, 'camera'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!mounted) return;
    switch (action) {
      case 'note':
        await editNote();
      case 'folder':
        await createFolder();
      case 'images':
        await importImages();
      case 'camera':
        await takePhoto();
      case null:
        break;
    }
  }

  Future<void> createFolder() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New folder'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Folder name *'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CANCEL'),
          ),
          FilledButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                Navigator.pop(context, controller.text.trim());
              }
            },
            child: const Text('CREATE'),
          ),
        ],
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 350));
    controller.dispose();
    if (name == null || !mounted) return;
    setState(
      () => notes.add(
        SecretNote(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          title: name,
          body: '',
          kind: 'folder',
          parentId: currentFolderId,
        ),
      ),
    );
    await save();
  }

  Future<void> takePhoto() async {
    final photo = await ImagePicker().pickImage(
      source: ImageSource.camera,
      imageQuality: 95,
    );
    if (photo == null) return;
    final path = await copyImageIntoWorkspace(photo);
    if (!mounted) return;
    setState(
      () => notes.add(
        SecretNote(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          title:
              'Photo ${DateTime.now().toLocal().toString().split('.').first}',
          body: '',
          kind: 'image',
          parentId: currentFolderId,
          imagePath: path,
        ),
      ),
    );
    await save();
  }

  Future<void> attachImages(SecretNote note) async {
    final picked = await openFiles(
      acceptedTypeGroups: const [
        XTypeGroup(
          label: 'Images',
          extensions: ['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'],
          mimeTypes: ['image/*'],
        ),
      ],
    );
    if (picked.isEmpty) return;
    for (final image in picked) {
      note.attachments.add(await copyImageIntoWorkspace(image));
    }
    note.updatedAt = DateTime.now();
    if (mounted) setState(() {});
    await save();
  }

  Future<void> pasteEntry() async {
    final source = notes.where((item) => item.id == copiedEntryId).firstOrNull;
    if (source == null) return;
    var imagePath = source.imagePath;
    if (imagePath.isNotEmpty && await File(imagePath).exists()) {
      imagePath = await copyImageIntoWorkspace(XFile(imagePath));
    }
    final attachments = <String>[];
    for (final path in source.attachments) {
      if (await File(path).exists()) {
        attachments.add(await copyImageIntoWorkspace(XFile(path)));
      }
    }
    if (!mounted) return;
    setState(
      () => notes.add(
        SecretNote(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          title: '${source.title} copy',
          body: source.body,
          kind: source.kind,
          parentId: currentFolderId,
          imagePath: imagePath,
          attachments: attachments,
        ),
      ),
    );
    await save();
  }

  Future<void> cropImage(SecretNote entry) async {
    final decoded = img.decodeImage(await File(entry.imagePath).readAsBytes());
    if (decoded == null) return;
    final size = decoded.width < decoded.height
        ? decoded.width
        : decoded.height;
    final cropped = img.copyCrop(
      decoded,
      x: (decoded.width - size) ~/ 2,
      y: (decoded.height - size) ~/ 2,
      width: size,
      height: size,
    );
    await File(
      entry.imagePath,
    ).writeAsBytes(img.encodeJpg(cropped, quality: 92));
    entry.updatedAt = DateTime.now();
    if (mounted) setState(() {});
    await save();
  }

  Future<void> shareEntry(SecretNote entry) async {
    if (entry.kind == 'image') {
      await SharePlus.instance.share(
        ShareParams(files: [XFile(entry.imagePath)], title: entry.title),
      );
    } else {
      await SharePlus.instance.share(
        ShareParams(text: '${entry.title}\n\n${entry.body}'),
      );
    }
  }

  Set<String> descendantIds(Iterable<String> parentIds) {
    final descendants = <String>{...parentIds};
    var changed = true;
    while (changed) {
      changed = false;
      for (final entry in notes) {
        if (!descendants.contains(entry.id) &&
            entry.parentId != null &&
            descendants.contains(entry.parentId)) {
          descendants.add(entry.id);
          changed = true;
        }
      }
    }
    return descendants;
  }

  bool hasSelectedAncestor(SecretNote entry) {
    var parentId = entry.parentId;
    while (parentId != null) {
      if (selectedEntryIds.contains(parentId)) return true;
      parentId = notes
          .where((item) => item.id == parentId)
          .firstOrNull
          ?.parentId;
    }
    return false;
  }

  Future<void> moveSelectedInsideWorkspace() async {
    if (selectedEntryIds.isEmpty) return;
    final forbidden = descendantIds(selectedEntryIds);
    final folders =
        notes
            .where(
              (entry) =>
                  entry.kind == 'folder' && !forbidden.contains(entry.id),
            )
            .toList()
          ..sort((a, b) => a.title.compareTo(b.title));
    final destination = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Move selected items to…'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, '__root__'),
            child: const ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.home_outlined),
              title: Text('Private files root'),
            ),
          ),
          ...folders.map(
            (folder) => SimpleDialogOption(
              onPressed: () => Navigator.pop(context, folder.id),
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.folder_outlined),
                title: Text(folder.title),
              ),
            ),
          ),
        ],
      ),
    );
    if (destination == null || !mounted) return;
    final newParentId = destination == '__root__' ? null : destination;
    setState(() {
      for (final entry in notes.where(
        (item) =>
            selectedEntryIds.contains(item.id) && !hasSelectedAncestor(item),
      )) {
        entry
          ..parentId = newParentId
          ..updatedAt = DateTime.now();
      }
      selectedEntryIds.clear();
    });
    await save();
  }

  Future<void> moveSelectedImagesExternal() async {
    final images = notes
        .where(
          (entry) =>
              selectedEntryIds.contains(entry.id) && entry.kind == 'image',
        )
        .toList();
    if (images.isEmpty || images.length != selectedEntryIds.length) return;
    final destination = await getDirectoryPath(confirmButtonText: 'MOVE HERE');
    if (destination == null || !mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Move images out of private files?'),
        content: Text(
          'Move ${images.length} ${images.length == 1 ? 'image' : 'images'} '
          'to the selected phone folder? They will be removed from this private workspace.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('CANCEL'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('MOVE OUT'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    for (var index = 0; index < images.length; index++) {
      final entry = images[index];
      final source = File(entry.imagePath);
      if (!await source.exists()) continue;
      final extension = entry.imagePath.contains('.')
          ? '.${entry.imagePath.split('.').last}'
          : '.jpg';
      final baseName = entry.title
          .replaceAll(RegExp(r'\.[^.]+$'), '')
          .replaceAll(RegExp(r'[^A-Za-z0-9 _-]'), '_');
      final output =
          '$destination/${DateTime.now().microsecondsSinceEpoch}_$index'
          '_${baseName.isEmpty ? 'image' : baseName}$extension';
      await source.copy(output);
      await source.delete();
    }
    if (!mounted) return;
    setState(() {
      notes.removeWhere(images.contains);
      selectedEntryIds.clear();
    });
    await save();
  }

  Future<void> openEntry(SecretNote entry) async {
    if (entry.kind == 'folder') {
      setState(() => currentFolderId = entry.id);
      return;
    }
    final action = await showDialog<String>(
      context: context,
      builder: (context) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700, maxHeight: 760),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        entry.title,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: entry.kind == 'text'
                          ? () => Navigator.pop(context, 'edit')
                          : null,
                      tooltip: 'Edit note',
                      icon: const Icon(Icons.edit_outlined),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      tooltip: 'Close viewer',
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: SingleChildScrollView(
                    child: entry.kind == 'image'
                        ? Image.file(File(entry.imagePath))
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SelectableText(
                                entry.body.isEmpty ? 'Empty note' : entry.body,
                              ),
                              if (entry.attachments.isNotEmpty) ...[
                                const SizedBox(height: 16),
                                const Text(
                                  'ATTACHMENTS',
                                  style: TextStyle(
                                    color: secondary,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: entry.attachments
                                      .map(
                                        (path) => ClipRRect(
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                          child: Image.file(
                                            File(path),
                                            width: 130,
                                            height: 100,
                                            fit: BoxFit.cover,
                                          ),
                                        ),
                                      )
                                      .toList(),
                                ),
                              ],
                            ],
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (action == 'edit' && mounted) await editNote(entry);
  }

  Future<void> handleEntryAction(String action, SecretNote entry) async {
    switch (action) {
      case 'edit':
        await editNote(entry);
      case 'attach':
        await attachImages(entry);
      case 'copy':
        setState(() => copiedEntryId = entry.id);
      case 'crop':
        await cropImage(entry);
      case 'share':
        await shareEntry(entry);
      case 'delete':
        await deleteNote(entry);
    }
  }

  Future<void> deleteNote(SecretNote note) async {
    await deleteEntries({note});
  }

  Future<void> deleteSelectedEntries() async {
    final selected = notes
        .where((entry) => selectedEntryIds.contains(entry.id))
        .toSet();
    await deleteEntries(selected);
  }

  Future<void> deleteEntries(Set<SecretNote> requested) async {
    if (requested.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(requested.length == 1 ? 'Delete item?' : 'Delete items?'),
        content: Text(
          requested.length == 1
              ? 'Delete “${requested.single.title}”?'
              : 'Delete ${requested.length} selected items? Folders and their contents will be removed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('CANCEL'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: danger),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('DELETE'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final removing = <SecretNote>{...requested};
    var foundChild = true;
    while (foundChild) {
      foundChild = false;
      for (final entry in notes) {
        if (!removing.contains(entry) &&
            removing.any((parent) => entry.parentId == parent.id)) {
          removing.add(entry);
          foundChild = true;
        }
      }
    }
    for (final entry in removing) {
      for (final path in [entry.imagePath, ...entry.attachments]) {
        if (path.isEmpty) continue;
        try {
          final file = File(path);
          if (await file.exists()) await file.delete();
        } catch (_) {}
      }
    }
    if (!mounted) return;
    setState(() {
      notes.removeWhere(removing.contains);
      selectedEntryIds.clear();
    });
    await save();
  }

  void handleBack() {
    if (selectedEntryIds.isNotEmpty) {
      setState(selectedEntryIds.clear);
    } else if (currentFolderId != null) {
      setState(() => currentFolderId = currentFolder?.parentId);
    } else {
      widget.onClose();
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop) handleBack();
    },
    child: Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: selectedEntryIds.isNotEmpty
            ? IconButton(
                onPressed: () => setState(selectedEntryIds.clear),
                tooltip: 'Cancel selection',
                icon: const Icon(Icons.close_rounded),
              )
            : currentFolderId == null
            ? null
            : IconButton(
                onPressed: () =>
                    setState(() => currentFolderId = currentFolder?.parentId),
                tooltip: 'Up one folder',
                icon: const Icon(Icons.arrow_back_rounded),
              ),
        title: Text(
          selectedEntryIds.isEmpty
              ? currentFolder?.title ?? 'Private files'
              : '${selectedEntryIds.length} selected',
        ),
        actions: [
          if (selectedEntryIds.isNotEmpty)
            IconButton(
              onPressed: moveSelectedInsideWorkspace,
              tooltip: 'Move selected',
              icon: const Icon(Icons.drive_file_move_outline),
            ),
          if (onlyImagesSelected)
            IconButton(
              onPressed: moveSelectedImagesExternal,
              tooltip: 'Move images to phone folder',
              icon: const Icon(Icons.outbox_outlined),
            ),
          if (selectedEntryIds.isNotEmpty)
            IconButton(
              onPressed: deleteSelectedEntries,
              tooltip: 'Delete selected',
              color: danger,
              icon: const Icon(Icons.delete_outline_rounded),
            )
          else if (copiedEntryId != null)
            IconButton(
              onPressed: pasteEntry,
              tooltip: 'Paste copied item',
              icon: const Icon(Icons.content_paste_rounded),
            ),
          if (selectedEntryIds.isEmpty)
            IconButton(
              onPressed: widget.onClose,
              tooltip: 'Close notes',
              icon: const Icon(Icons.close_rounded),
            ),
        ],
      ),
      body: !loaded
          ? const Center(child: CircularProgressIndicator(color: accent))
          : GestureDetector(
              behavior: HitTestBehavior.opaque,
              onLongPress: selectedEntryIds.isEmpty ? showCreateMenu : null,
              child: visibleEntries.isEmpty
                  ? const EmptyMessage(
                      icon: Icons.folder_open_rounded,
                      text: 'This folder is empty. Hold here to add something.',
                    )
                  : GridView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                      gridDelegate:
                          const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 260,
                            mainAxisExtent: 210,
                            crossAxisSpacing: 10,
                            mainAxisSpacing: 10,
                          ),
                      itemCount: visibleEntries.length,
                      itemBuilder: (context, index) {
                        final entry = visibleEntries[index];
                        final selected = selectedEntryIds.contains(entry.id);
                        return Card(
                          color: surface,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(
                              color: selected ? danger : border,
                              width: selected ? 3 : 1,
                            ),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            onTap: () {
                              if (selectedEntryIds.isEmpty) {
                                openEntry(entry);
                              } else {
                                setState(() {
                                  if (!selectedEntryIds.add(entry.id)) {
                                    selectedEntryIds.remove(entry.id);
                                  }
                                });
                              }
                            },
                            onLongPress: () =>
                                setState(() => selectedEntryIds.add(entry.id)),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child:
                                      entry.kind == 'image' &&
                                          entry.imagePath.isNotEmpty
                                      ? Image.file(
                                          File(entry.imagePath),
                                          width: double.infinity,
                                          fit: BoxFit.cover,
                                        )
                                      : Center(
                                          child: Icon(
                                            entry.kind == 'folder'
                                                ? Icons.folder_rounded
                                                : Icons.description_outlined,
                                            color: entry.kind == 'folder'
                                                ? warning
                                                : accent,
                                            size: 64,
                                          ),
                                        ),
                                ),
                                ListTile(
                                  dense: true,
                                  title: Text(
                                    entry.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  subtitle: Text(
                                    entry.kind == 'folder'
                                        ? 'Folder'
                                        : entry.kind == 'image'
                                        ? 'Image'
                                        : '${entry.attachments.length} attachments',
                                  ),
                                  trailing: selectedEntryIds.isNotEmpty
                                      ? Icon(
                                          selected
                                              ? Icons.check_circle_rounded
                                              : Icons.circle_outlined,
                                          color: selected ? danger : secondary,
                                        )
                                      : PopupMenuButton<String>(
                                          onSelected: (action) =>
                                              handleEntryAction(action, entry),
                                          itemBuilder: (context) => [
                                            if (entry.kind == 'text')
                                              const PopupMenuItem(
                                                value: 'edit',
                                                child: Text('Edit note'),
                                              ),
                                            if (entry.kind == 'text')
                                              const PopupMenuItem(
                                                value: 'attach',
                                                child: Text('Attach images'),
                                              ),
                                            const PopupMenuItem(
                                              value: 'copy',
                                              child: Text('Copy'),
                                            ),
                                            if (entry.kind == 'image')
                                              const PopupMenuItem(
                                                value: 'crop',
                                                child: Text('Crop square'),
                                              ),
                                            if (entry.kind != 'folder')
                                              const PopupMenuItem(
                                                value: 'share',
                                                child: Text('Share / send'),
                                              ),
                                            const PopupMenuItem(
                                              value: 'delete',
                                              child: Text('Delete'),
                                            ),
                                          ],
                                        ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
    ),
  );
}

class _SecretNoteDraft {
  const _SecretNoteDraft(this.title, this.body);
  final String title;
  final String body;
}

class _SecretNoteEditor extends StatefulWidget {
  const _SecretNoteEditor({this.existing});
  final SecretNote? existing;

  @override
  State<_SecretNoteEditor> createState() => _SecretNoteEditorState();
}

class _SecretNoteEditorState extends State<_SecretNoteEditor> {
  late final title = TextEditingController(text: widget.existing?.title ?? '');
  late final body = TextEditingController(text: widget.existing?.body ?? '');

  @override
  void dispose() {
    title.dispose();
    body.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.existing == null ? 'New note' : 'Edit note'),
    content: SizedBox(
      width: 520,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: title,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Title *'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: body,
            minLines: 8,
            maxLines: 16,
            decoration: const InputDecoration(
              labelText: 'Note',
              alignLabelWithHint: true,
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('CANCEL'),
      ),
      FilledButton(
        onPressed: () {
          if (title.text.trim().isEmpty) return;
          Navigator.pop(
            context,
            _SecretNoteDraft(title.text.trim(), body.text.trim()),
          );
        },
        child: const Text('SAVE'),
      ),
    ],
  );
}

class HomePage extends StatelessWidget {
  const HomePage({
    super.key,
    required this.networks,
    required this.liveInventory,
    required this.connection,
    required this.loadingConnection,
    required this.onRefreshConnection,
    required this.onRequestPermissions,
    required this.onOpenLocationSettings,
    required this.onOpen,
    required this.onCreate,
    required this.onGoToNetworks,
  });

  final List<NetworkMap> networks;
  final LiveInventory liveInventory;
  final Map<String, dynamic> connection;
  final bool loadingConnection;
  final VoidCallback onRefreshConnection;
  final VoidCallback onRequestPermissions;
  final VoidCallback onOpenLocationSettings;
  final ValueChanged<NetworkMap> onOpen;
  final VoidCallback onCreate;
  final VoidCallback onGoToNetworks;

  @override
  Widget build(BuildContext context) {
    final deviceCount = networks.fold<int>(
      0,
      (total, network) => total + network.devices.length,
    );
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'LAN MAPPER',
            style: TextStyle(
              fontWeight: FontWeight.w900,
              letterSpacing: 1.6,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Your networks, remembered.',
            style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          const Text(
            'Map devices, label what they are, and review what changed.',
            style: TextStyle(color: secondary, fontSize: 15),
          ),
          const SizedBox(height: 20),
          CurrentWifiCard(
            connection: connection,
            loading: loadingConnection,
            onRefresh: onRefreshConnection,
            onRequestPermissions: onRequestPermissions,
            onOpenLocationSettings: onOpenLocationSettings,
          ),
          AnimatedBuilder(
            animation: liveInventory,
            builder: (context, _) {
              final devices = liveInventory.devices;
              if (devices.isEmpty) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(top: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SectionHeader(title: 'Latest live observations'),
                    const SizedBox(height: 8),
                    ...devices
                        .take(3)
                        .map(
                          (device) => ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(
                              Icons.sensors_rounded,
                              color: accent,
                            ),
                            title: Text(
                              device.ip,
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            subtitle: Text(
                              '${device.hostname.isEmpty ? 'Unidentified' : device.hostname} · ${device.ports.length} known ports',
                              style: const TextStyle(color: secondary),
                            ),
                          ),
                        ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 22),
          Row(
            children: [
              Expanded(
                child: SummaryCard(
                  label: 'NETWORKS',
                  value: '${networks.length}',
                  icon: Icons.hub_rounded,
                  onTap: onGoToNetworks,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SummaryCard(
                  label: 'DEVICES',
                  value: '$deviceCount',
                  icon: Icons.devices_rounded,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: networks.isEmpty ? onCreate : onGoToNetworks,
            icon: Icon(
              networks.isEmpty ? Icons.add_rounded : Icons.radar_rounded,
            ),
            label: Text(
              networks.isEmpty ? 'CREATE FIRST NETWORK' : 'SCAN OR IMPORT',
            ),
          ),
          if (networks.isNotEmpty) ...[
            const SizedBox(height: 28),
            const SectionHeader(title: 'Your networks'),
            const SizedBox(height: 10),
            ...networks
                .take(4)
                .map(
                  (network) => NetworkTile(
                    network: network,
                    onTap: () => onOpen(network),
                  ),
                ),
          ],
        ],
      ),
    );
  }
}

class NetworksPage extends StatelessWidget {
  const NetworksPage({
    super.key,
    required this.networks,
    required this.liveInventory,
    required this.currentSsid,
    required this.onOpen,
    required this.onCreate,
    required this.onChanged,
  });

  final List<NetworkMap> networks;
  final LiveInventory liveInventory;
  final String currentSsid;
  final ValueChanged<NetworkMap> onOpen;
  final VoidCallback onCreate;
  final Future<void> Function() onChanged;

  Future<void> mergeSavedNetworks(BuildContext context) async {
    if (networks.length < 2) return;
    var firstId = networks[0].id;
    var secondId = networks[1].id;
    final selection = await showDialog<List<String>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Merge saved networks'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: firstId,
                decoration: const InputDecoration(labelText: 'First network'),
                items: networks
                    .map(
                      (network) => DropdownMenuItem(
                        value: network.id,
                        child: Text(network.name),
                      ),
                    )
                    .toList(),
                onChanged: (value) =>
                    setDialogState(() => firstId = value ?? firstId),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: secondId,
                decoration: const InputDecoration(labelText: 'Second network'),
                items: networks
                    .map(
                      (network) => DropdownMenuItem(
                        value: network.id,
                        child: Text(network.name),
                      ),
                    )
                    .toList(),
                onChanged: (value) =>
                    setDialogState(() => secondId = value ?? secondId),
              ),
              const SizedBox(height: 10),
              const Text(
                'A new combined network will be created. Both originals will remain unchanged.',
                style: TextStyle(color: secondary, fontSize: 12),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('CANCEL'),
            ),
            FilledButton(
              onPressed: firstId == secondId
                  ? null
                  : () => Navigator.pop(context, [firstId, secondId]),
              child: const Text('CREATE MERGED COPY'),
            ),
          ],
        ),
      ),
    );
    if (selection == null || !context.mounted) return;
    final first = networks.firstWhere((item) => item.id == selection[0]);
    final second = networks.firstWhere((item) => item.id == selection[1]);
    final merged = mergeNetworks(first, second);
    networks.insert(0, merged);
    await onChanged();
    if (context.mounted) onOpen(merged);
  }

  Future<void> importNetForgeFile(BuildContext context) async {
    try {
      final picked = await openFile(
        acceptedTypeGroups: const [
          XTypeGroup(
            label: 'NetForge network',
            extensions: ['netforge', 'json'],
            mimeTypes: ['application/json'],
          ),
        ],
      );
      if (picked == null || !context.mounted) return;
      final incoming = parseNetForgeFile(await picked.readAsString());
      if (!context.mounted) return;
      final existingIndex = networks.indexWhere(
        (network) => network.id == incoming.id,
      );
      var imported = incoming;
      if (existingIndex >= 0) {
        final choice = await showDialog<String>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Network already exists'),
            content: Text(
              '“${incoming.name}” is already saved on this device. Replace it '
              'with the imported copy or keep both?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('CANCEL'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, 'copy'),
                child: const Text('KEEP BOTH'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, 'replace'),
                child: const Text('REPLACE'),
              ),
            ],
          ),
        );
        if (choice == null || !context.mounted) return;
        if (choice == 'replace') {
          networks[existingIndex] = incoming;
        } else {
          imported = NetworkMap.fromJson({
            ...incoming.toJson(),
            'id': DateTime.now().microsecondsSinceEpoch.toString(),
            'name': '${incoming.name} (imported)',
          });
          networks.insert(0, imported);
        }
      } else {
        networks.insert(0, imported);
      }
      await onChanged();
      if (context.mounted) onOpen(imported);
    } on FormatException catch (exception) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Import failed: ${exception.message}')),
      );
    } catch (exception) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open that NetForge file.')),
      );
    }
  }

  Future<void> importNotes(BuildContext context) async {
    final controller = TextEditingController();
    final result = await showModalBottomSheet<_ImportResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: surface,
      builder: (context) => Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          20,
          20,
          MediaQuery.viewInsetsOf(context).bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Import scan notes',
              style: TextStyle(fontSize: 23, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            const Text(
              'Paste your Notepad text. IPs, MAC addresses, port lists, and nearby labels will be extracted.',
              style: TextStyle(color: secondary),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              minLines: 8,
              maxLines: 14,
              decoration: const InputDecoration(
                hintText:
                    'Living Room TV  192.168.1.40  AA:BB:CC:DD:EE:FF  ports 80,443',
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () {
                  final devices = parseScanNotes(controller.text);
                  if (devices.isNotEmpty) {
                    Navigator.pop(
                      context,
                      _ImportResult(controller.text, devices),
                    );
                  }
                },
                child: const Text('IMPORT DEVICES'),
              ),
            ),
          ],
        ),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 350));
    controller.dispose();
    if (result == null || !context.mounted) return;
    var destination = 'new';
    if (networks.isNotEmpty) {
      final choice = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Where should these devices go?'),
          content: Text(
            '${result.devices.length} devices were found in the notes.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('CANCEL'),
            ),
            OutlinedButton(
              onPressed: () => Navigator.pop(context, 'existing'),
              child: const Text('ADD TO SAVED'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, 'new'),
              child: const Text('CREATE NEW'),
            ),
          ],
        ),
      );
      if (choice == null || !context.mounted) return;
      destination = choice;
    }
    if (destination == 'existing') {
      final target = await showDialog<NetworkMap>(
        context: context,
        builder: (context) => SimpleDialog(
          title: const Text('Add notes to…'),
          children: networks
              .map(
                (network) => SimpleDialogOption(
                  onPressed: () => Navigator.pop(context, network),
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(network.name),
                    subtitle: Text('${network.devices.length} devices'),
                  ),
                ),
              )
              .toList(),
        ),
      );
      if (target == null || !context.mounted) return;
      mergeDevicesInto(target, result.devices);
      final importedNotes = 'Imported scan notes:\n${result.rawText.trim()}';
      if (!target.notes.contains(result.rawText.trim())) {
        target.notes = target.notes.isEmpty
            ? importedNotes
            : '${target.notes}\n\n$importedNotes';
      }
      target.updatedAt = DateTime.now();
      await onChanged();
      if (context.mounted) onOpen(target);
      return;
    }
    final details = await _editNetworkDialog(
      context,
      initialName: 'Imported LAN',
      initialSsid: currentSsid,
      initialNotes: result.rawText,
    );
    if (details == null) return;
    final network = NetworkMap(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: details.name,
      ssid: details.ssid,
      gateway: details.gateway,
      subnet: details.subnet,
      notes: details.notes,
      devices: result.devices,
    );
    networks.insert(0, network);
    await onChanged();
    if (context.mounted) onOpen(network);
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'Networks',
          style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900),
        ),
        const Text(
          'Saved LAN maps and imported scan notes.',
          style: TextStyle(color: secondary),
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: onCreate,
                icon: const Icon(Icons.add_rounded),
                label: const Text('NEW'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => importNotes(context),
                icon: const Icon(Icons.note_add_outlined),
                label: const Text('IMPORT NOTES'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => importNetForgeFile(context),
            icon: const Icon(Icons.file_open_outlined),
            label: const Text('IMPORT .NETFORGE FILE'),
          ),
        ),
        if (networks.length >= 2) ...[
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => mergeSavedNetworks(context),
              icon: const Icon(Icons.merge_rounded),
              label: const Text('MERGE SAVED NETWORKS'),
            ),
          ),
        ],
        const SizedBox(height: 22),
        SavedNetworksList(
          networks: networks,
          onOpen: onOpen,
          onChanged: onChanged,
        ),
        const SizedBox(height: 26),
        QuickLanScanPanel(
          networks: networks,
          liveInventory: liveInventory,
          currentSsid: currentSsid,
          onOpen: onOpen,
          onChanged: onChanged,
        ),
      ],
    ),
  );
}

class SavedNetworksList extends StatefulWidget {
  const SavedNetworksList({
    super.key,
    required this.networks,
    required this.onOpen,
    required this.onChanged,
  });
  final List<NetworkMap> networks;
  final ValueChanged<NetworkMap> onOpen;
  final Future<void> Function() onChanged;

  @override
  State<SavedNetworksList> createState() => _SavedNetworksListState();
}

class _SavedNetworksListState extends State<SavedNetworksList> {
  bool showAll = false;

  Future<bool> confirmDelete(NetworkMap network) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete saved network?'),
        content: Text(
          'Delete “${network.name}” and its ${network.devices.length} saved '
          '${network.devices.length == 1 ? 'device' : 'devices'}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('CANCEL'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: danger),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('DELETE'),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  Future<void> deleteAfterConfirmation(NetworkMap network) async {
    if (!await confirmDelete(network) || !mounted) return;
    widget.networks.remove(network);
    await widget.onChanged();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final visible = showAll ? widget.networks : widget.networks.take(3);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(title: 'Saved networks (${widget.networks.length})'),
        const SizedBox(height: 8),
        if (widget.networks.isEmpty)
          const EmptyMessage(
            icon: Icons.hub_outlined,
            text: 'No networks saved yet.',
          )
        else
          ...visible.map(
            (network) => Dismissible(
              key: ValueKey('saved-network:${network.id}'),
              direction: DismissDirection.endToStart,
              background: const _SwipeStatusBackground(
                alignment: Alignment.centerRight,
                color: danger,
                icon: Icons.delete_outline_rounded,
                label: 'DELETE NETWORK',
              ),
              confirmDismiss: (_) => confirmDelete(network),
              onDismissed: (_) async {
                widget.networks.remove(network);
                await widget.onChanged();
                if (mounted) setState(() {});
              },
              child: NetworkTile(
                network: network,
                onTap: () => widget.onOpen(network),
                onLongPress: () => deleteAfterConfirmation(network),
              ),
            ),
          ),
        if (widget.networks.length > 3)
          SizedBox(
            width: double.infinity,
            child: TextButton.icon(
              onPressed: () => setState(() => showAll = !showAll),
              icon: Icon(
                showAll ? Icons.expand_less_rounded : Icons.expand_more_rounded,
              ),
              label: Text(
                showAll
                    ? 'SHOW RECENT 3'
                    : 'VIEW ALL ${widget.networks.length} NETWORKS',
              ),
            ),
          ),
      ],
    );
  }
}

class QuickLanScanPanel extends StatefulWidget {
  const QuickLanScanPanel({
    super.key,
    required this.networks,
    required this.liveInventory,
    required this.currentSsid,
    required this.onOpen,
    required this.onChanged,
  });
  final List<NetworkMap> networks;
  final LiveInventory liveInventory;
  final String currentSsid;
  final ValueChanged<NetworkMap> onOpen;
  final Future<void> Function() onChanged;

  @override
  State<QuickLanScanPanel> createState() => _QuickLanScanPanelState();
}

class _QuickLanScanPanelState extends State<QuickLanScanPanel> {
  bool scanning = false;
  int checked = 0;
  String? error;

  List<ScannedHost> get results => widget.liveInventory.devices
      .map(
        (device) => ScannedHost(
          device.ip,
          device.hostname.isEmpty ? device.ip : device.hostname,
          List.of(device.ports),
          mac: device.mac,
        ),
      )
      .toList();

  Future<void> scan() async {
    if (scanning) return;
    setState(() {
      scanning = true;
      checked = 0;
      error = null;
    });
    try {
      final found = await discoverLan(
        onProgress: (value) {
          if (mounted && (value % 8 == 0 || value == 254)) {
            setState(() => checked = value);
          }
        },
      );
      if (mounted) {
        widget.liveInventory.observeHosts(found);
        setState(() {
          checked = 254;
          scanning = false;
        });
      }
    } catch (exception) {
      if (mounted) {
        setState(() {
          error = '$exception';
          scanning = false;
        });
      }
    }
  }

  Future<void> saveResults() async {
    final details = await _editNetworkDialog(
      context,
      initialName: widget.currentSsid.isEmpty
          ? 'Scanned LAN'
          : '${widget.currentSsid} LAN',
      initialSsid: widget.currentSsid,
    );
    if (details == null || !mounted) return;
    final network = NetworkMap(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: details.name,
      ssid: details.ssid,
      gateway: details.gateway,
      subnet: details.subnet,
      notes: details.notes,
      devices: results.map((host) => host.toRecord()).toList(),
    );
    widget.networks.insert(0, network);
    await widget.onChanged();
    widget.liveInventory.clear();
    if (mounted) widget.onOpen(network);
  }

  Future<void> mergeResults() async {
    if (results.isEmpty || widget.networks.isEmpty) return;
    final target = await showDialog<NetworkMap>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Merge Live LAN into…'),
        children: widget.networks
            .map(
              (network) => SimpleDialogOption(
                onPressed: () => Navigator.pop(context, network),
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(network.name),
                  subtitle: Text(
                    '${network.devices.length} devices'
                    '${network.ssid.isEmpty ? '' : ' · ${network.ssid}'}',
                  ),
                ),
              ),
            )
            .toList(),
      ),
    );
    if (target == null || !mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Merge into saved network?'),
        content: Text(
          'Add ${results.length} Live LAN devices to “${target.name}”? '
          'Existing documentation will be kept and open ports will be combined.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('CANCEL'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('MERGE'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    mergeDevicesInto(target, results.map((host) => host.toRecord()));
    if (target.ssid.isEmpty && widget.currentSsid.isNotEmpty) {
      target.ssid = widget.currentSsid;
    }
    target.updatedAt = DateTime.now();
    await widget.onChanged();
    widget.liveInventory.clear();
    if (mounted) widget.onOpen(target);
  }

  Future<void> showResult(ScannedHost host) async {
    await showDevice(
      context,
      host.toRecord(),
      fresh: host,
      onPing: () => checkResultAlive(host),
      onScanAllPorts: () => scanResultPorts(host),
    );
  }

  Future<void> scanResultPorts(
    ScannedHost host, {
    PortSelectionMode initialPortMode = PortSelectionMode.common,
  }) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SimplePortScanner(
          liveInventory: widget.liveInventory,
          initialHost: host.ip,
          initialPortMode: initialPortMode,
        ),
      ),
    );
  }

  Future<void> checkResultAlive(ScannedHost host) async {
    final result = await checkHostAndListedPorts(host.ip, host.ports);
    if (result.reachable) {
      widget.liveInventory.replacePorts(host.ip, result.openPorts);
      if (result.mac.isNotEmpty) {
        widget.liveInventory.observeMac(host.ip, result.mac);
      }
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result.reachable
              ? '${host.ip} is alive · ${result.openPorts.length} checked '
                    'ports are open.'
              : '${host.ip} did not respond. It may be offline or blocking ping.',
        ),
      ),
    );
  }

  Future<void> showResultTools(ScannedHost host) async {
    final tool = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: surface,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(
                host.ip,
                style: const TextStyle(
                  color: accent,
                  fontWeight: FontWeight.w900,
                  fontFamily: 'monospace',
                ),
              ),
              subtitle: const Text('Choose a tool for this scan result'),
            ),
            ListTile(
              leading: const Icon(Icons.radar_rounded),
              title: const Text('Port scanner'),
              onTap: () => Navigator.pop(context, 'ports'),
            ),
            ListTile(
              leading: const Icon(Icons.travel_explore_rounded),
              title: const Text('DNS lookup'),
              onTap: () => Navigator.pop(context, 'dns'),
            ),
            ListTile(
              leading: const Icon(Icons.calculate_outlined),
              title: const Text('Subnet calculator'),
              onTap: () => Navigator.pop(context, 'subnet'),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
    if (!mounted || tool == null) return;
    if (tool == 'ports') {
      await scanResultPorts(host);
    } else if (tool == 'dns') {
      await showDnsLookup(context, widget.liveInventory, initialInput: host.ip);
    } else if (tool == 'subnet') {
      await showSubnetCalculator(context, initialCidr: '${host.ip}/24');
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.liveInventory,
    builder: (context, _) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(title: 'Live LAN workspace'),
        const SizedBox(height: 6),
        const Text(
          'Scans and global tools gather devices here. Nothing becomes a '
          'saved network until you choose Save Network.',
          style: TextStyle(color: secondary, fontSize: 12),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: scanning ? null : scan,
            icon: Icon(scanning ? Icons.sync_rounded : Icons.radar_rounded),
            label: Text(
              scanning ? 'SCANNING $checked / 254' : 'SCAN CURRENT LAN',
            ),
          ),
        ),
        if (scanning) ...[
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: checked / 254,
            color: accent,
            backgroundColor: border,
          ),
        ],
        if (error != null) ...[
          const SizedBox(height: 10),
          Text(error!, style: const TextStyle(color: danger)),
        ],
        if (!scanning && results.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(
            '${results.length} devices found',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              TextButton.icon(
                onPressed: saveResults,
                icon: const Icon(Icons.save_outlined),
                label: const Text('SAVE AS NEW'),
              ),
              if (widget.networks.isNotEmpty)
                TextButton.icon(
                  onPressed: mergeResults,
                  icon: const Icon(Icons.merge_rounded),
                  label: const Text('MERGE INTO SAVED'),
                ),
            ],
          ),
          ...results.map((host) {
            final device = host.toRecord();
            return DeviceTile(
              device: device,
              status: DeviceStatus.active,
              onTap: () => showResult(host),
              onTools: () => showResultTools(host),
              onPing: () => checkResultAlive(host),
            );
          }),
          if (results.any((host) => !isUsableMacAddress(host.mac)))
            MacDiscoveryNotice(
              unresolvedCount: results
                  .where((host) => !isUsableMacAddress(host.mac))
                  .length,
            ),
        ],
        if (!scanning && checked > 0 && results.isEmpty && error == null)
          const EmptyMessage(
            icon: Icons.search_off_rounded,
            text: 'No devices responded to the scan.',
          ),
      ],
    ),
  );
}

class DeviceCheckResult {
  const DeviceCheckResult({
    required this.ip,
    required this.reachable,
    required this.openPorts,
    required this.checkedPorts,
    this.mac = '',
  });

  final String ip;
  final bool reachable;
  final List<int> openPorts;
  final List<int> checkedPorts;
  final String mac;
}

typedef DeviceChecker =
    Future<DeviceCheckResult> Function(String ip, List<int> listedPorts);

typedef LanScanner =
    Future<List<ScannedHost>> Function({
      void Function(int checked)? onProgress,
    });

class NetworkWorkspace extends StatefulWidget {
  const NetworkWorkspace({
    super.key,
    required this.network,
    required this.onChanged,
    required this.liveInventory,
    this.deviceChecker,
    this.lanScanner,
  });

  final NetworkMap network;
  final Future<void> Function() onChanged;
  final LiveInventory liveInventory;
  final DeviceChecker? deviceChecker;
  final LanScanner? lanScanner;

  @override
  State<NetworkWorkspace> createState() => _NetworkWorkspaceState();
}

class _NetworkWorkspaceState extends State<NetworkWorkspace> {
  static const deviceChannel = MethodChannel('netforge/device_status');

  final refreshed = <String, ScannedHost>{};
  final missing = <String>{};
  final ignored = <String>{};
  final checking = <String>{};
  final recentlyAddedPorts = <String, Set<int>>{};
  bool scanning = false;
  bool hasRefreshed = false;
  int checked = 0;

  Iterable<ScannedHost> get newHosts {
    final saved = widget.network.devices.map((device) => device.ip).toSet();
    return refreshed.values.where(
      (host) => !saved.contains(host.ip) && !ignored.contains(host.ip),
    );
  }

  Future<void> changed() async {
    widget.network.updatedAt = DateTime.now();
    await widget.onChanged();
    if (mounted) setState(() {});
  }

  Future<void> scan() async {
    if (scanning) return;
    setState(() {
      scanning = true;
      hasRefreshed = false;
      checked = 0;
      refreshed.clear();
      missing.clear();
      ignored.clear();
      recentlyAddedPorts.clear();
    });
    try {
      final hosts = await (widget.lanScanner ?? discoverLan)(
        onProgress: (value) {
          if (mounted && (value % 8 == 0 || value == 254)) {
            setState(() => checked = value);
          }
        },
      );
      if (!mounted) return;
      final byIp = {for (final host in hosts) host.ip: host};
      final savedChecks = await Future.wait(
        widget.network.devices.map((device) async {
          try {
            final result =
                await (widget.deviceChecker ?? checkHostAndListedPorts)(
                  device.ip,
                  List.of(device.ports),
                );
            return (device: device, result: result);
          } catch (_) {
            return (device: device, result: null);
          }
        }),
      );
      if (!mounted) return;
      for (final entry in savedChecks) {
        final result = entry.result;
        if (result == null) continue;
        final broadResult = byIp[entry.device.ip];
        if (!result.reachable && broadResult == null) continue;
        final ports = {...?broadResult?.ports, ...result.openPorts}.toList()
          ..sort();
        final checkedPorts = {
          ...?broadResult?.checkedPorts,
          ...result.checkedPorts,
        }.toList()..sort();
        final hostname = broadResult?.hostname.isNotEmpty == true
            ? broadResult!.hostname
            : entry.device.name.isNotEmpty
            ? entry.device.name
            : entry.device.ip;
        byIp[entry.device.ip] = ScannedHost(
          entry.device.ip,
          hostname,
          ports,
          mac: result.mac.isNotEmpty ? result.mac : broadResult?.mac ?? '',
          checkedPorts: checkedPorts,
        );
      }
      final savedIps = widget.network.devices
          .map((device) => device.ip)
          .toSet();
      final observedAt = DateTime.now();
      var touchedSavedDevice = false;
      for (final device in widget.network.devices) {
        final observation = byIp[device.ip];
        if (observation == null) continue;
        final before = device.ports.toSet();
        addObservedOpenPorts(device, observation, observedAt: observedAt);
        final added = device.ports.toSet().difference(before);
        if (added.isNotEmpty) recentlyAddedPorts[device.ip] = added;
        device.lastSeen = observedAt;
        touchedSavedDevice = true;
      }
      setState(() {
        refreshed.addAll(byIp);
        missing.addAll(savedIps.difference(byIp.keys.toSet()));
        checked = 254;
        scanning = false;
        hasRefreshed = true;
      });
      if (touchedSavedDevice) await changed();
    } catch (error) {
      if (!mounted) return;
      setState(() => scanning = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Scan failed: $error')));
    }
  }

  Future<void> editNetwork() async {
    final result = await _editNetworkDialog(
      context,
      initialName: widget.network.name,
      initialSsid: widget.network.ssid,
      initialGateway: widget.network.gateway,
      initialSubnet: widget.network.subnet,
      initialNotes: widget.network.notes,
    );
    if (result == null) return;
    widget.network
      ..name = result.name
      ..ssid = result.ssid
      ..gateway = result.gateway
      ..subnet = result.subnet
      ..notes = result.notes;
    await changed();
  }

  Future<void> editDevice([DeviceRecord? existing]) async {
    final result = await deviceEditor(context, existing);
    if (result == null) return;
    if (existing == null) {
      widget.network.devices.add(result);
    } else {
      final index = widget.network.devices.indexOf(existing);
      if (index >= 0) {
        widget.network.devices[index] = result;
      } else {
        final removedIndex = widget.network.removedDevices.indexOf(existing);
        if (removedIndex >= 0) {
          widget.network.removedDevices[removedIndex] = result;
        }
      }
    }
    await changed();
  }

  Future<void> renameDevice(DeviceRecord device) async {
    final name = await showDialog<String>(
      context: context,
      builder: (context) => _DeviceNameDialog(initialName: device.name),
    );
    if (!mounted || name == null || name.isEmpty) return;
    device.name = name;
    await changed();
  }

  Future<void> checkSavedDevice(DeviceRecord device) async {
    if (checking.contains(device.ip)) return;
    setState(() => checking.add(device.ip));
    try {
      final result = await (widget.deviceChecker ?? checkHostAndListedPorts)(
        device.ip,
        List.of(device.ports),
      );
      if (!mounted) return;
      if (!result.reachable) {
        setState(() {
          refreshed.remove(device.ip);
          missing.add(device.ip);
          recentlyAddedPorts.remove(device.ip);
          hasRefreshed = true;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${device.ip} did not respond to ping or its listed ports.',
            ),
          ),
        );
        return;
      }

      final previous = refreshed[device.ip];
      final hostname = previous?.hostname.isNotEmpty == true
          ? previous!.hostname
          : device.name.isNotEmpty
          ? device.name
          : device.ip;
      final observed = ScannedHost(
        device.ip,
        hostname,
        List.of(result.openPorts),
        mac: result.mac.isNotEmpty ? result.mac : previous?.mac ?? '',
        checkedPorts: List.of(result.checkedPorts),
      );
      final observedAt = DateTime.now();
      final before = device.ports.toSet();
      addObservedOpenPorts(device, observed, observedAt: observedAt);
      final added = device.ports.toSet().difference(before);
      device
        ..isDead = false
        ..lastSeen = observedAt;
      setState(() {
        refreshed[device.ip] = observed;
        missing.remove(device.ip);
        if (added.isEmpty) {
          recentlyAddedPorts.remove(device.ip);
        } else {
          recentlyAddedPorts[device.ip] = added;
        }
        hasRefreshed = true;
      });
      await changed();
      if (!mounted) return;
      final openText = result.openPorts.isEmpty
          ? 'No checked ports are open, but the IP responded.'
          : 'Open ports: ${result.openPorts.join(', ')}.';
      final addedText = added.isEmpty
          ? ''
          : ' Added automatically: ${(added.toList()..sort()).join(', ')}.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${device.ip} is active. $openText$addedText')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Check failed: $error')));
    } finally {
      if (mounted) setState(() => checking.remove(device.ip));
    }
  }

  Future<void> openDeviceTools(DeviceRecord device) async {
    final tool = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: surface,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                device.ip,
                style: const TextStyle(
                  color: accent,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  fontFamily: 'monospace',
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Choose a tool. Newly confirmed open ports are saved '
                'automatically; identity and removals remain reviewable.',
                style: TextStyle(color: secondary),
              ),
              const SizedBox(height: 12),
              ListTile(
                leading: const Icon(Icons.radar_rounded),
                title: const Text('Port scanner'),
                subtitle: const Text('Scan ports and review open results'),
                onTap: () => Navigator.pop(context, 'ports'),
              ),
              ListTile(
                leading: const Icon(Icons.travel_explore_rounded),
                title: const Text('DNS lookup'),
                subtitle: const Text(
                  'Look up a hostname without changing saved data',
                ),
                onTap: () => Navigator.pop(context, 'dns'),
              ),
              ListTile(
                leading: const Icon(Icons.calculate_outlined),
                title: const Text('Subnet calculator'),
                subtitle: const Text('Calculate the range containing this IP'),
                onTap: () => Navigator.pop(context, 'subnet'),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || tool == null) return;
    if (tool == 'ports') {
      await openDevicePortScanner(device);
    } else if (tool == 'dns') {
      await showDnsLookup(
        context,
        widget.liveInventory,
        initialInput: device.ip,
        recordInLiveInventory: false,
        onResult: (ip, hostname) {
          if (ip != device.ip) return;
          final current = refreshed[ip];
          setState(() {
            refreshed[ip] = ScannedHost(
              ip,
              hostname,
              current == null ? List.of(device.ports) : List.of(current.ports),
              mac: current?.mac ?? device.mac,
            );
          });
        },
      );
    } else if (tool == 'subnet') {
      await showSubnetCalculator(context, initialCidr: '${device.ip}/24');
    }
    if (mounted) setState(() {});
  }

  Future<void> openDevicePortScanner(
    DeviceRecord device, {
    bool scanAllPorts = false,
  }) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SimplePortScanner(
          liveInventory: widget.liveInventory,
          initialHost: device.ip,
          recordInLiveInventory: false,
          initialPortMode: scanAllPorts
              ? PortSelectionMode.all
              : PortSelectionMode.common,
          onResults: (result) async {
            if (!mounted) return;
            final observedAt = DateTime.now();
            final before = device.ports.toSet();
            addObservedOpenPorts(device, result, observedAt: observedAt);
            final added = device.ports.toSet().difference(before);
            device.lastSeen = observedAt;
            final merged = mergePortScanObservation(
              result,
              previous: refreshed[device.ip],
              saved: device,
            );
            setState(() {
              refreshed[device.ip] = merged;
              missing.remove(device.ip);
              if (added.isEmpty) {
                recentlyAddedPorts.remove(device.ip);
              } else {
                recentlyAddedPorts[device.ip] = added;
              }
              hasRefreshed = true;
            });
            await changed();
          },
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> exportNetwork() async {
    final readable = exportNetworkText(widget.network);
    final json = portableNetworkJson(widget.network);
    final fileName = netForgeFileName(widget.network);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: surface,
      builder: (context) => FractionallySizedBox(
        heightFactor: .82,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Export network',
                style: TextStyle(fontSize: 23, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: SingleChildScrollView(child: SelectableText(readable)),
              ),
              const SizedBox(height: 12),
              if (Platform.isAndroid) ...[
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => shareNetForgeFile(fileName, json),
                    icon: const Icon(Icons.share_rounded),
                    label: const Text('SHARE .NETFORGE FILE'),
                  ),
                ),
                const SizedBox(height: 10),
              ],
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final saved = await saveNetForgeFile(fileName, json);
                    if (!saved || !context.mounted) return;
                    Navigator.pop(context);
                    if (!mounted) return;
                    ScaffoldMessenger.of(
                      this.context,
                    ).showSnackBar(SnackBar(content: Text('Saved $fileName')));
                  },
                  icon: const Icon(Icons.save_alt_rounded),
                  label: const Text('SAVE .NETFORGE FILE'),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () =>
                          Clipboard.setData(ClipboardData(text: readable)),
                      icon: const Icon(Icons.copy_rounded),
                      label: const Text('COPY TEXT'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () =>
                          Clipboard.setData(ClipboardData(text: json)),
                      icon: const Icon(Icons.data_object_rounded),
                      label: const Text('COPY JSON'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> shareNetForgeFile(String fileName, String content) async {
    try {
      final file = XFile.fromData(
        Uint8List.fromList(utf8.encode(content)),
        mimeType: 'application/json',
        name: fileName,
      );
      await SharePlus.instance.share(
        ShareParams(files: [file], title: 'Share ${widget.network.name}'),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the share sheet.')),
      );
    }
  }

  Future<bool> saveNetForgeFile(String fileName, String content) async {
    if (Platform.isAndroid) {
      return await deviceChannel.invokeMethod<bool>('saveNetForgeFile', {
            'name': fileName,
            'content': content,
          }) ??
          false;
    }
    final location = await getSaveLocation(suggestedName: fileName);
    if (location == null) return false;
    final file = XFile.fromData(
      Uint8List.fromList(utf8.encode(content)),
      mimeType: 'application/json',
      name: fileName,
    );
    await file.saveTo(location.path);
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final active = widget.network.devices.where(
      (device) => refreshed.containsKey(device.ip),
    );
    final markedInactiveButLive = widget.network.devices.where(
      (device) => device.isDead && refreshed.containsKey(device.ip),
    );
    final markedActiveButOffline = widget.network.devices.where(
      (device) => !device.isDead && missing.contains(device.ip),
    );
    final unresolvedMacs = refreshed.values
        .where((host) => !isUsableMacAddress(host.mac))
        .length;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.network.name),
        backgroundColor: background,
        actions: [
          IconButton(
            onPressed: exportNetwork,
            tooltip: 'Export or share network',
            icon: const Icon(Icons.ios_share_rounded),
          ),
          IconButton(
            onPressed: editNetwork,
            tooltip: 'Edit network',
            icon: const Icon(Icons.edit_outlined),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: editDevice,
        icon: const Icon(Icons.add_rounded),
        label: const Text('ADD DEVICE'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (widget.network.ssid.isNotEmpty)
                InfoChip(icon: Icons.wifi_rounded, text: widget.network.ssid),
              if (widget.network.gateway.isNotEmpty)
                InfoChip(
                  icon: Icons.router_rounded,
                  text: widget.network.gateway,
                ),
              if (widget.network.subnet.isNotEmpty)
                InfoChip(
                  icon: Icons.account_tree_outlined,
                  text: widget.network.subnet,
                ),
            ],
          ),
          if (widget.network.notes.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              widget.network.notes,
              style: const TextStyle(color: secondary),
            ),
          ],
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: scanning ? null : scan,
            icon: Icon(scanning ? Icons.sync_rounded : Icons.refresh_rounded),
            label: Text(
              scanning ? 'SCANNING $checked / 254' : 'REFRESH THIS LAN',
            ),
          ),
          if (scanning) ...[
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: checked / 254,
              color: accent,
              backgroundColor: border,
            ),
          ],
          if (hasRefreshed) ...[
            const SizedBox(height: 8),
            Text(
              '${active.length} saved active · ${missing.length} missing · ${newHosts.length} new',
              style: const TextStyle(color: secondary, fontSize: 12),
            ),
            if (unresolvedMacs > 0)
              MacDiscoveryNotice(unresolvedCount: unresolvedMacs),
          ],
          if (markedInactiveButLive.isNotEmpty ||
              markedActiveButOffline.isNotEmpty) ...[
            const SizedBox(height: 22),
            const SectionHeader(title: 'Saved status changes', color: warning),
            const SizedBox(height: 4),
            const Text(
              'These saved statuses do not match the latest refresh.',
              style: TextStyle(color: secondary, fontSize: 12),
            ),
            const SizedBox(height: 8),
            ...markedInactiveButLive.map(
              (device) => ReviewCard(
                color: accent,
                title: '${device.title} · ${device.ip}',
                subtitle: 'Currently live, but marked inactive in your list.',
                primary: 'CHECK & MARK ACTIVE',
                secondary: 'EDIT',
                onPrimary: () => checkSavedDevice(device),
                onSecondary: () => editDevice(device),
              ),
            ),
            ...markedActiveButOffline.map(
              (device) => ReviewCard(
                color: danger,
                title: '${device.title} · ${device.ip}',
                subtitle: 'Currently offline, but marked active in your list.',
                primary: 'MARK INACTIVE',
                secondary: 'EDIT',
                onPrimary: () async {
                  device.isDead = true;
                  await changed();
                },
                onSecondary: () => editDevice(device),
              ),
            ),
          ],
          if (newHosts.isNotEmpty) ...[
            const SizedBox(height: 22),
            SectionHeader(title: 'New devices', color: accent),
            const SizedBox(height: 8),
            ...newHosts.map(
              (host) => ReviewCard(
                color: accent,
                title: host.ip,
                subtitle:
                    '${host.hostname.isEmpty ? 'Unknown device' : host.hostname}'
                    ' · ${host.ports.length} open ports'
                    '${host.mac.isEmpty ? '' : ' · ${normalizeMacAddress(host.mac)}'}',
                primary: 'KEEP',
                secondary: 'IGNORE',
                onPrimary: () async {
                  widget.network.devices.add(host.toRecord());
                  await changed();
                },
                onSecondary: () => setState(() => ignored.add(host.ip)),
              ),
            ),
          ],
          const SizedBox(height: 24),
          SectionHeader(title: 'Devices (${widget.network.devices.length})'),
          const SizedBox(height: 8),
          if (widget.network.devices.isEmpty)
            const EmptyMessage(
              icon: Icons.devices_other_outlined,
              text: 'No devices documented yet. Refresh or add one.',
            )
          else
            ...widget.network.devices.map((device) {
              final isMissing = missing.contains(device.ip);
              final fresh = refreshed[device.ip];
              final addedPorts = recentlyAddedPorts[device.ip] ?? const <int>{};
              final closedPorts = observedClosedPorts(device, fresh);
              final unsavedOpenPorts = observedUnsavedOpenPorts(device, fresh);
              final portsChanged =
                  addedPorts.isNotEmpty ||
                  closedPorts.isNotEmpty ||
                  unsavedOpenPorts.isNotEmpty;
              final macChanged =
                  fresh != null &&
                  isUsableMacAddress(fresh.mac) &&
                  normalizeMacAddress(fresh.mac) !=
                      normalizeMacAddress(device.mac);
              final status = device.isDead
                  ? DeviceStatus.dead
                  : isMissing
                  ? DeviceStatus.missing
                  : portsChanged || macChanged
                  ? DeviceStatus.changed
                  : fresh != null
                  ? DeviceStatus.active
                  : DeviceStatus.saved;
              final statusReason = deviceStatusReason(
                status: status,
                device: device,
                fresh: fresh,
                automaticallyAddedPorts: addedPorts,
                checking: checking.contains(device.ip),
              );
              return Dismissible(
                key: ValueKey(
                  '${widget.network.id}:${device.ip}:${device.mac}',
                ),
                direction: DismissDirection.horizontal,
                background: _SwipeStatusBackground(
                  alignment: Alignment.centerLeft,
                  color: accent,
                  icon: Icons.network_ping_rounded,
                  label: 'CHECK IP & PORTS',
                ),
                secondaryBackground: _SwipeStatusBackground(
                  alignment: Alignment.centerRight,
                  color: danger,
                  icon: device.isDead
                      ? Icons.delete_outline_rounded
                      : Icons.wifi_off_rounded,
                  label: device.isDead ? 'DELETE' : 'MARK INACTIVE',
                ),
                confirmDismiss: (direction) async {
                  if (direction == DismissDirection.endToStart) {
                    if (device.isDead) return true;
                    device.isDead = true;
                  } else if (direction == DismissDirection.startToEnd) {
                    await checkSavedDevice(device);
                    return false;
                  }
                  await changed();
                  return false;
                },
                onDismissed: (_) async {
                  widget.network.devices.remove(device);
                  widget.network.removedDevices.add(device);
                  missing.remove(device.ip);
                  refreshed.remove(device.ip);
                  await changed();
                },
                child: DeviceTile(
                  device: device,
                  observedMac: fresh?.mac ?? '',
                  status: status,
                  statusReason: statusReason,
                  onTools: () => openDeviceTools(device),
                  onPing: checking.contains(device.ip)
                      ? null
                      : () => checkSavedDevice(device),
                  onTap: () => showDevice(
                    context,
                    device,
                    fresh: fresh,
                    onRename: () => renameDevice(device),
                    onEdit: () => editDevice(device),
                    onPing: () => checkSavedDevice(device),
                    onScanAllPorts: () => openDevicePortScanner(device),
                    onApplyMac: !macChanged
                        ? null
                        : () async {
                            device
                              ..mac = normalizeMacAddress(fresh.mac)
                              ..lastSeen = DateTime.now();
                            if (device.product.isEmpty ||
                                device.product == 'Reachable network device') {
                              device.product = guessProduct(
                                fresh.ports,
                                hostname: fresh.hostname,
                                mac: fresh.mac,
                              );
                            }
                            await changed();
                          },
                    onApplyHostname:
                        fresh == null ||
                            fresh.hostname.isEmpty ||
                            fresh.hostname == fresh.ip ||
                            fresh.hostname == device.name
                        ? null
                        : () async {
                            device
                              ..name = fresh.hostname
                              ..lastSeen = DateTime.now();
                            await changed();
                          },
                    onDelete: () async {
                      widget.network.devices.remove(device);
                      missing.remove(device.ip);
                      await changed();
                    },
                    onApplyPorts: fresh == null
                        ? null
                        : () async {
                            device
                              ..ports =
                                  (device.ports
                                      .where(
                                        (port) => !closedPorts.contains(port),
                                      )
                                      .toList()
                                    ..sort())
                              ..lastSeen = DateTime.now();
                            await changed();
                          },
                  ),
                  onKeep: isMissing ? () => checkSavedDevice(device) : null,
                  onDelete: isMissing
                      ? () async {
                          widget.network.devices.remove(device);
                          missing.remove(device.ip);
                          await changed();
                        }
                      : null,
                ),
              );
            }),
          if (widget.network.removedDevices.isNotEmpty) ...[
            const SizedBox(height: 26),
            SectionHeader(
              title:
                  'Removed devices (${widget.network.removedDevices.length})',
              color: danger,
            ),
            const SizedBox(height: 4),
            const Text(
              'Swipe right to restore. Swipe left to remove permanently.',
              style: TextStyle(color: secondary, fontSize: 12),
            ),
            const SizedBox(height: 8),
            ...widget.network.removedDevices.map(
              (device) => Dismissible(
                key: ValueKey(
                  '${widget.network.id}:removed:${device.ip}:${device.mac}',
                ),
                direction: DismissDirection.horizontal,
                background: const _SwipeStatusBackground(
                  alignment: Alignment.centerLeft,
                  color: accent,
                  icon: Icons.restore_rounded,
                  label: 'RESTORE TO NETWORK',
                ),
                secondaryBackground: const _SwipeStatusBackground(
                  alignment: Alignment.centerRight,
                  color: danger,
                  icon: Icons.delete_forever_outlined,
                  label: 'REMOVE PERMANENTLY',
                ),
                onDismissed: (direction) async {
                  widget.network.removedDevices.remove(device);
                  if (direction == DismissDirection.startToEnd) {
                    device.isDead = false;
                    widget.network.devices.add(device);
                  }
                  await changed();
                },
                child: DeviceTile(
                  device: device,
                  status: DeviceStatus.dead,
                  onTools: () => openDeviceTools(device),
                  onTap: () => showDevice(
                    context,
                    device,
                    onRename: () => renameDevice(device),
                    onEdit: () => editDevice(device),
                    onScanAllPorts: () => openDevicePortScanner(device),
                    onDelete: () async {
                      widget.network.removedDevices.remove(device);
                      await changed();
                    },
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

enum DeviceStatus { saved, active, changed, missing, dead }

Set<int> _checkedPortsFor(DeviceRecord device, ScannedHost fresh) {
  if (fresh.checkedPorts.isNotEmpty) return fresh.checkedPorts.toSet();
  // Empty coverage is the legacy full-snapshot form of ScannedHost.
  return {...device.ports, ...fresh.ports};
}

List<int> observedClosedPorts(DeviceRecord device, ScannedHost? fresh) {
  if (fresh == null) return const [];
  final closed = device.ports.toSet().intersection(
    _checkedPortsFor(device, fresh),
  )..removeAll(fresh.ports);
  return closed.toList()..sort();
}

List<int> observedUnsavedOpenPorts(DeviceRecord device, ScannedHost? fresh) {
  if (fresh == null) return const [];
  final unsaved = fresh.ports.toSet()..removeAll(device.ports);
  return unsaved.toList()..sort();
}

String deviceStatusReason({
  required DeviceStatus status,
  required DeviceRecord device,
  ScannedHost? fresh,
  Iterable<int> automaticallyAddedPorts = const [],
  bool checking = false,
}) {
  if (checking) return 'Checking IP and listed ports…';
  if (status == DeviceStatus.dead) return 'Red — marked inactive';
  if (status == DeviceStatus.missing) {
    return 'Red — no response to ping or listed-port checks';
  }
  if (status != DeviceStatus.changed) return '';

  final reasons = <String>[];
  final added = automaticallyAddedPorts.toSet().toList()..sort();
  if (added.isNotEmpty) {
    reasons.add('new open ports added: ${added.join(', ')}');
  }
  final unsaved = observedUnsavedOpenPorts(device, fresh);
  if (unsaved.isNotEmpty) {
    reasons.add('new open ports found: ${unsaved.join(', ')}');
  }
  final closed = observedClosedPorts(device, fresh);
  if (closed.isNotEmpty) {
    reasons.add('listed ports not open: ${closed.join(', ')}');
  }
  if (fresh != null &&
      isUsableMacAddress(fresh.mac) &&
      normalizeMacAddress(fresh.mac) != normalizeMacAddress(device.mac)) {
    reasons.add('MAC address changed');
  }
  return reasons.isEmpty
      ? 'Yellow — observed details changed'
      : 'Yellow — ${reasons.join(' · ')}';
}

String macDiscoveryExplanation() {
  if (Platform.isAndroid) {
    return 'Android 10 and newer blocks regular apps from reading the LAN '
        'neighbor table. Any MAC the phone exposes will appear here; add the '
        'rest with Edit or import them from your router or scan notes.';
  }
  if (Platform.isIOS) {
    return 'iOS does not expose other LAN devices’ MAC addresses to regular '
        'apps. Add them with Edit or import them from your router or scan notes.';
  }
  return 'The neighbor table did not report every MAC. Devices behind another '
      'router/VLAN, client isolation, or an incomplete local cache may remain '
      'unavailable.';
}

class MacDiscoveryNotice extends StatelessWidget {
  const MacDiscoveryNotice({super.key, required this.unresolvedCount});

  final int unresolvedCount;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    margin: const EdgeInsets.only(top: 10),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: warning.withValues(alpha: .08),
      border: Border.all(color: warning.withValues(alpha: .55)),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.info_outline_rounded, color: warning, size: 20),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            '$unresolvedCount ${unresolvedCount == 1 ? 'device has' : 'devices have'} '
            'no discovered MAC. ${macDiscoveryExplanation()}',
            style: const TextStyle(color: secondary, fontSize: 12),
          ),
        ),
      ],
    ),
  );
}

class _SwipeStatusBackground extends StatelessWidget {
  const _SwipeStatusBackground({
    required this.alignment,
    required this.color,
    required this.icon,
    required this.label,
  });
  final Alignment alignment;
  final Color color;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 9),
    padding: const EdgeInsets.symmetric(horizontal: 20),
    alignment: alignment,
    decoration: BoxDecoration(
      color: color.withValues(alpha: .2),
      border: Border.all(color: color),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(color: color, fontWeight: FontWeight.w900),
        ),
      ],
    ),
  );
}

class DeviceTile extends StatelessWidget {
  const DeviceTile({
    super.key,
    required this.device,
    required this.status,
    required this.onTap,
    required this.onTools,
    this.observedMac = '',
    this.statusReason = '',
    this.onPing,
    this.onKeep,
    this.onDelete,
  });

  final DeviceRecord device;
  final DeviceStatus status;
  final VoidCallback onTap;
  final VoidCallback onTools;
  final String observedMac;
  final String statusReason;
  final VoidCallback? onPing;
  final VoidCallback? onKeep;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final visibleMac = isUsableMacAddress(device.mac)
        ? normalizeMacAddress(device.mac)
        : isUsableMacAddress(observedMac)
        ? normalizeMacAddress(observedMac)
        : '';
    final color = switch (status) {
      DeviceStatus.active => border,
      DeviceStatus.changed => warning,
      DeviceStatus.missing => danger,
      DeviceStatus.dead => danger,
      DeviceStatus.saved => border,
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Material(
        color: color.withValues(alpha: status == DeviceStatus.saved ? .2 : .08),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: color),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            ListTile(
              onTap: onTap,
              onLongPress: () => _copyDevice(context),
              leading: Icon(
                status == DeviceStatus.missing || status == DeviceStatus.dead
                    ? Icons.wifi_off_rounded
                    : Icons.devices_rounded,
                color: color,
              ),
              title: Text(
                device.title,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 3),
                  InkWell(
                    onTap: onTools,
                    onLongPress: () => _copyIp(context),
                    borderRadius: BorderRadius.circular(6),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: 3,
                        horizontal: 2,
                      ),
                      child: Text(
                        device.ip,
                        style: const TextStyle(
                          color: accent,
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                  ),
                  if (device.ports.isNotEmpty)
                    Text(
                      device.ports.join(', '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: secondary,
                        fontSize: 12,
                        fontFamily: 'monospace',
                      ),
                    ),
                  if (visibleMac.isNotEmpty)
                    Text(
                      '$visibleMac${device.mac.isEmpty ? ' · detected' : ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: secondary,
                        fontSize: 12,
                        fontFamily: 'monospace',
                      ),
                    ),
                  if (statusReason.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      statusReason,
                      style: TextStyle(
                        color: color,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ],
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (onPing != null)
                    IconButton(
                      onPressed: onPing,
                      tooltip: 'Refresh listed ports for ${device.ip}',
                      icon: const Icon(Icons.network_ping_rounded),
                    ),
                  const Icon(Icons.chevron_right_rounded),
                ],
              ),
            ),
            if (status == DeviceStatus.missing)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: onKeep,
                        child: const Text('CHECK AGAIN'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton(
                        onPressed: onDelete,
                        style: FilledButton.styleFrom(backgroundColor: danger),
                        child: const Text('DELETE'),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _copyIp(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: device.ip));
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Copied ${device.ip}')));
  }

  Future<void> _copyDevice(BuildContext context) async {
    final details = [
      'Name: ${device.title}',
      'IP: ${device.ip}',
      'MAC: ${device.mac.isEmpty ? 'Not available' : device.mac}',
      'Product: ${device.product.isEmpty ? 'Unidentified' : device.product}',
      'Ports: ${device.ports.isEmpty ? 'None' : device.ports.join(', ')}',
      if (device.notes.isNotEmpty) 'Notes: ${device.notes}',
    ].join('\n');
    await Clipboard.setData(ClipboardData(text: details));
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Copied all info for ${device.ip}')));
  }
}

class MappingToolsPage extends StatelessWidget {
  const MappingToolsPage({
    super.key,
    required this.liveInventory,
    required this.onCreateNetwork,
    required this.onScanSubnet,
    required this.onReviewPortResults,
  });

  final LiveInventory liveInventory;
  final VoidCallback onCreateNetwork;
  final VoidCallback onScanSubnet;
  final VoidCallback onReviewPortResults;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'Tools',
          style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900),
        ),
        const Text(
          'Only tools that support identifying and documenting devices.',
          style: TextStyle(color: secondary),
        ),
        const SizedBox(height: 20),
        ToolTile(
          icon: Icons.add_rounded,
          title: 'Create network',
          subtitle: 'Add and document a network',
          onTap: onCreateNetwork,
        ),
        ToolTile(
          icon: Icons.radar_rounded,
          title: 'Scan subnet',
          subtitle: 'Discover devices on the current LAN',
          onTap: onScanSubnet,
        ),
        ToolTile(
          icon: Icons.radar_rounded,
          title: 'Port scanner',
          subtitle: 'Check custom or common TCP ports',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => SimplePortScanner(
                liveInventory: liveInventory,
                onReviewResults: onReviewPortResults,
              ),
            ),
          ),
        ),
        ToolTile(
          icon: Icons.wifi_find_rounded,
          title: 'Nearby access points',
          subtitle: 'View Wi-Fi networks and signal strength',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const NearbyAccessPointsPage()),
          ),
        ),
        ToolTile(
          icon: Icons.travel_explore_rounded,
          title: 'DNS lookup',
          subtitle: 'Resolve a hostname or reverse-lookup an IP',
          onTap: () => showDnsLookup(context, liveInventory),
        ),
        ToolTile(
          icon: Icons.calculate_outlined,
          title: 'Subnet calculator',
          subtitle: 'Calculate an IPv4 network range',
          onTap: () => showSubnetCalculator(context),
        ),
        ToolTile(
          icon: Icons.system_update_rounded,
          title: 'Updates',
          subtitle: 'Check GitHub for a newer NetForge release',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const UpdatesPage()),
          ),
        ),
      ],
    ),
  );
}

class NetForgeRelease {
  const NetForgeRelease({
    required this.version,
    required this.name,
    required this.notes,
    required this.pageUrl,
    this.apkUrl,
    this.linuxUrl,
  });

  final String version;
  final String name;
  final String notes;
  final String pageUrl;
  final String? apkUrl;
  final String? linuxUrl;

  factory NetForgeRelease.fromJson(Map<String, dynamic> json) {
    final assets = json['assets'] as List<dynamic>? ?? const [];
    String? apkUrl;
    String? linuxUrl;
    for (final value in assets) {
      final asset = value as Map<String, dynamic>;
      final name = asset['name'] as String? ?? '';
      final url = asset['browser_download_url'] as String? ?? '';
      if (name.toLowerCase().endsWith('.apk') &&
          url.startsWith(
            'https://github.com/indiCa8250/NetForge/releases/download/',
          )) {
        apkUrl = url;
      }
      if ((name.toLowerCase().endsWith('.appimage') ||
              name.toLowerCase().endsWith('.deb')) &&
          url.startsWith(
            'https://github.com/indiCa8250/NetForge/releases/download/',
          )) {
        linuxUrl = url;
      }
    }
    return NetForgeRelease(
      version: (json['tag_name'] as String? ?? '').replaceFirst(
        RegExp(r'^[vV]'),
        '',
      ),
      name: json['name'] as String? ?? 'NetForge update',
      notes: json['body'] as String? ?? '',
      pageUrl:
          json['html_url'] as String? ??
          'https://github.com/indiCa8250/NetForge/releases',
      apkUrl: apkUrl,
      linuxUrl: linuxUrl,
    );
  }
}

List<int> versionParts(String value) => value
    .split(RegExp(r'[.+-]'))
    .take(3)
    .map((part) => int.tryParse(part) ?? 0)
    .toList();

bool isNewerVersion(String latest, String current) {
  final latestParts = versionParts(latest);
  final currentParts = versionParts(current);
  for (var index = 0; index < 3; index++) {
    final left = index < latestParts.length ? latestParts[index] : 0;
    final right = index < currentParts.length ? currentParts[index] : 0;
    if (left != right) return left > right;
  }
  return false;
}

class UpdatesPage extends StatefulWidget {
  const UpdatesPage({super.key});

  @override
  State<UpdatesPage> createState() => _UpdatesPageState();
}

class _UpdatesPageState extends State<UpdatesPage> {
  static const channel = MethodChannel('netforge/device_status');
  static const releasesUrl = 'https://github.com/indiCa8250/NetForge/releases';
  static const latestApiUrl =
      'https://api.github.com/repos/indiCa8250/NetForge/releases/latest';

  String currentVersion = '';
  NetForgeRelease? release;
  bool loading = true;
  String? error;

  @override
  void initState() {
    super.initState();
    check();
  }

  Future<void> check() async {
    setState(() {
      loading = true;
      error = null;
    });
    final client = HttpClient();
    try {
      final package = await PackageInfo.fromPlatform();
      final request = await client.getUrl(Uri.parse(latestApiUrl));
      request.headers
        ..set(HttpHeaders.acceptHeader, 'application/vnd.github+json')
        ..set(HttpHeaders.userAgentHeader, 'NetForge/${package.version}');
      final response = await request.close();
      if (response.statusCode == HttpStatus.notFound) {
        throw const HttpException(
          'No NetForge release has been published yet.',
        );
      }
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('GitHub returned status ${response.statusCode}.');
      }
      final body = await utf8.decoder.bind(response).join();
      final latest = NetForgeRelease.fromJson(
        jsonDecode(body) as Map<String, dynamic>,
      );
      if (!mounted) return;
      setState(() {
        currentVersion = package.version;
        release = latest;
        loading = false;
      });
    } catch (exception) {
      if (!mounted) return;
      setState(() {
        error = exception is HttpException
            ? exception.message
            : 'Could not check GitHub for updates.';
        loading = false;
      });
    } finally {
      client.close(force: true);
    }
  }

  Future<void> openUpdate(String url) async {
    try {
      final approved = url.startsWith(
        'https://github.com/indiCa8250/NetForge/',
      );
      if (!approved) throw const FormatException('Invalid update link.');
      if (Platform.isAndroid) {
        await channel.invokeMethod<void>('openUrl', {'url': url});
      } else if (Platform.isLinux) {
        final result = await Process.run('xdg-open', [url]);
        if (result.exitCode != 0) {
          throw ProcessException('xdg-open', [url]);
        }
      } else {
        throw UnsupportedError('Updates are not supported here.');
      }
    } catch (exception) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the update link.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final latest = release;
    final updateAvailable =
        latest != null &&
        currentVersion.isNotEmpty &&
        isNewerVersion(latest.version, currentVersion);
    final downloadUrl = latest == null
        ? null
        : Platform.isAndroid
        ? latest.apkUrl
        : Platform.isLinux
        ? latest.linuxUrl
        : null;
    return Scaffold(
      appBar: AppBar(
        title: const Text('NetForge updates'),
        actions: [
          IconButton(
            onPressed: loading ? null : check,
            tooltip: 'Check again',
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Icon(Icons.system_update_rounded, color: accent, size: 52),
          const SizedBox(height: 14),
          const Text(
            'NetForge updates',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          Text(
            currentVersion.isEmpty
                ? 'Checking the installed version…'
                : 'Installed version $currentVersion',
            textAlign: TextAlign.center,
            style: const TextStyle(color: secondary),
          ),
          if (loading) ...[
            const SizedBox(height: 24),
            const LinearProgressIndicator(
              color: accent,
              backgroundColor: border,
            ),
          ] else if (error != null) ...[
            const SizedBox(height: 24),
            Text(
              error!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: warning),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: check,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('CHECK AGAIN'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => openUpdate(releasesUrl),
              icon: const Icon(Icons.open_in_browser_rounded),
              label: const Text('OPEN GITHUB RELEASES'),
            ),
          ] else if (latest != null) ...[
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: surface,
                border: Border.all(color: updateAvailable ? accent : border),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    updateAvailable ? 'UPDATE AVAILABLE' : 'YOU ARE UP TO DATE',
                    style: TextStyle(
                      color: updateAvailable ? accent : secondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${latest.name} · ${latest.version}',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  if (latest.notes.trim().isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(
                      latest.notes.trim(),
                      style: const TextStyle(color: secondary),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: () => openUpdate(downloadUrl ?? latest.pageUrl),
              icon: const Icon(Icons.download_rounded),
              label: Text(
                downloadUrl == null
                    ? 'OPEN RELEASE'
                    : Platform.isAndroid
                    ? 'DOWNLOAD APK'
                    : 'DOWNLOAD LINUX APP',
              ),
            ),
            const SizedBox(height: 8),
            Text(
              Platform.isAndroid
                  ? 'Android will ask you to approve installation. Updates '
                        'must use the same release signing key.'
                  : 'Download and install the Linux release package. Your '
                        'saved networks remain stored locally.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: secondary, fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }
}

class NearbyAccessPoint {
  const NearbyAccessPoint({
    required this.ssid,
    required this.bssid,
    required this.level,
    required this.frequency,
    required this.channel,
    required this.security,
  });

  final String ssid;
  final String bssid;
  final int level;
  final int frequency;
  final int channel;
  final String security;

  factory NearbyAccessPoint.fromMap(Map<Object?, Object?> map) =>
      NearbyAccessPoint(
        ssid: map['ssid'] as String? ?? '',
        bssid: map['bssid'] as String? ?? '',
        level: map['level'] as int? ?? -100,
        frequency: map['frequency'] as int? ?? 0,
        channel: map['channel'] as int? ?? 0,
        security: map['security'] as String? ?? '',
      );
}

class NearbyAccessPointsPage extends StatefulWidget {
  const NearbyAccessPointsPage({super.key, this.androidPlatformOverride});

  final bool? androidPlatformOverride;

  @override
  State<NearbyAccessPointsPage> createState() => _NearbyAccessPointsPageState();
}

class _NearbyAccessPointsPageState extends State<NearbyAccessPointsPage> {
  static const channel = MethodChannel('netforge/device_status');

  List<NearbyAccessPoint> accessPoints = [];
  bool loading = true;
  String? error;
  String? connectingAccessPoint;

  bool get isAndroid => widget.androidPlatformOverride ?? Platform.isAndroid;

  @override
  void initState() {
    super.initState();
    refresh();
  }

  Future<void> refresh() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      if (!isAndroid) {
        throw PlatformException(
          code: 'unsupported',
          message:
              'Nearby access-point scanning is currently available on Android.',
        );
      }
      await channel.invokeMethod<Map<Object?, Object?>>('requestPermissions');
      final raw =
          await channel.invokeListMethod<Map<Object?, Object?>>(
            'getNearbyAccessPoints',
          ) ??
          [];
      if (!mounted) return;
      setState(() {
        accessPoints = raw.map(NearbyAccessPoint.fromMap).toList();
        loading = false;
      });
    } on PlatformException catch (exception) {
      if (!mounted) return;
      setState(() {
        error = exception.message ?? 'Could not scan nearby access points.';
        loading = false;
      });
    }
  }

  Future<void> connect(NearbyAccessPoint accessPoint) async {
    final connectionKey = '${accessPoint.ssid}|${accessPoint.bssid}';
    if (connectingAccessPoint != null) return;
    setState(() => connectingAccessPoint = connectionKey);
    var message = 'Could not open Android Wi-Fi controls.';
    try {
      final response =
          await channel.invokeMapMethod<Object?, Object?>(
            'connectToAccessPoint',
            {'ssid': accessPoint.ssid, 'bssid': accessPoint.bssid},
          ) ??
          const <Object?, Object?>{};
      message =
          response['message'] as String? ??
          'Android Wi-Fi controls opened. Confirm the connection there.';
    } on PlatformException catch (exception) {
      message = exception.message ?? message;
    } finally {
      if (mounted) setState(() => connectingAccessPoint = null);
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  IconData signalIcon(int level) {
    if (level >= -55) return Icons.signal_wifi_4_bar_rounded;
    if (level >= -67) return Icons.network_wifi_3_bar_rounded;
    if (level >= -75) return Icons.network_wifi_2_bar_rounded;
    return Icons.network_wifi_1_bar_rounded;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Nearby access points'),
      actions: [
        IconButton(
          onPressed: loading ? null : refresh,
          tooltip: 'Scan again',
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
    ),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'Nearby Wi-Fi',
          style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 4),
        const Text(
          'Access points are ordered by signal strength. Double-tap a named '
          'network or use its connect button to open Android Wi-Fi controls.',
          style: TextStyle(color: secondary),
        ),
        if (loading) ...[
          const SizedBox(height: 20),
          const LinearProgressIndicator(color: accent, backgroundColor: border),
          const SizedBox(height: 10),
          const Text('Scanning…', style: TextStyle(color: secondary)),
        ] else if (error != null) ...[
          const SizedBox(height: 20),
          Text(error!, style: const TextStyle(color: danger)),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: refresh,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('TRY AGAIN'),
          ),
        ] else if (accessPoints.isEmpty) ...[
          const SizedBox(height: 20),
          const EmptyMessage(
            icon: Icons.wifi_find_rounded,
            text: 'No nearby access points were reported.',
          ),
        ] else ...[
          const SizedBox(height: 16),
          Text(
            '${accessPoints.length} access points',
            style: const TextStyle(
              color: secondary,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          ...accessPoints.map((accessPoint) {
            final connectionKey = '${accessPoint.ssid}|${accessPoint.bssid}';
            final connecting = connectingAccessPoint == connectionKey;
            final canConnect =
                accessPoint.ssid.isNotEmpty && connectingAccessPoint == null;
            return Card(
              color: surface,
              clipBehavior: Clip.antiAlias,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: const BorderSide(color: border),
              ),
              child: InkWell(
                onDoubleTap: canConnect ? () => connect(accessPoint) : null,
                child: ListTile(
                  leading: Icon(signalIcon(accessPoint.level), color: accent),
                  title: Text(
                    accessPoint.ssid.isEmpty
                        ? 'Hidden network'
                        : accessPoint.ssid,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  subtitle: Text(
                    [
                      'BSSID ${accessPoint.bssid}',
                      '${accessPoint.level} dBm',
                      if (accessPoint.channel > 0) 'Ch ${accessPoint.channel}',
                      if (accessPoint.frequency > 0)
                        '${accessPoint.frequency} MHz',
                      if (accessPoint.security.isNotEmpty) accessPoint.security,
                    ].join(' · '),
                    style: const TextStyle(color: secondary, fontSize: 12),
                  ),
                  trailing: connecting
                      ? const SizedBox.square(
                          dimension: 22,
                          child: CircularProgressIndicator(
                            color: accent,
                            strokeWidth: 2,
                          ),
                        )
                      : IconButton(
                          onPressed: canConnect
                              ? () => connect(accessPoint)
                              : null,
                          tooltip: accessPoint.ssid.isEmpty
                              ? 'Hidden networks require Android Wi-Fi settings'
                              : 'Connect to ${accessPoint.ssid}',
                          icon: const Icon(Icons.login_rounded),
                        ),
                ),
              ),
            );
          }),
        ],
      ],
    ),
  );
}

class SimplePortScanner extends StatefulWidget {
  const SimplePortScanner({
    super.key,
    required this.liveInventory,
    this.initialHost = '',
    this.initialPortMode = PortSelectionMode.common,
    this.recordInLiveInventory = true,
    this.onResults,
    this.onReviewResults,
  });
  final LiveInventory liveInventory;
  final String initialHost;
  final PortSelectionMode initialPortMode;
  final bool recordInLiveInventory;
  final ValueChanged<ScannedHost>? onResults;
  final VoidCallback? onReviewResults;

  @override
  State<SimplePortScanner> createState() => _SimplePortScannerState();
}

enum PortSelectionMode { common, custom, all }

String formatPortScanSummary({
  required int addressesChecked,
  required List<int> checkedPorts,
  required int hostsWithOpenPorts,
}) {
  final addressLabel = addressesChecked == 1 ? 'address' : 'addresses';
  if (checkedPorts.length == 1) {
    return 'TCP ${checkedPorts.single} open on $hostsWithOpenPorts of '
        '$addressesChecked $addressLabel checked.';
  }
  return '$hostsWithOpenPorts of $addressesChecked $addressLabel had at least '
      'one selected TCP port open.';
}

class _SimplePortScannerState extends State<SimplePortScanner> {
  static const scanLanTarget = '__scan_lan__';

  final ports = TextEditingController();
  final results = <String, List<int>>{};
  List<int> lastScannedPorts = const [];
  late String selectedTarget;
  late PortSelectionMode portMode;
  bool scanning = false;
  int checked = 0;
  int total = 0;
  int targetsChecked = 0;

  @override
  void initState() {
    super.initState();
    selectedTarget = widget.initialHost.isEmpty
        ? scanLanTarget
        : widget.initialHost;
    portMode = widget.initialPortMode;
  }

  @override
  void dispose() {
    ports.dispose();
    super.dispose();
  }

  Future<List<String>> resolveTargets() async {
    if (selectedTarget != scanLanTarget) {
      return [
        (await InternetAddress.lookup(
          selectedTarget,
        ).timeout(const Duration(seconds: 5))).first.address,
      ];
    }
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
    );
    final local = interfaces
        .expand((interface) => interface.addresses)
        .where(
          (address) =>
              !address.isLoopback &&
              RegExp(
                r'^(10\.|192\.168\.|172\.(1[6-9]|2\d|3[01])\.)',
              ).hasMatch(address.address),
        )
        .firstOrNull;
    if (local == null) {
      throw const SocketException('Connect to a private IPv4 LAN first.');
    }
    final prefix = local.address.substring(0, local.address.lastIndexOf('.'));
    return List.generate(254, (index) => '$prefix.${index + 1}');
  }

  List<int> selectedPorts() => switch (portMode) {
    PortSelectionMode.common => List.of(discoveryPorts),
    PortSelectionMode.custom => parsePorts(ports.text),
    PortSelectionMode.all => List.generate(65535, (index) => index + 1),
  };

  Future<void> scan() async {
    if (scanning) return;
    final scanPorts = selectedPorts();
    if (scanPorts.isEmpty) return;
    setState(() {
      scanning = true;
      checked = 0;
      total = 0;
      targetsChecked = 0;
      lastScannedPorts = List.unmodifiable(scanPorts);
      results.clear();
    });
    try {
      final scanTargets = await resolveTargets();
      if (scanTargets.isEmpty) throw const FormatException('No valid targets.');
      if (mounted) {
        setState(() => total = scanTargets.length * scanPorts.length);
      }
      for (final address in scanTargets) {
        final open = <int>[];
        var reachable = false;
        for (var offset = 0; offset < scanPorts.length; offset += 96) {
          final batch = scanPorts.skip(offset).take(96).toList();
          final probes = await Future.wait(
            batch.map(
              (port) async => (port: port, result: await _probe(address, port)),
            ),
          );
          open.addAll([
            for (final probe in probes)
              if (probe.result.open) probe.port,
          ]);
          reachable =
              reachable || probes.any((probe) => probe.result.reachable);
          if (mounted) {
            setState(() {
              checked += batch.length;
              if (open.isNotEmpty) {
                results[address] = List.of(open)..sort();
              }
            });
          }
        }
        if (mounted) setState(() => targetsChecked++);
        if (reachable) {
          if (widget.recordInLiveInventory && open.isNotEmpty) {
            widget.liveInventory.observePorts(address, open);
          }
          widget.onResults?.call(
            ScannedHost(
              address,
              address,
              List.of(open),
              checkedPorts: List.of(scanPorts),
            ),
          );
        }
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Scan failed: $error')));
      }
    }
    if (mounted) setState(() => scanning = false);
  }

  @override
  Widget build(BuildContext context) {
    final discoveredIps = {
      if (widget.initialHost.isNotEmpty) widget.initialHost,
      ...widget.liveInventory.devices.map((device) => device.ip),
    }.toList()..sort(compareIpv4);
    return Scaffold(
      appBar: AppBar(title: const Text('Port scanner')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          DropdownButtonFormField<String>(
            initialValue: selectedTarget,
            decoration: const InputDecoration(labelText: 'IP'),
            items: [
              const DropdownMenuItem(
                value: scanLanTarget,
                child: Text('Scan LAN'),
              ),
              ...discoveredIps.map(
                (ip) => DropdownMenuItem(
                  value: ip,
                  child: Text(
                    ip,
                    style: const TextStyle(fontFamily: 'monospace'),
                  ),
                ),
              ),
            ],
            onChanged: scanning
                ? null
                : (value) => setState(() => selectedTarget = value!),
          ),
          const SizedBox(height: 12),
          SegmentedButton<PortSelectionMode>(
            segments: const [
              ButtonSegment(
                value: PortSelectionMode.custom,
                label: Text('Single port'),
              ),
              ButtonSegment(
                value: PortSelectionMode.common,
                label: Text('Common ports'),
              ),
              ButtonSegment(
                value: PortSelectionMode.all,
                label: Text('All ports'),
              ),
            ],
            selected: {portMode},
            onSelectionChanged: scanning
                ? null
                : (selection) => setState(() => portMode = selection.first),
          ),
          const SizedBox(height: 8),
          Text(
            portMode == PortSelectionMode.common
                ? '${discoveryPorts.length} common ports selected. '
                      'A LAN scan checks each port against every LAN address.'
                : portMode == PortSelectionMode.all
                ? '65,535 ports selected for the chosen target.'
                : '${selectedPorts().length} custom ports selected.',
            style: const TextStyle(color: secondary, fontSize: 12),
          ),
          if (portMode == PortSelectionMode.custom) ...[
            const SizedBox(height: 12),
            TextField(
              controller: ports,
              enabled: !scanning,
              decoration: const InputDecoration(
                labelText: 'Port',
                hintText: '443',
              ),
            ),
          ],
          if (portMode == PortSelectionMode.all) ...[
            const SizedBox(height: 8),
            const Text(
              'A full scan can take a long time, especially across a LAN or IP list.',
              style: TextStyle(color: warning, fontSize: 12),
            ),
          ],
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: scanning ? null : scan,
            icon: const Icon(Icons.radar_rounded),
            label: Text(
              scanning ? '$checked / $total connection checks' : 'SCAN',
            ),
          ),
          if (scanning && total > 0) ...[
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: checked / total,
              color: accent,
              backgroundColor: border,
            ),
          ],
          const SizedBox(height: 18),
          if (!scanning && targetsChecked > 0) ...[
            Text(
              formatPortScanSummary(
                addressesChecked: targetsChecked,
                checkedPorts: lastScannedPorts,
                hostsWithOpenPorts: results.length,
              ),
              style: TextStyle(
                color: results.isEmpty ? secondary : accent,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
          ],
          PortScanResults(results: results),
          if (!scanning && checked > 0 && results.isEmpty)
            const EmptyMessage(
              icon: Icons.block_rounded,
              text: 'No selected TCP ports were open.',
            ),
          if (!scanning &&
              results.isNotEmpty &&
              widget.onReviewResults != null) ...[
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  widget.onReviewResults?.call();
                },
                icon: const Icon(Icons.save_alt_rounded),
                label: const Text('SAVE OR MERGE RESULTS'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

const portScanCopyTipPreferenceKey = 'netforge.port_scan.copy_tip_completed';

class PortScanResults extends StatefulWidget {
  const PortScanResults({super.key, required this.results});

  final Map<String, List<int>> results;

  @override
  State<PortScanResults> createState() => _PortScanResultsState();
}

class _PortScanResultsState extends State<PortScanResults> {
  bool showCopyTip = false;

  @override
  void initState() {
    super.initState();
    loadCopyTip();
  }

  Future<void> loadCopyTip() async {
    final preferences = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      showCopyTip = preferences.getBool(portScanCopyTipPreferenceKey) != true;
    });
  }

  Future<void> copy(String text, String message) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted && showCopyTip) setState(() => showCopyTip = false);
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(portScanCopyTipPreferenceKey, true);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final entries =
        widget.results.entries
            .where((entry) => entry.value.isNotEmpty)
            .map(
              (entry) =>
                  (ip: entry.key, ports: entry.value.toSet().toList()..sort()),
            )
            .toList()
          ..sort((left, right) => compareIpv4(left.ip, right.ip));
    return Column(
      children: [
        if (showCopyTip && entries.isNotEmpty)
          Container(
            key: const ValueKey('port-scan-copy-tip'),
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: .08),
              border: Border.all(color: accent.withValues(alpha: .45)),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.lightbulb_outline_rounded, color: accent, size: 18),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Tip: Hold the port list to copy all ports, or hold one '
                    'port to copy it.',
                    style: TextStyle(color: secondary, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        ...entries.map(
          (entry) => ExpansionTile(
            leading: const Icon(Icons.check_circle_rounded, color: accent),
            title: Text(
              entry.ip,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontWeight: FontWeight.w900,
              ),
            ),
            subtitle: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onLongPress: () => copy(
                entry.ports.join(', '),
                'Copied all ${entry.ports.length} open ports',
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  entry.ports.join(', '),
                  style: const TextStyle(fontFamily: 'monospace'),
                ),
              ),
            ),
            children: entry.ports
                .map(
                  (port) => ListTile(
                    title: Text(
                      '$port',
                      style: const TextStyle(fontFamily: 'monospace'),
                    ),
                    onLongPress: () => copy('$port', 'Copied port $port'),
                  ),
                )
                .toList(),
          ),
        ),
      ],
    );
  }
}

class ScannedHost {
  const ScannedHost(
    this.ip,
    this.hostname,
    this.ports, {
    this.mac = '',
    this.checkedPorts = const [],
  });
  final String ip;
  final String hostname;
  final List<int> ports;
  final String mac;
  final List<int> checkedPorts;

  DeviceRecord toRecord() => DeviceRecord(
    ip: ip,
    mac: mac,
    name: hostname == ip ? '' : hostname,
    product: guessProduct(ports, hostname: hostname, mac: mac),
    ports: List.of(ports),
  );
}

ScannedHost mergePortScanObservation(
  ScannedHost observation, {
  ScannedHost? previous,
  DeviceRecord? saved,
}) {
  final previousHostname = previous?.hostname ?? '';
  final hostname =
      observation.hostname.isNotEmpty && observation.hostname != observation.ip
      ? observation.hostname
      : previousHostname.isNotEmpty && previousHostname != observation.ip
      ? previousHostname
      : saved?.name.isNotEmpty == true
      ? saved!.name
      : observation.ip;
  final mac = isUsableMacAddress(observation.mac)
      ? normalizeMacAddress(observation.mac)
      : isUsableMacAddress(previous?.mac ?? '')
      ? normalizeMacAddress(previous!.mac)
      : isUsableMacAddress(saved?.mac ?? '')
      ? normalizeMacAddress(saved!.mac)
      : '';
  final incomingChecked = observation.checkedPorts.toSet();
  if (incomingChecked.isEmpty) {
    final openPorts = observation.ports.toSet().toList()..sort();
    return ScannedHost(
      observation.ip,
      hostname,
      openPorts,
      mac: mac,
      checkedPorts: const [],
    );
  }

  final openPorts = {...?saved?.ports, ...?previous?.ports}
    ..removeAll(incomingChecked)
    ..addAll(observation.ports);
  final checkedPorts = {...?previous?.checkedPorts, ...incomingChecked}.toList()
    ..sort();
  return ScannedHost(
    observation.ip,
    hostname,
    openPorts.toList()..sort(),
    mac: mac,
    checkedPorts: checkedPorts,
  );
}

bool addObservedOpenPorts(
  DeviceRecord device,
  ScannedHost observation, {
  DateTime? observedAt,
}) {
  final mergedPorts = {...device.ports, ...observation.ports}.toList()..sort();
  if (samePorts(device.ports, mergedPorts)) return false;
  device
    ..ports = mergedPorts
    ..lastSeen = observedAt ?? DateTime.now();
  return true;
}

const discoveryPorts = [
  22,
  53,
  80,
  139,
  443,
  445,
  548,
  631,
  5037,
  5555,
  8000,
  8080,
  8443,
  9100,
];

Future<List<ScannedHost>> discoverLan({
  void Function(int checked)? onProgress,
}) async {
  final interfaces = await NetworkInterface.list(
    type: InternetAddressType.IPv4,
  );
  final local = interfaces
      .expand((interface) => interface.addresses)
      .where(
        (address) =>
            !address.isLoopback &&
            RegExp(
              r'^(10\.|192\.168\.|172\.(1[6-9]|2\d|3[01])\.)',
            ).hasMatch(address.address),
      )
      .firstOrNull;
  if (local == null) {
    throw const SocketException('Connect to a private IPv4 LAN first.');
  }
  final prefix = local.address.substring(0, local.address.lastIndexOf('.'));
  final candidates = List.generate(254, (index) => '$prefix.${index + 1}');
  final found = <ScannedHost>[];
  var checked = 0;
  for (var offset = 0; offset < candidates.length; offset += 24) {
    await Future.wait(
      candidates.skip(offset).take(24).map((ip) async {
        final results = await Future.wait(
          discoveryPorts.map((port) => _probe(ip, port)),
        );
        final ports = <int>[
          for (var index = 0; index < results.length; index++)
            if (results[index].open) discoveryPorts[index],
        ];
        final reachable =
            ip == local.address || results.any((result) => result.reachable);
        if (reachable) {
          var hostname = ip;
          try {
            hostname = (await InternetAddress(
              ip,
            ).reverse().timeout(const Duration(milliseconds: 600))).host;
          } catch (_) {}
          found.add(
            ScannedHost(ip, hostname, ports, checkedPorts: discoveryPorts),
          );
        }
        checked++;
        onProgress?.call(checked);
      }),
    );
  }
  final macs = await discoverNeighborMacs();
  final foundByIp = {for (final host in found) host.ip: host};
  for (final entry in macs.entries) {
    if (entry.key.startsWith('$prefix.')) {
      foundByIp.putIfAbsent(
        entry.key,
        () => ScannedHost(
          entry.key,
          entry.key,
          const [],
          mac: entry.value,
          checkedPorts: discoveryPorts,
        ),
      );
    }
  }
  final resolved =
      foundByIp.values
          .map(
            (host) => ScannedHost(
              host.ip,
              host.hostname,
              host.ports,
              mac: macs[host.ip] ?? host.mac,
              checkedPorts: host.checkedPorts,
            ),
          )
          .toList()
        ..sort((a, b) => lastOctet(a.ip).compareTo(lastOctet(b.ip)));
  return resolved;
}

Future<Map<String, String>> discoverNeighborMacs() async {
  final output = StringBuffer();
  final nativeAddresses = <String, String>{};
  if (Platform.isAndroid) {
    try {
      final native =
          await const MethodChannel(
            'netforge/device_status',
          ).invokeMapMethod<String, String>('getNeighborMacs') ??
          const <String, String>{};
      for (final entry in native.entries) {
        if (InternetAddress.tryParse(entry.key)?.type ==
                InternetAddressType.IPv4 &&
            isUsableMacAddress(entry.value)) {
          nativeAddresses[entry.key] = normalizeMacAddress(entry.value);
        }
      }
    } on PlatformException {
      // MAC discovery is best effort. Android 10+ normally returns no entries
      // because regular apps cannot read the system neighbor table.
    }
  } else {
    try {
      final arpFile = File('/proc/net/arp');
      if (await arpFile.exists()) output.writeln(await arpFile.readAsString());
    } catch (_) {}
  }
  final commands = <(String, List<String>)>[];
  if (Platform.isAndroid) {
    commands.add(('/system/bin/ip', const ['neighbor', 'show']));
  } else if (Platform.isLinux) {
    commands
      ..add((
        _firstAvailableExecutable(const ['/usr/sbin/ip', '/sbin/ip'], 'ip'),
        const ['neighbor', 'show'],
      ))
      ..add((
        _firstAvailableExecutable(const ['/usr/sbin/arp'], 'arp'),
        const ['-an'],
      ));
  } else if (Platform.isMacOS) {
    commands.add((
      _firstAvailableExecutable(const ['/usr/sbin/arp'], 'arp'),
      const ['-an'],
    ));
  } else if (Platform.isWindows) {
    commands.add(('arp', const ['-a']));
  }
  final commandOutputs = await Future.wait(
    commands.map((command) => _neighborCommandOutput(command.$1, command.$2)),
  );
  for (final commandOutput in commandOutputs) {
    if (commandOutput.isNotEmpty) output.writeln(commandOutput);
  }
  return {...nativeAddresses, ...parseNeighborMacs(output.toString())};
}

String _firstAvailableExecutable(List<String> paths, String fallback) =>
    paths.firstWhere((path) => File(path).existsSync(), orElse: () => fallback);

Future<String> _neighborCommandOutput(
  String executable,
  List<String> arguments,
) async {
  try {
    final result = await Process.run(
      executable,
      arguments,
    ).timeout(const Duration(seconds: 2));
    return '${result.stdout}';
  } catch (_) {
    return '';
  }
}

Map<String, String> parseNeighborMacs(String output) {
  final addresses = <String, String>{};
  final ipPattern = RegExp(r'\b(?:\d{1,3}\.){3}\d{1,3}\b');
  final macPattern = RegExp(r'\b(?:[0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2}\b');
  for (final line in output.split('\n')) {
    final ip = ipPattern.firstMatch(line)?.group(0);
    final mac = macPattern.firstMatch(line)?.group(0);
    if (ip != null &&
        InternetAddress.tryParse(ip)?.type == InternetAddressType.IPv4 &&
        mac != null &&
        isUsableMacAddress(mac)) {
      addresses[ip] = normalizeMacAddress(mac);
    }
  }
  return addresses;
}

String normalizeMacAddress(String value) =>
    value.trim().replaceAll('-', ':').toUpperCase();

bool isUsableMacAddress(String value) {
  final normalized = normalizeMacAddress(value);
  if (!RegExp(r'^(?:[0-9A-F]{2}:){5}[0-9A-F]{2}$').hasMatch(normalized)) {
    return false;
  }
  return normalized != '00:00:00:00:00:00' && normalized != 'FF:FF:FF:FF:FF:FF';
}

Future<bool> pingHost(String ip) async {
  try {
    final arguments = Platform.isWindows
        ? ['-n', '1', '-w', '1500', ip]
        : Platform.isMacOS || Platform.isIOS
        ? ['-c', '1', '-W', '1500', ip]
        : ['-c', '1', '-W', '1', ip];
    final result = await Process.run(
      Platform.isAndroid ? '/system/bin/ping' : 'ping',
      arguments,
    ).timeout(const Duration(seconds: 3));
    if (result.exitCode == 0) return true;
  } catch (_) {}
  final probes = await Future.wait(
    discoveryPorts.take(6).map((port) => _probe(ip, port)),
  );
  return probes.any((probe) => probe.reachable);
}

class _Probe {
  const _Probe({required this.open, required this.reachable});
  final bool open;
  final bool reachable;
}

Future<_Probe> _probe(String ip, int port) async {
  try {
    final socket = await Socket.connect(
      ip,
      port,
      timeout: const Duration(milliseconds: 350),
    );
    socket.destroy();
    return const _Probe(open: true, reachable: true);
  } on SocketException catch (error) {
    return _Probe(
      open: false,
      reachable: const {61, 111, 10061}.contains(error.osError?.errorCode),
    );
  } catch (_) {
    return const _Probe(open: false, reachable: false);
  }
}

Future<DeviceCheckResult> checkHostAndListedPorts(
  String ip,
  List<int> listedPorts,
) async {
  final checkedPorts = {...discoveryPorts, ...listedPorts}.toList()..sort();
  final ping = pingHost(ip);
  final openPorts = <int>[];
  var reachableOnTcp = false;
  for (var offset = 0; offset < checkedPorts.length; offset += 96) {
    final batch = checkedPorts.skip(offset).take(96).toList();
    final probes = await Future.wait(
      batch.map((port) async => (port: port, result: await _probe(ip, port))),
    );
    openPorts.addAll([
      for (final probe in probes)
        if (probe.result.open) probe.port,
    ]);
    reachableOnTcp =
        reachableOnTcp || probes.any((probe) => probe.result.reachable);
  }
  final pingReachable = await ping;
  final reachable = reachableOnTcp || pingReachable;
  var mac = '';
  try {
    mac = (await discoverNeighborMacs())[ip] ?? '';
  } catch (_) {
    // Neighbor/MAC discovery is best effort and does not affect reachability.
  }
  return DeviceCheckResult(
    ip: ip,
    reachable: reachable,
    openPorts: openPorts.toSet().toList()..sort(),
    checkedPorts: checkedPorts,
    mac: mac,
  );
}

List<DeviceRecord> parseScanNotes(String text) {
  final ipPattern = RegExp(
    r'\b(?:25[0-5]|2[0-4]\d|1?\d?\d)(?:\.(?:25[0-5]|2[0-4]\d|1?\d?\d)){3}\b',
  );
  final macPattern = RegExp(r'\b(?:[0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2}\b');
  final devices = <String, DeviceRecord>{};
  for (final line in const LineSplitter().convert(text)) {
    final ipMatch = ipPattern.firstMatch(line);
    if (ipMatch == null) continue;
    final ip = ipMatch.group(0)!;
    final mac = macPattern.firstMatch(line)?.group(0)?.toUpperCase() ?? '';
    final portSection = RegExp(
      r'(?:ports?|tcp)\s*[:=]?\s*([0-9,\s-]+)',
      caseSensitive: false,
    ).firstMatch(line);
    final ports = portSection == null
        ? <int>[]
        : parsePorts(portSection.group(1)!);
    var label = line
        .replaceAll(ip, '')
        .replaceAll(macPattern, '')
        .replaceAll(
          RegExp(r'(?:ports?|tcp)\s*[:=]?\s*[0-9,\s-]+', caseSensitive: false),
          '',
        )
        .replaceAll(RegExp(r'[\[\](),|]+'), ' ')
        .trim();
    label = label.replaceAll(RegExp(r'\s{2,}'), ' ');
    final existing = devices[ip];
    if (existing == null) {
      devices[ip] = DeviceRecord(ip: ip, mac: mac, name: label, ports: ports);
    } else {
      if (existing.mac.isEmpty) existing.mac = mac;
      if (existing.name.isEmpty) existing.name = label;
      existing.ports = {...existing.ports, ...ports}.toList()..sort();
    }
  }
  return devices.values.toList()
    ..sort((a, b) => lastOctet(a.ip).compareTo(lastOctet(b.ip)));
}

List<int> parsePorts(String input) {
  final ports = <int>{};
  for (final item in input.split(',')) {
    final value = item.trim();
    if (value.contains('-')) {
      final bounds = value.split('-').map(int.tryParse).toList();
      if (bounds.length == 2 &&
          bounds[0] != null &&
          bounds[1] != null &&
          bounds[0]! >= 1 &&
          bounds[1]! <= 65535 &&
          bounds[1]! >= bounds[0]! &&
          bounds[1]! - bounds[0]! <= 65535) {
        for (var port = bounds[0]!; port <= bounds[1]!; port++) {
          ports.add(port);
        }
      }
    } else {
      final port = int.tryParse(value);
      if (port != null && port >= 1 && port <= 65535) ports.add(port);
    }
  }
  return ports.toList()..sort();
}

String serviceName(int port) {
  const names = {
    21: 'FTP',
    22: 'SSH',
    23: 'Telnet',
    25: 'SMTP',
    53: 'DNS',
    80: 'HTTP',
    139: 'NetBIOS',
    443: 'HTTPS',
    445: 'SMB',
    548: 'Apple file sharing',
    631: 'IPP printing',
    3389: 'Remote Desktop',
    5037: 'ADB server',
    5555: 'Android Debug Bridge',
    8080: 'HTTP alternate',
    8443: 'HTTPS alternate',
    9100: 'Printer',
  };
  return names[port] ?? 'Unknown service';
}

String guessProduct(List<int> ports, {String hostname = '', String mac = ''}) {
  final set = ports.toSet();
  final host = hostname.toLowerCase();
  if (host.contains('printer') ||
      host.contains('epson') ||
      host.contains('canon') ||
      host.contains('brother') ||
      host.contains('hp-')) {
    return 'Likely printer';
  }
  if (host.contains('roku') ||
      host.contains('tv') ||
      host.contains('chromecast')) {
    return 'Streaming or smart TV device';
  }
  if (host.contains('iphone') ||
      host.contains('ipad') ||
      host.contains('android') ||
      host.contains('phone')) {
    return 'Phone or tablet';
  }
  if (set.contains(5555) || set.contains(5037)) return 'Android / ADB device';
  if (set.contains(9100) || set.contains(631)) return 'Likely printer';
  if (set.contains(445) || set.contains(139)) return 'File-sharing device';
  if (set.contains(53)) return 'Router or DNS device';
  if (set.contains(548)) return 'Apple file-sharing device';
  if (set.any({80, 443, 8080, 8443}.contains)) return 'Web-enabled device';
  if (set.contains(22)) return 'SSH-enabled device';
  if (mac.isNotEmpty) return 'Identified LAN device';
  return 'Reachable network device';
}

bool samePorts(List<int> a, List<int> b) =>
    a.toSet().length == b.toSet().length && a.toSet().containsAll(b);

int lastOctet(String ip) => int.tryParse(ip.split('.').last) ?? 0;

String portableNetworkJson(NetworkMap network) =>
    const JsonEncoder.withIndent('  ').convert({
      'format': 'netforge.network',
      'version': 1,
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'network': network.toJson(),
    });

NetworkMap parseNetForgeFile(String contents) {
  try {
    final document = jsonDecode(contents);
    if (document is! Map<String, dynamic> ||
        document['format'] != 'netforge.network' ||
        document['version'] != 1 ||
        document['network'] is! Map<String, dynamic>) {
      throw const FormatException('This is not a supported .netforge file.');
    }
    return NetworkMap.fromJson(document['network'] as Map<String, dynamic>);
  } on FormatException {
    rethrow;
  } catch (_) {
    throw const FormatException('The .netforge file is damaged or incomplete.');
  }
}

String netForgeFileName(NetworkMap network) {
  final safeName = network.name
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  return '${safeName.isEmpty ? 'network' : safeName}.netforge';
}

String exportNetworkText(NetworkMap network) {
  final output = StringBuffer()
    ..writeln('LAN MAP: ${network.name}')
    ..writeln('SSID: ${network.ssid.isEmpty ? '-' : network.ssid}')
    ..writeln('Gateway: ${network.gateway.isEmpty ? '-' : network.gateway}')
    ..writeln('Subnet: ${network.subnet.isEmpty ? '-' : network.subnet}')
    ..writeln('Updated: ${network.updatedAt.toLocal()}')
    ..writeln('Notes: ${network.notes.isEmpty ? '-' : network.notes}')
    ..writeln()
    ..writeln('DEVICES (${network.devices.length})');
  for (final device in network.devices) {
    output
      ..writeln()
      ..writeln('${device.title} — ${device.ip}')
      ..writeln('  MAC: ${device.mac.isEmpty ? '-' : device.mac}')
      ..writeln('  Product: ${device.product.isEmpty ? '-' : device.product}')
      ..writeln(
        '  Ports: ${device.ports.isEmpty ? '-' : device.ports.join(', ')}',
      )
      ..writeln('  Notes: ${device.notes.isEmpty ? '-' : device.notes}');
  }
  return output.toString();
}

class _NetworkFormResult {
  const _NetworkFormResult(
    this.name,
    this.ssid,
    this.gateway,
    this.subnet,
    this.notes,
  );
  final String name;
  final String ssid;
  final String gateway;
  final String subnet;
  final String notes;
}

class _ImportResult {
  const _ImportResult(this.rawText, this.devices);
  final String rawText;
  final List<DeviceRecord> devices;
}

Future<_NetworkFormResult?> _editNetworkDialog(
  BuildContext context, {
  String initialName = '',
  String initialSsid = '',
  String initialGateway = '',
  String initialSubnet = '',
  String initialNotes = '',
}) => showDialog<_NetworkFormResult>(
  context: context,
  builder: (context) => _NetworkEditorDialog(
    initialName: initialName,
    initialSsid: initialSsid,
    initialGateway: initialGateway,
    initialSubnet: initialSubnet,
    initialNotes: initialNotes,
  ),
);

class _NetworkEditorDialog extends StatefulWidget {
  const _NetworkEditorDialog({
    required this.initialName,
    required this.initialSsid,
    required this.initialGateway,
    required this.initialSubnet,
    required this.initialNotes,
  });

  final String initialName;
  final String initialSsid;
  final String initialGateway;
  final String initialSubnet;
  final String initialNotes;

  @override
  State<_NetworkEditorDialog> createState() => _NetworkEditorDialogState();
}

class _NetworkEditorDialogState extends State<_NetworkEditorDialog> {
  late final name = TextEditingController(text: widget.initialName);
  late final ssid = TextEditingController(text: widget.initialSsid);
  late final gateway = TextEditingController(text: widget.initialGateway);
  late final subnet = TextEditingController(text: widget.initialSubnet);
  late final notes = TextEditingController(text: widget.initialNotes);

  @override
  void dispose() {
    name.dispose();
    ssid.dispose();
    gateway.dispose();
    subnet.dispose();
    notes.dispose();
    super.dispose();
  }

  void save() {
    if (name.text.trim().isEmpty) return;
    FocusScope.of(context).unfocus();
    Navigator.pop(
      context,
      _NetworkFormResult(
        name.text.trim(),
        ssid.text.trim(),
        gateway.text.trim(),
        subnet.text.trim(),
        notes.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.initialName.isEmpty ? 'New network' : 'Network details'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: name,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Network name *'),
            onSubmitted: (_) => save(),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: ssid,
            decoration: const InputDecoration(labelText: 'Wi-Fi SSID'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: gateway,
            decoration: const InputDecoration(labelText: 'Gateway IP'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: subnet,
            decoration: const InputDecoration(
              labelText: 'Subnet',
              hintText: '192.168.1.0/24',
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: notes,
            maxLines: 4,
            decoration: const InputDecoration(labelText: 'Notes'),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () {
          FocusScope.of(context).unfocus();
          Navigator.pop(context);
        },
        child: const Text('CANCEL'),
      ),
      FilledButton(onPressed: save, child: const Text('SAVE')),
    ],
  );
}

class _DeviceNameDialog extends StatefulWidget {
  const _DeviceNameDialog({required this.initialName});

  final String initialName;

  @override
  State<_DeviceNameDialog> createState() => _DeviceNameDialogState();
}

class _DeviceNameDialogState extends State<_DeviceNameDialog> {
  late final controller = TextEditingController(text: widget.initialName);

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void save() {
    final name = controller.text.trim();
    if (name.isEmpty) return;
    FocusScope.of(context).unfocus();
    Navigator.pop(context, name);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Name this device'),
    content: TextField(
      controller: controller,
      autofocus: true,
      decoration: const InputDecoration(
        labelText: 'Device name',
        hintText: 'Office printer',
      ),
      onSubmitted: (_) => save(),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('CANCEL'),
      ),
      FilledButton(onPressed: save, child: const Text('SAVE')),
    ],
  );
}

Future<DeviceRecord?> deviceEditor(
  BuildContext context,
  DeviceRecord? existing,
) async {
  final ip = TextEditingController(text: existing?.ip ?? '');
  final mac = TextEditingController(text: existing?.mac ?? '');
  final name = TextEditingController(text: existing?.name ?? '');
  final product = TextEditingController(text: existing?.product ?? '');
  final ports = TextEditingController(text: existing?.ports.join(',') ?? '');
  final notes = TextEditingController(text: existing?.notes ?? '');
  final result = await showDialog<DeviceRecord>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(existing == null ? 'Add device' : 'Edit device'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: ip,
              decoration: const InputDecoration(labelText: 'IP address *'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: mac,
              decoration: const InputDecoration(labelText: 'MAC address'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: name,
              decoration: const InputDecoration(labelText: 'Your device label'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: product,
              decoration: const InputDecoration(
                labelText: 'Product / suspected type',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: ports,
              decoration: const InputDecoration(
                labelText: 'Open ports',
                hintText: '22,80,443',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: notes,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Notes'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('CANCEL'),
        ),
        FilledButton(
          onPressed: () {
            if (InternetAddress.tryParse(ip.text.trim()) == null) return;
            Navigator.pop(
              context,
              DeviceRecord(
                ip: ip.text.trim(),
                mac: mac.text.trim().toUpperCase(),
                name: name.text.trim(),
                product: product.text.trim(),
                ports: parsePorts(ports.text),
                notes: notes.text.trim(),
                isDead: existing?.isDead ?? false,
                firstSeen: existing?.firstSeen,
                lastSeen: existing?.lastSeen,
              ),
            );
          },
          child: const Text('SAVE'),
        ),
      ],
    ),
  );
  await Future<void>.delayed(const Duration(milliseconds: 350));
  for (final controller in [ip, mac, name, product, ports, notes]) {
    controller.dispose();
  }
  return result;
}

Future<void> showDevice(
  BuildContext context,
  DeviceRecord device, {
  ScannedHost? fresh,
  VoidCallback? onRename,
  VoidCallback? onEdit,
  VoidCallback? onPing,
  required VoidCallback onScanAllPorts,
  VoidCallback? onDelete,
  VoidCallback? onAddNewPorts,
  VoidCallback? onApplyPorts,
  VoidCallback? onApplyMac,
  VoidCallback? onApplyHostname,
}) async {
  final savedPorts = device.ports.toSet();
  final latestPorts = fresh?.ports.toSet() ?? const <int>{};
  final newPorts = latestPorts.difference(savedPorts);
  final closedPorts = savedPorts.difference(latestPorts);
  final action = await showModalBottomSheet<_DeviceSheetAction>(
    context: context,
    isScrollControlled: true,
    backgroundColor: surface,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              onTap: onRename == null
                  ? null
                  : () {
                      Navigator.pop(context, _DeviceSheetAction.rename);
                    },
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        device.name.isEmpty
                            ? 'Unknown network device'
                            : device.name,
                        style: const TextStyle(
                          fontSize: 23,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    if (onRename != null)
                      const Icon(Icons.edit_outlined, color: accent),
                  ],
                ),
              ),
            ),
            if (onRename != null)
              const Text(
                'Tap the name to rename this device',
                style: TextStyle(color: secondary, fontSize: 11),
              ),
            const SizedBox(height: 16),
            DetailRow(label: 'IP ADDRESS', value: device.ip),
            DetailRow(
              label: 'MAC ADDRESS',
              value: device.mac.isEmpty ? 'Not documented' : device.mac,
            ),
            if (onApplyMac != null) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: warning.withValues(alpha: .08),
                  border: Border.all(color: warning),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'DISCOVERED MAC\n${normalizeMacAddress(fresh!.mac)}',
                  style: const TextStyle(
                    color: warning,
                    fontWeight: FontWeight.w800,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(context, _DeviceSheetAction.applyMac);
                  },
                  icon: const Icon(Icons.fingerprint_rounded),
                  label: Text(
                    device.mac.isEmpty
                        ? 'SAVE DISCOVERED MAC'
                        : 'REPLACE SAVED MAC',
                  ),
                ),
              ),
            ],
            DetailRow(
              label: 'PRODUCT',
              value: device.product.isEmpty ? 'Unidentified' : device.product,
            ),
            if (fresh == null)
              DetailRow(
                label: 'SAVED PORTS',
                value: device.ports.isEmpty ? 'None' : device.ports.join(', '),
              )
            else
              PortStatusReview(saved: device.ports, latest: fresh.ports),
            if (device.notes.isNotEmpty)
              DetailRow(label: 'NOTES', value: device.notes),
            const SizedBox(height: 12),
            if (onApplyHostname != null) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: warning.withValues(alpha: .08),
                  border: Border.all(color: warning),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'DISCOVERED HOSTNAME\n${fresh!.hostname}',
                  style: const TextStyle(
                    color: warning,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(context, _DeviceSheetAction.applyHostname);
                  },
                  icon: const Icon(Icons.dns_outlined),
                  label: const Text('USE DISCOVERED HOSTNAME'),
                ),
              ),
              const SizedBox(height: 10),
            ],
            if (fresh != null &&
                (newPorts.isNotEmpty || closedPorts.isNotEmpty)) ...[
              if (newPorts.isNotEmpty && onAddNewPorts != null)
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(context, _DeviceSheetAction.addNewPorts);
                    },
                    icon: const Icon(Icons.add_rounded),
                    label: Text(
                      closedPorts.isEmpty
                          ? 'ADD NEW PORTS'
                          : 'ADD NEW · KEEP CLOSED PORTS',
                    ),
                  ),
                ),
              if (newPorts.isNotEmpty && onAddNewPorts != null)
                const SizedBox(height: 8),
              if (onApplyPorts != null)
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    style: closedPorts.isEmpty
                        ? null
                        : FilledButton.styleFrom(backgroundColor: danger),
                    onPressed: () {
                      Navigator.pop(context, _DeviceSheetAction.applyPorts);
                    },
                    icon: Icon(
                      closedPorts.isEmpty
                          ? Icons.sync_rounded
                          : Icons.delete_sweep_outlined,
                    ),
                    label: Text(
                      closedPorts.isEmpty
                          ? 'SAVE LATEST PORTS'
                          : 'SYNC · REMOVE CLOSED PORTS',
                    ),
                  ),
                ),
              const SizedBox(height: 10),
            ],
            if (onPing != null) ...[
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(context, _DeviceSheetAction.ping);
                  },
                  icon: const Icon(Icons.network_ping_rounded),
                  label: const Text('REFRESH LISTED PORTS / CHECK ALIVE'),
                ),
              ),
              const SizedBox(height: 10),
            ],
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () {
                  Navigator.pop(context, _DeviceSheetAction.scanAllPorts);
                },
                icon: const Icon(Icons.radar_rounded),
                label: const Text('PORT SCANNER'),
              ),
            ),
            const SizedBox(height: 10),
            if (onEdit != null) ...[
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(context, _DeviceSheetAction.edit);
                  },
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('EDIT'),
                ),
              ),
              const SizedBox(height: 10),
            ],
            if (onDelete != null)
              SizedBox(
                width: double.infinity,
                child: TextButton.icon(
                  style: TextButton.styleFrom(foregroundColor: danger),
                  onPressed: () async {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (dialogContext) => AlertDialog(
                        title: const Text('Delete this device?'),
                        content: Text(
                          '${device.title} (${device.ip}) will be removed from this saved network.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () =>
                                Navigator.pop(dialogContext, false),
                            child: const Text('CANCEL'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.pop(dialogContext, true),
                            style: FilledButton.styleFrom(
                              backgroundColor: danger,
                            ),
                            child: const Text('DELETE'),
                          ),
                        ],
                      ),
                    );
                    if (confirmed == true && context.mounted) {
                      Navigator.pop(context);
                      await Future<void>.delayed(
                        const Duration(milliseconds: 350),
                      );
                      onDelete();
                    }
                  },
                  icon: const Icon(Icons.delete_outline_rounded),
                  label: const Text('DELETE DEVICE'),
                ),
              ),
          ],
        ),
      ),
    ),
  );

  if (!context.mounted) return;
  switch (action) {
    case _DeviceSheetAction.rename:
      onRename?.call();
    case _DeviceSheetAction.edit:
      onEdit?.call();
    case _DeviceSheetAction.scanAllPorts:
      onScanAllPorts();
    case _DeviceSheetAction.ping:
      onPing?.call();
    case _DeviceSheetAction.addNewPorts:
      onAddNewPorts?.call();
    case _DeviceSheetAction.applyPorts:
      onApplyPorts?.call();
    case _DeviceSheetAction.applyMac:
      onApplyMac?.call();
    case _DeviceSheetAction.applyHostname:
      onApplyHostname?.call();
    case null:
      break;
  }
}

enum _DeviceSheetAction {
  rename,
  edit,
  scanAllPorts,
  ping,
  addNewPorts,
  applyPorts,
  applyMac,
  applyHostname,
}

class PortStatusReview extends StatelessWidget {
  const PortStatusReview({
    super.key,
    required this.saved,
    required this.latest,
  });

  final List<int> saved;
  final List<int> latest;

  @override
  Widget build(BuildContext context) {
    final savedSet = saved.toSet();
    final latestSet = latest.toSet();
    final stillOpen = savedSet.intersection(latestSet).toList()..sort();
    final newPorts = latestSet.difference(savedSet).toList()..sort();
    final closed = savedSet.difference(latestSet).toList()..sort();

    if (stillOpen.isEmpty && newPorts.isEmpty && closed.isEmpty) {
      return const DetailRow(label: 'PORT STATUS', value: 'No ports found');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (stillOpen.isNotEmpty)
          _PortStatusGroup(
            label: 'STILL OPEN',
            ports: stillOpen,
            color: accent,
          ),
        if (newPorts.isNotEmpty)
          _PortStatusGroup(
            label: 'NEW · NOT SAVED',
            ports: newPorts,
            color: warning,
          ),
        if (closed.isNotEmpty)
          _PortStatusGroup(
            label: 'NO LONGER OPEN · STILL SAVED',
            ports: closed,
            color: danger,
          ),
      ],
    );
  }
}

class _PortStatusGroup extends StatelessWidget {
  const _PortStatusGroup({
    required this.label,
    required this.ports,
    required this.color,
  });

  final String label;
  final List<int> ports;
  final Color color;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 9),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 10,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 5),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: ports
              .map(
                (port) => Chip(
                  visualDensity: VisualDensity.compact,
                  backgroundColor: color.withValues(alpha: .1),
                  side: BorderSide(color: color),
                  label: Text(
                    '$port',
                    style: TextStyle(
                      color: color,
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              )
              .toList(),
        ),
      ],
    ),
  );
}

Future<void> showDnsLookup(
  BuildContext context,
  LiveInventory liveInventory, {
  String initialInput = '',
  bool recordInLiveInventory = true,
  void Function(String ip, String hostname)? onResult,
}) async {
  final input = TextEditingController(text: initialInput);
  String result = '';
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: surface,
    builder: (context) => StatefulBuilder(
      builder: (context, setModalState) => Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          20,
          20,
          MediaQuery.viewInsetsOf(context).bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: input,
              decoration: const InputDecoration(
                labelText: 'Hostname or IP address',
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () async {
                final value = input.text.trim();
                if (value.isEmpty) {
                  setModalState(
                    () => result = 'Enter a hostname or IP address.',
                  );
                  return;
                }
                try {
                  final address = InternetAddress.tryParse(value);
                  final answers = address == null
                      ? await InternetAddress.lookup(
                          value,
                        ).timeout(const Duration(seconds: 8))
                      : [
                          await address.reverse().timeout(
                            const Duration(seconds: 8),
                          ),
                        ];
                  for (final answer in answers) {
                    if (answer.host != answer.address) {
                      if (recordInLiveInventory) {
                        liveInventory.observeHostname(
                          answer.address,
                          answer.host,
                        );
                      }
                      onResult?.call(answer.address, answer.host);
                    }
                  }
                  if (!context.mounted) return;
                  setModalState(
                    () => result = answers
                        .map(
                          (answer) => answer.host == answer.address
                              ? answer.address
                              : '${answer.address} — ${answer.host}',
                        )
                        .join('\n'),
                  );
                } on SocketException {
                  if (!context.mounted) return;
                  setModalState(() => result = dnsLookupFailureMessage(value));
                } on TimeoutException {
                  if (!context.mounted) return;
                  setModalState(
                    () => result =
                        'The DNS lookup timed out. Check your network connection and try again.',
                  );
                }
              },
              child: const Text('LOOK UP'),
            ),
            if (result.isNotEmpty) ...[
              const SizedBox(height: 14),
              SelectableText(result),
            ],
          ],
        ),
      ),
    ),
  );
  await Future<void>.delayed(const Duration(milliseconds: 350));
  input.dispose();
}

String dnsLookupFailureMessage(String value) {
  if (InternetAddress.tryParse(value) != null) {
    return 'No reverse DNS hostname was found for $value.\n'
        'This device may not publish a hostname, but it can still be online.';
  }
  return 'Could not resolve “$value”. Check the hostname and your network connection.';
}

Future<void> showSubnetCalculator(
  BuildContext context, {
  String initialCidr = '192.168.1.0/24',
}) async {
  final input = TextEditingController(text: initialCidr);
  String result = '';
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: surface,
    builder: (context) => StatefulBuilder(
      builder: (context, setModalState) => Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          20,
          20,
          MediaQuery.viewInsetsOf(context).bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: input,
              decoration: const InputDecoration(labelText: 'IPv4 CIDR'),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () {
                try {
                  final parts = input.text.trim().split('/');
                  final octets = parts[0].split('.').map(int.parse).toList();
                  final cidr = int.parse(parts[1]);
                  if (octets.length != 4 ||
                      octets.any((value) => value < 0 || value > 255) ||
                      cidr < 0 ||
                      cidr > 32) {
                    throw const FormatException();
                  }
                  final ip = octets.fold<int>(
                    0,
                    (value, octet) => (value << 8) | octet,
                  );
                  final mask = cidr == 0
                      ? 0
                      : (0xFFFFFFFF << (32 - cidr)) & 0xFFFFFFFF;
                  final network = ip & mask;
                  final broadcast = network | (~mask & 0xFFFFFFFF);
                  setModalState(
                    () => result =
                        'Network: ${formatIp(network)}\n'
                        'Mask: ${formatIp(mask)}\n'
                        'Broadcast: ${formatIp(broadcast)}',
                  );
                } catch (_) {
                  setModalState(() => result = 'Enter a valid IPv4 CIDR.');
                }
              },
              child: const Text('CALCULATE'),
            ),
            if (result.isNotEmpty) ...[
              const SizedBox(height: 14),
              SelectableText(result),
            ],
          ],
        ),
      ),
    ),
  );
  await Future<void>.delayed(const Duration(milliseconds: 350));
  input.dispose();
}

String formatIp(int value) =>
    '${(value >> 24) & 255}.${(value >> 16) & 255}.${(value >> 8) & 255}.${value & 255}';

class CurrentWifiCard extends StatelessWidget {
  const CurrentWifiCard({
    super.key,
    required this.connection,
    required this.loading,
    required this.onRefresh,
    required this.onRequestPermissions,
    required this.onOpenLocationSettings,
  });

  final Map<String, dynamic> connection;
  final bool loading;
  final VoidCallback onRefresh;
  final VoidCallback onRequestPermissions;
  final VoidCallback onOpenLocationSettings;

  @override
  Widget build(BuildContext context) {
    final ssid = connection['ssid'] as String?;
    final gateway = connection['gateway'] as String?;
    final bssid = connection['bssid'] as String?;
    final needsPermission = connection['permissionsRequired'] == true;
    final locationEnabled = connection['locationEnabled'] != false;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFF172A21), surface]),
        border: Border.all(color: const Color(0xFF31563B)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.wifi_rounded, color: accent),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'CURRENT WI-FI',
                  style: TextStyle(
                    color: secondary,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: .8,
                  ),
                ),
              ),
              IconButton(
                onPressed: loading ? null : onRefresh,
                tooltip: 'Refresh Wi-Fi details',
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
          Text(
            ssid ??
                (loading ? 'Reading connection…' : 'Wi-Fi name unavailable'),
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
          ),
          if (gateway != null || bssid != null) ...[
            const SizedBox(height: 8),
            if (gateway != null)
              Text(
                'Gateway  $gateway',
                style: const TextStyle(color: secondary),
              ),
            if (bssid != null)
              Text(
                'Access point  $bssid',
                style: const TextStyle(
                  color: secondary,
                  fontFamily: 'monospace',
                ),
              ),
          ],
          if (needsPermission) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onRequestPermissions,
                icon: const Icon(Icons.lock_open_rounded),
                label: const Text('ALLOW WI-FI NAME ACCESS'),
              ),
            ),
          ] else if (!locationEnabled) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onOpenLocationSettings,
                icon: const Icon(Icons.location_on_outlined),
                label: const Text('TURN ON LOCATION SERVICES'),
              ),
            ),
          ] else if (ssid == null && !loading) ...[
            const SizedBox(height: 8),
            const Text(
              'Android may require Location Services to be turned on before it reveals the connected Wi-Fi name.',
              style: TextStyle(color: secondary, fontSize: 11),
            ),
          ],
          if (loading) ...[
            const SizedBox(height: 10),
            const LinearProgressIndicator(
              color: accent,
              backgroundColor: border,
            ),
          ],
        ],
      ),
    );
  }
}

class SummaryCard extends StatelessWidget {
  const SummaryCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.onTap,
  });
  final String label;
  final String value;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: surface,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(15),
      side: const BorderSide(color: border),
    ),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: accent),
            const SizedBox(height: 14),
            Text(
              value,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
            ),
            Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(
                      color: secondary,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (onTap != null)
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: secondary,
                    size: 17,
                  ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

class NetworkTile extends StatelessWidget {
  const NetworkTile({
    super.key,
    required this.network,
    required this.onTap,
    this.onLongPress,
  });
  final NetworkMap network;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 9),
    child: ListTile(
      onTap: onTap,
      onLongPress: onLongPress,
      tileColor: surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: border),
      ),
      leading: const CircleAvatar(
        backgroundColor: Color(0xFF172A21),
        child: Icon(Icons.hub_rounded, color: accent),
      ),
      title: Text(
        network.name,
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
      subtitle: Text(
        '${network.devices.length} devices'
        '${network.ssid.isEmpty ? '' : ' · ${network.ssid}'}',
        style: const TextStyle(color: secondary),
      ),
      trailing: const Icon(Icons.chevron_right_rounded),
    ),
  );
}

class ReviewCard extends StatelessWidget {
  const ReviewCard({
    super.key,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.primary,
    required this.secondary,
    required this.onPrimary,
    required this.onSecondary,
  });
  final Color color;
  final String title;
  final String subtitle;
  final String primary;
  final String secondary;
  final VoidCallback onPrimary;
  final VoidCallback onSecondary;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .08),
      border: Border.all(color: color),
      borderRadius: BorderRadius.circular(13),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
        Text(
          subtitle,
          style: const TextStyle(color: Color(0xFF91A4B7), fontSize: 12),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: FilledButton(onPressed: onPrimary, child: Text(primary)),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton(
                onPressed: onSecondary,
                child: Text(secondary),
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

class ToolTile extends StatelessWidget {
  const ToolTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 9),
    child: ListTile(
      onTap: onTap,
      tileColor: surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: border),
      ),
      leading: Icon(icon, color: accent),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
      subtitle: Text(subtitle, style: const TextStyle(color: secondary)),
      trailing: const Icon(Icons.chevron_right_rounded),
    ),
  );
}

class SectionHeader extends StatelessWidget {
  const SectionHeader({super.key, required this.title, this.color});
  final String title;
  final Color? color;

  @override
  Widget build(BuildContext context) => Text(
    title,
    style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.w900),
  );
}

class InfoChip extends StatelessWidget {
  const InfoChip({super.key, required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    decoration: BoxDecoration(
      color: surface,
      border: Border.all(color: border),
      borderRadius: BorderRadius.circular(30),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: accent, size: 16),
        const SizedBox(width: 6),
        Text(text),
      ],
    ),
  );
}

class DetailRow extends StatelessWidget {
  const DetailRow({super.key, required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 110,
          child: Text(
            label,
            style: const TextStyle(
              color: secondary,
              fontSize: 10,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        Expanded(
          child: SelectableText(
            value,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    ),
  );
}

class EmptyMessage extends StatelessWidget {
  const EmptyMessage({super.key, required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(30),
    child: Column(
      children: [
        Icon(icon, color: secondary, size: 42),
        const SizedBox(height: 10),
        Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(color: secondary),
        ),
      ],
    ),
  );
}
