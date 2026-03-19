# Mobile Auth Agent

Mobile Auth Agent is an Android-focused Flutter application that reads SMS inbox messages, extracts one-time passwords (OTPs), and forwards the latest detected OTP to an external API.

The app is designed for operational OTP forwarding workflows where incoming verification codes must be detected quickly, displayed in the UI, and optionally synchronized to a backend service with enough safeguards to avoid accidental duplicate sends.

## What the app does

At a high level, the app:

- requests SMS read permission from the user
- reads inbox messages from Android through a native bridge
- filters messages that look like OTP messages
- extracts a 4 to 8 digit OTP from the SMS body
- automatically sends newly detected OTPs to a configured API endpoint
- listens for incoming SMS events while the app is open
- processes SMS received while the app is backgrounded via an Android `BroadcastReceiver`
- stores API call history locally for review in the UI
- allows manual resend by swiping a message tile

## Current platform support

The repository contains the default Flutter platform folders, but the OTP-reading functionality is implemented for **Android**.

SMS reading and realtime/background SMS handling depend on Android platform APIs such as:

- `READ_SMS`
- `RECEIVE_SMS`
- `POST_NOTIFICATIONS`
- Android `MethodChannel`
- Android `EventChannel`
- a manifest-declared `BroadcastReceiver`

## Main user-facing features

### 1. Inbox scanning

On launch, the app can read the device SMS inbox and show OTP matches in a scrollable list.

Each OTP card shows:

- extracted OTP code
- sender address
- received time
- a truncated message body

The full SMS body can be opened in a bottom sheet.

### 2. Automatic OTP API sync

When a new OTP is detected, the app can automatically call the configured API.

The current implementation sends a `GET` request to:

- `{apiBaseUrl}/fetch/latest/otp?otp=<CODE>`

with these headers:

- `origin`
- `referer`
- `visa-client`

### 3. Realtime foreground SMS handling

When the app is visible, incoming SMS messages are emitted from native Android code through an `EventChannel` to Flutter.

The current flow sends the merged SMS payload itself, not just a generic event count. This allows Flutter to prioritize the actual incoming message during OTP selection and avoids missing API calls because of inbox refresh timing races.

### 4. Background SMS handling

When the app is not visible, a native Android `BroadcastReceiver` receives `SMS_RECEIVED` events.

In background mode, the receiver can:

- evaluate the incoming SMS for OTP content
- attempt API sync natively
- record that the OTP was already handled in background
- increment a pending-message counter so Flutter can refresh after resume
- show an incoming SMS notification when appropriate

### 5. Duplicate suppression and retry flow support

The app contains two layers of duplicate protection:

- **foreground/session dedupe by SMS message ID** to stop the same inbox record from being re-sent repeatedly during refreshes
- **background handled key tracking** to avoid re-sending OTPs already processed by the native background receiver

This is intentionally more permissive than a pure `sender + otp` dedupe strategy, so retry flows still work when a new SMS arrives with the same OTP digits but represents a different message event.

### 6. Manual resend

Users can swipe left on a message tile to resend that OTP to the API manually.

This is useful when:

- the automatic API call failed
- the user wants to retry a previously detected OTP
- the backend needs to be retriggered intentionally

### 7. API history screen

The app persists API call history and exposes it in a dedicated history page.

Stored history includes:

- OTP code
- sender
- SMS received time
- API called time
- success/failure status
- optional HTTP status code
- optional error message

## OTP detection rules

OTP extraction is implemented in `lib/src/services/otp_message_filter.dart`.

The filter currently requires:

1. an SMS body containing at least one OTP-related keyword, such as:
   - `otp`
   - `code`
   - `verification`
   - `verify`
   - `passcode`
   - `authentication`
   - `auth code`
   - `security code`
   - `login code`
   - `one-time password`
2. a numeric candidate that resolves to a 4 to 8 digit OTP

Optional sender filtering is also supported via configuration.

## Project architecture

### Flutter layer

- `lib/main.dart`
  - app entry point
  - wires dependencies into `OtpReaderPage`
- `lib/src/pages/otp_reader_page.dart`
  - main screen
  - coordinates permission flow, inbox reads, realtime refresh, API sync, dedupe, and UI state
- `lib/src/pages/api_history_page.dart`
  - shows saved API request history
- `lib/src/services/sms_reader_service.dart`
  - Flutter-facing bridge for Android SMS/native APIs
- `lib/src/services/otp_message_filter.dart`
  - OTP detection and extraction logic
- `lib/src/services/otp_api_service.dart`
  - outbound API client
- `lib/src/models/*`
  - typed models for SMS messages, OTP matches, and API history entries
- `lib/src/widgets/*`
  - UI building blocks such as OTP message cards and detail sheets

### Android layer

- `android/app/src/main/kotlin/com/visa2fly/otp_message_reader/MainActivity.kt`
  - exposes a `MethodChannel` for permissions, inbox reads, config sync, history storage, and background state queries
  - exposes an `EventChannel` for foreground incoming SMS events
- `android/app/src/main/kotlin/com/visa2fly/otp_message_reader/SmsBackgroundReceiver.kt`
  - receives `SMS_RECEIVED`
  - merges multipart SMS messages
  - forwards foreground SMS payloads to Flutter
  - performs background OTP processing and API sync
  - stores background-handled keys and pending counts
  - manages local notifications and API history persistence

## Runtime flow

### App startup

1. Flutter starts `OtpReaderPage`
2. background API config is synced to native storage
3. SMS permission state is checked
4. if permission is available, inbox reading begins
5. pending background messages are consumed and refreshed if needed
6. foreground SMS event listening is started

### Foreground SMS flow

1. Android receives a new SMS
2. multipart SMS parts are merged
3. if the app is visible, native code emits the actual SMS payload through `EventChannel`
4. Flutter receives the payload and triggers a realtime refresh
5. OTP matches are filtered from the inbox
6. the incoming payload is used to choose the correct realtime OTP to sync
7. the app calls the API and records the result

### Background SMS flow

1. Android receives a new SMS while the app is not visible
2. the background receiver evaluates the SMS natively
3. if an OTP is found, the latest match is sent to the API
4. the handled OTP key is persisted to avoid duplicate foreground sync later
5. a pending-message count is stored for the Flutter UI to consume after resume

## Configuration

The real runtime configuration is kept in:

- `lib/src/config/app_config.dart`

That file is intended to stay **local and untracked**.

The public template lives in:

- `lib/src/config/app_config.example.dart`

### Create your local config

Before running the app, copy the example file and fill in your real values:

```bash
cp lib/src/config/app_config.example.dart lib/src/config/app_config.dart
```

Then update the copied `app_config.dart` with your real API values.

The current `AppConfig` fields are:

- `apiBaseUrl`
- `apiOrigin`
- `apiReferer`
- `visaClientHeaderValue`
- `senderFilters`

The example config uses placeholder values and should be replaced locally.

### Example configuration options

- `apiBaseUrl`
  - base path for the OTP API, for example `https://devapi.visa2fly.com/api`
- `senderFilters`
  - optional list of sender substrings used to restrict matching, for example `['VISATF']`

If you want to change environments, update your local `app_config.dart` or inject a different `AppConfig` into `MyApp`.

## Android permissions and manifest behavior

The Android manifest currently declares:

- `android.permission.READ_SMS`
- `android.permission.RECEIVE_SMS`
- `android.permission.POST_NOTIFICATIONS`

It also registers `SmsBackgroundReceiver` for:

- `android.provider.Telephony.SMS_RECEIVED`

## Local development

### Prerequisites

- Flutter SDK
- Dart SDK compatible with the Flutter version in use
- Android SDK / Android Studio
- an Android device or emulator

### Run the app

```bash
flutter pub get
cp lib/src/config/app_config.example.dart lib/src/config/app_config.dart
flutter run
```

Because this project includes native Android code for SMS handling, perform a **full rebuild** after Kotlin/manifest changes instead of relying only on hot reload.

## Testing

The project includes unit and widget tests covering:

- OTP extraction behavior
- API client behavior
- UI flows
- duplicate suppression
- manual resend
- background-handled OTP suppression
- realtime incoming SMS event processing
- race-condition protection for queued incoming refreshes

Useful commands:

```bash
flutter test
flutter test test/widget_test.dart
flutter analyze
```

## Operational notes

- A `403` from the API usually means the request reached the server but was rejected.
- A timeout usually means network reachability, IP routing, firewall, or protocol mismatch.
- If foreground SMS events appear to be ignored after native code changes, rebuild and reinstall the app.
- Sender filters are optional; if configured, only senders containing those substrings are considered.

## Repository status and intent

This is not a generic starter Flutter app anymore. It is a workflow-driven Android OTP forwarding tool with:

- native Android SMS integration
- realtime and background OTP processing
- external API synchronization
- retry support
- local audit history
- a Flutter UI for review and manual intervention

## License

No license file is currently included in this repository.
