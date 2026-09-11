import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
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
  int _captured=0,_review=0;
  @override void initState(){super.initState();_init();}
  Future<void> _init() async {try{final cams=await availableCameras();if(cams.isEmpty)throw Exception('Nenhuma câmera encontrada');final back=cams.where((c)=>c.lensDirection==CameraLensDirection.back).firstOrNull??cams.first;final controller=CameraController(back,ResolutionPreset.high,enableAudio:false);await controller.initialize();if(!mounted){await controller.dispose();return;}setState(()=>_camera=controller);}catch(e){if(mounted)setState(()=>_message='Não foi possível abrir a câmera: $e');}}
  Future<void> _toggleTorch()async{final c=_camera;if(c==null)return;try{_torch=!_torch;await c.setFlashMode(_torch?FlashMode.torch:FlashMode.off);if(mounted)setState((){});}catch(_){if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Flash não disponível nesta câmera.')));}}
  Future<void> _capture() async {if(_busy||_camera?.value.isInitialized!=true)return;setState((){_busy=true;_message='Lendo endereço e identificador...';});try{final file=await _camera!.takePicture();final results=await Future.wait<dynamic>([_ocr.recognizeFile(file.path),_barcode.recognizeFile(file.path)]);final text=results[0] as String;final tracking=results[1] as String?;if(text.trim().isEmpty)throw Exception('Nenhum endereço encontrado');final before=widget.state.packages.length;await widget.state.addFromText(text,trackingCode:tracking);if(widget.state.packages.length<=before)throw Exception('Este pacote parece já ter sido registrado');final p=widget.state.packages.last;_captured++;if(p.address.validation!=ValidationStatus.confirmed)_review++;if((await Vibration.hasVibrator())==true)Vibration.vibrate(duration:p.address.validation==ValidationStatus.confirmed?70:160);final linked=tracking!=null?' • código vinculado':'';if(mounted)setState(()=>_message=p.address.validation==ValidationStatus.confirmed?'✓ ${p.label} pronto$linked — próximo':'⚠ ${p.label} salvo para revisar$linked — próximo');}catch(e){if(mounted)setState(()=>_message='Não registrei: $e');}finally{if(mounted)setState(()=>_busy=false);}}
  @override void dispose(){_camera?.dispose();_ocr.dispose();_barcode.dispose();super.dispose();}
  @override Widget build(BuildContext context){final c=_camera;return Scaffold(backgroundColor:Colors.black,appBar:AppBar(title:Text('Scanner • $_captured lidos'),actions:[if(_review>0)Center(child:Padding(padding:const EdgeInsets.only(right:8),child:Text('⚠ $_review'))),IconButton(onPressed:c==null?null:_toggleTorch,tooltip:_torch?'Desligar lanterna':'Ligar lanterna',icon:Icon(_torch?Icons.flash_on:Icons.flash_off))]),body:Column(children:[Expanded(child:c==null?const Center(child:CircularProgressIndicator()):Stack(fit:StackFit.expand,children:[CameraPreview(c),IgnorePointer(child:CustomPaint(painter:_ScanFramePainter())),Positioned(left:24,right:24,top:18,child:Container(padding:const EdgeInsets.symmetric(horizontal:14,vertical:10),decoration:BoxDecoration(color:Colors.black.withValues(alpha:.68),borderRadius:BorderRadius.circular(12)),child:const Text('Priorize DESTINATÁRIO / endereço de entrega.\nSe o código de barras ou QR couber na foto, o app também vincula o pacote.',textAlign:TextAlign.center,style:TextStyle(color:Colors.white,fontWeight:FontWeight.w600))))])),Container(color:Theme.of(context).colorScheme.surface,padding:const EdgeInsets.fromLTRB(16,12,16,20),child:SafeArea(top:false,child:Column(children:[Text(_message,textAlign:TextAlign.center,maxLines:2,overflow:TextOverflow.ellipsis),const SizedBox(height:10),Row(children:[Expanded(flex:2,child:SizedBox(height:54,child:OutlinedButton.icon(onPressed:()=>Navigator.pop(context),icon:const Icon(Icons.done_all),label:Text('FINALIZAR ($_captured)',maxLines:1,overflow:TextOverflow.ellipsis)))),const SizedBox(width:10),Expanded(flex:3,child:SizedBox(height:54,child:FilledButton.icon(onPressed:_busy?null:_capture,icon:Icon(_busy?Icons.hourglass_top:Icons.document_scanner),label:Text(_busy?'Lendo...':'CAPTURAR PRÓXIMO'))))])])))]));}
}

class _ScanFramePainter extends CustomPainter{
 @override void paint(Canvas canvas,Size size){final w=size.width*.88;final h=(size.height*.40).clamp(210.0,330.0);final r=Rect.fromCenter(center:Offset(size.width/2,size.height*.55),width:w,height:h);final shade=Paint()..color=Colors.black.withValues(alpha:.38);final path=Path()..addRect(Offset.zero&size)..addRRect(RRect.fromRectAndRadius(r,const Radius.circular(18)))..fillType=PathFillType.evenOdd;canvas.drawPath(path,shade);final border=Paint()..color=Colors.white..style=PaintingStyle.stroke..strokeWidth=3;canvas.drawRRect(RRect.fromRectAndRadius(r,const Radius.circular(18)),border);}
 @override bool shouldRepaint(covariant CustomPainter oldDelegate)=>false;
}
extension _FirstOrNull<T> on Iterable<T>{T? get firstOrNull=>isEmpty?null:first;}
