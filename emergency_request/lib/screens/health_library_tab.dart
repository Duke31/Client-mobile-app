import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';

class DangerSignItem {
  final String title;
  final String subtitle;
  final String severity; // 'CRITICAL P1' | 'URGENT P2'
  final String clinicalImplication;
  final String recommendedAction;
  final String conditionCode;
  final String icon;

  const DangerSignItem({
    required this.title,
    required this.subtitle,
    required this.severity,
    required this.clinicalImplication,
    required this.recommendedAction,
    required this.conditionCode,
    required this.icon,
  });
}

class HealthLibraryTab extends StatelessWidget {
  final Function(String condition, int priority) onDispatchCondition;

  const HealthLibraryTab({
    super.key,
    required this.onDispatchCondition,
  });

  static const List<DangerSignItem> dangerSigns = [
    DangerSignItem(
      title: 'Vaginal Bleeding (Antepartum Hemorrhage)',
      subtitle: 'Any bright red or dark vaginal spotting or active blood flow',
      severity: 'CRITICAL P1',
      clinicalImplication:
          'May indicate placental abruption or placenta previa. Risk of sudden maternal hypovolemic shock and fetal compromise.',
      recommendedAction:
          'Remain recumbent. Do not insert tampons or undergo pelvic exam. ALS ambulance dispatch initiates O-Neg blood bank pre-alert.',
      conditionCode: 'Vaginal Bleeding - Hemorrhage Risk',
      icon: '🩸',
    ),
    DangerSignItem(
      title: 'Premature Rupture of Membranes (PROM)',
      subtitle: 'Sudden gush or continuous trickle of watery amniotic fluid',
      severity: 'CRITICAL P1',
      clinicalImplication:
          'Loss of sterile barrier creates ascending intrauterine infection risk (chorioamnionitis) or umbilical cord prolapse.',
      recommendedAction:
          'Note fluid color (clear, green/meconium, blood-stained) and time. Transfer immediately to sterile obstetric delivery suite.',
      conditionCode: 'Water Broke (PROM)',
      icon: '💧',
    ),
    DangerSignItem(
      title: 'Severe Persistent Headache & Vision Flashes',
      subtitle: 'Frontal or occipital throbbing unresponsive to rest, with blurred vision or spots',
      severity: 'CRITICAL P1',
      clinicalImplication:
          'Pathognomonic sign of impending eclampsia and severe gestational hypertensive cerebral edema.',
      recommendedAction:
          'Direct admission to high-dependency bay for magnesium sulfate seizure prophylaxis and blood pressure management.',
      conditionCode: 'Severe Headache / Blurred Vision (Pre-eclampsia)',
      icon: '⚡',
    ),
    DangerSignItem(
      title: 'Markedly Reduced Fetal Movements',
      subtitle: 'Fewer than 10 kicks in 2 hours during active maternal observation',
      severity: 'URGENT P2',
      clinicalImplication:
          'Fetal compensation response to acute placental insufficiency or cord compression.',
      recommendedAction:
          'Immediate cardiotocography (CTG) and ultrasound biophysical profile at secondary center.',
      conditionCode: 'Reduced Fetal Movement Alert',
      icon: '🦶',
    ),
    DangerSignItem(
      title: 'Convulsions, Fits or Sudden Collapse',
      subtitle: 'Generalized tonic-clonic jerking or transient loss of responsiveness',
      severity: 'CRITICAL P1',
      clinicalImplication:
          'Eclamptic seizure or acute neurological event requiring definitive airway and magnesium control.',
      recommendedAction:
          'Place patient in left recovery position. Clear airway of secretions. Direct Direct-to-Bed resuscitation transfer.',
      conditionCode: 'Convulsions / Loss of Consciousness',
      icon: '🚨',
    ),
    DangerSignItem(
      title: 'Acute Crushing Chest Pain or Breathlessness',
      subtitle: 'Pressure radiating to jaw/left arm, or inability to complete sentences',
      severity: 'CRITICAL P1',
      clinicalImplication:
          'Acute myocardial infarction, pulmonary embolism, or critical bronchospasm.',
      recommendedAction:
          'ALS ambulance with 12-lead telemetry and oxygen therapy en route to primary cardiac center.',
      conditionCode: 'Chest Pain / STEMI',
      icon: '🫀',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? AppTheme.darkCard : Colors.white;
    final cardBorder = isDark ? AppTheme.darkCardBorder : const Color(0xFFE2E8F0);
    final textColor = isDark ? Colors.white : const Color(0xFF0F172A);

    return Scaffold(
      backgroundColor: isDark ? AppTheme.darkBg : AppTheme.lightBg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFDC2626).withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Text('🚩', style: TextStyle(fontSize: 22)),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Clinical Red Flags & Library',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          color: textColor,
                          letterSpacing: -0.4,
                        ),
                      ),
                      Text(
                        'Evidence-based maternal & emergency danger signs',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Educational Banner
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E1B4B) : const Color(0xFFEEF2FF),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isDark ? const Color(0xFF3730A3) : const Color(0xFFC7D2FE),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline_rounded, color: Color(0xFF4F46E5), size: 22),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Recognizing these signs early eliminates the delay in seeking care. Each danger flag allows 1-tap direct emergency dispatch.',
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.35,
                          color: isDark ? const Color(0xFFC7D2FE) : const Color(0xFF312E81),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),

              // Danger signs list
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: dangerSigns.length,
                separatorBuilder: (_, __) => const SizedBox(height: 14),
                itemBuilder: (context, idx) {
                  final item = dangerSigns[idx];
                  final isP1 = item.severity.contains('P1');

                  return Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: cardBg,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: isP1
                            ? Colors.red.shade400.withValues(alpha: 0.4)
                            : cardBorder,
                        width: isP1 ? 1.5 : 1.0,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.04),
                          blurRadius: 10,
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(item.icon, style: const TextStyle(fontSize: 26)),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.between,
                                    children: [
                                      Expanded(
                                        child: Text(
                                          item.title,
                                          style: TextStyle(
                                            fontSize: 14.5,
                                            fontWeight: FontWeight.w800,
                                            color: textColor,
                                          ),
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: isP1
                                              ? Colors.red.shade900.withValues(alpha: 0.2)
                                              : Colors.amber.shade900.withValues(alpha: 0.2),
                                          borderRadius: BorderRadius.circular(6),
                                          border: Border.all(
                                            color: isP1 ? Colors.redAccent : Colors.amber,
                                          ),
                                        ),
                                        child: Text(
                                          item.severity,
                                          style: TextStyle(
                                            color: isP1 ? Colors.redAccent : Colors.amber,
                                            fontSize: 9.5,
                                            fontWeight: FontWeight.w900,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    item.subtitle,
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w500,
                                      color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: isDark ? Colors.black26 : const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Clinical Risk: ${item.clinicalImplication}',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  height: 1.35,
                                  color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF334155),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Guidance: ${item.recommendedAction}',
                                style: TextStyle(
                                  fontSize: 11,
                                  height: 1.35,
                                  color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: () {
                              HapticFeedback.heavyImpact();
                              onDispatchCondition(item.conditionCode, isP1 ? 1 : 2);
                            },
                            icon: const Icon(Icons.flash_on_rounded, size: 16),
                            label: Text(
                              'Dispatch for ${item.title.split('(').first.trim()} Now',
                              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
                            ),
                            style: FilledButton.styleFrom(
                              backgroundColor: isP1 ? const Color(0xFFDC2626) : const Color(0xFFD97706),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 10),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
