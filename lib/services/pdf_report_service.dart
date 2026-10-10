import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../data/models/models.dart';

class PdfReportService {
  static final PdfReportService instance = PdfReportService._();
  PdfReportService._();

  Future<void> generarReporteCierre({
    required EventConfigModel config,
    required Map<String, dynamic> datosReporte,
  }) async {
    final doc = pw.Document();

    final totales = (datosReporte['totales'] as Map<String, dynamic>?) ?? {};
    final metodos = (datosReporte['metodos_pago'] as List?) ?? [];
    final productos = (datosReporte['productos'] as List?) ?? [];
    final meseros = (datosReporte['meseros'] as List?) ?? [];

    final totalComandas = totales['total_comandas'] ?? 0;
    final totalVentas = (totales['total_ventas'] is num) ? (totales['total_ventas'] as num).toDouble() : 0.0;

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) {
          return [
            // Cabecera
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('MASTERDRINKS POS', style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold, color: PdfColors.amber800)),
                    pw.Text('REPORTE OFICIAL DE CIERRE DE CAJA', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text(config.evento, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12)),
                    pw.Text('${config.barra} · ${config.fecha}', style: const pw.TextStyle(fontSize: 10)),
                  ],
                ),
              ],
            ),
            pw.Divider(thickness: 2, color: PdfColors.amber800),
            pw.SizedBox(height: 12),

            // Resumen de Ventas
            pw.Text('RESUMEN GENERAL', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 6),
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey300),
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                  children: [
                    pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('Concepto', style: pw.TextStyle(fontWeight: pw.FontWeight.bold))),
                    pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('Valor', textAlign: pw.TextAlign.right, style: pw.TextStyle(fontWeight: pw.FontWeight.bold))),
                  ],
                ),
                pw.TableRow(
                  children: [
                    pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('Total Comandas Cobradas')),
                    pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('$totalComandas', textAlign: pw.TextAlign.right)),
                  ],
                ),
                pw.TableRow(
                  children: [
                    pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('TOTAL RECAUDADO (Bs.)', style: pw.TextStyle(fontWeight: pw.FontWeight.bold))),
                    pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('Bs. ${totalVentas.toStringAsFixed(2)}', textAlign: pw.TextAlign.right, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.amber900))),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 16),

            // Desglose por método de pago
            pw.Text('VENTAS POR MÉTODO DE PAGO', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 6),
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey300),
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                  children: [
                    pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('Método', style: pw.TextStyle(fontWeight: pw.FontWeight.bold))),
                    pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('Monto (Bs.)', textAlign: pw.TextAlign.right, style: pw.TextStyle(fontWeight: pw.FontWeight.bold))),
                  ],
                ),
                ...metodos.map((m) {
                  final monto = (m['monto'] is num) ? (m['monto'] as num).toDouble() : 0.0;
                  return pw.TableRow(
                    children: [
                      pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text(m['metodo'] ?? '')),
                      pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('Bs. ${monto.toStringAsFixed(2)}', textAlign: pw.TextAlign.right)),
                    ],
                  );
                }),
              ],
            ),
            pw.SizedBox(height: 16),

            // Productos vendidos
            pw.Text('TOP PRODUCTOS DESPACHADOS', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 6),
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey300),
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                  children: [
                    pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('Producto', style: pw.TextStyle(fontWeight: pw.FontWeight.bold))),
                    pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('Unidades', textAlign: pw.TextAlign.center, style: pw.TextStyle(fontWeight: pw.FontWeight.bold))),
                    pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('Total (Bs.)', textAlign: pw.TextAlign.right, style: pw.TextStyle(fontWeight: pw.FontWeight.bold))),
                  ],
                ),
                ...productos.take(15).map((p) {
                  final unidades = p['total_unidades'] ?? 0;
                  final totalRec = (p['total_recaudado'] is num) ? (p['total_recaudado'] as num).toDouble() : 0.0;
                  return pw.TableRow(
                    children: [
                      pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text(p['nombre'] ?? '')),
                      pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('$unidades', textAlign: pw.TextAlign.center)),
                      pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('Bs. ${totalRec.toStringAsFixed(2)}', textAlign: pw.TextAlign.right)),
                    ],
                  );
                }),
              ],
            ),
            pw.SizedBox(height: 16),

            if (meseros.isNotEmpty) ...[
              pw.Text('VENTAS POR MESERO', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 6),
              pw.Table(
                border: pw.TableBorder.all(color: PdfColors.grey300),
                children: [
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                    children: [
                      pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('Mesero', style: pw.TextStyle(fontWeight: pw.FontWeight.bold))),
                      pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('Comandas', textAlign: pw.TextAlign.center, style: pw.TextStyle(fontWeight: pw.FontWeight.bold))),
                      pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('Total (Bs.)', textAlign: pw.TextAlign.right, style: pw.TextStyle(fontWeight: pw.FontWeight.bold))),
                    ],
                  ),
                  ...meseros.map((m) {
                    final total = (m['total'] is num) ? (m['total'] as num).toDouble() : 0.0;
                    return pw.TableRow(
                      children: [
                        pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text(m['nombre'] ?? '')),
                        pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('${m['comandas'] ?? 0}', textAlign: pw.TextAlign.center)),
                        pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('Bs. ${total.toStringAsFixed(2)}', textAlign: pw.TextAlign.right)),
                      ],
                    );
                  }),
                ],
              ),
              pw.SizedBox(height: 20),
            ],


            // Firmas
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
              children: [
                pw.Column(
                  children: [
                    pw.Container(width: 140, height: 1, color: PdfColors.black),
                    pw.SizedBox(height: 4),
                    pw.Text('Firma Cajero', style: const pw.TextStyle(fontSize: 10)),
                  ],
                ),
                pw.Column(
                  children: [
                    pw.Container(width: 140, height: 1, color: PdfColors.black),
                    pw.SizedBox(height: 4),
                    pw.Text('Firma Administrador / Responsable', style: const pw.TextStyle(fontSize: 10)),
                  ],
                ),
              ],
            ),
          ];
        },
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => doc.save(),
      name: 'Cierre_Caja_${config.barra}.pdf',
    );
  }
}
