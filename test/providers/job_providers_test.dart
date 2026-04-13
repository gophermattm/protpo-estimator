import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:protpo_app/providers/job_providers.dart';
import 'package:protpo_app/providers/estimator_providers.dart';
import 'package:protpo_app/models/estimate.dart';
import 'package:protpo_app/services/serialization.dart';

void main() {
  group('activeJobIdProvider', () {
    test('initial value is null', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(activeJobIdProvider), isNull);
    });

    test('can be set to a job ID', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(activeJobIdProvider.notifier).state = 'job-42';
      expect(container.read(activeJobIdProvider), 'job-42');
    });
  });

  group('activeEstimateIdProvider', () {
    test('initial value is null', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(activeEstimateIdProvider), isNull);
    });

    test('can be set to an estimate ID', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(activeEstimateIdProvider.notifier).state = 'est-99';
      expect(container.read(activeEstimateIdProvider), 'est-99');
    });
  });

  group('hasActiveEstimate', () {
    test('returns false when both IDs are null', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(hasActiveEstimateProvider), isFalse);
    });

    test('returns false when only jobId is set', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(activeJobIdProvider.notifier).state = 'job-1';
      expect(container.read(hasActiveEstimateProvider), isFalse);
    });

    test('returns true when both IDs are set', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(activeJobIdProvider.notifier).state = 'job-1';
      container.read(activeEstimateIdProvider.notifier).state = 'est-1';
      expect(container.read(hasActiveEstimateProvider), isTrue);
    });
  });

  group('loadEstimateIntoEditor', () {
    test('hydrates estimatorProvider from estimate.estimatorState', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      // Build a realistic estimatorState map using the existing serializer
      final state = container.read(estimatorProvider);
      final notifier = container.read(estimatorProvider.notifier);
      notifier.updateProjectInfo(state.projectInfo.copyWith(
        projectName: 'Warehouse Bid',
        customerName: 'Acme Properties',
      ));
      final serialized = stateToJson(container.read(estimatorProvider), 'est-test');

      // Reset the estimator to blank
      notifier.loadState(container.read(estimatorProvider).copyWith(
        projectInfo: container.read(estimatorProvider).projectInfo.copyWith(
          projectName: '', customerName: '',
        ),
      ));
      expect(container.read(estimatorProvider).projectInfo.projectName, '');

      // Create an Estimate carrying the serialized state
      final estimate = Estimate(
        id: 'est-test',
        name: 'TPO Bid',
        estimatorState: serialized,
      );

      // Load the estimate into the editor
      final result = loadEstimateIntoEditor(container, estimate, 'job-42');
      expect(result, isTrue);
      expect(container.read(activeJobIdProvider), 'job-42');
      expect(container.read(activeEstimateIdProvider), 'est-test');
      expect(
        container.read(estimatorProvider).projectInfo.projectName,
        'Warehouse Bid',
      );
    });

    test('returns false when estimatorState is empty/invalid', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final estimate = Estimate(
        id: 'est-bad',
        name: 'Bad Estimate',
        estimatorState: const {},
      );

      final result = loadEstimateIntoEditor(container, estimate, 'job-1');
      expect(result, isFalse);
      expect(container.read(activeJobIdProvider), isNull);
      expect(container.read(activeEstimateIdProvider), isNull);
    });
  });

  group('buildEstimateDraft', () {
    test('serializes current estimator state into an Estimate update', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      // Set up an active estimate context
      container.read(activeJobIdProvider.notifier).state = 'job-1';
      container.read(activeEstimateIdProvider.notifier).state = 'est-1';

      // Put some data in the estimator
      final notifier = container.read(estimatorProvider.notifier);
      notifier.updateProjectInfo(
        container.read(estimatorProvider).projectInfo.copyWith(
          projectName: 'Test Project',
        ),
      );

      final draft = buildEstimateDraft(container, 'est-1', 'TPO Bid');
      expect(draft, isNotNull);
      expect(draft!.id, 'est-1');
      expect(draft.name, 'TPO Bid');
      expect(draft.estimatorState['projectInfo'], isNotNull);
      expect(
        (draft.estimatorState['projectInfo'] as Map)['projectName'],
        'Test Project',
      );
      expect(draft.totalArea, isA<double>());
      expect(draft.buildingCount, greaterThan(0));
    });

    test('returns null when estimateId is empty', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final draft = buildEstimateDraft(container, '', 'Name');
      expect(draft, isNull);
    });
  });
}
