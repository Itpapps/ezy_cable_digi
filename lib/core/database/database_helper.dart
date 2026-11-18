import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../data/customer.dart';
import '../data/collection_schedule.dart';
import '../data/offline_customer.dart';
import '../data/payment.dart';
import '../utils/money_parser.dart';

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  static Database? _database;

  DatabaseHelper._internal();

  factory DatabaseHelper() => _instance;

  // Method to reset database if needed
  Future<void> resetDatabase() async {
    try {
      print('DatabaseHelper: Resetting database...');
      final db = await database;
      await db.delete('payments');
      await db.delete('customers');
      print('DatabaseHelper: Database reset completed');
    } catch (e) {
      print('DatabaseHelper: Error resetting database: $e');
      rethrow;
    }
  }

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    String path = join(await getDatabasesPath(), 'ezy_cable_digi.db');
    return await openDatabase(
      path,
      version: 7,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    try {
      print('DatabaseHelper: Creating customers table...');
      await db.execute('''
        CREATE TABLE customers (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          altCustomerId TEXT NOT NULL,
          name TEXT NOT NULL,
          primaryMobileNumber TEXT,
          lcoCustomerId TEXT,
          crfNumber TEXT,
          serialNumber TEXT,
          vcNumber TEXT,
          nickName TEXT,
          secondaryMobileNumber TEXT,
          pendingAmount TEXT,
          lastPaidDate TEXT,
          customerType TEXT,
          broadbandUserId TEXT,
          address TEXT,
          groupName TEXT,
          areaName TEXT,
          totalDue TEXT,
          amountPayable TEXT,
          billMonth TEXT,
          boxNumber TEXT,
          latitude REAL,
          longitude REAL
        )
      ''');
      print('DatabaseHelper: Customers table created successfully');

      print('DatabaseHelper: Creating payments table...');
      await db.execute('''
        CREATE TABLE payments (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          customerId TEXT NOT NULL,
          customerName TEXT NOT NULL,
          customerMobile TEXT,
          amount REAL NOT NULL,
          paymentMethod TEXT NOT NULL,
          paymentDate TEXT NOT NULL,
          transactionId TEXT NOT NULL,
          status TEXT NOT NULL,
          receiptPath TEXT,
          smsSent INTEGER NOT NULL DEFAULT 0,
          chequeNo TEXT,
          bankName TEXT,
          branch TEXT,
          instrumentDate TEXT,
          synced INTEGER NOT NULL DEFAULT 1
        )
      ''');
      print('DatabaseHelper: Payments table created successfully');

      print('DatabaseHelper: Creating collection_schedules table...');
      await db.execute('''
        CREATE TABLE collection_schedules (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          customerId TEXT NOT NULL,
          customerName TEXT NOT NULL,
          accountNumber TEXT,
          employee TEXT,
          status TEXT NOT NULL,
          scheduleDate TEXT NOT NULL,
          remarks TEXT,
          createdAt TEXT NOT NULL
        )
      ''');
      print('DatabaseHelper: Collection schedules table created successfully');
      
      await _createOfflineTables(db);
      print('DatabaseHelper: All tables created successfully');
    } catch (e) {
      print('DatabaseHelper: Error creating tables: $e');
      print('DatabaseHelper: Stack trace: ${StackTrace.current}');
      rethrow;
    }
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    print('DatabaseHelper: Upgrading database from version $oldVersion to $newVersion');
    try {
      if (oldVersion < 2) {
        print('DatabaseHelper: Creating payments table for version 2...');
        await db.execute('''
          CREATE TABLE payments (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            customerId TEXT NOT NULL,
            customerName TEXT NOT NULL,
            customerMobile TEXT,
            amount REAL NOT NULL,
            paymentMethod TEXT NOT NULL,
            paymentDate TEXT NOT NULL,
            transactionId TEXT NOT NULL,
            status TEXT NOT NULL,
            receiptPath TEXT,
            smsSent INTEGER NOT NULL DEFAULT 0
          )
        ''');
        print('DatabaseHelper: Payments table created in upgrade');
      }
      if (oldVersion < 3) {
        await db.execute('ALTER TABLE customers ADD COLUMN latitude REAL');
        await db.execute('ALTER TABLE customers ADD COLUMN longitude REAL');
      }
      if (oldVersion < 4) {
        await db.execute('ALTER TABLE payments ADD COLUMN chequeNo TEXT');
        await db.execute('ALTER TABLE payments ADD COLUMN bankName TEXT');
        await db.execute('ALTER TABLE payments ADD COLUMN branch TEXT');
        await db.execute('ALTER TABLE payments ADD COLUMN instrumentDate TEXT');
        await db.execute(
            'ALTER TABLE payments ADD COLUMN synced INTEGER NOT NULL DEFAULT 1');
      }
      if (oldVersion < 5) {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS collection_schedules (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            customerId TEXT NOT NULL,
            customerName TEXT NOT NULL,
            accountNumber TEXT,
            employee TEXT,
            status TEXT NOT NULL,
            scheduleDate TEXT NOT NULL,
            remarks TEXT,
            createdAt TEXT NOT NULL
          )
        ''');
      }
      if (oldVersion < 6) {
        // customers.broadbandUserId was in Customer.toMap() but never in the
        // schema → any customer insert (offline seed/cache) crashed.
        await db.execute(
            'ALTER TABLE customers ADD COLUMN broadbandUserId TEXT');
      }
      if (oldVersion < 7) {
        await _createOfflineTables(db);
      }
    } catch (e) {
      print('DatabaseHelper: Error upgrading database: $e');
      print('DatabaseHelper: Stack trace: ${StackTrace.current}');
      rethrow;
    }
  }

  Future<int> insertCollectionSchedule(CollectionSchedule schedule) async {
    final db = await database;
    final map = Map<String, dynamic>.from(schedule.toMap());
    map.remove('id');
    return db.insert('collection_schedules', map);
  }

  Future<List<CollectionSchedule>> searchCollectionSchedules({
    required DateTime startDate,
    required DateTime endDate,
    String? employee,
    String? customerName,
    String? accountNumber,
    String? status,
  }) async {
    final db = await database;
    final whereParts = <String>[];
    final args = <Object?>[];

    final start = DateTime(startDate.year, startDate.month, startDate.day);
    final end = DateTime(endDate.year, endDate.month, endDate.day);
    final startStr =
        '${start.year}-${start.month.toString().padLeft(2, '0')}-${start.day.toString().padLeft(2, '0')}';
    final endStr =
        '${end.year}-${end.month.toString().padLeft(2, '0')}-${end.day.toString().padLeft(2, '0')}';

    whereParts.add('scheduleDate >= ?');
    args.add(startStr);
    whereParts.add('scheduleDate <= ?');
    args.add(endStr);

    if (employee != null && employee.trim().isNotEmpty && employee != 'Choose') {
      whereParts.add('employee = ?');
      args.add(employee.trim());
    }
    if (status != null && status.trim().isNotEmpty && status != 'Choose') {
      whereParts.add('status = ?');
      args.add(status.trim());
    }
    if (customerName != null && customerName.trim().isNotEmpty) {
      whereParts.add('customerName LIKE ?');
      args.add('%${customerName.trim()}%');
    }
    if (accountNumber != null && accountNumber.trim().isNotEmpty) {
      whereParts.add('accountNumber LIKE ?');
      args.add('%${accountNumber.trim()}%');
    }

    final maps = await db.query(
      'collection_schedules',
      where: whereParts.isEmpty ? null : whereParts.join(' AND '),
      whereArgs: args,
      orderBy: 'scheduleDate DESC, id DESC',
    );
    return maps.map(CollectionSchedule.fromMap).toList();
  }

  Future<int> insertCustomer(Customer customer) async {
    final db = await database;
    return await db.insert(
      'customers',
      customer.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Customer>> searchCustomers(String criteria, String query) async {
    final db = await database;
    String columnName;
    
    switch (criteria) {
      case 'Alt Customer Id':
        columnName = 'altCustomerId';
        break;
      case 'Name':
        columnName = 'name';
        break;
      case 'Primary Mobile Number':
        columnName = 'primaryMobileNumber';
        break;
      case 'Lco Customer Id':
      case 'Lco  Customer Id':
        columnName = 'lcoCustomerId';
        break;
      case 'CRF Number':
        columnName = 'crfNumber';
        break;
      case 'Serial Number':
        columnName = 'serialNumber';
        break;
      case 'VC Number':
        columnName = 'vcNumber';
        break;
      case 'NickName':
        columnName = 'nickName';
        break;
      case 'Secondary Mobile Number':
        columnName = 'secondaryMobileNumber';
        break;
      default:
        columnName = 'name';
    }

    final List<Map<String, dynamic>> maps = await db.query(
      'customers',
      where: '$columnName LIKE ?',
      whereArgs: ['%$query%'],
      orderBy: 'name ASC',
    );

    return List.generate(maps.length, (i) {
      return Customer.fromMap(maps[i]);
    });
  }

  Future<Customer?> getCustomerById(int id) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'customers',
      where: 'id = ?',
      whereArgs: [id],
    );

    if (maps.isNotEmpty) {
      return Customer.fromMap(maps.first);
    }
    return null;
  }

  Future<Customer?> getCustomerByLcoId(String lcoCustomerId) async {
    final db = await database;
    final maps = await db.query(
      'customers',
      where: 'lcoCustomerId = ?',
      whereArgs: [lcoCustomerId],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return Customer.fromMap(maps.first);
  }

  Future<int> updateCustomerLocation({
    required String lcoCustomerId,
    required String areaName,
    required double latitude,
    required double longitude,
  }) async {
    final db = await database;
    return db.update(
      'customers',
      {
        'areaName': areaName,
        'latitude': latitude,
        'longitude': longitude,
      },
      where: 'lcoCustomerId = ?',
      whereArgs: [lcoCustomerId],
    );
  }

  Future<List<Customer>> getCustomersWithLocation() async {
    final db = await database;
    final maps = await db.query(
      'customers',
      where: 'latitude IS NOT NULL AND longitude IS NOT NULL',
      orderBy: 'name ASC',
    );
    return maps.map(Customer.fromMap).toList();
  }

  Future<int> insertPayment(Payment payment) async {
    try {
      print('DatabaseHelper: Inserting payment...');
      print('DatabaseHelper: Payment data: ${payment.toMap()}');
      
      final db = await database;
      print('DatabaseHelper: Got database instance');
      
      // Check if payments table exists
      final tables = await db.rawQuery("SELECT name FROM sqlite_master WHERE type='table' AND name='payments'");
      print('DatabaseHelper: Tables found: $tables');
      
      if (tables.isEmpty) {
        print('DatabaseHelper: Payments table does not exist, creating it...');
        await db.execute('''
          CREATE TABLE payments (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            customerId TEXT NOT NULL,
            customerName TEXT NOT NULL,
            customerMobile TEXT,
            amount REAL NOT NULL,
            paymentMethod TEXT NOT NULL,
            paymentDate TEXT NOT NULL,
            transactionId TEXT NOT NULL,
            status TEXT NOT NULL,
            receiptPath TEXT,
            smsSent INTEGER NOT NULL DEFAULT 0,
            chequeNo TEXT,
            bankName TEXT,
            branch TEXT,
            instrumentDate TEXT,
            synced INTEGER NOT NULL DEFAULT 1
          )
        ''');
        print('DatabaseHelper: Payments table created manually');
      }
      
      final map = Map<String, dynamic>.from(payment.toMap());
      map.remove('id');
      final result = await db.insert('payments', map);
      print('DatabaseHelper: Insert result: $result');
      
      if (result <= 0) {
        print('DatabaseHelper: ERROR - Insert failed, result: $result');
        throw Exception('Failed to insert payment - database returned $result');
      }
      
      print('DatabaseHelper: Payment inserted successfully with ID: $result');
      return result;
    } catch (e) {
      print('DatabaseHelper: Error inserting payment: $e');
      print('DatabaseHelper: Stack trace: ${StackTrace.current}');
      rethrow;
    }
  }

  Future<List<Payment>> getPaymentsByCustomerId(String customerId) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'payments',
      where: 'customerId = ?',
      whereArgs: [customerId],
      orderBy: 'paymentDate DESC',
    );

    return List.generate(maps.length, (i) {
      return Payment.fromMap(maps[i]);
    });
  }

  Future<String> generateTransactionId() async {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final random = DateTime.now().second.toString().padLeft(2, '0');
    return 'TXN$timestamp$random';
  }

  Future<int> getCurrentMonthPaymentCount(String customerId) async {
    final db = await database;
    final now = DateTime.now();
    final firstDayOfMonth = DateTime(now.year, now.month, 1);
    final lastDayOfMonth = DateTime(now.year, now.month + 1, 0);

    final List<Map<String, dynamic>> maps = await db.query(
      'payments',
      where: 'customerId = ? AND paymentDate >= ? AND paymentDate <= ?',
      whereArgs: [
        customerId,
        firstDayOfMonth.toIso8601String(),
        lastDayOfMonth.toIso8601String(),
      ],
    );

    return maps.length;
  }

  Future<int> getCustomerCount() async {
    final db = await database;
    return Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM customers'),
        ) ??
        0;
  }

  /// Customers with pending or payable amount &gt; 0 (offline unpaid list).
  Future<List<Customer>> getUnpaidCustomers({
    bool onlyCurrentMonth = false,
  }) async {
    final db = await database;
    final maps = await db.query('customers', orderBy: 'name ASC');
    final now = DateTime.now();

    return maps.map(Customer.fromMap).where((c) {
      if (!isUnpaidCustomer(
        amountPayable: c.amountPayable,
        pendingAmount: c.pendingAmount,
      )) {
        return false;
      }
      if (onlyCurrentMonth) {
        final bm = c.billMonth;
        final y = '${now.year}';
        final m = now.month.toString().padLeft(2, '0');
        if (bm.contains(y) && bm.contains(m)) return true;
        final lp = c.lastPaidDate.trim();
        if (lp.isEmpty) return true;
        return lp.contains('$m-$y') || lp.contains('$y');
      }
      return true;
    }).toList();
  }

  Future<int> countUnsyncedPayments() async {
    final db = await database;
    return Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM payments WHERE synced = 0'),
        ) ??
        0;
  }

  Future<int> markAllPaymentsSynced() async {
    final db = await database;
    return db.update('payments', {'synced': 1}, where: 'synced = ?', whereArgs: [0]);
  }

  /// Today completed payments: cash/bank STB-style summary for miniday report.
  Future<Map<String, dynamic>> getTodayCollectionSummary() async {
    final db = await database;
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day).toIso8601String();
    final end = DateTime(now.year, now.month, now.day, 23, 59, 59, 999)
        .toIso8601String();

    final maps = await db.query(
      'payments',
      where: 'paymentDate >= ? AND paymentDate <= ? AND status = ?',
      whereArgs: [start, end, 'completed'],
    );

    var cashCount = 0;
    var bankCount = 0;
    var cashAmount = 0.0;
    var bankAmount = 0.0;

    for (final m in maps) {
      final method = (m['paymentMethod'] as String? ?? '').toLowerCase();
      final amt = (m['amount'] as num?)?.toDouble() ?? 0;
      if (method == 'cash') {
        cashCount++;
        cashAmount += amt;
      } else {
        bankCount++;
        bankAmount += amt;
      }
    }

    return {
      'cashCount': cashCount,
      'bankCount': bankCount,
      'cashAmount': cashAmount,
      'bankAmount': bankAmount,
      'totalAmount': cashAmount + bankAmount,
    };
  }

  Future<int> countPaymentsToday() async {
    final s = await getTodayCollectionSummary();
    return (s['cashCount'] as int) + (s['bankCount'] as int);
  }

  Future<List<Payment>> getPaymentsTodayList() async {
    final db = await database;
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day).toIso8601String();
    final end = DateTime(now.year, now.month, now.day, 23, 59, 59, 999)
        .toIso8601String();
    final maps = await db.query(
      'payments',
      where: 'paymentDate >= ? AND paymentDate <= ? AND status = ?',
      whereArgs: [start, end, 'completed'],
      orderBy: 'paymentDate DESC',
    );
    return maps.map(Payment.fromMap).toList();
  }
  Future<List<Customer>> getCustomersPaginated({
  int limit = 20,
  int offset = 0,
}) async {
  final db = await database;

  final maps = await db.query(
    'customers',
    orderBy: 'name ASC',
    limit: limit,
    offset: offset,
  );

  return maps.map((e) => Customer.fromMap(e)).toList();
}
Future<List<Customer>> getFilteredCustomersPaginated({
  int limit = 20,
  int offset = 0,
  String? customerType,
  String? group,
}) async {
  final db = await database;

  List<String> whereClauses = [];
  List<dynamic> whereArgs = [];

  if (customerType != null && customerType != 'Total Unpaid List') {
    if (customerType == 'Active Customers') {
      whereClauses.add("amountPayable = ?");
      whereArgs.add('₹0');
    } else if (customerType == 'Inactive Customers') {
      whereClauses.add("amountPayable != ?");
      whereArgs.add('₹0');
    }
  }

  if (group != null && group != 'Select') {
    whereClauses.add("groupName = ?");
    whereArgs.add(group);
  }

  final maps = await db.query(
    'customers',
    where: whereClauses.isEmpty ? null : whereClauses.join(" AND "),
    whereArgs: whereArgs,
    orderBy: 'name ASC',
    limit: limit,
    offset: offset,
  );

  return maps.map((e) => Customer.fromMap(e)).toList();
}

  // ═══════════════════════════════════════════════════════════════════════════
  // OFFLINE TABLES (Android parity: offline_data_4 + offliendataafter_pay)
  // ═══════════════════════════════════════════════════════════════════════════

  static const _tblOfflineCustomers = 'offline_customers';
  static const _tblOfflinePayments = 'offline_payments';

  Future<void> _createOfflineTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_tblOfflineCustomers (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        lcoCrfNo TEXT,
        accountNum TEXT,
        name TEXT,
        address TEXT,
        billAmount TEXT,
        taxAmount TEXT,
        pendingAmount TEXT,
        totalAmount TEXT,
        amount TEXT,
        month TEXT,
        mobileNum TEXT,
        lastPaidAmount TEXT,
        lastPaidDate TEXT,
        businessName TEXT,
        customerId TEXT,
        crfNumber TEXT,
        lcoCustId TEXT,
        paymentFlag TEXT,
        flag INTEGER DEFAULT 0,
        paymentDate TEXT,
        syncPaymentDate TEXT,
        chequeNumber TEXT,
        bankName TEXT,
        branchName TEXT,
        insDate TEXT,
        sendSms TEXT,
        payMode TEXT,
        discountAmount TEXT,
        totalAfterDiscount TEXT,
        discountStartDate TEXT,
        discountEndDate TEXT,
        penaltyAmount TEXT,
        totalAfterPenalty TEXT,
        penaltyStartDate TEXT,
        penaltyEndDate TEXT,
        discountPenaltyFlag TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_tblOfflinePayments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        lcoCrfNo TEXT,
        accountNum TEXT,
        name TEXT,
        address TEXT,
        billAmount TEXT,
        taxAmount TEXT,
        pendingAmount TEXT,
        totalAmount TEXT,
        amount TEXT,
        month TEXT,
        mobileNum TEXT,
        lastPaidAmount TEXT,
        lastPaidDate TEXT,
        businessName TEXT,
        customerId TEXT,
        crfNumber TEXT,
        lcoCustId TEXT,
        paymentFlag TEXT,
        flag INTEGER DEFAULT 1,
        paymentDate TEXT,
        syncPaymentDate TEXT,
        chequeNumber TEXT,
        bankName TEXT,
        branchName TEXT,
        insDate TEXT,
        sendSms TEXT,
        payMode TEXT,
        discountAmount TEXT,
        totalAfterDiscount TEXT,
        discountStartDate TEXT,
        discountEndDate TEXT,
        penaltyAmount TEXT,
        totalAfterPenalty TEXT,
        penaltyStartDate TEXT,
        penaltyEndDate TEXT,
        discountPenaltyFlag TEXT
      )
    ''');
  }

  // ── INSERT downloaded customer ──
  Future<int> insertOfflineCustomer(OfflineCustomer c) async {
    final db = await database;
    final map = c.toMap();
    map.remove('id');
    return db.insert(_tblOfflineCustomers, map);
  }

  // ── ATOMIC replace: delete all offline data + insert new customers ──
  Future<int> replaceAllOfflineCustomers(List<OfflineCustomer> customers) async {
    final db = await database;
    int inserted = 0;
    await db.transaction((txn) async {
      await txn.delete(_tblOfflineCustomers);
      await txn.delete(_tblOfflinePayments);
      for (final c in customers) {
        final map = c.toMap();
        map.remove('id');
        await txn.insert(_tblOfflineCustomers, map);
        inserted++;
      }
    });
    return inserted;
  }

  // ── INSERT payment queue record ──
  Future<int> insertOfflinePayment(OfflineCustomer c) async {
    final db = await database;
    final map = c.toMap();
    map.remove('id');
    return db.insert(_tblOfflinePayments, map);
  }

  // ── GET all offline customers ──
  Future<List<OfflineCustomer>> getAllOfflineCustomers() async {
    final db = await database;
    final maps = await db.query(_tblOfflineCustomers, orderBy: 'name ASC');
    return maps.map(OfflineCustomer.fromMap).toList();
  }

  // ── GET unpaid offline customers (flag=0) ──
  // Android `Offline_unPaidCustomer_Fragment` "Only Current Month" tri-state:
  //   null  → all unpaid (initial load, :120-126)
  //   true  → current month  (payment_flag == "000")        (checkbox checked)
  //   false → non-current month (payment_flag != "000")     (checkbox unchecked, :300-306)
  Future<List<OfflineCustomer>> getUnpaidOfflineCustomers({
    bool? currentMonthOnly,
  }) async {
    final db = await database;
    String where = 'flag = 0';
    if (currentMonthOnly == true) {
      where += " AND paymentFlag = '000'";
    } else if (currentMonthOnly == false) {
      where += " AND (paymentFlag IS NULL OR paymentFlag != '000')";
    }
    final maps = await db.query(_tblOfflineCustomers,
        where: where, orderBy: 'name ASC');
    return maps.map(OfflineCustomer.fromMap).toList();
  }

  // ── GET payments by flag (from offline_payments queue) ──
  Future<List<OfflineCustomer>> getOfflinePaymentsByFlag(int f) async {
    final db = await database;
    final maps = await db.query(_tblOfflinePayments,
        where: 'flag = ?', whereArgs: [f], orderBy: 'id DESC');
    return maps.map(OfflineCustomer.fromMap).toList();
  }

  // ── GET all paid+synced from payment queue ──
  Future<List<OfflineCustomer>> getAllPaidSyncOfflinePayments() async {
    final db = await database;
    final maps = await db.query(_tblOfflinePayments,
        where: 'flag IN (1, 2)', orderBy: 'id DESC');
    return maps.map(OfflineCustomer.fromMap).toList();
  }

  // ── GET today's payments from payment queue ──
  Future<List<OfflineCustomer>> getTodayOfflinePayments(String todayDate) async {
    final db = await database;
    // B-A1 / Android DB_Helper :927: only paid (1) and synced (2) rows count.
    final maps = await db.query(_tblOfflinePayments,
        where: "flag IN (1, 2) AND paymentDate LIKE ?",
        whereArgs: ['$todayDate%'],
        orderBy: 'id DESC');
    return maps.map(OfflineCustomer.fromMap).toList();
  }

  // ── GET payments between dates (offline Collections report) ──
  // Android parity: DB_Helper.getAllBetweenDates queries the pay-queue table by
  // `last_paid_date BETWEEN start AND end` (dates as "dd-MM-yyyy"). Mirrors that
  // exactly — lastPaidDate is stored as "dd-MM-yyyy" at commit.
  Future<List<OfflineCustomer>> getOfflinePaymentsBetweenDates(
      String startDate, String endDate) async {
    final db = await database;
    final maps = await db.query(_tblOfflinePayments,
        where: "lastPaidDate BETWEEN ? AND ?",
        whereArgs: [startDate, endDate],
        orderBy: 'id DESC');
    return maps.map(OfflineCustomer.fromMap).toList();
  }

  // ── SEARCH offline customers by name (LIKE) ──
  // Android DB_Helper.getAllspecificContactsByName :360 (`name like 'x%'`):
  // names that START with the typed text, not names that merely contain it.
  Future<List<OfflineCustomer>> searchOfflineByName(String query) async {
    final db = await database;
    final maps = await db.query(_tblOfflineCustomers,
        where: "name LIKE ?", whereArgs: ['$query%'], orderBy: 'name ASC');
    return maps.map(OfflineCustomer.fromMap).toList();
  }

  // ── SEARCH offline customers by CRF (exact, NOCASE) ──
  Future<List<OfflineCustomer>> searchOfflineByCrf(String query) async {
    final db = await database;
    final maps = await db.query(_tblOfflineCustomers,
        where: "crfNumber = ? COLLATE NOCASE", whereArgs: [query]);
    return maps.map(OfflineCustomer.fromMap).toList();
  }

  // ── SEARCH offline customers by LCO ID (exact, NOCASE) ──
  Future<List<OfflineCustomer>> searchOfflineByLcoId(String query) async {
    final db = await database;
    final maps = await db.query(_tblOfflineCustomers,
        where: "lcoCustId = ? COLLATE NOCASE", whereArgs: [query]);
    return maps.map(OfflineCustomer.fromMap).toList();
  }

  // ── SEARCH offline customers by mobile (LIKE) ──
  Future<List<OfflineCustomer>> searchOfflineByMobile(String query) async {
    final db = await database;
    final maps = await db.query(_tblOfflineCustomers,
        where: "mobileNum LIKE ?", whereArgs: ['%$query%']);
    return maps.map(OfflineCustomer.fromMap).toList();
  }

  // ── GET single by customerId ──
  Future<OfflineCustomer?> getOfflineCustomerById(String custId) async {
    final db = await database;
    final maps = await db.query(_tblOfflineCustomers,
        where: "customerId = ?", whereArgs: [custId], limit: 1);
    if (maps.isEmpty) return null;
    return OfflineCustomer.fromMap(maps.first);
  }

  // ── UPDATE offline_customers after payment (set flag, amount, date) ──
  Future<int> updateOfflineCustomerAfterPayment(OfflineCustomer c) async {
    final db = await database;
    return db.update(
      _tblOfflineCustomers,
      {
        'flag': c.flag,
        'amount': c.amount,
        'paymentDate': c.paymentDate,
        'lastPaidDate': c.lastPaidDate,
        'lastPaidAmount': c.lastPaidAmount,
        'chequeNumber': c.chequeNumber,
        'bankName': c.bankName,
        'branchName': c.branchName,
        'insDate': c.insDate,
        'sendSms': c.sendSms,
        'payMode': c.payMode,
        'discountPenaltyFlag': c.discountPenaltyFlag,
        'syncPaymentDate': c.syncPaymentDate,
      },
      where: 'customerId = ?',
      whereArgs: [c.customerId],
    );
  }

  // ── UPDATE offline_payments queue (match by customerId AND paymentDate) ──
  Future<int> updateOfflinePaymentAfterSync(OfflineCustomer c) async {
    final db = await database;
    return db.update(
      _tblOfflinePayments,
      {'flag': c.flag, 'syncPaymentDate': c.syncPaymentDate},
      where: 'customerId = ? AND paymentDate = ?',
      whereArgs: [c.customerId, c.paymentDate],
    );
  }

  // ── UPDATE outstanding/total amount on offline_customers ──
  Future<int> updateOfflineCustomerOutstanding(
      String customerId, String newTotalAmount) async {
    final db = await database;
    return db.update(
      _tblOfflineCustomers,
      {'totalAmount': newTotalAmount},
      where: 'customerId = ?',
      whereArgs: [customerId],
    );
  }

  // ── COUNT offline customers ──
  Future<int> getOfflineCustomerCount() async {
    final db = await database;
    return Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM $_tblOfflineCustomers'),
        ) ??
        0;
  }

  // ── COUNT paid (flag=1) in payment queue ──
  Future<int> getOfflinePaidCount() async {
    final db = await database;
    return Sqflite.firstIntValue(
          await db.rawQuery(
              'SELECT COUNT(*) FROM $_tblOfflinePayments WHERE flag = 1'),
        ) ??
        0;
  }

  // ── COUNT synced (flag=2) in payment queue ──
  Future<int> getOfflineSyncedCount() async {
    final db = await database;
    return Sqflite.firstIntValue(
          await db.rawQuery(
              'SELECT COUNT(*) FROM $_tblOfflinePayments WHERE flag = 2'),
        ) ??
        0;
  }

  // ── DELETE ALL offline data (both tables) ──
  Future<void> deleteAllOfflineData() async {
    final db = await database;
    await db.delete(_tblOfflineCustomers);
    await db.delete(_tblOfflinePayments);
  }

  // ── Offline collection summary for today ──
  Future<Map<String, dynamic>> getOfflineTodaySummary(String todayDate) async {
    final payments = await getTodayOfflinePayments(todayDate);
    var cashCount = 0;
    var bankCount = 0;
    var cashAmount = 0.0;
    var bankAmount = 0.0;
    for (final p in payments) {
      final amt = double.tryParse(p.amount) ?? 0;
      if (p.payMode == 'R') {
        cashCount++;
        cashAmount += amt;
      } else {
        bankCount++;
        bankAmount += amt;
      }
    }
    return {
      'cashCount': cashCount,
      'bankCount': bankCount,
      'cashAmount': cashAmount,
      'bankAmount': bankAmount,
      'totalAmount': cashAmount + bankAmount,
      'totalCount': cashCount + bankCount,
    };
  }
}
