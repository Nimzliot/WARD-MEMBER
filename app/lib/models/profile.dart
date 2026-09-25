class Profile {
  final String id;
  final String? fullName;
  final String? email;
  final String? phone;
  final bool phoneVerified;
  final int? wardId;
  final String? wardName;
  final String? residentId;
  final String role;

  const Profile({
    required this.id,
    this.fullName,
    this.email,
    this.phone,
    required this.phoneVerified,
    this.wardId,
    this.wardName,
    this.residentId,
    required this.role,
  });

  /// Phone-only accounts get a placeholder auth email from the server.
  static const phoneEmailDomain = 'phone.wardbudget.app';

  bool get isAdmin => role == 'admin';

  bool get hasRealEmail => email != null && !email!.endsWith('@$phoneEmailDomain');

  bool get isComplete =>
      (fullName?.trim().isNotEmpty ?? false) &&
      wardId != null &&
      (residentId?.trim().isNotEmpty ?? false);

  factory Profile.fromMap(Map<String, dynamic> m) => Profile(
        id: m['id'] as String,
        fullName: m['full_name'] as String?,
        email: m['email'] as String?,
        phone: m['phone'] as String?,
        phoneVerified: m['phone_verified'] as bool? ?? false,
        wardId: m['ward_id'] as int?,
        wardName: (m['wards'] as Map<String, dynamic>?)?['name'] as String?,
        residentId: m['resident_id'] as String?,
        role: m['role'] as String? ?? 'resident',
      );
}
