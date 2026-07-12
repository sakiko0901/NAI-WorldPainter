import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nai_huishi/core/constants/api_constants.dart';
import 'package:nai_huishi/core/di/injection.dart';
import 'package:nai_huishi/presentation/viewmodels/generation_viewmodel.dart';

class AdvancedParametersPage extends StatefulWidget {
  const AdvancedParametersPage({super.key});

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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('高级参数'),
        leading: IconButton(
          icon: const Icon(CupertinoIcons.chevron_left),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _directorCard(isDark),
          const SizedBox(height: 16),
          _card(
            isDark,
            children: [
              _stepsControl(),
              const SizedBox(height: 22),
              _slider(
                title: '引导比例',
                subtitle: 'CFG Scale',
                value: _vm.scale,
                min: 1,
                max: 10,
                divisions: 18,
                onChanged: _vm.updateScale,
              ),
              const SizedBox(height: 22),
              _slider(
                title: '提示词引导重缩放',
                subtitle: 'Prompt Guidance Rescale',
                value: _vm.cfgRescale,
                min: 0,
                max: 1,
                divisions: 10,
                onChanged: _vm.updateCfgRescale,
              ),
            ],
          ),
          const SizedBox(height: 16),
          _card(
            isDark,
            children: [
              _dropdown(
                title: '采样算法',
                value: _vm.isIkunEndpoint && _vm.selectedSampler == 'ddim'
                    ? 'ddim_v3'
                    : _vm.selectedSampler,
                values: _vm.isIkunEndpoint
                    ? ApiConstants.ikunSupportedSamplers
                    : ApiConstants.supportedSamplers,
                onChanged: _vm.updateSelectedSampler,
              ),
              const SizedBox(height: 20),
              _dropdown(
                title: '噪声调度',
                value: _vm.isIkunEndpoint &&
                        _vm.selectedNoiseSchedule == 'polyexponential'
                    ? 'exponential'
                    : _vm.selectedNoiseSchedule,
                values: _vm.isIkunEndpoint
                    ? ApiConstants.ikunSupportedNoiseSchedules
                    : ApiConstants.supportedNoiseSchedules,
                onChanged: _vm.updateSelectedNoiseSchedule,
              ),
              const SizedBox(height: 20),
              _seedInput(),
            ],
          ),
        ],
      ),
    );
  }

  Widget _directorCard(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C21) : Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Icon(CupertinoIcons.video_camera_solid,
              color: Theme.of(context)
                  .colorScheme
                  .onSurfaceVariant
                  .withValues(alpha: 0.45)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('导演工具',
                    style: TextStyle(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.55),
                      fontWeight: FontWeight.w700,
                    )),
                const SizedBox(height: 3),
                Text('即将推出',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurfaceVariant
                          .withValues(alpha: 0.45),
                    )),
              ],
            ),
          ),
          const Icon(CupertinoIcons.lock_fill, size: 16, color: Colors.grey),
        ],
      ),
    );
  }

  Widget _card(bool isDark, {required List<Widget> children}) => Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1C1C21) : Colors.white,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(children: children),
      );

  Widget _stepsControl() {
    final isFixed = _vm.is7877Endpoint;
    final value = isFixed ? ApiConstants.defaultSteps : _vm.steps;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text('生成步数 (Steps)',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            ),
            Text('$value',
                style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w700)),
          ],
        ),
        Slider(
          value: value.toDouble(),
          min: 1,
          max: 50,
          divisions: 49,
          onChanged: isFixed ? null : (next) => _vm.updateSteps(next.round()),
        ),
        if (isFixed)
          Text(
            '7877 渠道固定为 28 步，不可修改。',
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
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
          onChanged: onChanged,
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
        InputDecorator(
          decoration: const InputDecoration(),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value,
              isExpanded: true,
              borderRadius: BorderRadius.circular(20),
              items: values
                  .map((item) =>
                      DropdownMenuItem(value: item, child: Text(item)))
                  .toList(),
              onChanged: (next) {
                if (next != null) onChanged(next);
              },
            ),
          ),
        ),
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
              labelText: '种子',
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
