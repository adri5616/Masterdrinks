import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../data/models/models.dart';

class PrintService {
  static final PrintService instance = PrintService._();
  PrintService._();

  Future<void> imprimirTicket({
    required BuildContext context,
    required int idComanda,
    required EventConfigModel config,
    required String cajeroNombre,
    required String? meseroNombre,
    required List<CartItemModel> items,
    required double total,
    required List<PaymentSplit> pagos,
    required String fechaHora,
  }) async {
    final doc = pw.Document();

    // Ticket térmico de 80mm / 58mm
    final pageFormat = PdfPageFormat.roll80;

    doc.addPage(
      pw.Page(
        pageFormat: pageFormat,
        margin: const pw.EdgeInsets.all(10),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              // Encabezado
              pw.Text(
                'MASTERDRINKS',
                style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
              ),
              pw.SizedBox(height: 2),
              pw.Text(
                config.evento.toUpperCase(),
                style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
                textAlign: pw.TextAlign.center,
              ),
              pw.Text(config.barra, style: const pw.TextStyle(fontSize: 10)),
              pw.Divider(thickness: 1),

              // Metadatos
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('COMANDA: #$idComanda', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 13)),
                  pw.Text(fechaHora.length > 16 ? fechaHora.substring(11, 16) : fechaHora, style: const pw.TextStyle(fontSize: 10)),
                ],
              ),
              pw.SizedBox(height: 3),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('CAJERO: $cajeroNombre', style: const pw.TextStyle(fontSize: 9)),
                  if (meseroNombre != null)
                    pw.Text('MESERO: $meseroNombre', style: const pw.TextStyle(fontSize: 9)),
                ],
              ),
              pw.Divider(thickness: 1),

              // Lista de productos
              pw.Row(
                children: [
                  pw.Expanded(flex: 4, child: pw.Text('CANT · PRODUCTO', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold))),
                  pw.Expanded(flex: 2, child: pw.Text('P.UNIT', textAlign: pw.TextAlign.right, style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold))),
                  pw.Expanded(flex: 2, child: pw.Text('TOTAL', textAlign: pw.TextAlign.right, style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold))),
                ],
              ),
              pw.SizedBox(height: 4),

              ...items.map((item) {
                return pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Row(
                      children: [
                        pw.Expanded(
                          flex: 4,
                          child: pw.Text(
                            '${item.cantidad}x ${item.name}',
                            style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
                          ),
                        ),
                        pw.Expanded(
                          flex: 2,
                          child: pw.Text(
                            item.unitPrice.toStringAsFixed(2),
                            textAlign: pw.TextAlign.right,
                            style: const pw.TextStyle(fontSize: 9),
                          ),
                        ),
                        pw.Expanded(
                          flex: 2,
                          child: pw.Text(
                            item.subtotal.toStringAsFixed(2),
                            textAlign: pw.TextAlign.right,
                            style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                    if (item.acompanante != null)
                      pw.Padding(
                        padding: const pw.EdgeInsets.only(left: 12),
                        child: pw.Text(
                          '+ Refresco: ${item.acompanante!.nombre} (Incluido)',
                          style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
                        ),
                      ),
                    pw.SizedBox(height: 3),
                  ],
                );
              }),

              pw.Divider(thickness: 1),

              // Totales
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('TOTAL:', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
                  pw.Text(
                    'Bs. ${total.toStringAsFixed(2)}',
                    style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
                  ),
                ],
              ),
              pw.SizedBox(height: 4),

              // Formas de pago
              ...pagos.map((p) => pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(p.metodo, style: const pw.TextStyle(fontSize: 9)),
                  pw.Text('Bs. ${p.monto.toStringAsFixed(2)}', style: const pw.TextStyle(fontSize: 9)),
                ],
              )),

              pw.Divider(thickness: 1),
              pw.SizedBox(height: 4),
              pw.Text('¡GRACIAS POR SU COMPRA!', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
              pw.Text('EUPHORIA · MASTERDRINKS POS', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
              pw.SizedBox(height: 10),
            ],
          );
        },
      ),
    );

    // Enviar a impresión directa o preview
    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => doc.save(),
      name: 'Ticket_Comanda_$idComanda.pdf',
    );
  }
}
