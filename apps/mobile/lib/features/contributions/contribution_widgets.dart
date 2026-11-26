import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../core/ui.dart';
import 'contribution_service.dart';

class ContributionStatusChip extends StatelessWidget {
  const ContributionStatusChip(this.status, {super.key});
  final String? status;

  @override
  Widget build(BuildContext context) {
    final tone = switch (status) {
      'APPROVED' => ChipTone.ok,
      'REJECTED' => ChipTone.bad,
      'NEEDS_CHANGES' => ChipTone.bad,
      _ => ChipTone.review,
    };
    return StatusChip(contributionStatusLabels[status] ?? (status ?? ''), tone: tone);
  }
}

/// Miniatura del lugar: foto local, foto del servidor o icono de tienda.
class PlaceThumb extends StatelessWidget {
  const PlaceThumb({super.key, this.url, this.file, this.size = 72});
  final String? url;
  final File? file;
  final double size;

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      color: HtColors.blueSoft,
      child: Icon(Icons.storefront, color: HtColors.blue, size: size * .5),
    );
    Widget img;
    if (file != null) {
      img = Image.file(file!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => placeholder);
    } else if (url != null) {
      img = Image.network(url!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => placeholder);
    } else {
      img = placeholder;
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(width: size * 1.15, height: size, child: img),
    );
  }
}
