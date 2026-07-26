import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
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

class LiveDevice {
  LiveDevice({
    required this.ip,
    this.hostname = '',
    List<int>? ports,
    DateTime? lastSeen,
  }) : ports = ports ?? [],
       lastSeen = lastSeen ?? DateTime.now();

  final String ip;
  String hostname;
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

  void observeHostname(String ip, String hostname) {
    final current = _devices.putIfAbsent(ip, () => LiveDevice(ip: ip));
    current
      ..hostname = hostname
      ..lastSeen = DateTime.now();
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
  final networks = <NetworkMap>[];
  final liveInventory = LiveInventory();
  Map<String, dynamic> connection = {};
  int tab = 0;
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
    final result = await _editNetworkDialog(context);
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

  @override
  Widget build(BuildContext context) {
    if (!loaded) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: accent)),
      );
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
      ),
      NetworksPage(
        networks: networks,
        liveInventory: liveInventory,
        onOpen: openNetwork,
        onCreate: createNetwork,
        onChanged: save,
      ),
    ];
    return Scaffold(
      body: IndexedStack(index: tab, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (value) => setState(() => tab = value),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_rounded), label: 'Home'),
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
  }
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
    required this.onOpen,
    required this.onCreate,
    required this.onChanged,
  });

  final List<NetworkMap> networks;
  final LiveInventory liveInventory;
  final ValueChanged<NetworkMap> onOpen;
  final VoidCallback onCreate;
  final Future<void> Function() onChanged;

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
    final details = await _editNetworkDialog(
      context,
      initialName: 'Imported LAN',
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
    required this.onOpen,
    required this.onChanged,
  });
  final List<NetworkMap> networks;
  final LiveInventory liveInventory;
  final ValueChanged<NetworkMap> onOpen;
  final Future<void> Function() onChanged;

  @override
  State<QuickLanScanPanel> createState() => _QuickLanScanPanelState();
}

class _QuickLanScanPanelState extends State<QuickLanScanPanel> {
  final results = <ScannedHost>[];
  bool scanning = false;
  int checked = 0;
  String? error;

  Future<void> scan() async {
    if (scanning) return;
    setState(() {
      scanning = true;
      checked = 0;
      results.clear();
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
          results.addAll(found);
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
      initialName: 'Scanned LAN',
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
    if (mounted) widget.onOpen(network);
  }

  Future<void> showResult(ScannedHost host) async {
    final openTools = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: surface,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InkWell(
                onTap: () => Navigator.pop(context, true),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          host.ip,
                          style: const TextStyle(
                            color: accent,
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
                      const Icon(Icons.construction_rounded, color: accent),
                    ],
                  ),
                ),
              ),
              Text(
                host.hostname == host.ip
                    ? guessProduct(host.ports)
                    : host.hostname,
                style: const TextStyle(color: secondary),
              ),
              const SizedBox(height: 18),
              Text(
                'ALL KNOWN OPEN PORTS (${host.ports.length})',
                style: const TextStyle(
                  color: secondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              if (host.ports.isEmpty)
                const Text('No open ports found in this scan.')
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: host.ports
                      .map(
                        (port) => Chip(
                          label: Text('$port · ${serviceName(port)}'),
                          side: const BorderSide(color: border),
                        ),
                      )
                      .toList(),
                ),
            ],
          ),
        ),
      ),
    );
    if (openTools == true && mounted) await showResultTools(host);
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
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => SimplePortScanner(
            liveInventory: widget.liveInventory,
            initialHost: host.ip,
            onResults: (finding) {
              final index = results.indexOf(host);
              if (index < 0) return;
              final ports = {...host.ports, ...finding.ports}.toList()..sort();
              setState(() {
                results[index] = ScannedHost(host.ip, host.hostname, ports);
              });
            },
          ),
        ),
      );
    } else if (tool == 'dns') {
      await showDnsLookup(
        context,
        widget.liveInventory,
        initialInput: host.ip,
        onResult: (ip, hostname) {
          final index = results.indexOf(host);
          if (index < 0 || ip != host.ip) return;
          setState(() {
            results[index] = ScannedHost(host.ip, hostname, host.ports);
          });
        },
      );
    } else if (tool == 'subnet') {
      await showSubnetCalculator(context, initialCidr: '${host.ip}/24');
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const SectionHeader(title: 'Scan current LAN'),
      const SizedBox(height: 6),
      const Text(
        'Results appear below and remain unsaved until you choose Save Network.',
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
        Row(
          children: [
            Expanded(
              child: Text(
                '${results.length} devices found',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            TextButton.icon(
              onPressed: saveResults,
              icon: const Icon(Icons.save_outlined),
              label: const Text('SAVE NETWORK'),
            ),
          ],
        ),
        ...results.map(
          (host) => ListTile(
            onTap: () => showResult(host),
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.devices_rounded, color: accent),
            title: Text(
              host.ip,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontWeight: FontWeight.w800,
              ),
            ),
            subtitle: host.ports.isEmpty
                ? null
                : Text(
                    host.ports.join(', '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: secondary,
                      fontFamily: 'monospace',
                    ),
                  ),
            trailing: const Icon(Icons.chevron_right_rounded),
          ),
        ),
      ],
      if (!scanning && checked > 0 && results.isEmpty && error == null)
        const EmptyMessage(
          icon: Icons.search_off_rounded,
          text: 'No devices responded to the scan.',
        ),
    ],
  );
}

class NetworkWorkspace extends StatefulWidget {
  const NetworkWorkspace({
    super.key,
    required this.network,
    required this.onChanged,
    required this.liveInventory,
  });

  final NetworkMap network;
  final Future<void> Function() onChanged;
  final LiveInventory liveInventory;

  @override
  State<NetworkWorkspace> createState() => _NetworkWorkspaceState();
}

class _NetworkWorkspaceState extends State<NetworkWorkspace> {
  static const deviceChannel = MethodChannel('netforge/device_status');

  final refreshed = <String, ScannedHost>{};
  final missing = <String>{};
  final ignored = <String>{};
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
    final isInitialScan = !hasRefreshed && widget.network.devices.isEmpty;
    setState(() {
      scanning = true;
      hasRefreshed = false;
      checked = 0;
      refreshed.clear();
      missing.clear();
      ignored.clear();
    });
    try {
      final hosts = await discoverLan(
        onProgress: (value) {
          if (mounted && (value % 8 == 0 || value == 254)) {
            setState(() => checked = value);
          }
        },
      );
      if (!mounted) return;
      widget.liveInventory.observeHosts(hosts);
      if (isInitialScan && addFirstScanHosts(widget.network, hosts) > 0) {
        widget.network.updatedAt = DateTime.now();
        await widget.onChanged();
        if (!mounted) return;
      }
      final byIp = {for (final host in hosts) host.ip: host};
      final savedIps = widget.network.devices
          .map((device) => device.ip)
          .toSet();
      setState(() {
        refreshed.addAll(byIp);
        missing.addAll(savedIps.difference(byIp.keys.toSet()));
        checked = 254;
        scanning = false;
        hasRefreshed = true;
      });
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
    final controller = TextEditingController(text: device.name);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Name this device'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Device name',
            hintText: 'Office printer',
          ),
          onSubmitted: (value) => Navigator.pop(context, value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CANCEL'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('SAVE'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.isEmpty) return;
    device.name = name;
    await changed();
  }

  Future<void> markDeviceActive(DeviceRecord device) async {
    final live = widget.liveInventory.forIp(device.ip);
    device
      ..isDead = false
      ..lastSeen = DateTime.now();
    missing.remove(device.ip);
    refreshed[device.ip] = ScannedHost(
      device.ip,
      live?.hostname ?? device.name,
      live == null ? List.of(device.ports) : List.of(live.ports),
    );
    await changed();
  }

  Future<void> restoreDeviceNormal(DeviceRecord device) async {
    device.isDead = false;
    missing.remove(device.ip);
    refreshed.remove(device.ip);
    await changed();
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
                'Choose a tool. Results gathered here are saved back to this network.',
                style: TextStyle(color: secondary),
              ),
              const SizedBox(height: 12),
              ListTile(
                leading: const Icon(Icons.radar_rounded),
                title: const Text('Port scanner'),
                subtitle: const Text('Scan ports and add open results'),
                onTap: () => Navigator.pop(context, 'ports'),
              ),
              ListTile(
                leading: const Icon(Icons.travel_explore_rounded),
                title: const Text('DNS lookup'),
                subtitle: const Text('Find and save the device hostname'),
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
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => SimplePortScanner(
            liveInventory: widget.liveInventory,
            initialHost: device.ip,
            onResults: (result) async {
              final mergedPorts = {...device.ports, ...result.ports}.toList()
                ..sort();
              device
                ..ports = mergedPorts
                ..lastSeen = DateTime.now()
                ..isDead = false;
              refreshed[device.ip] = result;
              missing.remove(device.ip);
              await changed();
            },
          ),
        ),
      );
    } else if (tool == 'dns') {
      await showDnsLookup(
        context,
        widget.liveInventory,
        initialInput: device.ip,
        onResult: (ip, hostname) async {
          if (ip != device.ip) return;
          if (device.name.isEmpty) device.name = hostname;
          device.lastSeen = DateTime.now();
          await changed();
        },
      );
    } else if (tool == 'subnet') {
      await showSubnetCalculator(context, initialCidr: '${device.ip}/24');
    }
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
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
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
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.network.name),
        backgroundColor: background,
        actions: [
          IconButton(
            onPressed: exportNetwork,
            tooltip: 'Export',
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
                primary: 'MARK ACTIVE',
                secondary: 'EDIT',
                onPrimary: () => markDeviceActive(device),
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
                    '${host.hostname.isEmpty ? 'Unknown device' : host.hostname} · ${host.ports.length} open ports',
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
              final live = widget.liveInventory.forIp(device.ip);
              final fresh =
                  refreshed[device.ip] ??
                  (live == null
                      ? null
                      : ScannedHost(
                          live.ip,
                          live.hostname,
                          List.of(live.ports),
                        ));
              final portsChanged =
                  fresh != null && !samePorts(device.ports, fresh.ports);
              final status = device.isDead
                  ? DeviceStatus.dead
                  : isMissing
                  ? DeviceStatus.missing
                  : portsChanged
                  ? DeviceStatus.changed
                  : fresh != null
                  ? DeviceStatus.active
                  : DeviceStatus.saved;
              return Dismissible(
                key: ValueKey(
                  '${widget.network.id}:${device.ip}:${device.mac}',
                ),
                direction: DismissDirection.horizontal,
                background: _SwipeStatusBackground(
                  alignment: Alignment.centerLeft,
                  color: accent,
                  icon: device.isDead
                      ? Icons.undo_rounded
                      : Icons.refresh_rounded,
                  label: device.isDead ? 'RESTORE NORMAL' : 'REFRESH ACTIVE',
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
                    if (device.isDead) {
                      await restoreDeviceNormal(device);
                    } else {
                      await markDeviceActive(device);
                    }
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
                  status: status,
                  onTools: () => openDeviceTools(device),
                  onTap: () => showDevice(
                    context,
                    device,
                    fresh: fresh,
                    onRename: () => renameDevice(device),
                    onEdit: () => editDevice(device),
                    onDelete: () async {
                      widget.network.devices.remove(device);
                      missing.remove(device.ip);
                      await changed();
                    },
                    onApplyPorts: fresh == null
                        ? null
                        : () async {
                            device
                              ..ports = List.of(fresh.ports)
                              ..lastSeen = DateTime.now();
                            if (fresh.hostname.isNotEmpty &&
                                device.name.isEmpty) {
                              device.name = fresh.hostname;
                            }
                            await changed();
                          },
                  ),
                  onKeep: isMissing
                      ? () => setState(() => missing.remove(device.ip))
                      : null,
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
    this.onKeep,
    this.onDelete,
  });

  final DeviceRecord device;
  final DeviceStatus status;
  final VoidCallback onTap;
  final VoidCallback onTools;
  final VoidCallback? onKeep;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
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
                ],
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
            ),
            if (status == DeviceStatus.missing)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: onKeep,
                        child: const Text('KEEP'),
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
}

class MappingToolsPage extends StatelessWidget {
  const MappingToolsPage({
    super.key,
    required this.liveInventory,
    required this.onCreateNetwork,
    required this.onScanSubnet,
  });

  final LiveInventory liveInventory;
  final VoidCallback onCreateNetwork;
  final VoidCallback onScanSubnet;

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
              builder: (_) => SimplePortScanner(liveInventory: liveInventory),
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
  const NearbyAccessPointsPage({super.key});

  @override
  State<NearbyAccessPointsPage> createState() => _NearbyAccessPointsPageState();
}

class _NearbyAccessPointsPageState extends State<NearbyAccessPointsPage> {
  static const channel = MethodChannel('netforge/device_status');

  List<NearbyAccessPoint> accessPoints = [];
  bool loading = true;
  String? error;

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
      if (!Platform.isAndroid) {
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
          'Access points are ordered by signal strength.',
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
          ...accessPoints.map(
            (accessPoint) => Card(
              color: surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: const BorderSide(color: border),
              ),
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
                    accessPoint.bssid,
                    '${accessPoint.level} dBm',
                    if (accessPoint.channel > 0) 'Ch ${accessPoint.channel}',
                    if (accessPoint.frequency > 0)
                      '${accessPoint.frequency} MHz',
                    if (accessPoint.security.isNotEmpty) accessPoint.security,
                  ].join(' · '),
                  style: const TextStyle(color: secondary, fontSize: 12),
                ),
              ),
            ),
          ),
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
    this.onResults,
  });
  final LiveInventory liveInventory;
  final String initialHost;
  final ValueChanged<ScannedHost>? onResults;

  @override
  State<SimplePortScanner> createState() => _SimplePortScannerState();
}

enum PortSelectionMode { common, custom, all }

class _SimplePortScannerState extends State<SimplePortScanner> {
  static const scanLanTarget = '__scan_lan__';

  final ports = TextEditingController();
  final results = <String, List<int>>{};
  late String selectedTarget;
  late PortSelectionMode portMode;
  bool scanning = false;
  int checked = 0;
  int total = 0;

  @override
  void initState() {
    super.initState();
    selectedTarget = widget.initialHost.isEmpty
        ? scanLanTarget
        : widget.initialHost;
    portMode = PortSelectionMode.common;
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
        for (var offset = 0; offset < scanPorts.length; offset += 96) {
          final batch = scanPorts.skip(offset).take(96).toList();
          final hits = <int>[];
          await Future.wait(
            batch.map((port) async {
              try {
                final socket = await Socket.connect(
                  address,
                  port,
                  timeout: const Duration(milliseconds: 500),
                );
                socket.destroy();
                hits.add(port);
              } catch (_) {}
            }),
          );
          open.addAll(hits);
          if (mounted) {
            setState(() {
              checked += batch.length;
              if (open.isNotEmpty) {
                results[address] = List.of(open)..sort();
              }
            });
          }
        }
        widget.liveInventory.observePorts(address, open);
        widget.onResults?.call(ScannedHost(address, address, List.of(open)));
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
            label: Text(scanning ? '$checked / $total checks' : 'SCAN'),
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
          ...results.entries.map(
            (entry) => ExpansionTile(
              leading: const Icon(Icons.check_circle_rounded, color: accent),
              title: Text(
                entry.key,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w900,
                ),
              ),
              subtitle: Text('${entry.value.length} open ports'),
              children: entry.value
                  .map(
                    (port) => ListTile(
                      title: Text('TCP $port'),
                      subtitle: Text(serviceName(port)),
                    ),
                  )
                  .toList(),
            ),
          ),
          if (!scanning && checked > 0 && results.isEmpty)
            const EmptyMessage(
              icon: Icons.block_rounded,
              text: 'No selected TCP ports were open.',
            ),
        ],
      ),
    );
  }
}

class ScannedHost {
  const ScannedHost(this.ip, this.hostname, this.ports);
  final String ip;
  final String hostname;
  final List<int> ports;

  DeviceRecord toRecord() => DeviceRecord(
    ip: ip,
    name: hostname == ip ? '' : hostname,
    product: guessProduct(ports),
    ports: List.of(ports),
  );
}

int addFirstScanHosts(NetworkMap network, Iterable<ScannedHost> hosts) {
  if (network.devices.isNotEmpty) return 0;
  final discovered = hosts.map((host) => host.toRecord()).toList();
  network.devices.addAll(discovered);
  return discovered.length;
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
          found.add(ScannedHost(ip, hostname, ports));
        }
        checked++;
        onProgress?.call(checked);
      }),
    );
  }
  found.sort((a, b) => lastOctet(a.ip).compareTo(lastOctet(b.ip)));
  return found;
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

String guessProduct(List<int> ports) {
  final set = ports.toSet();
  if (set.contains(5555) || set.contains(5037)) return 'Android / ADB device';
  if (set.contains(9100) || set.contains(631)) return 'Likely printer';
  if (set.contains(445) || set.contains(139)) return 'File-sharing device';
  if (set.contains(53)) return 'Router or DNS device';
  if (set.any({80, 443, 8080, 8443}.contains)) return 'Web-enabled device';
  if (set.contains(22)) return 'SSH-enabled device';
  return 'Unknown network device';
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
  required VoidCallback onRename,
  required VoidCallback onEdit,
  required VoidCallback onDelete,
  VoidCallback? onApplyPorts,
}) async {
  await showModalBottomSheet<void>(
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
              onTap: () {
                Navigator.pop(context);
                onRename();
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
                    const Icon(Icons.edit_outlined, color: accent),
                  ],
                ),
              ),
            ),
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
            DetailRow(
              label: 'PRODUCT',
              value: device.product.isEmpty ? 'Unidentified' : device.product,
            ),
            DetailRow(
              label: 'SAVED PORTS',
              value: device.ports.isEmpty ? 'None' : device.ports.join(', '),
            ),
            if (fresh != null)
              DetailRow(
                label: 'LATEST PORTS',
                value: fresh.ports.isEmpty ? 'None' : fresh.ports.join(', '),
              ),
            if (device.notes.isNotEmpty)
              DetailRow(label: 'NOTES', value: device.notes),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      onEdit();
                    },
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('EDIT'),
                  ),
                ),
                if (onApplyPorts != null) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        onApplyPorts();
                      },
                      icon: const Icon(Icons.sync_rounded),
                      label: const Text('APPLY PORTS'),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 10),
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
                          onPressed: () => Navigator.pop(dialogContext, false),
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
}

Future<void> showDnsLookup(
  BuildContext context,
  LiveInventory liveInventory, {
  String initialInput = '',
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
                try {
                  final value = input.text.trim();
                  final address = InternetAddress.tryParse(value);
                  final answers = address == null
                      ? await InternetAddress.lookup(value)
                      : [await address.reverse()];
                  for (final answer in answers) {
                    if (answer.host != answer.address) {
                      liveInventory.observeHostname(
                        answer.address,
                        answer.host,
                      );
                      onResult?.call(answer.address, answer.host);
                    }
                  }
                  setModalState(
                    () => result = answers
                        .map(
                          (answer) => answer.host == answer.address
                              ? answer.address
                              : '${answer.address} — ${answer.host}',
                        )
                        .join('\n'),
                  );
                } catch (error) {
                  setModalState(() => result = 'Lookup failed: $error');
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
  });
  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: surface,
      border: Border.all(color: border),
      borderRadius: BorderRadius.circular(15),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: accent),
        const SizedBox(height: 14),
        Text(
          value,
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
        ),
        Text(
          label,
          style: const TextStyle(
            color: secondary,
            fontSize: 10,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    ),
  );
}

class NetworkTile extends StatelessWidget {
  const NetworkTile({super.key, required this.network, required this.onTap});
  final NetworkMap network;
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
