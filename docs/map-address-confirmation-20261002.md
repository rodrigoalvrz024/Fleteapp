# Map address correction

User authorized publishing this correction and installing the APK after tests.

- POST /places/reverse-geocode requires a current authenticated user and limits
  each user to 12 requests/minute. Coordinates are finite and bounded, supplied
  in the request body rather than the access-log URL. Unknown fields rejected.
- Google Geocoding API is queried server-side with existing GOOGLE_MAPS_KEY.
  It must be enabled and allowed by key restrictions; queries may be billed.
  No billing plan, credential, environment or dependency changes are included.
- Street/premise/route candidates only; no locality/plus-code substitute for a
  street address. Return the original selected coordinates, not the geocoder's
  geometry. Errors expose neither key nor provider response details.
- Mobile confirms/edits the suggested address before submitting, and permits
  manual text at the selected point when unavailable. Lookup is debounced and
  stale results cannot overwrite the latest point. Map text remains bounded.
- Creation/pricing reject known generic placeholders. Existing freights are
  not migrated or rewritten; clients with old APKs must select a real address
  through search or upgrade. Existing saved addresses remain unchanged.
- Backend focused tests: 21 passed. Full production-based suite: 135/138 passed;
  same three previously documented pricing-history v2/v3 expectation failures.
  No new regression in that suite; this does not resolve general release gates.
- Flutter full suite: 254 passed, 8 optional captures skipped. No analyzer
  errors; existing warnings/hints remain. New tests cover confirmed payload,
  original coordinates, failure/manual fallback, cancellation, stale response,
  narrow screen and large text. Splash/payment/state transitions unchanged.

Existing placeholder records still require the client to confirm the actual
street/number; GPS alone is not proof of an exact door address. No live freight
or customer account is altered by this deployment.
