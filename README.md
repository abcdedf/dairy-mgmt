# Dairy Farm Management System

A full-stack dairy production and sales management application built with Flutter (web) and WordPress REST API.

## Overview

This system helps dairy farms track their end-to-end operations:

- **Production recording** across four processing flows
- **Sales management** with customer-wise tracking
- **Inventory/stock** with 30-day running balances
- **Delivery challans and invoices** with PDF generation
- **Reports** including sales, vendor purchases, stock valuation, P&L, and audit logs
- **Multi-location support** with role-based access control

## Architecture

```
Flutter Web App (dfm/)
        │
        │  JWT-authenticated REST API calls
        ▼
WordPress REST API (dfm-backend/)
        │
        │  wpdb queries
        ▼
MariaDB Database
```

- **Frontend:** Flutter (Dart) — runs as a web application
- **Backend:** WordPress plugin exposing a custom REST API under `/wp-json/dairy/v1`
- **Database:** MariaDB (InnoDB, utf8mb4)
- **Auth:** JWT bearer tokens via a custom auth bridge plugin

## Project Structure

```
├── dfm/                         # Flutter project
│   ├── lib/
│   │   ├── main.dart
│   │   ├── models/              # Shared data models
│   │   ├── core/                # API client, auth, config, services
│   │   ├── controllers/         # GetX controllers (business logic)
│   │   └── pages/               # UI pages and shared widgets
│   ├── assets/images/           # PDF header/footer images
│   ├── docs/                    # Developer documentation
│   └── pubspec.yaml
│
├── dfm-backend/
│   ├── dairy-production-api/    # Main WordPress plugin (all endpoints)
│   └── dairy-jwt-auth/          # JWT authentication bridge plugin
│
└── CLAUDE.md                    # Detailed developer reference
```

## Production Flows

The system tracks purchases, processing, and sales across multiple activity types:

| Activity | Description |
|----------|-------------|
| FF Milk Purchase | Purchase full-fat milk from vendors |
| FF Milk Processing | FF Milk → Skim Milk + Cream |
| Pouch Production | FF Milk → Packaged Milk Pouches + Cream |
| Cream Purchase | Purchase cream from vendors |
| Cream Processing | Cream → Butter + Ghee |
| Butter Purchase | Purchase butter from vendors |
| Butter Processing | Butter → Ghee |
| Ingredient Purchase | SMP / Protein / Culture purchase |
| Curd Production | FF Milk → Cream + Curd |
| Madhusudan Sale | FF Milk → Madhusudan (bulk sale) |

Production flows are configurable in the database and can be activated/deactivated.

## Key Features

### Production
- Multi-vendor milk purchase tracking with SNF/Fat quality metrics
- Processing entries for all four flows plus pouch production
- Ingredient purchase tracking (SMP, Protein, Culture)

### Sales & Distribution
- Daily sales entry by product and customer
- Delivery challan creation and management
- Tax invoice generation from challans
- PDF generation for challans and invoices with custom headers/footers
- Per-customer pricing for pouch products

### Inventory
- 30-day running stock with daily cumulative balances
- Pouch stock tracking in crates
- Stock valuation with configurable estimated rates (finance role)

### Reports
- Sales reports (pivoted by product)
- Vendor purchase reports
- Pouch P&L analysis
- Cash flow and funds reports
- Sales ledger
- Audit log with full change history (finance role)

### Access Control
- Location-based access (users assigned to specific plant locations)
- Finance role for valuation and audit features
- TEST location available to all users for training

## Tech Stack

| Layer | Technology |
|-------|-----------|
| Frontend | Flutter 3.x (Web) |
| State Management | GetX |
| PDF Generation | `pdf` + `printing` packages |
| Backend | PHP (WordPress plugin) |
| Database | MariaDB |
| Auth | JWT (custom WP plugin) |
| Hosting | AWS (Bitnami WordPress) |

## Prerequisites

- Flutter SDK (3.0+)
- Chrome browser (for web development)
- PHP 8.x
- WordPress (5.x+) with MariaDB/MySQL, HTTPS enabled
- SSH access to the server (for deployment)

## Setup

### 1. Clone the repository

```bash
git clone <repo-url>
cd dairy-mgmt-1
```

### 2. Backend Setup (WordPress)

#### Install WordPress

Set up a WordPress instance on your server. Tested with Bitnami WordPress on AWS, but any standard WordPress installation works.

#### Install the plugins

Copy both plugins to the WordPress plugins directory:

```bash
scp -i /path/to/key.pem -r dfm-backend/dairy-jwt-auth/ \
    user@server:/path/to/wordpress/wp-content/plugins/dairy-jwt-auth/

scp -i /path/to/key.pem -r dfm-backend/dairy-production-api/ \
    user@server:/path/to/wordpress/wp-content/plugins/dairy-production-api/
```

#### Activate the plugins

1. Log in to WordPress Admin (`/wp-admin`)
2. Go to **Plugins** and activate both:
   - **Dairy JWT Auth** — JWT authentication for the REST API
   - **Dairy Production API** — Core business logic, endpoints, and database schema

#### Configure JWT secret

Add a JWT secret key to your `wp-config.php`:

```php
define('JWT_AUTH_SECRET_KEY', 'your-random-secret-key-here');
```

#### Database setup

All database tables are created automatically. Migrations run on the first API request after plugin activation or update. No manual SQL is needed.

#### Create users and assign locations

1. Create WordPress users via WP Admin (**Users** → **Add New**)
2. Go to **Dairy Farm** in the WP Admin sidebar to:
   - Create plant locations
   - Assign users to locations
   - Set finance permissions (`can_finance` flag)

### 3. Flutter App Setup

#### Configure the server URL

Create a JSON defines file outside source control:

```json
{
  "WP_BASE": "https://your-server.example.com"
}
```

#### Install dependencies and run locally

```bash
cd dfm
flutter pub get
flutter run -d chrome --dart-define-from-file=/path/to/your/dart_defines.json
```

### 4. Production Deployment

#### Build the Flutter web app

```bash
cd dfm
flutter build web --base-href /dairyapp/ --dart-define-from-file=/path/to/your/dart_defines.json
```

#### Deploy Flutter app to server

```bash
scp -r -i /path/to/key.pem dfm/build/web/* \
    user@server:/path/to/wordpress/dairyapp/
```

#### Update PHP plugins

Copy updated plugin files. Changes take effect immediately — no restart needed. Database migrations run automatically on the next API call.

```bash
scp -i /path/to/key.pem dfm-backend/dairy-production-api/dairy-production-api.php \
    user@server:/path/to/wordpress/wp-content/plugins/dairy-production-api/
```

## Documentation

- **[CLAUDE.md](CLAUDE.md)** — Detailed developer reference covering architecture, conventions, DB schema, API endpoints, and coding guidelines
- **[dfm/docs/adding-pdf-images.md](dfm/docs/adding-pdf-images.md)** — Procedure for adding/updating PDF header and footer images

## License

MIT License. See [LICENSE](LICENSE) for details.
