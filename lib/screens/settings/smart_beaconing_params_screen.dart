import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../services/beaconing_service.dart';

/// Sub-screen for SmartBeaconing™ parameter tuning.
class SmartBeaconingParamsScreen extends StatefulWidget {
  const SmartBeaconingParamsScreen({super.key});

  @override
  State<SmartBeaconingParamsScreen> createState() =>
      _SmartBeaconingParamsScreenState();
}

class _SmartBeaconingParamsScreenState
    extends State<SmartBeaconingParamsScreen> {
  late SmartBeaconingParams _params;

  @override
  void initState() {
    super.initState();
    _params = context.read<BeaconingService>().smartParams;
  }

  Future<void> _save() async {
    await context.read<BeaconingService>().setSmartParams(_params);
  }

  Future<void> _reset() async {
    await context.read<BeaconingService>().resetSmartDefaults();
    setState(() {
      _params = SmartBeaconingParams.defaults;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('SmartBeaconing™ Parameters')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _paramRow(
            label: 'Fast Speed (km/h)',
            value: _params.fastSpeedKmh,
            min: 10,
            max: 200,
            onChanged: (v) {
              setState(() => _params = _params.copyWith(fastSpeedKmh: v));
              _save();
            },
          ),
          _paramRow(
            label: 'Fast Rate (seconds)',
            value: _params.fastRateS.toDouble(),
            min: 10,
            max: 600,
            onChanged: (v) {
              setState(() => _params = _params.copyWith(fastRateS: v.round()));
              _save();
            },
          ),
          _paramRow(
            label: 'Slow Speed (km/h)',
            value: _params.slowSpeedKmh,
            min: 1,
            max: 30,
            onChanged: (v) {
              setState(() => _params = _params.copyWith(slowSpeedKmh: v));
              _save();
            },
          ),
          _paramRow(
            label: 'Slow Rate (seconds)',
            value: _params.slowRateS.toDouble(),
            min: 60,
            max: 3600,
            onChanged: (v) {
              setState(() => _params = _params.copyWith(slowRateS: v.round()));
              _save();
            },
          ),
          _paramRow(
            label: 'Min Turn Time (seconds)',
            value: _params.minTurnTimeS.toDouble(),
            min: 5,
            max: 120,
            onChanged: (v) {
              setState(
                () => _params = _params.copyWith(minTurnTimeS: v.round()),
              );
              _save();
            },
          ),
          _paramRow(
            label: 'Min Turn Angle (degrees)',
            value: _params.minTurnAngleDeg,
            min: 5,
            max: 90,
            onChanged: (v) {
              setState(() => _params = _params.copyWith(minTurnAngleDeg: v));
              _save();
            },
          ),
          _paramRow(
            label: 'Turn Slope',
            value: _params.turnSlope,
            min: 10,
            max: 600,
            onChanged: (v) {
              setState(() => _params = _params.copyWith(turnSlope: v));
              _save();
            },
          ),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            icon: const Icon(Symbols.refresh),
            label: const Text('Reset to Defaults'),
            onPressed: _reset,
          ),
        ],
      ),
    );
  }

  Widget _paramRow({
    required String label,
    required double value,
    required double min,
    required double max,
    required ValueChanged<double> onChanged,
  }) {
    final displayValue = value == value.truncateToDouble()
        ? '${value.toInt()}'
        : value.toStringAsFixed(1);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: Theme.of(context).textTheme.bodyMedium),
              Text(
                displayValue,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ],
          ),
        ),
        Slider(
          min: min,
          max: max,
          value: value.clamp(min, max),
          onChanged: onChanged,
        ),
      ],
    );
  }
}
