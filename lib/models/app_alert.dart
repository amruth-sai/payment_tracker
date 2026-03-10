// lib/models/app_alert.dart

enum AlertType { anomaly, duplicate, budgetWarning, dailyDigest, emiDetected }

enum AlertSeverity { info, warning, critical }

class AppAlert {
  final String id;
  final AlertType type;
  final String title;
  final String message;
  final AlertSeverity severity;
  final String? transactionId;
  final bool isRead;
  final DateTime createdAt;

  AppAlert({
    required this.id,
    required this.type,
    required this.title,
    required this.message,
    this.severity = AlertSeverity.info,
    this.transactionId,
    this.isRead = false,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'type': type.name,
      'title': title,
      'message': message,
      'severity': severity.name,
      'transaction_id': transactionId,
      'is_read': isRead ? 1 : 0,
      'created_at': createdAt.millisecondsSinceEpoch,
    };
  }

  factory AppAlert.fromMap(Map<String, dynamic> map) {
    return AppAlert(
      id: map['id'] as String,
      type: AlertType.values.firstWhere(
        (t) => t.name == map['type'],
        orElse: () => AlertType.anomaly,
      ),
      title: map['title'] as String,
      message: map['message'] as String,
      severity: AlertSeverity.values.firstWhere(
        (s) => s.name == map['severity'],
        orElse: () => AlertSeverity.info,
      ),
      transactionId: map['transaction_id'] as String?,
      isRead: (map['is_read'] as int?) == 1,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
    );
  }

  AppAlert copyWith({
    String? id,
    AlertType? type,
    String? title,
    String? message,
    AlertSeverity? severity,
    String? transactionId,
    bool? isRead,
    DateTime? createdAt,
  }) {
    return AppAlert(
      id: id ?? this.id,
      type: type ?? this.type,
      title: title ?? this.title,
      message: message ?? this.message,
      severity: severity ?? this.severity,
      transactionId: transactionId ?? this.transactionId,
      isRead: isRead ?? this.isRead,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
