# MEDIVO backup and restore

Rehearse this before the pilot, and again after any big change. A backup that has
never been restored is only a hope.

## What must survive a restore
- Approved plan revisions (and their `content_hash`), transfers, outcomes
- The audit chain (`audit_log`) with its hashes
- Batches, sales history, forecast runs

The app does not use Supabase Storage, so there are no stored files to protect.

## What the provider gives you
(check the current Supabase documentation for your plan before relying on this)
- Pro, Team and Enterprise projects: automatic daily backups kept for 7, 14 and 30
  days. Point-in-Time Recovery is an add-on.
- Free projects: no automatic backups. Take your own dump and keep it off-site.

## Taking your own dump
Use the session pooler connection string from the dashboard (Connect).
`pg_dump` includes rows by default. `supabase db dump` is schema-only unless you add `--data-only`.

```bash
pg_dump "<session-pooler-connection-string>" -Fc -n public -f medivo-YYYY-MM-DD.dump
```

Use a `pg_dump` at least as new as the project's Postgres. Encrypt the file and
store it somewhere other than the project that holds the data. Never commit it to Git.

## Restore drill (paid plans)
1. Dashboard, Database, Backups: restore a daily backup into a NEW project
   (restoring to a new project keeps your live data untouched).
2. In the SQL editor of the restored project run:
   `select public.admin_restore_report();`
3. In production run the same query and compare. Row counts must match the backup time.
   `approved_without_hash` and `profiles_without_user` must be 0.
   Every entry in `audit` must show `"ok": true`.
4. Sign in to the restored project as each role. In Security, press **Run all**.
5. Write the date, who ran it and the result below.

## If you only have your own dump
A dump restores into the SAME project after a data loss. Rows point at users
(`created_by`, `validated_by` and so on), so a different project needs the same
user ids; do not try this without rehearsing it first.

Load data with the restore flag on, so rows that have expired since the backup are
accepted (the expiry rules are skipped only for a connection that sets this flag):

```bash
PGOPTIONS="-c medivo.restore=on" pg_restore --data-only --no-owner -d "<connection-string>" medivo-YYYY-MM-DD.dump
```

## Rollback
- Keep the previous app build available.
- Database migrations only move forward. A rollback of data means restoring from a backup.

## Drill log
| Date | Who | Source | Result |
|---|---|---|---|
| | | | |