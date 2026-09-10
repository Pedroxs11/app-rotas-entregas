import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:vibration/vibration.dart';
import '../app_state.dart';
import '../services/ocr_service.dart';

class ScannerScreen extends StatefulWidget {
  final AppState state;
  const ScannerScreen({super.key, required this.state});
  @override State<ScannerScreen> createState()=>_ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen>{
  CameraController? _camera;
  final _ocr=OcrService();
  bool _busy=false;
  String _message='Centralize a etiqueta e toque em Capturar';
  int _captured=0;

  @override void initState(){super.initState();_init();}
  Future<void> _init() async {
    try{
      final cams=await availableCameras();
      if(cams.isEmpty) throw Exception('Nenhuma câmera encontrada');
      final back=cams.where((c)=>c.lensDirection==CameraLensDirection.back).firstOrNull ?? cams.first;
      final controller=CameraController(back,ResolutionPreset.high,enableAudio:false);
      await controller.initialize();
      if(!mounted){await controller.dispose();return;}
      setState(()=>_camera=controller);
    }catch(e){if(mounted)setState(()=>_message='Não foi possível abrir a câmera: $e');}
  }

  Future<void> _capture() async {
    if(_busy || _camera?.value.isInitialized!=true)return;
    setState((){_busy=true;_message='Lendo etiqueta...';});
    try{
      final file=await _camera!.takePicture();
      final text=await _ocr.recognizeFile(file.path);
      if(text.trim().isEmpty) throw Exception('Nenhum texto encontrado');
      await widget.state.addFromText(text);
      _captured++;
      if((await Vibration.hasVibrator())==true) Vibration.vibrate(duration:80);
      if(mounted)setState(()=>_message='✓ Pacote ${widget.state.packages.last.scanNumber.toString().padLeft(2,'0')} registrado. Próximo!');
    }catch(e){if(mounted)setState(()=>_message='Confira a etiqueta: $e');}
    finally{if(mounted)setState(()=>_busy=false);}
  }

  @override void dispose(){_camera?.dispose();_ocr.dispose();super.dispose();}
  @override Widget build(BuildContext context){
    final c=_camera;
    return Scaffold(appBar:AppBar(title:Text('Scanner • $_captured nesta sessão')),body:Column(children:[
      Expanded(child:c==null?const Center(child:CircularProgressIndicator()):Stack(fit:StackFit.expand,children:[CameraPreview(c),Center(child:Container(width:330,height:210,decoration:BoxDecoration(border:Border.all(color:Colors.white,width:3),borderRadius:BorderRadius.circular(16))))])),
      Padding(padding:const EdgeInsets.fromLTRB(16,12,16,24),child:Column(children:[Text(_message,textAlign:TextAlign.center),const SizedBox(height:12),SizedBox(width:double.infinity,height:54,child:FilledButton.icon(onPressed:_busy?null:_capture,icon:Icon(_busy?Icons.hourglass_top:Icons.document_scanner),label:Text(_busy?'Lendo...':'Capturar etiqueta')))]))
    ]));
  }
}

extension _FirstOrNull<T> on Iterable<T>{T? get firstOrNull=>isEmpty?null:first;}
