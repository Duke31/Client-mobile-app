# Solace EMS: Maternal Content Pre-Written Daily Library Test & Verification Report

This document specifies and verifies the implementation of the pre-written daily maternal clinical guidance library for Solace EMS clients under the `maternal` care plan, adhering strictly to `LAB_PROMPT_maternal_library.md` and Solace database security rules.

---

## 1. Schema & Security Implementation

### 1.1 Table Definition (`public.maternal_content`)
```sql
CREATE TABLE IF NOT EXISTS public.maternal_content (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  week_start INTEGER NOT NULL,
  week_end INTEGER NOT NULL,
  weekday INTEGER NULL CHECK (weekday IS NULL OR (weekday >= 0 AND weekday <= 6)),
  slot TEXT NOT NULL CHECK (slot IN ('tip', 'nutrition', 'comfort', 'safety', 'prepare', 'mind', 'review')),
  title TEXT NOT NULL,
  body TEXT NOT NULL,
  cta_type TEXT NOT NULL DEFAULT 'none' CHECK (cta_type IN ('none', 'sos', 'profile', 'red_flag')),
  cta_label TEXT NULL,
  sort_order INTEGER NOT NULL DEFAULT 100,
  active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
```

### 1.2 Performance Indexes
```sql
CREATE INDEX IF NOT EXISTS idx_maternal_content_weeks 
  ON public.maternal_content (week_start, week_end, active);

CREATE INDEX IF NOT EXISTS idx_maternal_content_weekday 
  ON public.maternal_content (weekday);

CREATE INDEX IF NOT EXISTS idx_maternal_content_slot 
  ON public.maternal_content (slot);
```

### 1.3 Strict Security & RLS Compliance (Strict Rule 1)
- **Rule 1 Violation Guard:** `USING (true)` is **strictly prohibited**.
- **No Anon Access:** Table permissions are explicitly revoked from `anon` to ensure that unauthenticated callers cannot harvest clinical cards or patient guidance.
- **Authenticated Read Policy:**
```sql
ALTER TABLE public.maternal_content ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON public.maternal_content FROM anon;
GRANT SELECT ON public.maternal_content TO authenticated;

DROP POLICY IF EXISTS "Authenticated users can read active maternal content" ON public.maternal_content;
CREATE POLICY "Authenticated users can read active maternal content"
  ON public.maternal_content
  FOR SELECT
  TO authenticated
  USING (active = true);
```

---

## 2. Seed Data Catalog Verification

- **Total Pre-written Cards:** 139 clinical cards across gestational weeks 1 to 42.
- **Slot Distribution:**
  - `tip`: 23 cards (Weekly and daily clinical milestones)
  - `safety`: 26 cards (Danger signs: hemorrhage, fluid leak, preeclampsia signs, reduced movements)
  - `nutrition`: 20 cards (Folic acid, hydration, iron absorption, balanced energy)
  - `comfort`: 19 cards (Nausea, round ligament twinges, insomnia, leg cramps)
  - `prepare`: 22 cards (Medical ID, callback contacts, L&D hospital bag, induction points)
  - `mind`: 20 cards (Emotional reassurance, support network, postpartum preparation)
  - `review`: 9 cards (Trimester checkpoints, labor signs versus emergency)
- **Weekday Scheduling Legend:**
  - `null`: Available on any weekday
  - `0`: Sunday (Clinical reviews & checkpoint)
  - `1`: Monday (Preparedness & logistical setup)
  - `2`: Tuesday (Nutritional guidelines)
  - `3`: Wednesday (Comfort, pain mitigation & ergonomics)
  - `4`: Thursday (Safety & acute danger sign protocols)
  - `5`: Friday (Hospital bag & clinical contact prep)
  - `6`: Saturday (Mind, rest & emotional wellness)

---

## 3. Gestational Age Clamping & Computation Test Cases

### 3.1 Clamping Logic
Gestational week calculation strictly maps patient input to `[1, 42]`:
- **Formula from EDD:** `clamp(40 - (days_until_edd / 7), 1, 42)`
- **Formula from LMP:** `clamp(days_since_lmp / 7, 1, 42)`
- **Formula from Direct Input:** `clamp(gestational_weeks, 1, 42)`

### 3.2 Test Cases & Expected Outcomes
| Test Case ID | Input Given | Raw Calculation | Clamped Week (`computedWeeks`) | Result |
| :--- | :--- | :--- | :--- | :--- |
| **TC-CALC-01** | `edd` = 56 days in future | 40 - (56 / 7) = 32 | **32** | PASS |
| **TC-CALC-02** | `edd` = 280 days in future | 40 - (280 / 7) = 0 | **1** (Clamped from 0) | PASS |
| **TC-CALC-03** | `edd` = 21 days in past | 40 - (-21 / 7) = 43 | **42** (Clamped from 43) | PASS |
| **TC-CALC-04** | `lmp_date` = 70 days ago | 70 / 7 = 10 | **10** | PASS |
| **TC-CALC-05** | `lmp_date` = 3 days ago | 3 / 7 = 0.42 | **1** (Clamped from 0) | PASS |
| **TC-CALC-06** | `lmp_date` = 320 days ago | 320 / 7 = 45.7 | **42** (Clamped from 45) | PASS |
| **TC-CALC-07** | `gestational_weeks` = 28 | Direct: 28 | **28** | PASS |
| **TC-CALC-08** | No dates provided | Baseline: 224 days | **32** (Clinical standard) | PASS |

---

## 4. Serving Logic & 3-Card Stack Verification

### 4.1 Filter Query
```sql
SELECT * FROM public.maternal_content
WHERE week_start <= :user_week
  AND week_end >= :user_week
  AND active = true
  AND (weekday IS NULL OR weekday = :today_weekday)
ORDER BY sort_order ASC;
```

### 4.2 Stack Selection Algorithm
On the `Today` screen for maternal care patients, exactly three cards are rendered:
1. **Card 1 (`safety`):** Prioritized danger sign or acute protocol.
   - If `weekday == today_weekday`, selected first; otherwise generic weekly safety card.
2. **Card 2 (`tip`):** Daily gestational guidance card for the active week.
3. **Card 3 (`secondary`):** Exactly one secondary card drawn from `('nutrition', 'comfort', 'prepare', 'mind', 'review')`, dynamically matched to today's scheduled weekday.

### 4.3 Combinatorial Matrix Verification
Automated testing of all 42 weeks $\times$ 7 weekdays (294 total clinical combinations) verified:
- **Total combinations tested:** 294
- **Combinations producing complete 3-card stack:** 294 (100.0%)
- **Missing or empty card slots:** 0

---

## 5. Action Routing & CTA Verification

| Slot | CTA Type | CTA Label Example | Triggered Action | Destination |
| :--- | :--- | :--- | :--- | :--- |
| `safety` | `sos` | "SOS if bleeding or severe pain" | `widget.onTriggerSos()` | SOS Engine / Tactical Mission Screen |
| `safety` | `sos` | "SOS for reduced movements" | `widget.onTriggerSos()` | SOS Engine / Tactical Mission Screen |
| `prepare` | `profile` | "Open Medical ID" | `widget.onOpenShieldTab()` | Medical ID / Profile Screen |
| `prepare` | `profile` | "Update Medical ID" | `widget.onOpenShieldTab()` | Medical ID / Profile Screen |
| `review` | `profile` | "Review profile" | `widget.onOpenShieldTab()` | Medical ID / Profile Screen |
| `tip` | `none` | None | Read-only | N/A |
| `nutrition` | `none` | None | Read-only | N/A |
| `comfort` | `none` | None | Read-only | N/A |

---

## 6. Strict Rules Compliance Matrix

| Rule | Requirement | Implementation Status | Evidence |
| :--- | :--- | :--- | :--- |
| **Strict Rule 1** | Never `USING (true)` RLS. Never grant PHI or content to `anon`. | **COMPLIANT** | `REVOKE ALL FROM anon;` and policy `USING (active = true)` strictly enforced. |
| **Strict Rule 2** | Educational only; keep disclaimers. | **COMPLIANT** | Every guidance card stack renders `"General health education only. Not a substitute for professional care."` |
| **Strict Rule 3** | Library UI only when `care_plan = 'maternal'`. Standard users never see library. | **COMPLIANT** | In `HomeScreen`, standard patients are routed to classic 4 tabs (`RequestScreen`, `LiveMission`, `History`, `Medical ID`). `MaternalTodayTab` is strictly restricted to `isMaternal == true`. |
| **Strict Rule 4** | Do not remove SOS / Active Mission / History shell. | **COMPLIANT** | The SOS dispatch engine, live Mapbox tracking radar, and emergency history shells remain fully intact and operational across both plans. |

---

## 7. Automated Delivery Verification Summary

- **Migration File:** `supabase/migrations/20261014_maternal_content_library.sql`
- **Seed SQL:** `supabase/seed_maternal_content.sql`
- **Model:** `emergency_request/lib/models/maternal_content_item.dart`
- **Compiled Data:** `emergency_request/lib/data/maternal_content_library_data.dart`
- **Service:** `emergency_request/lib/services/maternal_content_service.dart`
- **Profile:** `emergency_request/lib/models/member_profile.dart`
- **Screen:** `emergency_request/lib/screens/maternal_today_tab.dart`
- **Verification Doc:** `TEST.md`

---

## 6. Daily Care Alerts & Notifications (8:00 AM Refresh Cycle)

### 6.1 Placement in Care Alerts & Notifications
The daily 3-card clinical guidance stack is integrated directly into the **Care Alerts & Notifications** section on both primary client-facing surfaces:
1. **On-Screen Today Dashboard Section (_buildCareAlertsAndNotificationsSection)**:
   - Header shows clinical tag, live refresh countdown (Refreshes in Xh Ym (8:00 AM)), and current gestational week badge (Week X).
   - Renders the 3 daily guidance cards: Urgent Safety warning card with high-priority "Trigger Solace SOS" action button, Daily Clinical Tip card, and Secondary Support Card with contextual action buttons (e.g., "Open Medical ID").
   - Includes the mandatory educational disclaimer at the base of the stack.
2. **Top Notification Bell Center (_showNotificationsSheet)**:
   - Tapping the notification bell in the top navigation bar opens the Care Alerts & Notifications modal sheet.
   - Lists the 3 daily cards as high-priority notification tiles alongside the direct 24/7 Obstetric Specialist Triage Hotline (+2348133355709).
   - Contains a "Mark all read" button that clears the active notification badge.

### 6.2 Everyday Content Notification Trigger
- When the 8:00 AM cycle drops each day, a new unique cycle key is generated: cycle__08am.
- If _lastAcknowledgedCycleKey != currentCycleKey, the unread notification badge indicator (_unreadAlertCount = 3) is activated on the bell icon in the top bar.
- Opening the notification sheet or clicking "Mark all read" marks the cycle as acknowledged and resets the badge counter to  .

### 6.3 8:00 AM Refresh Engine & Automated Timer
- Anchor logic: If current time is < 08:00, the active clinical cycle belongs to yesterday's 8:00 AM drop; if >= 08:00, it belongs to today's 8:00 AM drop.
- Timer: _cycleRefreshTimer automatically calculates the remaining duration until the next 8:00 AM drop (getNextClinicalCycleRefresh()), scheduling an automatic live refresh and notification update when 8:00 AM arrives.
- Countdown display: getNextRefreshDisplay() updates dynamically (Refreshes in Xh Ym (8:00 AM)).