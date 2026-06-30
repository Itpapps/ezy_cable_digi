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

  // ── Drawer and Dashboard dynamic fields (Android: LoginActivity static fields) ──
  String username = '';
  String employeeName = '';
  String lastLogin = '';
  String businessName = '';

  // Discount config from the login response (Android LoginActivity statics).
  // enable_payment_discount: 1 = discount feature on for this tenant (default 0).
  // max_discount_percent_allowed: the % cap (default 100).
  int enablePaymentDiscount = 0;
  int maxDiscountPercentAllowed = 100;

  // ── Offline-mode fields (from validateLogin response) ──
  // machineNumber: device machine ID used in sync/download requests (11 chars).
  String machineNumber = '';
  // offline_user_code: stored in prefs for offline identity.
  String offlineUserCode = '';
  // offlineStatus: 1 = offline feature enabled for this user.
  int offlineStatus = 0;
  // lovvalue_restrict_partial_payment: 1 = paid amount must be >= total_amount.
  int restrictPartialPayment = 0;
  // Server current_date for discount/penalty date range checks.
  String serverCurrentDate = '';
  // use_crf flag from validateLogin (Android LoginActivity.use_caf). 1 = this
  // dealer uses CRF, so the CRF row is shown in search results / customer details.
  int useCaf = 0;
  // customerAppSearch from validateLogin (Android LoginActivity.customerAppSearch):
  // comma-separated allowed searchType ids (e.g. "1,2,5,6,16"). Drives which
  // options appear in the Search Customer dropdown.
  String customerAppSearch = '';

  // box_wise_service_extension from the validateLogin response ("1" = enabled,
  // default false). Gates the Package Hub's "Service Extension" tile (csews).
  // NOTE: this is the config flag the hub uses — NOT the `service_extension` role
  // permission below. See PACKAGE_OPERATIONS_COMPLETE.md (Service Extension).
  bool boxWiseServiceExtension = false;

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
    bool boxWiseServiceExtension = false,
    String machineNumber = '',
    String offlineUserCode = '',
    int offlineStatus = 0,
    int restrictPartialPayment = 0,
    String serverCurrentDate = '',
    int useCaf = 0,
    String customerAppSearch = '',
    String username = '',
    String employeeName = '',
    String lastLogin = '',
    String businessName = '',
  }) {
    this.authToken = authToken;
    this.dealerId = dealerId;
    this.userType = userType;
    this.employeeId = employeeId;
    this.enablePaymentDiscount = enablePaymentDiscount;
    this.maxDiscountPercentAllowed = maxDiscountPercentAllowed;
    this.boxWiseServiceExtension = boxWiseServiceExtension;
    this.machineNumber = machineNumber;
    this.offlineUserCode = offlineUserCode;
    this.offlineStatus = offlineStatus;
    this.restrictPartialPayment = restrictPartialPayment;
    this.serverCurrentDate = serverCurrentDate;
    this.useCaf = useCaf;
    this.customerAppSearch = customerAppSearch;
    this.username = username;
    this.employeeName = employeeName;
    this.lastLogin = lastLogin;
    this.businessName = businessName;
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
    boxWiseServiceExtension = false;
    packageActivation = false;
    packageDeactivation = false;
    scheduleService = false;
    serviceExtension = false;
    machineNumber = '';
    offlineUserCode = '';
    offlineStatus = 0;
    restrictPartialPayment = 0;
    serverCurrentDate = '';
    useCaf = 0;
    customerAppSearch = '';
    username = '';
    employeeName = '';
    lastLogin = '';
    businessName = '';
  }
}
