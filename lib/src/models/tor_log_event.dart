/// Log event coming from the native side (TorManager / TorIosPlugin / PT).
class TorLogEvent {
  final String level;
  final String tag;
  final String message;
  final DateTime timestamp;

  TorLogEvent({
    required this.level,
    required this.tag,
    required this.message,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  @override
  String toString() => '[$tag] $message';
}
