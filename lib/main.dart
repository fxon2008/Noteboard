import 'dart:async';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:uuid/uuid.dart';
import 'package:intl/intl.dart';
import 'models/note.dart';

final FlutterLocalNotificationsPlugin notifications = FlutterLocalNotificationsPlugin();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  Hive.registerAdapter(NoteAdapter());
  await Hive.openBox<Note>('notes');

  const AndroidInitializationSettings android = AndroidInitializationSettings('@mipmap/ic_launcher');
  const DarwinInitializationSettings ios = DarwinInitializationSettings();
  const InitializationSettings initSettings = InitializationSettings(android: android, iOS: ios);
  await notifications.initialize(initSettings);

  runApp(const NoteBoardApp());
}class NoteBoardApp extends StatelessWidget {
  const NoteBoardApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NoteBoard',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const HomePage(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final TextEditingController _searchController = TextEditingController();
  final Box<Note> box = Hive.box<Note>('notes');
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    _scheduleAllReminders();
  }

  void _onSearchChanged() {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      setState(() {});
    });
  }

  void _scheduleAllReminders() async {
    final now = DateTime.now();
    for (var note in box.values) {
      if (note.reminder != null && note.reminder!.isAfter(now)) {
        await _scheduleNotification(note);
      }
    }
  }

  Future<void> _scheduleNotification(Note note) async {
    final diff = note.reminder!.difference(DateTime.now()).inSeconds;
    if (diff <= 0) return;

    await notifications.zonedSchedule(
      note.id.hashCode,
      'Reminder',
      note.text.isEmpty ? 'Check your note!' : note.text,
      TZDateTime.now(local).add(Duration(seconds: diff)),
      const NotificationDetails(
        android: AndroidNotificationDetails('reminders', 'Note Reminders',
            importance: Importance.max, priority: Priority.high),
        iOS: DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
    );
  }  @override
  Widget build(BuildContext context) {
    final searchTerm = _searchController.text.toLowerCase();
    final filtered = box.values.where((n) => n.text.toLowerCase().contains(searchTerm)).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('NoteBoard'), centerTitle: true),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search notes...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                filled: true,
                fillColor: Colors.grey[100],
              ),
            ),
          ),
          Expanded(
            child: ValueListenableBuilder(
              valueListenable: box.listenable(),
              builder: (context, Box<Note> box, _) {
                final notes = searchTerm.isEmpty ? box.values.toList() : filtered;
                if (notes.isEmpty) {
                  return const Center(child: Text('Tap + to add a note!'));
                }
                return GridView.builder(
                  padding: const EdgeInsets.all(12),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 220,
                    childAspectRatio: 1,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                  ),
                  itemCount: notes.length,
                  itemBuilder: (context, i) {
                    final note = notes[i];
                    final color = _getColor(note.color);
                    final isOverdue = note.reminder != null && note.reminder!.isBefore(DateTime.now());

                    return Dismissible(
                      key: Key(note.id),
                      direction: DismissDirection.endToStart,
                      onDismissed: (_) => note.delete(),
                      child: Card(
                        color: color,
                        elevation: 4,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        child: InkWell(
                          onTap: () => _editNote(context, note),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    _colorDot('yellow', note),
                                    _colorDot('pink', note),
                                    _colorDot('blue', note),
                                    _colorDot('green', note),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Expanded(
                                  child: Text(
                                    note.text.isEmpty ? 'Empty...' : note.text,
                                    style: const TextStyle(fontSize: 15),
                                    maxLines: 5,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (note.reminder != null)
                                  Text(
                                    isOverdue ? 'OVERDUE' : DateFormat('MMM d, h:mm a').format(note.reminder!),
                                    style: TextStyle(fontSize: 10, color: isOverdue ? Colors.red[800] : Colors.black54),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _editNote(context, null),
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _colorDot(String colorName, Note note) {
    return GestureDetector(
      onTap: () { note.color = colorName; note.save(); },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 2),
        width: 16, height: 16,
        decoration: BoxDecoration(
          color: _getColor(colorName),
          shape: BoxShape.circle,
          border: Border.all(color: note.color == colorName ? Colors.black : Colors.transparent, width: 2),
        ),
      ),
    );
  }

  Color _getColor(String name) {
    switch (name) {
      case 'pink': return const Color(0xFFFFB3BA);
      case 'blue': return const Color(0xFFA3D9FF);
      case 'green': return const Color(0xFFB5EAD7);
      default: return const Color(0xFFFFF9B1);
    }
  }

  void _editNote(BuildContext context, Note? existing) async {
    final controller = TextEditingController(text: existing?.text ?? '');
    DateTime? selectedReminder = existing?.reminder;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom + 20, left: 20, right: 20, top: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: controller, autofocus: true, maxLines: 6, decoration: const InputDecoration(hintText: 'Write your note...')),
            const SizedBox(height: 16),
            Row(children: [
              const Icon(Icons.alarm),
              TextButton(
                onPressed: () async {
                  final date = await showDatePicker(context: context, initialDate: DateTime.now(), firstDate: DateTime.now(), lastDate: DateTime(2030));
                  if (date != null) {
                    final time = await showTimePicker(context: context, initialTime: TimeOfDay.now());
                    if (time != null) selectedReminder = DateTime(date.year, date.month, date.day, time.hour, time.minute);
                    setState(() {});
                  }
                },
                child: Text(selectedReminder == null ? 'Set Reminder' : DateFormat('MMM d, h:mm a').format(selectedReminder!)),
              ),
              if (selectedReminder != null)
                TextButton(onPressed: () { selectedReminder = null; setState(() {}); }, child: const Text('Clear')),
            ]),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () async {
                if (existing == null) {
                  final note = Note(id: const Uuid().v4(), text: controller.text, reminder: selectedReminder);
                  await box.put(note.id, note);
                  if (note.reminder != null) await _scheduleNotification(note);
                } else {
                  existing.text = controller.text;
                  existing.reminder = selectedReminder;
                  await existing.save();
                  await notifications.cancel(existing.id.hashCode);
                  if (existing.reminder != null) await _scheduleNotification(existing);
                }
                Navigator.pop(ctx);
              },
              child: Text(existing == null ? 'Save' : 'Update'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }
}Add main app code
