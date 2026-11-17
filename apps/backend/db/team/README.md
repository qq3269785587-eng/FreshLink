# Team database bootstrap files

This directory contains the shareable empty-schema baseline for the FreshLink team repository. The DDL was extracted from `apps/backend/db/xingchenwms-20251114.sql`; only the 148 `CREATE TABLE` statements were retained. No dump `INSERT` statements, user records, business records, model configuration, API keys, or logs were copied. The upstream project license must remain in the repository.

## Initialization order

Use `scripts/team/Initialize-TeamDatabase.ps1` from the repository root. It should:

1. Read `runtime/config/team-private.json` (local configuration, excluded from Git).
2. Prompt for MySQL administrator credentials and create only a missing schema whose name starts with `freshlink_`.
3. Import, in order:
   - `apps/backend/db/team/00_base_schema.sql`
   - `apps/backend/db/team/01_framework_seed.sql`
   - `apps/backend/db/fresh/P1_00_schema.sql`
   - `apps/backend/db/fresh/P1_10_menu_role_dict.sql`
   - `apps/backend/db/fresh/P1_20_demo_data.sql`
4. Create a local initial administrator and four P1 demo users with random local passwords. Store credentials only as Windows DPAPI CurrentUser ciphertext in ignored `runtime/config/team-demo-accounts.json`, protected for the current Windows user. Do not commit or send that file.

To view the login credentials on the same Windows account that initialized the database, run `scripts/team/Show-TeamDemoAccounts.ps1` (the local copies of these scripts are supplied from this directory). It intentionally prints secrets only when explicitly invoked.

The script must reject existing schemas (even empty ones), the legacy `xingchenwms` schema, names without the `freshlink_` prefix, and any schema containing tables. Run it only against a disposable team schema.

## Manual import

If bootstrapping manually, first create an empty schema named `freshlink_<yourname>`, then run the five SQL files above in order. This manual route does not create application users. Use the local initializer for credentials. Never import a private machine dump.

## Seed scope

`01_framework_seed.sql` creates one clean demo organization and the stable dashboard root menu ID required by P1 role grants. P1 migrations add FreshLink menus, roles, dictionaries, and example W1/S1/S2/A/B/X/Y records. Framework system menus unrelated to FreshLink, AI model settings, datasource settings, logs, and personal accounts are intentionally absent.
