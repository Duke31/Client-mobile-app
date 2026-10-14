class MaternalContentItem {
  final String id;
  final int weekStart;
  final int weekEnd;
  final int? weekday; // 0=Sunday, 1=Monday, 2=Tuesday, 3=Wednesday, 4=Thursday, 5=Friday, 6=Saturday, null=Any day
  final String slot; // tip, nutrition, comfort, safety, prepare, mind, review
  final String title;
  final String body;
  final String ctaType; // none, sos, profile, red_flag
  final String? ctaLabel;
  final int sortOrder;
  final bool active;

  const MaternalContentItem({
    this.id = '',
    required this.weekStart,
    required this.weekEnd,
    this.weekday,
    required this.slot,
    required this.title,
    required this.body,
    this.ctaType = 'none',
    this.ctaLabel,
    this.sortOrder = 100,
    this.active = true,
  });

  factory MaternalContentItem.fromJson(Map<String, dynamic> json) {
    return MaternalContentItem(
      id: json['id']?.toString() ?? '',
      weekStart: (json['week_start'] as num?)?.toInt() ?? 1,
      weekEnd: (json['week_end'] as num?)?.toInt() ?? 42,
      weekday: (json['weekday'] as num?)?.toInt(),
      slot: json['slot']?.toString().toLowerCase().trim() ?? 'tip',
      title: json['title']?.toString().trim() ?? '',
      body: json['body']?.toString().trim() ?? '',
      ctaType: json['cta_type']?.toString().toLowerCase().trim() ?? 'none',
      ctaLabel: json['cta_label']?.toString().trim(),
      sortOrder: (json['sort_order'] as num?)?.toInt() ?? 100,
      active: json['active'] == true || json['active'] == null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'week_start': weekStart,
      'week_end': weekEnd,
      'weekday': weekday,
      'slot': slot,
      'title': title,
      'body': body,
      'cta_type': ctaType,
      'cta_label': ctaLabel,
      'sort_order': sortOrder,
      'active': active,
    };
  }

  bool get isSafety => slot == 'safety';
  bool get isTip => slot == 'tip';
  bool get isSecondary => !isSafety && !isTip;

  String get slotDisplayLabel {
    switch (slot) {
      case 'safety':
        return '🚨 SAFETY PROTOCOL';
      case 'tip':
        return '💡 DAILY CLINICAL TIP';
      case 'nutrition':
        return '🥗 NUTRITION GUIDELINE';
      case 'comfort':
        return '🌿 COMFORT & RELIEF';
      case 'prepare':
        return '📋 CLINICAL PREPARATION';
      case 'mind':
        return '🧘 MENTAL WELLBEING';
      case 'review':
        return '📑 OBSTETRIC REVIEW';
      default:
        return '🌸 MATERNAL GUIDANCE';
    }
  }
}
