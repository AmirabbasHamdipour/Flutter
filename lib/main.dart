// main.dart
import 'dart:async';
import 'dart:collection';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart' as path_provider;

// -------------------- Models --------------------
part 'main.g.dart'; // برای Hive

@HiveType(typeId: 0)
class GoldTransaction extends HiveObject {
  @HiveField(0)
  String id;
  @HiveField(1)
  String type; // gold_18, gold_24, gold_ons, gold_mazneh (برای طلا) و برای سکه: coin_old, coin_new, coin_half, coin_quarter, coin_1g
  @HiveField(2)
  DateTime purchaseDate;
  @HiveField(3)
  double purchasePricePerUnit; // فی خرید
  @HiveField(4)
  double quantity; // وزن بر حسب گرم (برای طلا) یا تعداد (برای سکه؟ اما اینجا double است)
  @HiveField(5)
  String description;
  @HiveField(6)
  bool isGold; // true for gold, false for coin

  GoldTransaction({
    required this.id,
    required this.type,
    required this.purchaseDate,
    required this.purchasePricePerUnit,
    required this.quantity,
    required this.description,
    required this.isGold,
  });
}

@HiveType(typeId: 1)
class CoinTransaction extends HiveObject {
  @HiveField(0)
  String id;
  @HiveField(1)
  String coinType; // coin_old, coin_new, coin_half, coin_quarter, coin_1g
  @HiveField(2)
  DateTime purchaseDate;
  @HiveField(3)
  double purchasePricePerUnit; // فی هر سکه
  @HiveField(4)
  int count; // تعداد
  @HiveField(5)
  String description;

  CoinTransaction({
    required this.id,
    required this.coinType,
    required this.purchaseDate,
    required this.purchasePricePerUnit,
    required this.count,
    required this.description,
  });
}

// -------------------- مدل پاسخ API --------------------
class PriceResponse {
  final String name;
  final double? currentPrice;
  final double? high;
  final double? low;
  final double? yesterdayAvg;
  final Change? change;

  PriceResponse({
    required this.name,
    this.currentPrice,
    this.high,
    this.low,
    this.yesterdayAvg,
    this.change,
  });

  factory PriceResponse.fromJson(Map<String, dynamic> json) {
    return PriceResponse(
      name: json['name'] ?? '',
      currentPrice: json['current_price'] != null ? (json['current_price'] as num).toDouble() : null,
      high: json['high'] != null ? (json['high'] as num).toDouble() : null,
      low: json['low'] != null ? (json['low'] as num).toDouble() : null,
      yesterdayAvg: json['yesterday_avg'] != null ? (json['yesterday_avg'] as num).toDouble() : null,
      change: json['change'] != null ? Change.fromJson(json['change']) : null,
    );
  }
}

class Change {
  final double? value;
  final double? percent;
  final String? direction;

  Change({this.value, this.percent, this.direction});

  factory Change.fromJson(Map<String, dynamic> json) {
    return Change(
      value: json['value'] != null ? (json['value'] as num).toDouble() : null,
      percent: json['percent'] != null ? (json['percent'] as num).toDouble() : null,
      direction: json['direction'],
    );
  }
}

// -------------------- API Service (تطبیق با API جدید) --------------------
class ApiService {
  static const String baseUrl = 'https://tweeter.runflare.run/price/';

  static Future<PriceResponse?> fetchPrice(String obj) async {
    try {
      final response = await http.get(Uri.parse('$baseUrl$obj'));
      if (response.statusCode == 200) {
        final jsonData = jsonDecode(response.body);
        return PriceResponse.fromJson(jsonData);
      }
    } catch (e) {
      print('Error fetching $obj: $e');
    }
    return null;
  }

  // دریافت همه قیمت‌های مورد نیاز
  static Future<Map<String, PriceResponse>> fetchAllPrices() async {
    final types = [
      'gold_18',
      'gold_24',
      'gold_ons',
      'gold_mazneh',
      'coin_old',
      'coin_new',
      'coin_half',
      'coin_quarter',
      'coin_1g'
    ];
    Map<String, PriceResponse> prices = {};
    for (String type in types) {
      final response = await fetchPrice(type);
      if (response != null) prices[type] = response;
    }
    return prices;
  }
}

// -------------------- Providers --------------------
class PriceProvider extends ChangeNotifier {
  Map<String, PriceResponse> _prices = {};
  Map<String, PriceResponse> _lastSavedPrices = {};
  DateTime _lastUpdated = DateTime(2000);
  Timer? _timer;
  final SharedPreferences _prefs;

  static const List<String> _priceKeys = [
    'gold_18', 'gold_24', 'gold_ons', 'gold_mazneh',
    'coin_old', 'coin_new', 'coin_half', 'coin_quarter', 'coin_1g'
  ];

  Map<String, PriceResponse> get prices => UnmodifiableMapView(_prices);
  DateTime get lastUpdated => _lastUpdated;

  PriceProvider(this._prefs) {
    _loadSavedPrices();
    fetchPrices();
    startAutoUpdate();
  }

  void _loadSavedPrices() {
    _lastSavedPrices = {};
    for (var key in _priceKeys) {
      String? jsonStr = _prefs.getString('price_$key');
      if (jsonStr != null) {
        try {
          final json = jsonDecode(jsonStr);
          _lastSavedPrices[key] = PriceResponse.fromJson(json);
        } catch (e) {
          print('Error loading saved price for $key: $e');
        }
      }
    }
    if (_lastSavedPrices.isNotEmpty) {
      _prices = Map.from(_lastSavedPrices);
      int? savedTime = _prefs.getInt('last_update');
      if (savedTime != null) {
        _lastUpdated = DateTime.fromMillisecondsSinceEpoch(savedTime);
      }
    }
  }

  Future<void> _savePrices(Map<String, PriceResponse> prices) async {
    for (var entry in prices.entries) {
      final jsonStr = jsonEncode({
        'name': entry.value.name,
        'current_price': entry.value.currentPrice,
        'high': entry.value.high,
        'low': entry.value.low,
        'yesterday_avg': entry.value.yesterdayAvg,
        'change': entry.value.change != null
            ? {
                'value': entry.value.change!.value,
                'percent': entry.value.change!.percent,
                'direction': entry.value.change!.direction,
              }
            : null,
      });
      await _prefs.setString('price_${entry.key}', jsonStr);
    }
    await _prefs.setInt('last_update', DateTime.now().millisecondsSinceEpoch);
  }

  void startAutoUpdate({int intervalSeconds = 300}) {
    _timer?.cancel();
    _timer = Timer.periodic(Duration(seconds: intervalSeconds), (_) => fetchPrices());
  }

  void setAutoUpdateInterval(int seconds) {
    startAutoUpdate(intervalSeconds: seconds);
  }

  Future<void> fetchPrices() async {
    final newPrices = await ApiService.fetchAllPrices();
    if (newPrices.isNotEmpty) {
      _prices = newPrices;
      _lastSavedPrices = Map.from(newPrices);
      _lastUpdated = DateTime.now();
      await _savePrices(newPrices);
      notifyListeners();
    } else if (_lastSavedPrices.isNotEmpty) {
      // استفاده از آخرین مقادیر ذخیره شده
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

class SettingsProvider extends ChangeNotifier {
  double _bankInterestRate = 26.0; // درصد
  int _autoUpdateInterval = 300; // ثانیه

  double get bankInterestRate => _bankInterestRate;
  int get autoUpdateInterval => _autoUpdateInterval;

  final SharedPreferences _prefs;

  SettingsProvider(this._prefs) {
    _loadSettings();
  }

  void _loadSettings() {
    _bankInterestRate = _prefs.getDouble('bankInterestRate') ?? 26.0;
    _autoUpdateInterval = _prefs.getInt('autoUpdateInterval') ?? 300;
  }

  Future<void> setBankInterestRate(double value) async {
    _bankInterestRate = value;
    await _prefs.setDouble('bankInterestRate', value);
    notifyListeners();
  }

  Future<void> setAutoUpdateInterval(int seconds) async {
    _autoUpdateInterval = seconds;
    await _prefs.setInt('autoUpdateInterval', seconds);
    notifyListeners();
  }
}

class DataProvider extends ChangeNotifier {
  final Box<GoldTransaction> goldBox;
  final Box<CoinTransaction> coinBox;

  DataProvider({required this.goldBox, required this.coinBox}) {
    _ensureDefaultData();
  }

  void _ensureDefaultData() {
    if (goldBox.isEmpty) {
      _addDefaultGold();
    }
    if (coinBox.isEmpty) {
      _addDefaultCoins();
    }
  }

  void _addDefaultGold() {
    final golds = [
      GoldTransaction(
        id: DateTime.now().millisecondsSinceEpoch.toString() + '1',
        type: 'gold_18',
        purchaseDate: DateTime(2025, 1, 2),
        purchasePricePerUnit: 52518583,
        quantity: 100,
        description: '',
        isGold: true,
      ),
      GoldTransaction(
        id: DateTime.now().millisecondsSinceEpoch.toString() + '2',
        type: 'gold_18',
        purchaseDate: DateTime(2025, 2, 9),
        purchasePricePerUnit: 65792511,
        quantity: 61.195,
        description: '',
        isGold: true,
      ),
      GoldTransaction(
        id: DateTime.now().millisecondsSinceEpoch.toString() + '3',
        type: 'gold_18',
        purchaseDate: DateTime(2025, 4, 13),
        purchasePricePerUnit: 76180802,
        quantity: 50,
        description: '',
        isGold: true,
      ),
      GoldTransaction(
        id: DateTime.now().millisecondsSinceEpoch.toString() + '4',
        type: 'gold_18',
        purchaseDate: DateTime(2025, 10, 6),
        purchasePricePerUnit: 105960571,
        quantity: 100,
        description: '',
        isGold: true,
      ),
      GoldTransaction(
        id: DateTime.now().millisecondsSinceEpoch.toString() + '5',
        type: 'gold_18',
        purchaseDate: DateTime(2025, 11, 10),
        purchasePricePerUnit: 105730000,
        quantity: 60,
        description: '',
        isGold: true,
      ),
      GoldTransaction(
        id: DateTime.now().millisecondsSinceEpoch.toString() + '6',
        type: 'gold_18',
        purchaseDate: DateTime(2025, 12, 14),
        purchasePricePerUnit: 138048000,
        quantity: 15,
        description: '',
        isGold: true,
      ),
    ];
    goldBox.addAll(golds);
  }

  void _addDefaultCoins() {
    final coins = [
      CoinTransaction(
        id: DateTime.now().millisecondsSinceEpoch.toString() + 'c1',
        coinType: 'coin_quarter',
        purchaseDate: DateTime(2023, 1, 17),
        purchasePricePerUnit: 70500000,
        count: 3,
        description: 'خرید از بورس کالای کارگزاری آگاه',
      ),
      CoinTransaction(
        id: DateTime.now().millisecondsSinceEpoch.toString() + 'c2',
        coinType: 'coin_new',
        purchaseDate: DateTime(2025, 1, 1),
        purchasePricePerUnit: 560000000,
        count: 2,
        description: 'خرید از زهرا',
      ),
      CoinTransaction(
        id: DateTime.now().millisecondsSinceEpoch.toString() + 'c3',
        coinType: 'coin_quarter',
        purchaseDate: DateTime(2025, 1, 1),
        purchasePricePerUnit: 174000000,
        count: 1,
        description: 'خرید از زهرا',
      ),
      CoinTransaction(
        id: DateTime.now().millisecondsSinceEpoch.toString() + 'c4',
        coinType: 'coin_new',
        purchaseDate: DateTime(2025, 9, 8),
        purchasePricePerUnit: 832224932,
        count: 6,
        description: 'خرید از مرکز مبادلات سکه و ارز',
      ),
      CoinTransaction(
        id: DateTime.now().millisecondsSinceEpoch.toString() + 'c5',
        coinType: 'coin_half',
        purchaseDate: DateTime(2025, 9, 8),
        purchasePricePerUnit: 441195425,
        count: 10,
        description: 'خرید از مرکز مبادلات سکه و ارز',
      ),
      CoinTransaction(
        id: DateTime.now().millisecondsSinceEpoch.toString() + 'c6',
        coinType: 'coin_quarter',
        purchaseDate: DateTime(2025, 9, 8),
        purchasePricePerUnit: 257758617,
        count: 14,
        description: 'خرید از مرکز مبادلات سکه و ارز',
      ),
      CoinTransaction(
        id: DateTime.now().millisecondsSinceEpoch.toString() + 'c7',
        coinType: 'coin_half',
        purchaseDate: DateTime(2025, 11, 12),
        purchasePricePerUnit: 575585000,
        count: 1,
        description: 'خرید از مرکز مبادلات کاربری مریم',
      ),
      CoinTransaction(
        id: DateTime.now().millisecondsSinceEpoch.toString() + 'c8',
        coinType: 'coin_quarter',
        purchaseDate: DateTime(2025, 11, 12),
        purchasePricePerUnit: 327850000,
        count: 2,
        description: 'خرید از مرکز مبادلات کابری مریم',
      ),
      CoinTransaction(
        id: DateTime.now().millisecondsSinceEpoch.toString() + 'c9',
        coinType: 'coin_new',
        purchaseDate: DateTime(2026, 2, 15),
        purchasePricePerUnit: 1930000000,
        count: 4,
        description: 'خرید از علی بابت پول ماشین',
      ),
      CoinTransaction(
        id: DateTime.now().millisecondsSinceEpoch.toString() + 'c10',
        coinType: 'coin_quarter',
        purchaseDate: DateTime(2026, 2, 15),
        purchasePricePerUnit: 525000000,
        count: 6,
        description: 'خرید از علی بابت پول ماشین',
      ),
      CoinTransaction(
        id: DateTime.now().millisecondsSinceEpoch.toString() + 'c11',
        coinType: 'coin_half',
        purchaseDate: DateTime(2026, 2, 15),
        purchasePricePerUnit: 970000000,
        count: 3,
        description: 'خرید از علی بابت پول ماشین',
      ),
    ];
    coinBox.addAll(coins);
  }

  List<GoldTransaction> get goldList => goldBox.values.toList();

  Future<void> addGold(GoldTransaction transaction) async {
    await goldBox.add(transaction);
    notifyListeners();
  }

  Future<void> updateGold(GoldTransaction transaction) async {
    await transaction.save();
    notifyListeners();
  }

  Future<void> deleteGold(GoldTransaction transaction) async {
    await transaction.delete();
    notifyListeners();
  }

  List<CoinTransaction> get coinList => coinBox.values.toList();

  Future<void> addCoin(CoinTransaction transaction) async {
    await coinBox.add(transaction);
    notifyListeners();
  }

  Future<void> updateCoin(CoinTransaction transaction) async {
    await transaction.save();
    notifyListeners();
  }

  Future<void> deleteCoin(CoinTransaction transaction) async {
    await transaction.delete();
    notifyListeners();
  }
}

// -------------------- Utility Functions --------------------
class Calculator {
  static int daysBetween(DateTime from, DateTime to) {
    from = DateTime(from.year, from.month, from.day);
    to = DateTime(to.year, to.month, to.day);
    return (to.difference(from).inHours / 24).round();
  }

  static double calculateProfit({
    required double currentPrice,
    required double purchasePrice,
    required double quantity,
    required double paidAmount,
    required double interestRate,
    required int days,
  }) {
    final currentValue = currentPrice * quantity;
    final purchaseProfit = currentValue - paidAmount;
    final bankProfit = (paidAmount * interestRate * days) / 36500;
    return purchaseProfit - bankProfit;
  }
}

// -------------------- Screens --------------------
class HomeScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final priceProvider = Provider.of<PriceProvider>(context);
    final dataProvider = Provider.of<DataProvider>(context);
    final settings = Provider.of<SettingsProvider>(context);

    double totalGoldValue = 0;
    double totalGoldPaid = 0;
    double totalGoldProfit = 0;
    for (var g in dataProvider.goldList) {
      final currentPrice = priceProvider.prices[g.type]?.currentPrice ?? 0;
      totalGoldValue += currentPrice * g.quantity;
      totalGoldPaid += g.purchasePricePerUnit * g.quantity;
      int days = Calculator.daysBetween(g.purchaseDate, DateTime.now());
      double profit = Calculator.calculateProfit(
        currentPrice: currentPrice,
        purchasePrice: g.purchasePricePerUnit,
        quantity: g.quantity,
        paidAmount: g.purchasePricePerUnit * g.quantity,
        interestRate: settings.bankInterestRate,
        days: days,
      );
      totalGoldProfit += profit;
    }

    double totalCoinValue = 0;
    double totalCoinPaid = 0;
    double totalCoinProfit = 0;
    for (var c in dataProvider.coinList) {
      final currentPrice = priceProvider.prices[c.coinType]?.currentPrice ?? 0;
      totalCoinValue += currentPrice * c.count;
      totalCoinPaid += c.purchasePricePerUnit * c.count;
      int days = Calculator.daysBetween(c.purchaseDate, DateTime.now());
      double profit = Calculator.calculateProfit(
        currentPrice: currentPrice,
        purchasePrice: c.purchasePricePerUnit,
        quantity: c.count.toDouble(),
        paidAmount: c.purchasePricePerUnit * c.count,
        interestRate: settings.bankInterestRate,
        days: days,
      );
      totalCoinProfit += profit;
    }

    final totalAssets = totalGoldValue + totalCoinValue;
    final totalProfit = totalGoldProfit + totalCoinProfit;

    return Scaffold(
      appBar: AppBar(title: Text('خلاصه دارایی'), centerTitle: true),
      body: RefreshIndicator(
        onRefresh: () => priceProvider.fetchPrices(),
        child: ListView(
          padding: EdgeInsets.all(16),
          children: [
            Card(
              elevation: 4,
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Column(
                  children: [
                    Text(
                      'آخرین به‌روزرسانی: ${priceProvider.lastUpdated.year > 2000 ? DateFormat('yyyy/MM/dd HH:mm').format(priceProvider.lastUpdated) : '---'}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildSummaryItem(context, 'کل دارایی', NumberFormat('#,###').format(totalAssets), Colors.green),
                      ],
                    ),
                    SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildSummaryItem(context, 'طلای آب شده', NumberFormat('#,###').format(totalGoldValue), Colors.blue), // رنگ آبی
                        _buildSummaryItem(context, 'سکه', NumberFormat('#,###').format(totalCoinValue), Colors.amber),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(height: 16),
            Card(
              elevation: 4,
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('سود/زیان کل: ', style: TextStyle(fontWeight: FontWeight.bold)),
                        Text(
                          NumberFormat('#,###').format(totalProfit),
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: totalProfit >= 0 ? Colors.green : Colors.red),
                        ),
                      ],
                    ),
                    Divider(),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildSummaryItem(context, 'سود طلا', NumberFormat('#,###').format(totalGoldProfit), totalGoldProfit >= 0 ? Colors.green : Colors.red),
                        _buildSummaryItem(context, 'سود سکه', NumberFormat('#,###').format(totalCoinProfit), totalCoinProfit >= 0 ? Colors.green : Colors.red),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(height: 20),
            Text('قیمت‌های لحظه‌ای', style: Theme.of(context).textTheme.titleMedium),
            SizedBox(height: 10),
            GridView.count(
              shrinkWrap: true,
              physics: NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              childAspectRatio: 2,
              children: priceProvider.prices.entries.map((e) {
                final price = e.value.currentPrice ?? 0;
                return Card(
                  child: Padding(
                    padding: EdgeInsets.all(8),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(_getPersianName(e.key), style: TextStyle(fontWeight: FontWeight.bold)),
                        Text(NumberFormat('#,###').format(price)),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryItem(BuildContext context, String label, String value, Color color) {
    return Column(
      children: [
        Text(label, style: Theme.of(context).textTheme.bodyMedium),
        SizedBox(height: 4),
        Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
      ],
    );
  }

  String _getPersianName(String key) {
    switch (key) {
      case 'gold_18': return 'طلای ۱۸ عیار';
      case 'gold_24': return 'طلای ۲۴ عیار';
      case 'gold_ons': return 'انس طلا';
      case 'gold_mazneh': return 'مظنه تهران';
      case 'coin_old': return 'سکه طرح قدیم';
      case 'coin_new': return 'سکه طرح جدید';
      case 'coin_half': return 'نیم سکه';
      case 'coin_quarter': return 'ربع سکه';
      case 'coin_1g': return 'سکه یک گرمی';
      default: return key;
    }
  }
}

class GoldListScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final priceProvider = Provider.of<PriceProvider>(context);
    final dataProvider = Provider.of<DataProvider>(context);
    final settings = Provider.of<SettingsProvider>(context);

    double totalWeight = 0;
    double totalPaid = 0;
    double totalProfit = 0;

    for (var g in dataProvider.goldList) {
      totalWeight += g.quantity;
      totalPaid += g.purchasePricePerUnit * g.quantity;
      final currentPrice = priceProvider.prices[g.type]?.currentPrice ?? 0;
      int days = Calculator.daysBetween(g.purchaseDate, DateTime.now());
      double profit = Calculator.calculateProfit(
        currentPrice: currentPrice,
        purchasePrice: g.purchasePricePerUnit,
        quantity: g.quantity,
        paidAmount: g.purchasePricePerUnit * g.quantity,
        interestRate: settings.bankInterestRate,
        days: days,
      );
      totalProfit += profit;
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('طلای آب شده'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: Icon(Icons.add),
            onPressed: () => _showAddEditGoldDialog(context, null),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: EdgeInsets.all(8),
            child: Row(
              children: [
                Expanded(child: _buildSummaryCard('وزن کل', '${totalWeight.toStringAsFixed(3)} گرم', Colors.amber)),
                Expanded(child: _buildSummaryCard('مبلغ پرداختی', NumberFormat('#,###').format(totalPaid), Colors.blue)),
                Expanded(child: _buildSummaryCard('سود خالص', NumberFormat('#,###').format(totalProfit), totalProfit >= 0 ? Colors.green : Colors.red)),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: dataProvider.goldList.length,
              itemBuilder: (ctx, index) {
                final g = dataProvider.goldList[index];
                final currentPrice = priceProvider.prices[g.type]?.currentPrice ?? 0;
                final paid = g.purchasePricePerUnit * g.quantity;
                final currentValue = currentPrice * g.quantity;
                final days = Calculator.daysBetween(g.purchaseDate, DateTime.now());
                final profit = Calculator.calculateProfit(
                  currentPrice: currentPrice,
                  purchasePrice: g.purchasePricePerUnit,
                  quantity: g.quantity,
                  paidAmount: paid,
                  interestRate: settings.bankInterestRate,
                  days: days,
                );

                return Card(
                  margin: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: ListTile(
                    title: Text('${g.quantity} گرم - خرید در ${DateFormat.yMd().format(g.purchaseDate)}'),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('فی خرید: ${NumberFormat('#,###').format(g.purchasePricePerUnit)}'),
                        Text('ارزش فعلی: ${NumberFormat('#,###').format(currentValue)}'),
                        Text('سود خالص: ${NumberFormat('#,###').format(profit)} (${profit >= 0 ? '+' : ''}${profit.toStringAsFixed(0)})',
                            style: TextStyle(color: profit >= 0 ? Colors.green : Colors.red)),
                      ],
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: Icon(Icons.edit, size: 20),
                          onPressed: () => _showAddEditGoldDialog(context, g),
                        ),
                        IconButton(
                          icon: Icon(Icons.delete, size: 20, color: Colors.red),
                          onPressed: () {
                            showDialog(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: Text('تأیید حذف'),
                                content: Text('آیا از حذف این آیتم اطمینان دارید؟'),
                                actions: [
                                  TextButton(onPressed: () => Navigator.pop(ctx), child: Text('لغو')),
                                  TextButton(
                                    onPressed: () {
                                      dataProvider.deleteGold(g);
                                      Navigator.pop(ctx);
                                    },
                                    child: Text('حذف', style: TextStyle(color: Colors.red)),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard(String label, String value, Color color) {
    return Card(
      child: Padding(
        padding: EdgeInsets.all(8),
        child: Column(
          children: [
            Text(label, style: TextStyle(fontSize: 12)),
            SizedBox(height: 4),
            Text(value, style: TextStyle(fontWeight: FontWeight.bold, color: color)),
          ],
        ),
      ),
    );
  }

  void _showAddEditGoldDialog(BuildContext context, GoldTransaction? existing) {
    final formKey = GlobalKey<FormState>();
    DateTime selectedDate = existing?.purchaseDate ?? DateTime.now();
    double price = existing?.purchasePricePerUnit ?? 0;
    double weight = existing?.quantity ?? 0;
    String desc = existing?.description ?? '';

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(existing == null ? 'افزودن طلای آب شده' : 'ویرایش'),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                children: [
                  TextFormField(
                    initialValue: price.toString(),
                    decoration: InputDecoration(labelText: 'فی خرید (تومان)'),
                    keyboardType: TextInputType.number,
                    validator: (v) => v!.isEmpty ? 'لطفاً وارد کنید' : null,
                    onSaved: (v) => price = double.parse(v!),
                  ),
                  TextFormField(
                    initialValue: weight.toString(),
                    decoration: InputDecoration(labelText: 'وزن (گرم)'),
                    keyboardType: TextInputType.number,
                    validator: (v) => v!.isEmpty ? 'لطفاً وارد کنید' : null,
                    onSaved: (v) => weight = double.parse(v!),
                  ),
                  ListTile(
                    title: Text('تاریخ خرید: ${DateFormat.yMd().format(selectedDate)}'),
                    trailing: Icon(Icons.calendar_today),
                    onTap: () async {
                      final date = await showDatePicker(
                        context: context,
                        initialDate: selectedDate,
                        firstDate: DateTime(2000),
                        lastDate: DateTime.now(),
                      );
                      if (date != null) selectedDate = date;
                    },
                  ),
                  TextFormField(
                    initialValue: desc,
                    decoration: InputDecoration(labelText: 'توضیحات'),
                    onSaved: (v) => desc = v ?? '',
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text('لغو')),
            ElevatedButton(
              onPressed: () {
                if (formKey.currentState!.validate()) {
                  formKey.currentState!.save();
                  final newTrans = GoldTransaction(
                    id: existing?.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
                    type: 'gold_18',
                    purchaseDate: selectedDate,
                    purchasePricePerUnit: price,
                    quantity: weight,
                    description: desc,
                    isGold: true,
                  );
                  if (existing == null) {
                    Provider.of<DataProvider>(context, listen: false).addGold(newTrans);
                  } else {
                    existing.purchaseDate = selectedDate;
                    existing.purchasePricePerUnit = price;
                    existing.quantity = weight;
                    existing.description = desc;
                    Provider.of<DataProvider>(context, listen: false).updateGold(existing);
                  }
                  Navigator.pop(ctx);
                }
              },
              child: Text('ذخیره'),
            ),
          ],
        );
      },
    );
  }
}

class CoinListScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final priceProvider = Provider.of<PriceProvider>(context);
    final dataProvider = Provider.of<DataProvider>(context);
    final settings = Provider.of<SettingsProvider>(context);

    int totalCoinCount = 0;
    int rubCount = 0;
    int nimCount = 0;
    int tamamCount = 0; // coin_new + coin_old
    double totalPaid = 0;

    for (var c in dataProvider.coinList) {
      totalCoinCount += c.count;
      if (c.coinType == 'coin_quarter') rubCount += c.count;
      else if (c.coinType == 'coin_half') nimCount += c.count;
      else if (c.coinType == 'coin_new' || c.coinType == 'coin_old') tamamCount += c.count;
      totalPaid += c.purchasePricePerUnit * c.count;
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('سکه‌ها'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: Icon(Icons.add),
            onPressed: () => _showAddEditCoinDialog(context, null),
          ),
        ],
      ),
      body: Column(
        children: [
          Card(
            margin: EdgeInsets.all(8),
            child: Padding(
              padding: EdgeInsets.all(12),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildStatColumn('ربع', rubCount.toString()),
                      _buildStatColumn('نیم', nimCount.toString()),
                      _buildStatColumn('تمام', tamamCount.toString()),
                    ],
                  ),
                  Divider(),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('تعداد کل: ', style: TextStyle(fontWeight: FontWeight.bold)),
                      Text(totalCoinCount.toString(), style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Card(
            margin: EdgeInsets.symmetric(horizontal: 8),
            child: ListTile(
              title: Text('مجموع مبلغ پرداختی سکه‌ها'),
              trailing: Text(NumberFormat('#,###').format(totalPaid), style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: dataProvider.coinList.length,
              itemBuilder: (ctx, index) {
                final c = dataProvider.coinList[index];
                final currentPrice = priceProvider.prices[c.coinType]?.currentPrice ?? 0;
                final paid = c.purchasePricePerUnit * c.count;
                final currentValue = currentPrice * c.count;
                final days = Calculator.daysBetween(c.purchaseDate, DateTime.now());
                final profit = Calculator.calculateProfit(
                  currentPrice: currentPrice,
                  purchasePrice: c.purchasePricePerUnit,
                  quantity: c.count.toDouble(),
                  paidAmount: paid,
                  interestRate: settings.bankInterestRate,
                  days: days,
                );

                return Card(
                  margin: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: ListTile(
                    title: Text('${c.count} ${_getCoinName(c.coinType)} - خرید در ${DateFormat.yMd().format(c.purchaseDate)}'),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('فی خرید: ${NumberFormat('#,###').format(c.purchasePricePerUnit)}'),
                        Text('ارزش فعلی: ${NumberFormat('#,###').format(currentValue)}'),
                        Text('سود خالص: ${NumberFormat('#,###').format(profit)} (${profit >= 0 ? '+' : ''}${profit.toStringAsFixed(0)})',
                            style: TextStyle(color: profit >= 0 ? Colors.green : Colors.red)),
                        if (c.description.isNotEmpty) Text(c.description, style: TextStyle(fontSize: 12, color: Colors.grey)),
                      ],
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: Icon(Icons.edit, size: 20),
                          onPressed: () => _showAddEditCoinDialog(context, c),
                        ),
                        IconButton(
                          icon: Icon(Icons.delete, size: 20, color: Colors.red),
                          onPressed: () {
                            showDialog(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: Text('تأیید حذف'),
                                content: Text('آیا از حذف این آیتم اطمینان دارید؟'),
                                actions: [
                                  TextButton(onPressed: () => Navigator.pop(ctx), child: Text('لغو')),
                                  TextButton(
                                    onPressed: () {
                                      dataProvider.deleteCoin(c);
                                      Navigator.pop(ctx);
                                    },
                                    child: Text('حذف', style: TextStyle(color: Colors.red)),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  String _getCoinName(String type) {
    switch (type) {
      case 'coin_new': return 'سکه تمام (امامی)';
      case 'coin_old': return 'سکه تمام (قدیم)';
      case 'coin_half': return 'نیم سکه';
      case 'coin_quarter': return 'ربع سکه';
      case 'coin_1g': return 'سکه یک گرمی';
      default: return type;
    }
  }

  Widget _buildStatColumn(String label, String value) {
    return Column(
      children: [
        Text(label, style: TextStyle(fontWeight: FontWeight.bold)),
        SizedBox(height: 4),
        Text(value, style: TextStyle(fontSize: 16)),
      ],
    );
  }

  void _showAddEditCoinDialog(BuildContext context, CoinTransaction? existing) {
    final formKey = GlobalKey<FormState>();
    DateTime selectedDate = existing?.purchaseDate ?? DateTime.now();
    double price = existing?.purchasePricePerUnit ?? 0;
    int count = existing?.count ?? 1;
    String desc = existing?.description ?? '';
    String coinType = existing?.coinType ?? 'coin_new';

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(existing == null ? 'افزودن سکه' : 'ویرایش'),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                children: [
                  DropdownButtonFormField<String>(
                    value: coinType,
                    items: [
                      DropdownMenuItem(value: 'coin_new', child: Text('تمام (امامی)')),
                      DropdownMenuItem(value: 'coin_old', child: Text('تمام (قدیم)')),
                      DropdownMenuItem(value: 'coin_half', child: Text('نیم سکه')),
                      DropdownMenuItem(value: 'coin_quarter', child: Text('ربع سکه')),
                      DropdownMenuItem(value: 'coin_1g', child: Text('سکه یک گرمی')),
                    ],
                    onChanged: (v) => coinType = v!,
                    decoration: InputDecoration(labelText: 'نوع سکه'),
                  ),
                  TextFormField(
                    initialValue: price.toString(),
                    decoration: InputDecoration(labelText: 'فی خرید (تومان)'),
                    keyboardType: TextInputType.number,
                    validator: (v) => v!.isEmpty ? 'لطفاً وارد کنید' : null,
                    onSaved: (v) => price = double.parse(v!),
                  ),
                  TextFormField(
                    initialValue: count.toString(),
                    decoration: InputDecoration(labelText: 'تعداد'),
                    keyboardType: TextInputType.number,
                    validator: (v) => v!.isEmpty ? 'لطفاً وارد کنید' : null,
                    onSaved: (v) => count = int.parse(v!),
                  ),
                  ListTile(
                    title: Text('تاریخ خرید: ${DateFormat.yMd().format(selectedDate)}'),
                    trailing: Icon(Icons.calendar_today),
                    onTap: () async {
                      final date = await showDatePicker(
                        context: context,
                        initialDate: selectedDate,
                        firstDate: DateTime(2000),
                        lastDate: DateTime.now(),
                      );
                      if (date != null) selectedDate = date;
                    },
                  ),
                  TextFormField(
                    initialValue: desc,
                    decoration: InputDecoration(labelText: 'توضیحات'),
                    onSaved: (v) => desc = v ?? '',
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text('لغو')),
            ElevatedButton(
              onPressed: () {
                if (formKey.currentState!.validate()) {
                  formKey.currentState!.save();
                  final newTrans = CoinTransaction(
                    id: existing?.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
                    coinType: coinType,
                    purchaseDate: selectedDate,
                    purchasePricePerUnit: price,
                    count: count,
                    description: desc,
                  );
                  if (existing == null) {
                    Provider.of<DataProvider>(context, listen: false).addCoin(newTrans);
                  } else {
                    existing.coinType = coinType;
                    existing.purchaseDate = selectedDate;
                    existing.purchasePricePerUnit = price;
                    existing.count = count;
                    existing.description = desc;
                    Provider.of<DataProvider>(context, listen: false).updateCoin(existing);
                  }
                  Navigator.pop(ctx);
                }
              },
              child: Text('ذخیره'),
            ),
          ],
        );
      },
    );
  }
}

class ChartsScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final priceProvider = Provider.of<PriceProvider>(context);
    final dataProvider = Provider.of<DataProvider>(context);
    final settings = Provider.of<SettingsProvider>(context);

    final goldList = dataProvider.goldList;
    final coinList = dataProvider.coinList;

    // محاسبه ارزش طلا
    double totalGoldValue = 0;
    for (var g in goldList) {
      totalGoldValue += (priceProvider.prices[g.type]?.currentPrice ?? 0) * g.quantity;
    }

    // محاسبه ارزش سکه به تفکیک
    double totalCoinRob = 0; // ربع
    double totalCoinNim = 0; // نیم
    double totalCoinTamam = 0; // تمام (جدید و قدیم)
    double totalCoin1g = 0; // یک گرمی
    for (var c in coinList) {
      final currentPrice = priceProvider.prices[c.coinType]?.currentPrice ?? 0;
      final value = currentPrice * c.count;
      if (c.coinType == 'coin_quarter') totalCoinRob += value;
      else if (c.coinType == 'coin_half') totalCoinNim += value;
      else if (c.coinType == 'coin_new' || c.coinType == 'coin_old') totalCoinTamam += value;
      else if (c.coinType == 'coin_1g') totalCoin1g += value;
    }

    final totalAssets = totalGoldValue + totalCoinRob + totalCoinNim + totalCoinTamam + totalCoin1g;

    // --- نمودار دایره‌ای ---
    List<PieChartSectionData> pieSections = [];
    if (totalGoldValue > 0) {
      pieSections.add(PieChartSectionData(
        value: totalGoldValue,
        title: 'طلای آب شده\n${((totalGoldValue / totalAssets) * 100).toStringAsFixed(1)}%',
        color: Colors.blue, // رنگ آبی برای طلا
        radius: 50,
      ));
    }
    if (totalCoinRob > 0) {
      pieSections.add(PieChartSectionData(
        value: totalCoinRob,
        title: 'ربع سکه\n${((totalCoinRob / totalAssets) * 100).toStringAsFixed(1)}%',
        color: Colors.amber,
        radius: 50,
      ));
    }
    if (totalCoinNim > 0) {
      pieSections.add(PieChartSectionData(
        value: totalCoinNim,
        title: 'نیم سکه\n${((totalCoinNim / totalAssets) * 100).toStringAsFixed(1)}%',
        color: Colors.green,
        radius: 50,
      ));
    }
    if (totalCoinTamam > 0) {
      pieSections.add(PieChartSectionData(
        value: totalCoinTamam,
        title: 'تمام سکه\n${((totalCoinTamam / totalAssets) * 100).toStringAsFixed(1)}%',
        color: Colors.purple,
        radius: 50,
      ));
    }
    if (totalCoin1g > 0) {
      pieSections.add(PieChartSectionData(
        value: totalCoin1g,
        title: 'یک گرمی\n${((totalCoin1g / totalAssets) * 100).toStringAsFixed(1)}%',
        color: Colors.orange,
        radius: 50,
      ));
    }

    // --- نمودار میله‌ای سود هر خرید ---
    List<BarChartGroupData> barGroups = [];
    int index = 0;
    for (var g in goldList) {
      final currentPrice = priceProvider.prices[g.type]?.currentPrice ?? 0;
      final paid = g.purchasePricePerUnit * g.quantity;
      final days = Calculator.daysBetween(g.purchaseDate, DateTime.now());
      final profit = Calculator.calculateProfit(
        currentPrice: currentPrice,
        purchasePrice: g.purchasePricePerUnit,
        quantity: g.quantity,
        paidAmount: paid,
        interestRate: settings.bankInterestRate,
        days: days,
      );
      barGroups.add(
        BarChartGroupData(x: index++, barRods: [
          BarChartRodData(toY: profit, color: profit >= 0 ? Colors.green : Colors.red, width: 10),
        ]),
      );
    }
    for (var c in coinList) {
      final currentPrice = priceProvider.prices[c.coinType]?.currentPrice ?? 0;
      final paid = c.purchasePricePerUnit * c.count;
      final days = Calculator.daysBetween(c.purchaseDate, DateTime.now());
      final profit = Calculator.calculateProfit(
        currentPrice: currentPrice,
        purchasePrice: c.purchasePricePerUnit,
        quantity: c.count.toDouble(),
        paidAmount: paid,
        interestRate: settings.bankInterestRate,
        days: days,
      );
      barGroups.add(
        BarChartGroupData(x: index++, barRods: [
          BarChartRodData(toY: profit, color: profit >= 0 ? Colors.green : Colors.red, width: 10),
        ]),
      );
    }

    // --- نمودار روند ارزش کل دارایی (با استفاده از قیمت دیروز و امروز و اولین خرید) ---
    // محاسبه ارزش کل با قیمت دیروز (yesterday_avg)
    double totalAssetsYesterday = 0;
    for (var g in goldList) {
      final yesterdayPrice = priceProvider.prices[g.type]?.yesterdayAvg ?? 0;
      totalAssetsYesterday += yesterdayPrice * g.quantity;
    }
    for (var c in coinList) {
      final yesterdayPrice = priceProvider.prices[c.coinType]?.yesterdayAvg ?? 0;
      totalAssetsYesterday += yesterdayPrice * c.count;
    }

    // ارزش کل در تاریخ اولین خرید (با فرض اینکه اولین خرید قدیمی‌ترین تاریخ باشد)
    DateTime firstPurchaseDate = DateTime.now();
    double firstPurchaseTotal = 0;
    // پیدا کردن اولین تاریخ
    for (var g in goldList) {
      if (g.purchaseDate.isBefore(firstPurchaseDate)) firstPurchaseDate = g.purchaseDate;
    }
    for (var c in coinList) {
      if (c.purchaseDate.isBefore(firstPurchaseDate)) firstPurchaseDate = c.purchaseDate;
    }
    // محاسبه مجموع مبالغ پرداختی در آن تاریخ (فقط خریدهایی که در آن تاریخ یا قبل از آن انجام شده)
    // ساده‌سازی: از تمام خریدها استفاده می‌کنیم چون خریدهای بعد از آن تاریخ در آن زمان وجود نداشته‌اند.
    // در این نسخه ساده، فرض می‌کنیم که اولین خرید تنها خرید در آن تاریخ است.
    // برای دقیق‌تر شدن، می‌توانیم فقط خریدهایی را در نظر بگیریم که در آن تاریخ یا قبل از آن هستند.
    // اما برای سادگی، از مجموع کل مبالغ پرداختی استفاده می‌کنیم (که با واقعیت تطابق ندارد).
    // بهتر است از مجموع مبالغ پرداختی همان خریدهای قبل از آن تاریخ استفاده کنیم.
    // ما اینجا یک پیاده‌سازی ساده انجام می‌دهیم: از اولین خرید به عنوان یک نقطه استفاده می‌کنیم.
    // ارزش آن خرید در آن تاریخ = مبلغ پرداختی آن خرید (چون قیمت همان لحظه را ندارد)
    // اما اگر چند خرید در آن تاریخ باشند، مجموع مبالغ پرداختی آنها.
    double firstPurchaseValue = 0;
    for (var g in goldList) {
      if (g.purchaseDate == firstPurchaseDate) {
        firstPurchaseValue += g.purchasePricePerUnit * g.quantity;
      }
    }
    for (var c in coinList) {
      if (c.purchaseDate == firstPurchaseDate) {
        firstPurchaseValue += c.purchasePricePerUnit * c.count;
      }
    }

    // ایجاد نقاط برای نمودار خطی (سه نقطه)
    List<FlSpot> lineSpots = [];
    lineSpots.add(FlSpot(0, firstPurchaseValue)); // نقطه اول (روز 0 = اولین خرید)
    // محاسبه فاصله روزها از اولین خرید تا دیروز و امروز
    int daysToYesterday = Calculator.daysBetween(firstPurchaseDate, DateTime.now().subtract(Duration(days: 1)));
    int daysToToday = Calculator.daysBetween(firstPurchaseDate, DateTime.now());
    lineSpots.add(FlSpot(daysToYesterday.toDouble(), totalAssetsYesterday));
    lineSpots.add(FlSpot(daysToToday.toDouble(), totalAssets));

    return Scaffold(
      appBar: AppBar(title: Text('نمودارها'), centerTitle: true),
      body: ListView(
        padding: EdgeInsets.all(16),
        children: [
          Text('نمودار توزیع دارایی', style: Theme.of(context).textTheme.titleMedium),
          SizedBox(height: 10),
          Container(
            height: 250,
            child: PieChart(
              PieChartData(
                sections: pieSections,
                sectionsSpace: 2,
                centerSpaceRadius: 40,
              ),
            ),
          ),
          SizedBox(height: 20),

          Text('نمودار سود/زیان هر خرید', style: Theme.of(context).textTheme.titleMedium),
          SizedBox(height: 10),
          Container(
            height: 300,
            child: BarChart(
              BarChartData(
                barGroups: barGroups,
                titlesData: FlTitlesData(show: false),
                borderData: FlBorderData(show: false),
                gridData: FlGridData(show: false),
              ),
            ),
          ),
          SizedBox(height: 20),

          Text('روند ارزش کل دارایی', style: Theme.of(context).textTheme.titleMedium),
          SizedBox(height: 10),
          Container(
            height: 200,
            child: LineChart(
              LineChartData(
                lineBarsData: [
                  LineChartBarData(
                    spots: lineSpots,
                    isCurved: true,
                    color: Colors.blue,
                    barWidth: 3,
                    isStrokeCapRound: true,
                    dotData: FlDotData(show: true),
                    belowBarData: BarAreaData(show: false),
                  ),
                ],
                titlesData: FlTitlesData(
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) {
                        if (value == 0) return Text('اولین خرید');
                        if (value == daysToYesterday) return Text('دیروز');
                        if (value == daysToToday) return Text('امروز');
                        return Text('');
                      },
                    ),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 40,
                      getTitlesWidget: (value, meta) {
                        return Text(NumberFormat.compact().format(value));
                      },
                    ),
                  ),
                ),
                borderData: FlBorderData(show: true),
                gridData: FlGridData(show: true),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class SettingsScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<SettingsProvider>(context);
    final priceProvider = Provider.of<PriceProvider>(context);

    return Scaffold(
      appBar: AppBar(title: Text('تنظیمات'), centerTitle: true),
      body: ListView(
        padding: EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                children: [
                  Text('نرخ سود بانکی', style: Theme.of(context).textTheme.titleSmall),
                  Slider(
                    value: settings.bankInterestRate,
                    min: 0,
                    max: 50,
                    divisions: 100,
                    label: settings.bankInterestRate.toStringAsFixed(1) + '%',
                    onChanged: (v) => settings.setBankInterestRate(v),
                  ),
                  Text('${settings.bankInterestRate.toStringAsFixed(1)}%'),
                ],
              ),
            ),
          ),
          Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                children: [
                  Text('فاصله به‌روزرسانی خودکار (ثانیه)', style: Theme.of(context).textTheme.titleSmall),
                  Slider(
                    value: settings.autoUpdateInterval.toDouble(),
                    min: 30, // حداقل ۳۰ ثانیه
                    max: 600, // حداکثر ۶۰۰ ثانیه
                    divisions: (600 - 30) ~/ 10, // تقریبا 57 قسمت
                    label: settings.autoUpdateInterval.toString(),
                    onChanged: (v) {
                      settings.setAutoUpdateInterval(v.toInt());
                      priceProvider.setAutoUpdateInterval(v.toInt());
                    },
                  ),
                  Text('${settings.autoUpdateInterval} ثانیه'),
                ],
              ),
            ),
          ),
          Card(
            child: ListTile(
              title: Text('به‌روزرسانی دستی قیمت‌ها'),
              trailing: Icon(Icons.refresh),
              onTap: () => priceProvider.fetchPrices(),
            ),
          ),
          Card(
            child: ListTile(
              title: Text('نسخه ۱.۰.۰'),
              subtitle: Text('طراحی شده با فلاتر'),
            ),
          ),
        ],
      ),
    );
  }
}

// -------------------- Main App --------------------
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final appDocumentDir = await path_provider.getApplicationDocumentsDirectory();
  Hive.init(appDocumentDir.path);
  Hive.registerAdapter(GoldTransactionAdapter());
  Hive.registerAdapter(CoinTransactionAdapter());

  final goldBox = await Hive.openBox<GoldTransaction>('goldTransactions');
  final coinBox = await Hive.openBox<CoinTransaction>('coinTransactions');
  final prefs = await SharedPreferences.getInstance();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => PriceProvider(prefs)),
        ChangeNotifierProvider(create: (_) => SettingsProvider(prefs)),
        ChangeNotifierProvider(create: (_) => DataProvider(goldBox: goldBox, coinBox: coinBox)),
      ],
      child: MaterialApp(
        title: 'مدیریت دارایی طلا و سکه',
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.amber),
          fontFamily: 'Vazir', // در صورت وجود فونت
        ),
        home: MainScreen(),
        debugShowCheckedModeBanner: false,
      ),
    ),
  );
}

class MainScreen extends StatefulWidget {
  @override
  _MainScreenState createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;

  final List<Widget> _screens = [
    HomeScreen(),
    GoldListScreen(),
    CoinListScreen(),
    ChartsScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_selectedIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) => setState(() => _selectedIndex = index),
        destinations: [
          NavigationDestination(icon: Icon(Icons.home), label: 'خانه'),
          NavigationDestination(icon: Icon(Icons.monetization_on), label: 'طلای آب شده'),
          NavigationDestination(icon: Icon(Icons.account_balance_wallet), label: 'سکه'),
          NavigationDestination(icon: Icon(Icons.bar_chart), label: 'نمودارها'),
          NavigationDestination(icon: Icon(Icons.settings), label: 'تنظیمات'),
        ],
      ),
    );
  }
}