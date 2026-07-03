import '../../../core/config/app_config.dart';
import '../../../core/data/customer.dart';
import '../../../core/network/server_url_resolver.dart';
import '../../../core/network/soap_client.dart';
import '../../../core/services/session_service.dart';

/// Result of a Customer Search (`sc`) call.
class SearchResult {
  final int statusCode; // 0 = ok · non-zero = no records / error
  final String statusMessage;
  final List<Customer> customers;
  const SearchResult(this.statusCode, this.statusMessage, this.customers);
}

/// Result of a Prev/Next customer navigation (`prenext`).
class PrevNextResult {
  final int statusCode; // 0 ok · 1 no records · 2 server · 3 transport
  final String statusMessage;
  final Customer? customer; // the next/prev customer (non-null only on status 0)
  final int useAltCustomerId; // response flag Android reads for later ops
  const PrevNextResult(this.statusCode, this.statusMessage, this.customer,
      [this.useAltCustomerId = 0]);
}

/// Customer Search (config key `sc`).
///
/// Android: `SearchCustomer_Fragment_Newdesign` SOAP `searchCustomer`, wrapper
/// element `custInfo` with `i:type="searchCustomerInfo"`. Response repeats
/// `<searchCustomerList>` items. Field names are confirmed from the first real
/// response via the temporary [SC] logs.
class SearchRepository {
  SearchRepository._();
  static final SearchRepository instance = SearchRepository._();

  static String get _imei => AppConfig.deviceImei;

  Future<SearchResult> search({
    required int searchType,
    required String value,
    int isList = 0, // Android custInfo.is_list (0 = list, 1 = enriched detail)
  }) async {
    final ns = ServerUrlResolver.instance.namespace;

    final xml = await SoapClient.instance.call(
      url: ServerUrlResolver.instance.loginServerUrl,
      namespace: ns,
      soapAction: '$ns/searchCustomer',
      methodName: 'searchCustomer',
      wrapper: 'custInfo',
      wrapperType: 'searchCustomerInfo',
      fields: {
        'authToken': SessionService.instance.authToken,
        'imei': _imei,
        'searchType': searchType,
        'searchValue': value,
        'dealer_id': int.tryParse(SessionService.instance.dealerId) ?? 0,
        'is_list': isList,
      },
    );

    final status =
        int.tryParse(SoapClient.readField(xml, 'statusCode') ?? '') ?? 3;
    final message = SoapClient.readField(xml, 'statusMessage') ?? '';
    if (status != 0) {
      return SearchResult(status, message, const []);
    }

    final blocks = SoapClient.readAll(xml, 'searchCustomerList');
    final customers = blocks.map(_fromBlock).toList();
    return SearchResult(status, message, customers);
  }

  /// Android's second, enriched fetch on selecting a customer
  /// (SearchCustomer_Fragment_Newdesign:644-647): `searchCustomer` with
  /// `is_list=1, searchType=100, searchValue=customer_id`. THIS response carries
  /// `is_show` + `tmp_activation` (the list `is_list=0` response does not), which
  /// drive Renew / Temporary Activation in Customer Operations.
  ///
  /// Returns the (first) enriched [Customer] — Android uses index 0. Returns null
  /// on empty / multiple-with-none / malformed / transport error so the caller can
  /// fall back to the list customer: it NEVER blocks navigation or throws.
  Future<Customer?> fetchCustomerDetail(String customerId) async {
    if (customerId.trim().isEmpty) return null;
    try {
      final r = await search(searchType: 100, value: customerId, isList: 1);
      if (r.statusCode == 0 && r.customers.isNotEmpty) {
        return r.customers.first; // Android takes SearchCustArrayList.get(0)
      }
    } catch (_) {
      // Transport/parse failure → caller keeps the original list customer.
    }
    return null;
  }

  /// Prev/Next customer navigation — Android parity (SOAP `prenext`, config key
  /// `pn`, wrapper `custInfo`/`Next_Prev_searchCustomerInfo`, fields exactly
  /// `authToken, imei, customerId, prevnextflag`). [flag] 1 = next · 2 = prev.
  /// The response `searchCustomerList` is a FULL customer (incl. is_show/
  /// tmp_activation), so no second `searchCustomer(is_list=1)` is needed.
  /// status 0 = ok · 1 = no records · 2 = server · 3 = transport. Never throws.
  Future<PrevNextResult> prevNextCustomer({
    required int customerId,
    required int flag, // 1 = next, 2 = prev
  }) async {
    final ns = ServerUrlResolver.instance.namespace;
    try {
      final xml = await SoapClient.instance.call(
        url: ServerUrlResolver.instance.loginServerUrl,
        namespace: ns,
        soapAction: '$ns/prenext',
        methodName: 'prenext',
        wrapper: 'custInfo',
        wrapperType: 'Next_Prev_searchCustomerInfo',
        fields: {
          'authToken': SessionService.instance.authToken,
          'imei': _imei,
          'customerId': customerId,
          'prevnextflag': flag,
        },
        timeout: const Duration(seconds: 70),
      );
      final status =
          int.tryParse(SoapClient.readField(xml, 'statusCode') ?? '') ?? 3;
      final message = SoapClient.readField(xml, 'statusMessage') ?? '';
      final useAlt =
          int.tryParse(SoapClient.readField(xml, 'useAltCustomerId') ?? '') ?? 0;
      if (status != 0) {
        return PrevNextResult(status, message, null, useAlt);
      }
      // Android reads searchCustomerList[0]; a status-0 with no block is malformed.
      final blocks = SoapClient.readAll(xml, 'searchCustomerList');
      final customer = blocks.isEmpty ? null : _fromBlock(blocks.first);
      return PrevNextResult(status, message, customer, useAlt);
    } on SoapException {
      // Android: null response → statusCode 3, "Server is busy or Un reachable!".
      return const PrevNextResult(3, 'Please try again after sometime', null);
    } catch (_) {
      return const PrevNextResult(3, 'Please try again after sometime', null);
    }
  }

  // Field names confirmed from a real searchCustomer response (see API doc).
  Customer _fromBlock(String b) {
    String f(String tag) => SoapClient.readField(b, tag) ?? '';
    final total = f('total_amount');
    return Customer(
      altCustomerId: f('customnumber'),
      name: f('name'),
      primaryMobileNumber: f('mobile_no'),
      lcoCustomerId: f('customer_id'),
      crfNumber: f('crf'),
      serialNumber: '',
      vcNumber: f('vc_numbers'),
      nickName: '',
      secondaryMobileNumber: '',
      pendingAmount: total.isEmpty ? '₹0' : '₹$total',
      lastPaidDate: f('last_paid_date'),
      customerType: f('customer_type'),
      broadbandUserId: f('broadband_user_id'),
      // Android CustomerOperations grid-state (searchCustomer :2373-2376 +
      // unpaid_customer_activation :978).
      isShow: int.tryParse(f('is_show')) ?? 0,
      tmpActivation: int.tryParse(f('tmp_activation')) ?? 0,
      unpaidAct: int.tryParse(f('unpaid_customer_activation')) ?? 0,
      address: f('address'),
      groupName: f('group_name'),
      areaName: '',
      totalDue: total.isEmpty ? '₹0' : '₹$total',
      amountPayable: f('pending'),
      billMonth: f('bill_month'),
      boxNumber: f('box_numbers'),
      latitude: double.tryParse(f('latitude')),
      longitude: double.tryParse(f('longitude')),
    );
  }
}
