/// Holds the logged-in session values for the lifetime of the app process.
///
/// This is the Flutter equivalent of the Android app's `public static` fields on
/// `LoginActivity` (`authToken`, `dealerId`, `userType`, `employeeId`). Like
/// Android, these are kept **in memory only** — they are NOT persisted, so an
/// app kill means the user logs in again. Every later API reads from here, just
/// as Android reads `LoginActivity.authToken` / `LoginActivity.dealerId`.
class SessionService {
  SessionService._();
  static final SessionService instance = SessionService._();

  String authToken = '';
  String dealerId = '';
  String userType = '';
  String employeeId = '';

  // Discount config from the login response (Android LoginActivity statics).
  // enable_payment_discount: 1 = discount feature on for this tenant (default 0).
  // max_discount_percent_allowed: the % cap (default 100).
  int enablePaymentDiscount = 0;
  int maxDiscountPercentAllowed = 100;

  bool get isLoggedIn => authToken.isNotEmpty;

  void setFromLogin({
    required String authToken,
    required String dealerId,
    required String userType,
    required String employeeId,
    int enablePaymentDiscount = 0,
    int maxDiscountPercentAllowed = 100,
  }) {
    this.authToken = authToken;
    this.dealerId = dealerId;
    this.userType = userType;
    this.employeeId = employeeId;
    this.enablePaymentDiscount = enablePaymentDiscount;
    this.maxDiscountPercentAllowed = maxDiscountPercentAllowed;
  }

  void clear() {
    authToken = '';
    dealerId = '';
    userType = '';
    employeeId = '';
    enablePaymentDiscount = 0;
    maxDiscountPercentAllowed = 100;
  }
}
