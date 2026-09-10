import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/constants/app_colors.dart';

class StaticContentScreen extends StatelessWidget {
  final String title;
  final String body;
  final bool hideAppBar;

  const StaticContentScreen({
    super.key,
    required this.title,
    required this.body,
    this.hideAppBar = false,
  });

  @override
  Widget build(BuildContext context) {
    final textWidget = SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: SizedBox(
        width: double.infinity,
        child: Text(
          body,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 15,
            height: 1.5,
            color: AppColors.textPrimary,
          ),
        ),
      ),
    );

    if (hideAppBar) {
      return Container(
        color: Colors.white,
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              color: AppColors.primary.withValues(alpha: 0.08),
              alignment: Alignment.center,
              child: Text(
                title.toUpperCase(),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: AppColors.primary,
                ),
              ),
            ),
            Expanded(child: textWidget),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: textWidget,
    );
  }
}

const String kDummyAboutUs = '''
 Application: Digi.

 Company: ITP Software India Pvt Ltd.

 About App:
  Digi offers complete customer relationship management solution to local cable operators by keeping track of their customer's profile,  Make Payments and print or share a receipt, complaints Management or any customer queries which can be resolved through your smartphones - anytime and anywhere.

     itpworld.com,  All Rights Reserved
''';

const String kDummyPrivacyPolicy = '''
Privacy Policy (Demo)

We respect your privacy. This demo app stores customer and payment data locally on your device using SQLite for offline operations.

When you use sync features, data may be transmitted to your organization server as configured by your administrator.

Location data is used only for field tracking and customer location updates as enabled in the app.

We do not sell personal data. Contact your LCO for the full privacy policy applicable to your deployment.
''';

class PrivacyPolicyWebView extends StatefulWidget {
  const PrivacyPolicyWebView({super.key});

  @override
  State<PrivacyPolicyWebView> createState() => _PrivacyPolicyWebViewState();
}

class _PrivacyPolicyWebViewState extends State<PrivacyPolicyWebView> {
  late final WebViewController _controller;
  bool _loading = true;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (url) {
            if (mounted) setState(() { _loading = true; _hasError = false; });
          },
          onPageFinished: (url) {
            if (mounted) setState(() => _loading = false);
          },
          onWebResourceError: (error) {
            debugPrint('WebView error: ${error.errorCode} - ${error.description}');
            if (mounted) setState(() { _loading = false; _hasError = true; });
          },
        ),
      )
      ..loadRequest(Uri.parse(
          'https://www.itpworld.com/news/itp-software-india-pvt-ltd-privacy-policy'));
  }

  void _reload() {
    setState(() { _loading = true; _hasError = false; });
    _controller.reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Privacy Policy'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        actions: [
          if (_hasError)
            IconButton(
              icon: const Icon(Icons.refresh, color: Colors.white),
              onPressed: _reload,
            ),
        ],
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_loading)
            const Center(child: CircularProgressIndicator()),
          if (_hasError && !_loading)
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.wifi_off, size: 54, color: Colors.grey),
                  const SizedBox(height: 12),
                  const Text(
                    'Could not load the Privacy Policy.\nCheck your connection.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey, fontSize: 14),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _reload,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
