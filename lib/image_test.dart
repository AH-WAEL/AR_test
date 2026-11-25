import 'dart:async';
import 'dart:io' show Platform;

import 'package:ar_flutter_plugin_plus/ar_flutter_plugin_plus.dart';
import 'package:ar_flutter_plugin_plus/datatypes/config_planedetection.dart';
import 'package:ar_flutter_plugin_plus/datatypes/node_types.dart';
import 'package:ar_flutter_plugin_plus/managers/ar_anchor_manager.dart';
import 'package:ar_flutter_plugin_plus/managers/ar_location_manager.dart';
import 'package:ar_flutter_plugin_plus/managers/ar_object_manager.dart';
import 'package:ar_flutter_plugin_plus/managers/ar_session_manager.dart';
import 'package:ar_flutter_plugin_plus/models/ar_anchor.dart';
import 'package:ar_flutter_plugin_plus/models/ar_node.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vector_math/vector_math_64.dart' show Matrix4, Vector3, Vector4;

const duckUrl =
    'https://raw.githubusercontent.com/KhronosGroup/glTF-Sample-Models/main/2.0/Duck/glTF-Binary/Duck.glb';

// Must match the file names in the Images folder exactly.
const trackedImages = [
  'Images/augmented-images-earth.jpg',
  'Images/artifact1.png',
];

// If the image appears to have moved more than this (in metres) from where
// the duck is anchored, the duck is moved back onto the image.
const reanchorThreshold = 0.03;

class _TrackedImage {
  ARPlaneAnchor? anchor;
  Vector3? anchoredAt;
  DateTime lastSeen = DateTime.now();
  int detections = 0;
  int reanchors = 0;
  bool busy = false;
}

class ImageTestPage extends StatefulWidget {
  const ImageTestPage({super.key});
  @override
  State<ImageTestPage> createState() => _ImageTestPageState();
}

class _ImageTestPageState extends State<ImageTestPage> {
  ARSessionManager? _session;
  ARObjectManager? _objects;
  ARAnchorManager? _anchors;
  final Map<String, _TrackedImage> _tracked = {};
  String _setup = 'Starting image tracking...';
  Timer? _ticker;

  // Confirmed by the duck test: iOS draws this model 100x bigger.
  double get _duckScale => Platform.isIOS ? 0.002 : 0.2;

  @override
  void initState() {
    super.initState();
    // Refresh the status twice a second so "not seen for X s" stays live.
    _ticker = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _session?.dispose();
    super.dispose();
  }

  void _onARViewCreated(
    ARSessionManager session,
    ARObjectManager objects,
    ARAnchorManager anchors,
    ARLocationManager location,
  ) {
    _session = session;
    _objects = objects;
    _anchors = anchors;
    session.onInitialize(
      showFeaturePoints: false,
      showPlanes: false,
      trackingImagePaths: trackedImages,
      continuousImageTracking: true,
      imageTrackingUpdateIntervalMs: 100,
    );
    objects.onInitialize();
    session.onImageTrackingConfigured = (success) {
      setState(
        () => _setup = success
            ? 'Ready. Point the camera at one of the images'
            : 'Image tracking setup FAILED',
      );
    };
    session.onImageDetected = (imageName, transformation) {
      _onImageDetected(imageName, transformation);
    };
  }

  Future<void> _onImageDetected(String imageName, Matrix4 pose) async {
    final item = _tracked.putIfAbsent(imageName, () => _TrackedImage());
    item.lastSeen = DateTime.now();
    item.detections++;
    if (item.busy) return; // a placement is already in progress

    final position = pose.getTranslation();
    final needsPlacement =
        item.anchoredAt == null ||
        item.anchoredAt!.distanceTo(position) > reanchorThreshold;
    if (!needsPlacement) return;

    item.busy = true;
    try {
      // Remove the old anchor (and the duck on it) before re-placing.
      if (item.anchor != null) {
        _anchors?.removeAnchor(item.anchor!);
        item.reanchors++;
      }

      final anchor = ARPlaneAnchor(transformation: pose);
      final anchorOk = await _anchors?.addAnchor(anchor) ?? false;
      if (!anchorOk) {
        item.anchor = null;
        item.anchoredAt = null;
        debugPrint('Anchor failed for $imageName');
        return;
      }

      final node = ARNode(
        type: NodeType.webGLB,
        uri: duckUrl,
        scale: Vector3.all(_duckScale),
        position: Vector3.zero(),
        rotation: Vector4(1, 0, 0, 0),
      );
      final nodeOk =
          await _objects?.addNode(node, planeAnchor: anchor) ?? false;

      item.anchor = anchor;
      item.anchoredAt = position;
      debugPrint(
        'Placed duck on $imageName '
        '(node=$nodeOk, re-anchors=${item.reanchors})',
      );
    } finally {
      item.busy = false;
    }
  }

  String _statusText() {
    final lines = <String>[_setup];
    for (final entry in _tracked.entries) {
      final name = entry.key.split('/').last;
      final t = entry.value;
      final secondsAgo =
          DateTime.now().difference(t.lastSeen).inMilliseconds / 1000;
      final state = secondsAgo < 0.5
          ? 'TRACKING'
          : 'not seen for ${secondsAgo.toStringAsFixed(1)} s';
      lines.add(
        '$name: $state | detections ${t.detections} '
        '| re-snaps ${t.reanchors}',
      );
    }
    return lines.join('\n');
  }

  void _clear() {
    for (final t in _tracked.values) {
      if (t.anchor != null) _anchors?.removeAnchor(t.anchor!);
    }
    _tracked.clear();
    setState(() => _setup = 'Cleared. Point at an image again');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Image tracking test')),
      body: Stack(
        children: [
          ARView(
            onARViewCreated: _onARViewCreated,
            planeDetectionConfig: PlaneDetectionConfig.horizontal,
          ),
          Positioned(
            top: 12,
            left: 12,
            right: 12,
            child: Container(
              padding: const EdgeInsets.all(8),
              color: Colors.black54,
              child: Text(
                _statusText(),
                style: const TextStyle(color: Colors.white, fontSize: 13),
              ),
            ),
          ),
          Positioned(
            bottom: 24,
            left: 0,
            right: 0,
            child: Center(
              child: ElevatedButton(
                onPressed: _clear,
                child: const Text('Remove all'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
