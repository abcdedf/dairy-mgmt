// lib/pages/help_page.dart
//
// In-app help screen. Accessible from the user popup menu (top-right).
// Accordion sections — one per feature area. Tap to expand/collapse.

import 'package:flutter/material.dart';
import 'shared_widgets.dart';

class HelpPage extends StatelessWidget {
  const HelpPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        backgroundColor: kNavy,
        foregroundColor: Colors.white,
        title: const Text('Help & Guide',
            style: TextStyle(fontWeight: FontWeight.w600)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: const [
          _Section(
            icon: Icons.info_outline,
            title: 'About This App',
            content:
                'This app helps you record and track all dairy production, '
                'purchases, and sales across your locations.\n\n'
                'Use the bottom navigation to switch between Production, Sales, '
                'Stock, and Reports. The location selector in the top bar lets '
                'you switch between locations if you have access to more than one.',
          ),
          _Section(
            icon: Icons.water_drop_outlined,
            title: 'FF Milk Purchase',
            content:
                'Record full-fat (FF) milk purchased from vendors.\n\n'
                '• Select the vendor from the dropdown.\n'
                '• Enter quantity in KG, SNF, Fat percentage, and the rate per KG.\n'
                '• SNF and Fat are used to assess milk quality.\n'
                '• Stock: FF Milk balance increases on purchase.',
          ),
          _Section(
            icon: Icons.settings_outlined,
            title: 'FF Milk Processing (FF Milk → Skim + Cream)',
            content:
                'Record how FF milk is processed into Skim Milk and Cream.\n\n'
                '• Enter how many KG of FF Milk were used.\n'
                '• Enter the Skim Milk output (KG) and its SNF percentage.\n'
                '• Enter the Cream output (KG) and its Fat percentage.\n'
                '• Stock: FF Milk balance decreases, Skim Milk and Cream balances increase.',
          ),
          _Section(
            icon: Icons.blender_outlined,
            title: 'Cream Processing (Cream → Butter / Ghee)',
            content:
                'Record how Cream is converted into Butter and/or Ghee.\n\n'
                '• Enter how many KG of Cream were used.\n'
                '• Butter output defaults to 0 — fill in only if butter was produced.\n'
                '• Enter Ghee output in KG.\n'
                '• Stock: Cream balance decreases, Butter and Ghee balances increase.',
          ),
          _Section(
            icon: Icons.set_meal_outlined,
            title: 'Dahi Production (Skim Milk → Dahi)',
            content:
                'Record Dahi production using Skim Milk, SMP, Protein, and Culture.\n\n'
                '• Enter Skim Milk used (KG) and SMP bags used.\n'
                '• Enter Protein and Culture quantities (KG).\n'
                '• Enter the number of containers filled. Each container holds 5 KG, '
                'so the Dahi KG is computed automatically.\n'
                '• Seal count mirrors the container count automatically.\n'
                '• Stock: Skim Milk, SMP, Protein, and Culture balances decrease. '
                'Dahi container balance increases.',
          ),
          _Section(
            icon: Icons.shopping_bag_outlined,
            title: 'SMP / Protein / Culture Purchase',
            content:
                'Record purchases of ingredients used in Dahi production.\n\n'
                '• At least one of SMP, Protein, or Culture must be entered to save.\n'
                '• All three can be entered in a single record if purchased together.\n'
                '• Rate is optional but recommended for profitability tracking.\n'
                '• SMP is measured in Bags, Protein and Culture in KG.\n'
                '• Stock: Balances for SMP, Protein, and Culture increase on purchase.',
          ),
          _Section(
            icon: Icons.kitchen_outlined,
            title: 'Cream & Butter Purchase',
            content:
                'Record externally purchased Cream or Butter (from outside vendors).\n\n'
                '• Enter quantity, Fat percentage, and rate per KG.\n'
                '• These increase the Cream or Butter stock balance just like '
                'internally produced quantities.',
          ),
          _Section(
            icon: Icons.local_fire_department_outlined,
            title: 'Butter Processing (Butter → Ghee)',
            content:
                'Record conversion of Butter into Ghee.\n\n'
                '• Enter how many KG of Butter were used.\n'
                '• Enter the Ghee output in KG.\n'
                '• Stock: Butter balance decreases, Ghee balance increases.',
          ),
          _Section(
            icon: Icons.point_of_sale_outlined,
            title: 'Sales',
            content:
                'Record product sales to customers.\n\n'
                '• Select the customer from the dropdown.\n'
                '• Enter product, quantity (KG), and rate per KG.\n'
                '• Multiple products can be added in one entry.\n'
                '• Stock: Product balance decreases on sale.',
          ),
          _Section(
            icon: Icons.inventory_2_outlined,
            title: 'Stock',
            content:
                'Shows the current running balance for each product at your location.\n\n'
                '• Balances are computed from all production, purchases, and sales '
                'over the last 30 days.\n'
                '• A negative balance may indicate missing entries or data errors.\n'
                '• Stock badges on the production form show live balances so you '
                'can see what is available before entering data.',
          ),
          _Section(
            icon: Icons.receipt_long_outlined,
            title: 'Transactions',
            content:
                'Shows a detailed log of all production and sales entries for the '
                'last N days (configured by the administrator).\n\n'
                '• Production tab: all production flows including purchases.\n'
                '• Sales tab: all customer sales with totals.\n'
                '• Each card shows the date, entry type, quantities, and the name '
                'of the person who recorded it.',
          ),
          _Section(
            icon: Icons.bar_chart_outlined,
            title: 'Reports',
            content:
                'Summary reports for analysis and review.\n\n'
                '• Sales Report: daily and product-wise sales totals.\n'
                '• Vendor Purchase Report: milk purchased per vendor with quality '
                'averages (SNF, Fat) and total amounts paid.',
          ),
          _Section(
            icon: Icons.tips_and_updates_outlined,
            title: 'Tips',
            content:
                '• Always enter data for the correct date — use the date picker '
                'at the top of the Production form.\n'
                '• Stock badges on each form show the current balance. Check them '
                'before entering quantities to avoid errors.\n'
                '• If a save fails, the error message appears below the form. '
                'Fix the highlighted issue and try again.\n'
                '• To review what was already entered, go to the Transactions tab '
                'rather than re-entering data on the Production page.',
          ),
        ],
      ),
    );
  }
}

// ── Accordion section ─────────────────────────────────────────

class _Section extends StatefulWidget {
  final IconData icon;
  final String   title;
  final String   content;
  const _Section({
    required this.icon,
    required this.title,
    required this.content,
  });

  @override
  State<_Section> createState() => _SectionState();
}

class _SectionState extends State<_Section> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: DCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              onTap: () => setState(() => _open = !_open),
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 4, vertical: 4),
                child: Row(children: [
                  Container(
                    width: 34, height: 34,
                    decoration: BoxDecoration(
                      color: kNavy.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(widget.icon, size: 18, color: kNavy),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(widget.title,
                        style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF1A2035))),
                  ),
                  Icon(
                    _open
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: kNavy,
                  ),
                ]),
              ),
            ),
            if (_open) ...[
              const Divider(height: 20),
              Text(widget.content,
                  style: const TextStyle(
                      fontSize: 13,
                      height: 1.6,
                      color: Color(0xFF3D4966))),
            ],
          ],
        ),
      ),
    );
  }
}
