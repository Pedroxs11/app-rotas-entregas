import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vibration/vibration.dart';
import '../app_state.dart';
import '../domain/models.dart';
import '../services/ocr_service.dart';
import '../services/barcode_service.dart';

class ScannerScreen extends StatefulWidget {
  final AppState state;
  const ScannerScreen({super.key, required this.state});
  @override State<ScannerScreen> createState()=>_ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen>{
  CameraController? _camera;
  final _ocr=OcrService();
  final _barcode=BarcodeService();
  bool _busy=false,_torch=false;
  String _message='Enquadre DESTINATÁRIO e, se possível, o código da etiqueta';
  int _captured=0,_review=0,_failed=0;
  DateTime? _lastCaptureAt;

  @override void initState(){super.initState();_init();}
  Future<void> _init() async {try{final cams=await availableCameras();if(cams.isEmpty)throw Exception('Nenhuma câmera encontrada');final back=cams.where((c)=>c.lensDirection==CameraLensDirection.back).firstOrNull??cams.first;final controller=CameraController(back,ResolutionPreset.high,enableAudio:false);await controller.initialize();if(!mounted){await controller.dispose();return;}setState(()=>_camera=controller);}catch(e){if(mounted)setState(()=>_message='Não foi possível abrir a câmera: $e');}}
  Future<void> _toggleTorch()async{final c=_camera;if(c==null)return;try{_torch=!_torch;await c.setFlashMode(_torch?FlashMode.torch:FlashMode.off);if(mounted)setState((){});}catch(_){if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Flash não disponível nesta câmera.')));}}

  Future<void> _feedback({required bool success,required bool review}) async {
    try{
      await SystemSound.play(success?SystemSoundType.click:SystemSoundType.alert);
    }catch(_){/* vibration remains the fallback */}
    try{
      if((await Vibration.hasVibrator())==true){
        if(!success){
          Vibration.vibrate(pattern:[0,80,70,80]);
        }else{
          Vibration.vibrate(duration:review?160:70);
        }
      }
    }catch(_){/* feedback must never block the next package */}
  }

  Future<void> _capture() async {
    if(_busy||_camera?.value.isInitialized!=true)return;
    final now=DateTime.now();
    if(_lastCaptureAt!=null&&now.difference(_lastCaptureAt!)<const Duration(milliseconds:350))return;
    _lastCaptureAt=now;
    setState((){_busy=true;_message='Lendo endereço e identificador...';});
    try{
      final file=await _camera!.takePicture();
      final results=await Future.wait<dynamic>([_ocr.recognizeFile(file.path),_barcode.recognizeFile(file.path)]);
      final text=results[0] as String;
      final tracking=results[1] as String?;
      if(text.trim().isEmpty)throw Exception('Nenhum endereço encontrado');
      final before=widget.state.packages.length;
      await widget.state.addFromText(text,trackingCode:tracking);
      if(widget.state.packages.length<=before)throw Exception('Este pacote parece já ter sido registrado');
      final p=widget.state.packages.last;
      _captured++;
      final needsReview=p.address.validation!=ValidationStatus.confirmed;
      if(needsReview)_review++;
      await _feedback(success:true,review:needsReview);
      final linked=tracking!=null?' • código vinculado':'';
      if(mounted)setState(()=>_message=!needsReview?'✓ ${p.label} pronto$linked — próximo':'⚠ ${p.label} salvo para revisar$linked — próximo');
    }catch(e){
      _failed++;
      await _feedback(success:false,review:false);
      if(mounted)setState(()=>_message='Não registrei: $e • tente novamente');
    }finally{if(mounted)setState(()=>_busy=false);}
  }

  @override void dispose(){_camera?.dispose();_ocr.dispose();_barcode.dispose();super.dispose();}
  @override Widget build(BuildContext context){
    final c=_camera;
    return Scaffold(
      backgroundColor:Colors.black,
      appBar:AppBar(
        title:Text('Scanner • $_captured salvos'),
        actions:[
          if(_review>0)Center(child:Padding(padding:const EdgeInsets.only(right:8),child:Text('⚠ $_review'))),
          if(_failed>0)Center(child:Padding(padding:const EdgeInsets.only(right:8),child:Text('↻ $_failed'))),
          IconButton(onPressed:c==null?null:_toggleTorch,tooltip:_torch?'Desligar lanterna':'Ligar lanterna',icon:Icon(_torch?Icons.flash_on:Icons.flash_off))
        ],
      ),
      body:Column(children:[
        Expanded(child:c==null?const Center(child:CircularProgressIndicator()):Stack(fit:StackFit.expand,children:[
          CameraPreview(c),
          IgnorePointer(child:CustomPaint(painter:_ScanFramePainter())),
          Positioned(left:24,right:24,top:18,child:Container(padding:const EdgeInsets.symmetric(horizontal:14,vertical:10),decoration:BoxDecoration(color:Colors.black.withValues(alpha:.68),borderRadius:BorderRadius.circular(12)),child:const Text('Priorize DESTINATÁRIO / endereço de entrega.\nSe o código de barras ou QR couber na foto, o app também vincula o pacote.',textAlign:TextAlign.center,style:TextStyle(color:Colors.white,fontWeight:FontWeight.w600))))
        ])),
        Container(color:Theme.of(context).colorScheme.surface,padding:const EdgeInsets.fromLTRB(16,12,16,20),child:SafeArea(top:false,child:Column(children:[
          Row(mainAxisAlignment:MainAxisAlignment.center,children:[
            _SessionChip(icon:Icons.check_circle_outline,label:'$_captured salvos'),
            const SizedBox(width:8),
            _SessionChip(icon:Icons.rate_review_outlined,label:'$_review revisar'),
            const SizedBox(width:8),
            _SessionChip(icon:Icons.refresh,label:'$_failed falhas'),
          ]),
          const SizedBox(height:10),
          Text(_message,textAlign:TextAlign.center,maxLines:2,overflow:TextOverflow.ellipsis),
          const SizedBox(height:10),
          Row(children:[
            Expanded(flex:2,child:SizedBox(height:58,child:OutlinedButton.icon(onPressed:_busy?null:()=>Navigator.pop(context),icon:const Icon(Icons.done_all),label:Text('FINALIZAR ($_captured)',maxLines:1,overflow:TextOverflow.ellipsis)))),
            const SizedBox(width:10),
            Expanded(flex:3,child:SizedBox(height:58,child:FilledButton.icon(onPressed:_busy?null:_capture,icon:Icon(_busy?Icons.hourglass_top:Icons.document_scanner),label:Text(_busy?'Lendo...':'CAPTURAR PRÓXIMO'))))
          ])
        ])))
      ])
    );
  }
}

class _SessionChip extends StatelessWidget{
 final IconData icon;final String label;
 const _SessionChip({required this.icon,required this.label});
 @override Widget build(BuildContext context)=>Container(padding:const EdgeInsets.symmetric(horizontal:9,vertical:6),decoration:BoxDecoration(border:Border.all(color:Theme.of(context).colorScheme.outlineVariant),borderRadius:BorderRadius.circular(20)),child:Row(mainAxisSize:MainAxisSize.min,children:[Icon(icon,size:16),const SizedBox(width:4),Text(label,style:Theme.of(context).textTheme.labelMedium)]));
}

class _ScanFramePainter extends CustomPainter{
 @override void paint(Canvas canvas,Size size){final w=size.width*.88;final h=(size.height*.40).clamp(210.0,330.0);final r=Rect.fromCenter(center:Offset(size.width/2,size.height*.55),width:w,height:h);final shade=Paint()..color=Colors.black.withValues(alpha:.38);final path=Path()..addRect(Offset.zero&size)..addRRect(RRect.fromRectAndRadius(r,const Radius.circular(18)))..fillType=PathFillType.evenOdd;canvas.drawPath(path,shade);final border=Paint()..color=Colors.white..style=PaintingStyle.stroke..strokeWidth=3;canvas.drawRRect(RRect.fromRectAndRadius(r,const Radius.circular(18)),border);}
 @override bool shouldRepaint(covariant CustomPainter oldDelegate)=>false;
}
extension _FirstOrNull<T> on Iterable<T>{T? get firstOrNull=>isEmpty?null:first;}
