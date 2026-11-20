import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'app_log_buffer.dart';
import 'app_log_singleton.dart';

class TerminalPage extends StatefulWidget {
  const TerminalPage({Key? key}) : super(key: key);

  @override
  State<TerminalPage> createState() => _TerminalPageState();
}

class _TerminalPageState extends State<TerminalPage> {
  late ScrollController _scrollController;
  String _filterText = '';
  final TextEditingController _filterController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    // S'abonner aux changements du buffer pour auto-scroll
    appLog.addListener(_onLogsChanged);
  }

  @override
  void dispose() {
    appLog.removeListener(_onLogsChanged);
    _scrollController.dispose();
    _filterController.dispose();
    super.dispose();
  }

  void _onLogsChanged() {
    // Auto-scroll vers le bas si l'utilisateur est proche du bas
    if (_isAtBottom()) {
      _scrollToBottom();
    }
  }

  bool _isAtBottom() {
    if (!_scrollController.hasClients) return true;
    // Si position à moins de 100 pixels du bas, considérer "au bas"
    return _scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 100;
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _clearLogs() {
    appLog.clear();
  }

  void _copyLogs() {
    final text = appLog.exportText();
    Clipboard.setData(ClipboardData(text: text)).then((_) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Logs copiés dans le presse-papiers'),
          duration: Duration(seconds: 2),
        ),
      );
    });
  }

  List<LogEntry> _getFilteredEntries() {
    final filter = _filterText.toLowerCase();
    if (filter.isEmpty) {
      return appLog.entries;
    }
    return appLog.entries
        .where((e) => e.formatted.toLowerCase().contains(filter))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Terminal Bluetooth'),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.delete),
            tooltip: 'Effacer les logs',
            onPressed: _clearLogs,
          ),
          IconButton(
            icon: const Icon(Icons.copy),
            tooltip: 'Copier tous les logs',
            onPressed: _copyLogs,
          ),
        ],
      ),
      body: Column(
        children: [
          // Section filtre (optionnel)
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              controller: _filterController,
              decoration: InputDecoration(
                hintText: 'Filtrer logs...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _filterText.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _filterController.clear();
                          setState(() {
                            _filterText = '';
                          });
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
              ),
              onChanged: (value) {
                setState(() {
                  _filterText = value;
                });
              },
            ),
          ),
          // ListeView des logs avec auto-scroll
          Expanded(
            child: ListenableBuilder(
              listenable: appLog,
              builder: (context, child) {
                final entries = _getFilteredEntries();
                if (entries.isEmpty) {
                  return Center(
                    child: Text(
                      _filterText.isEmpty
                          ? 'En attente de logs...'
                          : 'Aucun log ne correspond au filtre',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  );
                }
                return ListView.builder(
                  controller: _scrollController,
                  itemCount: entries.length,
                  itemBuilder: (context, index) {
                    final entry = entries[index];
                    final color = _getColorForKind(entry.kind);
                    return Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8.0,
                        vertical: 2.0,
                      ),
                      child: Text(
                        entry.formatted,
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                          color: color,
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Color _getColorForKind(LogKind kind) {
    switch (kind) {
      case LogKind.tx:
        return Colors.lightGreen;
      case LogKind.rx:
        return Colors.lightBlue;
      case LogKind.info:
        return Colors.grey[400]!;
      case LogKind.error:
        return Colors.redAccent;
    }
  }
}
