import 'dart:typed_data';

import 'package:excel/excel.dart' as xlsx;
import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Builds and saves PDF / Excel (xlsx) reports for any tabular data.
/// Used by the Super Admin dashboard (shops report) and inventory screens.
class ReportExporter {
  static pw.Table _table(List<String> headers, List<List<String>> rows) {
    return pw.TableHelper.fromTextArray(
      headers: headers,
      data: rows,
      headerStyle: pw.TextStyle(
        fontSize: 9,
        font: pw.Font.timesBold(),
        color: PdfColors.teal900,
      ),
      cellStyle: const pw.TextStyle(fontSize: 9),
      border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
      headerDecoration: const pw.BoxDecoration(color: PdfColors.teal50),
      cellAlignment: pw.Alignment.centerLeft,
    );
  }

  static Future<void> exportPdf(
    BuildContext context, {
    required String fileName,
    required String title,
    required List<String> headers,
    required List<List<String>> rows,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    await exportPdfWithMessenger(
      messenger,
      fileName: fileName,
      title: title,
      headers: headers,
      rows: rows,
    );
  }

  /// Context-free variant: capture the messenger before any await.
  static Future<void> exportPdfWithMessenger(
    ScaffoldMessengerState messenger, {
    required String fileName,
    required String title,
    required List<String> headers,
    required List<List<String>> rows,
  }) async {
    final pdf = pw.Document();
    final boldFont = pw.Font.timesBold();
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        build: (context) => [
          pw.Text(
            title,
            style: pw.TextStyle(fontSize: 18, font: boldFont),
          ),
          pw.Text(
            'MediManage Pharmacy Management · generated ${DateTime.now()}',
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
          ),
          pw.SizedBox(height: 12),
          _table(headers, rows),
        ],
      ),
    );
    final Uint8List bytes = await pdf.save();
    try {
      await FileSaver.instance.saveFile(
        name: '$fileName-${DateTime.now().millisecondsSinceEpoch}',
        bytes: bytes,
        fileExtension: 'pdf',
        mimeType: MimeType.pdf,
      );
      messenger.showSnackBar(
        const SnackBar(content: Text('PDF report saved')),
      );
    } catch (error) {
      debugPrint('PDF save failed: $error');
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not save PDF report')),
      );
    }
  }

  static Future<void> exportExcel(
    BuildContext context, {
    required String fileName,
    required String sheetName,
    required List<String> headers,
    required List<List<String>> rows,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    await exportExcelWithMessenger(
      messenger,
      fileName: fileName,
      sheetName: sheetName,
      headers: headers,
      rows: rows,
    );
  }

  /// Context-free variant: capture the messenger before any await.
  static Future<void> exportExcelWithMessenger(
    ScaffoldMessengerState messenger, {
    required String fileName,
    required String sheetName,
    required List<String> headers,
    required List<List<String>> rows,
  }) async {
    final excel = xlsx.Excel.createExcel();
    final sheet = sheetObject(excel, sheetName);
    sheet.appendRow([for (final h in headers) xlsx.TextCellValue(h)]);
    for (final row in rows) {
      sheet.appendRow([for (final cell in row) xlsx.TextCellValue(cell)]);
    }
    final Uint8List bytes = Uint8List.fromList(excel.save() ?? <int>[]);
    if (bytes.isEmpty) throw StateError('Could not build Excel file');
    try {
      await FileSaver.instance.saveFile(
        name: '$fileName-${DateTime.now().millisecondsSinceEpoch}',
        bytes: bytes,
        // The Excel package emits a real .xlsx workbook.
        fileExtension: 'xlsx',
        mimeType: MimeType.microsoftExcel,
      );
      messenger.showSnackBar(
        const SnackBar(content: Text('Excel report saved')),
      );
    } catch (error) {
      debugPrint('Excel save failed: $error');
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not save Excel report')),
      );
    }
  }

  static xlsx.Sheet sheetObject(xlsx.Excel excel, String sheetName) {
    // Only one sheet is appended per export; renaming the default sheet works
    // across excel package versions.
    return excel[sheetName];
  }
}
