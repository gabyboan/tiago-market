import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/material.dart';

class DiagnosticReportButton extends StatefulWidget {
  const DiagnosticReportButton({super.key});

  @override
  State<DiagnosticReportButton> createState() => _DiagnosticReportButtonState();
}

class _DiagnosticReportButtonState extends State<DiagnosticReportButton> {
  bool _sending = false;

  Future<void> _send() async {
    setState(() => _sending = true);
    var message = 'Diagnóstico de prueba registrado para enviar a Firebase.';
    try {
      final reporter = FirebaseCrashlytics.instance;
      if (!reporter.isCrashlyticsCollectionEnabled) {
        throw StateError('Crashlytics no está activo en esta versión.');
      }
      await reporter.recordError(
        StateError('Tiago Market: comprobación de diagnóstico del piloto'),
        StackTrace.current,
        reason: 'pilot_diagnostics_check',
        printDetails: false,
      );
      await reporter.sendUnsentReports();
    } catch (_) {
      message = 'No se pudo registrar el diagnóstico en esta versión.';
    }
    if (!mounted) return;
    setState(() => _sending = false);
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
        onPressed: _sending ? null : _send,
        icon: const Icon(Icons.bug_report_outlined),
        label: const Text('Enviar diagnóstico de prueba'),
      );
}
