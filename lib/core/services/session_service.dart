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
  // send_sms (Android LoginActivity.send_sms): 1 = the payment-SMS checkbox is
  // pre-checked so a receipt SMS is sent by default (default 0 = off/safe).
  int sendSms = 0;

  // CRF prefixes for Search-by-CRF (Android LoginActivity.userCode split on ",").
  // User picks a prefix + types only the last ≤4 digits; full CRF = prefix +
  // digits (SearchCustomer_Fragment_Newdesign:565). Empty → CRF search falls
  // back to a single full-number field (no regression).
  List<String> crfPrefixes = const [];

  // ── Offline-mode fields (from validateLogin response) ──
  // machineNumber: device machine ID used in sync/download requests (11 chars).
  String machineNumber = '';
  // offline_user_code: stored in prefs for offline identity.
  String offlineUserCode = '';
  // offlineStatus: 1 = offline feature enabled for this user.
  int offlineStatus = 0;
  // D-B6: common_employee (validateLogin; Android LoginActivity.common_employee,
  // default 0). 1 = an employee mapped to several dealers → login gate
  // (commonEmpCRF) + the Dealer dropdown on Search and Scan.
  int commonEmployee = 0;
  // lovvalue_restrict_partial_payment: 1 = paid amount must be >= total_amount.
  int restrictPartialPayment = 0;
  // A-B4: amount_round (validateLogin; Android LoginActivity.amount_round,
  // default "ACTUAL"). Values: ACTUAL / ROUND / CEIL.
  String amountRound = 'ACTUAL';
  // A-B5: GST receipt lines (validateLogin; Android LoginActivity :681-694,
  // missing/unparsable → 0). Tax lines show only when isSyncBills == 2 AND
  // gstCount > 0 (DisplayPaymentDetails_Fragment :372 / BluetoothChatService :1087).
  int isSyncBills = 0;
  int gstCount = 0;
  bool get showGstLines => isSyncBills == 2 && gstCount > 0;

  /// A-B4: Android's exact rule (CustomerMgmt_MakePayment_Fragment :1485-1497,
  /// DisplayPaymentDetails_Fragment :299-331): "ACTUAL" keeps the amount,
  /// "ROUND" = Java Math.round (half up), anything else = Math.ceil.
  double applyAmountRound(double v) {
    if (amountRound == 'ACTUAL') return v;
    if (amountRound == 'ROUND') return (v + 0.5).floorToDouble();
    return v.ceilToDouble();
  }
  // useLcoDeposit (Android LoginActivity.userLcoDeposit): 1 = this dealer uses LCO
  // deposit → the STB payment amount is locked to the full pending (no partial)
  // and the dashboard LCO Wallet card is shown. Default 0 = feature off (safe).
  int useLcoDeposit = 0;
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

  // ── Customer Operations grid flags (Android LoginActivity statics) ──────────
  // showCustomPackages ← validateLogin `show_custom_packages` (int 0/1).
  // The rest ← getRolePermissions ("1" = allowed). Default false = feature off,
  // so the grid behaves exactly as today until these are populated.
  bool showCustomPackages = false;        // Custom Packages tile
  bool renew = false;                      // Renew Services / Renew BroadBand
  bool onetimeCharges = false;             // One Time Charges + One Time History
  bool unpaidCustomerDeactivation = false; // Deactivate STB
  bool unpaidCustomerActivation = false;   // Unpaid Customer Activation

  // Payment permission (getRolePermissions `make_payment`). Android BLOCKS Make
  // Payment only when `make_payment=="0"` (CustomerOperations:1724 /
  // UnpaidNewAdapter:107 / UnpaidFrag_Adapter:134) — so this defaults **true**
  // (allow) and is set false only on an explicit "0". Pay Later is NOT gated
  // (Android commented it out).
  bool makePaymentAllowed = true;

  // share_option (getRolePermissions `share_option`). Android hides the Share
  // icon (invoice / one-time history) only on an explicit "0"
  // (OnetimeHistory_Adapter:227, default "1"). Defaults true = show.
  bool shareOption = true;

  // A-B2: customer_discount (getRolePermissions). Android LoginActivity :1083-
  // 1087 defaults "0" and shows the Discount field only when this is "1" AND
  // the dealer's enable_payment_discount is 1. Default false = hidden.
  bool customerDiscount = false;

  // D-B3: expenses (getRolePermissions). Android LoginActivity :1126-1132
  // defaults "0"; Expenses tab → "No Access" and List Expenses hidden unless 1.
  bool addExpense = false;

  bool get isLoggedIn => authToken.isNotEmpty;

  /// Centralized Android payment-permission rule, reused at every payment entry:
  /// blocked for SERVICE users or when `make_payment=="0"`.
  bool get canMakePayment =>
      userType.trim().toUpperCase() != 'SERVICE' && makePaymentAllowed;

  void setFromLogin({
    required String authToken,
    required String dealerId,
    required String userType,
    required String employeeId,
    int enablePaymentDiscount = 0,
    int maxDiscountPercentAllowed = 100,
    int sendSms = 0,
    List<String> crfPrefixes = const [],
    bool boxWiseServiceExtension = false,
    String machineNumber = '',
    String offlineUserCode = '',
    int offlineStatus = 0,
    int commonEmployee = 0,
    int restrictPartialPayment = 0,
    String amountRound = 'ACTUAL',
    int isSyncBills = 0,
    int gstCount = 0,
    int useLcoDeposit = 0,
    String serverCurrentDate = '',
    int useCaf = 0,
    String customerAppSearch = '',
    bool showCustomPackages = false,
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
    this.sendSms = sendSms;
    this.crfPrefixes = crfPrefixes;
    this.boxWiseServiceExtension = boxWiseServiceExtension;
    this.machineNumber = machineNumber;
    this.offlineUserCode = offlineUserCode;
    this.offlineStatus = offlineStatus;
    this.commonEmployee = commonEmployee;
    this.restrictPartialPayment = restrictPartialPayment;
    this.amountRound = amountRound;
    this.isSyncBills = isSyncBills;
    this.gstCount = gstCount;
    this.useLcoDeposit = useLcoDeposit;
    this.serverCurrentDate = serverCurrentDate;
    this.useCaf = useCaf;
    this.customerAppSearch = customerAppSearch;
    this.showCustomPackages = showCustomPackages;
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
    bool renew = false,
    bool onetimeCharges = false,
    bool unpaidCustomerDeactivation = false,
    bool unpaidCustomerActivation = false,
    bool makePaymentAllowed = true,
    bool shareOption = true,
    bool customerDiscount = false,
    bool addExpense = false,
  }) {
    this.packageActivation = packageActivation;
    this.packageDeactivation = packageDeactivation;
    this.scheduleService = scheduleService;
    this.serviceExtension = serviceExtension;
    this.renew = renew;
    this.onetimeCharges = onetimeCharges;
    this.unpaidCustomerDeactivation = unpaidCustomerDeactivation;
    this.unpaidCustomerActivation = unpaidCustomerActivation;
    this.makePaymentAllowed = makePaymentAllowed;
    this.shareOption = shareOption;
    this.customerDiscount = customerDiscount;
    this.addExpense = addExpense;
  }

  void clear() {
    authToken = '';
    dealerId = '';
    userType = '';
    employeeId = '';
    enablePaymentDiscount = 0;
    maxDiscountPercentAllowed = 100;
    sendSms = 0;
    crfPrefixes = const [];
    boxWiseServiceExtension = false;
    packageActivation = false;
    packageDeactivation = false;
    scheduleService = false;
    serviceExtension = false;
    showCustomPackages = false;
    renew = false;
    onetimeCharges = false;
    unpaidCustomerDeactivation = false;
    unpaidCustomerActivation = false;
    makePaymentAllowed = true;
    shareOption = true;
    customerDiscount = false;
    addExpense = false;
    machineNumber = '';
    offlineUserCode = '';
    offlineStatus = 0;
    commonEmployee = 0;
    restrictPartialPayment = 0;
    amountRound = 'ACTUAL';
    isSyncBills = 0;
    gstCount = 0;
    useLcoDeposit = 0;
    serverCurrentDate = '';
    useCaf = 0;
    customerAppSearch = '';
    username = '';
    employeeName = '';
    lastLogin = '';
    businessName = '';
  }
}
