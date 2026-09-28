import 'dart:io';
import 'package:flutter/material.dart';
import '../../evidence/application/evidence_controller.dart';
import '../../evidence/domain/evidence_image.dart';
import '../../../core/widgets/iris_card.dart';
import '../../../app/theme/iris_spacing.dart';
import '../application/multiview_service.dart';
import '../domain/multiview_pair_analysis.dart';

class MultiViewSection extends StatefulWidget {
  const MultiViewSection({required this.controller, required this.service, super.key});
  final EvidenceController controller;
  final MultiViewService service;
  @override State<MultiViewSection> createState() => _MultiViewSectionState();
}
class _MultiViewSectionState extends State<MultiViewSection> {
  EvidenceImage? a, b; MultiViewPairAnalysis? result; bool busy = false;
  @override Widget build(BuildContext context) => AnimatedBuilder(animation: widget.controller, builder: (_, __) {
    final items = widget.controller.items;
    if (items.length < 2) return const IrisCard(child: Text('MULTI-VIEW GEOMETRY\nAdditional views can improve spatial reconstruction.'));
    a ??= items.first; b ??= items[1];
    return IrisCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('MULTI-VIEW GEOMETRY', style: Theme.of(context).textTheme.titleMedium), const SizedBox(height: IrisSpacing.sm),
      DropdownButton<EvidenceImage>(isExpanded: true, value: a, items: items.map((e) => DropdownMenuItem(value: e, child: Text(e.originalDisplayName ?? e.id))).toList(), onChanged: (v) => setState(() { a = v; result = null; })),
      DropdownButton<EvidenceImage>(isExpanded: true, value: b, items: items.map((e) => DropdownMenuItem(value: e, child: Text(e.originalDisplayName ?? e.id))).toList(), onChanged: (v) => setState(() { b = v; result = null; })),
      FilledButton(onPressed: busy || a?.id == b?.id ? null : _analyze, child: Text(busy ? 'Analyzing…' : 'Analyze Pair')),
      if (result != null) ...[_Result(result: result!, a: a!, b: b!, service: widget.service)],
    ]));
  });
  Future<void> _analyze() async { final x=a, y=b; if(x==null||y==null||x.id==y.id)return; setState(()=>busy=true); try { final r=await widget.service.analyze(caseId: x.caseId, a:x, b:y); if(mounted)setState(()=>result=r); } finally { if(mounted)setState(()=>busy=false); } }
}
class _Result extends StatelessWidget { const _Result({required this.result, required this.a, required this.b, required this.service}); final MultiViewPairAnalysis result; final EvidenceImage a,b; final MultiViewService service;
  @override Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const SizedBox(height: IrisSpacing.sm), Text('Features A: ${result.featureCountA}'), Text('Features B: ${result.featureCountB}'), Text('Descriptor matches: ${result.acceptedMatchCount}'), Text('Verified geometric matches: ${result.verifiedInlierCount}'), Text('Geometric model: Fundamental matrix / epipolar'), Text('Status: ${result.status.name}'), const SizedBox(height: IrisSpacing.xs), const Text('Verified correspondence indicates image-level geometric consistency; it is not a metric 3D measurement.'), if(result.status==MultiViewStatus.verifiedCorrespondence) ...[const SizedBox(height: IrisSpacing.sm), Text('Multi-view correspondence established. Metric 3D fusion requires additional calibration/spatial constraints.'), _MatchPreview(result:result,a:a,b:b,service:service)] ]);
}
class _MatchPreview extends StatelessWidget { const _MatchPreview({required this.result,required this.a,required this.b,required this.service}); final MultiViewPairAnalysis result; final EvidenceImage a,b; final MultiViewService service;
  @override Widget build(BuildContext context)=>FutureBuilder<List<String>>(future: Future.wait([service.storage.absolutePath(a.storedRelativePath),service.storage.absolutePath(b.storedRelativePath)]),builder:(c,s)=>s.hasData?Row(children:[Expanded(child:_OverlayImage(path:s.data![0],width:result.imageWidthA,height:result.imageHeightA,points:result.correspondences,left:true)),Expanded(child:_OverlayImage(path:s.data![1],width:result.imageWidthB,height:result.imageHeightB,points:result.correspondences,left:false))]):const SizedBox(height:80));
}
class _OverlayImage extends StatelessWidget { const _OverlayImage({required this.path,required this.width,required this.height,required this.points,required this.left}); final String path; final int width,height; final List<List<double>> points; final bool left;
  @override Widget build(BuildContext context)=>AspectRatio(aspectRatio:width/height,child:Stack(fit:StackFit.expand,children:[Image.file(File(path),fit:BoxFit.contain),CustomPaint(painter:_CorrespondencePainter(width:width,height:height,points:points,left:left))]));
}
class _CorrespondencePainter extends CustomPainter { const _CorrespondencePainter({required this.width,required this.height,required this.points,required this.left}); final int width,height; final List<List<double>> points; final bool left;
  @override void paint(Canvas canvas,Size size){final p=Paint()..color=Colors.amber..style=PaintingStyle.fill; for(final point in points){if(point.length<4)continue; final x=(point[left?0:2]/width)*size.width; final y=(point[left?1:3]/height)*size.height; if(x.isFinite&&y.isFinite)canvas.drawCircle(Offset(x,y),4,p);}}
  @override bool shouldRepaint(covariant _CorrespondencePainter old)=>old.points!=points||old.left!=left||old.width!=width||old.height!=height;
}
