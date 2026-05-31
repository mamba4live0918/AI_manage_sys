# SaaS UI Overhaul Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Transform the entire app from mobile-first card UI to professional SaaS enterprise dashboard with indigo glass design system.

**Architecture:** Rewrite AppTheme colors/surfaces first, then rebuild ResponsiveScaffold sidebar (56→220px, group labels), then adapt each module dashboard to the new design language. All Flutter frontend only — zero backend changes.

**Tech Stack:** Flutter 3.44 + Material 3 + Riverpod + fl_chart + BackdropFilter

---

### Task 1: Rewrite AppTheme — Indigo Glass Design System

**Files:**
- Modify: `frontend/lib/config/theme.dart`

Replace all colors and surfaces with the new indigo glass palette:

```dart
import 'package:flutter/material.dart';

class AppTheme {
  AppTheme._();

  // ── Accent ──
  static const accent = Color(0xFF4F46E5);
  static const accentLight = Color(0xFF818CF8);

  // ── Status colors (keep) ──
  static const blue = Color(0xFF4F46E5);
  static const green = Color(0xFF22C55E);
  static const red = Color(0xFFEF4444);
  static const orange = Color(0xFFF59E0B);
  static const purple = Color(0xFF8B5CF6);
  static const teal = Color(0xFF14B8A6);
  static const pink = Color(0xFFEC4899);

  // Light — Indigo glass
  static const lightBgStart = Color(0xFFE8EAF0);
  static const lightBgEnd = Color(0xFFEBEDF3);
  static const lightSurface = Color(0x7AFFFFFF); // rgba(255,255,255,0.48)
  static const lightSurfaceSolid = Color(0xFFFFFFFF);
  static const lightBorder = Color(0x1F6366F1); // rgba(99,102,241,0.12)
  static const lightText = Color(0xFF1E1E3D);
  static const lightTextSecondary = Color(0xFF8B8BB0);

  // Dark — Clean charcoal
  static const darkBg = Color(0xFF0F1115);
  static const darkSurface = Color(0xFF16181D);
  static const darkSurfaceAlt = Color(0xFF1A1D22);
  static const darkBorder = Color(0xFF202328);
  static const darkText = Color(0xFFE8E8E8);
  static const darkTextSecondary = Color(0xFF6A6A6A);

  static ThemeData get light {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      fontFamily: 'Microsoft YaHei',
      colorScheme: ColorScheme.fromSeed(
        seedColor: accent,
        brightness: Brightness.light,
        surface: lightSurfaceSolid,
        primary: accent,
      ),
      scaffoldBackgroundColor: lightBgStart,
      appBarTheme: const AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: TextStyle(
          color: lightText, fontSize: 18, fontWeight: FontWeight.w600,
        ),
      ),
      cardTheme: CardThemeData(
        color: lightSurfaceSolid,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: lightBorder, width: 0.5),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: lightBorder, thickness: 0.5, space: 0,
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: lightSurface,
        selectedIconTheme: const IconThemeData(color: accent),
        unselectedIconTheme: IconThemeData(color: lightTextSecondary),
      ),
    );
  }

  static ThemeData get dark {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      fontFamily: 'Microsoft YaHei',
      colorScheme: ColorScheme.fromSeed(
        seedColor: accent,
        brightness: Brightness.dark,
        surface: darkSurface,
        primary: accentLight,
      ),
      scaffoldBackgroundColor: darkBg,
      appBarTheme: const AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: TextStyle(
          color: darkText, fontSize: 18, fontWeight: FontWeight.w600,
        ),
      ),
      cardTheme: CardThemeData(
        color: darkSurface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: darkBorder, width: 0.5),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: darkBorder, thickness: 0.5, space: 0,
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: darkSurface,
        selectedIconTheme: const IconThemeData(color: accentLight),
        unselectedIconTheme: IconThemeData(color: darkTextSecondary),
      ),
    );
  }
}
```

- [ ] **Step 1: Replace theme.dart content**
- [ ] **Step 2: Commit** `refactor: indigo glass design system — AppTheme rewrite`

---

### Task 2: ResponsiveScaffold — 220px Sidebar with Groups

**Files:**
- Modify: `frontend/lib/widgets/responsive_scaffold.dart`

Key changes:
- Desktop sidebar width: 56px → 220px (collapsed stays 56px)
- Nav items: icon + label side by side (currently icon-only in collapsed, stacked in expanded)
- Add group labels: "MAIN" (首页/文件/讲师IP/审计) and "BUSINESS" (市场/招投标/PM/HR/财务)
- Group labels: tiny uppercase text, muted color, 6px padding
- Active item: accent-colored background (accent.withAlpha(20)) + accent text
- Sidebar background: Light `rgba(255,255,255,0.48)` with BackdropFilter blur, Dark `#16181D` solid

- [ ] **Step 1: Rewrite _desktopLayout sidebar to 220px**
- [ ] **Step 2: Add _SidebarGroup widget for section headers**
- [ ] **Step 3: Rewrite _SidebarNavItem to horizontal icon+label**
- [ ] **Step 4: Update _mobileLayout similarly**
- [ ] **Step 5: Commit** `refactor: widen sidebar to 220px with horizontal icon+label nav items`

---

### Task 3: Finance Dashboard — SaaS Glass Redesign

**Files:**
- Modify: `frontend/lib/pages/finance/finance_dashboard_page.dart`

Redesign KPI cards and overall layout:
- KPI cards: Single-color background + subtle border. Light: glass blur, Dark: solid #16181D. No more purple/pink/blue/green gradients.
- KPI layout: 3 per row (not 4). Big numbers (28px), small label above, trend arrow below.
- Chart: Wrap in same glass/solid container style. fl_chart line color → accent.
- Budget section: Same container style. Category-colored bars (keep existing).
- Quick actions: Compact row with accent highlight on selected.
- Overall: Less padding, tighter spacing for data density.

- [ ] **Step 1: Rewrite _KpiCards without gradients**
- [ ] **Step 2: Update _RevenueTrendChart colors to accent**
- [ ] **Step 3: Update _BudgetUsageSection container style**
- [ ] **Step 4: Update _QuickActions style**
- [ ] **Step 5: Commit** `refactor: SaaS theme — cream+glass light, warm charcoal dark`

---

### Task 4: Invoice Page — Data Table + Tab Navigation

**Files:**
- Modify: `frontend/lib/pages/finance/finance_invoice_page.dart`

- Replace card ListView with DataTable
- Add breadcrumb "首页 › 财务 › 票据" below AppBar
- Add TabBar for sub-page switching (Dashboard/票据/预算/支出) at the finance module level
- DataTable columns: 编号 | 金额 | 销售方 | 购买方 | 到期日 | 状态
- Each row tappable → opens detail bottom sheet (keep existing detail logic)
- Keep search bar and filter chips above the table

Note: The actual Tab navigation integration with the finance dashboard page (Task 3) happens here — the finance_dashboard_page gets TabBar at top, each tab shows its content inline rather than pushing new routes.

- [ ] **Step 1: Add TabBar to finance_dashboard_page**
- [ ] **Step 2: Convert invoice list to DataTable**
- [ ] **Step 3: Commit** `feat: tab navigation + data table for invoice page`

---

### Task 5: Extend Theme to Remaining Modules

**Files:**
- Modify: `frontend/lib/pages/hr/hr_dashboard_page.dart`
- Modify: `frontend/lib/pages/dashboard/dashboard_page.dart`

Update KPI cards and containers in other dashboards to match new theme:
- HR dashboard: Replace gradient KPI cards with glass/solid cards
- Main dashboard: Same treatment
- All module dashboards that have colored gradient cards

- [ ] **Step 1: Update HR dashboard KPI cards**
- [ ] **Step 2: Update main dashboard**
- [ ] **Step 3: Commit** `refactor: extend SaaS theme to all module dashboards`

---

### Task 6: Polish — Breadcrumbs, Density, Hover States

**Files:**
- Create: `frontend/lib/widgets/breadcrumb_bar.dart`
- Modify: `frontend/lib/pages/finance/*.dart` (all finance pages)
- Modify: `frontend/lib/pages/hr/*.dart`
- Modify: `frontend/lib/pages/marketing/*.dart`
- Modify: `frontend/lib/pages/bidding/*.dart`
- Modify: `frontend/lib/pages/pm/*.dart`

- Add breadcrumb bar widget below AppBar on all module pages
- Reduce vertical padding throughout for higher information density
- Add subtle hover effects to interactive elements (InkWell splash color → accent)
- Ensure all DataTable/list views use consistent row heights

- [ ] **Step 1: Create BreadcrumbBar widget**
- [ ] **Step 2: Add to finance pages**
- [ ] **Step 3: Add to HR, marketing, bidding, PM pages**
- [ ] **Step 4: Commit** `feat: breadcrumb navigation and density polish across all modules`
