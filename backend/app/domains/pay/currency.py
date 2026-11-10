"""Country -> currency for Phlio Pay (symbols for display and activity text).

The country comes from sign-up (ISO 3166 alpha-2). The simulated ledger
stores amounts in the minor units of the transaction's currency; there is
no FX — this only decides which currency a user pays in.
"""

from __future__ import annotations

COUNTRY_CURRENCY: dict[str, str] = {
    "IN": "INR", "US": "USD", "GB": "GBP", "CA": "CAD", "AU": "AUD", "NZ": "NZD",
    "SG": "SGD", "MY": "MYR", "ID": "IDR", "TH": "THB", "PH": "PHP", "VN": "VND",
    "JP": "JPY", "KR": "KRW", "CN": "CNY", "HK": "HKD", "TW": "TWD",
    "AE": "AED", "SA": "SAR", "QA": "QAR", "KW": "KWD", "OM": "OMR", "BH": "BHD",
    "PK": "PKR", "BD": "BDT", "LK": "LKR", "NP": "NPR", "BT": "BTN", "MV": "MVR",
    "ZA": "ZAR", "NG": "NGN", "KE": "KES", "EG": "EGP", "GH": "GHS",
    "BR": "BRL", "MX": "MXN", "AR": "ARS", "CL": "CLP", "CO": "COP", "PE": "PEN",
    "CH": "CHF", "SE": "SEK", "NO": "NOK", "DK": "DKK", "PL": "PLN", "CZ": "CZK",
    "HU": "HUF", "RO": "RON", "TR": "TRY", "RU": "RUB", "UA": "UAH", "IL": "ILS",
    # Euro area
    **{c: "EUR" for c in ("DE", "FR", "IT", "ES", "PT", "NL", "BE", "AT", "IE", "FI",
                          "GR", "LU", "SK", "SI", "EE", "LV", "LT", "MT", "CY", "HR")},
}

SYMBOLS: dict[str, str] = {
    "INR": "₹", "USD": "$", "GBP": "£", "EUR": "€", "JPY": "¥", "CNY": "¥", "KRW": "₩",
    "CAD": "CA$", "AUD": "A$", "NZD": "NZ$", "SGD": "S$", "HKD": "HK$", "TWD": "NT$",
    "MYR": "RM", "IDR": "Rp", "THB": "฿", "PHP": "₱", "VND": "₫", "AED": "AED ",
    "SAR": "SAR ", "QAR": "QAR ", "KWD": "KD ", "OMR": "OMR ", "BHD": "BD ",
    "PKR": "Rs ", "BDT": "৳", "LKR": "Rs ", "NPR": "Rs ", "BTN": "Nu ", "MVR": "Rf ",
    "ZAR": "R", "NGN": "₦", "KES": "KSh ", "EGP": "E£", "GHS": "GH₵", "BRL": "R$",
    "MXN": "MX$", "ARS": "AR$", "CLP": "CLP$", "COP": "COL$", "PEN": "S/ ",
    "CHF": "CHF ", "SEK": "kr ", "NOK": "kr ", "DKK": "kr ", "PLN": "zł ",
    "CZK": "Kč ", "HUF": "Ft ", "RON": "lei ", "TRY": "₺", "RUB": "₽", "UAH": "₴",
    "ILS": "₪",
}

# Currencies without minor units in everyday use.
ZERO_DECIMAL = {"JPY", "KRW", "VND", "IDR", "CLP", "HUF"}


def currency_for(country: str | None, default: str = "INR") -> str:
    return COUNTRY_CURRENCY.get((country or "").upper(), default if not country else "USD")


def format_amount(minor_units: int, currency: str) -> str:
    symbol = SYMBOLS.get(currency, f"{currency} ")
    value = minor_units / 100
    return f"{symbol}{value:,.0f}" if value == int(value) or currency in ZERO_DECIMAL else f"{symbol}{value:,.2f}"
