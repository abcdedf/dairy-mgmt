# Dairy Farm Management System

A full-stack dairy processing operations management system built with Flutter (web + mobile) and a WordPress REST API backend.

## Overview

This system digitises dairy farm operations — tracking production flows, purchases, sales, stock, and financial reporting across multiple locations with role-based access control.

### Key Features

- **4 Production Flows**: FF Milk processing, Cream-to-Butter/Ghee, Butter-to-Ghee, Dahi production
- **Purchase Tracking**: Vendor purchases with SNF/Fat quality metrics and rate capture
- **Sales Management**: Customer sales across 9 product types with duplicate prevention
- **30-Day Running Stock**: Cumulative daily balances aggregated across all production and sales tables
- **Financial Reports**: Sales reports, vendor purchase reports, stock valuation, funds report
- **Anomaly Detection**: Automatic flagging of production yield ratio outliers
- **Vendor Ledger**: Payment tracking with running balance per vendor
- **Audit Trail**: Every data mutation logged with before/after JSON snapshots
- **Multi-Location**: Location-scoped data with user-location access mappings
- **Role-Based Access**: Operator vs. Finance roles with server-enforced permissions

## Architecture

```
Flutter App (dfm/)
    │  JWT Bearer token on every request
    ▼
WordPress REST API (dairy-production-api plugin)
    │  wpdb queries
    ▼
MariaDB
```

### Tech Stack

| Layer | Technology |
|-------|-----------|
| Frontend | Flutter 3.x (Web + Mobile) |
| State Management | GetX |
| Backend | WordPress REST API (PHP plugin) |
| Authentication | JWT tokens |
| Database | MariaDB / MySQL |

## Project Structure

```
├── dfm/                          # Flutter application
│   └── lib/
│       ├── main.dart               # App entry, routing, shell
│       ├── models/models.dart      # Shared DTOs
│       ├── core/                   # Services (API, auth, permissions, etc.)
│       ├── controllers/            # GetX controllers (one per feature)
│       └── pages/                  # UI pages and shared widgets
│
├── dairy-production-api/           # WordPress plugin — business logic + API
│   └── dairy-production-api.php    # 35 REST endpoints, 16 DB tables
│
└── dairy-jwt-auth/                 # WordPress plugin — JWT authentication
    └── dairy-jwt-auth.php          # Token issue, refresh, logout
```

## Setup

### Prerequisites

- Flutter SDK 3.x
- WordPress 6.x with MariaDB/MySQL
- PHP 8.x

### Flutter App

```bash
cd dfm
flutter pub get
flutter run -d chrome          # Web
flutter run                    # Connected device
```

### Backend

1. Copy `dairy-production-api/` and `dairy-jwt-auth/` to your WordPress `wp-content/plugins/` directory
2. Activate both plugins in WordPress admin
3. Database tables are created automatically on first load (self-healing migrations)

### Configuration

Update the server URL in `dfm/lib/core/app_config.dart`:

```dart
static const String wpBase = 'https://your-wordpress-site.com';
```

## API

35 REST endpoints under `/wp-json/dairy/v1/`. All endpoints require JWT authentication. See `CLAUDE.md` for the complete API reference.

## Database

16 tables with `wp_mf_3_dp_` prefix. 9 fixed product types. Self-healing migrations run on WordPress `init` — no manual schema management needed.

## Production Flows

```
Flow 1:  FF Milk  →  Skim Milk + Cream
Flow 2:  Cream    →  Butter + Ghee
Flow 3:  Butter   →  Ghee
Flow 4:  SMP + Protein + Culture + Skim Milk  →  Dahi (containers)
```

## Blog Post

Read the full story of how this project was built in 32 hours with AI-assisted development:
[Building a Full-Stack Business Application in 2 Days with AI-Assisted Development](blog/full-article.md)

## License

MIT — see [LICENSE](LICENSE).
