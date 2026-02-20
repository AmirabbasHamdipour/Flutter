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
  String type; // gold18, gold24, ons, dollar
  @HiveField(2)
  DateTime purchaseDate;
  @HiveField(3)
  double purchasePricePerUnit; // فی خرید
  @HiveField(4)
  double quantity; // وزن بر حسب گرم
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
  String coinType; // sekke, bahar, sekkenim, sekkerob
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

// -------------------- API Service --------------------
class ApiService {
  static const String baseUrl = 'https://tweeter.runflare.run/price/';

  static Future<double?> fetchPrice(String obj) async {
    try {
      final response = await http.get(Uri.parse('$baseUrl$obj'));
      if (response.statusCode == 200) {
        return double.tryParse(response.body);
      }
    } catch (e) {
      print('Error fetching $obj: $e');
    }
    return null;
  }

  // دریافت همه قیمت‌های مورد نیاز
  static Future<Map<String, double>> fetchAllPrices() async {
    final types = ['gold18', 'gold24', 'ons', 'dollar', 'sekke', 'sekkenim', 'sekkerob', 'bahar'];
    Map<String, double> prices = {};
    for (String type in types) {
      final price = await fetchPrice(type);
      if (price != null) prices[type] = price;
    }
    return prices;
  }
}

// -------------------- Providers --------------------
class PriceProvider extends ChangeNotifier {
  Map<String, double> _prices = {};
  Map<String, double> _lastSavedPrices = {};
  DateTime _lastUpdated = DateTime(2000); // تاریخ پیش‌فرض قدیمی
  Timer? _timer;
  final SharedPreferences _prefs;

  static const List<String> _priceKeys = ['gold18', 'gold24', 'ons', 'dollar', 'sekke', 'sekkenim', 'sekkerob', 'bahar'];

  Map<String, double> get prices => UnmodifiableMapView(_prices);
  DateTime get lastUpdated => _lastUpdated;

  PriceProvider(this._prefs) {
    _loadSavedPrices();
    fetchPrices();
    startAutoUpdate();
  }

  void _loadSavedPrices() {
    _lastSavedPrices = {};
    for (var key in _priceKeys) {
      double? value = _prefs.getDouble('price_$key');
      if (value != null) {
        _lastSavedPrices[key] = value;
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

  Future<void> _savePrices(Map<String, double> prices) async {
    for (var entry in prices.entries) {
      await _prefs.setDouble('price_${entry.key}', entry.value);
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
      // اگر نتواستیم دریافت کنیم، مقادیر قبلی را نمایش می‌دهیم (هم‌اکنون در _prices هستند)
      // فقط اطلاع‌رسانی می‌کنیم تا زمان به‌روزرسانی تغییر نکند
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
        type: 'gold18',
        purchaseDate: DateTime(2025, 1, 2),
        purchasePricePerUnit: 52518583,
        quantity: 100,
        description: '',
        isGold: true,
      ),
      GoldTransaction(
        id: DateTime.now().millisecondsSinceEpoch.toString() + '2',
        type: 'gold18',
        purchaseDate: DateTime(2025, 2, 9),
        purchasePricePerUnit: 65792511,
        quantity: 61.195,
        description: '',
        isGold: true,
      ),
      GoldTransaction(
        id: DateTime.now().millisecondsSinceEpoch.toString() + '3',
        type: 'gold18',
        purchaseDate: DateTime(2025, 4, 13),
        purchasePricePerUnit: 76180802,
        quantity: 50,
        description: '',
        isGold: true,
      ),
      GoldTransaction(
        id: DateTime.now().millisecondsSinceEpoch.toString() + '4',
        type: 'gold18',
        purchaseDate: DateTime(2025, 10, 6),
        purchasePricePerUnit: 105960571,
        quantity: 100,
        description: '',
        isGold: true,
      ),
      GoldTransaction(
        id: DateTime.now().millisecondsSinceEpoch.toString() + '5',
        type: 'gold18',
        purchaseDate: DateTime(2025, 11, 10),
        purchasePricePerUnit: 105730000,
        quantity: 60,
        description: '',
        isGold: true,
      ),
      GoldTransaction(
        id: DateTime.now().millisecondsSinceEpoch.toString() + '6',
        type: 'gold18',
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
        coinType: 'sekkerob',
        purchaseDate: DateTime(2023, 1, 17),
        purchasePricePerUnit: 70500000,
        count: 3,
        description: 'خرید از بورس کالای کارگزاری آگاه',
      ),
      CoinTransaction(
        id: DateTime.now().millisecondsSinceEpoch.toString() + 'c2',
        coinType: 'sekke',
        purchaseDate: DateTime(2025, 1, 1),
        purchasePricePerUnit: 560000000,
        count: 2,
        description: 'خرید از زهرا',
      ),
      CoinTransaction(
        id: DateTime.now().millisecondsSinceEpoch.toString() + 'c3',
        coinType: 'sekkerob',
        purchaseDate: DateTime(2025, 1, 1),
        purchasePricePerUnit: 174000000,
        count: 1,
        description: 'خرید از زهرا',
      ),
      CoinTransaction(
        id: DateTime.now().millisecondsSinceEpoch.toString() + 'c4',
        coinType: 'sekke',
        purchaseDate: DateTime(2025, 9, 8),
        purchasePricePerUnit: 832224932,
        count: 6,
        description: 'خرید از مرکز مبادلات سکه و ارز',
      ),
      CoinTransaction(
        id: DateTime.now().millisecondsSinceEpoch.toString() + 'c5',
        coinType: 'sekkenim',
        purchaseDate: DateTime(2025, 9, 8),
        purchasePricePerUnit: 441195425,
        count: 10,
        description: 'خرید از مرکز مبادلات سکه و ارز',
      ),
      CoinTransaction(
        id: DateTime.now().millisecondsSinceEpoch.toString() + 'c6',
        coinType: 'sekkerob',
        purchaseDate: DateTime(2025, 9, 8),
        purchasePricePerUnit: 257758617,
        count: 14,
        description: 'خرید از مرکز مبادلات سکه و ارز',
      ),
      CoinTransaction(
        id: DateTime.now().millisecondsSinceEpoch.toString() + 'c7',
        coinType: 'sekkenim',
        purchaseDate: DateTime(2025, 11, 12),
        purchasePricePerUnit: 575585000,
        count: 1,
        description: 'خرید از مرکز مبادلات کاربری مریم',
      ),
      CoinTransaction(
        id: DateTime.now().millisecondsSinceEpoch.toString() + 'c8',
        coinType: 'sekkerob',
        purchaseDate: DateTime(2025, 11, 12),
        purchasePricePerUnit: 327850000,
        count: 2,
        description: 'خرید از مرکز مبادلات کابری مریم',
      ),
      CoinTransaction(
        id: DateTime.now().millisecondsSinceEpoch.toString() + 'c9',
        coinType: 'sekke',
        purchaseDate: DateTime(2026, 2, 15),
        purchasePricePerUnit: 1930000000,
        count: 4,
        description: 'خرید از علی بابت پول ماشین',
      ),
      CoinTransaction(
        id: DateTime.now().millisecondsSinceEpoch.toString() + 'c10',
        coinType: 'sekkerob',
        purchaseDate: DateTime(2026, 2, 15),
        purchasePricePerUnit: 525000000,
        count: 6,
        description: 'خرید از علی بابت پول ماشین',
      ),
      CoinTransaction(
        id: DateTime.now().millisecondsSinceEpoch.toString() + 'c11',
        coinType: 'sekkenim',
        purchaseDate: DateTime(2026, 2, 15),
        purchasePricePerUnit: 970000000,
        count: 3,
        description: 'خرید از علی بابت پول ماشین',
      ),
    ];
    coinBox.addAll(coins);
  }

  // CRUD for Gold
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

  // CRUD for Coin
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

    // محاسبات طلا
    double totalGoldValue = 0;
    double totalGoldPaid = 0;
    double totalGoldProfit = 0;
    for (var g in dataProvider.goldList) {
      final currentPrice = priceProvider.prices[g.type] ?? 0;
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

    // محاسبات سکه
    double totalCoinValue = 0;
    double totalCoinPaid = 0;
    double totalCoinProfit = 0;
    for (var c in dataProvider.coinList) {
      final currentPrice = priceProvider.prices[c.coinType] ?? 0;
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
            // کارت اول: مجموع دارایی‌ها
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
                        _buildSummaryItem(context, 'طلای آب شده', NumberFormat('#,###').format(totalGoldValue), Colors.blue),
                        _buildSummaryItem(context, 'سکه', NumberFormat('#,###').format(totalCoinValue), Colors.blue),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(height: 16),
            // کارت دوم: سودها
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
                return Card(
                  child: Padding(
                    padding: EdgeInsets.all(8),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(_getPersianName(e.key), style: TextStyle(fontWeight: FontWeight.bold)),
                        Text(NumberFormat('#,###').format(e.value)),
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
      case 'gold18': return 'طلای ۱۸ عیار';
      case 'gold24': return 'طلای ۲۴ عیار';
      case 'ons': return 'اونس جهانی';
      case 'dollar': return 'دلار';
      case 'sekke': return 'سکه تمام (امامی)';
      case 'sekkenim': return 'نیم سکه';
      case 'sekkerob': return 'ربع سکه';
      case 'bahar': return 'سکه تمام (قدیم)';
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
      final currentPrice = priceProvider.prices[g.type] ?? 0;
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
          // کارت‌های خلاصه
          Padding(
            padding: EdgeInsets.all(8),
            child: Row(
              children: [
                Expanded(child: _buildSummaryCard('وزن کل', '${totalWeight.toStringAsFixed(3)} گرم', Colors.blue)),
                Expanded(child: _buildSummaryCard('مبلغ پرداختی', NumberFormat('#,###').format(totalPaid), Colors.blue)),
                //Expanded(child: _buildSummaryCard('سود خالص', NumberFormat('#,###').format(totalProfit), totalProfit >= 0 ? Colors.green : Colors.red)),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: dataProvider.goldList.length,
              itemBuilder: (ctx, index) {
                final g = dataProvider.goldList[index];
                final currentPrice = priceProvider.prices[g.type] ?? 0;
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
                    type: 'gold18',
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
    int tamamCount = 0;
    double totalPaid = 0;

    for (var c in dataProvider.coinList) {
      totalCoinCount += c.count;
      if (c.coinType == 'sekkerob') rubCount += c.count;
      else if (c.coinType == 'sekkenim') nimCount += c.count;
      else if (c.coinType == 'sekke' || c.coinType == 'bahar') tamamCount += c.count;
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
          // کارت آمار سکه‌ها
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
          // کارت مجموع پرداختی
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
                final currentPrice = priceProvider.prices[c.coinType] ?? 0;
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
      case 'sekke': return 'سکه تمام (امامی)';
      case 'bahar': return 'سکه تمام (قدیم)';
      case 'sekkenim': return 'نیم سکه';
      case 'sekkerob': return 'ربع سکه';
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
    String coinType = existing?.coinType ?? 'sekke';

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
                      DropdownMenuItem(value: 'sekke', child: Text('تمام (امامی)')),
                      DropdownMenuItem(value: 'bahar', child: Text('تمام (قدیم)')),
                      DropdownMenuItem(value: 'sekkenim', child: Text('نیم سکه')),
                      DropdownMenuItem(value: 'sekkerob', child: Text('ربع سکه')),
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
      totalGoldValue += (priceProvider.prices[g.type] ?? 0) * g.quantity;
    }

    // محاسبه ارزش سکه به تفکیک
    double totalCoinRob = 0;
    double totalCoinNim = 0;
    double totalCoinTamam = 0;
    for (var c in coinList) {
      final currentPrice = priceProvider.prices[c.coinType] ?? 0;
      final value = currentPrice * c.count;
      if (c.coinType == 'sekkerob') totalCoinRob += value;
      else if (c.coinType == 'sekkenim') totalCoinNim += value;
      else if (c.coinType == 'sekke' || c.coinType == 'bahar') totalCoinTamam += value;
    }

    final totalAssets = totalGoldValue + totalCoinRob + totalCoinNim + totalCoinTamam;

    // داده برای نمودار میله‌ای سود هر خرید (ترکیبی)
    List<BarChartGroupData> barGroups = [];
    int index = 0;
    for (var g in goldList) {
      final currentPrice = priceProvider.prices[g.type] ?? 0;
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
      final currentPrice = priceProvider.prices[c.coinType] ?? 0;
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

    // داده برای نمودار خطی قیمت‌های نسبی
    final priceEntries = priceProvider.prices.entries.toList();
    final maxPrice = priceEntries.map((e) => e.value).fold(0.0, max);
    final lineBarsData = priceEntries.map((entry) {
      return LineChartBarData(
        spots: [FlSpot(priceEntries.indexOf(entry).toDouble(), entry.value / maxPrice)],
        isCurved: true,
        color: _getColorForItem(entry.key),
        barWidth: 2,
        isStrokeCapRound: true,
        dotData: FlDotData(show: false),
        belowBarData: BarAreaData(show: false),
      );
    }).toList();

    return Scaffold(
      appBar: AppBar(title: Text('نمودارها'), centerTitle: true),
      body: ListView(
        padding: EdgeInsets.all(16),
        children: [
          // نمودار دایره‌ای توزیع دارایی
          Text('نمودار توزیع دارایی', style: Theme.of(context).textTheme.titleMedium),
          SizedBox(height: 10),
          Container(
            height: 250,
            child: PieChart(
              PieChartData(
                sections: _buildPieSections(totalGoldValue, totalCoinRob, totalCoinNim, totalCoinTamam, totalAssets),
                sectionsSpace: 2,
                centerSpaceRadius: 40,
                pieTouchData: PieTouchData(
                  touchCallback: (FlTouchEvent event, pieTouchResponse) {},
                ),
              ),
            ),
          ),
          SizedBox(height: 20),

          // نمودار میله‌ای سود هر خرید
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

          // نمودار خطی قیمت‌های نسبی
          Text('نمودار تغییرات نسبی قیمت‌ها', style: Theme.of(context).textTheme.titleMedium),
          SizedBox(height: 10),
          Container(
            height: 200,
            child: LineChart(
              LineChartData(
                lineBarsData: lineBarsData,
                titlesData: FlTitlesData(
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) {
                        int idx = value.toInt();
                        if (idx >= 0 && idx < priceEntries.length) {
                          return Text(_shortName(priceEntries[idx].key), style: TextStyle(fontSize: 10));
                        }
                        return Text('');
                      },
                    ),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                ),
                borderData: FlBorderData(show: false),
                gridData: FlGridData(show: false),
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<PieChartSectionData> _buildPieSections(
      double gold, double rob, double nim, double tamam, double total) {
    List<PieChartSectionData> sections = [];
    if (gold > 0) {
      sections.add(PieChartSectionData(
        value: gold,
        title: 'طلای آب شده\n${((gold / total) * 100).toStringAsFixed(1)}%',
        color: Colors.amber,
        radius: 50,
      ));
    }
    if (rob > 0) {
      sections.add(PieChartSectionData(
        value: rob,
        title: 'ربع سکه\n${((rob / total) * 100).toStringAsFixed(1)}%',
        color: Colors.blue,
        radius: 50,
      ));
    }
    if (nim > 0) {
      sections.add(PieChartSectionData(
        value: nim,
        title: 'نیم سکه\n${((nim / total) * 100).toStringAsFixed(1)}%',
        color: Colors.green,
        radius: 50,
      ));
    }
    if (tamam > 0) {
      sections.add(PieChartSectionData(
        value: tamam,
        title: 'تمام سکه\n${((tamam / total) * 100).toStringAsFixed(1)}%',
        color: Colors.purple,
        radius: 50,
      ));
    }
    return sections;
  }

  Color _getColorForItem(String key) {
    switch (key) {
      case 'gold18':
        return Colors.amber;
      case 'gold24':
        return Colors.orange;
      case 'ons':
        return Colors.yellow;
      case 'dollar':
        return Colors.green;
      case 'sekke':
        return Colors.blue;
      case 'bahar':
        return Colors.indigo;
      case 'sekkenim':
        return Colors.purple;
      case 'sekkerob':
        return Colors.pink;
      default:
        return Colors.grey;
    }
  }

  String _shortName(String key) {
    switch (key) {
      case 'gold18': return '18';
      case 'gold24': return '24';
      case 'ons': return 'اونس';
      case 'dollar': return 'دلار';
      case 'sekke': return 'تمام';
      case 'sekkenim': return 'نیم';
      case 'sekkerob': return 'ربع';
      case 'bahar': return 'قدیم';
      default: return '';
    }
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
                    min: 60,
                    max: 3600,
                    divisions: 59,
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

  // Hive initialization
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