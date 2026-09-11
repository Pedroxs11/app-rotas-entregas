import 'package:app_rotas_entregas/domain/models.dart';
import 'package:app_rotas_entregas/services/migrating_package_store.dart';
import 'package:app_rotas_entregas/services/package_store.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeStore implements PackageStore {
  List<DeliveryPackage> packages;
  bool optimized;
  bool failNextSave;
  bool corruptNextSave;
  int saves=0;
  int clears=0;

  FakeStore({
    List<DeliveryPackage>? packages,
    this.optimized=false,
    this.failNextSave=false,
    this.corruptNextSave=false,
  }):packages=[...?packages];

  @override
  Future<List<DeliveryPackage>> load() async=>[...packages];

  @override
  Future<bool> loadRouteOptimized() async=>optimized;

  @override
  Future<void> save(List<DeliveryPackage> value,{bool? routeOptimized}) async {
    saves++;
    if(failNextSave){
      failNextSave=false;
      throw StateError('simulated write failure');
    }
    packages=corruptNextSave&&value.isNotEmpty?[value.last]:[...value];
    corruptNextSave=false;
    if(routeOptimized!=null)optimized=routeOptimized;
  }

  @override
  Future<void> clear() async {
    packages=[];
    optimized=false;
    clears++;
  }
}

DeliveryPackage pkg(String id,int scan)=>DeliveryPackage(
  id:id,
  scanNumber:scan,
  address:AddressData(
    raw:'Rua $scan',
    street:'Rua',
    number:'$scan',
    city:'São Paulo',
    state:'SP',
    confidence:1,
    validation:ValidationStatus.confirmed,
  ),
  scannedAt:DateTime.utc(2026,9,12,10,scan),
);

void main(){
  test('copies legacy packages in exact order with route metadata',() async {
    final primary=FakeStore();
    final legacy=FakeStore(packages:[pkg('a',1),pkg('b',2),pkg('c',3)],optimized:true);
    final store=MigratingPackageStore(primary:primary,legacy:legacy);

    final loaded=await store.load();

    expect(loaded.map((p)=>p.id),['a','b','c']);
    expect(await store.loadRouteOptimized(),isTrue);
    expect(primary.saves,1);
    expect(legacy.packages,hasLength(3));
  });

  test('existing primary data wins over stale legacy data',() async {
    final primary=FakeStore(packages:[pkg('new',1)],optimized:false);
    final legacy=FakeStore(packages:[pkg('old',2)],optimized:true);
    final store=MigratingPackageStore(primary:primary,legacy:legacy);

    expect((await store.load()).single.id,'new');
    expect(primary.saves,0);
  });

  test('migrates route metadata even when legacy package list is empty',() async {
    final primary=FakeStore();
    final legacy=FakeStore(optimized:true);
    final store=MigratingPackageStore(primary:primary,legacy:legacy);

    expect(await store.load(),isEmpty);
    expect(await store.loadRouteOptimized(),isTrue);
    expect(primary.saves,1);
  });

  test('failed primary write keeps legacy intact and migration can retry',() async {
    final primary=FakeStore(failNextSave:true);
    final legacy=FakeStore(packages:[pkg('safe',1)],optimized:true);
    final store=MigratingPackageStore(primary:primary,legacy:legacy);

    await expectLater(store.load(),throwsStateError);
    expect(legacy.packages.single.id,'safe');

    expect((await store.load()).single.id,'safe');
    expect(primary.saves,2);
  });

  test('verification rejects corrupted primary migration',() async {
    final primary=FakeStore(corruptNextSave:true);
    final legacy=FakeStore(packages:[pkg('a',1),pkg('b',2)],optimized:true);
    final store=MigratingPackageStore(primary:primary,legacy:legacy);

    await expectLater(store.load(),throwsStateError);
    expect(legacy.packages.map((p)=>p.id),['a','b']);
  });

  test('clear removes both stores and prevents legacy resurrection',() async {
    final primary=FakeStore(packages:[pkg('new',1)],optimized:true);
    final legacy=FakeStore(packages:[pkg('old',2)],optimized:true);
    final store=MigratingPackageStore(primary:primary,legacy:legacy);

    await store.clear();

    expect(primary.clears,1);
    expect(legacy.clears,1);
    expect(await store.load(),isEmpty);
    expect(await store.loadRouteOptimized(),isFalse);
  });
}
