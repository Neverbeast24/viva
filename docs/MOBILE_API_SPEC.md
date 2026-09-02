# VIVRΛNT Mobile REST API Specification

> Live REST contract for the Flutter app. Implemented on **vivrant-server** under `/api/mobile/**`. Product overview: [VIVRANT_Complete_Documentation.md](https://github.com/Neverbeast24/vivrant-server/blob/main/docs/VIVRANT_Complete_Documentation.md) · Flutter guide: [VIVRANT_Mobile_Documentation.md](./VIVRANT_Mobile_Documentation.md).

**Audience:** backend / Next.js and Flutter engineers  
**Client:** Flutter iOS + Android (`vivrant_mobile`)  
**Base URL:** same host as VIVRΛNT Web (e.g. `https://your-app.vercel.app`)  
**Auth:** `Authorization: Bearer <supabase_access_token>` on all `/api/mobile/*` routes  
**Content-Type:** `application/json`  
**Last updated:** 2 September 2026

---

## 1. Why this exists

VIVRΛNT Web runs most member domain logic as **Next.js Server Actions** (cookie sessions). Native mobile cannot call Server Actions reliably, so Flutter uses a **JSON REST catalog** under `/api/mobile/*` that mirrors those actions and returns Supabase JWT sessions for auth.

This catalog is **implemented**. Keep web Server Actions and mobile routes on the same tables and Gemini helpers — do not invent parallel schemas.

Shared platform routes (cookie or Bearer):

| Method | Path | Notes |
|--------|------|--------|
| `POST` | `/api/auth/login` | Returns `access_token` + `refresh_token` for mobile; also sets cookies |
| `POST` | `/api/auth/signup` | Session tokens when email confirmation is off |
| `POST` | `/api/auth/forgot-password` | |
| `POST` | `/api/auth/reset-password` | Recovery session |
| `POST` | `/api/auth/change-password` | `{ currentPassword, password }` |
| `GET` | `/api/search?q=` | Accept Bearer |
| `POST`/`DELETE` | `/api/device-tokens` | FCM registration (Bearer) |

---

## 2. Conventions

### 2.1 Auth

1. Mobile signs in via `POST /api/auth/login` (or signup).
2. Response **must** include Supabase session tokens (web can keep setting cookies too).
3. Subsequent requests send:

```http
Authorization: Bearer eyJhbGciOi...
```

4. Server creates a Supabase client scoped to that JWT (same pattern as `device-tokens/route.ts`).
5. Reject `profiles.status === 'suspended'` with `403` and `{ "error": "..." }`.
6. On `401`, client clears tokens and returns to login.

### 2.2 Success / error shapes

```json
{ "ok": true, "...": "payload" }
```

```json
{ "error": "Human-readable message" }
```

Use HTTP status: `400` validation, `401` auth, `403` suspended/forbidden, `404` missing, `500` unexpected.

### 2.3 IDs & dates

- Numeric row `id` values as JSON numbers.
- Timestamps ISO-8601 UTC (`logged_at`, `created_at`, …).
- Dates as `YYYY-MM-DD` (`checkin_date`, `entry_date`, `target_date`).
- Money in PHP pesos as numbers (`estimated_price`, `amount`, `monthly_health_budget`).

### 2.4 Source of truth

Reimplement by calling the **same Supabase tables + Gemini helpers** used by:

- `src/app/dashboard/**/actions.ts`
- `src/app/dashboard/**/ai-actions.ts`
- `src/lib/ai/gemini.ts`

Do **not** invent parallel schemas. Prefer extracting shared service functions from Server Actions, then wrapping them in Route Handlers.

---

## 3. Auth endpoints (extend existing)

### `POST /api/auth/login`

**Body**

```json
{ "email": "user@example.com", "password": "••••••••" }
```

**Required mobile response**

```json
{
  "ok": true,
  "user": { "id": "uuid", "email": "user@example.com" },
  "access_token": "…",
  "refresh_token": "…",
  "expires_in": 3600,
  "profile": { /* profiles row */ }
}
```

Still set cookies for the web browser if desired. Mobile ignores cookies.

### `POST /api/auth/signup`

**Body**

```json
{ "email": "…", "password": "…", "displayName": "Optional" }
```

**Response** — if session available immediately, same token fields as login; otherwise:

```json
{ "ok": true, "needs_email_confirmation": true }
```

### `POST /api/auth/forgot-password`

```json
{ "email": "…" }
```

### `POST /api/auth/reset-password`

```json
{ "password": "…" }
```

(Requires recovery session.)

### `POST /api/mobile/auth/logout`

Invalidate/refresh cleanup optional; always `{ "ok": true }`. Client deletes local tokens.

### `POST /api/mobile/auth/refresh` (recommended)

```json
{ "refresh_token": "…" }
```

Returns new `access_token` / `refresh_token`.

---

## 4. Profile, settings, today

### `GET /api/mobile/profile`

Returns `{ "profile": Profile }`.

### `PATCH /api/mobile/profile`

Body: subset of profile health fields (`display_name`, `birth_date`, `sex`, `height_cm`, `weight_kg`, `goal_weight_kg`, `activity_level`, `health_focus`, `daily_step_goal`, `daily_water_goal_ml`, `bio`, …).  
Mirrors `saveHealthProfile`.

### `GET /api/mobile/settings/preferences`

Returns `{ "settings": UserSettings | null }` (`theme`, `notifications_enabled`, `weekly_report_enabled`, `timezone`, `list_order`).

### `PUT /api/mobile/settings/preferences`

```json
{
  "theme": "light|dark|system",
  "notifications_enabled": true,
  "weekly_report_enabled": true,
  "timezone": "Asia/Manila"
}
```

Mirrors `saveSettings` → `user_settings`.

### `PATCH /api/mobile/settings/preferences`

Save a module list order (groceries, pantry, habits, goals, reminders):

```json
{ "module": "groceries", "ids": [3, 1, 2] }
```

### `POST /api/mobile/profile/avatar`

`multipart/form-data` with `file` → Firebase/Supabase `avatars` bucket. Returns `{ "avatar_url": "…" }`.

### `DELETE /api/mobile/profile/avatar`

### `GET /api/mobile/today`

Aggregate for the Today screen:

```json
{
  "checkin": { "energy": 4, "mood": 3, "steps": 4200, "water_ml": 750, "note": null },
  "calories": 1450,
  "protein_g": 90,
  "steps": 4200,
  "water_ml": 750,
  "workouts_minutes": 35,
  "active_goals": 3,
  "unread_notifications": 2
}
```

### `POST /api/mobile/today/checkin`

```json
{
  "energy": 1-5,
  "mood": 1-5,
  "steps": 0,
  "water_ml": 0,
  "sleep_minutes": 420,
  "sleep_quality": 1-5,
  "bedtime": "22:30",
  "wake_time": "06:30",
  "note": "optional"
}
```

Upsert `daily_checkins` on `(user_id, checkin_date)` — same as `saveCheckin`.

---

## 5. Nutrition

| Method | Path | Mirrors |
|--------|------|---------|
| `GET` | `/api/mobile/nutrition/meals?date=YYYY-MM-DD` | list `nutrition_logs` |
| `POST` | `/api/mobile/nutrition/meals` | `logMeal` |
| `PATCH` | `/api/mobile/nutrition/meals/:id` | update meal |
| `DELETE` | `/api/mobile/nutrition/meals/:id` | archive meal (soft delete) |
| `POST` | `/api/mobile/nutrition/meals/bulk` | `{ "text": "…" }` or `{ "items": […] }` (max 20) |
| `POST` | `/api/mobile/nutrition/water` | `addWaterIntake` |
| `POST` | `/api/mobile/nutrition/estimate` | `estimateMealWithAi` (optional image) |
| `POST` | `/api/mobile/nutrition/suggest` | `suggestMeal` |

**POST meal body**

```json
{
  "meal_name": "Chicken rice",
  "meal_type": "breakfast|lunch|dinner|snack",
  "calories": 520,
  "protein_g": 42,
  "carbs_g": 48,
  "fat_g": 12
}
```

**POST water**

```json
{ "ml": 250 }
```

(or `amount_ml` — accept either; web uses `amount_ml`)

**POST estimate**

```json
{ "description": "adobo with rice and egg" }
```

```json
{
  "ok": true,
  "summary": "…",
  "calories": 650,
  "protein_g": 35,
  "carbs_g": 70,
  "fat_g": 20
}
```

---

## 6. Movement

| Method | Path | Mirrors |
|--------|------|---------|
| `GET` | `/api/mobile/movement/workouts?date=` | list |
| `POST` | `/api/mobile/movement/workouts` | `logWorkout` |
| `PATCH` | `/api/mobile/movement/workouts/:id` | update |
| `DELETE` | `/api/mobile/movement/workouts/:id` | archive |
| `POST` | `/api/mobile/movement/suggest` | `suggestWorkoutWithAi` |

**POST workout**

```json
{
  "title": "Evening run",
  "activity_type": "walk|run|strength|cycle|yoga|other",
  "duration_minutes": 30,
  "calories_burned": 280
}
```

---

## 7. Gym

| Method | Path | Mirrors |
|--------|------|---------|
| `GET` | `/api/mobile/gym` | overview stats |
| `GET` | `/api/mobile/gym/exercises?equipment=` | `gym_exercises` catalog |
| `GET` | `/api/mobile/gym/sessions` | list |
| `POST` | `/api/mobile/gym/sessions` | `logGymSession` |
| `PATCH` | `/api/mobile/gym/sessions/:id` | update |
| `DELETE` | `/api/mobile/gym/sessions/:id` | archive |
| `GET`/`PUT`/`DELETE` | `/api/mobile/gym/sessions/live` | live rest timer + checks (`gym_live_sessions`) |
| `GET` | `/api/mobile/gym/plans` | list (includes `days[]`, `summary`, `level`) |
| `PATCH` | `/api/mobile/gym/plans/:id` | edit saved program |
| `DELETE` | `/api/mobile/gym/plans/:id` | archive |
| `POST` | `/api/mobile/gym/plans/ai` | `createAiGymPlan` — optional prefs body below |
| `GET`/`PUT`/`POST`/`DELETE` | `/api/mobile/gym/plans/draft` | program builder draft |
| `POST` | `/api/mobile/gym/plans/draft/commit` | save draft as a plan |
| `POST` | `/api/mobile/gym/machines/recommend` | `recommendMachinesWithAi` |
| `POST` | `/api/mobile/gym/machines/identify` | `identifyMachineFromPhoto` (multipart `photo`) |

**POST AI plan prefs (optional)**

```json
{
  "days_per_week": 3,
  "session_minutes": 45,
  "level": "beginner",
  "known_machine_slugs": ["leg-press", "stiff-leg-deadlift"],
  "known_custom_exercises": ["Hip thrust"],
  "avoid_targets": ["core", "lower_back"]
}
```

`level` allowlist: `beginner`, `intermediate`, `advanced` (defaults to `beginner`). Working loads are scaled from profile body weight using this level.

`avoid_targets` allowlist: `core`, `arms`, `forearms`, `shoulders`, `chest`, `back`, `traps`, `legs`, `glutes`, `hamstrings`, `calves`, `inner_thighs`, `lower_back`, `cardio`, `mobility`.

**POST identify machine** (`multipart/form-data`, field `photo` — JPG/PNG/WEBP/GIF under 4MB)

```json
{
  "ok": true,
  "detection": {
    "found": true,
    "machine": "Leg Press Machine",
    "demo_slug": "leg-press",
    "confidence": 91,
    "why": "Plate-loaded sled with a back pad.",
    "how_to_use": "Feet mid-platform, press without locking out.",
    "sets": "3 x 12",
    "muscle_group": "legs",
    "notes": "",
    "alternatives": []
  },
  "exercise": { "slug": "leg-press", "name": "Leg Press Machine" }
}
```

**POST session**

```json
{
  "title": "Upper body",
  "focus": "full_body|strength|fat_loss|mobility|endurance|upper|lower|core",
  "duration_minutes": 55,
  "calories_burned": 320,
  "exercises": [{ "name": "Bench press", "sets": "3x8" }],
  "notes": "optional"
}
```

---

## 8. Sleep, hydration, mindfulness, journal, habits

### Sleep

- `POST /api/mobile/sleep` → `logSleep`  
  `{ "sleep_minutes", "sleep_quality", "bedtime", "wake_time", "note?" }`
- `POST /api/mobile/sleep/coach` → `coachSleep` → `{ "coaching": "…" }`

### Hydration

- `POST /api/mobile/hydration` → `{ "ml": 250 }` (adds to today’s check-in)
- `POST /api/mobile/hydration/reminders` → `scheduleHydrationReminders`

### Mindfulness

- `POST /api/mobile/mindfulness/mood` → `{ "mood": 1-5, "note?" }`
- `POST /api/mobile/mindfulness/coach` → `{ "tip": "…" }`

### Journal

- `GET /api/mobile/journal`
- `POST /api/mobile/journal` → `{ "title?", "body", "mood?", "entry_date?", "tags?" }`
- `PATCH /api/mobile/journal/:id`
- `DELETE /api/mobile/journal/:id`
- `POST /api/mobile/journal/reflect` → `reflectOnJournal`

### Habits & challenges

- `GET /api/mobile/habits` — include `done_today: boolean`
- `POST /api/mobile/habits` → `{ "title": "…" }`
- `PATCH /api/mobile/habits/:id`
- `POST /api/mobile/habits/:id/toggle` → `{ "done": true }`
- `DELETE /api/mobile/habits/:id`
- `POST /api/mobile/habits/suggest` → AI suggestions
- `GET /api/mobile/habits/challenges`
- `POST /api/mobile/habits/challenges` → `{ "title", "target_value", "unit", … }`
- `DELETE /api/mobile/habits/challenges/:id`
- `POST /api/mobile/habits/challenges/refresh`

---

## 9. Groceries & pantry

### Groceries

- `GET /api/mobile/groceries`
- `POST /api/mobile/groceries`  
  `{ "name", "quantity?", "category?", "estimated_price?" }`  
  Categories: `produce|protein|dairy|grains|pantry|snacks|drinks|household|other`
- `PATCH /api/mobile/groceries/:id` → `{ "is_checked": true }` (also name/qty/category/price)
- `DELETE /api/mobile/groceries/:id`
- `POST /api/mobile/groceries/bulk` → `{ "text": "…" }` pasted list
- `POST /api/mobile/groceries/clear-completed`
- `POST /api/mobile/groceries/restock-pantry`
- `POST /api/mobile/groceries/plan` → `generateSmartGroceryPlan`
- `POST /api/mobile/groceries/estimate-cost` → `{ "name", "quantity?" }`
- `POST /api/mobile/groceries/plan/add` → add AI plan items to list

### Pantry

- `GET /api/mobile/pantry` (optional `?low_stock=1`, `?category=`)
- `POST /api/mobile/pantry` → `{ "name", "category", "stock_level": 0-100 }`
- `PATCH /api/mobile/pantry/:id` → `{ "stock_level": 40 }`
- `DELETE /api/mobile/pantry/:id`
- `POST /api/mobile/pantry/bulk` → `{ "text": "…" }`
- `POST /api/mobile/pantry/low-stock-to-grocery`

Low-stock threshold: **≤ 25** (same as web).

---

## 10. Spending

- `GET /api/mobile/spending` — month totals + budget remaining
- `GET /api/mobile/spending/expenses`
- `POST /api/mobile/spending/expenses`  
  `{ "title", "category": "food|fitness|supplements|wellness|other", "amount", "spent_at?" }`
- `PATCH /api/mobile/spending/expenses/:id`
- `DELETE /api/mobile/spending/expenses/:id`
- `POST /api/mobile/spending/expenses/bulk` → `{ "text": "…" }`
- `PUT /api/mobile/spending/budget` → `{ "amount": 5000 }` → `profiles.monthly_health_budget`
- `POST /api/mobile/spending/coach`

---

## 11. Reports, AI, goals, health history

### Reports

- `GET /api/mobile/reports` — weekly aggregates (calories, workouts, spend, check-ins)
- `POST /api/mobile/reports/weekly-story` → `generateWeeklyStory`

### Ask VIVRΛNT

- `GET /api/mobile/ai/chat` → `{ "messages": [{ "id", "role": "user|viva", "content", "follow_up?" }] }`
- `POST /api/mobile/ai/chat` → `{ "question": "…" }` → returns assistant message
- `POST /api/mobile/ai/insights` → `generateInsight`
- `GET /api/mobile/ai/reminders`
- `POST /api/mobile/ai/reminders`
- `PATCH /api/mobile/ai/reminders/:id` → `{ "enabled": false }`
- `DELETE /api/mobile/ai/reminders/:id`
- `POST /api/mobile/ai/reminders/draft`
- `POST /api/mobile/ai/reminders/sync-gym-plan`
- `POST /api/mobile/ai/reminders/sync-today`

### Goals

- `GET /api/mobile/goals`
- `POST /api/mobile/goals`  
  `{ "title", "category": "nutrition|movement|sleep|mindfulness|spending|other", "target_value?", "unit?", "target_date?" }`
- `PATCH /api/mobile/goals/:id` → `{ "status"?: "active|completed|paused", "current_value"? }`
- `DELETE /api/mobile/goals/:id`
- `POST /api/mobile/goals/refresh-progress`
- `POST /api/mobile/goals/suggest`
- `POST /api/mobile/goals/accept` → accept AI suggestion payload

### Health history

- `GET /api/mobile/health-history`
- `POST /api/mobile/health-history`  
  `{ "recorded_at?", "weight_kg?", "height_cm?", "body_fat_pct?", "waist_cm?", "note?" }`
- `DELETE /api/mobile/health-history/:id`
- `POST /api/mobile/health-history/analyze`

---

## 12. Notifications, devices, support, search

### Notifications

- `GET /api/mobile/notifications`
- `POST /api/mobile/notifications/:id/read`
- `POST /api/mobile/notifications/read-all`

### Device tokens (existing)

```http
POST /api/device-tokens
Authorization: Bearer <access_token>
{ "token": "<fcm_token>", "platform": "android|ios" }
```

```http
DELETE /api/device-tokens
{ "token": "<fcm_token>" }
```

### Support

- `POST /api/mobile/support/tickets`  
  `{ "subject", "body", "category?" }` → `submitSupportTicket`
- `GET /api/mobile/support/tickets` (member’s own tickets)

### Search (existing)

```http
GET /api/search?q=chicken
Authorization: Bearer …
```

Ensure Bearer works the same as cookies.

### Archive

Deletes in member modules are **soft deletes**. Restore from Archived; members cannot hard-delete.

- `GET /api/mobile/archive` → `{ "items": [{ "id", "entity", "entity_id", "title", "deleted_at" }] }`
- `POST /api/mobile/archive` `{ "id": <archived_records.id> }` → restore
- `GET /api/mobile/archive/export` → `{ "dump": { taken_at, user_id, tables } }` JSON backup

Archivable `entity` values: `nutrition_logs`, `workout_logs`, `expenses`, `pantry_items`, `grocery_items`, `health_goals`, `health_history`, `gym_sessions`, `gym_plans`, `habits`, `challenges`, `journal_entries`, `user_reminders`.

---

## 13. Staff admin (Bearer + `admin` / `super_admin`)

| Method | Path | Who |
|--------|------|-----|
| `GET` | `/api/mobile/admin/overview` | admin+ |
| `GET` | `/api/mobile/admin/users` | admin+ |
| `PATCH` | `/api/mobile/admin/users/:id` | admin+ — role / status |
| `GET` / `PATCH` | `/api/mobile/admin/tickets` | admin+ |
| `GET` | `/api/mobile/admin/roles` | admin+ |
| `GET` | `/api/mobile/admin/audit` | admin+ |
| `GET` / `POST` | `/api/mobile/admin/settings` | admin+ — health + broadcast |
| `GET` | `/api/mobile/admin/activity` | super_admin |
| `GET` / `PATCH` | `/api/mobile/admin/inquiries` | super_admin |

---

## 14. Profile type (shared)

```ts
type Profile = {
  user_id: string;
  display_name: string;
  email: string;
  avatar_url: string | null;
  role: "user" | "admin" | "super_admin";
  status: "active" | "suspended";
  timezone: string;
  birth_date: string | null;
  sex: string | null;
  height_cm: number | null;
  weight_kg: number | null;
  goal_weight_kg: number | null;
  activity_level: string | null;
  health_focus: string | null;
  daily_step_goal: number;
  daily_water_goal_ml: number;
  monthly_health_budget: number | null;
  bio: string | null;
  created_at?: string;
  updated_at?: string;
};
```

---

## 15. Implementation status

The catalog is live in `viva-server` (`src/app/api/mobile/**`, `src/lib/mobile/auth.ts`). When adding a route:

1. Call the same Supabase tables + Gemini helpers as the matching Server Action.
2. Keep RLS; use the service role only for restore/backup/admin reads that RLS cannot do.
3. Never expose `GEMINI_API_KEY` to Flutter.
4. Smoke-test with a Bearer token from `POST /api/auth/login`.
5. Keep `/api/device-tokens` as the FCM path.

---

## 16. Flutter client mapping

| Flutter service method | Endpoint |
|------------------------|----------|
| `VivrantApi.login` | `POST /api/auth/login` |
| `VivrantApi.getToday` | `GET /api/mobile/today` |
| `VivrantApi.logMeal` | `POST /api/mobile/nutrition/meals` |
| `VivrantApi.logWorkout` | `POST /api/mobile/movement/workouts` |
| `VivrantApi.askAi` | `POST /api/mobile/ai/chat` |
| `VivrantApi.registerDeviceToken` | `POST /api/device-tokens` |
| … | See `lib/data/api/` for the full list |

---

## 17. Out of scope for mobile API

- Public marketing pages (`/`, `/about`, `/pricing`, `/contact`)
- Firebase messaging service worker JS
- Cron secret routes (`/api/cron/reminders`, `/api/cron/backup`) — server-only
- Direct Gemini or Supabase secret-key access from Flutter

Staff **admin JSON routes are in scope** (section 13). The richest admin UI remains on web.

---

## 18. Config

```bash
flutter run --dart-define=API_BASE_URL=https://your-vivrant-host.vercel.app
```

Android emulator localhost → host machine: `http://10.0.2.2:3000` (default in `lib/config/env.dart`).  
iOS simulator: `http://127.0.0.1:3000`.  
Physical device: `http://<pc-lan-ip>:3000`.  
Release builds require `https://`.
