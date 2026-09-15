# Cargo and vehicle selection - pilot

## Scope

Mobile request flow: Route > Cargo > Vehicle > Time > Price.
The approved splash, backend prices, driver approval rules and production
deployment are unchanged. Existing source changes in the workspace are retained.

## Customer experience

- Add quantities of familiar objects instead of requiring customers to guess kg.
- Reference objects carry explicitly approximate planning weights and volumes.
  The customer may override totals with known measurements; photos remain optional.
- Object names and quantities are included in the stored cargo description, so
  the driver can see the declared load through the existing details endpoint.
- The server recommends a vehicle. Customers can choose that class or a larger
  supported class; smaller classes are unavailable. No unsupported passenger-car
  category has been added.
- Plain-language vehicle descriptions explain open vs enclosed cargo space and
  typical use cases, without promising a particular vehicle's exact dimensions.
- The recommended option is selected by default and shown first on its own.
  Comparing other vehicles is optional. Cards lead with familiar cargo uses
  (furniture and boxes, several large pieces, bulky move), show labeled household
  icons, and retain the actual vehicle category as secondary text. These examples
  are not capacity guarantees. Customers can return directly to edit their load.
- Each selected vehicle fetches a server quote. Prices are not multiplied or
  calculated on-device. The recommendation is shown first.
- Changing the time recalculates the final quote. UTC timestamps are used for
  both estimate and creation. The requested category is bound to the quote and
  is sent unchanged when creating the request.
- Editing inputs invalidates prices. Stale asynchronous responses cannot restore
  an old quote. Manual-review cargo cannot be submitted with an automatic price.

## Design review

Applied the Apple-design reference's restraint, immediate touch feedback,
accessible text scaling, familiar controls and reduced-motion support:
https://github.com/emilkowalski/skills/blob/main/skills/apple-design/SKILL.md

- Shared compact header, back action, typography and persistent primary CTA.
- Five-step progress indicator, with readable current-step name instead of five
  tiny labels. Advancing or returning resets the content to its beginning.
- Inventory in a dismissible sheet; familiar plus/minus buttons with tooltips.
- Selected and recommended vehicles are distinct states, with radio/check cues.
- Service choices retain Muvv's existing pastel palette and adapt to large text.
- Timetable choices grow with their content. Step/selection animations respect
  reduced motion. Login fields and social controls also accommodate large text.

This review covers the request wizard, not a certification of all screens after
booking (payment, live trip, delivery and ratings still need end-to-end device QA).

## Verification

- 30 focused Flutter tests: login roles, request steps, quote invalidation,
  submission payload, small-screen text scaling, navigation and unchanged splash.
- 13 existing Python unit tests: pricing service and quote integrity.
- Tests use a simulated API and do not create real customer orders or payments.
- Static analysis: no errors or warnings in the reviewed flow; style-only
  suggestions remain in existing code.
- Android release-mode APK 1.0.9 (versionCode 10) built and installed with
  `adb install -r` on the connected Huawei; installed version verified through
  Android package metadata. Existing application data was retained.
- Physical testing of the new wizard is pending: the handset locked again
  during compilation. No live order or payment was created.

## Before public release

- Calibrate the reference object allowances against actual pilot loads. They are
  product planning defaults, not measured weights or guaranteed fit. Oversized,
  dense, industrial and unlisted objects still require measurements/review.
- Confirm per-vehicle interior dimensions and protection of exposed cargo.
- Verify the full flow on a physical iPhone and with VoiceOver/TalkBack.
- Test actual uploads, scheduled time, manual quote/support and driver detail
  visibility together with approved driver matching. Do not treat mock tests as
  proof that live storage, payments or dispatch are healthy.
- The local Android build uses the existing debug signing configuration in
  release mode; production store signing must be prepared separately.
