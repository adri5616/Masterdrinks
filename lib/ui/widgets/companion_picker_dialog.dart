import 'package:flutter/material.dart';
import '../../config/theme.dart';
import '../../data/models/models.dart';
import 'glass_card.dart';

class CompanionPickerDialog extends StatelessWidget {
  final ProductModel product;
  final List<ProductModel> companions;

  const CompanionPickerDialog({
    super.key,
    required this.product,
    required this.companions,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: GlassCard(
          borderRadius: 20,
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppTheme.amberGold.withOpacity(0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.liquor, color: AppTheme.amberGold, size: 28),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          product.nombre,
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'Selecciona el refresco / mezclador incluido:',
                          style: TextStyle(fontSize: 13, color: Colors.white70),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              const Divider(color: AppTheme.borderGlass),
              const SizedBox(height: 10),

              if (companions.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Text(
                      'No hay refrescos/acompañantes con stock disponible.',
                      style: TextStyle(color: Colors.white54),
                    ),
                  ),
                )
              else
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: companions.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final comp = companions[index];
                      return ListTile(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: const BorderSide(color: AppTheme.borderGlass),
                        ),
                        tileColor: AppTheme.surfaceGlass,
                        leading: const Icon(Icons.local_drink, color: AppTheme.amberGold),
                        title: Text(
                          comp.nombre,
                          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                        subtitle: Text(
                          'Stock: ${comp.stockActual} disp. · Incluido (Bs. 0.00)',
                          style: const TextStyle(color: Colors.white60, fontSize: 12),
                        ),
                        trailing: const Icon(Icons.check_circle_outline, color: AppTheme.amberGold),
                        onTap: () => Navigator.of(context).pop(comp),
                      );
                    },
                  ),
                ),

              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(null),
                    child: const Text('Cancelar', style: TextStyle(color: Colors.white60)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
