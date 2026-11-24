import 'role.dart';

/// Single source of truth for who may do what.
/// Client checks only decide what the UI shows. The database enforces the
/// same matrix, so a modified client can never do more than its role allows.
const Map<Role, Set<Permission>> rolePermissions = {
  Role.pharmacist: {
    Permission.viewOverview,
    Permission.viewAudit,
    Permission.importData,
    Permission.addBatch,
    Permission.validateStock,
    Permission.runForecast,
    Permission.manualForecast,
    Permission.approvePlan,
    Permission.recordOutcome,
  },
  Role.purchaser: {
    Permission.viewOverview,
    Permission.viewAudit,
    Permission.importData,
    Permission.runForecast,
    Permission.manualForecast,
    Permission.reviewPlan,
  },
  Role.branchManager: {
    Permission.viewOverview,
    Permission.viewAudit,
    Permission.approveTransfer,
    Permission.approveRecall,
  },
};

extension RolePermissions on Role {
  bool can(Permission permission) =>
      rolePermissions[this]?.contains(permission) ?? false;
}