import 'package:app_rotas_entregas/app_state.dart';
import 'package:app_rotas_entregas/domain/models.dart';
import 'package:app_rotas_entregas/services/package_store.dart';
import 'package:app_rotas_entregas/services/package_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class BulkStore implements PackageStore {
  BulkStore(this.packages,{this.optimized=false});
  List<DeliveryPackage> packages;
  bool optimized;
  int saves=0;
  @override Future<List<DeliveryPackage>> load() async=>[...packages];
  @override Future<bool> loadRouteOptimized() async=>optimized;
  @override Future<void> save(List<DeliveryPackage> value,{bool? routeOptimized}) async {packages=[...value];if(routeOptimized!=null)optimized=routeOptimized;saves++;}
  @override Future<void> clear() async {packages=[];optimized=false;}
}

DeliveryPackage _existing(String id,int scan,{DeliveryStatus status=DeliveryStatus.pending,String? zone})=>DeliveryPackage(
  id:id,scanNumber:scan,status:status,physicalZone:zone,
  address:AddressData(raw:'Rua Antiga, $scan',street:'Rua Antiga',number:'$scan',city:'São Paulo',state:'SP',confidence:.5,validation:ValidationStatus.needsReview),
  scannedAt:DateTime.utc(2026,9,13,19,scan),
);

void main(){
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('bulk import ignores blank lines and imports each valid address once',() async {
    final store=BulkStore([]);final state=AppState(store:store);await state.init();
    final count=await state.addManyFromText('Rua Alfa, 10\n\n  Rua Beta, 20  \n\nRua Gama, 30');
    expect(count,3);expect(state.packages,hasLength(3));expect(state.packages.map((p)=>p.address.raw).toSet(),{'Rua Alfa, 10','Rua Beta, 20','Rua Gama, 30'});expect(state.routeOptimized,isFalse);expect(store.saves,1);
  });

  test('bulk import invalidates optimized route while preserving existing active load positions',() async {
    final store=BulkStore([_existing('old',1,zone:'A-01')],optimized:true);final state=AppState(store:store);await state.init();
    final count=await state.addManyFromText('Rua Nova, 200\nRua Nova Dois, 300');
    expect(count,2);expect(state.packages,hasLength(3));expect(state.routeOptimized,isFalse);expect(state.packages.first.physicalZone,'A-01');expect(state.packages.skip(1).every((p)=>p.physicalZone==null),isTrue);expect(store.optimized,isFalse);
  });

  test('bulk import preserves both delivered history and existing active load positions',() async {
    final store=BulkStore([_existing('done',1,status:DeliveryStatus.delivered,zone:'HIST'),_existing('active',2,zone:'A-02')],optimized:true);final state=AppState(store:store);await state.init();
    final count=await state.addManyFromText('Rua Nova, 400');
    expect(count,1);expect(state.packages.firstWhere((p)=>p.id=='done').physicalZone,'HIST');expect(state.packages.firstWhere((p)=>p.id=='done').status,DeliveryStatus.delivered);expect(state.packages.firstWhere((p)=>p.id=='active').physicalZone,'A-02');expect(state.packages.last.physicalZone,isNull);expect(state.routeOptimized,isFalse);
  });

  test('parallel scanner imports return the exact package created by each capture',() async {
    final store=BulkStore([]);
    final state=AppState(store:store);
    await state.init();

    final captured=await Future.wait([
      state.addFromText('etiqueta sem endereco alpha',trackingCode:'SCAN-001'),
      state.addFromText('etiqueta sem endereco beta',trackingCode:'SCAN-002'),
    ]);

    expect(captured.map((p)=>p.trackingCode).toList(),['SCAN-001','SCAN-002']);
    expect(captured.map((p)=>p.scanNumber).toSet(),{1,2});
    expect(captured.map((p)=>p.id).toSet(),hasLength(2));
    expect(
      state.packages.map((p)=>p.id).toSet(),
      containsAll(captured.map((p)=>p.id)),
    );
    expect(state.packages,hasLength(2));
  });

  test('empty bulk import is a true no-op and preserves optimized route and load labels',() async {
    final store=BulkStore([_existing('old',1,zone:'A-01')],optimized:true);final state=AppState(store:store);await state.init();
    final count=await state.addManyFromText('  \n\n   ');
    expect(count,0);expect(state.packages,hasLength(1));expect(state.packages.single.id,'old');expect(state.packages.single.physicalZone,'A-01');expect(state.routeOptimized,isTrue);expect(store.optimized,isTrue);expect(store.saves,0);
  });

  test('parallel scanner captures with the same normalized tracking code save only once', () async {
    final store = BulkStore([]);
    final state = AppState(store: store);
    await state.init();

    Future<Object> capture(Future<DeliveryPackage> operation) async {
      try {
        return await operation;
      } catch (error) {
        return error;
      }
    }

    final results = await Future.wait<Object>([
      capture(
        state.addFromText(
          'etiqueta sem endereco alpha',
          trackingCode: 'AB-123',
        ),
      ),
      capture(
        state.addFromText(
          'etiqueta sem endereco beta',
          trackingCode: 'ab 123',
        ),
      ),
    ]);

    expect(results.whereType<DeliveryPackage>(), hasLength(1));
    expect(results.whereType<DuplicatePackageException>(), hasLength(1));
    expect(state.packages, hasLength(1));
    expect(store.saves, 1);
  });


  test('scanner keeps all 600 organized packages in place for car and motorcycle', () async {
    for (final vehicle in [VehicleType.car, VehicleType.motorcycle]) {
      final targetZone = vehicle == VehicleType.car
          ? 'Porta-malas'
          : 'Baú traseiro';
      SharedPreferences.setMockInitialValues({
        'load_vehicle_type': vehicle.name,
      });

      final store = BulkStore(
        List.generate(
          600,
          (index) => _existing(
            'organized-${vehicle.name}-$index',
            index + 1,
            zone: targetZone,
          ),
        ),
        optimized: true,
      );
      final state = AppState(store: store);
      await state.init();

      expect(state.packages, hasLength(600));
      expect(state.routeOptimized, isTrue);
      expect(
        state.packages.every((package) => package.physicalZone == targetZone),
        isTrue,
      );

      final scanned = await state.addFromText(
        'etiqueta sem endereco nova',
        trackingCode: 'SCAN-${vehicle.name.toUpperCase()}',
      );

      expect(state.packages, hasLength(601));
      expect(state.routeOptimized, isFalse);
      expect(
        state.packages
            .where((package) => package.id.startsWith('organized-'))
            .every((package) => package.physicalZone == targetZone),
        isTrue,
        reason: 'Scanning a new package must not erase the existing $vehicle load.',
      );
      expect(
        state.packages.singleWhere((package) => package.id == scanned.id).physicalZone,
        isNull,
      );
      expect(
        store.packages
            .where((package) => package.id.startsWith('organized-'))
            .every((package) => package.physicalZone == targetZone),
        isTrue,
      );
      expect(store.packages, hasLength(601));
      expect(store.saves, 1);
    }
  });


  test('scanner keeps scan numbers unique after removing a package from an organized load',() async {
    final store=BulkStore([
      _existing('first',1,zone:'Porta-malas'),
      _existing('middle',2,zone:'Porta-malas'),
      _existing('last',3,zone:'Porta-malas'),
    ],optimized:true);
    final state=AppState(store:store);
    await state.init();

    await state.removePackage('middle');
    expect(state.packages,hasLength(2));
    expect(state.packages.map((p)=>p.scanNumber).toSet(),{1,3});
    expect(state.packages.every((p)=>p.physicalZone=='Porta-malas'),isTrue);

    final scanned=await state.addFromText(
      'etiqueta sem endereco depois da remocao',
      trackingCode:'SCAN-AFTER-DELETE',
    );
    expect(scanned.scanNumber,4);
    expect(scanned.physicalZone,isNull);

    final bulkCount=await state.addManyFromText(
      'Rua Nova, 500\\nRua Nova, 600',
    );
    expect(bulkCount,2);
    expect(state.packages,hasLength(5));
    expect(
      state.packages.map((p)=>p.scanNumber).toSet(),
      {1,3,4,5,6},
    );
    expect(
      state.packages.map((p)=>p.scanNumber).toSet(),
      hasLength(state.packages.length),
      reason:'Removing an earlier package must not cause a later scan number to be reused.',
    );
    expect(state.packages.firstWhere((p)=>p.id=='first').physicalZone,'Porta-malas');
    expect(state.packages.firstWhere((p)=>p.id=='last').physicalZone,'Porta-malas');
    expect(state.packages.firstWhere((p)=>p.id==scanned.id).physicalZone,isNull);
    expect(state.routeOptimized,isFalse);
    expect(store.packages,hasLength(5));
    expect(store.saves,3);
  });

}
