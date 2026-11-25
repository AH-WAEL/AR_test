import 'package:ar_flutter_plugin_plus/ar_flutter_plugin_plus.dart';
import 'package:ar_flutter_plugin_plus/datatypes/config_planedetection.dart';
import 'package:ar_flutter_plugin_plus/datatypes/hittest_result_types.dart';
import 'package:ar_flutter_plugin_plus/datatypes/node_types.dart';
import 'package:ar_flutter_plugin_plus/managers/ar_anchor_manager.dart';
import 'package:ar_flutter_plugin_plus/managers/ar_location_manager.dart';
import 'package:ar_flutter_plugin_plus/managers/ar_object_manager.dart';
import 'package:ar_flutter_plugin_plus/managers/ar_session_manager.dart';
import 'package:ar_flutter_plugin_plus/models/ar_anchor.dart';
import 'package:ar_flutter_plugin_plus/models/ar_hittest_result.dart';
import 'package:ar_flutter_plugin_plus/models/ar_node.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vector_math/vector_math_64.dart' show Vector3, Vector4;

import 'image_test.dart';

const duckUrl =
    'https://raw.githubusercontent.com/KhronosGroup/glTF-Sample-Models/main/2.0/Duck/glTF-Binary/Duck.glb';

void main() => runApp(const MaterialApp(home: ImageTestPage()));

class ArTestPage extends StatefulWidget {
  const ArTestPage({super.key});
  @override
  State<ArTestPage> createState() => _ArTestPageState();
}

class _ArTestPageState extends State<ArTestPage> {
  ARSessionManager? _session;
  ARObjectManager? _objects;
  ARAnchorManager? _anchors;
  final List<ARAnchor> _placed = [];

  // Diagnostic: each tap places a duck at the next scale in this list.
  final List<double> _scales = [0.2, 0.05, 0.01, 0.002];
  int _tapCount = 0;

  String _status = 'Move the phone slowly over a table or the floor';

  @override
  void dispose() {
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
      showFeaturePoints: true,
      showPlanes: true,
      showWorldOrigin: true,
    );
    objects.onInitialize();
    session.onPlaneOrPointTap = _onTap;
  }

  Future<void> _onTap(List<ARHitTestResult> hits) async {
    final planeHits = hits.where((h) => h.type == ARHitTestResultType.plane);
    if (planeHits.isEmpty) {
      setState(() => _status = 'No surface detected there yet, keep scanning');
      return;
    }

    final hit = planeHits.first;
    final usedScale = _scales[_tapCount % _scales.length];
    final dist = hit.distance.toStringAsFixed(2);

    final anchor = ARPlaneAnchor(transformation: hit.worldTransform);
    final anchorOk = await _anchors?.addAnchor(anchor) ?? false;
    if (!anchorOk) {
      setState(() => _status = 'Could not add anchor (hit at $dist m)');
      return;
    }
    _placed.add(anchor);

    final node = ARNode(
      type: NodeType.webGLB,
      uri: duckUrl,
      scale: Vector3.all(usedScale),
      position: Vector3(0, 0, 0),
      rotation: Vector4(1, 0, 0, 0),
    );
    final nodeOk = await _objects?.addNode(node, planeAnchor: anchor) ?? false;

    _tapCount++;
    debugPrint(
      'AR place: anchor=$anchorOk node=$nodeOk scale=$usedScale distance=$dist',
    );
    setState(
      () => _status = nodeOk
          ? 'Duck #${_placed.length}: scale $usedScale, hit at $dist m'
          : 'Could not load the model (check internet)',
    );
  }

  void _clear() {
    for (final a in _placed) {
      _anchors?.removeAnchor(a);
    }
    _placed.clear();
    _tapCount = 0;
    setState(() => _status = 'Cleared. Next tap uses scale ${_scales[0]}');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('AR test')),
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
              child: Text(_status, style: const TextStyle(color: Colors.white)),
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
