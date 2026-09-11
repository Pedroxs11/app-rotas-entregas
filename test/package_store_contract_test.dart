import 'package:app_rotas_entregas/app_state.dart';
import 'package:app_rotas_entregas/domain/models.dart';
import 'package:app_rotas_entregas/services/package_store.dart';
import 'package:flutter_test/flutter_test.dart';

class MemoryPackageStore implements PackageStore {
  List<DeliveryPackage> packages;
  bool optimized;
  int saves=0;
  int clears=0;

  MemoryPackageStore({List<DeliveryPackage>? packages,this.optimized=false})
      : packages=[...?packages];

  @override
  Future<List<DeliveryPackage>> load() async=>[...packages];

  @override
  Future<bool> loadRouteOptimized() async=>optimized;

  @override
  Future<void> save(List<DeliveryPackage> value,{bool? routeOptimized}) async {
    packages=[...value];
    if(routeOptimized!=null)optimized=routeOptimized;
    saves++;
  }

  @override
  Future<void> clear() async {
    packages=[];
    optimized=false;
    clears++;
  }
}

void main(){
  test('AppState restores data through PackageStore contract',() async {
    final store=MemoryPackageStore(optimized:true);
    final state=AppState(store:store);

    await state.init();

    expect(state.loading,isFalse);
    expect(state.routeOptimized,isTrue);
    expect(state.packages,isEmpty);
  });

  test('clear uses injected store instead of concrete local storage',() async {
    final store=MemoryPackageStore(optimized:true);
    final state=AppState(store:store);
    await state.init();

    await state.clear();

    expect(store.clears,1);
    expect(store.optimized,isFalse);
    expect(state.routeOptimized,isFalse);
    expect(state.packages,isEmpty);
  });
}
