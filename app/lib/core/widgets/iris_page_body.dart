import 'package:flutter/material.dart';

import '../../app/theme/iris_spacing.dart';

class IrisPageBody extends StatelessWidget {
  const IrisPageBody({
    required this.children,
    this.safeTop = false,
    this.maxContentWidth = 720,
    super.key,
  });

  final List<Widget> children;
  final bool safeTop;
  final double maxContentWidth;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: safeTop,
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          return Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxContentWidth),
              child: ListView(
                padding: EdgeInsets.fromLTRB(
                  IrisSpacing.pageHorizontal(constraints.maxWidth),
                  IrisSpacing.md,
                  IrisSpacing.pageHorizontal(constraints.maxWidth),
                  IrisSpacing.lg,
                ),
                children: children,
              ),
            ),
          );
        },
      ),
    );
  }
}
