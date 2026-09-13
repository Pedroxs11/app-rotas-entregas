import 'package:app_rotas_entregas/app_state.dart';
import 'package:app_rotas_entregas/domain/models.dart';
import 'package:app_rotas_entregas/services/package_store.dart';
import 'package:flutter_test/flutter_test.dart';

class MetadataFailureStore implements PackageStore {
  MetadataFailureStore(this.packages);

  List<DeliveryPackage> packages;
  int saves = 0;

  @override
  Future<List<DeliveryPackage>> load() async => [...packages];

  @override
  Future<bool> loadRouteOptimized() async =>
      throw StateError('route metadata unavailable');

  @override
  Future<void> save(List<DeliveryPackage> value,{bool? routeOptimized}) async {
    packages = [...value];
    saves++;
  }

  @override
  Future<void> clear() async => packages = [];
}

DeliveryPackage _package()=>DeliveryPackage(
  id:'kept',
  scanNumber:1,
  trackingCode:'BRTESTE1',
  physicalZone:'A-01',
  address:const AddressData(
    raw:'Rua Teste, 100',
    street:'Rua Teste',
    number:'100',
    city:'São Paulo',
    state:'SP',
    latitude:-23.55,
    longitude:-46.63,
    confidence:1,
    validation:ValidationStatus.confirmed,
  ),
  scannedAt:DateTime.utc(2026,9,13,14),
);

void main(){
  test('route metadata startup failure keeps already loaded packages usable',() async {
    final store=MetadataFailureStore([_package()]);
    final state=AppState(store:store);

    await state.init();

    expect(state.loading,isFalse);
    expect(state.packages,hasLength(1));
    expect(state.packages.single.id,'kept');
    expect(state.packages.single.trackingCode,'BRTESTE1');
    expect(state.packages.single.physicalZone,'A-01');
    expect(state.routeOptimized,isFalse);
    expect(state.startupError,contains('route metadata unavailable'));
    expect(store.saves,0);
  });
}
