/// GoRouter catalog. Import feature barrels only — never reach into
/// `presentation/screens/` from this file.
///
/// Route groups:
/// - `/splash` `/onboarding` `/login` `/signup` `/forgot-password` — unauthenticated
/// - shell tabs: `/today` `/nutrition` `/move` `/ai` `/more`
/// - hubs: `/wellness` `/kitchen` `/gym` …
/// - modules under More, plus `/admin/*` for staff
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/admin/admin.dart';
import '../features/ai/ai.dart';
import '../features/archive/archive.dart';
import '../features/auth/auth.dart';
import '../features/groceries/groceries.dart';
import '../features/gym/gym.dart';
import '../features/habits/habits.dart';
import '../features/hydration/hydration.dart';
import '../features/journal/journal.dart';
import '../features/kitchen/kitchen.dart';
import '../features/mindfulness/mindfulness.dart';
import '../features/movement/movement.dart';
import '../features/notifications/notifications.dart';
import '../features/nutrition/nutrition.dart';
import '../features/onboarding/onboarding.dart';
import '../features/pantry/pantry.dart';
import '../features/profile/profile.dart';
import '../features/reports/reports.dart';
import '../features/search/search.dart';
import '../features/sleep/sleep.dart';
import '../features/spending/spending.dart';
import '../features/support/support.dart';
import '../features/today/today.dart';
import '../features/training/training.dart';
import '../features/wellness/wellness.dart';
import '../shared/providers/auth_provider.dart';
import 'page_transitions.dart';
import 'shell/app_shell.dart';
import 'shell/more_menu_screen.dart';

final _rootKey = GlobalKey<NavigatorState>();

bool _isStaffRole(String? role) => role == 'admin' || role == 'super_admin';
bool _isSuperAdminRole(String? role) => role == 'super_admin';

final routerProvider = Provider<GoRouter>((ref) {
  // Do not watch authProvider here — recreating GoRouter on every auth change
  // resets navigation. refreshListenable + ref.read keeps the same router.
  final refresh = _AuthListenable(ref);

  return GoRouter(
    navigatorKey: _rootKey,
    initialLocation: '/splash',
    refreshListenable: refresh,
    redirect: (context, state) {
      final auth = ref.read(authProvider);
      final loc = state.matchedLocation;
      final status = auth.status;

      if (status == AuthStatus.unknown) {
        return loc == '/splash' ? null : '/splash';
      }

      final onAuthFlow =
          loc.startsWith('/login') ||
          loc.startsWith('/signup') ||
          loc.startsWith('/forgot-password');

      if (status == AuthStatus.unauthenticated) {
        if (auth.error == 'needs_onboarding') {
          return loc == '/onboarding' ? null : '/onboarding';
        }
        // Splash / finished onboarding must leave the loading screen.
        if (loc == '/splash' || loc == '/onboarding') {
          return '/login';
        }
        if (!onAuthFlow) return '/login';
        return null;
      }

      if (status == AuthStatus.authenticated &&
          (onAuthFlow || loc == '/splash' || loc == '/onboarding')) {
        return '/today';
      }

      if (status == AuthStatus.authenticated && loc.startsWith('/admin')) {
        final role = auth.profile?.role;
        if (!_isStaffRole(role)) return '/more';
        final needsSuper =
            loc.startsWith('/admin/activity') ||
            loc.startsWith('/admin/inquiries');
        if (needsSuper && !_isSuperAdminRole(role)) return '/admin';
      }

      // Legacy aliases after Training / Wellness / Kitchen merge.
      if (loc == '/movement') return '/move/activity';
      if (loc == '/training') return '/move';

      return null;
    },
    routes: [
      vivrantGoRoute(
        path: '/splash',
        transition: VivrantTransition.fadeThrough,
        builder: (_, __) => const SplashScreen(),
      ),
      vivrantGoRoute(
        path: '/onboarding',
        transition: VivrantTransition.fadeThrough,
        builder: (_, __) => const OnboardingScreen(),
      ),
      vivrantGoRoute(
        path: '/login',
        transition: VivrantTransition.fadeThrough,
        builder: (_, __) => const LoginScreen(),
      ),
      vivrantGoRoute(
        path: '/signup',
        builder: (_, __) => const SignupScreen(),
      ),
      vivrantGoRoute(
        path: '/forgot-password',
        builder: (_, __) => const ForgotPasswordScreen(),
      ),
      StatefulShellRoute(
        builder: (context, state, navigationShell) {
          return AppShell(navigationShell: navigationShell);
        },
        navigatorContainerBuilder: (context, navigationShell, children) {
          return ShellSwipeContainer(
            navigationShell: navigationShell,
            children: children,
          );
        },
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/today', builder: (_, __) => const TodayScreen()),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/nutrition',
                builder: (_, __) => const NutritionScreen(),
                routes: [
                  vivrantGoRoute(
                    path: 'log',
                    builder: (_, __) => const LogMealScreen(),
                  ),
                  vivrantGoRoute(
                    path: 'history',
                    builder: (_, __) => const MealsHistoryScreen(),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/move',
                builder: (_, __) => const TrainingHubScreen(),
                routes: [
                  vivrantGoRoute(
                    path: 'activity',
                    builder: (_, __) => const MovementScreen(),
                  ),
                  vivrantGoRoute(
                    path: 'log',
                    builder: (_, state) => LogWorkoutScreen(
                      initialDayLabel: state.uri.queryParameters['day'],
                      initialPlanId: int.tryParse(state.uri.queryParameters['plan'] ?? ''),
                    ),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/ai', builder: (_, __) => const AiChatScreen()),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/more',
                builder: (_, __) => const MoreMenuScreen(),
              ),
            ],
          ),
        ],
      ),
      vivrantGoRoute(path: '/wellness', builder: (_, __) => const WellnessHubScreen()),
      vivrantGoRoute(path: '/kitchen', builder: (_, __) => const KitchenHubScreen()),
      vivrantGoRoute(path: '/gym', builder: (_, __) => const GymOverviewScreen()),
      vivrantGoRoute(path: '/gym/demos', builder: (_, __) => const GymDemosScreen()),
      vivrantGoRoute(
        path: '/gym/machines',
        builder: (_, __) => const GymMachinesScreen(),
      ),
      vivrantGoRoute(
        path: '/gym/sessions',
        builder: (context, state) {
          final plan = int.tryParse(state.uri.queryParameters['plan'] ?? '');
          final day = state.uri.queryParameters['day'];
          return GymSessionsScreen(initialPlanId: plan, initialDayLabel: day);
        },
      ),
      vivrantGoRoute(path: '/gym/plans', builder: (_, __) => const GymPlansHubScreen()),
      vivrantGoRoute(
        path: '/gym/plans/build',
        builder: (_, __) => const GymPlansScreen(),
      ),
      vivrantGoRoute(
        path: '/gym/plans/saved',
        builder: (_, __) => const GymPlansScreen(view: GymPlansView.saved),
      ),
      vivrantGoRoute(path: '/sleep', builder: (_, __) => const SleepScreen()),
      vivrantGoRoute(path: '/hydration', builder: (_, __) => const HydrationScreen()),
      vivrantGoRoute(
        path: '/mindfulness',
        builder: (_, __) => const MindfulnessScreen(),
      ),
      vivrantGoRoute(path: '/journal', builder: (_, __) => const JournalScreen()),
      vivrantGoRoute(
        path: '/journal/new',
        builder: (_, __) => const JournalNewScreen(),
      ),
      vivrantGoRoute(
        path: '/journal/history',
        builder: (_, __) => const JournalHistoryScreen(),
      ),
      vivrantGoRoute(path: '/habits', builder: (_, __) => const HabitsScreen()),
      vivrantGoRoute(
        path: '/habits/challenges',
        builder: (_, __) => const ChallengesScreen(),
      ),
      vivrantGoRoute(path: '/groceries', builder: (_, __) => const GroceriesScreen()),
      vivrantGoRoute(
        path: '/groceries/tools',
        builder: (_, __) => const GroceriesToolsScreen(),
      ),
      vivrantGoRoute(path: '/pantry', builder: (_, __) => const PantryScreen()),
      vivrantGoRoute(path: '/pantry/add', builder: (_, __) => const AddPantryScreen()),
      vivrantGoRoute(path: '/spending', builder: (_, __) => const SpendingScreen()),
      vivrantGoRoute(
        path: '/spending/history',
        builder: (_, __) => const SpendingHistoryScreen(),
      ),
      vivrantGoRoute(
        path: '/spending/log',
        builder: (_, __) => const LogExpenseScreen(),
      ),
      vivrantGoRoute(
        path: '/spending/sheet',
        builder: (_, __) => const SpendingSheetScreen(),
      ),
      vivrantGoRoute(
        path: '/spending/budget',
        builder: (_, __) => const BudgetScreen(),
      ),
      vivrantGoRoute(path: '/reports', builder: (_, __) => const ReportsScreen()),
      vivrantGoRoute(
        path: '/reports/week',
        builder: (_, __) => const ReportsWeekScreen(),
      ),
      vivrantGoRoute(
        path: '/reports/open',
        builder: (_, __) => const ReportsOpenScreen(),
      ),
      vivrantGoRoute(path: '/ai/insights', builder: (_, __) => const InsightsScreen()),
      vivrantGoRoute(
        path: '/ai/reminders',
        builder: (_, __) => const RemindersScreen(),
      ),
      vivrantGoRoute(path: '/profile', builder: (_, __) => const ProfileScreen()),
      vivrantGoRoute(
        path: '/profile/health',
        builder: (_, __) => const HealthProfileScreen(),
      ),
      vivrantGoRoute(path: '/profile/goals', builder: (_, __) => const GoalsScreen()),
      vivrantGoRoute(
        path: '/profile/history',
        builder: (_, __) => const HealthHistoryScreen(),
      ),
      vivrantGoRoute(
        path: '/profile/activity',
        builder: (_, __) => const ActivityScreen(),
      ),
      vivrantGoRoute(
        path: '/profile/archive',
        builder: (_, __) => const ArchiveScreen(),
      ),
      vivrantGoRoute(
        path: '/profile/preferences',
        builder: (_, __) => const PreferencesScreen(),
      ),
      vivrantGoRoute(
        path: '/profile/password',
        builder: (_, __) => const ChangePasswordScreen(),
      ),
      vivrantGoRoute(path: '/support', builder: (_, __) => const SupportScreen()),
      vivrantGoRoute(
        path: '/notifications',
        builder: (_, __) => const NotificationsScreen(),
      ),
      vivrantGoRoute(path: '/search', builder: (_, __) => const SearchScreen()),
      vivrantGoRoute(path: '/admin', builder: (_, __) => const AdminOverviewScreen()),
      vivrantGoRoute(
        path: '/admin/users',
        builder: (_, __) => const AdminUsersScreen(),
      ),
      vivrantGoRoute(
        path: '/admin/tickets',
        builder: (_, __) => const AdminTicketsScreen(),
      ),
      vivrantGoRoute(
        path: '/admin/roles',
        builder: (_, __) => const AdminRolesScreen(),
      ),
      vivrantGoRoute(
        path: '/admin/audit',
        builder: (_, __) => const AdminAuditScreen(),
      ),
      vivrantGoRoute(
        path: '/admin/settings',
        builder: (_, __) => const AdminSettingsScreen(),
      ),
      vivrantGoRoute(
        path: '/admin/activity',
        builder: (_, __) => const AdminActivityScreen(),
      ),
      vivrantGoRoute(
        path: '/admin/inquiries',
        builder: (_, __) => const AdminInquiriesScreen(),
      ),
    ],
  );
});

class _AuthListenable extends ChangeNotifier {
  _AuthListenable(this._ref) {
    // Defer GoRouter refresh so it never runs inside StateNotifier's
    // synchronous listener loop. A throw there becomes
    // StateNotifierListenerError and wrongly fails an otherwise-OK login.
    _ref.listen(authProvider, (_, __) {
      Future.microtask(() {
        if (hasListeners) notifyListeners();
      });
    });
  }

  final Ref _ref;
}
