// Phlio Pay currency: which money symbol a person sees and pays in.
//
// Decided by the country picked at sign-up (`UserEntity.country`); for
// accounts made before that was stored, the phone number's country code,
// then the device region. India → ₹, United States → $, the euro area → €,
// and so on. Mirrors `backend/app/domains/pay/currency.py`.

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/authentication/presentation/controllers/auth_controller.dart';

@immutable
class PhlioCurrency {
  const PhlioCurrency(this.code, this.symbol, {this.icon, this.decimals = 2});

  /// ISO 4217, e.g. INR.
  final String code;

  /// Display symbol, e.g. ₹.
  final String symbol;

  /// A Material icon for the symbol when one exists (else draw [symbol]).
  final IconData? icon;
  final int decimals;

  String format(int minorUnits, {bool signed = false, bool negative = false}) {
    final value = minorUnits / 100;
    final whole = value == value.truncateToDouble() || decimals == 0;
    final text = _group(whole ? value.toStringAsFixed(0) : value.toStringAsFixed(2));
    final sign = signed ? (negative ? '−' : '+') : '';
    return '$sign$symbol$text';
  }

  /// Quick amounts for the pay sheet, in this currency's everyday sizes.
  List<int> get quickAmounts => switch (code) {
        'INR' || 'PKR' || 'LKR' || 'NPR' || 'BDT' => [100, 500, 1000, 2000],
        'JPY' || 'KRW' => [1000, 3000, 5000, 10000],
        'IDR' || 'VND' => [50000, 100000, 200000, 500000],
        _ => [5, 10, 20, 50],
      };

  static String _group(String number) {
    final parts = number.split('.');
    final digits = parts[0];
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
      buffer.write(digits[i]);
    }
    return parts.length > 1 ? '$buffer.${parts[1]}' : buffer.toString();
  }
}

const _euro = PhlioCurrency('EUR', '€', icon: Icons.euro_rounded);

const Map<String, PhlioCurrency> phlioCurrencies = {
  'INR': PhlioCurrency('INR', '₹', icon: Icons.currency_rupee_rounded),
  'USD': PhlioCurrency('USD', '\$', icon: Icons.attach_money_rounded),
  'GBP': PhlioCurrency('GBP', '£', icon: Icons.currency_pound_rounded),
  'EUR': _euro,
  'JPY': PhlioCurrency('JPY', '¥', icon: Icons.currency_yen_rounded, decimals: 0),
  'CNY': PhlioCurrency('CNY', '¥', icon: Icons.currency_yuan_rounded),
  'KRW': PhlioCurrency('KRW', '₩', decimals: 0),
  'RUB': PhlioCurrency('RUB', '₽', icon: Icons.currency_ruble_rounded),
  'TRY': PhlioCurrency('TRY', '₺', icon: Icons.currency_lira_rounded),
  'CHF': PhlioCurrency('CHF', 'CHF ', icon: Icons.currency_franc_rounded),
  'CAD': PhlioCurrency('CAD', 'CA\$', icon: Icons.attach_money_rounded),
  'AUD': PhlioCurrency('AUD', 'A\$', icon: Icons.attach_money_rounded),
  'NZD': PhlioCurrency('NZD', 'NZ\$', icon: Icons.attach_money_rounded),
  'SGD': PhlioCurrency('SGD', 'S\$', icon: Icons.attach_money_rounded),
  'HKD': PhlioCurrency('HKD', 'HK\$', icon: Icons.attach_money_rounded),
  'TWD': PhlioCurrency('TWD', 'NT\$', icon: Icons.attach_money_rounded),
  'MXN': PhlioCurrency('MXN', 'MX\$', icon: Icons.attach_money_rounded),
  'BRL': PhlioCurrency('BRL', 'R\$'),
  'ARS': PhlioCurrency('ARS', 'AR\$', icon: Icons.attach_money_rounded),
  'CLP': PhlioCurrency('CLP', 'CLP\$', decimals: 0),
  'COP': PhlioCurrency('COP', 'COL\$'),
  'PEN': PhlioCurrency('PEN', 'S/ '),
  'MYR': PhlioCurrency('MYR', 'RM'),
  'IDR': PhlioCurrency('IDR', 'Rp', decimals: 0),
  'THB': PhlioCurrency('THB', '฿'),
  'PHP': PhlioCurrency('PHP', '₱'),
  'VND': PhlioCurrency('VND', '₫', decimals: 0),
  'AED': PhlioCurrency('AED', 'AED '),
  'SAR': PhlioCurrency('SAR', 'SAR '),
  'QAR': PhlioCurrency('QAR', 'QAR '),
  'KWD': PhlioCurrency('KWD', 'KD '),
  'OMR': PhlioCurrency('OMR', 'OMR '),
  'BHD': PhlioCurrency('BHD', 'BD '),
  'PKR': PhlioCurrency('PKR', 'Rs '),
  'BDT': PhlioCurrency('BDT', '৳'),
  'LKR': PhlioCurrency('LKR', 'Rs '),
  'NPR': PhlioCurrency('NPR', 'Rs '),
  'BTN': PhlioCurrency('BTN', 'Nu '),
  'MVR': PhlioCurrency('MVR', 'Rf '),
  'ZAR': PhlioCurrency('ZAR', 'R'),
  'NGN': PhlioCurrency('NGN', '₦'),
  'KES': PhlioCurrency('KES', 'KSh '),
  'EGP': PhlioCurrency('EGP', 'E£'),
  'GHS': PhlioCurrency('GHS', 'GH₵'),
  'SEK': PhlioCurrency('SEK', 'kr '),
  'NOK': PhlioCurrency('NOK', 'kr '),
  'DKK': PhlioCurrency('DKK', 'kr '),
  'PLN': PhlioCurrency('PLN', 'zł '),
  'CZK': PhlioCurrency('CZK', 'Kč '),
  'HUF': PhlioCurrency('HUF', 'Ft ', decimals: 0),
  'RON': PhlioCurrency('RON', 'lei '),
  'UAH': PhlioCurrency('UAH', '₴'),
  'ILS': PhlioCurrency('ILS', '₪'),
};

const Map<String, String> _countryCurrency = {
  'IN': 'INR', 'US': 'USD', 'GB': 'GBP', 'CA': 'CAD', 'AU': 'AUD', 'NZ': 'NZD',
  'SG': 'SGD', 'MY': 'MYR', 'ID': 'IDR', 'TH': 'THB', 'PH': 'PHP', 'VN': 'VND',
  'JP': 'JPY', 'KR': 'KRW', 'CN': 'CNY', 'HK': 'HKD', 'TW': 'TWD',
  'AE': 'AED', 'SA': 'SAR', 'QA': 'QAR', 'KW': 'KWD', 'OM': 'OMR', 'BH': 'BHD',
  'PK': 'PKR', 'BD': 'BDT', 'LK': 'LKR', 'NP': 'NPR', 'BT': 'BTN', 'MV': 'MVR',
  'ZA': 'ZAR', 'NG': 'NGN', 'KE': 'KES', 'EG': 'EGP', 'GH': 'GHS',
  'BR': 'BRL', 'MX': 'MXN', 'AR': 'ARS', 'CL': 'CLP', 'CO': 'COP', 'PE': 'PEN',
  'CH': 'CHF', 'SE': 'SEK', 'NO': 'NOK', 'DK': 'DKK', 'PL': 'PLN', 'CZ': 'CZK',
  'HU': 'HUF', 'RO': 'RON', 'TR': 'TRY', 'RU': 'RUB', 'UA': 'UAH', 'IL': 'ILS',
  'DE': 'EUR', 'FR': 'EUR', 'IT': 'EUR', 'ES': 'EUR', 'PT': 'EUR', 'NL': 'EUR',
  'BE': 'EUR', 'AT': 'EUR', 'IE': 'EUR', 'FI': 'EUR', 'GR': 'EUR', 'LU': 'EUR',
  'SK': 'EUR', 'SI': 'EUR', 'EE': 'EUR', 'LV': 'EUR', 'LT': 'EUR', 'MT': 'EUR',
  'CY': 'EUR', 'HR': 'EUR',
};

/// Longest calling-code prefixes first.
const List<(String, String)> _phoneCountry = [
  ('+971', 'AE'), ('+966', 'SA'), ('+974', 'QA'), ('+965', 'KW'), ('+968', 'OM'),
  ('+973', 'BH'), ('+977', 'NP'), ('+975', 'BT'), ('+960', 'MV'), ('+880', 'BD'),
  ('+886', 'TW'), ('+852', 'HK'), ('+234', 'NG'), ('+254', 'KE'), ('+233', 'GH'),
  ('+353', 'IE'), ('+351', 'PT'), ('+358', 'FI'), ('+380', 'UA'), ('+420', 'CZ'),
  ('+972', 'IL'), ('+91', 'IN'), ('+44', 'GB'), ('+61', 'AU'), ('+64', 'NZ'),
  ('+65', 'SG'), ('+60', 'MY'), ('+62', 'ID'), ('+66', 'TH'), ('+63', 'PH'),
  ('+84', 'VN'), ('+81', 'JP'), ('+82', 'KR'), ('+86', 'CN'), ('+92', 'PK'),
  ('+94', 'LK'), ('+27', 'ZA'), ('+20', 'EG'), ('+55', 'BR'), ('+52', 'MX'),
  ('+54', 'AR'), ('+56', 'CL'), ('+57', 'CO'), ('+51', 'PE'), ('+41', 'CH'),
  ('+46', 'SE'), ('+47', 'NO'), ('+45', 'DK'), ('+48', 'PL'), ('+36', 'HU'),
  ('+40', 'RO'), ('+90', 'TR'), ('+49', 'DE'), ('+33', 'FR'), ('+39', 'IT'),
  ('+34', 'ES'), ('+31', 'NL'), ('+32', 'BE'), ('+43', 'AT'), ('+30', 'GR'),
  ('+7', 'RU'), ('+1', 'US'),
];

PhlioCurrency currencyByCode(String? code) =>
    phlioCurrencies[(code ?? '').toUpperCase()] ??
    PhlioCurrency((code ?? 'INR').toUpperCase(), '${(code ?? 'INR').toUpperCase()} ');

PhlioCurrency currencyForCountry(String? country) {
  final code = _countryCurrency[(country ?? '').toUpperCase()];
  return code == null ? phlioCurrencies['USD']! : currencyByCode(code);
}

String? countryFromPhone(String? phone) {
  if (phone == null || !phone.startsWith('+')) return null;
  for (final (prefix, country) in _phoneCountry) {
    if (phone.startsWith(prefix)) return country;
  }
  return null;
}

/// The signed-in person's Pay currency.
final userCurrencyProvider = Provider<PhlioCurrency>((ref) {
  final user = ref.watch(authControllerProvider).valueOrNull;
  final country = user?.country ??
      countryFromPhone(user?.phoneNumber) ??
      ui.PlatformDispatcher.instance.locale.countryCode ??
      'IN';
  return currencyForCountry(country);
});

/// A currency symbol in a thin circle — the "pay" button in chat composers
/// (₹ in India, $ in the US, € in the euro area…).
class CurrencyGlyph extends StatelessWidget {
  const CurrencyGlyph({super.key, required this.currency, this.size = 26, this.color = Colors.white});

  final PhlioCurrency currency;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final symbol = currency.symbol.trim();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: color, width: size * 0.075),
      ),
      child: currency.icon != null
          ? Icon(currency.icon, size: size * 0.62, color: color)
          : FittedBox(
              child: Padding(
                padding: EdgeInsets.all(size * 0.16),
                child: Text(symbol,
                    style: TextStyle(
                        color: color, fontWeight: FontWeight.w700, fontSize: size * 0.5, height: 1)),
              ),
            ),
    );
  }
}
