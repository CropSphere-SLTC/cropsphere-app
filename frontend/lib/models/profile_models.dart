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
    photoUrl: json['photo_url'] as String?,
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
  // The farmer's home district / main crop. Two writers share these: the
  // chatbot sets them server-side from conversational context ("I'm from
  // Jaffna"), and Account Settings now sets them explicitly. toJson only
  // emits them when non-null, and the backend only writes the keys it
  // actually receives, so neither writer clears the other's value.
  final String? preferredDistrict;
  final String? preferredCrop;

  UserPreferences({
    required this.language,
    required this.notifications,
    this.preferredDistrict,
    this.preferredCrop,
  });

  factory UserPreferences.fromJson(Map<String, dynamic> json) =>
      UserPreferences(
        language: json['language'] ?? 'en',
        notifications: NotificationPreferences.fromJson(
          json['notifications'] ?? {},
        ),
        preferredDistrict: json['preferred_district'],
        preferredCrop: json['preferred_crop'],
      );

  Map<String, dynamic> toJson() => {
    'language': language,
    'notifications': notifications.toJson(),
    // Omitted entirely when null — the backend treats an absent key as
    // "leave whatever is stored alone", so a save from a screen that
    // doesn't manage these can't wipe them.
    if (preferredDistrict != null) 'preferred_district': preferredDistrict,
    if (preferredCrop != null) 'preferred_crop': preferredCrop,
  };

  UserPreferences copyWith({
    String? language,
    NotificationPreferences? notifications,
    String? preferredDistrict,
    String? preferredCrop,
  }) => UserPreferences(
    language: language ?? this.language,
    notifications: notifications ?? this.notifications,
    preferredDistrict: preferredDistrict ?? this.preferredDistrict,
    preferredCrop: preferredCrop ?? this.preferredCrop,
  );
}
