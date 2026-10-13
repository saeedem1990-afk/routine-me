import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:intl/intl.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  tzdata.initializeTimeZones();
  await NotifyService.init();
  runApp(const RoutineMeApp());
}

class RoutineTask {
  RoutineTask({required this.id, required this.fa, required this.en, this.doneDates = const []});
  final String id;
  String fa;
  String en;
  List<String> doneDates;
  Map<String, dynamic> toJson() => {'id': id, 'fa': fa, 'en': en, 'doneDates': doneDates};
  factory RoutineTask.fromJson(Map<String, dynamic> j) => RoutineTask(
    id: j['id'] as String, fa: j['fa'] as String, en: j['en'] as String,
    doneDates: List<String>.from(j['doneDates'] ?? []));
}

class NotifyService {
  static final FlutterLocalNotificationsPlugin plugin = FlutterLocalNotificationsPlugin();
  static Future<void> init() async {
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: android);
    await plugin.initialize(settings);
  }
  static Future<void> schedule(int hour, int minute, bool persian) async {
    await plugin.cancel(1);
    const details = NotificationDetails(android: AndroidNotificationDetails(
      'routine_reminder', 'Routine reminders', channelDescription: 'Daily routine reminder',
      importance: Importance.high, priority: Priority.high));
    final now = tz.TZDateTime.now(tz.local);
    var next = tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    if (!next.isAfter(now)) next = next.add(const Duration(days: 1));
    await plugin.zonedSchedule(1, persian ? 'وقت روتین روزانه است' : 'Time for your daily routine',
      persian ? 'کارهای امروزت رو بررسی کن.' : 'Check off your tasks for today.', next, details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time);
  }
}

class RoutineMeApp extends StatefulWidget {
  const RoutineMeApp({super.key});
  @override State<RoutineMeApp> createState() => _RoutineMeAppState();
}
class _RoutineMeAppState extends State<RoutineMeApp> {
  bool _fa = true;
  ThemeMode _themeMode = ThemeMode.system;
  @override void initState() { super.initState(); _loadPrefs(); }
  Future<void> _loadPrefs() async {
    final p = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() { _fa = p.getBool('languageFa') ?? true; _themeMode = ThemeMode.values[p.getInt('themeMode') ?? 0]; });
  }
  Future<void> _setLanguage(bool value) async { final p = await SharedPreferences.getInstance(); await p.setBool('languageFa', value); setState(() => _fa = value); }
  Future<void> _setTheme(ThemeMode value) async { final p = await SharedPreferences.getInstance(); await p.setInt('themeMode', value.index); setState(() => _themeMode = value); }
  @override Widget build(BuildContext context) => MaterialApp(
    title: 'Routine Me', debugShowCheckedModeBanner: false,
    locale: Locale(_fa ? 'fa' : 'en'), supportedLocales: const [Locale('fa'), Locale('en')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    themeMode: _themeMode,
    theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff277da1)), useMaterial3: true),
    darkTheme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff4ea8de), brightness: Brightness.dark), useMaterial3: true),
    home: Directionality(textDirection: _fa ? TextDirection.rtl : TextDirection.ltr,
      child: HomePage(isFa: _fa, themeMode: _themeMode, onLanguage: _setLanguage, onTheme: _setTheme)));
}

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.isFa, required this.themeMode, required this.onLanguage, required this.onTheme});
  final bool isFa; final ThemeMode themeMode; final ValueChanged<bool> onLanguage; final ValueChanged<ThemeMode> onTheme;
  @override State<HomePage> createState() => _HomePageState();
}
class _HomePageState extends State<HomePage> {
  List<RoutineTask> tasks = [];
  bool loading = true;
  int tab = 0;
  DateTime selectedDay = DateTime.now();
  final TextEditingController faController = TextEditingController();
  final TextEditingController enController = TextEditingController();
  String get today => DateFormat('yyyy-MM-dd').format(DateTime.now());
  String get selectedKey => DateFormat('yyyy-MM-dd').format(selectedDay);
  String t(String fa, String en) => widget.isFa ? fa : en;
  @override void initState() { super.initState(); _loadTasks(); }
  @override void dispose() { faController.dispose(); enController.dispose(); super.dispose(); }
  Future<void> _loadTasks() async {
    final p = await SharedPreferences.getInstance(); final raw = p.getString('tasks');
    if (raw != null) { try { tasks = (jsonDecode(raw) as List).map((e) => RoutineTask.fromJson(Map<String,dynamic>.from(e))).toList(); } catch (_) {} }
    if (tasks.isEmpty && raw == null) {
      tasks = [RoutineTask(id:'1',fa:'مطالعه زبان',en:'Study English'), RoutineTask(id:'2',fa:'ورزش',en:'Exercise'), RoutineTask(id:'3',fa:'مطالعه کتاب',en:'Read a book')];
      await _save();
    }
    if (mounted) setState(() => loading = false);
  }
  Future<void> _save() async { final p = await SharedPreferences.getInstance(); await p.setString('tasks', jsonEncode(tasks.map((e) => e.toJson()).toList())); }
  bool _done(RoutineTask task, String day) => task.doneDates.contains(day);
  Future<void> _toggle(RoutineTask task, String day, bool value) async {
    setState(() { if (value) { if (!task.doneDates.contains(day)) task.doneDates.add(day); } else { task.doneDates.remove(day); } }); await _save();
  }
  Future<void> _editTask([RoutineTask? task]) async {
    faController.text = task?.fa ?? ''; enController.text = task?.en ?? '';
    final result = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: Text(task == null ? t('افزودن کار','Add a task') : t('ویرایش کار','Edit task')),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: faController, decoration: const InputDecoration(labelText: 'نام فارسی')),
        TextField(controller: enController, decoration: const InputDecoration(labelText: 'English name')),
      ]),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('انصراف','Cancel'))),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t('ذخیره','Save')))]));
    if (result != true || (faController.text.trim().isEmpty && enController.text.trim().isEmpty)) return;
    setState(() { if (task == null) { tasks.add(RoutineTask(id: DateTime.now().microsecondsSinceEpoch.toString(), fa: faController.text.trim().isEmpty ? enController.text.trim() : faController.text.trim(), en: enController.text.trim().isEmpty ? faController.text.trim() : enController.text.trim())); } else { task.fa = faController.text.trim().isEmpty ? task.en : faController.text.trim(); task.en = enController.text.trim().isEmpty ? task.fa : enController.text.trim(); } }); await _save();
  }
  Future<void> _delete(RoutineTask task) async { final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(title: Text(t('حذف کار؟','Delete task?')), content: Text(t('این کار و آمار آن حذف می‌شود.','This task and its history will be deleted.')), actions: [TextButton(onPressed:()=>Navigator.pop(ctx,false),child:Text(t('انصراف','Cancel'))), FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:Text(t('حذف','Delete')))])); if (ok == true) { setState(() => tasks.remove(task)); await _save(); } }
  int _totalDone(RoutineTask task) => task.doneDates.toSet().length;
  int _streak(RoutineTask task) { var d = DateTime.now(); if (!_done(task, DateFormat('yyyy-MM-dd').format(d))) d = d.subtract(const Duration(days:1)); int n=0; while (_done(task, DateFormat('yyyy-MM-dd').format(d))) { n++; d=d.subtract(const Duration(days:1)); } return n; }
  int _completedFor(String day) => tasks.where((x) => _done(x,day)).length;
  Widget _dashboard() {
    final completed = _completedFor(today); final percent = tasks.isEmpty ? 0.0 : completed/tasks.length;
    return ListView(padding: const EdgeInsets.all(16), children: [
      Card(child: Padding(padding: const EdgeInsets.all(18), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(t('پیشرفت امروز','Today’s progress'), style: Theme.of(context).textTheme.titleLarge), const SizedBox(height:12), LinearProgressIndicator(value:percent,minHeight:9,borderRadius:BorderRadius.circular(8)), const SizedBox(height:8), Text('${(percent*100).round()}%  •  $completed/${tasks.length} ${t('کار انجام‌شده','tasks completed')}')]))),
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(t('کارهای امروز','Today’s tasks'),style:Theme.of(context).textTheme.titleLarge), IconButton(onPressed:()=>_editTask(),icon:const Icon(Icons.add_circle_outline),tooltip:t('افزودن کار','Add task'))]),
      if (tasks.isEmpty) Padding(padding: const EdgeInsets.all(24), child: Text(t('هنوز کاری اضافه نکرده‌ای. از + شروع کن.','No tasks yet. Tap + to add one.'))),
      ...tasks.map((task) => Card(child: ListTile(leading: Checkbox(value:_done(task,today), onChanged:(v)=>_toggle(task,today,v??false)), title:Text(widget.isFa ? task.fa : task.en, style: TextStyle(decoration:_done(task,today)?TextDecoration.lineThrough:null)), subtitle:Text('${t('دفعات انجام','Completed')}: ${_totalDone(task)}  •  ${t('رکورد فعلی','Current streak')}: ${_streak(task)} ${t('روز','days')}'), trailing:PopupMenuButton<String>(onSelected:(v){if(v=='edit')_editTask(task); if(v=='delete')_delete(task);},itemBuilder:(_)=>[PopupMenuItem(value:'edit',child:Text(t('ویرایش','Edit'))),PopupMenuItem(value:'delete',child:Text(t('حذف','Delete')))])))),
    ]);
  }
  Widget _stats() => ListView(padding: const EdgeInsets.all(16), children: [Text(t('آمار و گزارش','Statistics & reports'),style:Theme.of(context).textTheme.headlineSmall), const SizedBox(height:8), Card(child:Padding(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(t('امروز','Today'),style:Theme.of(context).textTheme.titleMedium),Text('${_completedFor(today)} / ${tasks.length} ${t('کار انجام‌شده','tasks completed')}')])),), Card(child:Padding(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(t('این هفته','This week'),style:Theme.of(context).textTheme.titleMedium),Text('${_periodCount(7)} ${t('ثبت انجام کار','task check-ins')}')])),), Card(child:Padding(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(t('این ماه','This month'),style:Theme.of(context).textTheme.titleMedium),Text('${_periodCount(30)} ${t('ثبت انجام کار','task check-ins')}')])),), const SizedBox(height:8), ...tasks.map((task)=>Card(child:ListTile(title:Text(widget.isFa?task.fa:task.en),subtitle:Text('${t('مجموع دفعات','Total completions')}: ${_totalDone(task)}'),trailing:Column(mainAxisAlignment:MainAxisAlignment.center,children:[const Icon(Icons.local_fire_department_outlined),Text('${_streak(task)}')]))))]);
  int _periodCount(int days) { final start=DateTime.now().subtract(Duration(days:days-1)); return tasks.fold(0,(sum,task)=>sum+task.doneDates.where((d){final date=DateTime.tryParse(d); return date!=null && !date.isBefore(DateTime(start.year,start.month,start.day));}).length); }
  Widget _calendar() => ListView(padding:const EdgeInsets.all(12),children:[Text(t('تقویم فعالیت','Activity calendar'),style:Theme.of(context).textTheme.headlineSmall),TableCalendar<RoutineTask>(firstDay:DateTime.utc(2020,1,1),lastDay:DateTime.utc(2035,12,31),focusedDay:selectedDay,selectedDayPredicate:(d)=>isSameDay(d,selectedDay),onDaySelected:(selected,focused)=>setState(()=>selectedDay=selected),calendarBuilders:CalendarBuilders(markerBuilder:(ctx,day,events){final key=DateFormat('yyyy-MM-dd').format(day);if(_completedFor(key)==0)return null;return Container(width:6,height:6,margin:const EdgeInsets.only(top:35),decoration:const BoxDecoration(color:Colors.green,shape:BoxShape.circle));}),headerStyle:HeaderStyle(formatButtonVisible:false,titleCentered:true)), const SizedBox(height:12),Text('${DateFormat('yyyy-MM-dd').format(selectedDay)} — ${_completedFor(selectedKey)} ${t('کار انجام‌شده','tasks completed')}',style:Theme.of(context).textTheme.titleMedium),...tasks.where((task)=>_done(task,selectedKey)).map((task)=>ListTile(leading:const Icon(Icons.check_circle,color:Colors.green),title:Text(widget.isFa?task.fa:task.en)),),if(_completedFor(selectedKey)==0)Padding(padding:const EdgeInsets.all(12),child:Text(t('برای این روز فعالیتی ثبت نشده است.','No activity recorded for this day.')))]);
  Widget _settings() => ListView(padding:const EdgeInsets.all(16),children:[Text(t('تنظیمات','Settings'),style:Theme.of(context).textTheme.headlineSmall),SwitchListTile(title:Text(t('زبان فارسی','Persian language')),subtitle:Text(t('خاموش: English','Off: English')),value:widget.isFa,onChanged:widget.onLanguage),ListTile(title:Text(t('ظاهر برنامه','Appearance')),subtitle:Text(t('روشن، تاریک یا تنظیم دستگاه','Light, dark, or system setting')),trailing:DropdownButton<ThemeMode>(value:widget.themeMode,onChanged:(v){if(v!=null)widget.onTheme(v);},items:[DropdownMenuItem(value:ThemeMode.system,child:Text(t('دستگاه','System'))),DropdownMenuItem(value:ThemeMode.light,child:Text(t('روشن','Light'))),DropdownMenuItem(value:ThemeMode.dark,child:Text(t('تاریک','Dark')))])),const Divider(),Text(t('یادآوری روزانه','Daily reminder'),style:Theme.of(context).textTheme.titleMedium),const SizedBox(height:8),FilledButton.icon(onPressed:()async{final picked=await showTimePicker(context:context,initialTime:const TimeOfDay(hour:20,minute:0));if(picked!=null){await NotifyService.schedule(picked.hour,picked.minute,widget.isFa);if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(t('یادآوری روزانه تنظیم شد.','Daily reminder scheduled.'))));}},icon:const Icon(Icons.notifications_active_outlined),label:Text(t('انتخاب ساعت یادآوری','Choose reminder time'))),const SizedBox(height:8),Text(t('اطلاعات روی همین دستگاه ذخیره می‌شود و برای کارکرد برنامه به حساب کاربری نیاز نیست.','Your data is stored on this device. No account is needed.'))]);
  @override Widget build(BuildContext context) { final pages=[_dashboard(),_stats(),_calendar(),_settings()]; return Scaffold(appBar:AppBar(title:const Text('Routine Me'),actions:[if(tab==0)IconButton(onPressed:()=>_editTask(),icon:const Icon(Icons.add))]),body:loading?const Center(child:CircularProgressIndicator()):pages[tab],bottomNavigationBar:NavigationBar(selectedIndex:tab,onDestinationSelected:(i)=>setState(()=>tab=i),destinations:[NavigationDestination(icon:const Icon(Icons.checklist),label:t('امروز','Today')),NavigationDestination(icon:const Icon(Icons.bar_chart),label:t('آمار','Stats')),NavigationDestination(icon:const Icon(Icons.calendar_month),label:t('تقویم','Calendar')),NavigationDestination(icon:const Icon(Icons.settings),label:t('تنظیمات','Settings'))])); }
}
