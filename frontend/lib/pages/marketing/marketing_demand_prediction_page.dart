import 'package:flutter/material.dart';
import '../../config/theme.dart';
import '../../services/api_client.dart';

class MarketingDemandPredictionPage extends StatefulWidget {
  final String customerId;
  const MarketingDemandPredictionPage({super.key, required this.customerId});

  @override
  State<MarketingDemandPredictionPage> createState() => _MarketingDemandPredictionPageState();
}

class _MarketingDemandPredictionPageState extends State<MarketingDemandPredictionPage> {
  final _api = ApiClient();
  String? _content;
  String? _model;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _predict();
  }

  Future<void> _predict() async {
    try {
      final resp = await _api.dio.post('/marketing/customers/${widget.customerId}/predict-demand');
      setState(() {
        _content = resp.data['content'] as String? ?? '';
        _model = resp.data['model'] as String? ?? '';
        _loading = false;
      });
    } catch (e) {
      setState(() { _error = '$e'; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('需求预测报告'),
        actions: [
          if (_model != null && _model!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: AppTheme.purple.withAlpha(20),
                ),
                child: Text(_model!, style: const TextStyle(fontSize: 12, color: Color(0xFF7C3AED))),
              ),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('预测失败: $_error'))
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: SelectableText(_content ?? '', style: const TextStyle(fontSize: 15, height: 1.8)),
                ),
    );
  }
}
