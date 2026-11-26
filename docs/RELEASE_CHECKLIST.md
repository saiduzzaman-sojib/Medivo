# MEDIVO release checklist

## Every release
- [ ] `flutter analyze` shows no issues
- [ ] `flutter test` passes
- [ ] In the app, sign in as each role (pharmacist, purchaser, branch manager) and
      press Run all in Security. All 14 checks pass for each.
- [ ] `006`, `008`, `011`, `013`, `015` and `017` test scripts pass on the production
      project after the last migration
- [ ] `version:` in `pubspec.yaml` is raised (for example 1.0.1+2)

## Production Supabase project (separate from development)
- [ ] Run migrations 001 to 017 in order. Do not run `004_seed.sql` (demo data).
- [ ] Authentication: "Allow new users to sign up" is OFF
- [ ] Create real users with strong unique passwords, then link them to the real tenant
      (adapt `005_link_users.sql`: real tenant id, real names and emails)
- [ ] `update public.tenants set require_mfa = true, require_mfa_for_recall = true`
      for the real tenant
- [ ] Authentication settings: password length 12 or more, email confirmation on,
      rate limits reviewed, leaked-password protection on if your plan has it
- [ ] The service_role key is not in the app, in Git or in any chat
- [ ] A backup exists and a restore drill was done (see `BACKUP_RESTORE.md`)

## Build
Use the production configuration file. Keep the symbols file private.

```bash
# Android (needs signing, below)
flutter build appbundle --release --obfuscate --split-debug-info=build/symbols \
  --dart-define-from-file=env/prod.json

# iOS (open ios/Runner.xcworkspace in Xcode once: set Team and the bundle id)
flutter build ipa --release --obfuscate --split-debug-info=build/symbols \
  --dart-define-from-file=env/prod.json

# Web
flutter build web --release --dart-define-from-file=env/prod.json
```

## Android signing (one time)
1. Create a key and keep it OUT of Git (also back it up safely):
   `keytool -genkey -v -keystore ~/medivo-upload.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload`
2. Create `android/key.properties` (already ignored by Git):
   ```
   storePassword=...
   keyPassword=...
   keyAlias=upload
   storeFile=/Users/you/medivo-upload.jks
   ```
3. In `android/app/build.gradle.kts` add at the top:
   ```kotlin
   import java.util.Properties
   import java.io.FileInputStream

   val keystoreProperties = Properties()
   val keystorePropertiesFile = rootProject.file("key.properties")
   if (keystorePropertiesFile.exists()) {
       keystoreProperties.load(FileInputStream(keystorePropertiesFile))
   }
   ```
   and inside `android { ... }`:
   ```kotlin
   signingConfigs {
       create("release") {
           keyAlias = keystoreProperties["keyAlias"] as String
           keyPassword = keystoreProperties["keyPassword"] as String
           storeFile = file(keystoreProperties["storeFile"] as String)
           storePassword = keystoreProperties["storePassword"] as String
       }
   }
   buildTypes {
       release {
           signingConfig = signingConfigs.getByName("release")
       }
   }
   ```
   (This file is generated and differs between Flutter versions. Merge it into what is
   already there instead of pasting over it.)

## Web hosting
- Serve over HTTPS only
- Add response headers: `Strict-Transport-Security`, `X-Content-Type-Options: nosniff`,
  `Referrer-Policy: no-referrer` and a `Content-Security-Policy` that allows your
  Supabase URL and Google Fonts
- In Supabase Authentication, set the Site URL to the real web address

## Known limits (say them out loud in the pilot)
- Forecasts and plans are calculated on the device and recorded on the server.
  The server re-checks the rules, but a server-side worker is still to come.
- Offline mode shows saved data only. Changes need a connection.
- The interface is English only until the Bangla step.
- Numeric accuracy and performance targets are agreed with the owner before any
  accuracy is claimed.