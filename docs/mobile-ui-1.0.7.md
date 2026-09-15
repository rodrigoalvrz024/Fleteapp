# Mobile UI and navigation - 1.0.7

## Navigation fix

- Client tabs (freights, payments, profile) and driver tabs (trips, payouts,
  profile) now have their respective home route beneath them.
- Primary mobile tabs use immediate transitions; task pages retain native
  forward/back transitions. Existing URLs and query parameters are preserved.
- Payments includes the shared bottom navigation. It highlights Payments and
  supports returning home through the tab bar, toolbar or Android Back.
- Shared task headers provide an explicit back button with a role-aware fallback
  for direct links. Chat falls back to its freight, recovery to sign-in.
- Hidden driver home does not open an incoming-request overlay over another task.

## Design coverage

| Area | Change |
| --- | --- |
| Payments | Compact header, card-availability sheet, links to freight payment history and help, permanent tab bar |
| Client/driver profile hubs | Unframed grouped rows, shorter section headings, tappable identity, shared toolbar |
| Addresses, notifications, promotions, help, preferences | Shared compact page frame, adaptive switches, consistent spacing and typography |
| Freight lists/details, request flow, profile editor, driver trips/payouts, legal documents | Shared mobile header, safe areas, back action and compact empty states through WebPageScaffold |
| Driver documents/vehicle registration | Shared mobile frame with an explicit exit, including loading and verification states |
| Chat | Explicit return to the relevant freight; existing chat appearance and behavior retained |
| Login/register | Smaller mobile headings; login remains scrollable when system text is enlarged |
| Password recovery/reset | Clean mobile background with existing Muvv logo, shared primary action and compact form |
| Shared controls | Immediate press feedback, reduced-motion support, wrapping status labels and accessible tab actions |

The approved Splash source, assets and timeline were not changed. Backend,
prices, permissions, stored payment data and deployment settings were not changed.

## Checks

- `flutter test --no-pub`: navigation, chat, typography and Splash regression tests.
- Utility layouts tested at 320x640 and 393x852, with system text at 100% and 200%.
- `flutter analyze --no-pub --no-fatal-infos --no-fatal-warnings`: no errors;
  existing unused-code/deprecation notices remain.
- Optional preview command: `flutter test --no-pub --dart-define=MUVV_UI_CAPTURE=<absolute-output-directory>`.
  Captures use real Flutter widgets with test account placeholders, not customer data.

## Physical Android verification - 2026-09-06

- Installed release 1.0.7 (versionCode 8) on the connected Huawei ANE-LX3,
  preserving its existing test-account session.
- Installed APK SHA-256 matched the built artifact:
  `A9CC3A5B0873064E8FB1410AA5626F04A92BD9F7ECF01742A4FE93A2B18E5480`.
- Driver: opened Gains, Trips and Profile; the bottom navigation remained
  visible. Android Back from Gains returned to driver Home.
- Switched the existing approved test account to client mode. Payments kept
  its bottom navigation. Both Android Back and the toolbar arrow returned Home.
- Payments -> Profile worked. Profile -> Payment methods -> toolbar Back
  returned to Profile. The Webpay information sheet opened and closed normally.
- Restored the account to driver mode and Home. No freight was created,
  accepted, started or completed, and no payment was initiated.
- Device evidence is under `output/muvv-1.0.7-phone-*.png` and the related
  UI hierarchy XML files. These are local QA artifacts, not production assets.
- Separate password-login verification from the PC could not be completed:
  Railway requests timed out. The existing session and role switch worked on
  the phone. This run does not establish that historical test passwords remain
  valid and did not reset any password.

## Still required

- Verify on a physical iPhone, including safe areas, keyboard and larger text.
- Webpay card storage/payment activation remains unavailable. This UI does not
  collect card details or initiate charges.
- Existing placeholder features (saved addresses, coupon validation, some
  settings persistence) are not implemented by this design change.
- This is a shared mobile design pass, not a redesign of the public website or
  administrative dashboard. The latter still needs its own visual review.
