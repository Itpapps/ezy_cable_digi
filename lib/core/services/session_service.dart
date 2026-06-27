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

  // ── Package-operation role permissions (from getRolePermissions, key `grp`) ──
  // Each is the `{name}.permission` flag ("1" = allowed). Loaded ONCE after login
  // (session-only; never refreshed). Default **false = deny** if missing/failed —
  // the Package Hub shows/hides actions on these. See PACKAGE_OPERATIONS_COMPLETE.md §1.5.
  bool packageActivation = false;   // Add Services
  bool packageDeactivation = false; // Remove Services
  bool scheduleService = false;     // Schedule Services
  bool serviceExtension = false;    // Service Extension

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

  /// Package-operation permissions from `getRolePermissions` (after login).
  /// Defaults stay false (deny) when the call fails or a flag is missing.
  void setRolePermissions({
    bool packageActivation = false,
    bool packageDeactivation = false,
    bool scheduleService = false,
    bool serviceExtension = false,
  }) {
    this.packageActivation = packageActivation;
    this.packageDeactivation = packageDeactivation;
    this.scheduleService = scheduleService;
    this.serviceExtension = serviceExtension;
  }

  void clear() {
    authToken = '';
    dealerId = '';
    userType = '';
    employeeId = '';
    enablePaymentDiscount = 0;
    maxDiscountPercentAllowed = 100;
    packageActivation = false;
    packageDeactivation = false;
    scheduleService = false;
    serviceExtension = false;
  }
}
