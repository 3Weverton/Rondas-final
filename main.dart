import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() => runApp(const RondasApp());

class Ronda {
  final String previsto;
  final String? registrado;
  final String status; // em_espera, concluida, perdida

  Ronda({required this.previsto, this.registrado, required this.status});

  Map<String, dynamic> toJson() => {
    'previsto': previsto,
    'registrado': registrado,
    'status': status,
  };

  factory Ronda.fromJson(Map<String, dynamic> j) => Ronda(
    previsto: j['previsto'],
    registrado: j['registrado'],
    status: j['status'],
  );
}

class RondasApp extends StatelessWidget {
  const RondasApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Minhas Rondas',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const RondasPage(),
    );
  }
}

class RondasPage extends StatefulWidget {
  const RondasPage({super.key});

  @override
  State<RondasPage> createState() => _RondasPageState();
}

class _RondasPageState extends State<RondasPage> {
  final List<Ronda> _rondas = [];
  int _inicio = 22;
  int _fim = 7;
  bool _carregando = true;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    final p = await SharedPreferences.getInstance();
    _inicio = p.getInt('inicio') ?? 22;
    _fim = p.getInt('fim') ?? 7;
    final raw = p.getString('rondas');
    if (raw != null) {
      _rondas
        ..clear()
        ..addAll((jsonDecode(raw) as List)
            .map((e) => Ronda.fromJson(Map<String, dynamic>.from(e))));
    } else {
      _gerarRondas(DateTime.now());
    }
    _atualizarPerdidas();
    setState(() => _carregando = false);
  }

  Future<void> _salvar() async {
    final p = await SharedPreferences.getInstance();
    await p.setInt('inicio', _inicio);
    await p.setInt('fim', _fim);
    await p.setString('rondas', jsonEncode(_rondas.map((e) => e.toJson()).toList()));
  }

  void _gerarRondas(DateTime dia) {
    _rondas.clear();
    DateTime base = DateTime(dia.year, dia.month, dia.day, _inicio);
    int total = ((_fim - _inicio + 24) % 24);
    if (total == 0) total = 24;
    for (int i = 0; i <= total; i++) {
      final h = (base.hour + i) % 24;
      _rondas.add(Ronda(previsto: '${h.toString().padLeft(2, '0')}:00', status: 'em_espera'));
    }
  }

  void _atualizarPerdidas() {
    final agora = DateTime.now();
    // A ronda passa a "perdida" quando o horário previsto já passou
    // e ainda não foi registrada. A última ronda futura continua em espera.
    for (int i = 0; i < _rondas.length; i++) {
      final r = _rondas[i];
      if (r.status != 'em_espera') continue;
      final partes = r.previsto.split(':');
      int h = int.parse(partes[0]);
      DateTime previsto = DateTime(agora.year, agora.month, agora.day, h);
      // Para uma jornada que atravessa meia-noite, horas menores que o início
      // pertencem ao dia seguinte.
      if (_inicio > _fim && h < _inicio) {
        previsto = previsto.add(const Duration(days: 1));
      }
      if (agora.isAfter(previsto.add(const Duration(minutes: 30)))) {
        _rondas[i] = Ronda(previsto: r.previsto, status: 'perdida');
      }
    }
  }

  int get _proximaIndex {
    for (int i = 0; i < _rondas.length; i++) {
      if (_rondas[i].status == 'em_espera') return i;
    }
    return -1;
  }

  Future<void> _registrar() async {
    _atualizarPerdidas();
    final idx = _proximaIndex;
    if (idx < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não há ronda em espera para registrar.')),
      );
      return;
    }

    final agora = DateTime.now();
    final hora = '${agora.hour.toString().padLeft(2, '0')}:'
        '${agora.minute.toString().padLeft(2, '0')}:'
        '${agora.second.toString().padLeft(2, '0')}';

    setState(() {
      final r = _rondas[idx];
      _rondas[idx] = Ronda(
        previsto: r.previsto,
        registrado: hora,
        status: 'concluida',
      );
    });
    await _salvar();
  }

  String _dataFormatada(DateTime data) {
    return '${data.day.toString().padLeft(2, '0')}/'
        '${data.month.toString().padLeft(2, '0')}/${data.year}';
  }

  String _horaCompleta(DateTime data) {
    return '${data.hour.toString().padLeft(2, '0')}:'
        '${data.minute.toString().padLeft(2, '0')}:'
        '${data.second.toString().padLeft(2, '0')}';
  }

  Future<File> _gerarRelatorio(DateTime finalizadoEm) async {
    final documento = pw.Document();
    final concluidas = _rondas.where((r) => r.status == 'concluida').length;
    final perdidas = _rondas.where((r) => r.status == 'perdida').length;

    documento.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (context) => [
          pw.Text(
            'RELATORIO DE RONDAS',
            style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 8),
          pw.Text('Data: ${_dataFormatada(finalizadoEm)}'),
          pw.Text('Periodo previsto: ${_inicio.toString().padLeft(2, '0')}:00 ate ${_fim.toString().padLeft(2, '0')}:00'),
          pw.Text('Turno finalizado as: ${_horaCompleta(finalizadoEm)}'),
          pw.SizedBox(height: 18),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
            children: [
              pw.Text('Total: ${_rondas.length}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
              pw.Text('Concluidas: $concluidas', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
              pw.Text('Perdidas: $perdidas', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            ],
          ),
          pw.SizedBox(height: 18),
          pw.TableHelper.fromTextArray(
            headers: const ['Ronda prevista', 'Status', 'Horario registrado'],
            data: _rondas.map((r) => [
              r.previsto,
              r.status == 'concluida'
                  ? 'Concluida'
                  : r.status == 'perdida'
                      ? 'Perdida - sem registro'
                      : 'Em espera',
              r.registrado ?? '-',
            ]).toList(),
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            cellStyle: const pw.TextStyle(fontSize: 10),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
            cellAlignment: pw.Alignment.center,
            border: pw.TableBorder.all(color: PdfColors.grey600, width: 0.5),
          ),
          pw.SizedBox(height: 18),
          pw.Text('Relatorio gerado automaticamente pelo aplicativo Minhas Rondas.',
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
        ],
      ),
    );

    final dir = await getApplicationDocumentsDirectory();
    final nome = 'relatorio_rondas_${finalizadoEm.year}${finalizadoEm.month.toString().padLeft(2, '0')}${finalizadoEm.day.toString().padLeft(2, '0')}_${finalizadoEm.hour.toString().padLeft(2, '0')}${finalizadoEm.minute.toString().padLeft(2, '0')}.pdf';
    final arquivo = File('${dir.path}/$nome');
    await arquivo.writeAsBytes(await documento.save());
    return arquivo;
  }

  Future<void> _finalizarTurno() async {
    _atualizarPerdidas();
    final pendentes = _rondas.where((r) => r.status == 'em_espera').length;

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Finalizar turno?'),
        content: Text(
          pendentes > 0
              ? 'Existem $pendentes ronda(s) ainda em espera. Ao finalizar, elas constarao no relatorio como nao realizadas.'
              : 'O turno sera encerrado e um relatorio sera gerado.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Finalizar')),
        ],
      ),
    );

    if (confirmar != true || !mounted) return;

    // Tudo que ficou em espera no momento do encerramento passa a constar
    // no relatorio como nao realizado.
    setState(() {
      for (int i = 0; i < _rondas.length; i++) {
        if (_rondas[i].status == 'em_espera') {
          final r = _rondas[i];
          _rondas[i] = Ronda(previsto: r.previsto, status: 'perdida');
        }
      }
    });

    final finalizadoEm = DateTime.now();
    try {
      final arquivo = await _gerarRelatorio(finalizadoEm);
      if (!mounted) return;
      await Share.shareXFiles(
        [XFile(arquivo.path, mimeType: 'application/pdf')],
        subject: 'Relatorio de Rondas - ${_dataFormatada(finalizadoEm)}',
        text: 'Relatorio do turno de ${_dataFormatada(finalizadoEm)}.',
      );

      // So inicia uma nova jornada depois que o relatorio foi gerado.
      _gerarRondas(finalizadoEm.add(const Duration(days: 1)));
      await _salvar();
      if (!mounted) return;
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Turno finalizado. Relatorio salvo em ${arquivo.path}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Nao foi possivel gerar o relatorio: $e')),
      );
    }
  }

  Future<void> _configurar() async {
    int inicio = _inicio;
    int fim = _fim;
    await showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: const Text('Configurar rondas'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<int>(
                value: inicio,
                decoration: const InputDecoration(labelText: 'Primeira ronda'),
                items: List.generate(24, (h) => DropdownMenuItem(
                  value: h, child: Text('${h.toString().padLeft(2, '0')}:00'),
                )),
                onChanged: (v) => setLocal(() => inicio = v!),
              ),
              DropdownButtonFormField<int>(
                value: fim,
                decoration: const InputDecoration(labelText: 'Última ronda'),
                items: List.generate(24, (h) => DropdownMenuItem(
                  value: h, child: Text('${h.toString().padLeft(2, '0')}:00'),
                )),
                onChanged: (v) => setLocal(() => fim = v!),
              ),
              const SizedBox(height: 12),
              const Text('O protótipo usa intervalo de 1 hora e funciona offline.'),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Salvar'),
            ),
          ],
        ),
      ),
    );
    // O diálogo acima não devolve os valores; para manter o protótipo simples,
    // a configuração efetiva é feita por um segundo diálogo compacto.
    if (!mounted) return;
    await _configurarSimples();
  }

  Future<void> _configurarSimples() async {
    int inicio = _inicio;
    int fim = _fim;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Horário das rondas'),
        content: Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<int>(
                value: inicio,
                decoration: const InputDecoration(labelText: 'Início'),
                items: List.generate(24, (h) => DropdownMenuItem(
                  value: h, child: Text('${h.toString().padLeft(2, '0')}h'),
                )),
                onChanged: (v) => inicio = v!,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: DropdownButtonFormField<int>(
                value: fim,
                decoration: const InputDecoration(labelText: 'Fim'),
                items: List.generate(24, (h) => DropdownMenuItem(
                  value: h, child: Text('${h.toString().padLeft(2, '0')}h'),
                )),
                onChanged: (v) => fim = v!,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Aplicar')),
        ],
      ),
    );
    if (ok == true) {
      setState(() {
        _inicio = inicio;
        _fim = fim;
        _gerarRondas(DateTime.now());
      });
      await _salvar();
    }
  }

  String _statusTexto(String s) {
    switch (s) {
      case 'concluida': return 'Ronda concluída';
      case 'perdida': return 'Ronda perdida — sem registro';
      default: return 'Em espera';
    }
  }

  Color _statusCor(String s) {
    switch (s) {
      case 'concluida': return Colors.green;
      case 'perdida': return Colors.red;
      default: return Colors.orange;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_carregando) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    _atualizarPerdidas();
    final idx = _proximaIndex;
    final proxima = idx >= 0 ? _rondas[idx] : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Minhas Rondas'),
        actions: [
          IconButton(
            tooltip: 'Configurar',
            icon: const Icon(Icons.settings),
            onPressed: _configurarSimples,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          setState(() {});
          await _salvar();
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    const Text('PRÓXIMA RONDA', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Text(proxima?.previsto ?? 'Concluídas',
                        style: const TextStyle(fontSize: 42, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    Text(proxima == null ? 'Não há rondas pendentes' : 'Aguardando registro',
                        style: const TextStyle(fontSize: 16)),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      height: 58,
                      child: FilledButton.icon(
                        onPressed: proxima == null ? null : _registrar,
                        icon: const Icon(Icons.check_circle_outline),
                        label: const Text('REGISTRAR PASSAGEM', style: TextStyle(fontSize: 17)),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: OutlinedButton.icon(
                        onPressed: _finalizarTurno,
                        icon: const Icon(Icons.assignment_turned_in_outlined),
                        label: const Text('FINALIZAR TURNO'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Text('Histórico de hoje', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            ..._rondas.asMap().entries.map((e) {
              final r = e.value;
              return Card(
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: _statusCor(r.status),
                    child: Icon(
                      r.status == 'concluida' ? Icons.check : r.status == 'perdida' ? Icons.close : Icons.schedule,
                      color: Colors.white,
                    ),
                  ),
                  title: Text('Prevista: ${r.previsto}'),
                  subtitle: Text('${_statusTexto(r.status)}${r.registrado != null ? ' • registrada às ${r.registrado}' : ''}'),
                ),
              );
            }),
            const SizedBox(height: 12),
            const Text(
              'Os horários registrados são gravados automaticamente e não há botão para editá-los.',
              style: TextStyle(color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
