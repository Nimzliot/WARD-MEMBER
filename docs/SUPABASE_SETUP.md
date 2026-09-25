# Supabase Dashboard Setup

## 1. Create the project
1. Go to https://supabase.com/dashboard, then **New project**. Pick the region closest to your users (Mumbai `ap-south-1`).
2. Wait for the project to finish provisioning.

## 2. Run the schema
1. Open **SQL Editor**, click **New query**, paste all of `database/schema.sql`, and click **Run**.
2. The last result grid should list 3 wards with 4, 4 and 3 proposals.

## 3. Turn on email OTP (a 6-digit code instead of a magic link)
1. Open **Authentication**, then **Sign In / Providers**, then **Email**.
   - **Enable Email provider**: ON
   - **Confirm email**: ON
   - **Email OTP Length**: `6`
   - **Email OTP Expiration**: `600` seconds (10 min) is plenty
2. Open **Authentication**, then **Emails**, then **Templates**, then **Magic Link**. Replace the body with:

   ```html
   <h2>Your Ward Budget login code</h2>
   <p>Enter this code in the app:</p>
   <p style="font-size:32px;font-weight:bold;letter-spacing:8px">{{ .Token }}</p>
   <p>It expires in 10 minutes. If you didn't request it, ignore this email.</p>
   ```
   Subject: `Your login code: {{ .Token }}`

3. Make the same change to the **Confirm signup** template. A brand-new email address can receive that template on its first `signInWithOtp`. If the template still contains `{{ .ConfirmationURL }}`, the new user gets a link instead of a code.
4. Click **Save** on both templates.

The app verifies the code with `verifyOTP(type: OtpType.email, ...)`, which accepts both the signup code and the login code.

## 4. Email rate limits (important for the demo)
The built-in Supabase mailer sends only a few emails per hour, and you will hit that limit while testing.
- For the demo, go to **Authentication**, then **Emails**, then **SMTP Settings**, and connect a free SMTP provider (Brevo, Resend, or a Gmail App Password). Then raise **Rate Limits**, then **Emails sent per hour**.

## 5. URL configuration
Open **Authentication**, then **URL Configuration**. Nothing here is needed for the OTP flow, because the app never opens links. Leave the defaults.

## 6. Realtime
`schema.sql` already adds `votes` to the `supabase_realtime` publication. To check, open **Database**, then **Publications**, then `supabase_realtime`. `votes` should be ticked.

## 7. Collect your keys (Project Settings, then API / API Keys)
| Value | Used by | Notes |
|---|---|---|
| Project URL | Flutter + Node | `https://xxxx.supabase.co` |
| `anon` / publishable key | Flutter | Safe to ship in the app |
| `service_role` / secret key | Node only | **Never** put this in the Flutter app or commit it |

## 8. Make a user an admin
After the user has signed in once (so their profile row exists), run this in the SQL Editor:
```sql
update public.profiles set role = 'admin' where email = 'you@example.com';
```
