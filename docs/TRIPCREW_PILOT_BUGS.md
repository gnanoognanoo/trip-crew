# TripCrew Pilot — Bug Log

This log is used by pilot organizers and testers to track issues encountered during real-world outings.

> **Instruction for Testers**: Fill in a new entry for each bug encountered. **Do not automatically mark bugs resolved** until verified by a developer on physical hardware.

---

## Bug Template

```markdown
### [BUG-XXX] Short Title

- **ID**: BUG-001
- **Date**: YYYY-MM-DD
- **Feature**: TripCrew Pay / Live Crew / Trip Pulse / Auth / Other
- **Phone**: e.g., Google Pixel 7 / Samsung Galaxy S23 / OnePlus 11
- **Android Version**: e.g., Android 14 / Android 13
- **Steps to Reproduce**:
  1. Open TripCrew Pay in trip workspace
  2. Tap 'Pay from Trip Pot'
  3. Enter amount and tap Confirm
- **Expected Result**: Payment processes and reduces pot balance
- **Actual Result**: Error message or crash
- **Severity**: Critical (Crash / Data Loss) | Major (Blocked Feature) | Minor (Cosmetic / Typo)
- **Status**: Open / Investigating / Fixed / Verified
```

---

## Active Pilot Bug Entries

### [BUG-001] Example Pilot Entry (Template Reference)
- **ID**: BUG-001
- **Date**: 2026-09-11
- **Feature**: TripCrew Pay
- **Phone**: Physical Android Test Device
- **Android Version**: Android 14
- **Steps to Reproduce**:
  1. Disconnect network completely (Airplane Mode).
  2. Attempt sandbox contribution or payment.
- **Expected Result**: UI displays clear message: "TripCrew Pay requires an internet connection."
- **Actual Result**: Works as expected (Blocked offline).
- **Severity**: Minor
- **Status**: Open
