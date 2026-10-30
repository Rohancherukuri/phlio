# Phlio Pay sandbox integration

Open Phlio Pay > UPI, cards & bank statements. This addition is separate from
the existing demo wallet/QR ledger, which does not move real money.

## Packages and rails

The official `razorpay_flutter` 1.4.7 SDK handles checkout on Android/iOS. The
existing Dio client talks to FastAPI; httpx calls Razorpay from the backend.
Existing file_picker selects statement CSVs. Native Flutter animations implement
processing, success and failure without animation assets or another dependency.

This is merchant checkout, not a UPI TPAP/P2P banking integration. Available UPI,
card and bank methods are controlled by Razorpay account configuration; actual
UPI app switching requires provider-supported testing/live onboarding. No bank
linking, UPI PIN collection, PAN/CVV storage, payouts or automatic bank sync is
implemented. The sandbox rejects live keys. A gateway account is not free money
movement: provider production fees and onboarding apply separately.

## Setup

Add to backend .env (never Flutter or source control):

```
RAZORPAY_KEY_ID=rzp_test_your_key
RAZORPAY_KEY_SECRET=your_test_secret
PAY_GATEWAY_DATABASE=data/pay_gateway.sqlite3
```

Restart the API. Enable automatic capture in the provider dashboard for successful
sandbox checkouts. Missing keys show setup pending rather than fabricated success.
Use Razorpay's current documented test methods for your account.

Orders are stored durably and scoped by authenticated owner. A client request UUID
is claimed once; an uncertain creation timeout is never silently retried at the
provider. Such orders require reconciliation by receipt in the provider dashboard.
App callback signatures use HMAC-SHA256 and the stored server order id. Success
requires a server-fetched captured payment with matching order, INR and amount.
Authorised, cancelled-client and network-error outcomes remain pending unless the
provider confirms failure. History supports status refresh after restart. There is
no webhook/background reconciliation yet; check status fetches the authoritative
provider result. This is sandbox-ready, not a production launch.

## Statement import

UTF-8 CSV, <=2 MB / 1000 rows, columns:
`date,description,amount,direction,method,account,reference`.
Date: YYYY-MM-DD. Amount: positive decimal INR, max two decimal places.
Direction: debit or credit. Method: upi, debit_card, credit_card, bank, cash, other.
Account: nickname or last four digits (do not supply full card/account numbers).
Reference is optional. Map your bank export to these columns first. PDF/XLS and
bank-specific parsers are not supported. A sample is in docs/examples/pay_statement.csv.

Preview requires confirmation; it expires after ten minutes and is replaced by
the next preview. Imports are transactionally inserted, scoped to the user, and
deduplicate identical normalised rows while preserving repeated identical rows in
one file. Overlapping statements with ambiguous duplicate rows may need manual
review; use consistent references/account names. Imported records are labelled
and never change wallet balances or trigger payments. Remove deletes an imported
entry. Data remains in the backend SQLite store; protect its backups as private
financial data. Live bank feeds would require a consent-based bank/AA integration.

## Verification

Backend tests cover ownership, deduplication, invalid money, repeat order requests,
forged callbacks, captured-versus-authorised status, and live-key rejection.
Widget tests cover processing/final states on a narrow screen. Actual provider
checkout cannot be validated until test credentials are supplied.

References: https://razorpay.com/docs/payments/payment-gateway/flutter-integration/standard/integration-steps/
https://razorpay.com/docs/api/payments/fetch-with-id/

Visual reference: https://mobbin.com/screens/25fc692d-19a1-4de4-a63f-b0a6ecca0bd6
(circular confirmation and a clear result label). PhonePe was not returned by the
reference search; these are Phlio-native animations, not copied PhonePe assets.
