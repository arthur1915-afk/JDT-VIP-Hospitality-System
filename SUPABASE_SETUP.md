# Cloud backend setup (Supabase)

This repository now includes the database foundation for shared, multi-user operation.

## 1. Create a Supabase project
Create a project at https://supabase.com/dashboard. Keep the database password private.

## 2. Apply the database schema
Open **SQL Editor → New query**, paste the contents of `supabase/schema.sql`, and run it. This creates profiles, vendors, menu items, orders, order lines and service requests, with Row Level Security policies.

## 3. Configure browser connection
Copy `supabase-config.example.js` to `supabase-config.js`. Fill in the project URL and the browser-safe publishable/anon key from **Project Settings → API**. Never use the service_role/secret key in a browser.

## 4. Create users and assign roles
Enable Email authentication in Supabase. Create the first account through Supabase Auth. Find its UUID in **Authentication → Users**, then run (replace the placeholder):

```sql
update public.profiles set role = 'admin'
where id = 'YOUR_AUTH_USER_UUID';
```

Create staff accounts and vendor accounts in Auth, then assign roles. For a vendor account, set the vendor relationship:

```sql
update public.profiles
set role = 'vendor',
    vendor_id = (select id from public.vendors where name = 'Concessions')
where id = 'YOUR_VENDOR_USER_UUID';
```

New signups are always assigned the guest role. Role changes must be made by an administrator in the trusted Supabase dashboard or a secured server-side admin workflow.

## 5. Production integration status
The existing `index.html` is still the browser-local prototype. The SQL schema is a backend foundation; it does not silently switch the prototype to cloud storage. Before live operation, complete and test the authenticated Supabase client integration for sign-in, role-aware screens, order creation (including server-side price validation), realtime subscriptions, and service requests.

## Security notes
- RLS is enabled on all application tables.
- No service-role key belongs in frontend code or GitHub.
- The prototype's localStorage data is not shared or suitable for operational records.
- The sample policies are a starting point and require a security review and end-to-end tests before a live match.
- Add menu seed data, venue/booth configuration, backups, monitoring, privacy notices and operational procedures before launch.
