<?php
/**
 * Plugin Name: Dairy App - Production API
 * Description: REST API for dairy production, sales, stock and audit log.
 *              Authentication via the "JWT Authentication for WP REST API"
 *              plugin by Tmeister (install from WordPress.org plugin directory).
 * Version:     3.0.0
 *
 * INSTALL
 * 1. Install "JWT Authentication for WP REST API" from WP Admin > Plugins > Add New
 * 2. Upload THIS plugin zip via WP Admin > Plugins > Add New > Upload Plugin
 * 3. Configure wp-config.php (see full instructions)
 * 4. Activate JWT Auth plugin FIRST, then this plugin
 *
 * ERROR LOGGING
 * All errors write to PHP error log via error_log().
 * Log prefix: [DairyAPI]
 * To find the log: WP Admin > Tools > Site Health > Info > Server > error_log
 */

defined('ABSPATH') || exit;

class Dairy_Production_API {

    const NS         = 'dairy/v1';
    const LOG_PREFIX = '[DairyAPI]';

    const TABLE_LABELS = [
        'wp_mf_3_dp_estimated_rates'       => 'Estimated Rates',
        'wp_mf_3_dp_pouch_products'        => 'Pouch Products',
        'wp_mf_3_dp_production_flows'      => 'Production Flows',
        'wp_mf_4_transactions'             => 'Transactions',
        'wp_mf_4_transaction_lines'        => 'Transaction Lines',
        'wp_mf_4_vendor_payments'          => 'Vendor Payments',
        'wp_mf_3_dp_party_addresses'       => 'Party Addresses',
        'wp_mf_4_parties'                  => 'Parties',
        'wp_mf_4_challans'                 => 'Delivery Challans',
        'wp_mf_4_challan_lines'            => 'Delivery Challan Lines',
        'wp_mf_4_invoices'                 => 'Invoices',
    ];

    // Flow type constants — must match production_flows.key in the DB.
    // Used in milk_usage.flow_type and all queries that reference flows.

    // Pages every logged-in user with at least one location can see
    const PAGES_BASE = ['production', 'sales', 'reports'];

    // Pages requiring can_finance = true
    const PAGES_FINANCE = ['stock_valuation', 'audit_log', 'vendor_ledger', 'funds_report', 'admin'];

    // Pages requiring can_anomaly = true
    const PAGES_ANOMALY = ['anomalies'];

    public function __construct() {
        add_action('rest_api_init', [ $this, 'register_routes' ]);
        add_action('init',           [ $this, 'run_migrations' ]);
        add_action('admin_menu',    [ $this, 'register_admin_menu' ]);
        add_action('admin_post_dairy_save_permissions',
                   [ $this, 'handle_save_permissions' ]);
        add_action('admin_post_dairy_save_vendor_locations',
                   [ $this, 'handle_save_vendor_locations' ]);

        // WP-Cron: scheduled report emails
        add_action('dairy_send_scheduled_reports', [ $this, 'process_scheduled_reports' ]);
        if ( ! wp_next_scheduled('dairy_send_scheduled_reports') ) {
            wp_schedule_event( time(), 'hourly', 'dairy_send_scheduled_reports' );
        }
    }

    // ════════════════════════════════════════════════════
    // PERMISSIONS HELPERS
    // ════════════════════════════════════════════════════

    /**
     * Return array of location IDs the current user can access.
     */
    private function user_locations( int $uid ): array {
        $rows = $this->db()->get_results(
            $this->db()->prepare(
                "SELECT location_id FROM wp_mf_3_dp_user_location_access
                  WHERE user_id = %d", $uid
            ), ARRAY_A
        );
        $this->check_db('user_locations');
        return array_column($rows ?? [], 'location_id');
    }

    /**
     * Return true if the current user has the finance flag.
     */
    private function user_can_finance( int $uid ): bool {
        $row = $this->db()->get_row(
            $this->db()->prepare(
                "SELECT can_finance FROM wp_mf_3_dp_user_flags
                  WHERE user_id = %d", $uid
            ), ARRAY_A
        );
        $this->check_db('user_can_finance');
        return (bool) ($row['can_finance'] ?? false);
    }

    /**
     * Return true if the current user has the anomaly flag.
     */
    private function user_can_anomaly( int $uid ): bool {
        $row = $this->db()->get_row(
            $this->db()->prepare(
                "SELECT can_anomaly FROM wp_mf_3_dp_user_flags
                  WHERE user_id = %d", $uid
            ), ARRAY_A
        );
        $this->check_db('user_can_anomaly');
        return (bool) ($row['can_anomaly'] ?? false);
    }

    /**
     * Build the permissions object returned at login and by /me.
     * This is the single source of truth for what the app shows.
     */
    public function build_permissions( int $uid ): array {
        $locations = $this->user_locations($uid);
        $finance   = $this->user_can_finance($uid);
        $anomaly   = $this->user_can_anomaly($uid);

        // Fetch full location objects for the app dropdowns
        $loc_rows = empty($locations) ? [] : $this->db()->get_results(
            $this->db()->prepare(
                "SELECT id, name, code FROM wp_mf_3_dp_locations
                  WHERE id IN (" . implode(',', array_fill(0, count($locations), '%d')) . ")
                    AND is_active = 1
                  ORDER BY sort_order, name",
                ...$locations
            ), ARRAY_A
        );
        $this->check_db('build_permissions.locations');

        // Always append the Test location for every user — no config needed.
        $test_row = $this->db()->get_row(
            "SELECT id, name, code FROM wp_mf_3_dp_locations
              WHERE code = 'TEST' AND is_active = 1 LIMIT 1",
            ARRAY_A
        );
        if ($test_row) {
            $already = array_filter($loc_rows ?? [], fn($l) => $l['code'] === 'TEST');
            if (empty($already)) $loc_rows[] = $test_row;
        }
        $all_locs = array_values($loc_rows ?? []);

        // Derive visible pages. Use combined list so users who only have
        // Test can still see app pages.
        $pages = [];
        if ( ! empty($all_locs) ) {
            $pages = self::PAGES_BASE;
            if ( $finance ) {
                $pages = array_merge($pages, self::PAGES_FINANCE);
            }
            if ( $anomaly ) {
                $pages = array_merge($pages, self::PAGES_ANOMALY);
            }
        }

        return [
            'locations'   => $all_locs,
            'can_finance' => $finance,
            'can_anomaly' => $anomaly,
            'pages'       => $pages,
        ];
    }

    /**
     * Check that the requested location_id is in the user's permitted list.
     * Returns a WP_REST_Response error or null if allowed.
     */
    private function check_location_access( int $uid, int $location_id ): ?WP_REST_Response {
        // Test location is always accessible — no explicit assignment needed
        $is_test = (bool) $this->db()->get_var(
            $this->db()->prepare(
                "SELECT id FROM wp_mf_3_dp_locations WHERE id=%d AND code='TEST'",
                $location_id
            )
        );
        if ($is_test) return null;

        $allowed = $this->user_locations($uid);
        if ( ! in_array((string) $location_id, $allowed, false) ) {
            $this->log("check_location_access: user $uid denied for location $location_id");
            return $this->err('You do not have access to this location.', 403);
        }
        return null;
    }

    /**
     * Check that the user has the finance flag.
     */
    private function check_finance_access( int $uid ): ?WP_REST_Response {
        if ( ! $this->user_can_finance($uid) ) {
            $this->log("check_finance_access: user $uid denied (no finance flag)");
            return $this->err('You do not have access to financial data.', 403);
        }
        return null;
    }

    /**
     * Check that the user has the anomaly flag.
     */
    private function check_anomaly_access( int $uid ): ?WP_REST_Response {
        if ( ! $this->user_can_anomaly($uid) ) {
            $this->log("check_anomaly_access: user $uid denied (no anomaly flag)");
            return $this->err('You do not have access to anomaly data.', 403);
        }
        return null;
    }

    // ════════════════════════════════════════════════════
    // PERMISSION CALLBACK (JWT plugin sets current user)
    // ════════════════════════════════════════════════════

    public function require_auth(): bool|WP_Error {
        if ( is_user_logged_in() ) return true;
        $this->log('require_auth: unauthenticated request to ' . ($_SERVER['REQUEST_URI'] ?? ''));
        return new WP_Error(
            'rest_not_logged_in',
            'You must be logged in to access this endpoint.',
            [ 'status' => 401 ]
        );
    }

    // ════════════════════════════════════════════════════
    // ROUTE REGISTRATION
    // ════════════════════════════════════════════════════


    // ════════════════════════════════════════════════════
    // ENSURE DAHI PRODUCT EXISTS (id=6, unit=pcs)
    // ════════════════════════════════════════════════════

    // ════════════════════════════════════════════════════
    // MIGRATION RUNNER — version-guarded, runs once per version bump
    // ════════════════════════════════════════════════════

    private const MIGRATION_VERSION = 12;

    public function run_migrations(): void {
        $current = (int) get_option('dairy_migration_version', 0);
        if ($current >= self::MIGRATION_VERSION) return;

        $this->ensure_dahi_product();
        $this->ensure_v4_schema();

        // V2: Create V4 vendor payments table and rename unused V3 tables
        if ($current < 2) {
            $this->migrate_vendor_payments_v4();
            $this->rename_unused_v3_tables();
        }

        // V3: Delivery challan tables
        if ($current < 3) {
            $this->ensure_challan_schema();
        }

        // V4: Invoice tables
        if ($current < 4) {
            $this->ensure_invoice_schema();
        }

        // V5: Rename pouch_types → pouch_products, add crate_rate, add pouch_product_id to challan_lines
        if ($current < 5) {
            $this->migrate_pouch_products_v5();
        }

        // V6: Retire wp_mf_3_dp_customers — move customer_products & customer_location_access to use party_id
        if ($current < 6) {
            $this->migrate_customers_to_parties_v6();
        }

        // V7: Drop unused V3 data tables (re-created empty by ensure_dahi_product after V2 rename)
        if ($current < 7) {
            $this->cleanup_unused_v3_tables_v7();
        }

        // V8: Retire wp_mf_3_dp_vendors — move vendor_location_access & vendor_products to use party_id
        if ($current < 8) {
            $this->migrate_vendors_to_parties_v8();
        }

        // V9: Party addresses table (billing + shipping)
        if ($current < 9) {
            $this->ensure_party_addresses_v9();
        }

        // V10: Address snapshots on challans/invoices + company settings defaults
        if ($current < 10) {
            $this->ensure_document_addresses_v10();
        }

        // V11: Drop redundant pouch_rates table — rates consolidated into pouch_products.crate_rate
        if ($current < 11) {
            $exists = (int) $this->db()->get_var(
                "SELECT COUNT(*) FROM information_schema.TABLES
                 WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'wp_mf_3_dp_pouch_rates'");
            if ($exists) {
                $this->db()->query("DROP TABLE wp_mf_3_dp_pouch_rates");
                $this->check_db('v11.drop_pouch_rates');
                $this->log('V11: Dropped wp_mf_3_dp_pouch_rates (rates in pouch_products.crate_rate)');
            }
        }

        // V12: Per-customer pouch rates table
        if ($current < 12) {
            $exists = (int) $this->db()->get_var(
                "SELECT COUNT(*) FROM information_schema.TABLES
                 WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'wp_mf_3_dp_customer_pouch_rates'");
            if (!$exists) {
                $this->db()->query("
                    CREATE TABLE wp_mf_3_dp_customer_pouch_rates (
                        id              INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
                        party_id        INT UNSIGNED NOT NULL,
                        pouch_product_id INT UNSIGNED NOT NULL,
                        crate_rate      DECIMAL(10,2) NOT NULL,
                        UNIQUE KEY uq_party_pouch (party_id, pouch_product_id)
                    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
                ");
                $this->check_db('v12.create_customer_pouch_rates');
                $this->log('V12: Created wp_mf_3_dp_customer_pouch_rates table');
            }
        }

        update_option('dairy_migration_version', self::MIGRATION_VERSION);
    }

    public function ensure_dahi_product(): void {
        // NOTE: ingredient_purchase, vendor_payments, milk_usage, pouch_production,
        // pouch_production_lines, madhusudan_sale, curd_production CREATE TABLE blocks
        // removed in V7 — these tables are unused (superseded by V4 transactions).

        // Ensure ingredient products exist
        $rows = [
            [7, 'SMP',     'Bags', 7],
            [8, 'Protein', 'KG',   8],
            [9, 'Culture', 'KG',   9],
        ];
        foreach ($rows as [$id, $name, $unit, $sort]) {
            $this->db()->query("INSERT INTO wp_mf_3_dp_products (id, name, unit, sort_order, is_active)
                VALUES ($id, '$name', '$unit', $sort, 1)
                ON DUPLICATE KEY UPDATE name='$name', unit='$unit'");
        }

        $db = $this->db();
        $db->query("INSERT INTO wp_mf_3_dp_products (id, name, unit, sort_order, is_active)
                    VALUES (6, 'Dahi', 'pcs', 6, 1)
                    ON DUPLICATE KEY UPDATE name='Dahi', unit='pcs'");
        $this->check_db('ensure_dahi_product');

        // Add can_anomaly column to user_flags
        $col_exists = $db->get_var("SELECT COUNT(*) FROM information_schema.COLUMNS
            WHERE TABLE_SCHEMA = DATABASE()
              AND TABLE_NAME = 'wp_mf_3_dp_user_flags'
              AND COLUMN_NAME = 'can_anomaly'");
        if (!$col_exists) {
            $db->query("ALTER TABLE wp_mf_3_dp_user_flags
                ADD COLUMN can_anomaly TINYINT(1) NOT NULL DEFAULT 0 AFTER can_finance");
            $this->check_db('ensure_dahi_product.add_can_anomaly');
        }

        // Create vendor_location_access table
        $db->query("
            CREATE TABLE IF NOT EXISTS wp_mf_3_dp_vendor_location_access (
                id          INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
                vendor_id   INT UNSIGNED NOT NULL,
                location_id INT UNSIGNED NOT NULL,
                created_at  TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                UNIQUE KEY uq_vendor_location (vendor_id, location_id),
                KEY idx_vla_loc (location_id),
                CONSTRAINT fk_vla_loc FOREIGN KEY (location_id)
                    REFERENCES wp_mf_3_dp_locations (id) ON DELETE CASCADE
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
        ");
        $this->check_db('ensure_dahi_product.vendor_location_access_table');

        // Seed: if table is empty, insert all active vendor × location pairs
        $vla_count = (int) $db->get_var("SELECT COUNT(*) FROM wp_mf_3_dp_vendor_location_access");
        if ($vla_count === 0) {
            $db->query("
                INSERT INTO wp_mf_3_dp_vendor_location_access (vendor_id, location_id)
                SELECT v.id, l.id
                  FROM wp_mf_3_dp_vendors v
                  CROSS JOIN wp_mf_3_dp_locations l
                 WHERE v.is_active = 1 AND l.is_active = 1
            ");
            $this->check_db('ensure_dahi_product.seed_vendor_location_access');
        }

        // ── Vendor-Product mapping table ──
        $db->query("
            CREATE TABLE IF NOT EXISTS wp_mf_3_dp_vendor_products (
                id          INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
                vendor_id   INT UNSIGNED NOT NULL,
                product_id  INT UNSIGNED NOT NULL,
                UNIQUE KEY uq_vend_prod (vendor_id, product_id),
                KEY idx_vp_prod (product_id)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
        ");
        $this->check_db('ensure_dahi_product.vendor_products_table');

        // Seed: if empty, assign all active vendors to FF Milk (product_id=1)
        $vp_count = (int) $db->get_var("SELECT COUNT(*) FROM wp_mf_3_dp_vendor_products");
        if ($vp_count === 0) {
            $db->query("
                INSERT INTO wp_mf_3_dp_vendor_products (vendor_id, product_id)
                SELECT id, 1 FROM wp_mf_3_dp_vendors WHERE is_active = 1
            ");
            $this->check_db('ensure_dahi_product.seed_vendor_products');
        }

        // Fix culture/protein columns: INT → DECIMAL(10,2)
        $col_type = $db->get_var("
            SELECT DATA_TYPE FROM information_schema.COLUMNS
            WHERE TABLE_SCHEMA = DATABASE()
              AND TABLE_NAME   = 'wp_mf_3_dp_dahi_production'
              AND COLUMN_NAME  = 'input_culture_kg'");
        if ($col_type === 'int') {
            $db->query("ALTER TABLE wp_mf_3_dp_dahi_production
                MODIFY input_culture_kg DECIMAL(10,2) NOT NULL DEFAULT 0.00,
                MODIFY input_protein_kg DECIMAL(10,2) NOT NULL DEFAULT 0.00");
            $this->check_db('ensure_dahi_product.fix_decimal_cols');
        }

        // Add location_id to audit_log
        $audit_loc_exists = $db->get_var("SELECT COUNT(*) FROM information_schema.COLUMNS
            WHERE TABLE_SCHEMA = DATABASE()
              AND TABLE_NAME = 'wp_mf_3_dp_audit_log'
              AND COLUMN_NAME = 'location_id'");
        if (!$audit_loc_exists) {
            $db->query("ALTER TABLE wp_mf_3_dp_audit_log
                ADD COLUMN location_id INT UNSIGNED NULL AFTER ip_address,
                ADD KEY idx_audit_loc (location_id)");
            $this->check_db('ensure_dahi_product.audit_log_location_id');
        }

        // ── Pouch Types table ──
        $db->query("
            CREATE TABLE IF NOT EXISTS wp_mf_3_dp_pouch_products (
                id              INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
                name            VARCHAR(100) NOT NULL,
                milk_per_pouch  DECIMAL(10,2) NOT NULL DEFAULT 0,
                pouches_per_crate INT UNSIGNED NOT NULL DEFAULT 12,
                is_active       TINYINT(1) NOT NULL DEFAULT 1,
                created_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                UNIQUE KEY uq_pouch_name (name)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
        ");
        $this->check_db('ensure_dahi_product.pouch_types_table');

        // Migrate: rename litre→milk_per_pouch if old column exists
        $has_litre = (int) $db->get_var(
            "SELECT COUNT(*) FROM information_schema.COLUMNS
              WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='wp_mf_3_dp_pouch_products' AND COLUMN_NAME='litre'");
        if ($has_litre) {
            $db->query("ALTER TABLE wp_mf_3_dp_pouch_products CHANGE COLUMN litre milk_per_pouch DECIMAL(10,2) NOT NULL DEFAULT 0");
            $this->check_db('ensure_dahi_product.pouch_types_rename_litre');
        }

        // Migrate: add pouches_per_crate if missing
        $has_ppc = (int) $db->get_var(
            "SELECT COUNT(*) FROM information_schema.COLUMNS
              WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='wp_mf_3_dp_pouch_products' AND COLUMN_NAME='pouches_per_crate'");
        if (!$has_ppc) {
            $db->query("ALTER TABLE wp_mf_3_dp_pouch_products ADD COLUMN pouches_per_crate INT UNSIGNED NOT NULL DEFAULT 12 AFTER milk_per_pouch");
            $this->check_db('ensure_dahi_product.pouch_types_add_ppc');
        }

        // Migrate: drop price column if exists (moved to pouch_rates)
        $has_price = (int) $db->get_var(
            "SELECT COUNT(*) FROM information_schema.COLUMNS
              WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='wp_mf_3_dp_pouch_products' AND COLUMN_NAME='price'");
        if ($has_price) {
            $db->query("ALTER TABLE wp_mf_3_dp_pouch_products DROP COLUMN price");
            $this->check_db('ensure_dahi_product.pouch_types_drop_price');
        }

        // pouch_rates table removed — rates consolidated into pouch_products.crate_rate

        // ── Curd product ──
        $exists = $db->get_var("SELECT COUNT(*) FROM wp_mf_3_dp_products WHERE id=10");
        if (!$exists) {
            $db->insert('wp_mf_3_dp_products', [
                'id' => 10, 'name' => 'Curd', 'unit' => 'Matka',
                'is_active' => 1, 'sort_order' => 10,
            ]);
            $this->check_db('ensure_dahi_product.curd_product');
        }

        $exists = $db->get_var("SELECT COUNT(*) FROM wp_mf_3_dp_estimated_rates WHERE product_id=10");
        if (!$exists) {
            $db->insert('wp_mf_3_dp_estimated_rates', ['product_id' => 10, 'rate' => '190.00']);
            $this->check_db('ensure_dahi_product.curd_rate');
        }

        // curd_production table removed in V7 (superseded by V4 transactions)

        // ── Production Flows table ──
        $db->query("
            CREATE TABLE IF NOT EXISTS wp_mf_3_dp_production_flows (
                `key`        VARCHAR(50) NOT NULL PRIMARY KEY,
                label        VARCHAR(100) NOT NULL,
                sort_order   INT NOT NULL DEFAULT 0,
                is_active    TINYINT(1) NOT NULL DEFAULT 1
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
        ");
        $this->check_db('ensure_dahi_product.production_flows_table');

        // Seed default flows if table is empty
        $count = (int) $db->get_var("SELECT COUNT(*) FROM wp_mf_3_dp_production_flows");
        if ($count === 0) {
            $flows = [
                ['key' => 'ff_milk_purchase',   'label' => 'FF Milk Purchase',              'sort_order' => 10],
                ['key' => 'ff_milk_processing', 'label' => 'FF Milk → Cream + Skim',       'sort_order' => 20],
                ['key' => 'pouch_production',   'label' => 'FF Milk → Cream + Pouches',    'sort_order' => 30],
                ['key' => 'cream_purchase',     'label' => 'Cream Purchase',                'sort_order' => 40],
                ['key' => 'cream_processing',   'label' => 'Cream → Butter / Ghee',        'sort_order' => 50],
                ['key' => 'butter_purchase',    'label' => 'Butter Purchase',               'sort_order' => 60],
                ['key' => 'butter_processing',  'label' => 'Butter → Ghee',                'sort_order' => 70],
                ['key' => 'smp_purchase',       'label' => 'SMP / Protein / Culture Purchase', 'sort_order' => 80],
                ['key' => 'dahi_processing',    'label' => 'Dahi Production',               'sort_order' => 90],
                ['key' => 'curd_production',    'label' => 'FF Milk → Cream + Curd',       'sort_order' => 100],
                ['key' => 'madhusudan_sale',    'label' => 'FF Milk → Madhusudan',         'sort_order' => 110],
            ];
            foreach ($flows as $f) {
                $db->insert('wp_mf_3_dp_production_flows', $f);
            }
            $this->check_db('ensure_dahi_product.production_flows_seed');
        }

        // ── Report Menu table ──
        $db->query("
            CREATE TABLE IF NOT EXISTS wp_mf_3_dp_report_menu (
                `key`       VARCHAR(50) NOT NULL PRIMARY KEY,
                label       VARCHAR(100) NOT NULL,
                subtitle    VARCHAR(255) NOT NULL DEFAULT '',
                sort_order  INT NOT NULL DEFAULT 0,
                is_active   TINYINT(1) NOT NULL DEFAULT 1,
                permission  VARCHAR(20) NOT NULL DEFAULT 'all'
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
        ");
        $this->check_db('ensure_dahi_product.report_menu_table');

        $rm_count = (int) $db->get_var("SELECT COUNT(*) FROM wp_mf_3_dp_report_menu");
        if ($rm_count === 0) {
            $reports = [
                ['key'=>'daily_product_sales',   'label'=>'Daily Product Sales Report',  'subtitle'=>'Product-wise sales aggregated by date — last 30 days',                     'sort_order'=>10, 'permission'=>'all'],
                ['key'=>'daily_customer_sales',  'label'=>'Daily Customer Sales Report', 'subtitle'=>'All sales by customer with product, qty, rate and total — last 30 days',   'sort_order'=>20, 'permission'=>'all'],
                ['key'=>'sales_transactions',    'label'=>'Sales Transactions',          'subtitle'=>'Every sale entry with customer, qty, rate and user — last 7 days',          'sort_order'=>30, 'permission'=>'all'],
                ['key'=>'production_transactions','label'=>'Productions Report',         'subtitle'=>'All production entries with quantities and user — last 7 days',             'sort_order'=>40, 'permission'=>'all'],
                ['key'=>'vendor_purchase_report', 'label'=>'Vendor Purchase Report',     'subtitle'=>'All purchases by vendor with product, qty, rate and amount',                'sort_order'=>50, 'permission'=>'all'],
                ['key'=>'stock',                 'label'=>'Stock',                       'subtitle'=>'30-day running stock balance across all products',                          'sort_order'=>60, 'permission'=>'all'],
                ['key'=>'vendor_ledger',         'label'=>'Vendor Ledger',               'subtitle'=>'Payment tracking — purchases, payments and balance due per vendor',         'sort_order'=>70, 'permission'=>'finance'],
                ['key'=>'cashflow_report',       'label'=>'Cash Flow Report',            'subtitle'=>'Daily cash position — sales, purchases, payments and running balance',      'sort_order'=>80, 'permission'=>'finance'],
                ['key'=>'profitability_report',  'label'=>'Profitability Report',        'subtitle'=>'Cost vs value per production flow — last 30 days',                          'sort_order'=>90, 'permission'=>'finance'],
                ['key'=>'funds_report',          'label'=>'Funds Report',                'subtitle'=>'Sales revenue, stock value, vendor dues and free cash',                     'sort_order'=>100,'permission'=>'finance'],
                ['key'=>'stock_valuation',       'label'=>'Stock Valuation',             'subtitle'=>'Stock quantities with estimated values per product',                        'sort_order'=>110,'permission'=>'finance'],
                ['key'=>'madhusudan_pnl',        'label'=>'Madhusudan P&L',              'subtitle'=>'FF Milk direct sale — revenue, cost and profit per transaction',            'sort_order'=>120,'permission'=>'all'],
                ['key'=>'pouch_pnl',             'label'=>'Pouch P&L',                   'subtitle'=>'Pouch production — revenue, cost and profit per batch',                    'sort_order'=>130,'permission'=>'all'],
                ['key'=>'pouch_stock',           'label'=>'Pouch Stock',                 'subtitle'=>'Per-type pouch production balance',                                         'sort_order'=>140,'permission'=>'all'],
                ['key'=>'pouch_types',           'label'=>'Pouch Types',                 'subtitle'=>'Manage pouch types — name, litre, price',                                   'sort_order'=>150,'permission'=>'all'],
            ];
            foreach ($reports as $rpt) {
                $db->insert('wp_mf_3_dp_report_menu', $rpt);
            }
            $this->check_db('ensure_dahi_product.report_menu_seed');
        }

        // Add Cash+Stock Report to menu if not exists
        $cs_exists = (int) $db->get_var("SELECT COUNT(*) FROM wp_mf_3_dp_report_menu WHERE `key`='cash_stock_report'");
        if (!$cs_exists) {
            $db->insert('wp_mf_3_dp_report_menu', [
                'key'         => 'cash_stock_report',
                'label'       => 'Cash + Stock Report',
                'subtitle'    => 'Daily cash position with stock valuation across products',
                'sort_order'  => 85,
                'permission'  => 'finance',
            ]);
            $this->check_db('ensure_dahi_product.cash_stock_report_seed');
        }

        // Add Stock Flow report to menu if not exists
        $sf_exists = (int) $db->get_var("SELECT COUNT(*) FROM wp_mf_3_dp_report_menu WHERE `key`='stock_flow'");
        if (!$sf_exists) {
            $db->insert('wp_mf_3_dp_report_menu', [
                'key'         => 'stock_flow',
                'label'       => 'Stock Flow',
                'subtitle'    => 'In / Out / Current per product per day — 30 day view',
                'sort_order'  => 65,
                'permission'  => 'all',
            ]);
            $this->check_db('ensure_dahi_product.stock_flow_seed');
        }

        // Rename Production Transactions → Productions Report
        $db->query("UPDATE wp_mf_3_dp_report_menu SET label='Productions Report' WHERE `key`='production_transactions' AND label='Production Transactions'");
        $this->check_db('ensure_dahi_product.rename_production_transactions');

        // Deactivate individual P&L reports (covered by Profitability Report) and move Pouch Types to Admin
        $db->query("UPDATE wp_mf_3_dp_report_menu SET is_active=0 WHERE `key` IN ('madhusudan_pnl','pouch_pnl','pouch_types','funds_report') AND is_active=1");
        $this->check_db('ensure_dahi_product.deactivate_pnl_reports');

        // ── Location sort_order column ──
        $loc_sort_exists = (int) $db->get_var("SELECT COUNT(*) FROM information_schema.COLUMNS
            WHERE TABLE_SCHEMA = DATABASE()
              AND TABLE_NAME = 'wp_mf_3_dp_locations'
              AND COLUMN_NAME = 'sort_order'");
        if (!$loc_sort_exists) {
            $db->query("ALTER TABLE wp_mf_3_dp_locations ADD COLUMN sort_order INT NOT NULL DEFAULT 0 AFTER code");
            $this->check_db('ensure_dahi_product.locations_sort_order');
            // Seed: alphabetical order
            $locs = $db->get_results("SELECT id FROM wp_mf_3_dp_locations ORDER BY name", ARRAY_A);
            $s = 10;
            foreach ($locs ?: [] as $loc_row) {
                $db->update('wp_mf_3_dp_locations', ['sort_order' => $s], ['id' => (int)$loc_row['id']]);
                $s += 10;
            }
            $this->check_db('ensure_dahi_product.locations_sort_order_seed');
        }

        // Deactivate Dahi product (replaced by Curd) and hide its production flow
        $dahi_active = (int) $db->get_var("SELECT is_active FROM wp_mf_3_dp_products WHERE id=6");
        if ($dahi_active === 1) {
            $db->update('wp_mf_3_dp_products', ['is_active' => 0], ['id' => 6]);
            $this->check_db('ensure_dahi_product.deactivate_dahi');
        }
        $dahi_flow_active = $db->get_var("SELECT is_active FROM wp_mf_3_dp_production_flows WHERE `key`='dahi_processing'");
        if ($dahi_flow_active !== null && (int)$dahi_flow_active === 1) {
            $db->update('wp_mf_3_dp_production_flows', ['is_active' => 0], ['key' => 'dahi_processing']);
            $this->check_db('ensure_dahi_product.deactivate_dahi_flow');
        }

        // Stock column order: Skim Milk, Curd, Ghee, Cream, Butter, FF Milk, SMP, Culture, Protein
        $skim_sort = (int) $db->get_var("SELECT sort_order FROM wp_mf_3_dp_products WHERE id=2");
        if ($skim_sort !== 1) {
            $order = [2 => 1, 10 => 2, 5 => 3, 3 => 4, 4 => 5, 1 => 6, 7 => 7, 9 => 8, 8 => 9, 6 => 99];
            foreach ($order as $pid => $sort) {
                $db->update('wp_mf_3_dp_products', ['sort_order' => $sort], ['id' => $pid]);
            }
            $this->check_db('ensure_dahi_product.stock_column_order');
        }

        // ── Customer-Product mapping table ──
        $db->query("
            CREATE TABLE IF NOT EXISTS wp_mf_3_dp_customer_products (
                id          INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
                customer_id INT UNSIGNED NOT NULL,
                product_id  INT UNSIGNED NOT NULL,
                UNIQUE KEY uq_cust_prod (customer_id, product_id),
                KEY idx_cp_prod (product_id)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
        ");
        $this->check_db('ensure_dahi_product.customer_products_table');

        // Migrate: parse product prefix from customer names, seed mappings, strip prefixes
        $cp_count = (int) $db->get_var("SELECT COUNT(*) FROM wp_mf_3_dp_customer_products");
        if ($cp_count === 0) {
            $prefix_map = [
                'Skim-'    => 2,
                'Curd-'    => 10,
                'Ghee-'    => 5,
                'Cream-'   => 3,
                'Butter-'  => 4,
                'FF Milk-' => 1,
            ];
            $custs = $db->get_results("SELECT id, name FROM wp_mf_3_dp_customers", ARRAY_A);
            foreach ($custs as $c) {
                $cid  = (int) $c['id'];
                $name = $c['name'];
                foreach ($prefix_map as $prefix => $pid) {
                    if (str_starts_with($name, $prefix)) {
                        $db->insert('wp_mf_3_dp_customer_products', [
                            'customer_id' => $cid,
                            'product_id'  => $pid,
                        ]);
                        $short = substr($name, strlen($prefix));
                        // Only rename if no collision
                        $dup = $db->get_var($db->prepare(
                            "SELECT COUNT(*) FROM wp_mf_3_dp_customers WHERE name=%s AND id!=%d",
                            $short, $cid));
                        if (!$dup) {
                            $db->update('wp_mf_3_dp_customers', ['name' => $short], ['id' => $cid]);
                        }
                        break;
                    }
                }
            }
            $this->check_db('ensure_dahi_product.customer_products_seed');
        }

        // ── Customer-Location mapping table ──
        $db->query("
            CREATE TABLE IF NOT EXISTS wp_mf_3_dp_customer_location_access (
                id          INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
                customer_id INT UNSIGNED NOT NULL,
                location_id INT UNSIGNED NOT NULL,
                created_at  TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                UNIQUE KEY uq_cust_loc (customer_id, location_id),
                KEY idx_cla_loc (location_id)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
        ");
        $this->check_db('ensure_dahi_product.customer_location_access_table');

        // Seed: if empty, assign all active customers to all active locations
        $cla_count = (int) $db->get_var("SELECT COUNT(*) FROM wp_mf_3_dp_customer_location_access");
        if ($cla_count === 0) {
            $db->query("
                INSERT INTO wp_mf_3_dp_customer_location_access (customer_id, location_id)
                SELECT c.id, l.id
                  FROM wp_mf_3_dp_customers c
                  CROSS JOIN wp_mf_3_dp_locations l
                 WHERE c.is_active = 1 AND l.is_active = 1
            ");
            $this->check_db('ensure_dahi_product.seed_customer_location_access');
        }

        // ── Matka product (ingredient, like SMP/Protein/Culture) ──
        $matka_exists = (int) $db->get_var("SELECT COUNT(*) FROM wp_mf_3_dp_products WHERE id=11");
        if (!$matka_exists) {
            $db->insert('wp_mf_3_dp_products', [
                'id' => 11, 'name' => 'Matka', 'unit' => 'pcs',
                'is_active' => 1, 'sort_order' => 11,
            ]);
            $this->check_db('ensure_dahi_product.matka_product');
        }
        $matka_rate_exists = (int) $db->get_var("SELECT COUNT(*) FROM wp_mf_3_dp_estimated_rates WHERE product_id=11");
        if (!$matka_rate_exists) {
            $db->insert('wp_mf_3_dp_estimated_rates', ['product_id' => 11, 'rate' => '15.00']);
            $this->check_db('ensure_dahi_product.matka_rate');
        }

        // ── Report Email Schedules table ──
        $db->query("
            CREATE TABLE IF NOT EXISTS wp_mf_3_dp_report_email_schedules (
                id           INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
                report_key   VARCHAR(50) NOT NULL,
                emails       TEXT NOT NULL,
                frequency    VARCHAR(20) NOT NULL DEFAULT 'daily',
                day_of_week  TINYINT NULL COMMENT '0=Sun..6=Sat for weekly',
                day_of_month TINYINT NULL COMMENT '1-28 for monthly',
                time_hour    TINYINT NOT NULL DEFAULT 8 COMMENT '0-23 IST hour',
                location_id  INT UNSIGNED NULL COMMENT 'NULL = all locations',
                is_active    TINYINT(1) NOT NULL DEFAULT 1,
                last_sent_at DATETIME NULL,
                created_by   BIGINT UNSIGNED NOT NULL,
                created_at   TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                updated_at   TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
                KEY idx_res_active (is_active)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
        ");
        $this->check_db('ensure_dahi_product.report_email_schedules_table');

        // Add date_range_days column if missing
        $has_drd = (int) $db->get_var("SELECT COUNT(*) FROM information_schema.COLUMNS
            WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='wp_mf_3_dp_report_email_schedules' AND COLUMN_NAME='date_range_days'");
        if (!$has_drd) {
            $db->query("ALTER TABLE wp_mf_3_dp_report_email_schedules ADD COLUMN date_range_days SMALLINT NOT NULL DEFAULT 7 AFTER location_id");
            $this->check_db('ensure_dahi_product.report_email_add_date_range_days');
        }
    }

    // ════════════════════════════════════════════════════
    // V4 SCHEMA — normalized transactions model
    // ════════════════════════════════════════════════════

    public function ensure_v4_schema(): void {
        $db = $this->db();

        // ── parties table ──
        $db->query("
            CREATE TABLE IF NOT EXISTS wp_mf_4_parties (
                id          INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
                name        VARCHAR(100) NOT NULL,
                party_type  ENUM('vendor', 'customer', 'internal') NOT NULL,
                is_active   TINYINT NOT NULL DEFAULT 1,
                created_at  TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                UNIQUE KEY uq_name_type (name, party_type)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
        ");
        $this->check_db('ensure_v4_schema.parties');

        // Seed reserved Internal party (id=1)
        $internal_exists = (int) $db->get_var("SELECT COUNT(*) FROM wp_mf_4_parties WHERE party_type='internal'");
        if (!$internal_exists) {
            $db->query("INSERT INTO wp_mf_4_parties (id, name, party_type) VALUES (1, 'Internal', 'internal')");
            $this->check_db('ensure_v4_schema.seed_internal');
        }

        // Migrate existing vendors into parties
        $v_count = (int) $db->get_var("SELECT COUNT(*) FROM wp_mf_4_parties WHERE party_type='vendor'");
        if (!$v_count) {
            $db->query("
                INSERT IGNORE INTO wp_mf_4_parties (name, party_type, is_active)
                SELECT name, 'vendor', is_active FROM wp_mf_3_dp_vendors
            ");
            $this->check_db('ensure_v4_schema.migrate_vendors');
        }

        // Migrate existing customers into parties
        $c_count = (int) $db->get_var("SELECT COUNT(*) FROM wp_mf_4_parties WHERE party_type='customer'");
        if (!$c_count) {
            $db->query("
                INSERT IGNORE INTO wp_mf_4_parties (name, party_type, is_active)
                SELECT name, 'customer', is_active FROM wp_mf_3_dp_customers
            ");
            $this->check_db('ensure_v4_schema.migrate_customers');
        }

        // ── transactions table ──
        $db->query("
            CREATE TABLE IF NOT EXISTS wp_mf_4_transactions (
                id                  INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
                location_id         INT UNSIGNED NOT NULL,
                transaction_date    DATE NOT NULL,
                transaction_type    ENUM('purchase', 'processing', 'sale') NOT NULL,
                processing_type     VARCHAR(30) NULL COMMENT 'FK to wp_mf_3_dp_production_flows.key; NULL for purchase/sale',
                party_id            INT UNSIGNED NOT NULL COMMENT 'FK to wp_mf_4_parties; Internal(1) for processing',
                created_by          BIGINT UNSIGNED,
                created_at          TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                INDEX idx_t_loc_date (location_id, transaction_date),
                INDEX idx_t_type (transaction_type),
                INDEX idx_t_proc_type (processing_type),
                INDEX idx_t_party (party_id)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
        ");
        $this->check_db('ensure_v4_schema.transactions');

        // ── transaction_lines table ──
        $db->query("
            CREATE TABLE IF NOT EXISTS wp_mf_4_transaction_lines (
                id                      INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
                transaction_id          INT UNSIGNED NOT NULL COMMENT 'FK to wp_mf_4_transactions',
                product_id              INT UNSIGNED NOT NULL COMMENT 'FK to wp_mf_3_dp_products',
                qty                     DECIMAL(10,2) NOT NULL COMMENT 'Signed: + inward, - outward',
                rate                    DECIMAL(10,2) NULL COMMENT 'Purchase/sale rate; NULL for processing',
                source_transaction_id   INT UNSIGNED NULL COMMENT 'FK to wp_mf_4_transactions; purchase this input came from',
                snf                     DECIMAL(4,1) NULL COMMENT 'Only for FF Milk, Skim Milk',
                fat                     DECIMAL(4,1) NULL COMMENT 'Only for FF Milk, Cream, Butter',
                INDEX idx_tl_txn (transaction_id),
                INDEX idx_tl_product (product_id),
                INDEX idx_tl_source (source_transaction_id)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
        ");
        $this->check_db('ensure_v4_schema.transaction_lines');

        // ── FK: transaction_lines → transactions ON DELETE CASCADE ──
        $fk_exists = (int) $db->get_var("
            SELECT COUNT(*) FROM information_schema.TABLE_CONSTRAINTS
            WHERE TABLE_SCHEMA = DATABASE()
              AND TABLE_NAME   = 'wp_mf_4_transaction_lines'
              AND CONSTRAINT_TYPE = 'FOREIGN KEY'
              AND CONSTRAINT_NAME = 'fk_tl_transaction'
        ");
        if (!$fk_exists) {
            // Clean up any orphan lines first
            $db->query("DELETE FROM wp_mf_4_transaction_lines WHERE transaction_id NOT IN (SELECT id FROM wp_mf_4_transactions)");
            $this->check_db('ensure_v4_schema.cleanup_orphan_lines');
            $db->query("ALTER TABLE wp_mf_4_transaction_lines
                ADD CONSTRAINT fk_tl_transaction
                FOREIGN KEY (transaction_id) REFERENCES wp_mf_4_transactions(id)
                ON DELETE CASCADE");
            $this->check_db('ensure_v4_schema.fk_tl_transaction');
        }

        // ── Add notes column if missing (for pouch lines, etc.) ──
        $has_notes = (int) $db->get_var("
            SELECT COUNT(*) FROM information_schema.COLUMNS
            WHERE TABLE_SCHEMA = DATABASE()
              AND TABLE_NAME   = 'wp_mf_4_transactions'
              AND COLUMN_NAME  = 'notes'
        ");
        if (!$has_notes) {
            $db->query("ALTER TABLE wp_mf_4_transactions ADD COLUMN notes TEXT NULL AFTER created_at");
            $this->check_db('ensure_v4_schema.add_notes');
        }
    }

    /**
     * V2 Migration: Create wp_mf_4_vendor_payments and copy data from V3.
     */
    private function ensure_challan_schema(): void {
        $db = $this->db();

        $db->query("
            CREATE TABLE IF NOT EXISTS wp_mf_4_challans (
                id               INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
                location_id      INT UNSIGNED NOT NULL,
                party_id         INT UNSIGNED NOT NULL COMMENT 'FK to wp_mf_4_parties (customer)',
                challan_number   INT UNSIGNED NOT NULL COMMENT 'Sequential per location',
                challan_date     DATE NOT NULL,
                delivery_address TEXT NULL,
                status           ENUM('pending','invoiced') NOT NULL DEFAULT 'pending',
                notes            TEXT NULL,
                created_by       BIGINT UNSIGNED,
                created_at       TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                UNIQUE KEY uq_loc_challan (location_id, challan_number),
                INDEX idx_ch_loc_date (location_id, challan_date),
                INDEX idx_ch_status (status),
                INDEX idx_ch_party (party_id)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
        ");
        $this->check_db('ensure_challan_schema.challans');

        $db->query("
            CREATE TABLE IF NOT EXISTS wp_mf_4_challan_lines (
                id           INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
                challan_id   INT UNSIGNED NOT NULL,
                product_id   INT UNSIGNED NOT NULL,
                qty          DECIMAL(10,2) NOT NULL,
                rate         DECIMAL(10,2) NOT NULL,
                amount       DECIMAL(12,2) NOT NULL,
                created_at   TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                INDEX idx_cl_challan (challan_id)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
        ");
        $this->check_db('ensure_challan_schema.challan_lines');

        // FK: challan_lines → challans ON DELETE CASCADE
        $fk_exists = (int) $db->get_var("
            SELECT COUNT(*) FROM information_schema.TABLE_CONSTRAINTS
            WHERE TABLE_SCHEMA = DATABASE()
              AND TABLE_NAME   = 'wp_mf_4_challan_lines'
              AND CONSTRAINT_TYPE = 'FOREIGN KEY'
              AND CONSTRAINT_NAME = 'fk_cl_challan'
        ");
        if (!$fk_exists) {
            $db->query("ALTER TABLE wp_mf_4_challan_lines
                ADD CONSTRAINT fk_cl_challan
                FOREIGN KEY (challan_id) REFERENCES wp_mf_4_challans(id)
                ON DELETE CASCADE");
            $this->check_db('ensure_challan_schema.fk_cl_challan');
        }

        // Seed report menu
        $ch_exists = (int) $db->get_var("SELECT COUNT(*) FROM wp_mf_3_dp_report_menu WHERE `key`='challans'");
        if (!$ch_exists) {
            $db->insert('wp_mf_3_dp_report_menu', [
                'key'         => 'challans',
                'label'       => 'Delivery Challans',
                'subtitle'    => 'Create and manage delivery challans for customers',
                'sort_order'  => 45,
                'permission'  => 'all',
                'is_active'   => 1,
            ]);
            $this->check_db('ensure_challan_schema.menu_seed');
        }

        $this->log('Challan schema ensured.');
    }

    private function ensure_invoice_schema(): void {
        $db = $this->db();

        $db->query("
            CREATE TABLE IF NOT EXISTS wp_mf_4_invoices (
                id               INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
                location_id      INT UNSIGNED NOT NULL,
                party_id         INT UNSIGNED NOT NULL COMMENT 'FK to wp_mf_4_parties (customer)',
                invoice_number   INT UNSIGNED NOT NULL COMMENT 'Sequential per location',
                invoice_date     DATE NOT NULL,
                subtotal         DECIMAL(12,2) NOT NULL DEFAULT 0,
                tax              DECIMAL(12,2) NOT NULL DEFAULT 0,
                total            DECIMAL(12,2) NOT NULL DEFAULT 0,
                payment_status   ENUM('unpaid','paid') NOT NULL DEFAULT 'unpaid',
                notes            TEXT NULL,
                created_by       BIGINT UNSIGNED,
                created_at       TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                UNIQUE KEY uq_loc_invoice (location_id, invoice_number),
                INDEX idx_inv_loc_date (location_id, invoice_date),
                INDEX idx_inv_status (payment_status),
                INDEX idx_inv_party (party_id)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
        ");
        $this->check_db('ensure_invoice_schema.invoices');

        // Add invoice_id column to challans if not exists
        $has_inv_id = (int) $db->get_var("
            SELECT COUNT(*) FROM information_schema.COLUMNS
            WHERE TABLE_SCHEMA = DATABASE()
              AND TABLE_NAME   = 'wp_mf_4_challans'
              AND COLUMN_NAME  = 'invoice_id'
        ");
        if (!$has_inv_id) {
            $db->query("ALTER TABLE wp_mf_4_challans ADD COLUMN invoice_id INT UNSIGNED NULL AFTER status");
            $this->check_db('ensure_invoice_schema.challans_invoice_id');
        }

        $this->log('Invoice schema ensured.');
    }

    private function migrate_pouch_products_v5(): void {
        $db = $this->db();

        // Rename wp_mf_3_dp_pouch_types → wp_mf_3_dp_pouch_products
        $old_exists = (int) $db->get_var(
            "SELECT COUNT(*) FROM information_schema.TABLES
              WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'wp_mf_3_dp_pouch_types'");
        $new_exists = (int) $db->get_var(
            "SELECT COUNT(*) FROM information_schema.TABLES
              WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'wp_mf_3_dp_pouch_products'");
        if ($old_exists && !$new_exists) {
            $db->query("RENAME TABLE wp_mf_3_dp_pouch_types TO wp_mf_3_dp_pouch_products");
            $this->check_db('v5.rename_pouch_types');
        }

        // Add crate_rate column to pouch_products if missing
        $has_crate_rate = (int) $db->get_var(
            "SELECT COUNT(*) FROM information_schema.COLUMNS
              WHERE TABLE_SCHEMA = DATABASE()
                AND TABLE_NAME = 'wp_mf_3_dp_pouch_products'
                AND COLUMN_NAME = 'crate_rate'");
        if (!$has_crate_rate) {
            $db->query("ALTER TABLE wp_mf_3_dp_pouch_products
                ADD COLUMN crate_rate DECIMAL(10,2) NOT NULL DEFAULT 0 AFTER pouches_per_crate");
            $this->check_db('v5.add_crate_rate');

            // Migrate existing rates from pouch_rates table into the new column
            $db->query("
                UPDATE wp_mf_3_dp_pouch_products pp
                  JOIN wp_mf_3_dp_pouch_rates pr ON pr.pouch_type_id = pp.id
                   SET pp.crate_rate = pr.rate_per_crate
            ");
            $this->check_db('v5.migrate_crate_rates');
        }

        // Add pouch_product_id column to challan_lines if missing
        $has_ppid = (int) $db->get_var(
            "SELECT COUNT(*) FROM information_schema.COLUMNS
              WHERE TABLE_SCHEMA = DATABASE()
                AND TABLE_NAME = 'wp_mf_4_challan_lines'
                AND COLUMN_NAME = 'pouch_product_id'");
        if (!$has_ppid) {
            $db->query("ALTER TABLE wp_mf_4_challan_lines
                ADD COLUMN pouch_product_id INT UNSIGNED NULL AFTER product_id");
            $this->check_db('v5.challan_lines_pouch_product_id');
        }

        // Make product_id nullable (it was NOT NULL before; pouch lines will have product_id=NULL)
        $db->query("ALTER TABLE wp_mf_4_challan_lines
            MODIFY COLUMN product_id INT UNSIGNED NULL");
        $this->check_db('v5.challan_lines_product_id_nullable');

        // Add Pouch Milk as product ID 12 (category placeholder for customer assignment)
        $pm_exists = (int) $db->get_var("SELECT COUNT(*) FROM wp_mf_3_dp_products WHERE id = 12");
        if (!$pm_exists) {
            $this->safe_insert('wp_mf_3_dp_products', [
                'id'         => 12,
                'name'       => 'Pouch Milk',
                'unit'       => 'crates',
                'sort_order' => 60,
                'is_active'  => 1,
            ], 'v5.pouch_milk_product');
            // Verify the insert actually worked
            $verify = (int) $db->get_var("SELECT COUNT(*) FROM wp_mf_3_dp_products WHERE id = 12");
            if (!$verify) {
                $this->log('CRITICAL: Product 12 (Pouch Milk) insert was not persisted! Manual intervention needed.');
            }
        }

        $this->log('V5 pouch_products migration complete.');
    }

    /**
     * V6: Retire wp_mf_3_dp_customers — move customer_products & customer_location_access to use party_id from wp_mf_4_parties.
     * Steps:
     * 1. Ensure any customers in wp_mf_3_dp_customers that are missing from wp_mf_4_parties get inserted
     * 2. Add party_id column to customer_products and customer_location_access
     * 3. Populate party_id by joining on customer name
     * 4. Drop old customer_id column (after removing unique constraints that include it)
     * 5. Add new unique constraints on party_id
     * 6. Rename wp_mf_3_dp_customers → wp_xx3_dp_customers
     */
    private function migrate_customers_to_parties_v6(): void {
        $db = $this->db();

        // 1. Sync: ensure all customers exist in parties table
        $missing = $db->get_results("
            SELECT c.id, c.name, c.is_active
              FROM wp_mf_3_dp_customers c
              LEFT JOIN wp_mf_4_parties p ON p.name = c.name AND p.party_type = 'customer'
             WHERE p.id IS NULL
        ", ARRAY_A) ?? [];
        foreach ($missing as $m) {
            $result = $db->insert('wp_mf_4_parties', [
                'name'       => $m['name'],
                'party_type' => 'customer',
                'is_active'  => (int) $m['is_active'],
            ]);
            if ($result === false) {
                $this->log("V6: FAILED to insert missing customer '{$m['name']}' into parties: " . ($db->last_error ?: '(no error)'));
            } else {
                $this->log("V6: Synced customer '{$m['name']}' to parties, party_id={$db->insert_id}");
            }
        }

        // 2a. Add party_id to customer_products
        $has_party_id_cp = (int) $db->get_var("
            SELECT COUNT(*) FROM information_schema.COLUMNS
             WHERE TABLE_SCHEMA = DATABASE()
               AND TABLE_NAME = 'wp_mf_3_dp_customer_products'
               AND COLUMN_NAME = 'party_id'");
        if (!$has_party_id_cp) {
            $db->query("ALTER TABLE wp_mf_3_dp_customer_products ADD COLUMN party_id INT UNSIGNED NULL AFTER customer_id");
            $this->check_db('v6.cp_add_party_id');

            // Populate party_id by joining customer name → party name
            $db->query("
                UPDATE wp_mf_3_dp_customer_products cp
                  JOIN wp_mf_3_dp_customers c ON c.id = cp.customer_id
                  JOIN wp_mf_4_parties p ON p.name = c.name AND p.party_type = 'customer'
                   SET cp.party_id = p.id
            ");
            $this->check_db('v6.cp_populate_party_id');

            // Log any unmapped rows
            $unmapped = (int) $db->get_var("SELECT COUNT(*) FROM wp_mf_3_dp_customer_products WHERE party_id IS NULL");
            if ($unmapped) {
                $this->log("V6 WARNING: $unmapped customer_products rows have NULL party_id after migration!");
            } else {
                $this->log("V6: All customer_products rows mapped to party_id successfully.");
            }

            // Drop old unique constraint on (customer_id, product_id), add new one on (party_id, product_id)
            $db->query("ALTER TABLE wp_mf_3_dp_customer_products DROP INDEX uq_cust_prod");
            $this->check_db('v6.cp_drop_old_uq');
            $db->query("ALTER TABLE wp_mf_3_dp_customer_products DROP COLUMN customer_id");
            $this->check_db('v6.cp_drop_customer_id');
            $db->query("ALTER TABLE wp_mf_3_dp_customer_products MODIFY COLUMN party_id INT UNSIGNED NOT NULL");
            $this->check_db('v6.cp_party_id_not_null');
            $db->query("ALTER TABLE wp_mf_3_dp_customer_products ADD UNIQUE KEY uq_party_prod (party_id, product_id)");
            $this->check_db('v6.cp_add_uq');
        }

        // 2b. Add party_id to customer_location_access
        $has_party_id_cla = (int) $db->get_var("
            SELECT COUNT(*) FROM information_schema.COLUMNS
             WHERE TABLE_SCHEMA = DATABASE()
               AND TABLE_NAME = 'wp_mf_3_dp_customer_location_access'
               AND COLUMN_NAME = 'party_id'");
        if (!$has_party_id_cla) {
            $db->query("ALTER TABLE wp_mf_3_dp_customer_location_access ADD COLUMN party_id INT UNSIGNED NULL AFTER customer_id");
            $this->check_db('v6.cla_add_party_id');

            $db->query("
                UPDATE wp_mf_3_dp_customer_location_access cla
                  JOIN wp_mf_3_dp_customers c ON c.id = cla.customer_id
                  JOIN wp_mf_4_parties p ON p.name = c.name AND p.party_type = 'customer'
                   SET cla.party_id = p.id
            ");
            $this->check_db('v6.cla_populate_party_id');

            $unmapped = (int) $db->get_var("SELECT COUNT(*) FROM wp_mf_3_dp_customer_location_access WHERE party_id IS NULL");
            if ($unmapped) {
                $this->log("V6 WARNING: $unmapped customer_location_access rows have NULL party_id after migration!");
            } else {
                $this->log("V6: All customer_location_access rows mapped to party_id successfully.");
            }

            $db->query("ALTER TABLE wp_mf_3_dp_customer_location_access DROP INDEX uq_cust_loc");
            $this->check_db('v6.cla_drop_old_uq');
            $db->query("ALTER TABLE wp_mf_3_dp_customer_location_access DROP COLUMN customer_id");
            $this->check_db('v6.cla_drop_customer_id');
            $db->query("ALTER TABLE wp_mf_3_dp_customer_location_access MODIFY COLUMN party_id INT UNSIGNED NOT NULL");
            $this->check_db('v6.cla_party_id_not_null');
            $db->query("ALTER TABLE wp_mf_3_dp_customer_location_access ADD UNIQUE KEY uq_party_loc (party_id, location_id)");
            $this->check_db('v6.cla_add_uq');
        }

        // 3. Rename old customers table
        $old_exists = (int) $db->get_var(
            "SELECT COUNT(*) FROM information_schema.TABLES
              WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'wp_mf_3_dp_customers'");
        $xx_exists = (int) $db->get_var(
            "SELECT COUNT(*) FROM information_schema.TABLES
              WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'wp_xx3_dp_customers'");
        if ($old_exists && !$xx_exists) {
            $db->query("RENAME TABLE wp_mf_3_dp_customers TO wp_xx3_dp_customers");
            $this->check_db('v6.rename_customers');
            $this->log('V6: Renamed wp_mf_3_dp_customers → wp_xx3_dp_customers');
        }

        // Verify
        $cp_count = (int) $db->get_var("SELECT COUNT(*) FROM wp_mf_3_dp_customer_products WHERE party_id IS NOT NULL");
        $cla_count = (int) $db->get_var("SELECT COUNT(*) FROM wp_mf_3_dp_customer_location_access WHERE party_id IS NOT NULL");
        $this->log("V6 migration complete. customer_products=$cp_count rows, customer_location_access=$cla_count rows.");
    }

    private function migrate_vendor_payments_v4(): void {
        $db = $this->db();

        // Create V4 vendor payments table with party_id
        $db->query("
            CREATE TABLE IF NOT EXISTS wp_mf_4_vendor_payments (
                id           INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
                party_id     INT UNSIGNED NOT NULL COMMENT 'FK to wp_mf_4_parties',
                payment_date DATE NOT NULL,
                amount       DECIMAL(12,2) NOT NULL,
                method       VARCHAR(30) NOT NULL DEFAULT 'Cash',
                note         VARCHAR(255) DEFAULT NULL,
                created_by   BIGINT UNSIGNED NOT NULL,
                created_at   TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                INDEX idx_v4vp_party (party_id),
                INDEX idx_v4vp_date (payment_date)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
        ");
        $this->check_db('migrate_vendor_payments_v4.create_table');

        // Copy data from V3 → V4, matching vendor_id → party_id by vendor name
        $v4_count = (int) $db->get_var("SELECT COUNT(*) FROM wp_mf_4_vendor_payments");
        if ($v4_count === 0) {
            $v3_exists = (int) $db->get_var(
                "SELECT COUNT(*) FROM information_schema.TABLES
                 WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'wp_mf_3_dp_vendor_payments'"
            );
            if ($v3_exists) {
                $db->query("
                    INSERT INTO wp_mf_4_vendor_payments (party_id, payment_date, amount, method, note, created_by, created_at)
                    SELECT p.id, vp.payment_date, vp.amount, vp.method, vp.note, vp.created_by, vp.created_at
                      FROM wp_mf_3_dp_vendor_payments vp
                      JOIN wp_mf_3_dp_vendors v ON v.id = vp.vendor_id
                      JOIN wp_mf_4_parties p ON p.name = v.name AND p.party_type = 'vendor'
                ");
                $this->check_db('migrate_vendor_payments_v4.copy_data');
                $copied = (int) $db->get_var("SELECT COUNT(*) FROM wp_mf_4_vendor_payments");
                $this->log("Migrated $copied vendor payment rows from V3 to V4.");
            }
        }
    }

    /**
     * V2 Migration: Rename all unused V3 data tables (wp_mf_3 → wp_mf_xx3).
     * All save/read endpoints now use V4 tables exclusively.
     */
    private function rename_unused_v3_tables(): void {
        $db = $this->db();
        $tables = [
            'wp_mf_3_dp_milk_cream_production',
            'wp_mf_3_dp_cream_butter_ghee',
            'wp_mf_3_dp_butter_ghee',
            'wp_mf_3_dp_dahi_production',
            'wp_mf_3_dp_sales',
            'wp_mf_3_dp_ingredient_purchase',
            'wp_mf_3_dp_madhusudan_sale',
            'wp_mf_3_dp_pouch_production',
            'wp_mf_3_dp_pouch_production_lines',
            'wp_mf_3_dp_curd_production',
            'wp_mf_3_dp_milk_usage',
            'wp_mf_3_dp_vendor_payments',
        ];
        $renamed = 0;
        foreach ($tables as $tbl) {
            $new_name = str_replace('wp_mf_3_dp_', 'wp_mf_xx3_dp_', $tbl);
            $exists = (int) $db->get_var($db->prepare(
                "SELECT COUNT(*) FROM information_schema.TABLES
                 WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = %s", $tbl));
            if ($exists) {
                $db->query("RENAME TABLE `$tbl` TO `$new_name`");
                $this->check_db("rename_unused_v3_tables.$tbl");
                $renamed++;
            }
        }
        $this->log("Renamed $renamed unused V3 data tables (wp_mf_3 → wp_mf_xx3).");
    }

    /**
     * V7 Migration: Drop unused V3 data tables that were re-created empty by ensure_dahi_product()
     * after V2 had renamed them to wp_mf_xx3_dp_*. The _xx3_ copies hold archived data.
     * Also renames pouch_types (leftover from V5 rename to pouch_products).
     * pouch_rates was removed — rates consolidated into pouch_products.crate_rate.
     */
    private function cleanup_unused_v3_tables_v7(): void {
        $db = $this->db();

        // These 7 tables have both _3_ (empty, re-created) and _xx3_ (archived) copies.
        // Drop the empty _3_ copies.
        $drop_tables = [
            'wp_mf_3_dp_curd_production',
            'wp_mf_3_dp_ingredient_purchase',
            'wp_mf_3_dp_milk_usage',
            'wp_mf_3_dp_madhusudan_sale',
            'wp_mf_3_dp_pouch_production',
            'wp_mf_3_dp_pouch_production_lines',
            'wp_mf_3_dp_vendor_payments',
        ];
        $dropped = 0;
        foreach ($drop_tables as $tbl) {
            $exists = (int) $db->get_var($db->prepare(
                "SELECT COUNT(*) FROM information_schema.TABLES
                 WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = %s", $tbl));
            if ($exists) {
                $row_count = (int) $db->get_var("SELECT COUNT(*) FROM `$tbl`");
                $this->log("V7: Dropping $tbl ($row_count rows — empty re-created copy)");
                $db->query("DROP TABLE `$tbl`");
                $this->check_db("v7.drop.$tbl");
                $dropped++;
            }
        }

        // Rename pouch_types if it still exists (leftover from V5 rename to pouch_products)
        $pt_exists = (int) $db->get_var(
            "SELECT COUNT(*) FROM information_schema.TABLES
             WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'wp_mf_3_dp_pouch_types'");
        if ($pt_exists) {
            $db->query("RENAME TABLE wp_mf_3_dp_pouch_types TO wp_mf_xx3_dp_pouch_types");
            $this->check_db('v7.rename_pouch_types');
            $this->log("V7: Renamed wp_mf_3_dp_pouch_types → wp_mf_xx3_dp_pouch_types");
        }

        $this->log("V7: Dropped $dropped unused V3 tables.");
    }

    /**
     * V8: Retire wp_mf_3_dp_vendors — move vendor_location_access & vendor_products to use party_id.
     * Same pattern as V6 (customers → parties).
     */
    private function migrate_vendors_to_parties_v8(): void {
        $db = $this->db();

        // 1. Sync: ensure all vendors exist in parties table
        $missing = $db->get_results("
            SELECT v.id, v.name, v.is_active
              FROM wp_mf_3_dp_vendors v
              LEFT JOIN wp_mf_4_parties p ON p.name = v.name AND p.party_type = 'vendor'
             WHERE p.id IS NULL
        ", ARRAY_A) ?? [];
        foreach ($missing as $m) {
            $result = $db->insert('wp_mf_4_parties', [
                'name'       => $m['name'],
                'party_type' => 'vendor',
                'is_active'  => (int) $m['is_active'],
            ]);
            if ($result === false) {
                $this->log("V8: FAILED to insert missing vendor '{$m['name']}' into parties: " . ($db->last_error ?: '(no error)'));
            } else {
                $this->log("V8: Synced vendor '{$m['name']}' to parties, party_id={$db->insert_id}");
            }
        }

        // 2a. Add party_id to vendor_location_access
        $has_pid_vla = (int) $db->get_var("
            SELECT COUNT(*) FROM information_schema.COLUMNS
             WHERE TABLE_SCHEMA = DATABASE()
               AND TABLE_NAME = 'wp_mf_3_dp_vendor_location_access'
               AND COLUMN_NAME = 'party_id'");
        if (!$has_pid_vla) {
            $db->query("ALTER TABLE wp_mf_3_dp_vendor_location_access ADD COLUMN party_id INT UNSIGNED NULL AFTER vendor_id");
            $this->check_db('v8.vla_add_party_id');

            $db->query("
                UPDATE wp_mf_3_dp_vendor_location_access vla
                  JOIN wp_mf_3_dp_vendors v ON v.id = vla.vendor_id
                  JOIN wp_mf_4_parties p ON p.name = v.name AND p.party_type = 'vendor'
                   SET vla.party_id = p.id
            ");
            $this->check_db('v8.vla_populate_party_id');

            // Delete orphan rows where vendor_id had no match in vendors table (NULL or 0 party_id)
            $unmapped = (int) $db->get_var("SELECT COUNT(*) FROM wp_mf_3_dp_vendor_location_access WHERE party_id IS NULL OR party_id = 0");
            if ($unmapped) {
                $db->query("DELETE FROM wp_mf_3_dp_vendor_location_access WHERE party_id IS NULL OR party_id = 0");
                $this->check_db('v8.vla_delete_orphans');
                $this->log("V8: Deleted $unmapped orphan vendor_location_access rows (no matching vendor in parties).");
            } else {
                $this->log("V8: All vendor_location_access rows mapped to party_id successfully.");
            }

            $db->query("ALTER TABLE wp_mf_3_dp_vendor_location_access DROP INDEX uq_vendor_location");
            $this->check_db('v8.vla_drop_old_uq');
            $db->query("ALTER TABLE wp_mf_3_dp_vendor_location_access DROP COLUMN vendor_id");
            $this->check_db('v8.vla_drop_vendor_id');
            $db->query("ALTER TABLE wp_mf_3_dp_vendor_location_access MODIFY COLUMN party_id INT UNSIGNED NOT NULL");
            $this->check_db('v8.vla_party_id_not_null');
            $db->query("ALTER TABLE wp_mf_3_dp_vendor_location_access ADD UNIQUE KEY uq_party_loc (party_id, location_id)");
            $this->check_db('v8.vla_add_uq');
        }

        // 2b. Add party_id to vendor_products
        $has_pid_vp = (int) $db->get_var("
            SELECT COUNT(*) FROM information_schema.COLUMNS
             WHERE TABLE_SCHEMA = DATABASE()
               AND TABLE_NAME = 'wp_mf_3_dp_vendor_products'
               AND COLUMN_NAME = 'party_id'");
        if (!$has_pid_vp) {
            $db->query("ALTER TABLE wp_mf_3_dp_vendor_products ADD COLUMN party_id INT UNSIGNED NULL AFTER vendor_id");
            $this->check_db('v8.vp_add_party_id');

            $db->query("
                UPDATE wp_mf_3_dp_vendor_products vp
                  JOIN wp_mf_3_dp_vendors v ON v.id = vp.vendor_id
                  JOIN wp_mf_4_parties p ON p.name = v.name AND p.party_type = 'vendor'
                   SET vp.party_id = p.id
            ");
            $this->check_db('v8.vp_populate_party_id');

            $unmapped = (int) $db->get_var("SELECT COUNT(*) FROM wp_mf_3_dp_vendor_products WHERE party_id IS NULL OR party_id = 0");
            if ($unmapped) {
                $db->query("DELETE FROM wp_mf_3_dp_vendor_products WHERE party_id IS NULL OR party_id = 0");
                $this->check_db('v8.vp_delete_orphans');
                $this->log("V8: Deleted $unmapped orphan vendor_products rows.");
            } else {
                $this->log("V8: All vendor_products rows mapped to party_id successfully.");
            }

            $db->query("ALTER TABLE wp_mf_3_dp_vendor_products DROP INDEX uq_vend_prod");
            $this->check_db('v8.vp_drop_old_uq');
            $db->query("ALTER TABLE wp_mf_3_dp_vendor_products DROP COLUMN vendor_id");
            $this->check_db('v8.vp_drop_vendor_id');
            $db->query("ALTER TABLE wp_mf_3_dp_vendor_products MODIFY COLUMN party_id INT UNSIGNED NOT NULL");
            $this->check_db('v8.vp_party_id_not_null');
            $db->query("ALTER TABLE wp_mf_3_dp_vendor_products ADD UNIQUE KEY uq_party_prod (party_id, product_id)");
            $this->check_db('v8.vp_add_uq');
        }

        // 3. Rename old vendors table
        $old_exists = (int) $db->get_var(
            "SELECT COUNT(*) FROM information_schema.TABLES
              WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'wp_mf_3_dp_vendors'");
        $xx_exists = (int) $db->get_var(
            "SELECT COUNT(*) FROM information_schema.TABLES
              WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'wp_xx3_dp_vendors'");
        if ($old_exists && !$xx_exists) {
            $db->query("RENAME TABLE wp_mf_3_dp_vendors TO wp_xx3_dp_vendors");
            $this->check_db('v8.rename_vendors');
            $this->log('V8: Renamed wp_mf_3_dp_vendors → wp_xx3_dp_vendors');
        }

        // Verify
        $vla_count = (int) $db->get_var("SELECT COUNT(*) FROM wp_mf_3_dp_vendor_location_access WHERE party_id IS NOT NULL");
        $vp_count = (int) $db->get_var("SELECT COUNT(*) FROM wp_mf_3_dp_vendor_products WHERE party_id IS NOT NULL");
        $this->log("V8 migration complete. vendor_location_access=$vla_count rows, vendor_products=$vp_count rows.");
    }

    /**
     * V9: Create party_addresses table for billing and shipping addresses.
     */
    private function ensure_party_addresses_v9(): void {
        $db = $this->db();
        $db->query("
            CREATE TABLE IF NOT EXISTS wp_mf_3_dp_party_addresses (
                id           INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
                party_id     INT UNSIGNED NOT NULL COMMENT 'FK to wp_mf_4_parties',
                address_type ENUM('billing','shipping') NOT NULL,
                label        VARCHAR(100) NULL COMMENT 'User-friendly name, e.g. Warehouse A',
                address_text TEXT NOT NULL,
                is_default   TINYINT NOT NULL DEFAULT 0,
                is_active    TINYINT NOT NULL DEFAULT 1,
                created_at   TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                KEY idx_pa_party (party_id),
                KEY idx_pa_party_type (party_id, address_type)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
        ");
        $this->check_db('v9.party_addresses_table');
        $this->log('V9: party_addresses table created.');
    }

    private function ensure_document_addresses_v10(): void {
        $db = $this->db();

        // Add address snapshot columns to challans
        $exists = $db->get_var("SELECT COUNT(*) FROM information_schema.COLUMNS
            WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'wp_mf_4_challans'
            AND COLUMN_NAME = 'billing_address_snapshot'");
        if (!$exists) {
            $db->query("ALTER TABLE wp_mf_4_challans
                ADD COLUMN billing_address_snapshot TEXT NULL AFTER delivery_address,
                ADD COLUMN shipping_address_snapshot TEXT NULL AFTER billing_address_snapshot");
            $this->check_db('v10.challans_address_cols');
        }

        // Add address snapshot columns to invoices
        $exists = $db->get_var("SELECT COUNT(*) FROM information_schema.COLUMNS
            WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'wp_mf_4_invoices'
            AND COLUMN_NAME = 'billing_address_snapshot'");
        if (!$exists) {
            $db->query("ALTER TABLE wp_mf_4_invoices
                ADD COLUMN billing_address_snapshot TEXT NULL AFTER notes,
                ADD COLUMN shipping_address_snapshot TEXT NULL AFTER billing_address_snapshot");
            $this->check_db('v10.invoices_address_cols');
        }

        // Seed company settings as WP options (only if not already set)
        if (!get_option('dairy_company_name')) {
            update_option('dairy_company_name', 'Your Company Name');
            update_option('dairy_company_address', '');
            update_option('dairy_company_phone', '');
            update_option('dairy_company_email', '');
            update_option('dairy_company_website', '');
            update_option('dairy_company_gstin', '');
            update_option('dairy_company_signatory', '');
        }
        $this->log('V10: document address snapshots + company settings seeded.');
    }

    public function register_routes(): void {
        $auth = [ 'permission_callback' => [ $this, 'require_auth' ] ];

        // Permissions — called after login to get the full permissions object
        $this->r('/me',                'GET',  'get_me',                 $auth);

        $this->r('/locations',         'GET',  'get_locations',          $auth);
        $this->r('/products',          'GET',  'get_products',           $auth);
        // V3 production routes removed — Flutter uses /v4/transaction exclusively
        $this->r('/customers',         'GET',  'get_customers',          $auth);
        $this->r('/customers',         'POST', 'save_customer',           $auth);
        $this->r('/customers/(?P<id>\\d+)', 'POST', 'update_customer',    $auth);
        $this->r('/vendors',           'POST', 'save_vendor',             $auth);
        $this->r('/vendors/(?P<id>\\d+)', 'POST', 'update_vendor',        $auth);
        $this->r('/admin/products',    'GET',  'get_admin_products',      $auth);
        $this->r('/admin/products/(?P<id>\\d+)', 'POST', 'update_product', $auth);
        $this->r('/vendors',           'GET',  'get_vendors',            $auth);
        // V3 sales GET/POST/DELETE routes removed — Flutter uses /v4/transaction exclusively
        $this->r('/sales-report',      'GET',  'get_sales_report',       $auth);
        $this->r('/vendor-purchase-report','GET', 'get_vendor_purchase_report', $auth);
        $this->r('/stock',             'GET',  'get_stock',              $auth);
        $this->r('/estimated-rates',   'GET',  'get_estimated_rates',    $auth);
        $this->r('/estimated-rates',   'POST', 'update_estimated_rates', $auth);
        $this->r('/stock-valuation',   'GET',  'get_stock_valuation',    $auth);
        $this->r('/audit-log',              'GET',  'get_audit_log',              $auth);
        $this->r('/settings',               'GET',  'get_settings',               $auth);
        $this->r('/production-transactions','GET',  'get_production_transactions', $auth);
        $this->r('/sales-transactions',     'GET',  'get_sales_transactions',      $auth);
        $this->r('/anomalies',              'GET',  'get_anomalies',               $auth);
        $this->r('/vendor-payment',         'POST', 'save_vendor_payment',         $auth);
        $this->r('/vendor-ledger',          'GET',  'get_vendor_ledger',           $auth);
        $this->r('/vendor-ledger-detail',   'GET',  'get_vendor_ledger_detail',    $auth);
        $this->r('/funds-report',           'GET',  'get_funds_report',            $auth);
        // V3 milk-availability route removed — Flutter uses /v4/milk-availability
        $this->r('/pouch-products',            'GET',  'get_pouch_products',          $auth);
        $this->r('/pouch-products',            'POST', 'save_pouch_product',          $auth);
        $this->r('/pouch-products/(?P<id>\\d+)','POST','update_pouch_product',       $auth);
        // Per-customer pouch rates
        $this->r('/customer-pouch-rates',              'GET',  'get_customer_pouch_rates',    $auth);
        $this->r('/customer-pouch-rates',              'POST', 'save_customer_pouch_rate',    $auth);
        $this->r('/customer-pouch-rates/(?P<id>\\d+)', 'DELETE','delete_customer_pouch_rate', $auth);
        // V3 pouch-production/stock routes removed — Flutter uses /v4/transaction
        // pouch-rates routes removed — rates live in pouch_products.crate_rate
        $this->r('/pouch-pnl',              'GET',  'get_pouch_pnl',              $auth);
        // V3 madhusudan-sale routes removed — Flutter uses /v4/transaction
        $this->r('/madhusudan-pnl',       'GET',  'get_madhusudan_pnl',      $auth);
        // V3 curd-production routes removed — Flutter uses /v4/transaction
        $this->r('/production-flows',   'GET',  'get_production_flows',    $auth);
        $this->r('/cashflow-report',       'GET',  'get_cashflow_report',       $auth);
        $this->r('/cash-stock-report',     'GET',  'get_cash_stock_report',     $auth);
        $this->r('/sales-ledger',          'GET',  'get_sales_ledger',          $auth);
        $this->r('/profitability-report',  'GET',  'get_profitability_report',  $auth);
        $this->r('/report-menu',           'GET',  'get_report_menu',           $auth);
        $this->r('/report-email-schedules',     'GET',  'get_report_email_schedules',     $auth);
        $this->r('/report-email-schedule',      'POST', 'save_report_email_schedule',     $auth);
        $this->r('/report-email-schedule/(?P<id>\\d+)', 'DELETE', 'delete_report_email_schedule', $auth);

        // ── V4 endpoints ──
        $this->r('/v4/parties',                      'GET',    'get_v4_parties',            $auth);
        $this->r('/v4/transaction',                  'POST',   'save_v4_transaction',       $auth);
        $this->r('/v4/transactions',                 'GET',    'get_v4_transactions',       $auth);
        $this->r('/v4/transaction/(?P<id>\\d+)',     'DELETE', 'delete_v4_transaction',     $auth);
        $this->r('/v4/stock',                        'GET',    'get_v4_stock',              $auth);
        $this->r('/v4/stock-flow',                   'GET',    'get_v4_stock_flow',         $auth);
        $this->r('/v4/milk-availability',            'GET',    'get_v4_milk_availability',  $auth);

        // ── V4 Challan endpoints ──
        $this->r('/v4/challans',                     'GET',    'get_v4_challans',           $auth);
        $this->r('/v4/challan',                      'POST',   'save_v4_challan',           $auth);
        $this->r('/v4/challan/(?P<id>\\d+)',         'DELETE', 'delete_v4_challan',         $auth);

        // ── V4 Invoice endpoints ──
        $this->r('/v4/invoices',                     'GET',    'get_v4_invoices',           $auth);
        $this->r('/v4/invoice',                      'POST',   'save_v4_invoice',           $auth);
        $this->r('/v4/invoice/(?P<id>\\d+)',         'DELETE', 'delete_v4_invoice',         $auth);
        $this->r('/v4/invoice/(?P<id>\\d+)/pay',     'POST',   'mark_invoice_paid',         $auth);

        // ── Company settings endpoints ──
        $this->r('/company-settings',                'GET',    'get_company_settings',      $auth);
        $this->r('/company-settings',                'POST',   'save_company_settings',     $auth);

        $this->r('/report-email-schedule/(?P<id>\\d+)/send', 'POST', 'test_report_email',  $auth);
    }

    private function r( string $path, string $method, string $cb, array $extra = [] ): void {
        $methods_map = [
            'GET'    => WP_REST_Server::READABLE,
            'POST'   => WP_REST_Server::CREATABLE,
            'PUT'    => WP_REST_Server::EDITABLE,
            'PATCH'  => WP_REST_Server::EDITABLE,
            'DELETE' => WP_REST_Server::DELETABLE,
        ];
        register_rest_route(self::NS, $path, array_merge([
            'methods'  => $methods_map[$method] ?? $method,
            'callback' => [ $this, $cb ],
        ], $extra));
    }

    // ════════════════════════════════════════════════════
    // /me — permissions object
    // ════════════════════════════════════════════════════

    public function get_me(): WP_REST_Response {
        try {
            $uid  = $this->uid();
            $user = wp_get_current_user();
            return $this->ok([
                'user' => [
                    'id'           => $uid,
                    'username'     => $user->user_login,
                    'email'        => $user->user_email,
                    'display_name' => $user->display_name,
                ],
                'permissions' => $this->build_permissions($uid),
            ]);
        } catch (\Exception $e) { return $this->exc('get_me', $e); }
    }

    // ════════════════════════════════════════════════════
    // INPUT VALIDATION HELPERS
    // ════════════════════════════════════════════════════

    private function validate_loc_date( WP_REST_Request $r ): ?WP_REST_Response {
        $loc = $r->get_param('location_id');
        $dt  = $r->get_param('entry_date');
        if ( empty($loc) || ! ctype_digit((string) $loc) )
            return $this->err('location_id is required and must be a positive integer.');
        if ( empty($dt) || ! preg_match('/^\d{4}-\d{2}-\d{2}$/', $dt) )
            return $this->err('entry_date is required in YYYY-MM-DD format.');
        [$y, $m, $d] = explode('-', $dt);
        if ( ! checkdate((int)$m, (int)$d, (int)$y) )
            return $this->err('entry_date is not a valid calendar date.');
        return null;
    }

    private function validate_loc( WP_REST_Request $r ): ?WP_REST_Response {
        $loc = $r->get_param('location_id');
        if ( empty($loc) || ! ctype_digit((string) $loc) )
            return $this->err('location_id is required and must be a positive integer.');
        return null;
    }

    // ════════════════════════════════════════════════════
    // REFERENCE DATA
    // ════════════════════════════════════════════════════

    /**
     * Returns only locations the current user is permitted to access.
     */
    public function get_locations(): WP_REST_Response {
        try {
            $uid       = $this->uid();
            $perms     = $this->build_permissions($uid);
            return $this->ok($perms['locations']);
        } catch (\Exception $e) { return $this->exc('get_locations', $e); }
    }

    public function get_products(): WP_REST_Response {
        try {
            $rows = $this->db()->get_results(
                "SELECT id, name, unit FROM wp_mf_3_dp_products
                  WHERE is_active=1 ORDER BY sort_order", ARRAY_A);
            $this->check_db('get_products');
            return $this->ok($rows);
        } catch (\Exception $e) { return $this->exc('get_products', $e); }
    }

    // V3 Flows 1-4 (get/save milk-cream, cream-butter-ghee, butter-ghee, dahi) removed — Flutter uses /v4/transaction

    // ════════════════════════════════════════════════════
    // CUSTOMERS & VENDORS
    // ════════════════════════════════════════════════════

    // V6: All customer CRUD now uses wp_mf_4_parties + party_id in join tables
    public function get_customers( WP_REST_Request $r ): WP_REST_Response {
        try {
            $db   = $this->db();
            $pid  = (int) ($r->get_param('product_id') ?? 0);
            $all  = (int) ($r->get_param('all') ?? 0);
            $active_clause = $all ? '' : "AND p.is_active=1";
            if ($pid) {
                $rows = $db->get_results($db->prepare(
                    "SELECT p.id, p.name, p.is_active
                       FROM wp_mf_4_parties p
                       JOIN wp_mf_3_dp_customer_products cp ON cp.party_id = p.id
                      WHERE p.party_type='customer' AND cp.product_id=%d $active_clause
                      ORDER BY p.name", $pid), ARRAY_A);
            } else {
                $active_where = $all ? "party_type='customer'" : "party_type='customer' AND is_active=1";
                $rows = $db->get_results(
                    "SELECT id, name, is_active FROM wp_mf_4_parties WHERE $active_where ORDER BY name",
                    ARRAY_A);
            }
            $this->check_db('get_customers');
            // Attach product_ids and location_ids (now keyed by party_id)
            $all_cp = $db->get_results("SELECT party_id, product_id FROM wp_mf_3_dp_customer_products", ARRAY_A);
            $cp_map = [];
            foreach ($all_cp as $cp) { $cp_map[(int)$cp['party_id']][] = (int)$cp['product_id']; }
            $all_cl = $db->get_results("SELECT party_id, location_id FROM wp_mf_3_dp_customer_location_access", ARRAY_A);
            $cl_map = [];
            foreach ($all_cl as $cl) { $cl_map[(int)$cl['party_id']][] = (int)$cl['location_id']; }
            // Attach addresses
            $all_addr = $db->get_results(
                "SELECT id, party_id, address_type, label, address_text, is_default
                   FROM wp_mf_3_dp_party_addresses
                  WHERE is_active = 1
                  ORDER BY party_id, address_type, is_default DESC", ARRAY_A) ?? [];
            $addr_map = [];
            foreach ($all_addr as $a) { $addr_map[(int)$a['party_id']][] = $a; }
            foreach ($rows as &$row) {
                $row['product_ids']  = $cp_map[(int)$row['id']] ?? [];
                $row['location_ids'] = $cl_map[(int)$row['id']] ?? [];
                $row['addresses']    = $addr_map[(int)$row['id']] ?? [];
            }
            return $this->ok($rows ?? []);
        } catch (\Exception $e) { return $this->exc('get_customers', $e); }
    }

    public function save_customer( WP_REST_Request $r ): WP_REST_Response {
        if ($e = $this->check_finance_access($this->uid())) return $e;
        try {
            $db   = $this->db();
            $name = trim($r->get_param('name') ?? '');
            $pids = $r->get_param('product_ids') ?? [];
            $lids = $r->get_param('location_ids') ?? [];
            if (!$name) return $this->err('Name is required.');
            if (empty($pids) || !is_array($pids)) return $this->err('At least one product is required.');
            $dup = $db->get_var($db->prepare(
                "SELECT COUNT(*) FROM wp_mf_4_parties WHERE name=%s AND party_type='customer'", $name));
            if ($dup) return $this->err('Customer name already exists.');
            if (!$this->safe_insert('wp_mf_4_parties', [
                'name' => $name, 'party_type' => 'customer', 'is_active' => 1,
            ], 'save_customer')) {
                return $this->err('Database error.', 500);
            }
            $party_id = $db->insert_id;
            $this->log("save_customer: created party_id=$party_id name=$name");
            foreach ($pids as $pid) {
                $this->safe_insert('wp_mf_3_dp_customer_products', ['party_id' => $party_id, 'product_id' => (int)$pid], 'save_customer.cp');
            }
            if (!empty($lids) && is_array($lids)) {
                foreach ($lids as $lid) {
                    $this->safe_insert('wp_mf_3_dp_customer_location_access', ['party_id' => $party_id, 'location_id' => (int)$lid], 'save_customer.cla');
                }
            }
            // Addresses
            $addresses = $r->get_param('addresses') ?? [];
            if (!empty($addresses) && is_array($addresses)) {
                foreach ($addresses as $addr) {
                    $text = trim($addr['address_text'] ?? '');
                    if (!$text) continue;
                    $this->safe_insert('wp_mf_3_dp_party_addresses', [
                        'party_id'     => $party_id,
                        'address_type' => in_array($addr['address_type'] ?? '', ['billing','shipping']) ? $addr['address_type'] : 'shipping',
                        'label'        => trim($addr['label'] ?? ''),
                        'address_text' => $text,
                        'is_default'   => (int)($addr['is_default'] ?? 0),
                    ], 'save_customer.addr');
                }
            }
            $this->audit('wp_mf_4_parties', $party_id, 'INSERT', null, ['name' => $name, 'product_ids' => $pids, 'location_ids' => $lids]);
            return $this->ok(['id' => $party_id], 201);
        } catch (\Exception $e) { return $this->exc('save_customer', $e); }
    }

    public function update_customer( WP_REST_Request $r ): WP_REST_Response {
        if ($e = $this->check_finance_access($this->uid())) return $e;
        try {
            $db     = $this->db();
            $pid    = (int) $r['id'];  // party_id
            $name   = trim($r->get_param('name') ?? '');
            $pids   = $r->get_param('product_ids');
            $lids   = $r->get_param('location_ids');
            $active = $r->get_param('is_active');
            if (!$pid) return $this->err('id is required.');
            $old = $db->get_row($db->prepare(
                "SELECT * FROM wp_mf_4_parties WHERE id=%d AND party_type='customer'", $pid), ARRAY_A);
            if (!$old) return $this->err('Customer not found.', 404);
            $updates = [];
            if ($name && $name !== $old['name']) {
                $dup = $db->get_var($db->prepare(
                    "SELECT COUNT(*) FROM wp_mf_4_parties WHERE name=%s AND party_type='customer' AND id!=%d", $name, $pid));
                if ($dup) return $this->err('Customer name already exists.');
                $updates['name'] = $name;
            }
            if ($active !== null) { $updates['is_active'] = (int)$active; }
            if (!empty($updates)) {
                $result = $db->update('wp_mf_4_parties', $updates, ['id' => $pid]);
                if ($result === false) { $this->log("update_customer: UPDATE failed for party_id=$pid: " . ($db->last_error ?: '(no error)')); }
                $this->check_db('update_customer');
            }
            if ($pids !== null && is_array($pids)) {
                $db->delete('wp_mf_3_dp_customer_products', ['party_id' => $pid]);
                foreach ($pids as $p) { $this->safe_insert('wp_mf_3_dp_customer_products', ['party_id' => $pid, 'product_id' => (int)$p], 'update_customer.cp'); }
            }
            if ($lids !== null && is_array($lids)) {
                $db->delete('wp_mf_3_dp_customer_location_access', ['party_id' => $pid]);
                foreach ($lids as $l) { $this->safe_insert('wp_mf_3_dp_customer_location_access', ['party_id' => $pid, 'location_id' => (int)$l], 'update_customer.cla'); }
            }
            // Addresses: replace-all strategy
            $addresses = $r->get_param('addresses');
            if ($addresses !== null && is_array($addresses)) {
                // Deactivate all existing
                $db->update('wp_mf_3_dp_party_addresses', ['is_active' => 0], ['party_id' => $pid]);
                $this->check_db('update_customer.deactivate_addrs');
                foreach ($addresses as $addr) {
                    $text = trim($addr['address_text'] ?? '');
                    if (!$text) continue;
                    $addr_id = (int)($addr['id'] ?? 0);
                    $addr_data = [
                        'address_type' => in_array($addr['address_type'] ?? '', ['billing','shipping']) ? $addr['address_type'] : 'shipping',
                        'label'        => trim($addr['label'] ?? ''),
                        'address_text' => $text,
                        'is_default'   => (int)($addr['is_default'] ?? 0),
                        'is_active'    => 1,
                    ];
                    if ($addr_id) {
                        $db->update('wp_mf_3_dp_party_addresses', $addr_data, ['id' => $addr_id, 'party_id' => $pid]);
                        $this->check_db('update_customer.addr_update');
                    } else {
                        $addr_data['party_id'] = $pid;
                        $this->safe_insert('wp_mf_3_dp_party_addresses', $addr_data, 'update_customer.addr_insert');
                    }
                }
            }
            $after = $db->get_row($db->prepare("SELECT * FROM wp_mf_4_parties WHERE id=%d", $pid), ARRAY_A);
            $this->audit('wp_mf_4_parties', $pid, 'UPDATE', $old, $after);
            return $this->ok(['id' => $pid]);
        } catch (\Exception $e) { return $this->exc('update_customer', $e); }
    }

    public function get_vendors( WP_REST_Request $r ): WP_REST_Response {
        try {
            $db     = $this->db();
            $loc_id = (int) ($r->get_param('location_id') ?? 0);
            $all    = (int) ($r->get_param('all') ?? 0);
            if ($loc_id && !$all) {
                $rows = $db->get_results($db->prepare(
                    "SELECT p.id, p.name, p.is_active FROM wp_mf_4_parties p
                     JOIN wp_mf_3_dp_vendor_location_access vla ON vla.party_id = p.id
                     WHERE p.is_active=1 AND p.party_type='vendor' AND vla.location_id = %d ORDER BY p.name", $loc_id), ARRAY_A);
            } else {
                $where = $all ? "party_type='vendor'" : "party_type='vendor' AND is_active=1";
                $rows = $db->get_results("SELECT id, name, is_active FROM wp_mf_4_parties WHERE $where ORDER BY name", ARRAY_A);
            }
            $this->check_db('get_vendors');
            // Attach location_ids
            $all_vl = $db->get_results("SELECT party_id, location_id FROM wp_mf_3_dp_vendor_location_access", ARRAY_A);
            $vl_map = [];
            foreach ($all_vl as $vl) { $vl_map[(int)$vl['party_id']][] = (int)$vl['location_id']; }
            // Attach product_ids
            $all_vp = $db->get_results("SELECT party_id, product_id FROM wp_mf_3_dp_vendor_products", ARRAY_A);
            $vp_map = [];
            foreach ($all_vp as $vp) { $vp_map[(int)$vp['party_id']][] = (int)$vp['product_id']; }
            foreach ($rows as &$row) {
                $row['location_ids'] = $vl_map[(int)$row['id']] ?? [];
                $row['product_ids']  = $vp_map[(int)$row['id']] ?? [];
            }
            return $this->ok($rows ?? []);
        } catch (\Exception $e) { return $this->exc('get_vendors', $e); }
    }

    public function save_vendor( WP_REST_Request $r ): WP_REST_Response {
        if ($e = $this->check_finance_access($this->uid())) return $e;
        try {
            $db   = $this->db();
            $name = trim($r->get_param('name') ?? '');
            $lids = $r->get_param('location_ids') ?? [];
            if (!$name) return $this->err('Name is required.');
            $dup = $db->get_var($db->prepare(
                "SELECT COUNT(*) FROM wp_mf_4_parties WHERE name=%s AND party_type='vendor'", $name));
            if ($dup) return $this->err('Vendor name already exists.');
            $pids = $r->get_param('product_ids') ?? [];
            if (!$this->safe_insert('wp_mf_4_parties', [
                'name' => $name, 'party_type' => 'vendor', 'is_active' => 1,
            ], 'save_vendor')) {
                return $this->err('Database error.', 500);
            }
            $vid = $db->insert_id;
            if (!empty($lids) && is_array($lids)) {
                foreach ($lids as $lid) {
                    $this->safe_insert('wp_mf_3_dp_vendor_location_access', ['party_id' => $vid, 'location_id' => (int)$lid], 'save_vendor.vla');
                }
            }
            if (!empty($pids) && is_array($pids)) {
                foreach ($pids as $pid) {
                    $this->safe_insert('wp_mf_3_dp_vendor_products', ['party_id' => $vid, 'product_id' => (int)$pid], 'save_vendor.vp');
                }
            }
            $this->audit('wp_mf_4_parties', $vid, 'INSERT', null, ['name' => $name, 'party_type' => 'vendor', 'location_ids' => $lids, 'product_ids' => $pids]);
            return $this->ok(['id' => $vid], 201);
        } catch (\Exception $e) { return $this->exc('save_vendor', $e); }
    }

    public function update_vendor( WP_REST_Request $r ): WP_REST_Response {
        if ($e = $this->check_finance_access($this->uid())) return $e;
        try {
            $db     = $this->db();
            $vid    = (int) $r['id'];
            $name   = trim($r->get_param('name') ?? '');
            $lids   = $r->get_param('location_ids');
            $active = $r->get_param('is_active');
            if (!$vid) return $this->err('id is required.');
            $old = $db->get_row($db->prepare(
                "SELECT * FROM wp_mf_4_parties WHERE id=%d AND party_type='vendor'", $vid), ARRAY_A);
            if (!$old) return $this->err('Vendor not found.', 404);
            $updates = [];
            if ($name && $name !== $old['name']) {
                $dup = $db->get_var($db->prepare(
                    "SELECT COUNT(*) FROM wp_mf_4_parties WHERE name=%s AND party_type='vendor' AND id!=%d", $name, $vid));
                if ($dup) return $this->err('Vendor name already exists.');
                $updates['name'] = $name;
            }
            if ($active !== null) { $updates['is_active'] = (int)$active; }
            if (!empty($updates)) { $db->update('wp_mf_4_parties', $updates, ['id' => $vid]); $this->check_db('update_vendor'); }
            if ($lids !== null && is_array($lids)) {
                $db->delete('wp_mf_3_dp_vendor_location_access', ['party_id' => $vid]);
                foreach ($lids as $lid) {
                    $this->safe_insert('wp_mf_3_dp_vendor_location_access', ['party_id' => $vid, 'location_id' => (int)$lid], 'update_vendor.vla');
                }
            }
            $pids = $r->get_param('product_ids');
            if ($pids !== null && is_array($pids)) {
                $db->delete('wp_mf_3_dp_vendor_products', ['party_id' => $vid]);
                foreach ($pids as $pid) {
                    $this->safe_insert('wp_mf_3_dp_vendor_products', ['party_id' => $vid, 'product_id' => (int)$pid], 'update_vendor.vp');
                }
            }
            $after = $db->get_row($db->prepare(
                "SELECT * FROM wp_mf_4_parties WHERE id=%d", $vid), ARRAY_A);
            $this->audit('wp_mf_4_parties', $vid, 'UPDATE', $old, $after);
            return $this->ok(['id' => $vid]);
        } catch (\Exception $e) { return $this->exc('update_vendor', $e); }
    }

    public function get_admin_products(): WP_REST_Response {
        if ($e = $this->check_finance_access($this->uid())) return $e;
        try {
            $db = $this->db();
            $rows = $db->get_results(
                "SELECT p.id, p.name, p.unit, p.sort_order, p.is_active,
                        COALESCE(er.rate, 0) AS rate
                   FROM wp_mf_3_dp_products p
                   LEFT JOIN wp_mf_3_dp_estimated_rates er ON er.product_id = p.id
                  ORDER BY p.sort_order", ARRAY_A);
            $this->check_db('get_admin_products');
            return $this->ok($rows ?? []);
        } catch (\Exception $e) { return $this->exc('get_admin_products', $e); }
    }

    public function update_product( WP_REST_Request $r ): WP_REST_Response {
        if ($e = $this->check_finance_access($this->uid())) return $e;
        try {
            $db   = $this->db();
            $pid  = (int) $r['id'];
            $name = trim($r->get_param('name') ?? '');
            $unit = trim($r->get_param('unit') ?? '');
            $rate = $r->get_param('rate');
            $active = $r->get_param('is_active');
            if (!$pid) return $this->err('id is required.');
            $old = $db->get_row($db->prepare("SELECT * FROM wp_mf_3_dp_products WHERE id=%d", $pid), ARRAY_A);
            if (!$old) return $this->err('Product not found.', 404);
            $updates = [];
            if ($name && $name !== $old['name']) { $updates['name'] = $name; }
            if ($unit && $unit !== $old['unit']) { $updates['unit'] = $unit; }
            if ($active !== null) { $updates['is_active'] = (int)$active; }
            if (!empty($updates)) { $db->update('wp_mf_3_dp_products', $updates, ['id' => $pid]); $this->check_db('update_product'); }
            if ($rate !== null) {
                $db->query($db->prepare(
                    "INSERT INTO wp_mf_3_dp_estimated_rates (product_id, rate, updated_by)
                     VALUES (%d, %f, %d)
                     ON DUPLICATE KEY UPDATE rate=VALUES(rate), updated_by=VALUES(updated_by)",
                    $pid, (float)$rate, $this->uid()));
                $this->check_db('update_product.rate');
            }
            $after = $db->get_row($db->prepare("SELECT * FROM wp_mf_3_dp_products WHERE id=%d", $pid), ARRAY_A);
            $this->audit('wp_mf_3_dp_products', $pid, 'UPDATE', $old, $after);
            return $this->ok(['id' => $pid]);
        } catch (\Exception $e) { return $this->exc('update_product', $e); }
    }

    // ════════════════════════════════════════════════════
    // V3 Sales (get_sales, save_sale, delete_sale) removed — Flutter uses /v4/transaction

    // ════════════════════════════════════════════════════
    // SALES REPORT  — daily aggregated sales by product
    // ════════════════════════════════════════════════════

    public function get_sales_report( WP_REST_Request $r ): WP_REST_Response {
        $loc = (int) ($r->get_param('location_id') ?? 0);
        if ($loc) {
            if ($e = $this->check_location_access($this->uid(), $loc)) return $e;
        }
        try {
            $db   = $this->db();
            $from = $r['from'] ?? date('Y-m-d', strtotime('-29 days'));
            $to   = $r['to']   ?? date('Y-m-d');

            // Column order: Skim Milk, Curd, Ghee, Butter, Cream, FF Milk
            $col_order = [2, 10, 5, 4, 3, 1];

            // Fetch product names for the ordered columns
            $all_products = $db->get_results(
                "SELECT id, name FROM wp_mf_3_dp_products WHERE is_active=1", ARRAY_A
            );
            $this->check_db('sales_report.products');
            $prod_map = array_column($all_products, 'name', 'id');

            // V4: sale transactions, qty is negative — use ABS
            $loc_cond = $loc ? $db->prepare(' AND t.location_id = %d', $loc) : '';
            if ($loc) {
                $rows = $db->get_results($db->prepare(
                    "SELECT t.transaction_date AS entry_date, tl.product_id,
                            SUM(ABS(tl.qty))             AS qty_kg,
                            SUM(ABS(tl.qty) * tl.rate)   AS total_value,
                            NULL AS location_name
                       FROM wp_mf_4_transactions t
                       JOIN wp_mf_4_transaction_lines tl ON tl.transaction_id = t.id
                      WHERE t.transaction_type = 'sale'
                        AND t.transaction_date BETWEEN %s AND %s $loc_cond
                      GROUP BY t.transaction_date, tl.product_id
                      ORDER BY t.transaction_date DESC, tl.product_id",
                    $from, $to
                ), ARRAY_A);
            } else {
                $rows = $db->get_results($db->prepare(
                    "SELECT t.transaction_date AS entry_date, tl.product_id,
                            l.name AS location_name, t.location_id,
                            SUM(ABS(tl.qty))             AS qty_kg,
                            SUM(ABS(tl.qty) * tl.rate)   AS total_value
                       FROM wp_mf_4_transactions t
                       JOIN wp_mf_4_transaction_lines tl ON tl.transaction_id = t.id
                       JOIN wp_mf_3_dp_locations l ON l.id = t.location_id
                      WHERE t.transaction_type = 'sale'
                        AND t.transaction_date BETWEEN %s AND %s
                        AND l.code != 'TEST'
                      GROUP BY t.transaction_date, t.location_id, tl.product_id
                      ORDER BY t.transaction_date DESC, l.name, tl.product_id",
                    $from, $to
                ), ARRAY_A);
            }
            $this->check_db('sales_report.rows');

            // Pivot: build one row per (date, location) with a cell per product
            $grouped = [];
            foreach ($rows as $row) {
                $d   = $row['entry_date'];
                $loc_name = $row['location_name'] ?? null;
                $key = $loc ? $d : $d . '|' . ($row['location_id'] ?? '');
                $pid = (int) $row['product_id'];
                if (!isset($grouped[$key])) {
                    $grouped[$key] = ['date' => $d, 'location_name' => $loc_name, 'cells' => []];
                }
                $grouped[$key]['cells'][$pid] = [
                    'qty_kg'      => (int)   $row['qty_kg'],
                    'total_value' => (float) $row['total_value'],
                ];
            }

            // Build ordered rows
            $report = [];
            foreach ($grouped as $g) {
                $row_total = 0;
                $products  = [];
                foreach ($col_order as $pid) {
                    $cell = $g['cells'][$pid] ?? null;
                    $row_total += $cell['total_value'] ?? 0;
                    $products[$pid] = $cell;
                }
                $entry = [
                    'date'      => $g['date'],
                    'products'  => $products,
                    'row_total' => round($row_total, 2),
                ];
                if ($g['location_name'] !== null) $entry['location_name'] = $g['location_name'];
                $report[] = $entry;
            }

            return $this->ok([
                'location_id' => $loc,
                'from'        => $from,
                'to'          => $to,
                'col_order'   => $col_order,
                'prod_names'  => $prod_map,
                'rows'        => $report,
            ]);
        } catch (\Exception $e) { return $this->exc('get_sales_report', $e); }
    }

    // ════════════════════════════════════════════════════
    // VENDOR PURCHASE REPORT — last 30 days, all purchase types
    // ════════════════════════════════════════════════════

    public function get_vendor_purchase_report( WP_REST_Request $r ): WP_REST_Response {
        try {
            $db   = $this->db();
            $loc  = (int) ($r->get_param('location_id') ?? 0);
            $from = $r->get_param('from') ?? date('Y-m-d', strtotime('-29 days'));
            $to   = $r->get_param('to')   ?? date('Y-m-d');

            if ($loc) {
                if ($e = $this->check_location_access($this->uid(), $loc)) return $e;
            }

            $loc_cond  = $loc ? $db->prepare(' AND t.location_id = %d', $loc) : '';
            $test_cond = $loc ? '' : " AND l.code != 'TEST'";
            $loc_sel   = $loc ? 'NULL AS location_name' : 'l.name AS location_name';
            $loc_join  = $loc ? '' : ' JOIN wp_mf_3_dp_locations l ON l.id = t.location_id';

            // V4: All purchases from wp_mf_4_transactions + lines
            $rows = $db->get_results($db->prepare(
                "SELECT t.transaction_date AS entry_date, $loc_sel,
                        COALESCE(p.name, 'Unknown Vendor') AS vendor,
                        pr.name AS product,
                        tl.qty AS quantity_kg,
                        tl.fat,
                        tl.rate,
                        ROUND(tl.qty * tl.rate, 2) AS amount
                   FROM wp_mf_4_transactions t
                   JOIN wp_mf_4_transaction_lines tl ON tl.transaction_id = t.id
                   JOIN wp_mf_3_dp_products pr ON pr.id = tl.product_id
                   LEFT JOIN wp_mf_4_parties p ON p.id = t.party_id
                   $loc_join
                  WHERE t.transaction_type = 'purchase'
                    AND tl.qty > 0
                    AND t.transaction_date BETWEEN %s AND %s $loc_cond $test_cond
                  ORDER BY t.transaction_date DESC, p.name",
                $from, $to
            ), ARRAY_A);
            $this->check_db('vendor_report_v4');

            // Sort by date desc, then location, then vendor
            usort($rows, function($a, $b) {
                $d = strcmp($b['entry_date'], $a['entry_date']);
                if ($d !== 0) return $d;
                $l = strcmp($a['location_name'] ?? '', $b['location_name'] ?? '');
                if ($l !== 0) return $l;
                return strcmp($a['vendor'], $b['vendor']);
            });

            $total_qty    = array_sum(array_column($rows, 'quantity_kg'));
            $total_amount = array_sum(array_column($rows, 'amount'));

            return $this->ok([
                'location_id'  => $loc,
                'from'         => $from,
                'to'           => $to,
                'rows'         => $rows ?? [],
                'total_qty'    => (int)   $total_qty,
                'total_amount' => (float) $total_amount,
            ]);
        } catch (\Exception $e) { return $this->exc('get_vendor_purchase_report', $e); }
    }


    // ════════════════════════════════════════════════════
    // FLOW 5 - SMP / Protein / Culture Purchase
    // ════════════════════════════════════════════════════
    // V3 SMP Purchase (save_smp_purchase) removed — Flutter uses /v4/transaction

    // ════════════════════════════════════════════════════
    // STOCK
    // ════════════════════════════════════════════════════

    public function get_stock( WP_REST_Request $r ): WP_REST_Response {
        if ($e = $this->validate_loc($r)) return $e;
        if ($e = $this->check_location_access($this->uid(), (int)$r['location_id'])) return $e;
        try {
            $db   = $this->db();
            $loc  = (int) $r['location_id'];
            $from = $r['from'] ?? date('Y-m-d', strtotime('-29 days'));
            $to   = $r['to']   ?? date('Y-m-d');
            $products = $db->get_results(
                "SELECT id, name, unit FROM wp_mf_3_dp_products WHERE is_active=1 ORDER BY sort_order", ARRAY_A);
            $this->check_db('get_stock.products');

            // V4: All stock movements in transaction_lines with signed qty
            $prod_rows = $db->get_results($db->prepare(
                $this->stock_movements_sql(), $loc, $from, $to
            ), ARRAY_A);
            $this->check_db('get_stock.movements_v4');

            // Build daily movements
            $daily = [];
            foreach ($prod_rows as $row) {
                $daily[$row['entry_date']][$row['product_id']] =
                    ($daily[$row['entry_date']][$row['product_id']] ?? 0) + (float)$row['qty'];
            }

            // Walk every day, carry running cumulative balance forward
            $dates   = [];
            $running = [];
            foreach ($products as $p) $running[$p['id']] = 0;

            for ($ts = strtotime($from); $ts <= strtotime($to); $ts += 86400) {
                $d = date('Y-m-d', $ts);
                foreach ($products as $p) {
                    $running[$p['id']] += $daily[$d][$p['id']] ?? 0;
                }
                $stocks = [];
                foreach ($products as $p) $stocks[$p['id']] = (int) round($running[$p['id']]);
                $dates[] = ['date' => $d, 'stocks' => $stocks];
            }
            return $this->ok(['products'=>$products,'dates'=>$dates,'from'=>$from,'to'=>$to]);
        } catch (\Exception $e) { return $this->exc('get_stock', $e); }
    }

    // ════════════════════════════════════════════════════
    // ESTIMATED RATES  (finance only)
    // ════════════════════════════════════════════════════

    public function get_estimated_rates(): WP_REST_Response {
        if ($e = $this->check_finance_access($this->uid())) return $e;
        try {
            $rows = $this->db()->get_results(
                "SELECT er.product_id, p.name AS product_name, er.rate, er.updated_at
                   FROM wp_mf_3_dp_estimated_rates er
                   JOIN wp_mf_3_dp_products p ON p.id=er.product_id ORDER BY p.sort_order", ARRAY_A);
            $this->check_db('get_estimated_rates');
            return $this->ok($rows);
        } catch (\Exception $e) { return $this->exc('get_estimated_rates', $e); }
    }

    public function update_estimated_rates( WP_REST_Request $r ): WP_REST_Response {
        if ($e = $this->check_finance_access($this->uid())) return $e;
        try {
            $db    = $this->db();
            $rates = $r->get_param('rates') ?? [];
            if (empty($rates) || !is_array($rates)) return $this->err('rates array is required.');
            $updated = 0;
            foreach ($rates as $idx => $item) {
                $pid  = (int)   ($item['product_id'] ?? 0);
                $rate = (float) ($item['rate']       ?? -1);
                if (!$pid) { $this->log("update_estimated_rates: row $idx missing product_id"); continue; }
                if ($rate < 0) return $this->err("Row $idx: rate must be >= 0.");
                $before = $db->get_row($db->prepare("SELECT * FROM wp_mf_3_dp_estimated_rates WHERE product_id=%d", $pid), ARRAY_A);
                $result = $db->query($db->prepare(
                    "INSERT INTO wp_mf_3_dp_estimated_rates (product_id,rate,updated_by) VALUES (%d,%f,%d) ON DUPLICATE KEY UPDATE rate=VALUES(rate),updated_by=VALUES(updated_by)",
                    $pid,$rate,$this->uid()
                ));
                if ($result === false) {
                    $this->log_db("update_estimated_rates pid=$pid", $db->last_error);
                    return $this->err("Database error updating rate for product $pid.", 500);
                }
                $after = $db->get_row($db->prepare("SELECT * FROM wp_mf_3_dp_estimated_rates WHERE product_id=%d", $pid), ARRAY_A);
                if ($after) $this->audit('wp_mf_3_dp_estimated_rates',(int)$after['id'],$before?'UPDATE':'INSERT',$before,$after);
                $updated++;
            }
            return $this->ok(['updated' => $updated]);
        } catch (\Exception $e) { return $this->exc('update_estimated_rates', $e); }
    }



    // ════════════════════════════════════════════════════
    // STOCK VALUATION  (finance + location)
    // ════════════════════════════════════════════════════

    public function get_stock_valuation( WP_REST_Request $r ): WP_REST_Response {
        if ($e = $this->validate_loc($r)) return $e;
        if ($e = $this->check_finance_access($this->uid())) return $e;
        if ($e = $this->check_location_access($this->uid(), (int)$r['location_id'])) return $e;
        try {
            $stock_res = $this->get_stock($r);
            if ($stock_res->get_status() !== 200) return $stock_res;
            $stock_data = $stock_res->data['data'];
            $rate_rows  = $this->db()->get_results("SELECT product_id,rate FROM wp_mf_3_dp_estimated_rates", ARRAY_A);
            $this->check_db('get_stock_valuation.rates');
            $rates = [];
            foreach ($rate_rows as $rw) $rates[$rw['product_id']] = (float)$rw['rate'];
            foreach ($stock_data['dates'] as &$day) {
                $total = 0;
                foreach ($stock_data['products'] as $p) {
                    $value = round((int)($day['stocks'][$p['id']] ?? 0) * ($rates[$p['id']] ?? 0), 2);
                    $day['values'][$p['id']] = $value;
                    $total += $value;
                }
                $day['total_value'] = round($total, 2);
            }
            unset($day);
            $stock_data['estimated_rates'] = $rates;
            return $this->ok($stock_data);
        } catch (\Exception $e) { return $this->exc('get_stock_valuation', $e); }
    }

    // ════════════════════════════════════════════════════
    // AUDIT LOG  (finance only)
    // ════════════════════════════════════════════════════

    public function get_audit_log( WP_REST_Request $r ): WP_REST_Response {
        if ($e = $this->check_finance_access($this->uid())) return $e;
        try {
            $db   = $this->db();
            $days = max(1, min(90, (int)($r->get_param('days') ?? 30)));
            $from = date('Y-m-d H:i:s', strtotime("-{$days} days"));
            $loc_id = $r->get_param('location_id') ? (int)$r->get_param('location_id') : null;
            if ($loc_id) {
                $rows = $db->get_results($db->prepare(
                    "SELECT id,table_name,record_id,action,old_data,new_data,user_id,user_name,ip_address,location_id,created_at
                       FROM wp_mf_3_dp_audit_log WHERE created_at>=%s AND location_id=%d ORDER BY created_at DESC LIMIT 500",
                    $from, $loc_id
                ), ARRAY_A);
            } else {
                $rows = $db->get_results($db->prepare(
                    "SELECT id,table_name,record_id,action,old_data,new_data,user_id,user_name,ip_address,location_id,created_at
                       FROM wp_mf_3_dp_audit_log WHERE created_at>=%s ORDER BY created_at DESC LIMIT 500",
                    $from
                ), ARRAY_A);
            }
            $this->check_db('get_audit_log');
            foreach ($rows as &$row) {
                $row['table_label'] = self::TABLE_LABELS[$row['table_name']] ?? $row['table_name'];
                $row['old_data']    = $row['old_data'] ? json_decode($row['old_data'],true) : null;
                $row['new_data']    = $row['new_data'] ? json_decode($row['new_data'],true) : null;
            }
            unset($row);
            return $this->ok(['rows' => $rows, 'from' => $from]);
        } catch (\Exception $e) { return $this->exc('get_audit_log', $e); }
    }

    // ════════════════════════════════════════════════════
    // ANOMALIES — Flow 1 output/input ratio check
    // ════════════════════════════════════════════════════

    public function get_anomalies( WP_REST_Request $r ): WP_REST_Response {
        if ($e = $this->validate_loc($r)) return $e;
        if ($e = $this->check_location_access($this->uid(), (int)$r['location_id'])) return $e;
        if ($e = $this->check_anomaly_access($this->uid())) return $e;
        try {
            $db  = $this->db();
            $loc = (int) $r['location_id'];

            // V4: ff_milk_processing transactions
            $txns = $db->get_results($db->prepare(
                "SELECT t.id, t.transaction_date AS entry_date,
                        t.created_by, t.created_at, t.party_id,
                        COALESCE(p.name, '') AS vendor_name
                   FROM wp_mf_4_transactions t
                   LEFT JOIN wp_mf_4_parties p ON p.id = t.party_id
                  WHERE t.location_id = %d
                    AND t.transaction_type = 'processing'
                    AND t.processing_type = 'ff_milk_processing'
                  ORDER BY t.transaction_date DESC, t.created_at DESC",
                $loc
            ), ARRAY_A);
            $this->check_db('get_anomalies_v4');

            if (empty($txns)) return $this->ok(['rows' => []]);

            // Get lines for all these transactions
            $txn_ids = array_column($txns, 'id');
            $id_list = implode(',', array_map('intval', $txn_ids));
            $all_lines = $db->get_results(
                "SELECT transaction_id, product_id, qty FROM wp_mf_4_transaction_lines WHERE transaction_id IN ($id_list)",
                ARRAY_A
            );
            $this->check_db('get_anomalies_v4.lines');

            $lines_map = [];
            foreach ($all_lines as $ln) {
                $lines_map[(int)$ln['transaction_id']][] = $ln;
            }

            $user_ids = array_unique(array_filter(array_column($txns, 'created_by')));
            $names    = $this->resolve_first_names($user_ids);

            $rows = [];
            foreach ($txns as $t) {
                $tid = (int)$t['id'];
                $txn_lines = $lines_map[$tid] ?? [];
                $input = 0; $skim = 0; $cream = 0;
                foreach ($txn_lines as $ln) {
                    $pid = (int)$ln['product_id'];
                    $qty = (float)$ln['qty'];
                    if ($pid === 1 && $qty < 0) $input += abs($qty);
                    if ($pid === 2 && $qty > 0) $skim += $qty;
                    if ($pid === 3 && $qty > 0) $cream += $qty;
                }
                if ($input <= 0) continue;
                $ratio = round(($skim + $cream) / $input * 100, 2);
                $rows[] = [
                    'id'                    => $tid,
                    'entry_date'            => $t['entry_date'],
                    'input_ff_milk_used_kg' => (int)$input,
                    'output_skim_milk_kg'   => (int)$skim,
                    'output_cream_kg'       => $this->d2($cream),
                    'ratio'                 => $ratio,
                    'is_anomalous'          => $ratio < 105,
                    'vendor_name'           => $t['vendor_name'],
                    'user_name'             => $names[$t['created_by']] ?? 'Unknown',
                    'created_at'            => $t['created_at'],
                ];
            }

            return $this->ok(['rows' => $rows]);
        } catch (\Exception $e) { return $this->exc('get_anomalies', $e); }
    }

    // ════════════════════════════════════════════════════
    // VENDOR PAYMENTS & LEDGER  (finance only)
    // ════════════════════════════════════════════════════

    public function save_vendor_payment( WP_REST_Request $r ): WP_REST_Response {
        if ($e = $this->check_finance_access($this->uid())) return $e;
        try {
            $db       = $this->db();
            $party_id = (int) $r->get_param('party_id');
            $date     = sanitize_text_field($r->get_param('payment_date') ?? '');
            $amount   = (float) $r->get_param('amount');
            $method   = sanitize_text_field($r->get_param('method') ?? 'Cash');
            $note     = sanitize_text_field($r->get_param('note') ?? '');

            if (!$party_id) return $this->err('party_id is required.');
            if (!preg_match('/^\d{4}-\d{2}-\d{2}$/', $date)) return $this->err('payment_date must be YYYY-MM-DD.');
            if ($amount <= 0) return $this->err('amount must be greater than zero.');
            $allowed_methods = ['Cash', 'Bank Transfer', 'UPI', 'Cheque'];
            if (!in_array($method, $allowed_methods, true)) return $this->err('method must be one of: ' . implode(', ', $allowed_methods));

            // V4: Verify party exists as vendor
            $v = $db->get_var($db->prepare(
                "SELECT id FROM wp_mf_4_parties WHERE id=%d AND party_type='vendor'", $party_id));
            $this->check_db('save_vendor_payment.party_check');
            if (!$v) return $this->err('Vendor not found.', 404);

            $data = [
                'party_id'     => $party_id,
                'payment_date' => $date,
                'amount'       => $this->d2($amount),
                'method'       => $method,
                'note'         => $note ?: null,
                'created_by'   => $this->uid(),
            ];
            if ($db->insert('wp_mf_4_vendor_payments', $data) === false) {
                $this->log_db('save_vendor_payment', $db->last_error);
                return $this->err('Database error.', 500);
            }
            $this->audit('wp_mf_4_vendor_payments', $db->insert_id, 'INSERT', null, $data);
            return $this->ok(['id' => $db->insert_id], 201);
        } catch (\Exception $e) { return $this->exc('save_vendor_payment', $e); }
    }

    public function get_vendor_ledger( WP_REST_Request $r ): WP_REST_Response {
        if ($e = $this->check_finance_access($this->uid())) return $e;
        try {
            $db        = $this->db();
            $from      = sanitize_text_field($r->get_param('from') ?? date('Y-m-d', strtotime('-90 days')));
            $to        = sanitize_text_field($r->get_param('to')   ?? date('Y-m-d'));
            $loc_id    = (int) ($r->get_param('location_id') ?? 0);
            $vendor_id = (int) ($r->get_param('vendor_id') ?? 0);

            $loc_cond   = $loc_id    ? $db->prepare(' AND t.location_id = %d', $loc_id)    : '';
            // V4: vendor_id is now party_id
            $vend_cond  = $vendor_id ? $db->prepare(' AND t.party_id = %d', $vendor_id)    : '';
            $test_cond  = $loc_id    ? '' : " AND l.code != 'TEST'";

            // V4: Purchases grouped by date + location + vendor party
            $purch = $db->get_results($db->prepare("
                SELECT t.transaction_date AS date, l.name AS location_name,
                       p.name AS vendor_name,
                       ROUND(SUM(tl.qty * tl.rate), 2) AS purchases
                  FROM wp_mf_4_transactions t
                  JOIN wp_mf_4_transaction_lines tl ON tl.transaction_id = t.id
                  JOIN wp_mf_3_dp_locations l ON l.id = t.location_id
                  JOIN wp_mf_4_parties p ON p.id = t.party_id
                 WHERE t.transaction_type = 'purchase'
                   AND tl.qty > 0 AND tl.rate > 0
                   AND t.transaction_date BETWEEN %s AND %s $loc_cond $vend_cond $test_cond
                 GROUP BY t.transaction_date, l.name, p.name
            ", $from, $to), ARRAY_A);
            $this->check_db('vendor_ledger_v4.purchases');

            // V4: Payments grouped by date + vendor party
            $vend_pay_cond = $vendor_id ? $db->prepare(' AND pay.party_id = %d', $vendor_id) : '';
            $pays = $db->get_results($db->prepare("
                SELECT pay.payment_date AS date, p.name AS vendor_name,
                       ROUND(SUM(pay.amount), 2) AS payments
                  FROM wp_mf_4_vendor_payments pay
                  JOIN wp_mf_4_parties p ON p.id = pay.party_id
                 WHERE pay.payment_date BETWEEN %s AND %s $vend_pay_cond
                 GROUP BY pay.payment_date, p.name
            ", $from, $to), ARRAY_A);
            $this->check_db('vendor_ledger_v4.payments');

            // Merge into map keyed by date|vendor
            $map = [];
            foreach ($purch ?: [] as $r2) {
                $key = $r2['date'] . '|' . $r2['vendor_name'];
                if (!isset($map[$key])) {
                    $map[$key] = [
                        'date' => $r2['date'],
                        'locations' => [],
                        'vendor_name' => $r2['vendor_name'],
                        'purchases' => 0.0,
                        'payments' => 0.0,
                    ];
                }
                $map[$key]['purchases'] += (float)$r2['purchases'];
                $ln = $r2['location_name'];
                if ($ln && !in_array($ln, $map[$key]['locations'])) {
                    $map[$key]['locations'][] = $ln;
                }
            }
            foreach ($pays ?: [] as $r2) {
                $key = $r2['date'] . '|' . $r2['vendor_name'];
                if (!isset($map[$key])) {
                    $map[$key] = [
                        'date' => $r2['date'],
                        'locations' => [],
                        'vendor_name' => $r2['vendor_name'],
                        'purchases' => 0.0,
                        'payments' => 0.0,
                    ];
                }
                $map[$key]['payments'] += (float)$r2['payments'];
            }

            // Sort chronologically for running balance
            $rows = array_values($map);
            usort($rows, function($a, $b) {
                $d = strcmp($a['date'], $b['date']);
                if ($d !== 0) return $d;
                return strcmp($a['vendor_name'], $b['vendor_name']);
            });

            // Running balance per vendor
            $bal = [];
            foreach ($rows as &$row) {
                $v = $row['vendor_name'];
                if (!isset($bal[$v])) $bal[$v] = 0.0;
                $bal[$v] += $row['purchases'] - $row['payments'];
                $row['balance']       = round($bal[$v], 2);
                $row['purchases']     = round($row['purchases'], 2);
                $row['payments']      = round($row['payments'], 2);
                $row['location_name'] = implode(', ', $row['locations']);
                unset($row['locations']);
            }
            unset($row);

            // Reverse for date DESC display
            $rows = array_reverse($rows);

            // V4: Vendor list from parties
            $vendors = $db->get_results(
                "SELECT id, name FROM wp_mf_4_parties WHERE party_type='vendor' AND is_active=1 ORDER BY name", ARRAY_A);
            $this->check_db('vendor_ledger_v4.vendor_list');

            return $this->ok([
                'rows'    => $rows,
                'vendors' => $vendors ?? [],
                'from'    => $from,
                'to'      => $to,
            ]);
        } catch (\Exception $e) { return $this->exc('get_vendor_ledger', $e); }
    }

    public function get_vendor_ledger_detail( WP_REST_Request $r ): WP_REST_Response {
        if ($e = $this->check_finance_access($this->uid())) return $e;
        try {
            $db        = $this->db();
            $vendor_id = (int) ($r->get_param('vendor_id') ?? 0);

            $from   = sanitize_text_field($r->get_param('from') ?? date('Y-m-d', strtotime('-90 days')));
            $to     = sanitize_text_field($r->get_param('to')   ?? date('Y-m-d'));
            $loc_id = (int) ($r->get_param('location_id') ?? 0);

            // V4: vendor_id is now party_id
            $vendor_name = 'All Vendors';
            if ($vendor_id) {
                $vendor = $db->get_row($db->prepare(
                    "SELECT id, name FROM wp_mf_4_parties WHERE id=%d AND party_type='vendor'", $vendor_id), ARRAY_A);
                $this->check_db('vendor_ledger_detail_v4.vendor_check');
                if (!$vendor) return $this->err('Vendor not found.', 404);
                $vendor_name = $vendor['name'];
            }

            // V4: Purchase transactions from wp_mf_4_transactions
            $vend_cond = $vendor_id ? $db->prepare(" AND t.party_id = %d", $vendor_id) : '';
            $loc_cond  = $loc_id   ? $db->prepare(" AND t.location_id = %d", $loc_id) : '';

            $purchases = $db->get_results($db->prepare("
                SELECT 'purchase' AS type, t.transaction_date AS date, p.name AS vendor_name,
                       pr.name AS product,
                       tl.qty AS quantity, tl.rate,
                       ROUND(tl.qty * tl.rate, 2) AS amount,
                       l.name AS location_name
                  FROM wp_mf_4_transactions t
                  JOIN wp_mf_4_transaction_lines tl ON tl.transaction_id = t.id
                  JOIN wp_mf_3_dp_products pr ON pr.id = tl.product_id
                  JOIN wp_mf_3_dp_locations l ON l.id = t.location_id
                  LEFT JOIN wp_mf_4_parties p ON p.id = t.party_id
                 WHERE t.transaction_type = 'purchase'
                   AND tl.qty > 0
                   AND t.transaction_date BETWEEN %s AND %s $vend_cond $loc_cond
                 ORDER BY t.transaction_date DESC
            ", $from, $to), ARRAY_A);
            $this->check_db('vendor_ledger_detail_v4.purchases');

            // V4: Payment transactions from wp_mf_4_vendor_payments
            $vend_pay_cond = $vendor_id ? $db->prepare(' AND pay.party_id = %d', $vendor_id) : '';
            $payment_rows = $db->get_results($db->prepare("
                SELECT 'payment' AS type, pay.payment_date AS date, pay.amount, pay.method, pay.note,
                       pay.created_by, p.name AS vendor_name
                  FROM wp_mf_4_vendor_payments pay
                  JOIN wp_mf_4_parties p ON p.id = pay.party_id
                 WHERE pay.payment_date BETWEEN %s AND %s $vend_pay_cond
                 ORDER BY pay.payment_date DESC
            ", $from, $to), ARRAY_A);
            $this->check_db('vendor_ledger_detail_v4.payments');

            // Resolve user names for payments
            $user_ids = array_unique(array_filter(array_column($payment_rows, 'created_by')));
            $names    = $this->resolve_first_names($user_ids);
            foreach ($payment_rows as &$pr) {
                $pr['user_name'] = $names[$pr['created_by']] ?? 'Unknown';
                unset($pr['created_by']);
                $pr['amount'] = (float) $pr['amount'];
            }
            unset($pr);

            // Merge and sort by date DESC
            $all = array_merge($purchases, $payment_rows);
            usort($all, fn($a, $b) => strcmp($b['date'], $a['date']));

            // Calculate totals
            $total_purchases = 0.0;
            $total_payments  = 0.0;
            foreach ($purchases as $p) $total_purchases += (float) $p['amount'];
            foreach ($payment_rows as $p) $total_payments += $p['amount'];

            // V4: Vendors list from parties
            $vendor_list = $db->get_results("
                SELECT id, name FROM wp_mf_4_parties
                WHERE party_type='vendor' AND is_active = 1 ORDER BY name", ARRAY_A);
            $this->check_db('vendor_ledger_detail_v4.vendor_list');

            return $this->ok([
                'vendor_name'     => $vendor_name,
                'total_purchases' => round($total_purchases, 2),
                'total_payments'  => round($total_payments, 2),
                'balance_due'     => round($total_purchases - $total_payments, 2),
                'transactions'    => $all,
                'vendors'         => $vendor_list ?? [],
                'from'            => $from,
                'to'              => $to,
            ]);
        } catch (\Exception $e) { return $this->exc('get_vendor_ledger_detail', $e); }
    }

    // ════════════════════════════════════════════════════
    // ADMIN UI — Manage Staff Permissions
    // ════════════════════════════════════════════════════

    public function register_admin_menu(): void {
        add_menu_page(
            'Dairy Staff Permissions',
            'Dairy Permissions',
            'manage_options',
            'dairy-permissions',
            [ $this, 'render_admin_page' ],
            'dashicons-groups',
            30
        );
        add_submenu_page(
            'dairy-permissions',
            'Vendor Locations',
            'Vendor Locations',
            'manage_options',
            'dairy-vendor-locations',
            [ $this, 'render_vendor_locations_page' ]
        );
    }

    public function render_admin_page(): void {
        if ( ! current_user_can('manage_options') ) {
            wp_die('Insufficient permissions.');
        }

        $db        = $this->db();
        $locations = $db->get_results(
            "SELECT id, name FROM wp_mf_3_dp_locations WHERE is_active=1 ORDER BY name", ARRAY_A) ?? [];

        // Get all WordPress users except admins
        $wp_users = get_users(['role__not_in' => ['administrator'], 'orderby' => 'display_name']);

        // Load current permissions
        $access_rows = $db->get_results(
            "SELECT user_id, location_id FROM wp_mf_3_dp_user_location_access", ARRAY_A) ?? [];
        $access = [];
        foreach ($access_rows as $row) {
            $access[$row['user_id']][] = (int) $row['location_id'];
        }

        $flag_rows = $db->get_results(
            "SELECT user_id, can_finance, can_anomaly FROM wp_mf_3_dp_user_flags", ARRAY_A) ?? [];
        $flags = [];
        foreach ($flag_rows as $row) {
            $flags[$row['user_id']] = [
                'finance' => (bool) $row['can_finance'],
                'anomaly' => (bool) ($row['can_anomaly'] ?? false),
            ];
        }

        $saved = isset($_GET['saved']) && $_GET['saved'] === '1';
        ?>
        <div class="wrap">
            <h1>Dairy Staff Permissions</h1>
            <p style="color:#666;">
                Assign locations to staff. Finance access grants stock valuation and audit log visibility across all assigned locations.
            </p>

            <?php if ($saved): ?>
            <div class="notice notice-success is-dismissible">
                <p>Permissions saved successfully.</p>
            </div>
            <?php endif; ?>

            <?php if (empty($wp_users)): ?>
            <div class="notice notice-warning">
                <p>No non-administrator users found. Create staff accounts via <a href="<?= esc_url(admin_url('user-new.php')) ?>">Users &rarr; Add New</a>.</p>
            </div>
            <?php else: ?>

            <form method="post" action="<?= esc_url(admin_url('admin-post.php')) ?>">
                <input type="hidden" name="action" value="dairy_save_permissions">
                <?php wp_nonce_field('dairy_save_permissions'); ?>

                <table class="widefat striped" style="margin-top:16px;">
                    <thead>
                        <tr>
                            <th style="width:200px;">Staff Member</th>
                            <?php foreach ($locations as $loc): ?>
                            <th style="text-align:center;"><?= esc_html($loc['name']) ?></th>
                            <?php endforeach; ?>
                            <th style="text-align:center;">Finance</th>
                            <th style="text-align:center;">Anomaly</th>
                        </tr>
                    </thead>
                    <tbody>
                        <?php foreach ($wp_users as $u): ?>
                        <tr>
                            <td>
                                <strong><?= esc_html($u->display_name) ?></strong><br>
                                <small style="color:#888;"><?= esc_html($u->user_login) ?></small>
                            </td>
                            <?php foreach ($locations as $loc): ?>
                            <td style="text-align:center;">
                                <input type="checkbox"
                                    name="loc[<?= (int)$u->ID ?>][]"
                                    value="<?= (int)$loc['id'] ?>"
                                    <?= in_array((int)$loc['id'], $access[$u->ID] ?? []) ? 'checked' : '' ?>>
                            </td>
                            <?php endforeach; ?>
                            <td style="text-align:center;">
                                <input type="checkbox"
                                    name="finance[<?= (int)$u->ID ?>]"
                                    value="1"
                                    <?= !empty($flags[$u->ID]['finance']) ? 'checked' : '' ?>>
                            </td>
                            <td style="text-align:center;">
                                <input type="checkbox"
                                    name="anomaly[<?= (int)$u->ID ?>]"
                                    value="1"
                                    <?= !empty($flags[$u->ID]['anomaly']) ? 'checked' : '' ?>>
                            </td>
                        </tr>
                        <?php endforeach; ?>
                    </tbody>
                </table>

                <p class="submit">
                    <input type="submit" class="button button-primary" value="Save Permissions">
                </p>
            </form>
            <?php endif; ?>
        </div>
        <?php
    }

    public function handle_save_permissions(): void {
        if ( ! current_user_can('manage_options') ) wp_die('Insufficient permissions.');
        check_admin_referer('dairy_save_permissions');

        $db         = $this->db();
        $loc_input  = $_POST['loc']     ?? [];   // [user_id => [loc_id, ...]]
        $fin_input  = $_POST['finance'] ?? [];   // [user_id => '1']
        $ano_input  = $_POST['anomaly'] ?? [];   // [user_id => '1']

        // Get all non-admin user IDs to process (even those not in POST = all unchecked)
        $wp_users = get_users(['role__not_in' => ['administrator'], 'fields' => 'ID']);

        foreach ($wp_users as $uid) {
            $uid = (int) $uid;

            // ── Location access ──────────────────────────
            // Delete all existing rows for this user, then re-insert checked ones
            $db->delete('wp_mf_3_dp_user_location_access', ['user_id' => $uid]);

            $locs = array_map('intval', $loc_input[$uid] ?? []);
            foreach ($locs as $lid) {
                $db->insert('wp_mf_3_dp_user_location_access', [
                    'user_id'     => $uid,
                    'location_id' => $lid,
                ]);
            }

            // ── Finance + Anomaly flags ──────────────────
            $can_finance = isset($fin_input[$uid]) ? 1 : 0;
            $can_anomaly = isset($ano_input[$uid]) ? 1 : 0;
            $db->query($db->prepare(
                "INSERT INTO wp_mf_3_dp_user_flags (user_id, can_finance, can_anomaly)
                 VALUES (%d, %d, %d)
                 ON DUPLICATE KEY UPDATE can_finance = VALUES(can_finance), can_anomaly = VALUES(can_anomaly)",
                $uid, $can_finance, $can_anomaly
            ));
        }

        $this->log("Permissions saved by admin user ID " . get_current_user_id());

        wp_redirect(admin_url('admin.php?page=dairy-permissions&saved=1'));
        exit;
    }

    // ════════════════════════════════════════════════════
    // ADMIN UI — Vendor Location Assignments
    // ════════════════════════════════════════════════════

    public function render_vendor_locations_page(): void {
        if ( ! current_user_can('manage_options') ) {
            wp_die('Insufficient permissions.');
        }

        $db        = $this->db();
        $locations = $db->get_results(
            "SELECT id, name FROM wp_mf_3_dp_locations WHERE is_active=1 ORDER BY name", ARRAY_A) ?? [];
        $vendors   = $db->get_results(
            "SELECT id, name FROM wp_mf_4_parties WHERE party_type='vendor' AND is_active=1 ORDER BY name", ARRAY_A) ?? [];

        // Load current assignments
        $access_rows = $db->get_results(
            "SELECT party_id, location_id FROM wp_mf_3_dp_vendor_location_access", ARRAY_A) ?? [];
        $access = [];
        foreach ($access_rows as $row) {
            $access[(int)$row['party_id']][] = (int) $row['location_id'];
        }

        $saved = isset($_GET['saved']) && $_GET['saved'] === '1';
        $error = isset($_GET['error']) ? sanitize_text_field($_GET['error']) : '';
        ?>
        <div class="wrap">
            <h1>Dairy Vendor Locations</h1>
            <p style="color:#666;">
                Assign vendors to locations. Each vendor must have at least one location.
            </p>

            <?php if ($saved): ?>
            <div class="notice notice-success is-dismissible">
                <p>Vendor locations saved successfully.</p>
            </div>
            <?php endif; ?>

            <?php if ($error): ?>
            <div class="notice notice-error is-dismissible">
                <p><?= esc_html($error) ?></p>
            </div>
            <?php endif; ?>

            <?php if (empty($vendors)): ?>
            <div class="notice notice-warning">
                <p>No active vendors found.</p>
            </div>
            <?php else: ?>

            <form method="post" action="<?= esc_url(admin_url('admin-post.php')) ?>">
                <input type="hidden" name="action" value="dairy_save_vendor_locations">
                <?php wp_nonce_field('dairy_save_vendor_locations'); ?>

                <table class="widefat striped" style="margin-top:16px;">
                    <thead>
                        <tr>
                            <th style="width:200px;">Vendor</th>
                            <?php foreach ($locations as $loc): ?>
                            <th style="text-align:center;"><?= esc_html($loc['name']) ?></th>
                            <?php endforeach; ?>
                        </tr>
                    </thead>
                    <tbody>
                        <?php foreach ($vendors as $v): ?>
                        <tr>
                            <td><strong><?= esc_html($v['name']) ?></strong></td>
                            <?php foreach ($locations as $loc): ?>
                            <td style="text-align:center;">
                                <input type="checkbox"
                                    name="vloc[<?= (int)$v['id'] ?>][]"
                                    value="<?= (int)$loc['id'] ?>"
                                    <?= in_array((int)$loc['id'], $access[(int)$v['id']] ?? []) ? 'checked' : '' ?>>
                            </td>
                            <?php endforeach; ?>
                        </tr>
                        <?php endforeach; ?>
                    </tbody>
                </table>

                <p class="submit">
                    <input type="submit" class="button button-primary" value="Save Vendor Locations">
                </p>
            </form>
            <?php endif; ?>
        </div>
        <?php
    }

    public function handle_save_vendor_locations(): void {
        if ( ! current_user_can('manage_options') ) wp_die('Insufficient permissions.');
        check_admin_referer('dairy_save_vendor_locations');

        $db        = $this->db();
        $vloc_input = $_POST['vloc'] ?? [];  // [vendor_id => [loc_id, ...]]

        // Get all active vendors to process
        $vendors = $db->get_results(
            "SELECT id, name FROM wp_mf_4_parties WHERE party_type='vendor' AND is_active=1", ARRAY_A) ?? [];

        // Validate: every vendor must have at least one location checked
        foreach ($vendors as $v) {
            $vid  = (int) $v['id'];
            $locs = array_map('intval', $vloc_input[$vid] ?? []);
            if (empty($locs)) {
                $name = $v['name'];
                wp_redirect(admin_url(
                    'admin.php?page=dairy-vendor-locations&error='
                    . urlencode("Vendor \"$name\" must have at least one location assigned.")
                ));
                exit;
            }
        }

        // Delete-and-reinsert per vendor
        foreach ($vendors as $v) {
            $vid = (int) $v['id'];
            $db->delete('wp_mf_3_dp_vendor_location_access', ['party_id' => $vid]);
            $locs = array_map('intval', $vloc_input[$vid] ?? []);
            foreach ($locs as $lid) {
                $db->insert('wp_mf_3_dp_vendor_location_access', [
                    'party_id'    => $vid,
                    'location_id' => $lid,
                ]);
            }
        }

        $this->log("Vendor locations saved by admin user ID " . get_current_user_id());

        wp_redirect(admin_url('admin.php?page=dairy-vendor-locations&saved=1'));
        exit;
    }

    // V3 Madhusudan save/get removed — Flutter uses /v4/transaction

    public function get_madhusudan_pnl( WP_REST_Request $r ): WP_REST_Response {
        if ($e = $this->validate_loc($r)) return $e;
        if ($e = $this->check_location_access($this->uid(), (int)$r['location_id'])) return $e;
        try {
            $db  = $this->db();
            $loc = (int) $r['location_id'];

            // V4: madhusudan_sale processing transactions
            $txns = $db->get_results($db->prepare(
                "SELECT id, transaction_date AS entry_date, notes
                   FROM wp_mf_4_transactions
                  WHERE location_id = %d
                    AND transaction_type = 'processing'
                    AND processing_type = 'madhusudan_sale'
                  ORDER BY transaction_date DESC, id DESC", $loc
            ), ARRAY_A);
            $this->check_db('get_madhusudan_pnl.txns');

            // Batch-fetch all lines for these transactions
            $all_lines = [];
            if (!empty($txns)) {
                $txn_ids = array_column($txns, 'id');
                $ph = implode(',', array_fill(0, count($txn_ids), '%d'));
                $lines_q = $db->get_results($db->prepare(
                    "SELECT transaction_id, product_id, qty, source_transaction_id
                       FROM wp_mf_4_transaction_lines
                      WHERE transaction_id IN ($ph)",
                    ...$txn_ids), ARRAY_A) ?: [];
                foreach ($lines_q as $ln) {
                    $all_lines[$ln['transaction_id']][] = $ln;
                }
            }

            // V4: per-party weighted average purchase rate for FF milk at this location
            $avg_rates = $db->get_results($db->prepare(
                "SELECT t.party_id,
                        CASE WHEN SUM(tl.qty) > 0
                             THEN SUM(tl.qty * tl.rate) / SUM(tl.qty)
                             ELSE 0 END AS avg_rate
                   FROM wp_mf_4_transactions t
                   JOIN wp_mf_4_transaction_lines tl ON tl.transaction_id = t.id
                  WHERE t.location_id = %d
                    AND t.transaction_type = 'purchase'
                    AND tl.product_id = 1
                    AND tl.qty > 0
                  GROUP BY t.party_id", $loc), ARRAY_A) ?: [];
            $this->check_db('get_madhusudan_pnl.avg_rates');
            $party_avg = [];
            foreach ($avg_rates as $ar) $party_avg[(int)$ar['party_id']] = (float)$ar['avg_rate'];

            $rows = [];
            $grand_total_kg      = 0;
            $grand_total_revenue = 0.0;
            $grand_total_cost    = 0.0;

            foreach (($txns ?? []) as $t) {
                $txn_id = (int) $t['id'];
                $notes  = $t['notes'] ? json_decode($t['notes'], true) : [];
                $rate   = (float)($notes['sale_rate'] ?? 0);
                $lines  = $all_lines[$txn_id] ?? [];

                // Total milk qty from lines (product_id=1, negative in processing)
                $total_kg = 0;
                foreach ($lines as $ln) {
                    if ((int)$ln['product_id'] === 1) $total_kg += abs((float)$ln['qty']);
                }
                $revenue = $total_kg * $rate;

                // Cost: use source_transaction_id to find purchase party, then avg rate
                $cost = 0.0;
                foreach ($lines as $ln) {
                    if ((int)$ln['product_id'] !== 1) continue;
                    $src_id = $ln['source_transaction_id'] ?? null;
                    if ($src_id) {
                        // Find party_id of the source purchase transaction
                        $src_party = (int) $db->get_var($db->prepare(
                            "SELECT party_id FROM wp_mf_4_transactions WHERE id = %d", $src_id));
                        $cost += abs((float)$ln['qty']) * ($party_avg[$src_party] ?? 0);
                    }
                }

                $profit = $revenue - $cost;

                $rows[] = [
                    'id'               => $txn_id,
                    'entry_date'       => $t['entry_date'],
                    'total_ff_milk_kg' => (int)$total_kg,
                    'sale_rate'        => $this->d2($rate),
                    'revenue'          => $this->d2($revenue),
                    'cost'             => $this->d2($cost),
                    'profit'           => $this->d2($profit),
                ];

                $grand_total_kg      += (int)$total_kg;
                $grand_total_revenue += $revenue;
                $grand_total_cost    += $cost;
            }

            return $this->ok([
                'rows'   => $rows,
                'totals' => [
                    'total_ff_milk_kg' => $grand_total_kg,
                    'revenue'          => $this->d2($grand_total_revenue),
                    'cost'             => $this->d2($grand_total_cost),
                    'profit'           => $this->d2($grand_total_revenue - $grand_total_cost),
                ],
            ]);
        } catch (\Exception $e) { return $this->exc('get_madhusudan_pnl', $e); }
    }

    // V3 Curd Production save/get removed — Flutter uses /v4/transaction

    public function get_production_flows(): WP_REST_Response {
        try {
            $rows = $this->db()->get_results(
                "SELECT `key`, label, sort_order FROM wp_mf_3_dp_production_flows WHERE is_active=1 ORDER BY sort_order",
                ARRAY_A);
            $this->check_db('get_production_flows');
            return $this->ok($rows ?? []);
        } catch (\Exception $e) { return $this->exc('get_production_flows', $e); }
    }

    // ════════════════════════════════════════════════════
    // CASH FLOW REPORT
    // ════════════════════════════════════════════════════

    public function get_cashflow_report( WP_REST_Request $r ): WP_REST_Response {
        if ($e = $this->check_finance_access($this->uid())) return $e;
        try {
            $db   = $this->db();
            $from = $r->get_param('from') ?: date('Y-m-d', strtotime('-29 days'));
            $to   = $r->get_param('to')   ?: date('Y-m-d');
            $loc  = (int) ($r->get_param('location_id') ?? 0);
            $loc_cond   = $loc ? $db->prepare(' AND location_id = %d', $loc) : '';

            // When "All" (no loc), group by date+location; when specific loc, group by date only
            $grp_col  = $loc ? '' : ', location_id';
            $grp_join = $loc ? '' : ' JOIN wp_mf_3_dp_locations l ON l.id = t.location_id';
            $grp_sel  = $loc ? 'NULL AS location_id, NULL AS location_name' : 't.location_id, l.name AS location_name';
            $test_cond = $loc ? '' : " AND l.code != 'TEST'";

            // V4: Sales revenue per day
            $loc_cond_v4 = $loc ? $db->prepare(' AND t.location_id = %d', $loc) : '';
            $loc_join_v4 = $loc ? '' : ' JOIN wp_mf_3_dp_locations l ON l.id = t.location_id';
            $sel_loc_v4  = $loc ? 'NULL AS location_id, NULL AS location_name' : 't.location_id, l.name AS location_name';

            $sales = $db->get_results($db->prepare(
                "SELECT t.transaction_date AS d, $sel_loc_v4,
                        ROUND(SUM(ABS(tl.qty) * tl.rate), 2) AS amt
                   FROM wp_mf_4_transactions t
                   JOIN wp_mf_4_transaction_lines tl ON tl.transaction_id = t.id
                   $loc_join_v4
                  WHERE t.transaction_type = 'sale'
                    AND t.transaction_date BETWEEN %s AND %s $loc_cond_v4 $test_cond
                  GROUP BY t.transaction_date $grp_col",
                $from, $to
            ), ARRAY_A) ?: [];
            $this->check_db('cashflow_v4.sales');

            // V4: Madhusudan revenue (processing with sale_rate in notes)
            $mad_txns = $db->get_results($db->prepare(
                "SELECT t.id, t.transaction_date AS d, t.location_id, t.notes
                   FROM wp_mf_4_transactions t
                  WHERE t.transaction_type = 'processing'
                    AND t.processing_type = 'madhusudan_sale'
                    AND t.transaction_date BETWEEN %s AND %s $loc_cond_v4",
                $from, $to
            ), ARRAY_A) ?: [];
            // Compute madhusudan revenue in PHP
            $mad = [];
            if (!empty($mad_txns)) {
                $mad_ids = implode(',', array_map('intval', array_column($mad_txns, 'id')));
                $mad_lines = $db->get_results(
                    "SELECT transaction_id, SUM(ABS(qty)) AS milk_kg
                       FROM wp_mf_4_transaction_lines
                      WHERE transaction_id IN ($mad_ids) AND product_id = 1
                      GROUP BY transaction_id",
                    ARRAY_A
                );
                $mad_milk = [];
                foreach ($mad_lines as $ml) $mad_milk[(int)$ml['transaction_id']] = (float)$ml['milk_kg'];

                foreach ($mad_txns as $mt) {
                    $notes = $mt['notes'] ? json_decode($mt['notes'], true) : [];
                    $sale_rate = (float)($notes['sale_rate'] ?? 0);
                    $milk_qty = $mad_milk[(int)$mt['id']] ?? 0;
                    $amt = round($milk_qty * $sale_rate, 2);
                    if ($amt > 0) {
                        $lid = $mt['location_id'];
                        $mad[] = [
                            'd' => $mt['d'],
                            'location_id' => $loc ? null : $lid,
                            'location_name' => null,
                            'amt' => $amt,
                        ];
                    }
                }
                // Resolve location names for madhusudan if needed
                if (!$loc && !empty($mad)) {
                    $loc_ids = array_unique(array_filter(array_column($mad_txns, 'location_id')));
                    if (!empty($loc_ids)) {
                        $loc_list = implode(',', array_map('intval', $loc_ids));
                        $ln_rows = $db->get_results("SELECT id, name FROM wp_mf_3_dp_locations WHERE id IN ($loc_list)", ARRAY_A);
                        $ln_map = array_column($ln_rows, 'name', 'id');
                        foreach ($mad as &$mr) {
                            $mr['location_name'] = $ln_map[$mr['location_id']] ?? '';
                        }
                        unset($mr);
                    }
                }
            }
            $this->check_db('cashflow_v4.madhusudan');

            // V4: All purchases per day
            $purchases_cf = $db->get_results($db->prepare(
                "SELECT t.transaction_date AS d, $sel_loc_v4,
                        ROUND(SUM(tl.qty * tl.rate), 2) AS amt
                   FROM wp_mf_4_transactions t
                   JOIN wp_mf_4_transaction_lines tl ON tl.transaction_id = t.id
                   $loc_join_v4
                  WHERE t.transaction_type = 'purchase'
                    AND tl.qty > 0
                    AND t.transaction_date BETWEEN %s AND %s $loc_cond_v4 $test_cond
                  GROUP BY t.transaction_date $grp_col",
                $from, $to
            ), ARRAY_A) ?: [];
            $this->check_db('cashflow_v4.purchases');

            // ── Vendor payments per day (V4, global, not per-location) ──
            $pay_q = "SELECT payment_date AS d, ROUND(SUM(amount), 2) AS amt
                        FROM wp_mf_4_vendor_payments
                       WHERE payment_date BETWEEN %s AND %s
                       GROUP BY payment_date";
            $pay = $db->get_results($db->prepare($pay_q, $from, $to), ARRAY_A);
            $this->check_db('cashflow.payments');

            // ── Merge into (date, location) map ──
            // key = "date" when single loc, "date|loc_id" when all
            $map = [];
            $loc_names = [];

            $add = function($arr, $field) use (&$map, &$loc_names, $loc) {
                foreach ($arr as $r2) {
                    $lid = $r2['location_id'] ?? null;
                    $key = $loc ? $r2['d'] : $r2['d'] . '|' . $lid;
                    if (!isset($map[$key])) {
                        $map[$key] = ['date' => $r2['d'], 'location_id' => $lid, 'sales' => 0, 'purchases' => 0, 'payments' => 0];
                    }
                    $map[$key][$field] += (float)$r2['amt'];
                    if ($lid && isset($r2['location_name'])) $loc_names[$lid] = $r2['location_name'];
                }
            };

            $add($sales, 'sales');
            $add($mad, 'sales');
            $add($purchases_cf, 'purchases');

            // Payments are global — when "All", distribute to a special "—" location row
            // or just add as a single key per date with no location
            foreach ($pay as $r2) {
                if ($loc) {
                    $key = $r2['d'];
                    if (!isset($map[$key])) $map[$key] = ['date' => $r2['d'], 'location_id' => null, 'sales' => 0, 'purchases' => 0, 'payments' => 0];
                    $map[$key]['payments'] += (float)$r2['amt'];
                } else {
                    // For "All", add payments to a "Payments" pseudo-location per date
                    $key = $r2['d'] . '|PAY';
                    if (!isset($map[$key])) $map[$key] = ['date' => $r2['d'], 'location_id' => 'PAY', 'sales' => 0, 'purchases' => 0, 'payments' => 0];
                    $map[$key]['payments'] += (float)$r2['amt'];
                }
            }

            // Sort by date DESC, then location name
            uksort($map, function($a, $b) { return strcmp($b, $a); });

            // ── Build rows with beginning/end cash ──
            $rows = [];
            $cash = 0;
            // Process in chronological order for running cash
            $sorted_keys = array_keys($map);
            sort($sorted_keys); // chronological
            foreach ($sorted_keys as $key) {
                $v = $map[$key];
                $beg = round($cash, 2);
                $end_cash = round($beg + $v['sales'] - $v['payments'], 2);
                $row = [
                    'date'           => $v['date'],
                    'beginning_cash' => $beg,
                    'sales'          => round($v['sales'], 2),
                    'purchases'      => round($v['purchases'], 2),
                    'payments'       => round($v['payments'], 2),
                    'end_cash'       => $end_cash,
                ];
                if (!$loc) {
                    $lid = $v['location_id'];
                    $row['location_name'] = ($lid === 'PAY') ? 'Payments' : ($loc_names[$lid] ?? '');
                }
                $rows[] = $row;
                $cash = $end_cash;
            }
            // Reverse for date DESC display
            $rows = array_reverse($rows);

            return $this->ok([
                'from' => $from,
                'to'   => $to,
                'rows' => $rows,
            ]);
        } catch (\Exception $e) { return $this->exc('get_cashflow_report', $e); }
    }

    // ════════════════════════════════════════════════════
    // CASH + STOCK REPORT
    // ════════════════════════════════════════════════════

    public function get_cash_stock_report( WP_REST_Request $r ): WP_REST_Response {
        if ($e = $this->check_finance_access($this->uid())) return $e;
        try {
            $db   = $this->db();
            $from = $r->get_param('from') ?: date('Y-m-d', strtotime('-29 days'));
            $to   = $r->get_param('to')   ?: date('Y-m-d');
            $loc  = (int) ($r->get_param('location_id') ?? 0);

            // ── 1. Cash flow (grouped by date only) ──────────────
            $loc_cond  = $loc ? $db->prepare(' AND t.location_id = %d', $loc) : '';
            $test_cond = $loc ? '' : " AND l.code != 'TEST'";

            $loc_join  = $loc ? '' : ' JOIN wp_mf_3_dp_locations l ON l.id = t.location_id';

            // V4: Sales revenue
            $sales = $db->get_results($db->prepare(
                "SELECT t.transaction_date AS d, ROUND(SUM(ABS(tl.qty) * tl.rate), 2) AS amt
                   FROM wp_mf_4_transactions t
                   JOIN wp_mf_4_transaction_lines tl ON tl.transaction_id = t.id
                   $loc_join
                  WHERE t.transaction_type = 'sale'
                    AND t.transaction_date BETWEEN %s AND %s $loc_cond $test_cond
                  GROUP BY t.transaction_date",
                $from, $to), ARRAY_A) ?: [];
            $this->check_db('cash_stock.sales');

            // V4: Madhusudan revenue (processing with sale_rate in notes)
            $mad_txns = $db->get_results($db->prepare(
                "SELECT t.id, t.transaction_date AS d, t.notes
                   FROM wp_mf_4_transactions t
                   $loc_join
                  WHERE t.transaction_type = 'processing'
                    AND t.processing_type = 'madhusudan_sale'
                    AND t.transaction_date BETWEEN %s AND %s $loc_cond $test_cond",
                $from, $to), ARRAY_A) ?: [];
            $this->check_db('cash_stock.madhusudan');
            $mad = [];
            if (!empty($mad_txns)) {
                $mad_ids = array_column($mad_txns, 'id');
                $ph = implode(',', array_fill(0, count($mad_ids), '%d'));
                $mad_lines = $db->get_results($db->prepare(
                    "SELECT transaction_id, ABS(qty) AS qty FROM wp_mf_4_transaction_lines
                      WHERE transaction_id IN ($ph) AND product_id = 1",
                    ...$mad_ids), ARRAY_A) ?: [];
                $milk_by_txn = [];
                foreach ($mad_lines as $ml) $milk_by_txn[$ml['transaction_id']] = (float)$ml['qty'];
                $mad_by_date = [];
                foreach ($mad_txns as $mt) {
                    $notes = $mt['notes'] ? json_decode($mt['notes'], true) : [];
                    $sr = (float)($notes['sale_rate'] ?? 0);
                    $kg = $milk_by_txn[$mt['id']] ?? 0;
                    $mad_by_date[$mt['d']] = ($mad_by_date[$mt['d']] ?? 0) + ($kg * $sr);
                }
                foreach ($mad_by_date as $d => $amt) $mad[] = ['d' => $d, 'amt' => round($amt, 2)];
            }

            // V4: Purchases total
            $purchases = $db->get_results($db->prepare(
                "SELECT t.transaction_date AS d, ROUND(SUM(tl.qty * tl.rate), 2) AS amt
                   FROM wp_mf_4_transactions t
                   JOIN wp_mf_4_transaction_lines tl ON tl.transaction_id = t.id
                   $loc_join
                  WHERE t.transaction_type = 'purchase'
                    AND tl.qty > 0
                    AND t.transaction_date BETWEEN %s AND %s $loc_cond $test_cond
                  GROUP BY t.transaction_date",
                $from, $to), ARRAY_A) ?: [];
            $this->check_db('cash_stock.purchases');

            // V4: Payments
            $pay_q = "SELECT payment_date AS d, ROUND(SUM(amount), 2) AS amt
                        FROM wp_mf_4_vendor_payments
                       WHERE payment_date BETWEEN %s AND %s
                       GROUP BY payment_date";
            $pay = $db->get_results($db->prepare($pay_q, $from, $to), ARRAY_A);
            $this->check_db('cash_stock.payments');

            // Merge cash flow into date map
            $cash_map = []; // date => [sales, purchases, payments]
            $add_cash = function($arr, $field) use (&$cash_map) {
                foreach ($arr as $r2) {
                    $d = $r2['d'];
                    if (!isset($cash_map[$d])) $cash_map[$d] = ['sales' => 0, 'purchases' => 0, 'payments' => 0];
                    $cash_map[$d][$field] += (float)$r2['amt'];
                }
            };
            $add_cash($sales, 'sales');
            $add_cash($mad, 'sales');
            $add_cash($purchases, 'purchases');
            $add_cash($pay ?: [], 'payments');

            // ── 2. Stock movements (V4 — signed qty, no separate sales subtraction) ─────────
            $stk_loc_cond = $loc
                ? $db->prepare('t.location_id = %d', $loc)
                : "t.location_id IN (SELECT id FROM wp_mf_3_dp_locations WHERE code != 'TEST')";
            $stk_rows = $db->get_results($db->prepare(
                "SELECT t.transaction_date AS entry_date, tl.product_id, SUM(tl.qty) AS qty
                   FROM wp_mf_4_transaction_lines tl
                   JOIN wp_mf_4_transactions t ON t.id = tl.transaction_id
                  WHERE $stk_loc_cond
                    AND t.transaction_date BETWEEN %s AND %s
                  GROUP BY t.transaction_date, tl.product_id",
                $from, $to), ARRAY_A);
            $this->check_db('cash_stock.stock_movements');

            // Build daily stock movements map
            $daily_stk = []; // date => [product_id => net_movement]
            foreach ($stk_rows ?: [] as $sr) {
                $daily_stk[$sr['entry_date']][$sr['product_id']] =
                    ($daily_stk[$sr['entry_date']][$sr['product_id']] ?? 0) + (float)$sr['qty'];
            }

            // Estimated rates
            $rate_rows = $db->get_results("SELECT product_id, rate FROM wp_mf_3_dp_estimated_rates", ARRAY_A);
            $this->check_db('cash_stock.rates');
            $rates = [];
            foreach ($rate_rows ?: [] as $rr) $rates[(int)$rr['product_id']] = (float)$rr['rate'];

            // Product groups for columns
            // skim_milk=2, curd=10, cream=3, ghee=5, butter=4, ff_milk=1, smp_cul_pro=7+8+9
            $prod_cols = [
                'skim_milk' => [2],
                'curd'      => [10],
                'cream'     => [3],
                'ghee'      => [5],
                'butter'    => [4],
                'ff_milk'   => [1],
                'smp_cul_pro' => [7, 8, 9],
            ];

            // ── 3. Walk day by day, compute cumulative stock + cash ──
            $running_stock = []; // product_id => cumulative qty
            $cash = 0;
            $rows = [];

            for ($ts = strtotime($from); $ts <= strtotime($to); $ts += 86400) {
                $d = date('Y-m-d', $ts);

                // Update running stock
                foreach ($daily_stk[$d] ?? [] as $pid => $mv) {
                    $running_stock[$pid] = ($running_stock[$pid] ?? 0) + $mv;
                }

                // Cash flow for this date
                $cf = $cash_map[$d] ?? ['sales' => 0, 'purchases' => 0, 'payments' => 0];
                $beg_cash = round($cash, 2);
                $end_cash = round($beg_cash + $cf['sales'] - $cf['payments'], 2);

                // Stock values per column
                $stock_vals = [];
                $total_stock = 0;
                foreach ($prod_cols as $col => $pids) {
                    $val = 0;
                    foreach ($pids as $pid) {
                        $qty = $running_stock[$pid] ?? 0;
                        $val += $qty * ($rates[$pid] ?? 0);
                    }
                    $val = round($val, 2);
                    $stock_vals[$col] = $val;
                    $total_stock += $val;
                }
                $total_stock = round($total_stock, 2);

                $row = [
                    'date'           => $d,
                    'beginning_cash' => $beg_cash,
                    'sales'          => round($cf['sales'], 2),
                    'purchases'      => round($cf['purchases'], 2),
                    'payments'       => round($cf['payments'], 2),
                    'end_cash'       => $end_cash,
                ];
                foreach ($stock_vals as $col => $val) $row[$col] = $val;
                $row['total_stock'] = $total_stock;
                $row['cash_plus_stock'] = round($end_cash + $total_stock, 2);

                $rows[] = $row;
                $cash = $end_cash;
            }

            // Reverse for date DESC display
            $rows = array_reverse($rows);

            return $this->ok([
                'from' => $from,
                'to'   => $to,
                'rows' => $rows,
            ]);
        } catch (\Exception $e) { return $this->exc('get_cash_stock_report', $e); }
    }

    // ════════════════════════════════════════════════════
    // SALES LEDGER (flat transaction list with customer filter)
    // ════════════════════════════════════════════════════

    public function get_sales_ledger( WP_REST_Request $r ): WP_REST_Response {
        $loc = (int) ($r->get_param('location_id') ?? 0);
        if ($loc) {
            if ($e = $this->check_location_access($this->uid(), $loc)) return $e;
        }
        try {
            $db   = $this->db();
            $from = $r->get_param('from') ?: date('Y-m-d', strtotime('-29 days'));
            $to   = $r->get_param('to')   ?: date('Y-m-d');
            $cid  = (int) ($r->get_param('customer_id') ?? 0);

            $loc_cond  = $loc ? $db->prepare(' AND t.location_id = %d', $loc) : '';
            // V4: customer_id = party_id
            $cust_cond = $cid ? $db->prepare(' AND t.party_id = %d', $cid) : '';

            $rows = $db->get_results($db->prepare(
                "SELECT t.id, t.transaction_date AS entry_date,
                        p.name AS customer_name,
                        pr.name AS product_name, pr.unit,
                        ABS(tl.qty) AS quantity_kg, tl.rate,
                        ROUND(ABS(tl.qty) * tl.rate, 2) AS total,
                        l.name AS location_name
                   FROM wp_mf_4_transactions t
                   JOIN wp_mf_4_transaction_lines tl ON tl.transaction_id = t.id
                   JOIN wp_mf_3_dp_products pr ON pr.id = tl.product_id
                   LEFT JOIN wp_mf_4_parties p ON p.id = t.party_id
                   JOIN wp_mf_3_dp_locations l ON l.id = t.location_id
                  WHERE t.transaction_type = 'sale'
                    AND t.transaction_date BETWEEN %s AND %s
                    $loc_cond
                    $cust_cond
                  ORDER BY t.transaction_date DESC, p.name, pr.name",
                $from, $to
            ), ARRAY_A);
            $this->check_db('get_sales_ledger_v4');

            // Customers list from V4 parties
            $customers = $db->get_results($db->prepare(
                "SELECT DISTINCT p.id, p.name
                   FROM wp_mf_4_transactions t
                   JOIN wp_mf_4_parties p ON p.id = t.party_id
                  WHERE t.transaction_type = 'sale'
                    AND t.transaction_date BETWEEN %s AND %s $loc_cond
                  ORDER BY p.name",
                $from, $to
            ), ARRAY_A);
            $this->check_db('get_sales_ledger_v4.customers');

            return $this->ok([
                'from'      => $from,
                'to'        => $to,
                'rows'      => $rows ?? [],
                'customers' => $customers ?? [],
            ]);
        } catch (\Exception $e) { return $this->exc('get_sales_ledger', $e); }
    }

    // ════════════════════════════════════════════════════
    // AUDIT WRITER
    // ════════════════════════════════════════════════════

    private function audit( string $table, int $record_id, string $action, ?array $old, ?array $new, ?int $location_id = null ): void {
        try {
            $user   = wp_get_current_user();
            $row = [
                'table_name'  => $table,
                'record_id'   => $record_id,
                'action'      => $action,
                'old_data'    => $old ? wp_json_encode($old) : null,
                'new_data'    => $new ? wp_json_encode($new) : null,
                'user_id'     => $user->ID,
                'user_name'   => $user->user_login ?: 'system',
                'ip_address'  => $_SERVER['REMOTE_ADDR'] ?? null,
                'location_id' => $location_id,
            ];
            $result = $this->db()->insert('wp_mf_3_dp_audit_log', $row);
            if ($result === false) $this->log_db("audit INSERT $table/$record_id", $this->db()->last_error);
        } catch (\Exception $e) {
            $this->log("audit() exception for $table/$record_id: " . $e->getMessage());
        }
    }

    // ════════════════════════════════════════════════════
    // LOGGING HELPERS
    // ════════════════════════════════════════════════════

    private function log( string $message ): void { error_log(self::LOG_PREFIX . ' ' . $message); }
    private function log_db( string $ctx, string $err ): void { $this->log("DB error in $ctx - $err"); }
    private function check_db( string $ctx ): void { $e = $this->db()->last_error; if (!empty($e)) $this->log_db($ctx,$e); }

    /** Insert with return-value check + last_error check + verification log. */
    private function safe_insert(string $table, array $data, string $ctx): bool {
        $db = $this->db();
        $result = $db->insert($table, $data);
        if ($result === false) {
            $this->log("SAFE_INSERT FAILED in $ctx — table=$table, error=" . ($db->last_error ?: '(no wpdb error)') . ", data=" . json_encode($data));
            return false;
        }
        $this->check_db($ctx);
        $this->log("SAFE_INSERT OK in $ctx — table=$table, insert_id={$db->insert_id}");
        return true;
    }
    private function exc( string $ctx, \Exception $e ): WP_REST_Response {
        $this->log("Exception in $ctx - {$e->getMessage()} at {$e->getFile()}:{$e->getLine()}");
        return $this->err('An unexpected server error occurred. Check error logs.', 500);
    }

    // ════════════════════════════════════════════════════
    // MISC HELPERS
    // ════════════════════════════════════════════════════


    // ════════════════════════════════════════════════════
    // SETTINGS  — configurable values stored in wp_options
    // ════════════════════════════════════════════════════

    // Returns app-level settings.
    // transaction_days: how many days of history to show on transaction pages.
    public function get_settings( WP_REST_Request $r ): WP_REST_Response {
        $days = (int) get_option('dairy_transaction_days', 7);
        return $this->ok([
            'transaction_days' => max(1, min(90, $days)),
        ]);
    }

    // ════════════════════════════════════════════════════
    // PRODUCTION TRANSACTIONS — all production entries for
    // last N days, one row per record, with user first name
    // ════════════════════════════════════════════════════

    public function get_production_transactions( WP_REST_Request $r ): WP_REST_Response {
        $loc = (int) ($r->get_param('location_id') ?? 0);
        if ($loc) {
            if ($e = $this->check_location_access($this->uid(), $loc)) return $e;
        }
        try {
            $db   = $this->db();
            // Date range: from/to params, or single entry_date, or default last N days
            $p_from = $r->get_param('from');
            $p_to   = $r->get_param('to');
            $single_date = $r->get_param('entry_date');
            if ($p_from && $p_to && preg_match('/^\d{4}-\d{2}-\d{2}$/', $p_from) && preg_match('/^\d{4}-\d{2}-\d{2}$/', $p_to)) {
                $from = $p_from;
                $to   = $p_to;
            } elseif ($single_date && preg_match('/^\d{4}-\d{2}-\d{2}$/', $single_date)) {
                $from = $single_date;
                $to   = $single_date;
            } else {
                $days = (int) get_option('dairy_transaction_days', 7);
                $days = max(1, min(90, $days));
                $from = date('Y-m-d', strtotime("-{$days} days"));
                $to   = date('Y-m-d');
            }

            $loc_cond = $loc ? $db->prepare(' AND t.location_id = %d', $loc) : '';

            // V4: All production-related transactions (purchases + processing)
            $txns = $db->get_results($db->prepare(
                "SELECT t.id, t.transaction_date AS entry_date, t.transaction_type,
                        t.processing_type, t.party_id, t.notes,
                        p.name AS party_name, p.party_type,
                        t.created_at, t.created_by,
                        l.name AS location_name
                   FROM wp_mf_4_transactions t
                   JOIN wp_mf_3_dp_locations l ON l.id = t.location_id
                   LEFT JOIN wp_mf_4_parties p ON p.id = t.party_id
                  WHERE t.transaction_date BETWEEN %s AND %s
                    AND t.transaction_type IN ('purchase', 'processing')
                    $loc_cond
                  ORDER BY t.transaction_date DESC, t.created_at DESC",
                $from, $to
            ), ARRAY_A);
            $this->check_db('prod_tx_v4');

            if (empty($txns)) {
                return $this->ok(['days' => $days ?? 7, 'from' => $from, 'to' => $to, 'rows' => []]);
            }

            // Get all lines for these transactions in one query
            $txn_ids = array_column($txns, 'id');
            $id_list = implode(',', array_map('intval', $txn_ids));
            $lines = $db->get_results(
                "SELECT tl.transaction_id, tl.product_id, pr.name AS product_name,
                        tl.qty, tl.rate, tl.snf, tl.fat, tl.source_transaction_id
                   FROM wp_mf_4_transaction_lines tl
                   JOIN wp_mf_3_dp_products pr ON pr.id = tl.product_id
                  WHERE tl.transaction_id IN ($id_list)
                  ORDER BY tl.id",
                ARRAY_A
            );
            $this->check_db('prod_tx_v4.lines');

            // Group lines by transaction_id
            $lines_map = [];
            foreach ($lines as $ln) {
                $lines_map[(int)$ln['transaction_id']][] = $ln;
            }

            // Resolve user names
            $user_ids = array_unique(array_filter(array_column($txns, 'created_by')));
            $names = $this->resolve_first_names($user_ids);

            // Build rows with type derivation
            $rows = [];
            foreach ($txns as $t) {
                $tid = (int)$t['id'];
                $txn_lines = $lines_map[$tid] ?? [];
                $txn_type = $t['transaction_type'];
                $proc_type = $t['processing_type'] ?? '';

                // Derive human-readable type
                if ($txn_type === 'purchase') {
                    $primary_pid = !empty($txn_lines) ? (int)$txn_lines[0]['product_id'] : 0;
                    switch ($primary_pid) {
                        case 1:  $type = 'FF Milk Purchase'; break;
                        case 3:  $type = 'Cream Purchase'; break;
                        case 4:  $type = 'Butter Purchase'; break;
                        default: $type = 'Ingredient Purchase'; break;
                    }
                } else {
                    switch ($proc_type) {
                        case 'ff_milk_processing': $type = 'FF Milk Processing'; break;
                        case 'pouch_production':   $type = 'Pouch Production'; break;
                        case 'curd_production':    $type = 'Curd Production'; break;
                        case 'madhusudan_sale':    $type = 'Madhusudan Sale'; break;
                        default:                  $type = 'Processing'; break;
                    }
                }

                $rows[] = [
                    'id'               => $tid,
                    'entry_date'       => $t['entry_date'],
                    'type'             => $type,
                    'transaction_type' => $txn_type,
                    'processing_type'  => $proc_type ?: null,
                    'party_name'       => $t['party_name'] ?? '',
                    'notes'            => $t['notes'] ? json_decode($t['notes'], true) : null,
                    'created_at'       => $t['created_at'],
                    'user_name'        => $names[$t['created_by']] ?? 'Unknown',
                    'location_name'    => $t['location_name'],
                    'lines'            => $txn_lines,
                ];
            }

            return $this->ok([
                'days' => $days ?? 7,
                'from' => $from,
                'to'   => $to,
                'rows' => $rows,
            ]);
        } catch (\Exception $e) { return $this->exc('get_production_transactions', $e); }
    }

    // ════════════════════════════════════════════════════
    // SALES TRANSACTIONS — all sales for last N days (V4)
    // ════════════════════════════════════════════════════

    public function get_sales_transactions( WP_REST_Request $r ): WP_REST_Response {
        $loc = (int) ($r->get_param('location_id') ?? 0);
        if ($loc) {
            if ($e = $this->check_location_access($this->uid(), $loc)) return $e;
        }
        try {
            $db   = $this->db();
            $days = (int) get_option('dairy_transaction_days', 7);
            $days = max(1, min(90, $days));
            $from = date('Y-m-d', strtotime("-{$days} days"));
            $to   = date('Y-m-d');
            $loc_cond = $loc ? $db->prepare(' AND t.location_id = %d', $loc) : '';

            // V4: sale transactions with lines
            $rows = $db->get_results($db->prepare(
                "SELECT t.id, t.transaction_date AS entry_date,
                        tl.product_id, pr.name AS product_name,
                        ABS(tl.qty) AS quantity_kg, tl.rate,
                        ROUND(ABS(tl.qty) * tl.rate, 2) AS total,
                        t.created_at, t.created_by,
                        p.name AS customer_name,
                        l.name AS location_name
                   FROM wp_mf_4_transactions t
                   JOIN wp_mf_4_transaction_lines tl ON tl.transaction_id = t.id
                   JOIN wp_mf_3_dp_products pr ON pr.id = tl.product_id
                   LEFT JOIN wp_mf_4_parties p ON p.id = t.party_id
                   JOIN wp_mf_3_dp_locations l ON l.id = t.location_id
                  WHERE t.transaction_type = 'sale'
                    AND t.transaction_date BETWEEN %s AND %s
                    $loc_cond
                  ORDER BY t.transaction_date DESC, t.created_at DESC",
                $from, $to
            ), ARRAY_A);
            $this->check_db('sales_tx_v4');

            $user_ids = array_unique(array_filter(array_column($rows, 'created_by')));
            $names    = $this->resolve_first_names($user_ids);

            foreach ($rows as &$row) {
                $row['user_name'] = $names[$row['created_by']] ?? 'Unknown';
            }
            unset($row);

            return $this->ok([
                'days' => $days,
                'from' => $from,
                'to'   => $to,
                'rows' => $rows,
            ]);
        } catch (\Exception $e) { return $this->exc('get_sales_transactions', $e); }
    }

    // ════════════════════════════════════════════════════
    // FUNDS REPORT  (finance only — aggregates all locations)
    // ════════════════════════════════════════════════════

    public function get_funds_report( WP_REST_Request $r ): WP_REST_Response {
        if ($e = $this->check_finance_access($this->uid())) return $e;
        try {
            $db = $this->db();
            $filter_loc = (int) ($r->get_param('location_id') ?? 0);
            $loc_cond = $filter_loc ? $db->prepare(' AND location_id = %d', $filter_loc) : '';

            $v4_loc_cond = $filter_loc ? $db->prepare(' AND t.location_id = %d', $filter_loc) : '';

            // 1. Sales total — all time, optionally filtered by location (V4)
            $sales_total = (float) $db->get_var(
                "SELECT COALESCE(SUM(ABS(tl.qty) * tl.rate), 0)
                   FROM wp_mf_4_transactions t
                   JOIN wp_mf_4_transaction_lines tl ON tl.transaction_id = t.id
                  WHERE t.transaction_type = 'sale' $v4_loc_cond"
            );
            $this->check_db('funds_report.sales');

            // 2. Stock value — latest day stock per location × estimated rates
            $rates_rows = $db->get_results(
                "SELECT product_id, rate FROM wp_mf_3_dp_estimated_rates", ARRAY_A);
            $this->check_db('funds_report.rates');
            $rates = [];
            foreach ($rates_rows as $rw) $rates[(int)$rw['product_id']] = (float)$rw['rate'];

            if ($filter_loc) {
                $locations = $db->get_results($db->prepare(
                    "SELECT id FROM wp_mf_3_dp_locations WHERE is_active=1 AND id=%d", $filter_loc), ARRAY_A);
            } else {
                $locations = $db->get_results(
                    "SELECT id FROM wp_mf_3_dp_locations WHERE is_active=1", ARRAY_A);
            }
            $this->check_db('funds_report.locations');

            $products = $db->get_results(
                "SELECT id FROM wp_mf_3_dp_products WHERE is_active=1 ORDER BY sort_order", ARRAY_A);
            $this->check_db('funds_report.products');

            $from = date('Y-m-d', strtotime('-29 days'));
            $to   = date('Y-m-d');
            $stock_value = 0.0;

            foreach ($locations as $loc_row) {
                $loc = (int) $loc_row['id'];

                // V4: single stock movements query (signed qty includes sales)
                $prod_rows = $db->get_results($db->prepare(
                    $this->stock_movements_sql(), $loc, $from, $to
                ), ARRAY_A);
                $this->check_db("funds_report.stock_loc_$loc");

                // Build daily movements
                $daily = [];
                foreach ($prod_rows as $row) $daily[$row['entry_date']][$row['product_id']] = ($daily[$row['entry_date']][$row['product_id']] ?? 0) + (float)$row['qty'];

                // Walk 30-day window, carry forward running balance
                $running = [];
                foreach ($products as $p) $running[$p['id']] = 0;
                for ($ts = strtotime($from); $ts <= strtotime($to); $ts += 86400) {
                    $d = date('Y-m-d', $ts);
                    foreach ($products as $p) {
                        $running[$p['id']] += $daily[$d][$p['id']] ?? 0;
                    }
                }
                // running[] now has the latest-day stock for this location
                foreach ($products as $p) {
                    $pid = (int) $p['id'];
                    $stock_value += round($running[$pid] * ($rates[$pid] ?? 0), 2);
                }
            }
            $stock_value = round($stock_value, 2);

            // 3. Total vendor due — all-time purchases minus all-time payments (V4)
            $total_purchases = (float) $db->get_var(
                "SELECT COALESCE(SUM(ROUND(tl.qty * tl.rate, 2)), 0)
                   FROM wp_mf_4_transactions t
                   JOIN wp_mf_4_transaction_lines tl ON tl.transaction_id = t.id
                  WHERE t.transaction_type = 'purchase'
                    AND t.party_id > 1
                    AND tl.qty > 0 $v4_loc_cond"
            );
            $this->check_db('funds_report.purchases');

            $total_payments = (float) $db->get_var(
                "SELECT COALESCE(SUM(amount), 0) FROM wp_mf_4_vendor_payments"
            );
            $this->check_db('funds_report.payments');

            $vendor_due = round($total_purchases - $total_payments, 2);
            $free_cash  = round($sales_total + $stock_value - $vendor_due, 2);

            return $this->ok([
                'sales_total' => round($sales_total, 2),
                'stock_value' => $stock_value,
                'vendor_due'  => $vendor_due,
                'free_cash'   => $free_cash,
            ]);
        } catch (\Exception $e) { return $this->exc('get_funds_report', $e); }
    }

    // ── Resolve WP user IDs → first names ─────────────────────
    // Uses display_name; extracts the first word as "first name".
    private function resolve_first_names( array $user_ids ): array {
        if (empty($user_ids)) return [];
        $names = [];
        foreach ($user_ids as $uid) {
            $user = get_userdata((int) $uid);
            if ($user) {
                // Prefer first_name meta, fall back to first word of display_name
                $first = $user->first_name ?: explode(' ', $user->display_name)[0];
                $names[$uid] = $first ?: $user->user_login;
            }
        }
        return $names;
    }

    // ════════════════════════════════════════════════════
    // CUSTOMER POUCH RATES
    // ════════════════════════════════════════════════════

    public function get_customer_pouch_rates(WP_REST_Request $r): WP_REST_Response {
        try {
            $pp_id = (int) $r->get_param('pouch_product_id');
            $db = $this->db();
            if ($pp_id > 0) {
                $rows = $db->get_results($db->prepare("
                    SELECT cpr.id, cpr.party_id, p.name AS party_name,
                           cpr.pouch_product_id, cpr.crate_rate
                      FROM wp_mf_3_dp_customer_pouch_rates cpr
                      JOIN wp_mf_4_parties p ON p.id = cpr.party_id
                     WHERE cpr.pouch_product_id = %d
                     ORDER BY p.name
                ", $pp_id), ARRAY_A);
            } else {
                $rows = $db->get_results("
                    SELECT cpr.id, cpr.party_id, p.name AS party_name,
                           cpr.pouch_product_id, cpr.crate_rate
                      FROM wp_mf_3_dp_customer_pouch_rates cpr
                      JOIN wp_mf_4_parties p ON p.id = cpr.party_id
                     ORDER BY p.name
                ", ARRAY_A);
            }
            $this->check_db('get_customer_pouch_rates');
            return $this->ok($rows ?? []);
        } catch (\Exception $e) { return $this->exc('get_customer_pouch_rates', $e); }
    }

    public function save_customer_pouch_rate(WP_REST_Request $r): WP_REST_Response {
        try {
            $party_id   = (int) $r->get_param('party_id');
            $pp_id      = (int) $r->get_param('pouch_product_id');
            $crate_rate = $this->d2($r->get_param('crate_rate'));

            if ($party_id <= 0 || $pp_id <= 0) return $this->err('party_id and pouch_product_id required.');
            if ((float) $crate_rate <= 0) return $this->err('crate_rate must be positive.');

            $db = $this->db();
            // Upsert: INSERT ON DUPLICATE KEY UPDATE
            $sql = $db->prepare("
                INSERT INTO wp_mf_3_dp_customer_pouch_rates (party_id, pouch_product_id, crate_rate)
                VALUES (%d, %d, %s)
                ON DUPLICATE KEY UPDATE crate_rate = VALUES(crate_rate)
            ", $party_id, $pp_id, $crate_rate);
            $result = $db->query($sql);
            $this->check_db('save_customer_pouch_rate');
            if ($result === false) {
                return $this->err('Database error saving customer pouch rate.', 500);
            }
            // Get the id (insert_id if new, or look up if updated)
            $id = $db->insert_id;
            if (!$id) {
                $id = (int) $db->get_var($db->prepare("
                    SELECT id FROM wp_mf_3_dp_customer_pouch_rates
                     WHERE party_id = %d AND pouch_product_id = %d
                ", $party_id, $pp_id));
            }
            $this->audit('wp_mf_3_dp_customer_pouch_rates', $id, 'UPSERT', null,
                ['party_id' => $party_id, 'pouch_product_id' => $pp_id, 'crate_rate' => $crate_rate]);
            $this->log("Customer pouch rate saved: party=$party_id pouch=$pp_id rate=$crate_rate");
            return $this->ok(['id' => $id], 201);
        } catch (\Exception $e) { return $this->exc('save_customer_pouch_rate', $e); }
    }

    public function delete_customer_pouch_rate(WP_REST_Request $r): WP_REST_Response {
        try {
            $id = (int) $r['id'];
            $db = $this->db();
            $old = $db->get_row($db->prepare(
                "SELECT * FROM wp_mf_3_dp_customer_pouch_rates WHERE id = %d", $id), ARRAY_A);
            if (!$old) return $this->err('Rate not found.', 404);
            $result = $db->delete('wp_mf_3_dp_customer_pouch_rates', ['id' => $id]);
            $this->check_db('delete_customer_pouch_rate');
            if ($result === false) {
                return $this->err('Database error deleting customer pouch rate.', 500);
            }
            $this->audit('wp_mf_3_dp_customer_pouch_rates', $id, 'DELETE', $old, null);
            $this->log("Customer pouch rate deleted: id=$id");
            return $this->ok(['deleted' => true]);
        } catch (\Exception $e) { return $this->exc('delete_customer_pouch_rate', $e); }
    }

    // ════════════════════════════════════════════════════
    // SHARED STOCK MOVEMENTS SQL
    // ════════════════════════════════════════════════════

    /**
     * Returns the V4 stock movements SQL.
     * All movements are in wp_mf_4_transaction_lines with signed qty.
     * Requires 1 set of ($loc, $from, $to) parameters.
     */
    private function stock_movements_sql(): string {
        return "
            SELECT t.transaction_date AS entry_date, tl.product_id,
                   SUM(tl.qty) AS qty
              FROM wp_mf_4_transaction_lines tl
              JOIN wp_mf_4_transactions t ON t.id = tl.transaction_id
             WHERE t.location_id = %d
               AND t.transaction_date BETWEEN %s AND %s
             GROUP BY t.transaction_date, tl.product_id
        ";
    }

    // V3 Milk Availability removed — Flutter uses /v4/milk-availability

    // ════════════════════════════════════════════════════
    // POUCH PRODUCTS CRUD
    // ════════════════════════════════════════════════════

    public function get_pouch_products(): WP_REST_Response {
        try {
            $rows = $this->db()->get_results(
                "SELECT id, name, milk_per_pouch, pouches_per_crate, crate_rate, is_active FROM wp_mf_3_dp_pouch_products ORDER BY name",
                ARRAY_A);
            $this->check_db('get_pouch_products');
            return $this->ok($rows ?? []);
        } catch (\Exception $e) { return $this->exc('get_pouch_products', $e); }
    }

    public function save_pouch_product( WP_REST_Request $r ): WP_REST_Response {
        try {
            $name  = trim($r->get_param('name') ?? '');
            $milk  = (float) ($r->get_param('milk_per_pouch') ?? 0);
            $ppc   = (int)   ($r->get_param('pouches_per_crate') ?? 12);
            $crate_rate = (float) ($r->get_param('crate_rate') ?? 0);
            if (empty($name)) return $this->err('name is required.');
            if ($milk <= 0)   return $this->err('milk_per_pouch must be > 0.');
            if ($ppc  <= 0)   return $this->err('pouches_per_crate must be > 0.');

            $db   = $this->db();
            $data = [
                'name'             => $name,
                'milk_per_pouch'   => $this->d2($milk),
                'pouches_per_crate'=> $ppc,
                'crate_rate'       => $this->d2($crate_rate),
            ];
            if ($db->insert('wp_mf_3_dp_pouch_products', $data) === false) {
                $this->log_db('save_pouch_product', $db->last_error);
                return $this->err('Database error (duplicate name?).', 500);
            }
            $id = $db->insert_id;
            $this->audit('wp_mf_3_dp_pouch_products', $id, 'INSERT', null, $data);
            return $this->ok(['id' => $id], 201);
        } catch (\Exception $e) { return $this->exc('save_pouch_product', $e); }
    }

    public function update_pouch_product( WP_REST_Request $r ): WP_REST_Response {
        try {
            $id = (int) $r['id'];
            if (!$id) return $this->err('id is required.');
            $db = $this->db();
            $old = $db->get_row($db->prepare(
                "SELECT * FROM wp_mf_3_dp_pouch_products WHERE id=%d", $id), ARRAY_A);
            if (!$old) return $this->err('Pouch product not found.', 404);

            $name   = trim($r->get_param('name') ?? $old['name']);
            $milk   = $r->get_param('milk_per_pouch') !== null ? (float)$r->get_param('milk_per_pouch') : (float)$old['milk_per_pouch'];
            $ppc    = $r->get_param('pouches_per_crate') !== null ? (int)$r->get_param('pouches_per_crate') : (int)$old['pouches_per_crate'];
            $crate_rate = $r->get_param('crate_rate') !== null ? (float)$r->get_param('crate_rate') : (float)$old['crate_rate'];
            $active = $r->get_param('is_active') !== null ? (int)$r->get_param('is_active') : (int)$old['is_active'];

            $data = [
                'name'              => $name,
                'milk_per_pouch'    => $this->d2($milk),
                'pouches_per_crate' => $ppc,
                'crate_rate'        => $this->d2($crate_rate),
                'is_active'         => $active,
            ];
            $db->update('wp_mf_3_dp_pouch_products', $data, ['id' => $id]);
            $this->check_db('update_pouch_product');
            $new = $db->get_row($db->prepare(
                "SELECT * FROM wp_mf_3_dp_pouch_products WHERE id=%d", $id), ARRAY_A);
            $this->audit('wp_mf_3_dp_pouch_products', $id, 'UPDATE', $old, $new);
            return $this->ok(['id' => $id]);
        } catch (\Exception $e) { return $this->exc('update_pouch_product', $e); }
    }

    // V3 Pouch Production save/get removed — Flutter uses /v4/transaction

    // V3 Pouch Stock removed — Flutter uses /v4/transaction

    // get_pouch_rates / save_pouch_rates removed — rates live in pouch_products.crate_rate

    public function get_pouch_pnl( WP_REST_Request $r ): WP_REST_Response {
        if ($e = $this->validate_loc($r)) return $e;
        if ($e = $this->check_location_access($this->uid(), (int)$r['location_id'])) return $e;
        try {
            $db  = $this->db();
            $loc = (int) $r['location_id'];

            // V4: pouch_production processing transactions
            $txns = $db->get_results($db->prepare(
                "SELECT id, transaction_date AS entry_date, notes, created_at
                   FROM wp_mf_4_transactions
                  WHERE location_id = %d
                    AND transaction_type = 'processing'
                    AND processing_type = 'pouch_production'
                  ORDER BY transaction_date DESC, id DESC", $loc), ARRAY_A);
            $this->check_db('pouch_pnl.txns');

            // Get pouch type info + rates from pouch_products
            $pt_rows = $db->get_results(
                "SELECT id, name, milk_per_pouch, pouches_per_crate, crate_rate FROM wp_mf_3_dp_pouch_products", ARRAY_A);
            $pts = [];
            $rates = [];
            foreach ($pt_rows as $p) {
                $pts[(int)$p['id']] = $p;
                $rates[(int)$p['id']] = (float)$p['crate_rate'];
            }

            // Batch-fetch all transaction lines
            $all_lines = [];
            if (!empty($txns)) {
                $txn_ids = array_column($txns, 'id');
                $ph = implode(',', array_fill(0, count($txn_ids), '%d'));
                $lines_q = $db->get_results($db->prepare(
                    "SELECT transaction_id, product_id, qty, source_transaction_id
                       FROM wp_mf_4_transaction_lines
                      WHERE transaction_id IN ($ph)",
                    ...$txn_ids), ARRAY_A) ?: [];
                foreach ($lines_q as $ln) {
                    $all_lines[$ln['transaction_id']][] = $ln;
                }
            }

            // V4: per-party weighted average purchase rate for FF milk
            $avg_rates = $db->get_results($db->prepare(
                "SELECT t.party_id,
                        CASE WHEN SUM(tl.qty) > 0
                             THEN SUM(tl.qty * tl.rate) / SUM(tl.qty)
                             ELSE 0 END AS avg_rate
                   FROM wp_mf_4_transactions t
                   JOIN wp_mf_4_transaction_lines tl ON tl.transaction_id = t.id
                  WHERE t.location_id = %d
                    AND t.transaction_type = 'purchase'
                    AND tl.product_id = 1
                    AND tl.qty > 0
                  GROUP BY t.party_id", $loc), ARRAY_A) ?: [];
            $this->check_db('pouch_pnl.avg_rates');
            $party_avg = [];
            foreach ($avg_rates as $ar) $party_avg[(int)$ar['party_id']] = (float)$ar['avg_rate'];

            $rows = [];
            $grand_revenue = 0.0;
            $grand_cost    = 0.0;
            $grand_crates  = 0;

            foreach (($txns ?? []) as $txn) {
                $txn_id = (int) $txn['id'];
                $notes  = $txn['notes'] ? json_decode($txn['notes'], true) : [];
                $pouch_lines = $notes['pouch_lines'] ?? [];
                $lines  = $all_lines[$txn_id] ?? [];

                // Calculate revenue from pouch_lines in notes
                $revenue = 0.0;
                $total_crates = 0;
                $line_details = [];
                foreach ($pouch_lines as $pl) {
                    $ptid   = (int)($pl['pouch_type_id'] ?? 0);
                    $crates = (int)($pl['crate_count'] ?? 0);
                    $rate   = $rates[$ptid] ?? 0;
                    $line_rev = $rate * $crates;
                    $revenue += $line_rev;
                    $total_crates += $crates;
                    $pt = $pts[$ptid] ?? null;
                    $line_details[] = [
                        'pouch_type'    => $pt['name'] ?? 'Unknown',
                        'crate_count'   => $crates,
                        'rate_per_crate'=> $this->d2($rate),
                        'revenue'       => $this->d2($line_rev),
                    ];
                }

                // Cost: milk input lines (product_id=1, negative qty) using source party avg rate
                $cost = 0.0;
                foreach ($lines as $ln) {
                    if ((int)$ln['product_id'] !== 1) continue;
                    $kg = abs((float)$ln['qty']);
                    $src_id = $ln['source_transaction_id'] ?? null;
                    if ($src_id) {
                        $src_party = (int) $db->get_var($db->prepare(
                            "SELECT party_id FROM wp_mf_4_transactions WHERE id = %d", $src_id));
                        $cost += $kg * ($party_avg[$src_party] ?? 0);
                    }
                }

                $profit = $revenue - $cost;
                $rows[] = [
                    'id'           => $txn_id,
                    'entry_date'   => $txn['entry_date'],
                    'total_crates' => $total_crates,
                    'revenue'      => $this->d2($revenue),
                    'cost'         => $this->d2($cost),
                    'profit'       => $this->d2($profit),
                    'lines'        => $line_details,
                ];

                $grand_revenue += $revenue;
                $grand_cost    += $cost;
                $grand_crates  += $total_crates;
            }

            return $this->ok([
                'rows'   => $rows,
                'totals' => [
                    'total_crates' => $grand_crates,
                    'revenue'      => $this->d2($grand_revenue),
                    'cost'         => $this->d2($grand_cost),
                    'profit'       => $this->d2($grand_revenue - $grand_cost),
                ],
            ]);
        } catch (\Exception $e) { return $this->exc('get_pouch_pnl', $e); }
    }

    private function db(): wpdb  { global $wpdb; return $wpdb; }
    private function uid(): int  { return get_current_user_id(); }
    // ════════════════════════════════════════════════════
    // REPORT MENU CONFIG
    // ════════════════════════════════════════════════════

    public function get_report_menu(): WP_REST_Response {
        try {
            $rows = $this->db()->get_results(
                "SELECT `key`, label, subtitle, sort_order, permission
                   FROM wp_mf_3_dp_report_menu
                  WHERE is_active = 1
                  ORDER BY sort_order, label",
                ARRAY_A);
            $this->check_db('get_report_menu');
            return $this->ok($rows ?? []);
        } catch (\Exception $e) { return $this->exc('get_report_menu', $e); }
    }

    // ════════════════════════════════════════════════════
    // REPORT EMAIL SCHEDULES — CRUD
    // ════════════════════════════════════════════════════

    public function get_report_email_schedules( WP_REST_Request $r ): WP_REST_Response {
        if ($e = $this->check_finance_access($this->uid())) return $e;
        try {
            $rows = $this->db()->get_results(
                "SELECT s.*, rm.label AS report_label, l.name AS location_name
                   FROM wp_mf_3_dp_report_email_schedules s
                   LEFT JOIN wp_mf_3_dp_report_menu rm ON rm.`key` = s.report_key
                   LEFT JOIN wp_mf_3_dp_locations l ON l.id = s.location_id
                  ORDER BY s.is_active DESC, s.report_key, s.id",
                ARRAY_A);
            $this->check_db('get_report_email_schedules');

            // Available reports for dropdown
            $reports = $this->db()->get_results(
                "SELECT `key`, label FROM wp_mf_3_dp_report_menu WHERE is_active = 1 ORDER BY sort_order", ARRAY_A);
            $this->check_db('get_report_email_schedules.reports');

            // Available locations for dropdown
            $locations = $this->db()->get_results(
                "SELECT id, name FROM wp_mf_3_dp_locations WHERE is_active = 1 ORDER BY name", ARRAY_A);
            $this->check_db('get_report_email_schedules.locations');

            return $this->ok([
                'schedules' => $rows ?? [],
                'reports'   => $reports ?? [],
                'locations' => $locations ?? [],
            ]);
        } catch (\Exception $e) { return $this->exc('get_report_email_schedules', $e); }
    }

    public function save_report_email_schedule( WP_REST_Request $r ): WP_REST_Response {
        if ($e = $this->check_finance_access($this->uid())) return $e;
        try {
            $db = $this->db();
            $id         = (int) ($r->get_param('id') ?? 0);
            $report_key = trim($r->get_param('report_key') ?? '');
            $emails     = trim($r->get_param('emails') ?? '');
            $frequency  = $r->get_param('frequency') ?? 'daily';
            $day_of_week  = $r->get_param('day_of_week');
            $day_of_month = $r->get_param('day_of_month');
            $time_hour    = (int) ($r->get_param('time_hour') ?? 8);
            $location_id  = $r->get_param('location_id');
            $date_range_days = (int) ($r->get_param('date_range_days') ?? 7);
            $is_active    = (int) ($r->get_param('is_active') ?? 1);

            if (!$report_key) return $this->err('Report is required.');
            if (!$emails) return $this->err('At least one email is required.');
            if (!in_array($frequency, ['daily', 'weekly', 'monthly'])) return $this->err('Invalid frequency.');
            if ($time_hour < 0 || $time_hour > 23) return $this->err('Hour must be 0-23.');
            if ($date_range_days < 1 || $date_range_days > 90) return $this->err('Date range must be 1-90 days.');

            // Validate emails
            $email_list = array_map('trim', explode(',', $emails));
            foreach ($email_list as $em) {
                if (!filter_var($em, FILTER_VALIDATE_EMAIL)) return $this->err("Invalid email: $em");
            }
            $emails = implode(',', $email_list);

            $data = [
                'report_key'     => $report_key,
                'emails'         => $emails,
                'frequency'      => $frequency,
                'day_of_week'    => $frequency === 'weekly' ? (int)$day_of_week : null,
                'day_of_month'   => $frequency === 'monthly' ? (int)$day_of_month : null,
                'time_hour'      => $time_hour,
                'location_id'    => $location_id ? (int)$location_id : null,
                'date_range_days'=> $date_range_days,
                'is_active'      => $is_active,
            ];

            if ($id > 0) {
                // Update
                $old = $db->get_row($db->prepare(
                    "SELECT * FROM wp_mf_3_dp_report_email_schedules WHERE id=%d", $id), ARRAY_A);
                if (!$old) return $this->err('Schedule not found.', 404);
                $db->update('wp_mf_3_dp_report_email_schedules', $data, ['id' => $id]);
                $this->check_db('save_report_email_schedule.update');
                $this->audit('wp_mf_3_dp_report_email_schedules', $id, 'UPDATE', $old, $data);
                return $this->ok(['id' => $id]);
            } else {
                // Insert
                $data['created_by'] = $this->uid();
                if ($db->insert('wp_mf_3_dp_report_email_schedules', $data) === false) {
                    $this->log('[DairyAPI] save_report_email_schedule insert error: ' . $db->last_error);
                    return $this->err('Database error.', 500);
                }
                $new_id = $db->insert_id;
                $this->audit('wp_mf_3_dp_report_email_schedules', $new_id, 'INSERT', null, $data);
                return $this->ok(['id' => $new_id], 201);
            }
        } catch (\Exception $e) { return $this->exc('save_report_email_schedule', $e); }
    }

    public function delete_report_email_schedule( WP_REST_Request $r ): WP_REST_Response {
        if ($e = $this->check_finance_access($this->uid())) return $e;
        try {
            $db = $this->db();
            $id = (int) $r['id'];
            $old = $db->get_row($db->prepare(
                "SELECT * FROM wp_mf_3_dp_report_email_schedules WHERE id=%d", $id), ARRAY_A);
            if (!$old) return $this->err('Schedule not found.', 404);
            $db->delete('wp_mf_3_dp_report_email_schedules', ['id' => $id]);
            $this->check_db('delete_report_email_schedule');
            $this->audit('wp_mf_3_dp_report_email_schedules', $id, 'DELETE', $old, null);
            return $this->ok(['deleted' => $id]);
        } catch (\Exception $e) { return $this->exc('delete_report_email_schedule', $e); }
    }

    public function test_report_email( WP_REST_Request $r ): WP_REST_Response {
        if ($e = $this->check_finance_access($this->uid())) return $e;
        try {
            $db = $this->db();
            $id = (int) $r['id'];
            $schedule = $db->get_row($db->prepare(
                "SELECT * FROM wp_mf_3_dp_report_email_schedules WHERE id=%d", $id), ARRAY_A);
            if (!$schedule) return $this->err('Schedule not found.', 404);

            $result = $this->send_report_email($schedule);
            if ($result === true) return $this->ok(['sent' => true]);
            return $this->err($result ?: 'Failed to send email.', 500);
        } catch (\Exception $e) { return $this->exc('test_report_email', $e); }
    }

    // ════════════════════════════════════════════════════
    // REPORT EMAIL — SEND LOGIC + CRON
    // ════════════════════════════════════════════════════

    /**
     * WP-Cron callback: process all due schedules.
     */
    public function process_scheduled_reports(): void {
        $db = $this->db();
        $now = new \DateTime('now', new \DateTimeZone('Asia/Kolkata'));
        $current_hour = (int) $now->format('G');
        $today = $now->format('Y-m-d');
        $day_of_week = (int) $now->format('w');  // 0=Sun..6=Sat
        $day_of_month = (int) $now->format('j');

        $schedules = $db->get_results($db->prepare(
            "SELECT * FROM wp_mf_3_dp_report_email_schedules
              WHERE is_active = 1 AND time_hour = %d
                AND (last_sent_at IS NULL OR DATE(last_sent_at) < %s)",
            $current_hour, $today), ARRAY_A);

        foreach ($schedules ?: [] as $s) {
            // Check frequency match
            if ($s['frequency'] === 'weekly' && (int)$s['day_of_week'] !== $day_of_week) continue;
            if ($s['frequency'] === 'monthly' && (int)$s['day_of_month'] !== $day_of_month) continue;

            $result = $this->send_report_email($s);
            if ($result === true) {
                $db->update('wp_mf_3_dp_report_email_schedules',
                    ['last_sent_at' => $now->format('Y-m-d H:i:s')],
                    ['id' => (int)$s['id']]);
            } else {
                $this->log("[DairyAPI] Scheduled report email failed for schedule #{$s['id']}: $result");
            }
        }
    }

    /**
     * Generate report HTML and send via wp_mail.
     * Returns true on success, or error string on failure.
     */
    private function send_report_email( array $schedule ) {
        $report_key = $schedule['report_key'];
        $loc_id     = $schedule['location_id'] ? (int)$schedule['location_id'] : 0;
        $days       = (int)($schedule['date_range_days'] ?? 7);
        $to         = date('Y-m-d');
        $from       = date('Y-m-d', strtotime("-" . ($days - 1) . " days"));

        // Get report label
        $db = $this->db();
        $report_label = $db->get_var($db->prepare(
            "SELECT label FROM wp_mf_3_dp_report_menu WHERE `key` = %s", $report_key)) ?: $report_key;

        $loc_name = '';
        if ($loc_id) {
            $loc_name = $db->get_var($db->prepare(
                "SELECT name FROM wp_mf_3_dp_locations WHERE id = %d", $loc_id)) ?: '';
        }

        // Generate report data
        $data = $this->generate_report_data($report_key, $from, $to, $loc_id);
        if (is_string($data)) return $data; // error message

        // Build HTML
        $subject = "$report_label — $from to $to" . ($loc_name ? " ($loc_name)" : '');
        $html = $this->render_report_html($report_label, $data, $from, $to, $loc_name);

        // Send
        $emails = array_map('trim', explode(',', $schedule['emails']));
        $headers = ['Content-Type: text/html; charset=UTF-8'];
        $sent = wp_mail($emails, $subject, $html, $headers);
        return $sent ? true : 'wp_mail() returned false';
    }

    /**
     * Generate report data array for a given report key.
     * Returns array of rows or error string.
     */
    private function generate_report_data( string $key, string $from, string $to, int $loc ): array|string {
        $db = $this->db();
        $loc_cond  = $loc ? $db->prepare(' AND t.location_id = %d', $loc) : '';
        $test_cond = $loc ? '' : " AND l.code != 'TEST'";
        $loc_join  = $loc ? '' : ' JOIN wp_mf_3_dp_locations l ON l.id = t.location_id';

        switch ($key) {
            case 'daily_product_sales':
            case 'daily_customer_sales':
                // Sales aggregated by date (product or customer pivot)
                $group_col = $key === 'daily_product_sales' ? 'pr.name' : 'p.name';
                $group_alias = $key === 'daily_product_sales' ? 'product' : 'customer';
                $rows = $db->get_results($db->prepare(
                    "SELECT t.transaction_date AS date, $group_col AS $group_alias,
                            SUM(ABS(tl.qty)) AS qty_kg,
                            ROUND(SUM(ABS(tl.qty) * tl.rate), 2) AS total
                       FROM wp_mf_4_transactions t
                       JOIN wp_mf_4_transaction_lines tl ON tl.transaction_id = t.id
                       JOIN wp_mf_3_dp_products pr ON pr.id = tl.product_id
                       LEFT JOIN wp_mf_4_parties p ON p.id = t.party_id
                       $loc_join
                      WHERE t.transaction_type = 'sale'
                        AND t.transaction_date BETWEEN %s AND %s $loc_cond $test_cond
                      GROUP BY t.transaction_date, $group_col
                      ORDER BY t.transaction_date DESC, $group_col",
                    $from, $to), ARRAY_A);
                return $rows ?: [];

            case 'sales_transactions':
                $rows = $db->get_results($db->prepare(
                    "SELECT t.transaction_date AS date,
                            pr.name AS product, p.name AS customer,
                            ABS(tl.qty) AS qty_kg, tl.rate,
                            ROUND(ABS(tl.qty) * tl.rate, 2) AS total
                       FROM wp_mf_4_transactions t
                       JOIN wp_mf_4_transaction_lines tl ON tl.transaction_id = t.id
                       JOIN wp_mf_3_dp_products pr ON pr.id = tl.product_id
                       LEFT JOIN wp_mf_4_parties p ON p.id = t.party_id
                       $loc_join
                      WHERE t.transaction_type = 'sale'
                        AND t.transaction_date BETWEEN %s AND %s $loc_cond $test_cond
                      ORDER BY t.transaction_date DESC, t.created_at DESC",
                    $from, $to), ARRAY_A);
                return $rows ?: [];

            case 'vendor_purchase_report':
                $rows = $db->get_results($db->prepare(
                    "SELECT t.transaction_date AS date,
                            COALESCE(p.name, 'Unknown') AS vendor,
                            pr.name AS product,
                            tl.qty AS qty_kg, tl.fat, tl.rate,
                            ROUND(tl.qty * tl.rate, 2) AS amount
                       FROM wp_mf_4_transactions t
                       JOIN wp_mf_4_transaction_lines tl ON tl.transaction_id = t.id
                       JOIN wp_mf_3_dp_products pr ON pr.id = tl.product_id
                       LEFT JOIN wp_mf_4_parties p ON p.id = t.party_id
                       $loc_join
                      WHERE t.transaction_type = 'purchase'
                        AND tl.qty > 0
                        AND t.transaction_date BETWEEN %s AND %s $loc_cond $test_cond
                      ORDER BY t.transaction_date DESC, p.name",
                    $from, $to), ARRAY_A);
                return $rows ?: [];

            case 'cashflow_report':
                // Simplified: daily sales, purchases, payments
                $sales = $db->get_results($db->prepare(
                    "SELECT t.transaction_date AS date,
                            ROUND(SUM(ABS(tl.qty) * tl.rate), 2) AS sales
                       FROM wp_mf_4_transactions t
                       JOIN wp_mf_4_transaction_lines tl ON tl.transaction_id = t.id
                       $loc_join
                      WHERE t.transaction_type = 'sale'
                        AND t.transaction_date BETWEEN %s AND %s $loc_cond $test_cond
                      GROUP BY t.transaction_date
                      ORDER BY t.transaction_date DESC",
                    $from, $to), ARRAY_A) ?: [];
                $purchases = $db->get_results($db->prepare(
                    "SELECT t.transaction_date AS date,
                            ROUND(SUM(tl.qty * tl.rate), 2) AS purchases
                       FROM wp_mf_4_transactions t
                       JOIN wp_mf_4_transaction_lines tl ON tl.transaction_id = t.id
                       $loc_join
                      WHERE t.transaction_type = 'purchase' AND tl.qty > 0
                        AND t.transaction_date BETWEEN %s AND %s $loc_cond $test_cond
                      GROUP BY t.transaction_date",
                    $from, $to), ARRAY_A) ?: [];
                $payments = $db->get_results($db->prepare(
                    "SELECT payment_date AS date, ROUND(SUM(amount), 2) AS payments
                       FROM wp_mf_4_vendor_payments
                      WHERE payment_date BETWEEN %s AND %s
                      GROUP BY payment_date",
                    $from, $to), ARRAY_A) ?: [];
                // Merge into daily rows
                $map = [];
                foreach ($sales as $r) $map[$r['date']]['sales'] = (float)$r['sales'];
                foreach ($purchases as $r) $map[$r['date']]['purchases'] = (float)$r['purchases'];
                foreach ($payments as $r) $map[$r['date']]['payments'] = (float)$r['payments'];
                krsort($map);
                $rows = [];
                foreach ($map as $d => $v) {
                    $rows[] = ['date'=>$d, 'sales'=>$v['sales']??0, 'purchases'=>$v['purchases']??0, 'payments'=>$v['payments']??0];
                }
                return $rows;

            case 'production_transactions':
                $rows = $db->get_results($db->prepare(
                    "SELECT t.transaction_date AS date, t.transaction_type,
                            t.processing_type, COALESCE(p.name,'Internal') AS party,
                            GROUP_CONCAT(CONCAT(pr.name, ': ', tl.qty, ' ', pr.unit) SEPARATOR ', ') AS details
                       FROM wp_mf_4_transactions t
                       JOIN wp_mf_4_transaction_lines tl ON tl.transaction_id = t.id
                       JOIN wp_mf_3_dp_products pr ON pr.id = tl.product_id
                       LEFT JOIN wp_mf_4_parties p ON p.id = t.party_id
                       $loc_join
                      WHERE t.transaction_type IN ('purchase','processing')
                        AND t.transaction_date BETWEEN %s AND %s $loc_cond $test_cond
                      GROUP BY t.id
                      ORDER BY t.transaction_date DESC, t.created_at DESC",
                    $from, $to), ARRAY_A);
                return $rows ?: [];

            default:
                return "Report '$key' is not supported for email.";
        }
    }

    /**
     * Render report data as an HTML email.
     */
    private function render_report_html( string $title, array $rows, string $from, string $to, string $loc_name ): string {
        if (empty($rows)) {
            return "<html><body style='font-family:Arial,sans-serif;'>"
                 . "<h2 style='color:#1B4F72;'>$title</h2>"
                 . "<p>$from to $to" . ($loc_name ? " — $loc_name" : '') . "</p>"
                 . "<p style='color:#999;'>No data for this period.</p>"
                 . "</body></html>";
        }

        $cols = array_keys($rows[0]);
        $th_style = "background:#1B4F72; color:#fff; padding:8px 12px; text-align:left; font-size:13px;";
        $td_style = "padding:6px 12px; border-bottom:1px solid #e0e0e0; font-size:13px;";
        $td_alt   = "padding:6px 12px; border-bottom:1px solid #e0e0e0; font-size:13px; background:#f8f9fa;";

        $html  = "<html><body style='font-family:Arial,sans-serif; margin:0; padding:20px;'>";
        $html .= "<h2 style='color:#1B4F72; margin-bottom:4px;'>$title</h2>";
        $html .= "<p style='color:#666; margin-top:0;'>$from to $to" . ($loc_name ? " &mdash; $loc_name" : '') . "</p>";
        $html .= "<table style='border-collapse:collapse; width:100%; max-width:900px;'>";
        $html .= "<tr>";
        foreach ($cols as $c) {
            $label = ucwords(str_replace('_', ' ', $c));
            $html .= "<th style='$th_style'>$label</th>";
        }
        $html .= "</tr>";

        foreach ($rows as $i => $row) {
            $style = ($i % 2 === 0) ? $td_style : $td_alt;
            $html .= "<tr>";
            foreach ($cols as $c) {
                $val = htmlspecialchars($row[$c] ?? '', ENT_QUOTES, 'UTF-8');
                $align = is_numeric($row[$c] ?? '') ? ' text-align:right;' : '';
                $html .= "<td style='$style$align'>$val</td>";
            }
            $html .= "</tr>";
        }
        $html .= "</table>";
        $html .= "<p style='color:#aaa; font-size:11px; margin-top:16px;'>Auto-generated by Dairy Farm Management System</p>";
        $html .= "</body></html>";
        return $html;
    }

    // ════════════════════════════════════════════════════
    // PROFITABILITY REPORT  (finance)
    // ════════════════════════════════════════════════════

    public function get_profitability_report( WP_REST_Request $r ): WP_REST_Response {
        if ($e = $this->check_finance_access($this->uid())) return $e;
        try {
            $db   = $this->db();
            $from = $r->get_param('from') ?: date('Y-m-d', strtotime('-29 days'));
            $to   = $r->get_param('to')   ?: date('Y-m-d');
            $loc  = (int) ($r->get_param('location_id') ?? 0);
            $flow = $r->get_param('flow') ?: '';

            $loc_cond  = $loc ? $db->prepare(' AND t.location_id = %d', $loc) : '';
            $test_cond = $loc ? '' : " AND l.code != 'TEST'";
            $join_loc  = ' JOIN wp_mf_3_dp_locations l ON l.id = t.location_id';

            // ── Estimated rates ──
            $rate_rows = $db->get_results("SELECT product_id, rate FROM wp_mf_3_dp_estimated_rates", ARRAY_A);
            $est = [];
            foreach ($rate_rows ?: [] as $rr) $est[(int)$rr['product_id']] = (float)$rr['rate'];

            // ── V4: Avg FF milk purchase rate per date+location ──
            $avg_ff = [];
            $avg_q = $db->get_results($db->prepare(
                "SELECT t.transaction_date AS entry_date, t.location_id,
                        ROUND(SUM(tl.qty * tl.rate) / NULLIF(SUM(tl.qty), 0), 2) AS avg_rate
                   FROM wp_mf_4_transactions t
                   JOIN wp_mf_4_transaction_lines tl ON tl.transaction_id = t.id
                  WHERE t.transaction_type = 'purchase'
                    AND tl.product_id = 1 AND tl.qty > 0
                    AND t.transaction_date BETWEEN %s AND %s
                  GROUP BY t.transaction_date, t.location_id", $from, $to), ARRAY_A);
            foreach ($avg_q ?: [] as $aq) {
                $avg_ff[$aq['entry_date'] . '|' . $aq['location_id']] = (float)$aq['avg_rate'];
            }
            $global_avg_ff = $est[1] ?? 0;
            $get_ff_rate = function($date, $lid) use (&$avg_ff, $global_avg_ff) {
                return $avg_ff[$date . '|' . $lid] ?? $global_avg_ff;
            };

            // ── V4: Fetch all processing transactions in date range ──
            $proc_txns = $db->get_results($db->prepare(
                "SELECT t.id, t.transaction_date AS dt, t.location_id AS lid,
                        t.processing_type, t.notes,
                        l.name AS loc_name
                   FROM wp_mf_4_transactions t
                   JOIN wp_mf_3_dp_locations l ON l.id = t.location_id
                  WHERE t.transaction_type = 'processing'
                    AND t.transaction_date BETWEEN %s AND %s $loc_cond $test_cond
                  ORDER BY t.transaction_date DESC, l.name",
                $from, $to), ARRAY_A) ?: [];
            $this->check_db('profit.proc_txns');

            // Batch-fetch all lines for these processing transactions
            $all_proc_lines = [];
            if (!empty($proc_txns)) {
                $proc_ids = array_column($proc_txns, 'id');
                $ph = implode(',', array_fill(0, count($proc_ids), '%d'));
                $plines = $db->get_results($db->prepare(
                    "SELECT transaction_id, product_id, qty FROM wp_mf_4_transaction_lines
                      WHERE transaction_id IN ($ph)",
                    ...$proc_ids), ARRAY_A) ?: [];
                foreach ($plines as $pl) {
                    $all_proc_lines[$pl['transaction_id']][] = $pl;
                }
            }

            // Group processing transactions by date+location+processing_type
            $grouped = []; // "dt|lid|proc_type" => [aggregated data]
            foreach ($proc_txns as $pt) {
                $ptype = $pt['processing_type'] ?? '';
                $key = $pt['dt'] . '|' . $pt['lid'] . '|' . $ptype;
                if (!isset($grouped[$key])) {
                    $grouped[$key] = [
                        'dt' => $pt['dt'], 'lid' => $pt['lid'],
                        'loc_name' => $pt['loc_name'], 'proc_type' => $ptype,
                        'inputs' => [], 'outputs' => [], 'notes' => [],
                    ];
                }
                $lines = $all_proc_lines[$pt['id']] ?? [];
                foreach ($lines as $ln) {
                    $pid = (int)$ln['product_id'];
                    $qty = (float)$ln['qty'];
                    if ($qty < 0) {
                        $grouped[$key]['inputs'][$pid] = ($grouped[$key]['inputs'][$pid] ?? 0) + abs($qty);
                    } else {
                        $grouped[$key]['outputs'][$pid] = ($grouped[$key]['outputs'][$pid] ?? 0) + $qty;
                    }
                }
                if ($pt['notes']) $grouped[$key]['notes'][] = $pt['notes'];
            }

            $rows = [];

            // ── Flow: FF Milk → Skim + Cream (ff_milk_processing) ──
            if (!$flow || $flow === 'ff_milk') {
                foreach ($grouped as $g) {
                    if ($g['proc_type'] !== 'ff_milk_processing') continue;
                    $ff   = $g['inputs'][1] ?? 0;  // product_id=1 consumed
                    $skim = $g['outputs'][2] ?? 0;  // product_id=2 produced
                    $cream = $g['outputs'][3] ?? 0; // product_id=3 produced
                    if ($ff <= 0) continue;
                    $rate = $get_ff_rate($g['dt'], $g['lid']);
                    $cost = round($ff * $rate, 2);
                    $value = $skim * ($est[2] ?? 0) + $cream * ($est[3] ?? 0);
                    $profit = round($value - $cost, 2);
                    $rows[] = [
                        'date' => $g['dt'], 'location_name' => $g['loc_name'],
                        'flow' => 'ff_milk', 'flow_label' => 'FF Milk → Skim+Cream',
                        'inputs'  => 'FF Milk: ' . (int)$ff . ' KG (₹' . $this->d2($rate) . ')',
                        'outputs' => 'Skim: ' . (int)$skim . ' KG (₹' . $this->d2($est[2] ?? 0) . '), Cream: ' . (int)$cream . ' KG (₹' . $this->d2($est[3] ?? 0) . ')',
                        'cost' => $cost, 'value' => round($value, 2),
                        'profit' => $profit,
                        'profit_pct' => $cost > 0 ? round(($profit / $cost) * 100, 1) : 0,
                    ];
                }
            }

            // ── Flow: Cream → Butter + Ghee (cream_processing) ──
            if (!$flow || $flow === 'cream') {
                // V4: Avg cream purchase rate per date+location
                $avg_cr_q = $db->get_results($db->prepare(
                    "SELECT t.transaction_date AS entry_date, t.location_id,
                            ROUND(SUM(tl.qty * tl.rate) / NULLIF(SUM(tl.qty), 0), 2) AS avg_rate
                       FROM wp_mf_4_transactions t
                       JOIN wp_mf_4_transaction_lines tl ON tl.transaction_id = t.id
                      WHERE t.transaction_type = 'purchase'
                        AND tl.product_id = 3 AND tl.qty > 0 AND tl.rate > 0
                        AND t.transaction_date BETWEEN %s AND %s
                      GROUP BY t.transaction_date, t.location_id", $from, $to), ARRAY_A);
                $avg_cr = [];
                foreach ($avg_cr_q ?: [] as $aq) $avg_cr[$aq['entry_date'].'|'.$aq['location_id']] = (float)$aq['avg_rate'];

                foreach ($grouped as $g) {
                    if ($g['proc_type'] !== 'cream_processing') continue;
                    $cr     = $g['inputs'][3] ?? 0;
                    $butter = $g['outputs'][4] ?? 0;
                    $ghee   = $g['outputs'][5] ?? 0;
                    if ($cr <= 0) continue;
                    $rate = $avg_cr[$g['dt'].'|'.$g['lid']] ?? ($est[3] ?? 0);
                    $cost = round($cr * $rate, 2);
                    $value = $butter * ($est[4] ?? 0) + $ghee * ($est[5] ?? 0);
                    $profit = round($value - $cost, 2);
                    $rows[] = [
                        'date' => $g['dt'], 'location_name' => $g['loc_name'],
                        'flow' => 'cream', 'flow_label' => 'Cream → Butter+Ghee',
                        'inputs'  => 'Cream: ' . (int)$cr . ' KG (₹' . $this->d2($rate) . ')',
                        'outputs' => 'Butter: ' . (int)$butter . ' KG (₹' . $this->d2($est[4] ?? 0) . '), Ghee: ' . (int)$ghee . ' KG (₹' . $this->d2($est[5] ?? 0) . ')',
                        'cost' => $cost, 'value' => round($value, 2),
                        'profit' => $profit,
                        'profit_pct' => $cost > 0 ? round(($profit / $cost) * 100, 1) : 0,
                    ];
                }
            }

            // ── Flow: Butter → Ghee (butter_processing) ──
            if (!$flow || $flow === 'butter') {
                // V4: Avg butter purchase rate per date+location
                $avg_bt_q = $db->get_results($db->prepare(
                    "SELECT t.transaction_date AS entry_date, t.location_id,
                            ROUND(SUM(tl.qty * tl.rate) / NULLIF(SUM(tl.qty), 0), 2) AS avg_rate
                       FROM wp_mf_4_transactions t
                       JOIN wp_mf_4_transaction_lines tl ON tl.transaction_id = t.id
                      WHERE t.transaction_type = 'purchase'
                        AND tl.product_id = 4 AND tl.qty > 0 AND tl.rate > 0
                        AND t.transaction_date BETWEEN %s AND %s
                      GROUP BY t.transaction_date, t.location_id", $from, $to), ARRAY_A);
                $avg_bt = [];
                foreach ($avg_bt_q ?: [] as $aq) $avg_bt[$aq['entry_date'].'|'.$aq['location_id']] = (float)$aq['avg_rate'];

                foreach ($grouped as $g) {
                    if ($g['proc_type'] !== 'butter_processing') continue;
                    $bt   = $g['inputs'][4] ?? 0;
                    $ghee = $g['outputs'][5] ?? 0;
                    if ($bt <= 0) continue;
                    $rate = $avg_bt[$g['dt'].'|'.$g['lid']] ?? ($est[4] ?? 0);
                    $cost = round($bt * $rate, 2);
                    $value = $ghee * ($est[5] ?? 0);
                    $profit = round($value - $cost, 2);
                    $rows[] = [
                        'date' => $g['dt'], 'location_name' => $g['loc_name'],
                        'flow' => 'butter', 'flow_label' => 'Butter → Ghee',
                        'inputs'  => 'Butter: ' . (int)$bt . ' KG (₹' . $this->d2($rate) . ')',
                        'outputs' => 'Ghee: ' . (int)$ghee . ' KG (₹' . $this->d2($est[5] ?? 0) . ')',
                        'cost' => $cost, 'value' => round($value, 2),
                        'profit' => $profit,
                        'profit_pct' => $cost > 0 ? round(($profit / $cost) * 100, 1) : 0,
                    ];
                }
            }

            // ── Flow: FF Milk → Cream + Curd (curd_production) ──
            if (!$flow || $flow === 'curd') {
                $matka_rate   = $est[11] ?? 0;
                $smp_rate_est = $est[7]  ?? 0;
                $pro_rate_est = $est[8]  ?? 0;
                $cul_rate_est = $est[9]  ?? 0;
                foreach ($grouped as $g) {
                    if ($g['proc_type'] !== 'curd_production') continue;
                    $ff      = $g['inputs'][1] ?? 0;
                    $smp     = $g['inputs'][7] ?? 0;
                    $protein = $g['inputs'][8] ?? 0;
                    $culture = $g['inputs'][9] ?? 0;
                    $cream   = $g['outputs'][3] ?? 0;
                    $curd    = $g['outputs'][10] ?? 0;
                    $rate    = $get_ff_rate($g['dt'], $g['lid']);
                    $ff_cost    = round($ff * $rate, 2);
                    $matka_cost = round($curd * $matka_rate, 2);
                    $smp_cost   = round($smp * $smp_rate_est, 2);
                    $pro_cost   = round($protein * $pro_rate_est, 2);
                    $cul_cost   = round($culture * $cul_rate_est, 2);
                    $cost  = $ff_cost + $matka_cost + $smp_cost + $pro_cost + $cul_cost;
                    $value = $cream * ($est[3] ?? 0) + $curd * ($est[10] ?? 0);
                    $profit = round($value - $cost, 2);
                    $inputs = 'FF Milk: ' . (int)$ff . ' KG (₹' . $this->d2($rate) . ')';
                    if ($smp > 0)        $inputs .= ', SMP: ' . (int)$smp . ' (₹' . $this->d2($smp_rate_est) . ')';
                    if ($protein > 0)    $inputs .= ', Protein: ' . $this->d2($protein) . ' KG (₹' . $this->d2($pro_rate_est) . ')';
                    if ($culture > 0)    $inputs .= ', Culture: ' . $this->d2($culture) . ' KG (₹' . $this->d2($cul_rate_est) . ')';
                    if ($matka_rate > 0) $inputs .= ', Matka: ' . (int)$curd . ' (₹' . $this->d2($matka_rate) . ')';
                    $rows[] = [
                        'date' => $g['dt'], 'location_name' => $g['loc_name'],
                        'flow' => 'curd', 'flow_label' => 'FF Milk → Cream+Curd',
                        'inputs'  => $inputs,
                        'outputs' => 'Cream: ' . (int)$cream . ' KG (₹' . $this->d2($est[3] ?? 0) . '), Curd: ' . (int)$curd . ' (₹' . $this->d2($est[10] ?? 0) . ')',
                        'cost' => $cost, 'value' => round($value, 2),
                        'profit' => $profit,
                        'profit_pct' => $cost > 0 ? round(($profit / $cost) * 100, 1) : 0,
                    ];
                }
            }

            // Sort all rows by date DESC, then location, then flow
            usort($rows, function($a, $b) {
                $d = strcmp($b['date'], $a['date']);
                if ($d !== 0) return $d;
                $l = strcmp($a['location_name'] ?? '', $b['location_name'] ?? '');
                if ($l !== 0) return $l;
                return strcmp($a['flow'], $b['flow']);
            });

            $flows = [
                ['key' => 'ff_milk',     'label' => 'FF Milk → Skim + Cream'],
                ['key' => 'cream',       'label' => 'Cream → Butter + Ghee'],
                ['key' => 'butter',      'label' => 'Butter → Ghee'],
                ['key' => 'curd',        'label' => 'FF Milk → Cream + Curd'],
                ['key' => 'madhusudan',  'label' => 'FF Milk → Madhusudan'],
            ];

            return $this->ok([
                'from'  => $from,
                'to'    => $to,
                'flows' => $flows,
                'rows'  => $rows,
            ]);
        } catch (\Exception $e) { return $this->exc('get_profitability_report', $e); }
    }

    // ════════════════════════════════════════════════════════════
    // V4 ENDPOINTS
    // ════════════════════════════════════════════════════════════

    /**
     * GET /v4/parties — list parties, optionally filtered by type and location.
     */
    public function get_v4_parties(WP_REST_Request $r): WP_REST_Response {
        try {
            $db = $this->db();
            $where = "WHERE p.is_active = 1";
            $params = [];
            $type = $r->get_param('party_type');
            if ($type) {
                $where .= " AND p.party_type = %s";
                $params[] = $type;
            }
            $loc = $r->get_param('location_id');
            if ($loc && $type === 'vendor') {
                // Filter vendors by location via vendor_location_access (now uses party_id directly)
                $where .= " AND EXISTS (
                    SELECT 1 FROM wp_mf_3_dp_vendor_location_access vl
                    WHERE vl.party_id = p.id AND vl.location_id = %d
                )";
                $params[] = (int)$loc;
            }
            $sql = "SELECT p.id, p.name, p.party_type, p.is_active FROM wp_mf_4_parties p $where ORDER BY p.name";
            if ($params) $sql = $db->prepare($sql, ...$params);
            $rows = $db->get_results($sql, ARRAY_A) ?? [];
            $this->check_db('get_v4_parties');

            // Attach product_ids for customers
            $party_ids = array_column($rows, 'id');
            $cp_map = [];
            if (!empty($party_ids)) {
                $placeholders = implode(',', array_fill(0, count($party_ids), '%d'));
                $cp_sql = $db->prepare(
                    "SELECT party_id, product_id FROM wp_mf_3_dp_customer_products WHERE party_id IN ($placeholders)",
                    ...array_map('intval', $party_ids)
                );
                $cp_rows = $db->get_results($cp_sql, ARRAY_A) ?? [];
                foreach ($cp_rows as $cp) {
                    $cp_map[(int)$cp['party_id']][] = (int)$cp['product_id'];
                }
            }
            foreach ($rows as &$row) {
                $row['product_ids'] = $cp_map[(int)$row['id']] ?? [];
            }
            unset($row);

            return $this->ok($rows);
        } catch (\Exception $e) { return $this->exc('get_v4_parties', $e); }
    }

    /**
     * POST /v4/transaction — unified save for purchase, processing, sale.
     *
     * Payload:
     *   location_id, transaction_date, transaction_type,
     *   processing_type (nullable), party_id,
     *   lines: [{product_id, qty, rate?, snf?, fat?}]
     *   milk_usage: [{party_id, qty}]  (optional, for processing with FF Milk)
     *   inputs: [{product_id, qty, rate?, snf?, fat?}]  (optional, for processing non-milk inputs)
     *   outputs: [{product_id, qty, rate?, snf?, fat?}]  (optional, for processing outputs)
     *   notes: string (optional, JSON for pouch_lines etc.)
     */
    public function save_v4_transaction(WP_REST_Request $r): WP_REST_Response {
        $loc = (int) $r->get_param('location_id');
        if ($e = $this->check_location_access($this->uid(), $loc)) return $e;
        try {
            $db = $this->db();
            $txn_type = $r->get_param('transaction_type');
            if (!in_array($txn_type, ['purchase', 'processing', 'sale'])) {
                return $this->err('Invalid transaction_type.');
            }
            $txn_date = $r->get_param('transaction_date');
            if (!$txn_date) return $this->err('transaction_date required.');

            $proc_type = $r->get_param('processing_type');
            $party_id  = (int) $r->get_param('party_id');
            $notes     = $r->get_param('notes');

            // For processing, default party to Internal (1)
            if ($txn_type === 'processing' && !$party_id) $party_id = 1;
            if (!$party_id) return $this->err('party_id required.');

            // Insert transaction header
            $header = [
                'location_id'      => $loc,
                'transaction_date' => $txn_date,
                'transaction_type' => $txn_type,
                'party_id'         => $party_id,
                'created_by'       => $this->uid(),
            ];
            if ($proc_type)  $header['processing_type'] = $proc_type;
            if ($notes)      $header['notes'] = $notes;

            if ($db->insert('wp_mf_4_transactions', $header) === false) {
                $this->log_db('save_v4_transaction.header', $db->last_error);
                return $this->err('Database error saving transaction.', 500);
            }
            $txn_id = $db->insert_id;

            // ── Insert lines ──
            $line_count = 0;

            // milk_usage → negative FF Milk lines (product_id=1)
            // Auto-assigns source_transaction_id via FIFO from vendor's purchases
            $milk_usage = $r->get_param('milk_usage');
            if (is_array($milk_usage)) {
                foreach ($milk_usage as $mu) {
                    $mu_qty = (float)($mu['qty'] ?? $mu['ff_milk_kg'] ?? 0);
                    if ($mu_qty == 0) continue;
                    $consume_qty = abs($mu_qty);
                    $sign = $mu_qty > 0 ? -1 : 1; // positive input → negative stored (consumed); negative input → positive stored (reversal)

                    // FIFO: find vendor's purchases with remaining stock up to this transaction date
                    $vendor_id = (int)($mu['party_id'] ?? 0);
                    $source_txn_id = null;
                    if ($vendor_id > 0) {
                        $source_txn_id = !empty($mu['source_transaction_id'])
                            ? (int)$mu['source_transaction_id']
                            : $this->fifo_source($db, $loc, $vendor_id, $txn_date);
                    }

                    $line = [
                        'transaction_id' => $txn_id,
                        'product_id'     => 1, // FF Milk
                        'qty'            => $this->d2($sign * $consume_qty),
                    ];
                    if ($source_txn_id) {
                        $line['source_transaction_id'] = $source_txn_id;
                    }
                    $db->insert('wp_mf_4_transaction_lines', $line);
                    $this->check_db('save_v4_transaction.milk_usage_line');
                    $line_count++;
                }
            }

            // inputs → negative qty lines (for processing non-milk inputs)
            $inputs = $r->get_param('inputs');
            if (is_array($inputs)) {
                foreach ($inputs as $inp) {
                    $inp_qty = (float)($inp['qty'] ?? 0);
                    if ($inp_qty == 0) continue;
                    $line = [
                        'transaction_id' => $txn_id,
                        'product_id'     => (int)$inp['product_id'],
                        'qty'            => $this->d2(-$inp_qty), // negative = consumed
                    ];
                    if (isset($inp['rate'])) $line['rate'] = $this->d2($inp['rate']);
                    if (isset($inp['snf']))  $line['snf']  = $this->d1($inp['snf']);
                    if (isset($inp['fat']))  $line['fat']  = $this->d1($inp['fat']);
                    $db->insert('wp_mf_4_transaction_lines', $line);
                    $this->check_db('save_v4_transaction.input_line');
                    $line_count++;
                }
            }

            // outputs → positive qty lines (for processing outputs)
            $outputs = $r->get_param('outputs');
            if (is_array($outputs)) {
                foreach ($outputs as $out) {
                    $out_qty = (float)($out['qty'] ?? 0);
                    if ($out_qty == 0) continue;
                    $line = [
                        'transaction_id' => $txn_id,
                        'product_id'     => (int)$out['product_id'],
                        'qty'            => $this->d2($out_qty), // positive = produced
                    ];
                    if (isset($out['rate'])) $line['rate'] = $this->d2($out['rate']);
                    if (isset($out['snf']))  $line['snf']  = $this->d1($out['snf']);
                    if (isset($out['fat']))  $line['fat']  = $this->d1($out['fat']);
                    $db->insert('wp_mf_4_transaction_lines', $line);
                    $this->check_db('save_v4_transaction.output_line');
                    $line_count++;
                }
            }

            // lines → direct lines (for purchases and sales)
            // Purchase: qty stored as positive. Sale: qty stored as negative.
            $lines = $r->get_param('lines');
            if (is_array($lines)) {
                foreach ($lines as $ln) {
                    $ln_qty = (float)($ln['qty'] ?? 0);
                    if ($ln_qty == 0) continue;
                    $stored_qty = ($txn_type === 'sale') ? -$ln_qty : $ln_qty;
                    $line = [
                        'transaction_id' => $txn_id,
                        'product_id'     => (int)$ln['product_id'],
                        'qty'            => $this->d2($stored_qty),
                    ];
                    if (isset($ln['rate']))  $line['rate'] = $this->d2($ln['rate']);
                    if (isset($ln['snf']))   $line['snf']  = $this->d1($ln['snf']);
                    if (isset($ln['fat']))   $line['fat']  = $this->d1($ln['fat']);
                    if (!empty($ln['source_transaction_id'])) {
                        $line['source_transaction_id'] = (int)$ln['source_transaction_id'];
                    }
                    $db->insert('wp_mf_4_transaction_lines', $line);
                    $this->check_db('save_v4_transaction.line');
                    $line_count++;
                }
            }

            // ── Pouch production → auto-insert aggregated Pouch Milk (product 12) line ──
            if ($proc_type === 'pouch_production' && $notes) {
                $notes_data = is_string($notes) ? json_decode($notes, true) : $notes;
                $pouch_lines_data = $notes_data['pouch_lines'] ?? [];
                $total_crates = 0;
                foreach ($pouch_lines_data as $pl) {
                    $total_crates += (int)($pl['crate_count'] ?? 0);
                }
                if ($total_crates > 0) {
                    $pouch_kg = $total_crates * 12; // 12 litres/KG per crate
                    $db->insert('wp_mf_4_transaction_lines', [
                        'transaction_id' => $txn_id,
                        'product_id'     => 12,
                        'qty'            => $this->d2($pouch_kg),
                    ]);
                    $this->check_db('save_v4_transaction.pouch_milk_line');
                    $this->log("Pouch production: $total_crates crates = {$pouch_kg} KG added as product 12");
                    $line_count++;
                }
            }

            if ($line_count === 0) {
                // Rollback: delete the empty transaction
                $db->delete('wp_mf_4_transactions', ['id' => $txn_id]);
                return $this->err('No valid lines provided.');
            }

            $this->audit('wp_mf_4_transactions', $txn_id, 'INSERT', null, $header);
            return $this->ok(['id' => $txn_id, 'line_count' => $line_count], 201);
        } catch (\Exception $e) { return $this->exc('save_v4_transaction', $e); }
    }

    /**
     * GET /v4/transactions — list transactions with lines.
     * Params: location_id, from, to, transaction_type (optional), processing_type (optional)
     */
    public function get_v4_transactions(WP_REST_Request $r): WP_REST_Response {
        $loc = (int) $r->get_param('location_id');
        if (!$loc) return $this->err('location_id required.');
        if ($e = $this->check_location_access($this->uid(), $loc)) return $e;
        try {
            $db = $this->db();
            $to   = $r->get_param('to') ?? date('Y-m-d');
            $from = $r->get_param('from') ?? date('Y-m-d', strtotime('-6 days', strtotime($to)));
            $txn_type  = $r->get_param('transaction_type');
            $proc_type = $r->get_param('processing_type');

            $where = "WHERE t.location_id = %d AND t.transaction_date BETWEEN %s AND %s";
            $params = [$loc, $from, $to];
            if ($txn_type) {
                $where .= " AND t.transaction_type = %s";
                $params[] = $txn_type;
            }
            if ($proc_type) {
                $where .= " AND t.processing_type = %s";
                $params[] = $proc_type;
            }

            // Fetch transactions with user/location names
            $sql = $db->prepare("
                SELECT t.id, t.location_id, t.transaction_date, t.transaction_type,
                       t.processing_type, t.party_id, t.created_by, t.created_at, t.notes,
                       p.name AS party_name, p.party_type,
                       u.display_name AS user_name,
                       loc.name AS location_name
                FROM wp_mf_4_transactions t
                LEFT JOIN wp_mf_4_parties p ON p.id = t.party_id
                LEFT JOIN wp_users u ON u.ID = t.created_by
                LEFT JOIN wp_mf_3_dp_locations loc ON loc.id = t.location_id
                $where
                ORDER BY t.transaction_date DESC, t.id DESC
            ", ...$params);
            $txns = $db->get_results($sql, ARRAY_A) ?? [];
            $this->check_db('get_v4_transactions.txns');

            if (empty($txns)) return $this->ok(['rows' => []]);

            // Fetch all lines for these transactions
            $txn_ids = array_column($txns, 'id');
            $placeholders = implode(',', array_fill(0, count($txn_ids), '%d'));
            $lines_sql = $db->prepare("
                SELECT l.*, pr.name AS product_name, pr.unit AS product_unit
                FROM wp_mf_4_transaction_lines l
                JOIN wp_mf_3_dp_products pr ON pr.id = l.product_id
                WHERE l.transaction_id IN ($placeholders)
                ORDER BY l.id
            ", ...$txn_ids);
            $all_lines = $db->get_results($lines_sql, ARRAY_A) ?? [];
            $this->check_db('get_v4_transactions.lines');

            // Group lines by transaction_id
            $lines_by_txn = [];
            foreach ($all_lines as $ln) {
                $lines_by_txn[$ln['transaction_id']][] = $ln;
            }

            // Build response rows with V3-compatible type labels
            $rows = [];
            foreach ($txns as $t) {
                $t_lines = $lines_by_txn[$t['id']] ?? [];
                $type_label = $this->v4_type_label($t['transaction_type'], $t['processing_type'], $t_lines);
                $rows[] = [
                    'id'               => $t['id'],
                    'type'             => $type_label,
                    'transaction_type' => $t['transaction_type'],
                    'processing_type'  => $t['processing_type'],
                    'entry_date'       => $t['transaction_date'],
                    'party_name'       => $t['party_name'],
                    'party_type'       => $t['party_type'],
                    'party_id'         => $t['party_id'],
                    'created_at'       => $t['created_at'],
                    'user_name'        => $t['user_name'] ?? '',
                    'location_name'    => $t['location_name'] ?? '',
                    'notes'            => $t['notes'],
                    'lines'            => $t_lines,
                ];
            }
            return $this->ok(['rows' => $rows]);
        } catch (\Exception $e) { return $this->exc('get_v4_transactions', $e); }
    }

    /**
     * Map transaction_type + processing_type + lines to human-readable label.
     */
    private function v4_type_label(string $txn_type, ?string $proc_type, array $lines = []): string {
        if ($txn_type === 'sale') return 'Sale';
        if ($txn_type === 'purchase') {
            $pids = array_unique(array_column($lines, 'product_id'));
            if (in_array('1', $pids))  return 'FF Milk Purchase';
            if (in_array('3', $pids))  return 'Cream Purchase';
            if (in_array('4', $pids))  return 'Butter Purchase';
            if (count(array_intersect($pids, ['7','8','9','11'])) > 0) return 'Ingredient Purchase';
            return 'Purchase';
        }
        return match($proc_type) {
            'ff_milk_processing' => 'FF Milk Processing',
            'cream_processing'   => 'Cream Processing',
            'butter_processing'  => 'Butter Processing',
            'curd_production'    => 'Curd Production',
            'pouch_production'   => 'Pouch Production',
            'madhusudan_sale'    => 'Madhusudan Sale',
            default              => 'Processing',
        };
    }

    /**
     * DELETE /v4/transaction/{id} — delete a transaction and its lines.
     */
    public function delete_v4_transaction(WP_REST_Request $r): WP_REST_Response {
        $id = (int) $r['id'];
        try {
            $db = $this->db();
            $txn = $db->get_row($db->prepare(
                "SELECT * FROM wp_mf_4_transactions WHERE id = %d", $id
            ), ARRAY_A);
            if (!$txn) return $this->err('Transaction not found.', 404);

            if ($e = $this->check_location_access($this->uid(), (int)$txn['location_id'])) return $e;

            $db->delete('wp_mf_4_transaction_lines', ['transaction_id' => $id]);
            $this->check_db('delete_v4_transaction.lines');
            $db->delete('wp_mf_4_transactions', ['id' => $id]);
            $this->check_db('delete_v4_transaction.txn');

            $this->audit('wp_mf_4_transactions', $id, 'DELETE', $txn, null);
            return $this->ok(['deleted' => $id]);
        } catch (\Exception $e) { return $this->exc('delete_v4_transaction', $e); }
    }

    /**
     * GET /v4/stock — stock balances from V4 transaction lines.
     * Params: location_id, from (optional), to (optional)
     * Returns daily breakdown for stock page compatibility.
     */
    public function get_v4_stock(WP_REST_Request $r): WP_REST_Response {
        $loc = (int) $r->get_param('location_id');
        if (!$loc) return $this->err('location_id required.');
        if ($e = $this->check_location_access($this->uid(), $loc)) return $e;
        try {
            $db = $this->db();
            $to   = $r->get_param('to') ?? date('Y-m-d');
            $from = $r->get_param('from') ?? date('Y-m-d', strtotime('-29 days', strtotime($to)));

            // Get all products
            $products = $db->get_results("SELECT id, name, unit FROM wp_mf_3_dp_products WHERE is_active = 1 ORDER BY id", ARRAY_A) ?? [];

            // Get daily movements
            $movements = $db->get_results($db->prepare("
                SELECT t.transaction_date AS dt, l.product_id, SUM(l.qty) AS day_qty
                FROM wp_mf_4_transaction_lines l
                JOIN wp_mf_4_transactions t ON t.id = l.transaction_id
                WHERE t.location_id = %d AND t.transaction_date BETWEEN %s AND %s
                GROUP BY t.transaction_date, l.product_id
                ORDER BY t.transaction_date, l.product_id
            ", $loc, $from, $to), ARRAY_A) ?? [];

            // Build daily movements map
            $daily = []; // date => product_id => qty
            foreach ($movements as $m) {
                $daily[$m['dt']][$m['product_id']] = (float)$m['day_qty'];
            }

            // Build cumulative running balance
            $running = []; // product_id => cumulative balance
            // Get prior balance (before $from)
            $prior = $db->get_results($db->prepare("
                SELECT l.product_id, SUM(l.qty) AS bal
                FROM wp_mf_4_transaction_lines l
                JOIN wp_mf_4_transactions t ON t.id = l.transaction_id
                WHERE t.location_id = %d AND t.transaction_date < %s
                GROUP BY l.product_id
            ", $loc, $from), ARRAY_A) ?? [];
            foreach ($prior as $p) {
                $running[(int)$p['product_id']] = (float)$p['bal'];
            }

            // Build date rows
            $dates = [];
            $current = new \DateTime($from);
            $end     = new \DateTime($to);
            while ($current <= $end) {
                $dt = $current->format('Y-m-d');
                $day_movements = $daily[$dt] ?? [];
                foreach ($day_movements as $pid => $qty) {
                    $running[(int)$pid] = ($running[(int)$pid] ?? 0) + $qty;
                }
                $stocks = [];
                foreach ($running as $pid => $bal) {
                    $stocks[(string)$pid] = (int)round($bal);
                }
                $dates[] = ['date' => $dt, 'stocks' => (object)$stocks];
                $current->modify('+1 day');
            }

            return $this->ok(['products' => $products, 'dates' => $dates]);
        } catch (\Exception $e) { return $this->exc('get_v4_stock', $e); }
    }

    /**
     * GET /v4/stock-flow — Stock report with In / Out / Current per product per day.
     * Params: location_id (required), from, to (optional, default 30 days)
     * Returns: { products: [...], dates: [{ date, flows: { pid: { in, out, current } } }] }
     */
    public function get_v4_stock_flow(WP_REST_Request $r): WP_REST_Response {
        $loc = (int) $r->get_param('location_id');
        if (!$loc) return $this->err('location_id required.');
        if ($e = $this->check_location_access($this->uid(), $loc)) return $e;
        try {
            $db = $this->db();
            $to   = $r->get_param('to') ?? date('Y-m-d');
            $from = $r->get_param('from') ?? date('Y-m-d', strtotime('-29 days', strtotime($to)));

            $products = $db->get_results("SELECT id, name, unit FROM wp_mf_3_dp_products WHERE is_active = 1 ORDER BY sort_order, id", ARRAY_A) ?? [];

            // Daily in (positive qty) and out (negative qty) per product
            $movements = $db->get_results($db->prepare("
                SELECT t.transaction_date AS dt, l.product_id,
                       ROUND(SUM(CASE WHEN l.qty > 0 THEN l.qty ELSE 0 END)) AS day_in,
                       ROUND(SUM(CASE WHEN l.qty < 0 THEN ABS(l.qty) ELSE 0 END)) AS day_out
                FROM wp_mf_4_transaction_lines l
                JOIN wp_mf_4_transactions t ON t.id = l.transaction_id
                WHERE t.location_id = %d AND t.transaction_date BETWEEN %s AND %s
                GROUP BY t.transaction_date, l.product_id
                ORDER BY t.transaction_date, l.product_id
            ", $loc, $from, $to), ARRAY_A) ?? [];

            // Build daily map: date => pid => {in, out}
            $daily = [];
            foreach ($movements as $m) {
                $daily[$m['dt']][(int)$m['product_id']] = [
                    'in'  => (int)$m['day_in'],
                    'out' => (int)$m['day_out'],
                ];
            }

            // Prior balance (before $from) for running cumulative
            $running = [];
            $prior = $db->get_results($db->prepare("
                SELECT l.product_id, SUM(l.qty) AS bal
                FROM wp_mf_4_transaction_lines l
                JOIN wp_mf_4_transactions t ON t.id = l.transaction_id
                WHERE t.location_id = %d AND t.transaction_date < %s
                GROUP BY l.product_id
            ", $loc, $from), ARRAY_A) ?? [];
            foreach ($prior as $p) {
                $running[(int)$p['product_id']] = (float)$p['bal'];
            }

            // Build date rows
            $dates = [];
            $current = new \DateTime($from);
            $end     = new \DateTime($to);
            while ($current <= $end) {
                $dt = $current->format('Y-m-d');
                $day_data = $daily[$dt] ?? [];
                $flows = [];
                // Update running balance with today's net movement
                foreach ($day_data as $pid => $vals) {
                    $running[$pid] = ($running[$pid] ?? 0) + $vals['in'] - $vals['out'];
                }
                // Build flows for all products that have any balance
                foreach ($running as $pid => $bal) {
                    $d = $day_data[$pid] ?? ['in' => 0, 'out' => 0];
                    $flows[(string)$pid] = [
                        'in'      => $d['in'],
                        'out'     => $d['out'],
                        'current' => (int)round($bal),
                    ];
                }
                $dates[] = ['date' => $dt, 'flows' => (object)$flows];
                $current->modify('+1 day');
            }

            return $this->ok(['products' => $products, 'dates' => $dates]);
        } catch (\Exception $e) { return $this->exc('get_v4_stock_flow', $e); }
    }

    /**
     * GET /v4/milk-availability — available FF Milk per vendor from V4 purchases.
     * Params: location_id, as_of (date)
     * Returns: [{party_id, party_name, available_kg}]
     */
    public function get_v4_milk_availability(WP_REST_Request $r): WP_REST_Response {
        $loc = (int) $r->get_param('location_id');
        if (!$loc) return $this->err('location_id required.');
        if ($e = $this->check_location_access($this->uid(), $loc)) return $e;
        try {
            $db = $this->db();
            $as_of = $r->get_param('as_of') ?? date('Y-m-d');

            // Per vendor: purchased FF Milk minus consumed (linked via source_transaction_id)
            // Each purchase transaction has remaining = purchased_qty - SUM(linked consumption)
            $rows_raw = $db->get_results($db->prepare("
                SELECT t.party_id,
                       p.name AS party_name,
                       SUM(l.qty) AS total_purchased,
                       COALESCE((
                           SELECT SUM(ABS(cl.qty))
                           FROM wp_mf_4_transaction_lines cl
                           JOIN wp_mf_4_transactions ct ON ct.id = cl.transaction_id
                           WHERE cl.source_transaction_id IN (
                               SELECT t2.id FROM wp_mf_4_transactions t2
                               JOIN wp_mf_4_transaction_lines l2 ON l2.transaction_id = t2.id
                               WHERE t2.location_id = %d
                                 AND t2.party_id = t.party_id
                                 AND t2.transaction_type = 'purchase'
                                 AND t2.transaction_date <= %s
                                 AND l2.product_id = 1 AND l2.qty > 0
                           )
                           AND cl.product_id = 1
                           AND cl.qty < 0
                           AND ct.transaction_date <= %s
                       ), 0) AS total_consumed
                FROM wp_mf_4_transaction_lines l
                JOIN wp_mf_4_transactions t ON t.id = l.transaction_id
                JOIN wp_mf_4_parties p ON p.id = t.party_id
                WHERE t.location_id = %d
                  AND t.transaction_type = 'purchase'
                  AND t.transaction_date <= %s
                  AND l.product_id = 1
                  AND l.qty > 0
                GROUP BY t.party_id
            ", $loc, $as_of, $as_of, $loc, $as_of), ARRAY_A) ?? [];

            // Also account for unlinked consumption (source_transaction_id IS NULL)
            $unlinked = (float) $db->get_var($db->prepare("
                SELECT COALESCE(SUM(ABS(l.qty)), 0)
                FROM wp_mf_4_transaction_lines l
                JOIN wp_mf_4_transactions t ON t.id = l.transaction_id
                WHERE t.location_id = %d
                  AND t.transaction_date <= %s
                  AND l.product_id = 1
                  AND l.qty < 0
                  AND l.source_transaction_id IS NULL
            ", $loc, $as_of));

            // Build result: available = purchased - linked_consumed
            // Then subtract unlinked consumption FIFO from vendors with oldest purchases
            $rows = [];
            foreach ($rows_raw as $p) {
                $avail = (float)$p['total_purchased'] - (float)$p['total_consumed'];
                $rows[] = [
                    'party_id'     => $p['party_id'],
                    'party_name'   => $p['party_name'],
                    'available_kg' => max(0, (int)round($avail)),
                    'purchased_kg' => (int)round((float)$p['total_purchased']),
                    'consumed_kg'  => (int)round((float)$p['total_consumed']),
                ];
            }

            // Subtract unlinked consumption FIFO (oldest vendor first)
            // Sort by purchased date isn't available per-vendor here, so sort by party_id (stable)
            if ($unlinked > 0) {
                for ($i = 0; $i < count($rows) && $unlinked > 0; $i++) {
                    $deduct = min($unlinked, $rows[$i]['available_kg']);
                    $rows[$i]['available_kg'] -= (int)round($deduct);
                    $rows[$i]['consumed_kg']  += (int)round($deduct);
                    $unlinked -= $deduct;
                }
            }

            // Only return vendors with available > 0
            $rows = array_values(array_filter($rows, fn($r) => $r['available_kg'] > 0));
            return $this->ok($rows);
        } catch (\Exception $e) { return $this->exc('get_v4_milk_availability', $e); }
    }

    // ════════════════════════════════════════════════════
    // V4 DELIVERY CHALLANS
    // ════════════════════════════════════════════════════

    /**
     * GET /v4/challans — List challans for a location.
     * Params: location_id (required), status (pending|invoiced|all, default all), from, to
     */
    public function get_v4_challans(WP_REST_Request $r): WP_REST_Response {
        $loc = (int) $r->get_param('location_id');
        if (!$loc) return $this->err('location_id required.');
        if ($e = $this->check_location_access($this->uid(), $loc)) return $e;
        try {
            $db     = $this->db();
            $status = $r->get_param('status') ?? 'all';
            $to     = $r->get_param('to')   ?? date('Y-m-d');
            $from   = $r->get_param('from') ?? date('Y-m-d', strtotime('-29 days', strtotime($to)));

            $where = $db->prepare("c.location_id = %d AND c.challan_date BETWEEN %s AND %s", $loc, $from, $to);
            if ($status === 'pending')  $where .= " AND c.status = 'pending'";
            if ($status === 'invoiced') $where .= " AND c.status = 'invoiced'";

            $challans = $db->get_results("
                SELECT c.*, p.name AS party_name
                  FROM wp_mf_4_challans c
                  JOIN wp_mf_4_parties p ON p.id = c.party_id
                 WHERE $where
                 ORDER BY c.challan_date DESC, c.id DESC
            ", ARRAY_A) ?? [];

            if (!empty($challans)) {
                $ids = array_column($challans, 'id');
                $id_list = implode(',', array_map('intval', $ids));
                // Fetch lines: LEFT JOIN both product tables (one will be NULL per row)
                $lines = $db->get_results("
                    SELECT cl.*,
                           COALESCE(pr.name, pp.name) AS product_name,
                           COALESCE(pr.unit, 'crates') AS product_unit
                      FROM wp_mf_4_challan_lines cl
                      LEFT JOIN wp_mf_3_dp_products pr ON pr.id = cl.product_id
                      LEFT JOIN wp_mf_3_dp_pouch_products pp ON pp.id = cl.pouch_product_id
                     WHERE cl.challan_id IN ($id_list)
                     ORDER BY cl.id
                ", ARRAY_A) ?? [];

                $lines_by_challan = [];
                foreach ($lines as $l) {
                    $lines_by_challan[(int)$l['challan_id']][] = $l;
                }
                foreach ($challans as &$ch) {
                    $ch['lines'] = $lines_by_challan[(int)$ch['id']] ?? [];
                }
                unset($ch);
            }

            // Customers for the dropdown — enrich with product_ids (V6: direct join on party_id)
            $customers = $db->get_results("
                SELECT id, name FROM wp_mf_4_parties
                 WHERE party_type = 'customer' AND is_active = 1
                 ORDER BY name
            ", ARRAY_A) ?? [];
            $all_cp = $db->get_results("SELECT party_id, product_id FROM wp_mf_3_dp_customer_products", ARRAY_A) ?? [];
            $cp_map = [];
            foreach ($all_cp as $row) { $cp_map[(int)$row['party_id']][] = (int)$row['product_id']; }
            foreach ($customers as &$cust) {
                $cust['product_ids'] = $cp_map[(int)$cust['id']] ?? [];
            }
            unset($cust);

            // Products for the line item picker (bulk products only)
            $products = $db->get_results("
                SELECT id, name, unit FROM wp_mf_3_dp_products
                 WHERE is_active = 1
                 ORDER BY sort_order, id
            ", ARRAY_A) ?? [];

            // Pouch products for the pouch line picker
            $pouch_products = $db->get_results("
                SELECT id, name, pouches_per_crate, crate_rate FROM wp_mf_3_dp_pouch_products
                 WHERE is_active = 1
                 ORDER BY name
            ", ARRAY_A) ?? [];

            // Per-customer pouch rate overrides (small table, return all)
            $customer_pouch_rates = $db->get_results("
                SELECT party_id, pouch_product_id, crate_rate
                  FROM wp_mf_3_dp_customer_pouch_rates
            ", ARRAY_A) ?? [];

            return $this->ok([
                'challans'              => $challans,
                'customers'             => $customers,
                'products'              => $products,
                'pouch_products'        => $pouch_products,
                'customer_pouch_rates'  => $customer_pouch_rates,
            ]);
        } catch (\Exception $e) { return $this->exc('get_v4_challans', $e); }
    }

    /**
     * POST /v4/challan — Create a new delivery challan.
     * Body: { location_id, party_id, challan_date, delivery_address?, notes?, lines: [{product_id, qty, rate}] }
     */
    public function save_v4_challan(WP_REST_Request $r): WP_REST_Response {
        $loc      = (int) $r->get_param('location_id');
        $party_id = (int) $r->get_param('party_id');
        $date     = trim($r->get_param('challan_date') ?? '');
        $address  = trim($r->get_param('delivery_address') ?? '');
        $billing_snap  = trim($r->get_param('billing_address_snapshot') ?? '');
        $shipping_snap = trim($r->get_param('shipping_address_snapshot') ?? '');
        $notes    = trim($r->get_param('notes') ?? '');
        $lines    = $r->get_param('lines');

        if (!$loc)      return $this->err('location_id required.');
        if (!$party_id) return $this->err('Customer is required.');
        if (!$date)     return $this->err('Date is required.');
        if (empty($lines) || !is_array($lines)) return $this->err('At least one line item is required.');
        if ($e = $this->check_location_access($this->uid(), $loc)) return $e;

        try {
            $db = $this->db();

            // Validate customer
            $cust = $db->get_var($db->prepare(
                "SELECT id FROM wp_mf_4_parties WHERE id = %d AND party_type = 'customer'", $party_id));
            if (!$cust) return $this->err('Invalid customer.');

            // Auto-generate challan number
            $next_num = (int) $db->get_var($db->prepare(
                "SELECT COALESCE(MAX(challan_number), 0) + 1 FROM wp_mf_4_challans WHERE location_id = %d", $loc));

            $header = [
                'location_id'              => $loc,
                'party_id'                 => $party_id,
                'challan_number'           => $next_num,
                'challan_date'             => $date,
                'delivery_address'         => $address ?: null,
                'billing_address_snapshot'  => $billing_snap ?: null,
                'shipping_address_snapshot' => $shipping_snap ?: null,
                'notes'                    => $notes ?: null,
                'status'                   => 'pending',
                'created_by'               => $this->uid(),
            ];

            if ($db->insert('wp_mf_4_challans', $header) === false) {
                $this->log_db('save_v4_challan', $db->last_error);
                return $this->err('Database error.', 500);
            }
            $challan_id = (int) $db->insert_id;

            // Insert lines — each line has either product_id (bulk) or pouch_product_id (pouch)
            foreach ($lines as $ln) {
                $qty    = (float) ($ln['qty'] ?? 0);
                $rate   = (float) ($ln['rate'] ?? 0);
                $amount = round($qty * $rate, 2);
                if ($qty <= 0) continue;

                $line_data = [
                    'challan_id' => $challan_id,
                    'qty'        => $this->d2($qty),
                    'rate'       => $this->d2($rate),
                    'amount'     => $this->d2($amount),
                ];
                if (!empty($ln['pouch_product_id'])) {
                    $line_data['pouch_product_id'] = (int) $ln['pouch_product_id'];
                    $line_data['product_id']       = null;
                } else {
                    $line_data['product_id']       = (int) ($ln['product_id'] ?? 0);
                    $line_data['pouch_product_id'] = null;
                }
                $db->insert('wp_mf_4_challan_lines', $line_data);
                $this->check_db('save_v4_challan.line');
            }

            $this->audit('wp_mf_4_challans', $challan_id, 'INSERT', null, $header);
            return $this->ok(['id' => $challan_id, 'challan_number' => $next_num], 201);
        } catch (\Exception $e) { return $this->exc('save_v4_challan', $e); }
    }

    /**
     * DELETE /v4/challan/{id} — Delete a pending challan (lines cascade).
     */
    public function delete_v4_challan(WP_REST_Request $r): WP_REST_Response {
        $id = (int) $r['id'];
        try {
            $db = $this->db();
            $ch = $db->get_row($db->prepare("SELECT * FROM wp_mf_4_challans WHERE id = %d", $id), ARRAY_A);
            if (!$ch) return $this->err('Challan not found.', 404);
            if ($ch['status'] !== 'pending') return $this->err('Cannot delete an invoiced challan.');
            if ($e = $this->check_location_access($this->uid(), (int)$ch['location_id'])) return $e;

            $db->delete('wp_mf_4_challans', ['id' => $id]);
            $this->check_db('delete_v4_challan');
            $this->audit('wp_mf_4_challans', $id, 'DELETE', $ch, null);
            return $this->ok(['deleted' => true]);
        } catch (\Exception $e) { return $this->exc('delete_v4_challan', $e); }
    }

    // ════════════════════════════════════════════════════
    // V4 INVOICES
    // ════════════════════════════════════════════════════

    /**
     * GET /v4/invoices — List invoices for a location.
     * Params: location_id (required), payment_status (unpaid|paid|all, default all)
     */
    public function get_v4_invoices(WP_REST_Request $r): WP_REST_Response {
        $loc = (int) $r->get_param('location_id');
        if (!$loc) return $this->err('location_id required.');
        if ($e = $this->check_location_access($this->uid(), $loc)) return $e;
        try {
            $db     = $this->db();
            $status = $r->get_param('payment_status') ?? 'all';

            $where = $db->prepare("i.location_id = %d", $loc);
            if ($status === 'unpaid') $where .= " AND i.payment_status = 'unpaid'";
            if ($status === 'paid')   $where .= " AND i.payment_status = 'paid'";

            $invoices = $db->get_results("
                SELECT i.*, p.name AS party_name
                  FROM wp_mf_4_invoices i
                  JOIN wp_mf_4_parties p ON p.id = i.party_id
                 WHERE $where
                 ORDER BY i.invoice_date DESC, i.id DESC
            ", ARRAY_A) ?? [];

            // Attach challans for each invoice
            if (!empty($invoices)) {
                $inv_ids = array_column($invoices, 'id');
                $id_list = implode(',', array_map('intval', $inv_ids));
                $challans = $db->get_results("
                    SELECT c.id, c.challan_number, c.challan_date, c.invoice_id,
                           p.name AS party_name
                      FROM wp_mf_4_challans c
                      JOIN wp_mf_4_parties p ON p.id = c.party_id
                     WHERE c.invoice_id IN ($id_list)
                     ORDER BY c.challan_date, c.id
                ", ARRAY_A) ?? [];

                $ch_by_inv = [];
                foreach ($challans as $ch) {
                    $ch_by_inv[(int)$ch['invoice_id']][] = $ch;
                }

                // Also get consolidated line items per invoice (bulk + pouch)
                $lines = $db->get_results("
                    SELECT c.invoice_id,
                           cl.product_id, cl.pouch_product_id,
                           COALESCE(pr.name, pp.name) AS product_name,
                           COALESCE(pr.unit, 'crates') AS product_unit,
                           SUM(cl.qty) AS total_qty,
                           ROUND(SUM(cl.amount) / SUM(cl.qty), 2) AS avg_rate,
                           SUM(cl.amount) AS total_amount
                      FROM wp_mf_4_challan_lines cl
                      JOIN wp_mf_4_challans c ON c.id = cl.challan_id
                      LEFT JOIN wp_mf_3_dp_products pr ON pr.id = cl.product_id
                      LEFT JOIN wp_mf_3_dp_pouch_products pp ON pp.id = cl.pouch_product_id
                     WHERE c.invoice_id IN ($id_list)
                     GROUP BY c.invoice_id, cl.product_id, cl.pouch_product_id
                     ORDER BY cl.product_id, cl.pouch_product_id
                ", ARRAY_A) ?? [];

                $lines_by_inv = [];
                foreach ($lines as $l) {
                    $lines_by_inv[(int)$l['invoice_id']][] = $l;
                }

                foreach ($invoices as &$inv) {
                    $inv['challans'] = $ch_by_inv[(int)$inv['id']] ?? [];
                    $inv['lines']    = $lines_by_inv[(int)$inv['id']] ?? [];
                }
                unset($inv);
            }

            // Customers for dropdown
            $customers = $db->get_results("
                SELECT id, name FROM wp_mf_4_parties
                 WHERE party_type = 'customer' AND is_active = 1
                 ORDER BY name
            ", ARRAY_A) ?? [];

            return $this->ok([
                'invoices'  => $invoices,
                'customers' => $customers,
            ]);
        } catch (\Exception $e) { return $this->exc('get_v4_invoices', $e); }
    }

    /**
     * POST /v4/invoice — Create invoice from selected pending challans.
     * Body: { location_id, party_id, invoice_date, challan_ids: [1,2,...], notes? }
     */
    public function save_v4_invoice(WP_REST_Request $r): WP_REST_Response {
        $loc         = (int) $r->get_param('location_id');
        $party_id    = (int) $r->get_param('party_id');
        $date        = trim($r->get_param('invoice_date') ?? '');
        $challan_ids = $r->get_param('challan_ids');
        $notes       = trim($r->get_param('notes') ?? '');

        if (!$loc)      return $this->err('location_id required.');
        if (!$party_id) return $this->err('Customer is required.');
        if (!$date)     return $this->err('Date is required.');
        if (empty($challan_ids) || !is_array($challan_ids)) return $this->err('Select at least one challan.');
        if ($e = $this->check_location_access($this->uid(), $loc)) return $e;

        try {
            $db = $this->db();

            // Validate all challans: must be pending, same location, same customer
            $id_list = implode(',', array_map('intval', $challan_ids));
            $challans = $db->get_results("
                SELECT id, party_id, location_id, status
                  FROM wp_mf_4_challans
                 WHERE id IN ($id_list)
            ", ARRAY_A) ?? [];

            if (count($challans) !== count($challan_ids)) return $this->err('Some challans not found.');
            foreach ($challans as $ch) {
                if ($ch['status'] !== 'pending') return $this->err("Challan #{$ch['id']} is already invoiced.");
                if ((int)$ch['location_id'] !== $loc) return $this->err("Challan #{$ch['id']} belongs to a different location.");
                if ((int)$ch['party_id'] !== $party_id) return $this->err("Challan #{$ch['id']} belongs to a different customer.");
            }

            // Calculate totals from challan lines
            $subtotal = (float) $db->get_var("
                SELECT COALESCE(SUM(cl.amount), 0)
                  FROM wp_mf_4_challan_lines cl
                 WHERE cl.challan_id IN ($id_list)
            ");

            // Snapshot customer addresses at invoice creation time
            $billing_snap = '';
            $shipping_snap = '';
            $addrs = $db->get_results($db->prepare(
                "SELECT address_type, address_text, is_default FROM wp_mf_3_dp_party_addresses
                  WHERE party_id = %d AND is_active = 1
                  ORDER BY is_default DESC, id ASC", $party_id), ARRAY_A) ?? [];
            foreach ($addrs as $a) {
                if ($a['address_type'] === 'billing' && !$billing_snap) {
                    $billing_snap = $a['address_text'];
                }
                if ($a['address_type'] === 'shipping' && !$shipping_snap) {
                    $shipping_snap = $a['address_text'];
                }
            }

            // Auto-generate invoice number
            $next_num = (int) $db->get_var($db->prepare(
                "SELECT COALESCE(MAX(invoice_number), 0) + 1 FROM wp_mf_4_invoices WHERE location_id = %d", $loc));

            $header = [
                'location_id'              => $loc,
                'party_id'                 => $party_id,
                'invoice_number'           => $next_num,
                'invoice_date'             => $date,
                'subtotal'                 => $this->d2($subtotal),
                'tax'                      => $this->d2(0),
                'total'                    => $this->d2($subtotal),
                'payment_status'           => 'unpaid',
                'notes'                    => $notes ?: null,
                'billing_address_snapshot'  => $billing_snap ?: null,
                'shipping_address_snapshot' => $shipping_snap ?: null,
                'created_by'               => $this->uid(),
            ];

            if ($db->insert('wp_mf_4_invoices', $header) === false) {
                $this->log_db('save_v4_invoice', $db->last_error);
                return $this->err('Database error.', 500);
            }
            $invoice_id = (int) $db->insert_id;

            // Update challans: set status=invoiced, invoice_id
            $db->query("
                UPDATE wp_mf_4_challans
                   SET status = 'invoiced', invoice_id = $invoice_id
                 WHERE id IN ($id_list)
            ");
            $this->check_db('save_v4_invoice.update_challans');

            // ── Auto-create sale transaction for aggregated pouch milk ──
            $pouch_crates = (float) $db->get_var("
                SELECT COALESCE(SUM(cl.qty), 0)
                  FROM wp_mf_4_challan_lines cl
                 WHERE cl.challan_id IN ($id_list) AND cl.pouch_product_id IS NOT NULL
            ");
            if ($pouch_crates > 0) {
                $pouch_kg = $pouch_crates * 12; // 12 litres/KG per crate
                $sale_header = [
                    'location_id'      => $loc,
                    'transaction_date' => $date,
                    'transaction_type' => 'sale',
                    'party_id'         => $party_id,
                    'created_by'       => $this->uid(),
                    'notes'            => json_encode(['invoice_id' => $invoice_id]),
                ];
                if ($db->insert('wp_mf_4_transactions', $sale_header) === false) {
                    $this->log_db('save_v4_invoice.pouch_sale_txn', $db->last_error);
                } else {
                    $sale_txn_id = (int) $db->insert_id;
                    $db->insert('wp_mf_4_transaction_lines', [
                        'transaction_id' => $sale_txn_id,
                        'product_id'     => 12,
                        'qty'            => $this->d2(-$pouch_kg), // negative = outward/sold
                    ]);
                    $this->check_db('save_v4_invoice.pouch_sale_line');
                    $this->log("Invoice $invoice_id: pouch sale txn $sale_txn_id — $pouch_crates crates = {$pouch_kg} KG out");
                }
            }

            $this->audit('wp_mf_4_invoices', $invoice_id, 'INSERT', null, $header);
            return $this->ok(['id' => $invoice_id, 'invoice_number' => $next_num], 201);
        } catch (\Exception $e) { return $this->exc('save_v4_invoice', $e); }
    }

    /**
     * DELETE /v4/invoice/{id} — Delete an invoice, revert challans to pending.
     */
    public function delete_v4_invoice(WP_REST_Request $r): WP_REST_Response {
        $id = (int) $r['id'];
        try {
            $db = $this->db();
            $inv = $db->get_row($db->prepare("SELECT * FROM wp_mf_4_invoices WHERE id = %d", $id), ARRAY_A);
            if (!$inv) return $this->err('Invoice not found.', 404);
            if ($e = $this->check_location_access($this->uid(), (int)$inv['location_id'])) return $e;

            // Revert challans to pending
            $db->query($db->prepare("
                UPDATE wp_mf_4_challans
                   SET status = 'pending', invoice_id = NULL
                 WHERE invoice_id = %d
            ", $id));
            $this->check_db('delete_v4_invoice.revert_challans');

            // Delete auto-created pouch sale transaction (notes contains invoice_id)
            $sale_txns = $db->get_col($db->prepare("
                SELECT id FROM wp_mf_4_transactions
                 WHERE transaction_type = 'sale' AND notes LIKE %s
            ", '%"invoice_id":' . $id . '%'));
            foreach ($sale_txns as $stid) {
                $db->delete('wp_mf_4_transaction_lines', ['transaction_id' => (int)$stid]);
                $db->delete('wp_mf_4_transactions', ['id' => (int)$stid]);
                $this->log("Deleted pouch sale txn $stid for invoice $id");
            }

            // Delete invoice
            $db->delete('wp_mf_4_invoices', ['id' => $id]);
            $this->check_db('delete_v4_invoice');
            $this->audit('wp_mf_4_invoices', $id, 'DELETE', $inv, null);
            return $this->ok(['deleted' => true]);
        } catch (\Exception $e) { return $this->exc('delete_v4_invoice', $e); }
    }

    /**
     * POST /v4/invoice/{id}/pay — Mark invoice as paid/unpaid toggle.
     */
    public function mark_invoice_paid(WP_REST_Request $r): WP_REST_Response {
        $id = (int) $r['id'];
        try {
            $db = $this->db();
            $inv = $db->get_row($db->prepare("SELECT * FROM wp_mf_4_invoices WHERE id = %d", $id), ARRAY_A);
            if (!$inv) return $this->err('Invoice not found.', 404);
            if ($e = $this->check_location_access($this->uid(), (int)$inv['location_id'])) return $e;

            $new_status = $inv['payment_status'] === 'paid' ? 'unpaid' : 'paid';
            $db->update('wp_mf_4_invoices', ['payment_status' => $new_status], ['id' => $id]);
            $this->check_db('mark_invoice_paid');
            $this->audit('wp_mf_4_invoices', $id, 'UPDATE', $inv, ['payment_status' => $new_status]);
            return $this->ok(['payment_status' => $new_status]);
        } catch (\Exception $e) { return $this->exc('mark_invoice_paid', $e); }
    }

    // ════════════════════════════════════════════════════
    // COMPANY SETTINGS
    // ════════════════════════════════════════════════════

    public function get_company_settings(WP_REST_Request $r): WP_REST_Response {
        return $this->ok([
            'company_name'    => get_option('dairy_company_name', ''),
            'company_address' => get_option('dairy_company_address', ''),
            'company_phone'   => get_option('dairy_company_phone', ''),
            'company_email'   => get_option('dairy_company_email', ''),
            'company_website' => get_option('dairy_company_website', ''),
            'company_gstin'   => get_option('dairy_company_gstin', ''),
            'company_signatory' => get_option('dairy_company_signatory', ''),
        ]);
    }

    public function save_company_settings(WP_REST_Request $r): WP_REST_Response {
        // Finance-only
        $uid = $this->uid();
        $db = $this->db();
        $flag = $db->get_var($db->prepare(
            "SELECT can_finance FROM wp_mf_3_dp_user_flags WHERE user_id = %d", $uid));
        if (!$flag) return $this->err('Finance access required.', 403);

        $fields = ['company_name', 'company_address', 'company_phone',
                   'company_email', 'company_website', 'company_gstin', 'company_signatory'];
        foreach ($fields as $f) {
            $val = $r->get_param($f);
            if ($val !== null) {
                update_option('dairy_' . $f, trim($val));
            }
        }
        $this->log("Company settings updated by user $uid");
        return $this->ok(['saved' => true]);
    }

    /**
     * FIFO: find the oldest purchase transaction from a vendor that still has remaining stock.
     * Returns the transaction ID, or null if none found.
     */
    private function fifo_source($db, int $loc, int $vendor_id, string $as_of): ?int {
        // Get all FF Milk purchases from this vendor at this location up to as_of,
        // with remaining = purchased - consumed (via source_transaction_id links)
        $rows = $db->get_results($db->prepare("
            SELECT t.id AS txn_id,
                   l.qty AS purchased,
                   COALESCE((
                       SELECT SUM(ABS(cl.qty))
                       FROM wp_mf_4_transaction_lines cl
                       WHERE cl.source_transaction_id = t.id
                         AND cl.product_id = 1
                         AND cl.qty < 0
                   ), 0) AS consumed
            FROM wp_mf_4_transactions t
            JOIN wp_mf_4_transaction_lines l ON l.transaction_id = t.id
            WHERE t.location_id = %d
              AND t.party_id = %d
              AND t.transaction_type = 'purchase'
              AND t.transaction_date <= %s
              AND l.product_id = 1
              AND l.qty > 0
            ORDER BY t.transaction_date ASC, t.id ASC
        ", $loc, $vendor_id, $as_of), ARRAY_A) ?? [];

        foreach ($rows as $r) {
            $remaining = (float)$r['purchased'] - (float)$r['consumed'];
            if ($remaining > 0) return (int)$r['txn_id'];
        }
        return null;
    }

    private function d1($v): string { return number_format((float)$v, 1, '.', ''); }
    private function d2($v): string { return number_format((float)$v, 2, '.', ''); }

    private function ok( $data, int $status = 200 ): WP_REST_Response {
        return new WP_REST_Response(['success' => true,  'data'    => $data], $status);
    }
    private function err( string $msg, int $status = 400 ): WP_REST_Response {
        $this->log("error ($status): $msg");
        return new WP_REST_Response(['success' => false, 'message' => $msg], $status);
    }
}

new Dairy_Production_API();