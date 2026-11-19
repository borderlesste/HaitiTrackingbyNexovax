import 'package:flutter/material.dart';

import 'theme.dart';

class BrandHeader extends StatelessWidget {
  const BrandHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: HtColors.navy,
      padding: EdgeInsets.fromLTRB(20, MediaQuery.of(context).padding.top + 28, 20, 28),
      child: const Row(
        children: [
          Icon(Icons.location_on, color: HtColors.red, size: 44),
          SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('HAITI TRACKING',
                  style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: .5)),
              Text('by Nexovax', style: TextStyle(color: Colors.white70, fontSize: 14)),
            ],
          ),
        ],
      ),
    );
  }
}
