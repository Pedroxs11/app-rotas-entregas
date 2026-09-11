import 'package:flutter/material.dart';
import '../domain/models.dart';

class LoadScreen extends StatelessWidget{
  final List<DeliveryPackage> packages;
  const LoadScreen({super.key,required this.packages});

  bool _active(DeliveryPackage p)=>p.status==DeliveryStatus.pending||p.status==DeliveryStatus.current||p.status==DeliveryStatus.absent||p.status==DeliveryStatus.addressProblem;

  @override Widget build(BuildContext context){
    final route=packages.where(_active).toList();
    final loading=route.reversed.toList();
    return Scaffold(
      appBar:AppBar(title:const Text('Carregar veículo')),
      body:loading.isEmpty?const Center(child:Text('Nenhum pacote ativo para carregar.')):Column(children:[
        Padding(padding:const EdgeInsets.all(16),child:Card(child:Padding(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text('${loading.length} pacotes',style:Theme.of(context).textTheme.titleLarge),
          const SizedBox(height:6),
          const Text('Carregue nesta ordem: as últimas entregas entram primeiro. Assim, as primeiras paradas ficam mais acessíveis na hora de entregar.'),
        ]))),
        Expanded(child:ListView.separated(padding:const EdgeInsets.fromLTRB(12,0,12,20),itemCount:loading.length,separatorBuilder:(_,__)=>const Divider(height:1),itemBuilder:(context,i){
          final p=loading[i];
          final routePosition=route.indexWhere((x)=>x.id==p.id)+1;
          final firstDelivery=routePosition==1;
          return ListTile(
            leading:CircleAvatar(child:Text('${i+1}')),
            title:Text(p.label,style:const TextStyle(fontWeight:FontWeight.w600)),
            subtitle:Text('${p.physicalZone?.trim().isNotEmpty==true?'Local ${p.physicalZone} • ':''}Entrega #$routePosition\n${p.address.formatted.isEmpty?p.address.raw:p.address.formatted}',maxLines:3,overflow:TextOverflow.ellipsis),
            trailing:firstDelivery?const Chip(label:Text('POR ÚLTIMO')):null,
          );
        }))
      ]),
    );
  }
}
