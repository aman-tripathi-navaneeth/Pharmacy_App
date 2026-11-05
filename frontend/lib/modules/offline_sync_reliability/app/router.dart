import 'package:go_router/go_router.dart';

import '../features/home/home_screen.dart';
import '../features/integrations/integration_health_screen.dart';
import '../features/tickets/screens/create_ticket_screen.dart';
import '../features/tickets/screens/ticket_detail_screen.dart';
import '../features/tickets/screens/tickets_list_screen.dart';
import '../features/tour/tour_screen.dart';
import '../l10n/language_screen.dart';
import '../features/sync/domain/op_state.dart';
import '../features/sync/screens/conflict_resolution_screen.dart';
import '../features/sync/screens/operation_details_screen.dart';
import '../features/sync/screens/pending_operations_screen.dart';
import '../features/sync/screens/sync_status_screen.dart';

GoRouter buildRouter() => GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => const HomeScreen(),
          routes: [
            GoRoute(
              path: 'sync',
              builder: (_, _) => const SyncStatusScreen(),
              routes: [
                GoRoute(
                  path: 'pending',
                  builder: (_, s) => PendingOperationsScreen(
                    initialFilter: OpState.values.asNameMap()[s.uri.queryParameters['filter']],
                  ),
                ),
                GoRoute(
                  path: 'operations/:id',
                  builder: (_, s) => OperationDetailsScreen(operationId: s.pathParameters['id']!),
                ),
                GoRoute(
                  path: 'conflicts/:id',
                  builder: (_, s) => ConflictResolutionScreen(operationId: s.pathParameters['id']!),
                ),
              ],
            ),
            GoRoute(path: 'integrations', builder: (_, _) => const IntegrationHealthScreen()),
            GoRoute(path: 'language', builder: (_, _) => const LanguageScreen()),
            GoRoute(
              path: 'tour',
              builder: (_, s) => TourScreen(restart: s.uri.queryParameters['restart'] == '1'),
            ),
            GoRoute(
              path: 'support',
              builder: (_, _) => const TicketsListScreen(),
              routes: [
                GoRoute(
                  path: 'new',
                  builder: (_, s) => CreateTicketScreen(
                    relatedOperationId: s.uri.queryParameters['operationId'],
                    relatedModule: s.uri.queryParameters['module'],
                  ),
                ),
                GoRoute(
                  path: 'tickets/:id',
                  builder: (_, s) => TicketDetailScreen(ticketId: s.pathParameters['id']!),
                ),
              ],
            ),
          ],
        ),
      ],
    );
