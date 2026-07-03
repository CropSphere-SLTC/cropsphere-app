// lib/models/profile_models.dart
// Request and response models matching Pydantic schemas exactly

class UserProfile {
  final String name;
  final String email;
  final String? photoUrl;
  final String role;
  final String? lastLogin;
  final int activeSessions;

  UserProfile({
    required this.name,
    required this.email,
    this.photoUrl,
    required this.role,
    this.lastLogin,
    required this.activeSessions,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
    // GET /api/user/profile returns `name`; accept `display_name` too so a
    // future rename on either side of the API doesn't silently break this.
    name: json['name'] ?? json['display_name'] ?? '',
    email: json['email'] ?? '',
    photoUrl: json['photo_url'],
    role: json['role'] ?? 'user',
    lastLogin: json['last_login'],
    activeSessions: json['active_sessions'] ?? 0,
  );

  UserProfile copyWith({String? name}) => UserProfile(
    name: name ?? this.name,
    email: email,
    photoUrl: photoUrl,
    role: role,
    lastLogin: lastLogin,
    activeSessions: activeSessions,
  );
}

class NotificationPreferences {
  final bool priceAlerts;
  final bool weatherAlerts;
  final bool yieldRecommendations;

  NotificationPreferences({
    this.priceAlerts = true,
    this.weatherAlerts = true,
    this.yieldRecommendations = true,
  });

  factory NotificationPreferences.fromJson(Map<String, dynamic> json) =>
      NotificationPreferences(
        priceAlerts: json['price_alerts'] ?? true,
        weatherAlerts: json['weather_alerts'] ?? true,
        yieldRecommendations: json['yield_recommendations'] ?? true,
      );

  Map<String, dynamic> toJson() => {
    'price_alerts': priceAlerts,
    'weather_alerts': weatherAlerts,
    'yield_recommendations': yieldRecommendations,
  };
}

class UserPreferences {
  final String language;
  final NotificationPreferences notifications;

  UserPreferences({required this.language, required this.notifications});

  factory UserPreferences.fromJson(Map<String, dynamic> json) =>
      UserPreferences(
        language: json['language'] ?? 'en',
        notifications: NotificationPreferences.fromJson(
          json['notifications'] ?? {},
        ),
      );

  Map<String, dynamic> toJson() => {
    'language': language,
    'notifications': notifications.toJson(),
  };
}
