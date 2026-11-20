import 'package:app_rotas_entregas/app_state.dart';
import 'package:app_rotas_entregas/domain/models.dart';
import 'package:app_rotas_entregas/services/migrating_package_store.dart';
import 'package:app_rotas_entregas/services/package_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeStore implements PackageStore {
  List<DeliveryPackage> packages;
  bool optimized;
  bool failNextSave;
  bool corruptNextSave;
  bool failClearBeforeMutation;
  bool failClearAfterMutation;
  int saves=0;
  int clears=0;

  FakeStore({
    List<DeliveryPackage>? packages,
    this.optimized=false,
    this.failNextSave=false,
    this.corruptNextSave=false,
    this.failClearBeforeMutation=false,
    this.failClearAfterMutation=false,
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
    clears++;
    if(failClearBeforeMutation){
      failClearBeforeMutation=false;
      throw StateError('simulated clear failure before mutation');
    }
    packages=[];
    optimized=false;
    if(failClearAfterMutation){
      failClearAfterMutation=false;
      throw StateError('simulated clear failure after mutation');
    }
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
  TestWidgetsFlutterBinding.ensureInitialized();

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

  test('failed legacy clear before mutation restores primary and does not resurrect stale legacy data',() async {
    final primary=FakeStore(packages:[pkg('current',1)],optimized:true);
    final legacy=FakeStore(
      packages:[pkg('legacy',2)],
      optimized:true,
      failClearBeforeMutation:true,
    );
    final store=MigratingPackageStore(primary:primary,legacy:legacy);

    await expectLater(store.clear(),throwsStateError);

    expect(primary.packages.map((p)=>p.id),['current']);
    expect(primary.optimized,isTrue);
    expect(legacy.packages.map((p)=>p.id),['legacy']);
    expect(legacy.optimized,isTrue);

    // The failed clear must not leave an empty primary that causes stale
    // legacy data to be imported on the next app startup.
    expect((await store.load()).map((p)=>p.id),['current']);
    expect(await store.loadRouteOptimized(),isTrue);
  });

  test('AppState clear restores the visible route when legacy clear fails',() async {
    SharedPreferences.setMockInitialValues({});
    final primary=FakeStore(packages:[pkg('current',1)],optimized:true);
    final legacy=FakeStore(
      packages:[pkg('legacy',2)],
      optimized:true,
      failClearAfterMutation:true,
    );
    final store=MigratingPackageStore(primary:primary,legacy:legacy);
    final state=AppState(store:store);
    await state.init();

    await expectLater(state.clear(),throwsStateError);

    expect(state.packages.map((p)=>p.id),['current']);
    expect(state.routeOptimized,isTrue);
    expect(primary.packages.map((p)=>p.id),['current']);
    expect(legacy.packages.map((p)=>p.id),['legacy']);

    final reopened=AppState(store:store);
    await reopened.init();
    expect(reopened.packages.map((p)=>p.id),['current']);
    expect(reopened.routeOptimized,isTrue);
  });

  test('failed legacy clear after partial mutation restores both package snapshots',() async {
    final primary=FakeStore(packages:[pkg('current',1)],optimized:true);
    final legacy=FakeStore(
      packages:[pkg('legacy',2)],
      optimized:true,
      failClearAfterMutation:true,
    );
    final store=MigratingPackageStore(primary:primary,legacy:legacy);

    await expectLater(store.clear(),throwsStateError);

    expect(primary.packages.map((p)=>p.id),['current']);
    expect(primary.optimized,isTrue);
    expect(legacy.packages.map((p)=>p.id),['legacy']);
    expect(legacy.optimized,isTrue);
  });
}
