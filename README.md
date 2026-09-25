# Participatory Municipal Budgeting App (SDG 11)

Ward residents view their ward's municipal budget proposals, vote on how the money should be spent, and watch live results. Every vote is hash-chained, so tampering is visible.

| Folder | What |
|---|---|
| `app/` | Flutter app (Material 3, Supabase, go_router, Provider, fl_chart) |
| `server/` | Node.js + Express API (SMS OTP login via Fast2SMS, votes hash chain, audit, admin) |
| `database/` | `schema.sql` (tables, RLS, triggers, seed data) + migrations |
| `docs/` | Supabase dashboard setup |

## Quick start
1. **Supabase**: run `database/schema.sql` in the SQL Editor, then follow `docs/SUPABASE_SETUP.md`.
2. **Server**
   ```bash
   cd server
   cp .env.example .env      # fill in your keys
   npm install
   npm run dev
   ```
3. **App**
   ```bash
   cd app
   cp config.example.json config.json   # Supabase URL, anon key, API_BASE_URL
   flutter run --dart-define-from-file=config.json
   flutter build apk --release --dart-define-from-file=config.json
   ```
   `API_BASE_URL`: `http://10.0.2.2:3000` (Android emulator), `http://<laptop LAN IP>:3000` (phone on the same Wi-Fi), or an ngrok / Render HTTPS URL.

## Login
Users choose **one** method: an email code (Supabase Auth) or an SMS code (Fast2SMS through the Node server). Then they complete their profile (name, ward, Resident ID, e.g. `RES-1-1234` for Ward 1).

Make a user admin:
```sql
update profiles set role = 'admin' where email = 'you@example.com';
```
