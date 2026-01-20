import 'package:flutter/material.dart';
import 'package:hesen/web_utils.dart'
    if (dart.library.io) 'package:hesen/web_utils_stub.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'package:hesen/firebase_api.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:google_fonts/google_fonts.dart'; // Re-added for fallback
import 'package:hesen/screens/pwa_install_screen.dart'; // PWA Install Screen
import 'package:hesen/services/api_service.dart';
import 'package:hesen/models/match_model.dart';
import 'package:uuid/uuid.dart';
import 'package:curved_navigation_bar/curved_navigation_bar.dart';
import 'package:day_night_switch/day_night_switch.dart';
import 'package:hesen/video_player_screen.dart';
import 'package:hesen/widgets.dart';
import 'dart:async';
import 'package:hesen/privacy_policy_page.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:unity_ads_plugin/unity_ads_plugin.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:hesen/theme_customization_screen.dart';
import 'dart:io';
import 'package:hesen/telegram_dialog.dart';
import 'package:hesen/notification_page.dart';
import 'package:hesen/services/promo_code_service.dart';
import 'package:hesen/services/ad_service.dart';
import 'package:hesen/player_utils/web_player_registry.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

SharedPreferences? prefs;

// ... imports ...

Future<void> main() async {
  runZonedGuarded<Future<void>>(() async {
    WidgetsFlutterBinding.ensureInitialized();

    // REDIRECT LOGS TO CONSOLE OVERLAY REMOVED
    FlutterError.onError = (FlutterErrorDetails details) {
      FlutterError.presentError(details);
      // Only display critical UI error if it's NOT a Firebase init error that we can ignore
      if (details.exception.toString().contains("Firebase") ||
          details.exception.toString().contains("Null check")) {
        debugPrint("Ignored Firebase/Null Warning: ${details.exception}");
      } else {
        debugPrint("FLUTTER ERROR: ${details.exception}");
        _displayError(details.exception, details.stack);
      }
    };

    // Override print removed
    // void log(String msg) => LogConsole.log(msg);
    // debugPrint = ... removed

    // 0. LOAD FONTS FIRST - Prevents "Squares" glitch
    await GoogleFonts.pendingFonts([
      GoogleFonts.cairo(),
    ]);

    // 1. START APP - PRIORITY 1
    runApp(
      ChangeNotifierProvider(
        create: (context) => ThemeProvider(),
        child: const MyApp(),
      ),
    );

    // 1. Remove Web Splash Immediately - PRIORITY 2
    if (kIsWeb) {
      try {
        registerVidstackPlayer();
      } catch (e) {
        debugPrint("Vidstack Reg Error: $e");
      }
    }

    // 2. Load Config & Firebase in Background
    try {
      await dotenv.load(fileName: ".env");
    } catch (e) {
      debugPrint(".env warning (safely ignored).");
    }

    // 2. Remove Web Splash Immediately (Flutter is taking over)
    // 2. Remove Web Splash Immediately (Flutter is taking over)
    if (kIsWeb) {
      debugPrint("Registering Vidstack Player...");
      try {
        registerVidstackPlayer();
      } catch (e) {
        debugPrint("Vidstack Reg Error: $e");
      }
    }

    // 3. Initialize Firebase & Services in Background
    Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    ).then((_) {
      debugPrint("Firebase initialized.");
      // Initialize other services that depend on Firebase
      if (!kIsWeb) {
        try {
          final firebaseApi = FirebaseApi();
          firebaseApi.initNotification();
          UnityAds.init(
            gameId: dotenv.env['UNITY_GAME_ID'] ?? '',
            testMode: false,
            onComplete: () {},
            onFailed: (error, message) {},
          );
        } catch (e) {
          debugPrint("Services init error: $e");
        }
      }
    }).catchError((e) {
      debugPrint("FIREBASE INIT FAILED (IGNORING): $e");
    });
  }, (error, stack) {
    debugPrint("ZONED ERROR: $error");
    if (!error.toString().contains("Firebase") &&
        !error.toString().contains("Null check")) {
      _displayError(error, stack);
    }
  });
}

// Fallback error UI
void _displayError(dynamic error, StackTrace? stack) {
  if (kIsWeb) {
    // Attempt to log to console explicitly for web
    print("CRITICAL WRAPPER ERROR: $error\n$stack");
  }
  runApp(
    MaterialApp(
      home: Scaffold(
        backgroundColor: Colors.red,
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Center(
            child: Text(
              "CRITICAL ERROR:\n$error\n\nSTACK:\n$stack",
              style: const TextStyle(color: Colors.white, fontSize: 16),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    ),
  );
}

// --- Top-level function for background processing ---
Future<Map<String, dynamic>> _processFetchedData(List<dynamic> results) async {
  final List<dynamic> fetchedChannels = (results[0] as List<dynamic>?) ?? [];
  final List<dynamic> fetchedNews = (results[1] as List<dynamic>?) ?? [];
  final List<Match> fetchedMatches = (results[2] as List<Match>?) ?? [];
  final List<dynamic> fetchedGoals = (results[3] as List<dynamic>?) ?? [];

  final uuid = Uuid();

  List<Map<String, dynamic>> sortedCategories = [];
  for (var categoryData in fetchedChannels) {
    if (categoryData is Map) {
      sortedCategories.add(Map<String, dynamic>.from(categoryData));
    }
  }
  sortedCategories.sort((a, b) {
    if (a['createdAt'] == null || b['createdAt'] == null) return 0;
    try {
      final dateA = DateTime.parse(a['createdAt'].toString());
      final dateB = DateTime.parse(b['createdAt'].toString());
      return dateA.compareTo(dateB);
    } catch (e) {
      return a['createdAt'].toString().compareTo(b['createdAt'].toString());
    }
  });

  List<Map<String, dynamic>> processedChannels = [];
  for (var categoryData in sortedCategories) {
    Map<String, dynamic> newCategory = categoryData;
    if (newCategory['id'] == null) {
      newCategory['id'] = uuid.v4();
    }
    if (newCategory['channels'] is List) {
      List originalChannels = newCategory['channels'];
      List<Map<String, dynamic>> sortedChannelsList = [];
      for (var channelData in originalChannels) {
        if (channelData is Map) {
          Map<String, dynamic> newChannel = Map<String, dynamic>.from(
            channelData,
          );
          if (newChannel['id'] == null) {
            newChannel['id'] = uuid.v4();
          }
          sortedChannelsList.add(newChannel);
        }
      }
      sortedChannelsList.sort((a, b) {
        if (a['createdAt'] == null || b['createdAt'] == null) return 0;
        try {
          final dateA = DateTime.parse(a['createdAt'].toString());
          final dateB = DateTime.parse(b['createdAt'].toString());
          return dateA.compareTo(dateB);
        } catch (e) {
          return a['createdAt'].toString().compareTo(
                b['createdAt'].toString(),
              );
        }
      });
      newCategory['channels'] = sortedChannelsList;
    } else {
      newCategory['channels'] = [];
    }
    processedChannels.add(newCategory);
  }

  fetchedNews.sort((a, b) {
    final bool aHasDate = a is Map && a['date'] != null;
    final bool bHasDate = b is Map && b['date'] != null;
    if (!aHasDate && !bHasDate) return 0;
    if (!aHasDate) return 1;
    if (!bHasDate) return -1;
    try {
      final dateA = DateTime.parse(a['date'].toString());
      final dateB = DateTime.parse(b['date'].toString());
      return dateB.compareTo(dateA);
    } catch (e) {
      if (aHasDate && bHasDate) return 0;
      if (aHasDate) return 1;
      if (bHasDate) return -1;
      return 0;
    }
  });

  fetchedGoals.sort((a, b) {
    final bool aHasDate = a is Map && a['createdAt'] != null;
    final bool bHasDate = b is Map && b['createdAt'] != null;
    if (!aHasDate && !bHasDate) return 0;
    if (!aHasDate) return 1;
    if (!bHasDate) return -1;
    try {
      final dateA = DateTime.parse(a['createdAt'].toString());
      final dateB = DateTime.parse(b['createdAt'].toString());
      return dateB.compareTo(dateA);
    } catch (e) {
      if (aHasDate && bHasDate) return 0;
      if (aHasDate) return 1;
      if (bHasDate) return -1;
      return 0;
    }
  });

  return {
    'channels': processedChannels,
    'news': fetchedNews,
    'matches': fetchedMatches,
    'goals': fetchedGoals,
  };
}

// --- New top-level functions for background processing during refresh ---
Future<List<Map<String, dynamic>>> _processRefreshedChannelsData(
    List<dynamic> fetchedChannels) async {
  final uuid = Uuid();
  List<Map<String, dynamic>> sortedCategories = [];
  for (var categoryData in fetchedChannels) {
    if (categoryData is Map) {
      sortedCategories.add(Map<String, dynamic>.from(categoryData));
    }
  }
  sortedCategories.sort((a, b) {
    if (a['createdAt'] == null || b['createdAt'] == null) return 0;
    try {
      final dateA = DateTime.parse(a['createdAt'].toString());
      final dateB = DateTime.parse(b['createdAt'].toString());
      return dateA.compareTo(dateB);
    } catch (e) {
      return a['createdAt'].toString().compareTo(b['createdAt'].toString());
    }
  });

  List<Map<String, dynamic>> processedChannels = [];
  for (var categoryData in sortedCategories) {
    Map<String, dynamic> newCategory = Map<String, dynamic>.from(categoryData);
    if (newCategory['id'] == null) {
      newCategory['id'] = uuid.v4();
    }
    if (newCategory['channels'] is List) {
      List originalChannels = newCategory['channels'];
      List<Map<String, dynamic>> sortedChannelsList = [];
      for (var channelData in originalChannels) {
        if (channelData is Map) {
          Map<String, dynamic> newChannel =
              Map<String, dynamic>.from(channelData);
          if (newChannel['id'] == null) {
            newChannel['id'] = uuid.v4();
          }
          sortedChannelsList.add(newChannel);
        }
      }
      sortedChannelsList.sort((a, b) {
        if (a['createdAt'] == null || b['createdAt'] == null) return 0;
        try {
          final dateA = DateTime.parse(a['createdAt'].toString());
          final dateB = DateTime.parse(b['createdAt'].toString());
          return dateA.compareTo(dateB);
        } catch (e) {
          return a['createdAt'].toString().compareTo(b['createdAt'].toString());
        }
      });
      newCategory['channels'] = sortedChannelsList;
    } else {
      newCategory['channels'] = [];
    }
    processedChannels.add(newCategory);
  }
  return processedChannels;
}

Future<List<dynamic>> _processRefreshedNewsData(
    List<dynamic> fetchedNews) async {
  fetchedNews.sort((a, b) {
    final bool aHasDate = a is Map && a['date'] != null;
    final bool bHasDate = b is Map && b['date'] != null;
    if (!aHasDate && !bHasDate) return 0;
    if (!aHasDate) return 1;
    if (!bHasDate) return -1;
    try {
      final dateA = DateTime.parse(a['date'].toString());
      final dateB = DateTime.parse(b['date'].toString());
      return dateB.compareTo(dateA);
    } catch (e) {
      if (aHasDate && bHasDate) return 0;
      if (aHasDate) return 1;
      if (bHasDate) return -1;
      return 0;
    }
  });
  return fetchedNews;
}

Future<List<dynamic>> _processRefreshedGoalsData(
    List<dynamic> fetchedGoals) async {
  fetchedGoals.sort((a, b) {
    final bool aHasDate = a is Map && a['createdAt'] != null;
    final bool bHasDate = b is Map && b['createdAt'] != null;
    if (!aHasDate && !bHasDate) return 0;
    if (!aHasDate) return 1;
    if (!bHasDate) return -1;
    try {
      final dateA = DateTime.parse(a['createdAt'].toString());
      final dateB = DateTime.parse(b['createdAt'].toString());
      return dateB.compareTo(dateA);
    } catch (e) {
      if (aHasDate && bHasDate) return 0;
      if (aHasDate) return 1;
      if (bHasDate) return -1;
      return 0;
    }
  });
  return fetchedGoals;
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  void initState() {
    super.initState();
    if (!kIsWeb) {}
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);

    return MaterialApp(
      title: 'Hesen TV',
      debugShowCheckedModeBanner: false,
      themeMode: themeProvider.themeMode,
      theme: ThemeData(
        brightness: Brightness.light,
        primaryColor: themeProvider.getPrimaryColor(false),
        scaffoldBackgroundColor: themeProvider.getScaffoldBackgroundColor(
          false,
        ),
        cardColor: themeProvider.getCardColor(false),
        colorScheme: ColorScheme.light(
          primary: themeProvider.getPrimaryColor(false),
          secondary: themeProvider.getSecondaryColor(false),
          surface: Colors.white,
          background: themeProvider.getScaffoldBackgroundColor(false),
          error: Colors.red,
          onPrimary: Colors.white,
          onSecondary: Colors.white,
          onSurface: Colors.black,
          onBackground: Colors.black,
          onError: Colors.white,
          brightness: Brightness.light,
        ),
        appBarTheme: AppBarTheme(
          backgroundColor: themeProvider.getAppBarBackgroundColor(false),
          foregroundColor: Colors.white,
          iconTheme: const IconThemeData(color: Colors.white),
          titleTextStyle: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        textTheme: GoogleFonts.cairoTextTheme(
          const TextTheme(
            bodyLarge: TextStyle(color: Colors.black),
            bodyMedium: TextStyle(color: Colors.black),
            bodySmall: TextStyle(color: Colors.black),
          ),
        ),
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        primaryColor: themeProvider.getPrimaryColor(true),
        scaffoldBackgroundColor: themeProvider.getScaffoldBackgroundColor(true),
        cardColor: themeProvider.getCardColor(true),
        colorScheme: ColorScheme.dark(
          primary: themeProvider.getPrimaryColor(true),
          secondary: themeProvider.getSecondaryColor(true),
          surface: const Color(0xFF1C1C1C),
          background: themeProvider.getScaffoldBackgroundColor(true),
          error: Colors.red,
          onPrimary: Colors.white,
          onSecondary: Colors.white,
          onSurface: Colors.white,
          onBackground: Colors.white,
          onError: Colors.white,
          brightness: Brightness.dark,
        ),
        appBarTheme: AppBarTheme(
          backgroundColor: themeProvider.getAppBarBackgroundColor(true),
          foregroundColor: Colors.white,
          iconTheme: const IconThemeData(color: Colors.white),
          titleTextStyle: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        textTheme: GoogleFonts.cairoTextTheme(
          const TextTheme(
            bodyLarge: TextStyle(color: Colors.white),
            bodyMedium: TextStyle(color: Colors.white),
            bodySmall: TextStyle(color: Colors.white),
          ),
        ),
      ),
      // initialRoute: isPwaStandalone() ? '/home' : '/pwa_install',
      initialRoute: '/home', // BYPASS INSTALL SCREEN: Open as normal site
      routes: {
        '/pwa_install': (context) => const PwaInstallScreen(),
        '/home': (context) => HomePage(
              key: const ValueKey('home'),
              onThemeChanged: (isDarkMode) {
                themeProvider.setThemeMode(
                  isDarkMode ? ThemeMode.dark : ThemeMode.light,
                );
              },
            ),
        '/Notification_screen': (context) => const NotificationPage(),
      },
      navigatorKey: navigatorKey,
    );
  }
}

class HomePage extends StatefulWidget {
  final Function(bool) onThemeChanged;

  const HomePage({super.key, required this.onThemeChanged});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  String? _userName;
  String? _fcmToken;
  List<Match> matches = [];
  List<dynamic> channels = [];
  List<dynamic> news = [];
  List<dynamic> goals = [];
  int _selectedIndex = 0;
  Future<void>? _dataFuture;
  final TextEditingController _searchController = TextEditingController();
  List<dynamic> _filteredChannels = [];
  late bool _isDarkMode;
  bool _isSearchBarVisible = false;
  bool _isLoading = true;
  bool _hasError = false;
  bool _channelsHasError = false;
  bool _newsHasError = false;
  bool _goalsHasError = false;
  bool _matchesHasError = false;

  final String _interstitialPlacementId = 'Interstitial_Android';
  final String _rewardedPlacementId = 'Rewarded_Android';
  bool _isAdShowing = false;

  @override
  void initState() {
    super.initState();
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    _isDarkMode = themeProvider.themeMode == ThemeMode.dark;
    _dataFuture = _initData();
    _initNotifications();
    checkForUpdate().then((_) => _checkAndAskForName());
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<Map<String, dynamic>> _getAdStatus() async {
    final expiryDate = await AdService.getAdFreeExpiry();
    final hasUsedCode = await AdService.hasEverUsedPromoCode();
    return {'expiry': expiryDate, 'hasUsed': hasUsedCode};
  }

  Future<void> _showPromoCodeDialog() async {
    final promoController = TextEditingController();
    bool isProcessing = false;

    return showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('إدخال كود مانع الإعلانات',
                  textAlign: TextAlign.center),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: promoController,
                      autofocus: true,
                      decoration: const InputDecoration(
                        hintText: 'PROMO-CODE',
                        border: OutlineInputBorder(),
                      ),
                      enabled: !isProcessing,
                    ),
                    if (isProcessing)
                      const Padding(
                        padding: EdgeInsets.only(top: 16.0),
                        child: CircularProgressIndicator(),
                      ),
                  ],
                ),
              ),
              actions: <Widget>[
                TextButton(
                  child: const Text('إلغاء'),
                  onPressed:
                      isProcessing ? null : () => Navigator.of(context).pop(),
                ),
                TextButton(
                  child: const Text('تفعيل'),
                  onPressed: isProcessing
                      ? null
                      : () async {
                          if (promoController.text.isEmpty) return;

                          setDialogState(() {
                            isProcessing = true;
                          });

                          String result;
                          try {
                            final promoService = PromoCodeService();
                            result = await promoService
                                .redeemCode(promoController.text);
                          } catch (e) {
                            result =
                                'Error: فشلت العملية. الرجاء التحقق من اتصالك بالإنترنت والمحاولة مرة أخرى.';
                            debugPrint('Error redeeming code: $e');
                          }

                          if (!mounted) return;

                          Navigator.of(context).pop(); // Close the promo dialog

                          // Show result in a new dialog
                          showDialog(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: Text(result.startsWith('Success')
                                  ? 'نجاح'
                                  : 'خطأ'),
                              content: Text(result
                                  .replaceAll('Success: ', '')
                                  .replaceAll('Error: ', '')),
                              actions: [
                                TextButton(
                                  child: const Text('حسناً'),
                                  onPressed: () => Navigator.of(context).pop(),
                                ),
                              ],
                            ),
                          );
                        },
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _initNotifications() async {
    // On Web (especially iOS), requesting token immediately can freeze the app or cause issues.
    // It should be done via user interaction. Disabling auto-init for Web.
    if (kIsWeb) return;

    final firebaseApi = FirebaseApi();
    _fcmToken = await firebaseApi.initNotification();
    if (_userName != null && _userName!.isNotEmpty) {
      _sendDeviceInfoToServer(name: _userName!, token: _fcmToken);
    }
  }

  void _sendDeviceInfoToServer({required String name, required String? token}) {
    if (token == null) {
      print('Cannot send user info to server: FCM token is null.');
      return;
    }
    print('--- SENDING USER INFO TO SERVER (SIMULATION) ---');
    print('User Name: $name');
    print('FCM Token: $token');
    print('-------------------------------------------------');
  }

  Future<void> _checkAndAskForName() async {
    final prefs = await SharedPreferences.getInstance();
    final userName = prefs.getString('user_name');
    if (userName == null || userName.isEmpty) {
      if (mounted) {
        _showNameInputDialog();
      }
    } else {
      if (mounted) {
        setState(() {
          _userName = userName;
        });
        if (_fcmToken != null) {
          _sendDeviceInfoToServer(name: _userName!, token: _fcmToken);
        }
      }
    }
  }

  Future<void> _showNameInputDialog() async {
    final nameController = TextEditingController();
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('مرحباً بك!', textAlign: TextAlign.center),
          content: SingleChildScrollView(
            child: ListBody(
              children: <Widget>[
                Text(
                  'لتقديم تجربة أفضل، الرجاء إدخال اسمك الأول.',
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 15),
                TextField(
                  controller: nameController,
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: 'الاسم الأول',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: Text('حفظ'),
              onPressed: () async {
                if (nameController.text.isNotEmpty) {
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setString('user_name', nameController.text);
                  if (mounted) {
                    setState(() {
                      _userName = nameController.text;
                    });
                    _sendDeviceInfoToServer(name: _userName!, token: _fcmToken);
                    Navigator.of(context).pop();
                  }
                }
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _showEditNameDialog() async {
    final nameController = TextEditingController(text: _userName);
    return showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('تعديل اسمك', textAlign: TextAlign.center),
          content: TextField(
            controller: nameController,
            autofocus: true,
            decoration: InputDecoration(
              hintText: 'الاسم الجديد',
              border: OutlineInputBorder(),
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: Text('إلغاء'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: Text('حفظ'),
              onPressed: () async {
                if (nameController.text.isNotEmpty) {
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setString('user_name', nameController.text);
                  if (mounted) {
                    setState(() {
                      _userName = nameController.text;
                    });
                    Navigator.of(context).pop();
                  }
                }
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _initData() async {
    setState(() {
      _isLoading = true;
      _hasError = false;
      _channelsHasError = false;
      _newsHasError = false;
      _goalsHasError = false;
      _matchesHasError = false;
    });

    List<dynamic> fetchedResults = List.filled(4, null);

    try {
      fetchedResults[0] = await ApiService.fetchChannelCategories();
    } catch (e) {
      debugPrint('Error fetching channels: $e');
      if (mounted) setState(() => _channelsHasError = true);
    }
    try {
      fetchedResults[1] = await ApiService.fetchNews();
    } catch (e) {
      debugPrint('Error fetching news: $e');
      if (mounted) setState(() => _newsHasError = true);
    }
    try {
      fetchedResults[2] = await ApiService.fetchMatches();
    } catch (e) {
      debugPrint('Error fetching matches: $e');
      if (mounted) setState(() => _matchesHasError = true);
    }
    try {
      fetchedResults[3] = await ApiService.fetchGoals();
    } catch (e) {
      debugPrint('Error fetching goals: $e');
      if (mounted) setState(() => _goalsHasError = true);
    }

    if (_channelsHasError &&
        _newsHasError &&
        _matchesHasError &&
        _goalsHasError) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasError = true;
          if (kIsWeb) removeWebSplash();
        });
      }
      return;
    }

    try {
      final processedData = await compute(_processFetchedData, fetchedResults);
      if (mounted) {
        setState(() {
          channels = processedData['channels'] ?? [];
          news = processedData['news'] ?? [];
          matches = processedData['matches'] ?? [];
          goals = processedData['goals'] ?? [];
          _filteredChannels = channels;
          _filteredChannels = channels;
          _isLoading = false;
          // REMOVE WEB SPLASH HERE (Data Loaded)
          if (kIsWeb) removeWebSplash();
          _hasError = false;
          _channelsHasError = false;
          _newsHasError = false;
          _goalsHasError = false;
          _matchesHasError = false;
        });
      }
    } catch (e) {
      debugPrint('Error processing data with compute: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasError = true;
          if (kIsWeb) removeWebSplash();
        });
      }
    }
  }

  void _retryLoadingData() {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _hasError = false;
        _channelsHasError = false;
        _newsHasError = false;
        _goalsHasError = false;
        _matchesHasError = false;
        _dataFuture = _initData();
      });
    }
  }

  void _retryChannels() {
    if (mounted) {
      setState(() {
        _channelsHasError = false;
      });
      _refreshSection(0);
    }
  }

  void _retryNews() {
    if (mounted) {
      setState(() {
        _newsHasError = false;
      });
      _refreshSection(1);
    }
  }

  void _retryGoals() {
    if (mounted) {
      setState(() {
        _goalsHasError = false;
      });
      _refreshSection(2);
    }
  }

  void _retryMatches() {
    if (mounted) {
      setState(() {
        _matchesHasError = false;
      });
      _refreshSection(3);
    }
  }

  void _filterChannels(String query) {
    if (!mounted) return;
    setState(() {
      if (query.isEmpty) {
        _filteredChannels = channels;
      } else {
        _filteredChannels = channels.where((channelCategory) {
          if (channelCategory is Map) {
            String categoryName = channelCategory['name']?.toLowerCase() ?? '';
            if (categoryName.contains(query.toLowerCase())) {
              return true;
            }
            if (channelCategory['channels'] is List) {
              return channelCategory['channels'].any((channel) {
                if (channel is Map) {
                  String channelName = channel['name']?.toLowerCase() ?? '';
                  return channelName.contains(query.toLowerCase());
                }
                return false;
              });
            }
            return false;
          }
          return false;
        }).toList();
      }
    });
  }

  int compareVersions(String version1, String version2) {
    List<String> v1Parts = version1.split('.');
    List<String> v2Parts = version2.split('.');
    int len = v1Parts.length > v2Parts.length ? v1Parts.length : v2Parts.length;
    for (int i = 0; i < len; i++) {
      int v1 = i < v1Parts.length ? int.tryParse(v1Parts[i]) ?? 0 : 0;
      int v2 = i < v2Parts.length ? int.tryParse(v2Parts[i]) ?? 0 : 0;
      if (v1 < v2) return -1;
      if (v1 > v2) return 1;
    }
    return 0;
  }

  Future<void> checkForUpdate() async {
    try {
      final response = await http.get(
        Uri.parse(
          'https://raw.githubusercontent.com/hussein34535/forceupdate/refs/heads/main/update.json',
        ),
      );
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final latestVersion = data['version'];
        final updateUrl = data['update_url'];
        const currentVersion = '4.0.0';

        if (latestVersion != null &&
            updateUrl != null &&
            compareVersions(currentVersion, latestVersion) < 0) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              showUpdateDialog(updateUrl);
            }
          });
        } else {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              showTelegramDialog(context, userName: _userName);
            }
          });
        }
      } else if (mounted) {
        showTelegramDialog(context, userName: _userName);
      }
    } catch (e) {
      if (e is http.ClientException || e is SocketException) {
        // Prevent SnackBar from appearing over the Splash Screen
        if (mounted && !_isLoading) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  'فشل التحقق من التحديث. يرجى التحقق من اتصالك بالإنترنت.'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  void showUpdateDialog(String updateUrl) {
    if (!mounted) return;

    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withAlpha((0.8 * 255).round()),
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (
        BuildContext buildContext,
        Animation<double> animation,
        Animation<double> secondaryAnimation,
      ) {
        return PopScope(
          canPop: false,
          child: Scaffold(
            backgroundColor: Theme.of(
              context,
            ).scaffoldBackgroundColor.withAlpha((255 * 0.9).round()),
            body: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24.0),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        Text(
                          "⚠️ تحديث إجباري",
                          textAlign: TextAlign.center,
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          "هناك تحديث جديد إلزامي للتطبيق. الرجاء التحديث للاستمرار في استخدام التطبيق.",
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 30),
                        ElevatedButton(
                          onPressed: () async {
                            final Uri uri = Uri.parse(updateUrl);
                            try {
                              if (await canLaunchUrl(uri)) {
                                await launchUrl(
                                  uri,
                                  mode: LaunchMode.externalApplication,
                                );
                              } else {
                                if (mounted) {
                                  ScaffoldMessenger.of(
                                    context,
                                  ).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'لا يمكن فتح رابط التحديث.',
                                      ),
                                    ),
                                  );
                                }
                              }
                            } catch (e) {
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'حدث خطأ عند فتح الرابط.',
                                    ),
                                  ),
                                );
                              }
                            }
                          },
                          child: const Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: 25,
                              vertical: 12,
                            ),
                            child: Text(
                              "تحديث الآن",
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> requestNotificationPermission() async {
    var status = await Permission.notification.status;
    if (!status.isGranted) {
      await Permission.notification.request();
    }
  }

  void openVideo(
    BuildContext context,
    String initialUrl,
    List<Map<String, dynamic>> streamLinks,
    String sourceSection,
  ) async {
    // WEB SPECIFIC: Skip all ad logic on web
    if (kIsWeb) {
      _navigateToVideoPlayer(context, initialUrl, streamLinks);
      return;
    }

    // Check if the user has an active ad-free session
    final bool adFree = await AdService.isAdFree();
    if (adFree) {
      print("Ad-free period is active. Skipping ad.");
      _navigateToVideoPlayer(context, initialUrl, streamLinks);
      return;
    }

    if (_isAdShowing) {
      print("Ad is already in progress. Ignoring new request.");
      return;
    }

    // Filter out any stream links that don't have a valid name or url.
    final validStreamLinks = streamLinks.where((link) {
      final name = link['name']?.toString();
      final url = link['url']?.toString();

      // Basic validation: must have a URL and a non-empty name
      if (name == null ||
          name.trim().isEmpty ||
          url == null ||
          url.isEmpty ||
          name.trim().toLowerCase() == 'stream') {
        return false;
      }

      // Advanced validation: check for empty JSON rich text names like [{"text":""}]
      if (name.trim().startsWith('[') && name.trim().endsWith(']')) {
        try {
          final List<dynamic> nameParts = jsonDecode(name);
          if (nameParts.isNotEmpty) {
            bool allPartsEmpty = nameParts.every((part) {
              if (part is Map && part.containsKey('text')) {
                final text = part['text']?.toString();
                return text == null || text.trim().isEmpty;
              }
              return false; // Invalid part structure, treat as empty
            });
            if (allPartsEmpty) {
              return false; // It's an empty rich text, ignore it.
            }
          }
        } catch (e) {
          // Not valid JSON, so it's a regular name. Let it pass.
        }
      }

      return true; // The link is valid
    }).toList();

    setState(() {
      _isAdShowing = true;
    });

    void _resetAdLock() {
      if (mounted) {
        setState(() {
          _isAdShowing = false;
        });
      }
    }

    final bool isRewardedSection =
        sourceSection == 'news' || sourceSection == 'goals';
    final String placementId =
        isRewardedSection ? _rewardedPlacementId : _interstitialPlacementId;

    bool adLoadFinished = false;
    bool navigationDone = false;
    Timer? loadTimer;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return const AlertDialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          content: Center(
            child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
            ),
          ),
        );
      },
    );

    final BuildContext? capturedNavigatorContext = navigatorKey.currentContext;

    void dismissAndNavigate() {
      if (navigationDone) return;
      navigationDone = true;
      BuildContext effectiveContext = capturedNavigatorContext ?? context;

      if (Navigator.canPop(effectiveContext)) {
        Navigator.pop(effectiveContext);
      }
      _navigateToVideoPlayer(effectiveContext, initialUrl, validStreamLinks);
    }

    void cancelAdAndDismiss() {
      if (navigationDone) return;
      navigationDone = true;
      _resetAdLock();
      loadTimer?.cancel();
      BuildContext effectiveContext = capturedNavigatorContext ?? context;
      if (Navigator.canPop(effectiveContext)) {
        Navigator.pop(effectiveContext);
      }
    }

    void showAdOverlay(String adPlacementId) {
      UnityAds.showVideoAd(
        placementId: adPlacementId,
        onComplete: (pid) {},
        onFailed: (pid, err, msg) {},
        onStart: (pid) {},
        onClick: (pid) {},
        onSkipped: (pid) {
          if (isRewardedSection) {
            BuildContext effectiveContext = capturedNavigatorContext ?? context;
            ScaffoldMessenger.of(effectiveContext).showSnackBar(
              const SnackBar(
                content: Text('يجب مشاهدة الإعلان كاملاً للوصول للمحتوى.'),
              ),
            );
          }
        },
      );
    }

    loadTimer = Timer(const Duration(seconds: 10), () {
      print("Ad load timer expired.");
      _resetAdLock();
      if (!adLoadFinished) {
        print("Timeout occurred before ad load finished. Navigating early.");
        dismissAndNavigate();
      }
    });

    try {
      if (!kIsWeb) {
        UnityAds.load(
          placementId: placementId,
          onComplete: (loadedPlacementId) async {
            if (adLoadFinished) return;
            adLoadFinished = true;
            loadTimer?.cancel();

            if (navigationDone) {
              showAdOverlay(loadedPlacementId);
            } else {
              BuildContext effectiveContext =
                  capturedNavigatorContext ?? context;
              if (Navigator.canPop(effectiveContext)) {
                Navigator.pop(effectiveContext);
              }

              DateTime? adStartTime;

              await UnityAds.showVideoAd(
                placementId: loadedPlacementId,
                onComplete: (completedPlacementId) {
                  _resetAdLock();
                  dismissAndNavigate();
                },
                onFailed: (failedPlacementId, error, message) {
                  _resetAdLock();
                  dismissAndNavigate();
                },
                onStart: (startPlacementId) {
                  adStartTime = DateTime.now();
                },
                onClick: (clickPlacementId) => {},
                onSkipped: (skippedPlacementId) {
                  _resetAdLock();
                  print("Pre-Nav Ad $skippedPlacementId Skipped.");

                  final adWatchDuration = adStartTime != null
                      ? DateTime.now().difference(adStartTime!)
                      : Duration.zero;

                  if (adWatchDuration.inSeconds < 6) {
                    print(
                        "Skipped early (likely back press). Cancelling navigation.");
                    cancelAdAndDismiss();
                  } else {
                    print("Skipped after threshold. Navigating to player.");
                    dismissAndNavigate();
                  }
                },
              );
            }
          },
          onFailed: (failedPlacementId, error, message) {
            if (adLoadFinished) return;
            adLoadFinished = true;
            loadTimer?.cancel();

            _resetAdLock();

            if (!navigationDone) {
              dismissAndNavigate();
            }
          },
        );
      } else {
        // Fallback for web if somehow reached here
        _navigateToVideoPlayer(context, initialUrl, streamLinks);
      }
    } catch (e) {
      loadTimer.cancel();
      _resetAdLock();
      if (!navigationDone) {
        dismissAndNavigate();
      }
    }
  }

  void _navigateToVideoPlayer(
    BuildContext context,
    String initialUrl,
    List<Map<String, dynamic>> streamLinks,
  ) {
    navigatorKey.currentState?.push(
      MaterialPageRoute(
        builder: (context) =>
            VideoPlayerScreen(initialUrl: initialUrl, streamLinks: streamLinks),
      ),
    );
  }

  List<Widget> _buildAppBarActions() {
    List<Widget> actions = [];

    actions.add(
      Transform.scale(
        scale: 0.35,
        child: DayNightSwitch(
          value: _isDarkMode,
          moonImage: AssetImage('assets/moon.png'),
          sunImage: AssetImage('assets/sun.png'),
          onChanged: (value) {
            setState(() {
              _isDarkMode = value;
            });
            widget.onThemeChanged(value);
          },
          dayColor: Color(0xFFF8F8F8),
          nightColor: Color.fromARGB(255, 10, 10, 80),
          sunColor: Colors.amberAccent,
          moonColor: Colors.white,
        ),
      ),
    );

    return actions;
  }

  Widget _buildSearchBar() {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
        child: Container(
          height: 48,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: Theme.of(
                context,
              ).colorScheme.secondary.withAlpha((0.5 * 255).round()),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'بحث عن قناة...',
                    hintStyle: TextStyle(
                      color: Theme.of(context).textTheme.bodySmall?.color,
                    ),
                    prefixIcon: Icon(
                      Icons.search,
                      color: Theme.of(context).colorScheme.secondary,
                    ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    isDense: true,
                  ),
                  onChanged: _filterChannels,
                  style: TextStyle(
                    color: Theme.of(context).textTheme.bodyLarge!.color,
                  ),
                ),
              ),
              IconButton(
                icon: Icon(
                  Icons.close,
                  color: Theme.of(context).textTheme.bodyLarge!.color,
                ),
                onPressed: () {
                  if (!mounted) return;
                  setState(() {
                    _isSearchBarVisible = false;
                    _searchController.clear();
                    _filterChannels('');
                  });
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _refreshSection(int index) async {
    if (!mounted) return;

    setState(() {
      switch (index) {
        case 0:
          _channelsHasError = false;
          break;
        case 1:
          _newsHasError = false;
          break;
        case 2:
          _goalsHasError = false;
          break;
        case 3:
          _matchesHasError = false;
          break;
      }
    });

    try {
      switch (index) {
        case 0:
          try {
            final fetchedChannels = await ApiService.fetchChannelCategories();
            final processedChannels =
                await compute(_processRefreshedChannelsData, fetchedChannels);

            if (mounted) {
              setState(() {
                channels = processedChannels;
                _filterChannels(_searchController.text);
                _channelsHasError = false;
              });
            }
          } catch (e) {
            debugPrint('Error refreshing channels: $e');
            if (mounted) {
              setState(() {
                _channelsHasError = true;
                channels = [];
                _filterChannels('');
              });
            }
          }
          break;
        case 1:
          try {
            final fetchedNews = await ApiService.fetchNews();
            final processedNews =
                await compute(_processRefreshedNewsData, fetchedNews);

            if (mounted) {
              setState(() {
                news = processedNews;
                _newsHasError = false;
              });
            }
          } catch (e) {
            debugPrint('Error refreshing news: $e');
            if (mounted) {
              setState(() {
                _newsHasError = true;
                news = [];
              });
            }
          }
          break;
        case 2:
          try {
            final fetchedGoals = await ApiService.fetchGoals();
            final processedGoals =
                await compute(_processRefreshedGoalsData, fetchedGoals);

            if (mounted) {
              setState(() {
                goals = processedGoals;
                _goalsHasError = false;
              });
            }
          } catch (e) {
            debugPrint('Error refreshing goals: $e');
            if (mounted) {
              setState(() {
                _goalsHasError = true;
                goals = [];
              });
            }
          }
          break;
        case 3:
          try {
            final fetchedMatches = await ApiService.fetchMatches();
            if (mounted) {
              setState(() {
                matches = fetchedMatches;
                _matchesHasError = false;
              });
            }
          } catch (e) {
            debugPrint('Error refreshing matches: $e');
            if (mounted) {
              setState(() {
                _matchesHasError = true;
                matches = [];
              });
            }
          }
          break;
      }
    } catch (e) {
      debugPrint('Unexpected error during section refresh: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    // LOADING STATE: Match HTML Splash (Full Screen, Black, Centered Logo)
    // WEB ONLY as requested
    // LOADING STATE: Match HTML Splash (Full Screen, Black, Centered Logo)
    // WEB ONLY as requested
    if (kIsWeb && _isLoading) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF7C52D8)),
          ),
        ),
      );
    }

    final appBarHeight = AppBar().preferredSize.height;

    return Scaffold(
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(appBarHeight),
        child: AnimatedContainer(
          duration: Duration(milliseconds: 300),
          decoration: BoxDecoration(
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                spreadRadius: 1,
                blurRadius: 3,
                offset: Offset(0, 1),
              ),
            ],
            color: Theme.of(context).appBarTheme.backgroundColor,
          ),
          child: AppBar(
            elevation: 0,
            leading: IconButton(
              icon: Icon(Icons.menu_rounded, color: Colors.white, size: 28),
              onPressed: () {
                showModalBottomSheet(
                  context: context,
                  backgroundColor: Theme.of(context).cardColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(16),
                    ),
                  ),
                  builder: (BuildContext context) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          if (_userName != null)
                            ListTile(
                              leading: Icon(
                                Icons.person,
                                color: Theme.of(context).colorScheme.secondary,
                              ),
                              title: Text(
                                _userName!,
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Theme.of(
                                    context,
                                  ).textTheme.bodyLarge!.color,
                                ),
                              ),
                              trailing: Icon(Icons.edit,
                                  color: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.color),
                              onTap: () {
                                Navigator.pop(context);
                                _showEditNameDialog();
                              },
                            ),
                          FutureBuilder<Map<String, dynamic>>(
                            future: _getAdStatus(),
                            builder: (context, snapshot) {
                              Widget? subtitle;
                              IconData leadingIcon = Icons.shield_outlined;
                              Color iconColor =
                                  Theme.of(context).colorScheme.secondary;
                              bool hasEverUsed = false;

                              if (snapshot.connectionState ==
                                      ConnectionState.done &&
                                  snapshot.hasData) {
                                final DateTime? expiryDate =
                                    snapshot.data?['expiry'];
                                hasEverUsed =
                                    snapshot.data?['hasUsed'] ?? false;

                                if (expiryDate != null &&
                                    expiryDate.isAfter(DateTime.now())) {
                                  // State: Active
                                  final remainingDays = expiryDate
                                      .difference(DateTime.now())
                                      .inDays;
                                  leadingIcon = Icons.check_circle;
                                  iconColor = Colors.green;
                                  subtitle = Row(
                                    children: [
                                      Container(
                                        width: 8,
                                        height: 8,
                                        decoration: const BoxDecoration(
                                            color: Colors.green,
                                            shape: BoxShape.circle),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        'متبقي: ${remainingDays + 1} يوم',
                                        style: TextStyle(
                                            color: Theme.of(context)
                                                .textTheme
                                                .bodySmall
                                                ?.color
                                                ?.withValues(alpha: 0.8),
                                            fontSize: 12),
                                      ),
                                    ],
                                  );
                                } else if (hasEverUsed) {
                                  // State: Expired but used before
                                  leadingIcon = Icons.check_circle_outline;
                                  iconColor = Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.color ??
                                      Colors.grey;
                                }
                                // State: Never used -> defaults are already set
                              }

                              return ListTile(
                                leading: Icon(leadingIcon, color: iconColor),
                                title: Text(
                                  'كود مانع الإعلانات',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Theme.of(context)
                                        .textTheme
                                        .bodyLarge!
                                        .color,
                                  ),
                                ),
                                subtitle: subtitle,
                                onTap: () {
                                  Navigator.pop(context);
                                  _showPromoCodeDialog();
                                },
                              );
                            },
                          ),
                          ListTile(
                            leading: Icon(Icons.color_lens,
                                color: Theme.of(context).colorScheme.secondary),
                            title: Text(
                              'تخصيص الألوان',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Theme.of(
                                  context,
                                ).textTheme.bodyLarge!.color,
                              ),
                            ),
                            onTap: () {
                              Navigator.pop(context);
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) =>
                                      const ThemeCustomizationScreen(),
                                ),
                              );
                            },
                          ),
                          ListTile(
                            leading: Icon(
                              FontAwesomeIcons.telegram,
                              color: Theme.of(context).colorScheme.secondary,
                            ),
                            title: Text(
                              'Telegram',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Theme.of(
                                  context,
                                ).textTheme.bodyLarge!.color,
                              ),
                            ),
                            onTap: () async {
                              Navigator.pop(context);
                              final Uri telegramUri = Uri.parse(
                                'https://t.me/tv_7esen',
                              );
                              try {
                                if (await canLaunchUrl(telegramUri)) {
                                  await launchUrl(
                                    telegramUri,
                                    mode: LaunchMode.externalApplication,
                                  );
                                } else {
                                  if (mounted) {
                                    ScaffoldMessenger.of(
                                      context,
                                    ).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'لا يمكن فتح رابط التحديث.',
                                        ),
                                      ),
                                    );
                                  }
                                }
                              } catch (e) {
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'حدث خطأ عند فتح الرابط.',
                                      ),
                                    ),
                                  );
                                }
                              }
                            },
                          ),
                          ListTile(
                            leading: Icon(
                              Icons.search,
                              color: Theme.of(context).colorScheme.secondary,
                            ),
                            title: Text(
                              'البحث',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Theme.of(
                                  context,
                                ).textTheme.bodyLarge!.color,
                              ),
                            ),
                            onTap: () {
                              Navigator.pop(context);
                              setState(() {
                                _isSearchBarVisible = true;
                              });
                            },
                          ),
                          ListTile(
                            leading: Icon(
                              Icons.privacy_tip_rounded,
                              color: Theme.of(context).colorScheme.secondary,
                            ),
                            title: Text(
                              'سياسة الخصوصية',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Theme.of(
                                  context,
                                ).textTheme.bodyLarge!.color,
                              ),
                            ),
                            onTap: () {
                              Navigator.pop(context);
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => PrivacyPolicyPage(),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
            title: Row(
              children: [
                Expanded(
                  child: Directionality(
                    textDirection: TextDirection.rtl,
                    child: _userName != null
                        ? RichText(
                            textAlign:
                                Directionality.of(context) == TextDirection.rtl
                                    ? TextAlign.right
                                    : TextAlign.left,
                            text: TextSpan(
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                              children: [
                                const TextSpan(text: 'أهلاً بك '),
                                TextSpan(
                                  text: _userName,
                                  style: TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.bold,
                                    foreground: _isDarkMode
                                        ? (Paint()
                                          ..shader = LinearGradient(
                                            colors: <Color>[
                                              Colors.blue.shade800,
                                              Colors.deepPurple.shade700,
                                              Colors.blue.shade500,
                                            ],
                                            // --- >> START OF FIX << ---
                                            begin: Alignment.centerLeft,
                                            end: Alignment.centerRight,
                                            // --- >> END OF FIX << ---
                                          ).createShader(Rect.fromLTWH(
                                              0.0, 0.0, 200.0, 70.0)))
                                        : null,
                                    color:
                                        _isDarkMode ? null : Color(0xFFF8F8F8),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                ),
              ],
            ),
            actions: _buildAppBarActions(),
          ),
        ),
      ),
      body: _isSearchBarVisible
          ? _buildSearchBar()
          : FutureBuilder<void>(
              future: _dataFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Center(child: CircularProgressIndicator());
                } else if (_hasError) {
                  return _buildGeneralErrorWidget();
                } else {
                  return RefreshIndicator(
                    color: Theme.of(context).colorScheme.secondary,
                    backgroundColor: Theme.of(context).cardColor,
                    onRefresh: () => _refreshSection(_selectedIndex),
                    child: Padding(
                      padding: const EdgeInsets.only(top: 10.0),
                      child: IndexedStack(
                        index: _selectedIndex,
                        children: [
                          _buildSectionContent(0), // Channels
                          _buildSectionContent(1), // News
                          _buildSectionContent(2), // Goals
                          _buildSectionContent(3), // Matches
                        ],
                      ),
                    ),
                  );
                }
              },
            ),
      bottomNavigationBar: CurvedNavigationBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        color: _isDarkMode ? Colors.black : Color(0xFF7C52D8),
        buttonBackgroundColor: Theme.of(context).cardColor,
        animationDuration: const Duration(milliseconds: 300),
        items: [
          Icon(Icons.tv, size: 30, color: Colors.white),
          Image.asset(
            'assets/replay.png',
            width: 30,
            height: 30,
            color: Colors.white,
          ),
          Image.asset(
            'assets/goal.png',
            width: 30,
            height: 30,
            color: Colors.white,
          ),
          Image.asset(
            'assets/table.png',
            width: 30,
            height: 30,
            color: Colors.white,
          ),
        ],
        index: _selectedIndex,
        onTap: (index) {
          setState(() {
            _selectedIndex = index;
          });
        },
        height: 60,
      ),
    );
  }

  Widget _buildGeneralErrorWidget() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.error_outline,
            color: Colors.red,
            size: 60,
          ),
          const SizedBox(height: 20),
          Text(
            'حدث خطأ أثناء تحميل البيانات.',
            style: TextStyle(
              color: Theme.of(context).textTheme.bodyLarge!.color,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'الرجاء التحقق من اتصالك بالإنترنت والمحاولة مرة أخرى.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Theme.of(context).textTheme.bodyMedium!.color,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 30),
          ElevatedButton.icon(
            onPressed: _retryLoadingData,
            icon: Icon(Icons.replay),
            label: Text('إعادة المحاولة'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).primaryColor,
              foregroundColor: Colors.white,
              padding: EdgeInsets.symmetric(horizontal: 30, vertical: 15),
              textStyle: TextStyle(fontSize: 16),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionErrorWidget(String message, VoidCallback onRetry) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.error_outline,
            color: Colors.red,
            size: 50,
          ),
          const SizedBox(height: 15),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Theme.of(context).textTheme.bodyLarge!.color,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 25),
          ElevatedButton.icon(
            onPressed: onRetry,
            icon: Icon(Icons.replay),
            label: Text('إعادة المحاولة'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).primaryColor,
              foregroundColor: Colors.white,
              padding: EdgeInsets.symmetric(horizontal: 25, vertical: 12),
              textStyle: TextStyle(fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionContent(int index) {
    switch (index) {
      case 0: // Channels
        if (_channelsHasError) {
          return _buildSectionErrorWidget(
            'فشل تحميل القنوات. الرجاء المحاولة مرة أخرى.',
            _retryChannels,
          );
        } else {
          return ChannelsSection(
            channelCategories: _filteredChannels,
            openVideo: openVideo,
            isAdLoading: _isAdShowing,
          );
        }
      case 1: // News
        if (_newsHasError) {
          return _buildSectionErrorWidget(
            'فشل تحميل الأخبار. الرجاء المحاولة مرة أخرى.',
            _retryNews,
          );
        } else {
          return NewsSection(
            newsArticles: Future.value(news),
            openVideo: openVideo,
            isAdLoading: _isAdShowing,
          );
        }
      case 2: // Goals
        if (_goalsHasError) {
          return _buildSectionErrorWidget(
            'فشل تحميل الأهداف. الرجاء المحاولة مرة أخرى.',
            _retryGoals,
          );
        } else {
          return GoalsSection(
            goalsArticles: Future.value(goals),
            openVideo: openVideo,
            isAdLoading: _isAdShowing,
          );
        }
      case 3: // Matches
        if (_matchesHasError) {
          return _buildSectionErrorWidget(
            'فشل تحميل المباريات. الرجاء المحاولة مرة أخرى.',
            _retryMatches,
          );
        } else {
          return MatchesSection(
            matches: Future.value(matches),
            openVideo: openVideo,
            isAdLoading: _isAdShowing,
          );
        }
      default:
        return Center(child: Text('قسم غير معروف'));
    }
  }
}
