// lib/core/document_pdf.dart

import 'package:flutter/foundation.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';
import '../controllers/challan_controller.dart';
import '../controllers/invoice_controller.dart';
import 'api_client.dart';

/// Company info loaded from backend.
class CompanyInfo {
  final String name;
  final String address;
  final String phone;
  final String email;
  final String website;
  final String gstin;
  final String signatory;

  const CompanyInfo({
    this.name = '',
    this.address = '',
    this.phone = '',
    this.email = '',
    this.website = '',
    this.gstin = '',
    this.signatory = '',
  });

  factory CompanyInfo.fromJson(Map<String, dynamic> j) => CompanyInfo(
    name:      j['company_name']?.toString() ?? '',
    address:   j['company_address']?.toString() ?? '',
    phone:     j['company_phone']?.toString() ?? '',
    email:     j['company_email']?.toString() ?? '',
    website:   j['company_website']?.toString() ?? '',
    gstin:     j['company_gstin']?.toString() ?? '',
    signatory: j['company_signatory']?.toString() ?? '',
  );

  static Future<CompanyInfo> fetch() async {
    try {
      final res = await ApiClient.get('/company-settings');
      if (res.ok) {
        debugPrint('[DocumentPdf] Company info loaded: ${res.data}');
        return CompanyInfo.fromJson(res.data as Map<String, dynamic>);
      }
    } catch (e) {
      debugPrint('[DocumentPdf] Failed to load company info: $e');
    }
    return const CompanyInfo();
  }
}

class DocumentPdf {
  static final _inrFmt = NumberFormat('#,##,##0.00', 'en_IN');
  static final _dateFmt = DateFormat('dd/MM/yyyy');

  static String _fmtDate(String d) {
    try { return _dateFmt.format(DateTime.parse(d)); } catch (_) { return d; }
  }

  // ── Challan PDF ──────────────────────────────────────

  static Future<void> showChallanPdf(Challan challan) async {
    final company = await CompanyInfo.fetch();
    debugPrint('[DocumentPdf] Generating challan PDF: DC-${challan.challanNumber}');
    await Printing.layoutPdf(
      onLayout: (_) => _buildChallanPdf(challan, company),
      name: 'DC-${challan.challanNumber}',
    );
  }

  static Future<Uint8List> _buildChallanPdf(Challan ch, CompanyInfo co) async {
    final pdf = pw.Document();

    pdf.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      build: (ctx) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _companyHeader(co),
          pw.SizedBox(height: 8),
          pw.Divider(thickness: 1),
          pw.SizedBox(height: 12),

          // Title + number/date
          pw.Center(child: pw.Text('Delivery Challan',
              style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold))),
          pw.SizedBox(height: 8),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.end,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text('Challan No: DC-${ch.challanNumber}',
                      style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                  pw.Text('Date: ${_fmtDate(ch.challanDate)}'),
                ],
              ),
            ],
          ),
          pw.SizedBox(height: 16),

          // Customer info
          pw.Text('M/S ${ch.partyName}',
              style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
          if (ch.billingAddressSnapshot != null && ch.billingAddressSnapshot!.isNotEmpty)
            pw.Text(ch.billingAddressSnapshot!,
                style: const pw.TextStyle(fontSize: 10)),
          if (ch.shippingAddressSnapshot != null && ch.shippingAddressSnapshot!.isNotEmpty) ...[
            pw.SizedBox(height: 4),
            pw.Text('Ship To: ${ch.shippingAddressSnapshot!}',
                style: const pw.TextStyle(fontSize: 10)),
          ],
          pw.SizedBox(height: 16),

          // Line items table
          pw.TableHelper.fromTextArray(
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10),
            cellStyle: const pw.TextStyle(fontSize: 10),
            headerDecoration: const pw.BoxDecoration(
                color: PdfColor.fromInt(0xFFE8F5E9)),
            cellAlignment: pw.Alignment.centerLeft,
            headerAlignment: pw.Alignment.centerLeft,
            columnWidths: {
              0: const pw.FixedColumnWidth(30),
              1: const pw.FlexColumnWidth(3),
              2: const pw.FixedColumnWidth(60),
              3: const pw.FixedColumnWidth(50),
            },
            headers: ['#', 'Item', 'Unit', 'Qty'],
            data: List.generate(ch.lines.length, (i) {
              final l = ch.lines[i];
              return [
                '${i + 1}',
                l.productName,
                l.productUnit,
                l.qty.toInt().toString(),
              ];
            }),
          ),
          pw.SizedBox(height: 24),

          // Sign-off
          pw.Text('Yours faithfully,', style: const pw.TextStyle(fontSize: 10)),
          if (co.name.isNotEmpty)
            pw.Text('For ${co.name}',
                style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
          if (co.signatory.isNotEmpty) ...[
            pw.SizedBox(height: 24),
            pw.Text(co.signatory, style: const pw.TextStyle(fontSize: 10)),
          ],

          pw.Spacer(),

          // Footer
          pw.Divider(thickness: 0.5),
          _companyFooter(co),
        ],
      ),
    ));

    return pdf.save();
  }

  // ── Invoice PDF ──────────────────────────────────────

  static Future<void> showInvoicePdf(Invoice invoice) async {
    final company = await CompanyInfo.fetch();
    debugPrint('[DocumentPdf] Generating invoice PDF: INV-${invoice.invoiceNumber}');
    await Printing.layoutPdf(
      onLayout: (_) => _buildInvoicePdf(invoice, company),
      name: 'INV-${invoice.invoiceNumber}',
    );
  }

  static Future<Uint8List> _buildInvoicePdf(Invoice inv, CompanyInfo co) async {
    final pdf = pw.Document();

    pdf.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      build: (ctx) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _companyHeader(co),
          pw.SizedBox(height: 8),
          pw.Divider(thickness: 1),
          pw.SizedBox(height: 12),

          // Title + number/date
          pw.Center(child: pw.Text('Tax Invoice',
              style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold))),
          pw.SizedBox(height: 8),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.end,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text('Inv. No: INV-${inv.invoiceNumber}',
                      style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                  pw.Text('Date: ${_fmtDate(inv.invoiceDate)}'),
                ],
              ),
            ],
          ),
          pw.SizedBox(height: 16),

          // Customer info
          pw.Text('M/S ${inv.partyName}',
              style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
          if (inv.billingAddressSnapshot != null && inv.billingAddressSnapshot!.isNotEmpty)
            pw.Text(inv.billingAddressSnapshot!,
                style: const pw.TextStyle(fontSize: 10)),
          if (inv.shippingAddressSnapshot != null && inv.shippingAddressSnapshot!.isNotEmpty &&
              inv.shippingAddressSnapshot != inv.billingAddressSnapshot) ...[
            pw.SizedBox(height: 4),
            pw.Text('Ship To: ${inv.shippingAddressSnapshot!}',
                style: const pw.TextStyle(fontSize: 10)),
          ],

          // Challan references
          if (inv.challans.isNotEmpty) ...[
            pw.SizedBox(height: 4),
            pw.Text(
              'Challans: ${inv.challans.map((c) => 'DC-${c.challanNumber}').join(', ')}',
              style: pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
            ),
          ],
          pw.SizedBox(height: 16),

          // Line items table with financial columns
          pw.TableHelper.fromTextArray(
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10),
            cellStyle: const pw.TextStyle(fontSize: 10),
            headerDecoration: const pw.BoxDecoration(
                color: PdfColor.fromInt(0xFFE8EAF6)),
            columnWidths: {
              0: const pw.FixedColumnWidth(30),
              1: const pw.FlexColumnWidth(3),
              2: const pw.FixedColumnWidth(50),
              3: const pw.FixedColumnWidth(60),
              4: const pw.FixedColumnWidth(70),
              5: const pw.FixedColumnWidth(80),
            },
            cellAlignments: {
              0: pw.Alignment.center,
              1: pw.Alignment.centerLeft,
              2: pw.Alignment.center,
              3: pw.Alignment.centerRight,
              4: pw.Alignment.centerRight,
              5: pw.Alignment.centerRight,
            },
            headerAlignments: {
              0: pw.Alignment.center,
              1: pw.Alignment.centerLeft,
              2: pw.Alignment.center,
              3: pw.Alignment.centerRight,
              4: pw.Alignment.centerRight,
              5: pw.Alignment.centerRight,
            },
            headers: ['#', 'Item', 'Unit', 'Qty', 'Rate', 'Amount'],
            data: [
              ...List.generate(inv.lines.length, (i) {
                final l = inv.lines[i];
                return [
                  '${i + 1}',
                  l.productName,
                  l.productUnit,
                  l.totalQty.toInt().toString(),
                  _inrFmt.format(l.avgRate),
                  _inrFmt.format(l.totalAmount),
                ];
              }),
              // Tax row
              ['', 'IGST', '', '', '0%', '-'],
              // Total row
              ['', '', '', '', 'TOTAL', _inrFmt.format(inv.total)],
            ],
          ),
          pw.SizedBox(height: 8),

          // Amount in bold
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Text('Total: Rs. ${_inrFmt.format(inv.total)}',
                style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
          ),
          pw.SizedBox(height: 24),

          // Sign-off
          pw.Text('Yours faithfully,', style: const pw.TextStyle(fontSize: 10)),
          if (co.name.isNotEmpty)
            pw.Text('For ${co.name}',
                style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
          if (co.signatory.isNotEmpty) ...[
            pw.SizedBox(height: 24),
            pw.Text(co.signatory, style: const pw.TextStyle(fontSize: 10)),
          ],

          pw.Spacer(),

          // Footer
          pw.Divider(thickness: 0.5),
          _companyFooter(co),
        ],
      ),
    ));

    return pdf.save();
  }

  // ── Shared helpers ──────────────────────────────────

  static pw.Widget _companyHeader(CompanyInfo co) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            if (co.name.isNotEmpty)
              pw.Text(co.name,
                  style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
            if (co.address.isNotEmpty)
              pw.Text(co.address, style: const pw.TextStyle(fontSize: 9)),
            if (co.gstin.isNotEmpty)
              pw.Text('GSTIN: ${co.gstin}', style: const pw.TextStyle(fontSize: 9)),
            pw.SizedBox(height: 4),
            if (co.phone.isNotEmpty)
              pw.Text('Phone: ${co.phone}', style: const pw.TextStyle(fontSize: 9)),
            if (co.email.isNotEmpty)
              pw.Text('Email: ${co.email}', style: const pw.TextStyle(fontSize: 9)),
            if (co.website.isNotEmpty)
              pw.Text(co.website, style: const pw.TextStyle(fontSize: 9)),
          ],
        )),
      ],
    );
  }

  static pw.Widget _companyFooter(CompanyInfo co) {
    final parts = <String>[];
    if (co.name.isNotEmpty) parts.add(co.name);
    if (co.phone.isNotEmpty) parts.add('Ph: ${co.phone}');
    if (co.email.isNotEmpty) parts.add(co.email);
    return pw.Center(
      child: pw.Text(
        parts.join('  |  '),
        style: pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
      ),
    );
  }
}
