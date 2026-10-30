import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nai_huishi/presentation/widgets/studio_select.dart';
import 'package:nai_huishi/core/constants/api_constants.dart';
import 'package:nai_huishi/core/di/injection.dart';
import 'package:nai_huishi/presentation/viewmodels/generation_viewmodel.dart';

class AdvancedParametersPage extends StatefulWidget {
  final bool embedded;
  const AdvancedParametersPage({super.key, this.embedded = false});

  @override
  State<AdvancedParametersPage> createState() => _AdvancedParametersPageState();
}

class _AdvancedParametersPageState extends State<AdvancedParametersPage> {
  late final GenerationViewModel _vm;
  late final TextEditingController _seedController;

  @override
  void initState() {
    super.initState();
    _vm = sl<GenerationViewModel>();
    _seedController = TextEditingController(text: _vm.seed?.toString() ?? '');
    _vm.addListener(_onChanged);
  }

  void _onChanged() {
    final seed = _vm.seed?.toString() ?? '';
    if (_seedController.text != seed) {
      _seedController.value = TextEditingValue(
        text: seed,
        selection: TextSelection.collapsed(offset: seed.length),
      );
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _vm.removeListener(_onChanged);
    _seedController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controls = SliderTheme(
        data: SliderTheme.of(context).copyWith(
          trackHeight: 4,
          activeTickMarkColor: Colors.transparent,
          inactiveTickMarkColor: Colors.transparent,
          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
          overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _seedInput(),
            const SizedBox(height: 24),
            _stepsControl(),
            const SizedBox(height: 16),
            _slider(
                title: '引导比例',
                subtitle: 'CFG Scale',
                value: _vm.scale,
                min: 1,
                max: 10,
                divisions: 18,
                onChanged: _vm.updateScale),
            const SizedBox(height: 16),
            _slider(
                title: '提示词引导重缩放',
                subtitle: 'Prompt Guidance Rescale',
                value: _vm.cfgRescale,
                min: 0,
                max: 1,
                divisions: 10,
                onChanged: _vm.updateCfgRescale),
            const SizedBox(height: 16),
            _dropdown(
                title: '采样算法',
                value: _vm.selectedSampler,
                values: _vm.isIkunEndpoint
                    ? ApiConstants.ikunSupportedSamplers
                    : ApiConstants.supportedSamplers,
                onChanged: _vm.updateSelectedSampler),
            const SizedBox(height: 20),
            _dropdown(
                title: '噪声调度',
                value: _vm.selectedNoiseSchedule,
                values: _vm.isIkunEndpoint
                    ? ApiConstants.ikunSupportedNoiseSchedules
                    : ApiConstants.supportedNoiseSchedules,
                onChanged: _vm.updateSelectedNoiseSchedule),
          ],
        ));
    if (widget.embedded) return controls;
    return Scaffold(
      appBar: AppBar(title: const Text('高级参数')),
      body: SingleChildScrollView(
          padding: const EdgeInsets.all(20), child: controls),
    );
  }

  Widget _stepsControl() {
    final isIkun = _vm.isIkunEndpoint;
    final isLocked = (isIkun && _vm.isStepsLocked) || _vm.isMediumEffort;
    const maxSteps = 50.0;
    final value = _vm.isMediumEffort
        ? 14
        : isLocked
            ? ApiConstants.defaultSteps
            : _vm.steps;
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text('步数',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            ),
            if (isIkun)
              IconButton(
                tooltip: _vm.isStepsLocked ? '解除 28 步锁定' : '锁定为 28 步',
                visualDensity: VisualDensity.compact,
                onPressed: () => _vm.toggleStepsLock(),
                icon: Icon(
                  _vm.isStepsLocked
                      ? CupertinoIcons.lock_fill
                      : CupertinoIcons.lock_open,
                  size: 18,
                  color: _vm.isStepsLocked
                      ? colors.primary
                      : colors.onSurfaceVariant,
                ),
              ),
            Text('$value',
                style: TextStyle(
                    color: colors.primary, fontWeight: FontWeight.w700)),
          ],
        ),
        Slider(
          value: value.toDouble().clamp(1, maxSteps),
          min: 1,
          max: maxSteps,
          divisions: maxSteps.toInt() - 1,
          onChanged: isLocked ? null : (next) => _vm.updateSteps(next.round()),
        ),
        if (isIkun && _vm.isStepsLocked)
          Text(
            '已锁定为 28 步。点击锁图标后可自由调整。',
            style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
          ),
      ],
    );
  }

  Widget _slider({
    required String title,
    required String subtitle,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required ValueChanged<double> onChanged,
  }) {
    final digits = value == value.roundToDouble() ? 0 : 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w700)),
                  Text(subtitle,
                      style: TextStyle(
                          fontSize: 11,
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant)),
                ],
              ),
            ),
            Text(value.toStringAsFixed(digits),
                style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w700)),
          ],
        ),
        Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          divisions: divisions,
          onChanged:
              title == '提示词引导重缩放' && _vm.isMediumEffort ? null : onChanged,
        ),
      ],
    );
  }

  Widget _dropdown({
    required String title,
    required String value,
    required List<String> values,
    required ValueChanged<String> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        StudioSelect<String>(
            id: title == '采样算法' ? 'generation-sampler' : 'generation-noise',
            label: title,
            value: value,
            options: [
              for (final item in values) StudioSelectOption(item, item)
            ],
            onChanged:
                title == '采样算法' && _vm.isMediumEffort ? null : onChanged),
      ],
    );
  }

  Widget _seedInput() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: TextField(
            controller: _seedController,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              labelText: 'Seed',
              helperText: '留空时随机生成',
            ),
            onChanged: (value) =>
                _vm.updateSeed(value.isEmpty ? null : int.tryParse(value)),
          ),
        ),
        const SizedBox(width: 10),
        IconButton.filledTonal(
          tooltip: '随机种子',
          onPressed: () => _vm.updateSeed(
            DateTime.now().microsecondsSinceEpoch % 0xFFFFFFFF,
          ),
          icon: const Icon(CupertinoIcons.shuffle),
        ),
      ],
    );
  }
}
