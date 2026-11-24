/// The three roles defined in the blueprint.
enum Role {
  pharmacist('Pharmacist', 'Validates stock and approves the plan'),
  purchaser('Purchaser', 'Reviews orders and plans'),
  branchManager('Branch manager', 'Approves transfers and recalls');

  const Role(this.label, this.summary);
  final String label;
  final String summary;
}

/// Every protected action in the app.
/// The same list becomes the permission names checked by the database
/// (row level security) in Step 2, so keep the names stable.
enum Permission {
  viewOverview('View overview and forecasts'),
  viewAudit('View the audit log'),
  importData('Import sales and batches'),
  addBatch('Add a batch'),
  validateStock('Validate stock counts'),
  runForecast('Run a forecast job'),
  manualForecast('Approve a manual forecast'),
  reviewPlan('Submit a plan review'),
  approvePlan('Approve and lock the plan'),
  approveTransfer('Approve or reject transfers'),
  approveRecall('Approve a recall'),
  recordOutcome('Record cycle outcomes');

  const Permission(this.label);
  final String label;
}