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
        'wp_mf_3_dp_milk_cream_production' => 'Milk & Cream Production',
        'wp_mf_3_dp_cream_butter_ghee'     => 'Cream > Butter & Ghee',
        'wp_mf_3_dp_butter_ghee'           => 'Butter > Ghee',
        'wp_mf_3_dp_dahi_production'       => 'Dahi Production',
        'wp_mf_3_dp_sales'                 => 'Sales',
        'wp_mf_3_dp_estimated_rates'       => 'Estimated Rates',
        'wp_mf_3_dp_vendor_payments'       => 'Vendor Payments',
        'wp_mf_3_dp_milk_usage'            => 'Milk Usage',
        'wp_mf_3_dp_pouch_types'           => 'Pouch Types',
        'wp_mf_3_dp_pouch_production'      => 'Pouch Production',
        'wp_mf_3_dp_pouch_production_lines'=> 'Pouch Production Lines',
        'wp_mf_3_dp_pouch_rates'           => 'Pouch Rates',
        'wp_mf_3_dp_madhusudan_sale'       => 'Madhusudan Sale',
        'wp_mf_3_dp_curd_production'       => 'Curd Production',
        'wp_mf_3_dp_production_flows'      => 'Production Flows',
    ];

    // Pages every logged-in user with at least one location can see
    const PAGES_BASE = ['production', 'sales', 'reports'];

    // Pages requiring can_finance = true
    const PAGES_FINANCE = ['stock_valuation', 'audit_log', 'vendor_ledger', 'funds_report', 'admin'];

    // Pages requiring can_anomaly = true
    const PAGES_ANOMALY = ['anomalies'];

    public function __construct() {
        add_action('rest_api_init', [ $this, 'register_routes' ]);
        add_action('init',           [ $this, 'ensure_dahi_product' ]);
        add_action('admin_menu',    [ $this, 'register_admin_menu' ]);
        add_action('admin_post_dairy_save_permissions',
                   [ $this, 'handle_save_permissions' ]);
        add_action('admin_post_dairy_save_vendor_locations',
                   [ $this, 'handle_save_vendor_locations' ]);
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
                  ORDER BY name",
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

    public function ensure_dahi_product(): void {
        // Also ensure ingredient products exist
        $this->db()->query("
            CREATE TABLE IF NOT EXISTS wp_mf_3_dp_ingredient_purchase (
                id           INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
                location_id  INT UNSIGNED NOT NULL,
                entry_date   DATE NOT NULL,
                product_id   TINYINT UNSIGNED NOT NULL COMMENT '7=SMP,8=Protein,9=Culture',
                quantity     DECIMAL(10,2) NOT NULL DEFAULT 0,
                rate         DECIMAL(10,2) NOT NULL DEFAULT 0,
                created_by   BIGINT UNSIGNED,
                created_at   TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
        ");
        $col_exists = $this->db()->get_var("
            SELECT COUNT(*) FROM information_schema.COLUMNS
            WHERE TABLE_SCHEMA = DATABASE()
              AND TABLE_NAME   = 'wp_mf_3_dp_ingredient_purchase'
              AND COLUMN_NAME  = 'rate'");
        if (!$col_exists) {
            $this->db()->query("ALTER TABLE wp_mf_3_dp_ingredient_purchase
                ADD COLUMN rate DECIMAL(10,2) NOT NULL DEFAULT 0");
            $this->check_db('ensure_dahi_product.add_rate_col');
        }
        $rows = [
            [7, 'SMP',     'Bags', 7],
            [8, 'Protein', 'KG',   8],
            [9, 'Culture', 'KG',   9],
        ];
        foreach ($rows as [$id, $name, $unit, $sort]) {
            $this->db()->query("INSERT INTO wp_mf_3_dp_products (id, name, unit, sort_order, is_active)
                VALUES ($id, '$name', '$unit', $sort, 1)
                ON DUPLICATE KEY UPDATE name='$name', unit='$unit', is_active=1");
        }

        $db = $this->db();
        $db->query("INSERT INTO wp_mf_3_dp_products (id, name, unit, sort_order, is_active)
                    VALUES (6, 'Dahi', 'pcs', 6, 1)
                    ON DUPLICATE KEY UPDATE name='Dahi', unit='pcs', is_active=1");
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

        // Create vendor_payments table
        $db->query("
            CREATE TABLE IF NOT EXISTS wp_mf_3_dp_vendor_payments (
                id           INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
                vendor_id    INT UNSIGNED NOT NULL,
                payment_date DATE NOT NULL,
                amount       DECIMAL(12,2) NOT NULL,
                method       VARCHAR(20) NOT NULL DEFAULT 'Cash',
                note         VARCHAR(255) DEFAULT NULL,
                created_by   BIGINT UNSIGNED NOT NULL,
                created_at   TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                KEY idx_vp_vendor (vendor_id),
                KEY idx_vp_date (payment_date)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
        ");
        $this->check_db('ensure_dahi_product.vendor_payments_table');

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

        // ── Milk Usage table (shared per-vendor milk consumption tracking) ──
        $db->query("
            CREATE TABLE IF NOT EXISTS wp_mf_3_dp_milk_usage (
                id           INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
                flow_type    VARCHAR(30) NOT NULL COMMENT 'milk_cream, pouch',
                flow_id      INT UNSIGNED NOT NULL,
                location_id  INT UNSIGNED NOT NULL,
                entry_date   DATE NOT NULL,
                vendor_id    INT UNSIGNED NOT NULL,
                ff_milk_kg   INT UNSIGNED NOT NULL,
                created_by   BIGINT UNSIGNED,
                created_at   TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                KEY idx_mu_loc_date (location_id, entry_date),
                KEY idx_mu_vendor (vendor_id),
                KEY idx_mu_flow (flow_type, flow_id)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
        ");
        $this->check_db('ensure_dahi_product.milk_usage_table');

        // ── Pouch Types table ──
        $db->query("
            CREATE TABLE IF NOT EXISTS wp_mf_3_dp_pouch_types (
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
              WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='wp_mf_3_dp_pouch_types' AND COLUMN_NAME='litre'");
        if ($has_litre) {
            $db->query("ALTER TABLE wp_mf_3_dp_pouch_types CHANGE COLUMN litre milk_per_pouch DECIMAL(10,2) NOT NULL DEFAULT 0");
            $this->check_db('ensure_dahi_product.pouch_types_rename_litre');
        }

        // Migrate: add pouches_per_crate if missing
        $has_ppc = (int) $db->get_var(
            "SELECT COUNT(*) FROM information_schema.COLUMNS
              WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='wp_mf_3_dp_pouch_types' AND COLUMN_NAME='pouches_per_crate'");
        if (!$has_ppc) {
            $db->query("ALTER TABLE wp_mf_3_dp_pouch_types ADD COLUMN pouches_per_crate INT UNSIGNED NOT NULL DEFAULT 12 AFTER milk_per_pouch");
            $this->check_db('ensure_dahi_product.pouch_types_add_ppc');
        }

        // Migrate: drop price column if exists (moved to pouch_rates)
        $has_price = (int) $db->get_var(
            "SELECT COUNT(*) FROM information_schema.COLUMNS
              WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='wp_mf_3_dp_pouch_types' AND COLUMN_NAME='price'");
        if ($has_price) {
            $db->query("ALTER TABLE wp_mf_3_dp_pouch_types DROP COLUMN price");
            $this->check_db('ensure_dahi_product.pouch_types_drop_price');
        }

        // ── Pouch Rates table ──
        $db->query("
            CREATE TABLE IF NOT EXISTS wp_mf_3_dp_pouch_rates (
                pouch_type_id  INT UNSIGNED NOT NULL PRIMARY KEY,
                rate_per_crate DECIMAL(10,2) NOT NULL DEFAULT 0
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
        ");
        $this->check_db('ensure_dahi_product.pouch_rates_table');

        // ── Pouch Production header ──
        $db->query("
            CREATE TABLE IF NOT EXISTS wp_mf_3_dp_pouch_production (
                id               INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
                location_id      INT UNSIGNED NOT NULL,
                entry_date       DATE NOT NULL,
                output_cream_kg  INT UNSIGNED NOT NULL DEFAULT 0,
                output_cream_fat DECIMAL(4,1) NOT NULL DEFAULT 0,
                created_by       BIGINT UNSIGNED,
                created_at       TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                KEY idx_pp_loc_date (location_id, entry_date)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
        ");
        $this->check_db('ensure_dahi_product.pouch_production_table');

        // ── Pouch Production line items ──
        $db->query("
            CREATE TABLE IF NOT EXISTS wp_mf_3_dp_pouch_production_lines (
                id                  INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
                pouch_production_id INT UNSIGNED NOT NULL,
                pouch_type_id       INT UNSIGNED NOT NULL,
                quantity            INT UNSIGNED NOT NULL DEFAULT 0,
                KEY idx_ppl_prod (pouch_production_id)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
        ");
        $this->check_db('ensure_dahi_product.pouch_production_lines_table');

        // Migrate: rename quantity→crate_count if old column exists
        $has_quantity = (int) $db->get_var(
            "SELECT COUNT(*) FROM information_schema.COLUMNS
              WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='wp_mf_3_dp_pouch_production_lines' AND COLUMN_NAME='quantity'");
        if ($has_quantity) {
            $db->query("ALTER TABLE wp_mf_3_dp_pouch_production_lines CHANGE COLUMN quantity crate_count INT UNSIGNED NOT NULL DEFAULT 0");
            $this->check_db('ensure_dahi_product.ppl_rename_quantity');
        }

        // ── Madhusudan Sale table ──
        $db->query("
            CREATE TABLE IF NOT EXISTS wp_mf_3_dp_madhusudan_sale (
                id               INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
                location_id      INT UNSIGNED NOT NULL,
                entry_date       DATE NOT NULL,
                total_ff_milk_kg INT UNSIGNED NOT NULL,
                sale_rate        DECIMAL(10,2) NOT NULL,
                created_by       BIGINT UNSIGNED,
                created_at       TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                KEY idx_ms_loc_date (location_id, entry_date)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
        ");
        $this->check_db('ensure_dahi_product.madhusudan_sale_table');

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

        // ── Curd Production table ──
        $db->query("
            CREATE TABLE IF NOT EXISTS wp_mf_3_dp_curd_production (
                id                INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
                location_id       INT UNSIGNED NOT NULL,
                entry_date        DATE NOT NULL,
                output_cream_kg   INT UNSIGNED NOT NULL DEFAULT 0,
                output_cream_fat  DECIMAL(3,1) NOT NULL DEFAULT 0.0,
                output_curd_matka INT UNSIGNED NOT NULL DEFAULT 0,
                created_by        BIGINT UNSIGNED NOT NULL,
                created_at        TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                INDEX idx_loc_date (location_id, entry_date)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
        ");
        $this->check_db('ensure_dahi_product.curd_production_table');

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
    }

    public function register_routes(): void {
        $auth = [ 'permission_callback' => [ $this, 'require_auth' ] ];

        // Permissions — called after login to get the full permissions object
        $this->r('/me',                'GET',  'get_me',                 $auth);

        $this->r('/locations',         'GET',  'get_locations',          $auth);
        $this->r('/products',          'GET',  'get_products',           $auth);
        $this->r('/milk-cream',        'GET',  'get_milk_cream',         $auth);
        $this->r('/milk-cream',        'POST', 'save_milk_cream',        $auth);
        $this->r('/cream-butter-ghee', 'GET',  'get_cream_bg',           $auth);
        $this->r('/cream-butter-ghee', 'POST', 'save_cream_bg',          $auth);
        $this->r('/cream-input',       'POST', 'save_cream_input',       $auth);
        $this->r('/butter-ghee',       'GET',  'get_butter_ghee',        $auth);
        $this->r('/butter-ghee',       'POST', 'save_butter_ghee',       $auth);
        $this->r('/butter-input',      'POST', 'save_butter_input',      $auth);
        $this->r('/dahi',              'GET',  'get_dahi',               $auth);
        $this->r('/dahi',              'POST', 'save_dahi',              $auth);
        $this->r('/smp-purchase',      'POST', 'save_smp_purchase',      $auth);
        $this->r('/customers',         'GET',  'get_customers',          $auth);
        $this->r('/customers',         'POST', 'save_customer',           $auth);
        $this->r('/customers/(?P<id>\\d+)', 'POST', 'update_customer',    $auth);
        $this->r('/vendors',           'POST', 'save_vendor',             $auth);
        $this->r('/vendors/(?P<id>\\d+)', 'POST', 'update_vendor',        $auth);
        $this->r('/admin/products',    'GET',  'get_admin_products',      $auth);
        $this->r('/admin/products/(?P<id>\\d+)', 'POST', 'update_product', $auth);
        $this->r('/vendors',           'GET',  'get_vendors',            $auth);
        $this->r('/sales',             'GET',  'get_sales',              $auth);
        $this->r('/sales-report',      'GET',  'get_sales_report',       $auth);
        $this->r('/vendor-purchase-report','GET', 'get_vendor_purchase_report', $auth);
        $this->r('/sales',             'POST', 'save_sale',              $auth);
        $this->r('/sales/(?P<id>\\d+)', 'DELETE','delete_sale',           $auth);
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
        $this->r('/milk-availability',      'GET',  'get_milk_availability',       $auth);
        $this->r('/pouch-types',            'GET',  'get_pouch_types',             $auth);
        $this->r('/pouch-types',            'POST', 'save_pouch_type',             $auth);
        $this->r('/pouch-types/(?P<id>\\d+)','POST','update_pouch_type',           $auth);
        $this->r('/pouch-production',       'GET',  'get_pouch_production',        $auth);
        $this->r('/pouch-production',       'POST', 'save_pouch_production',       $auth);
        $this->r('/pouch-stock',            'GET',  'get_pouch_stock',             $auth);
        $this->r('/pouch-rates',            'GET',  'get_pouch_rates',             $auth);
        $this->r('/pouch-rates',            'POST', 'save_pouch_rates',            $auth);
        $this->r('/pouch-pnl',              'GET',  'get_pouch_pnl',              $auth);
        $this->r('/madhusudan-sale',      'GET',  'get_madhusudan_sales',    $auth);
        $this->r('/madhusudan-sale',      'POST', 'save_madhusudan_sale',    $auth);
        $this->r('/madhusudan-pnl',       'GET',  'get_madhusudan_pnl',      $auth);
        $this->r('/curd-production',    'GET',  'get_curd_productions',    $auth);
        $this->r('/curd-production',    'POST', 'save_curd_production',    $auth);
        $this->r('/production-flows',   'GET',  'get_production_flows',    $auth);
        $this->r('/cashflow-report',    'GET',  'get_cashflow_report',     $auth);
        $this->r('/sales-ledger',       'GET',  'get_sales_ledger',        $auth);
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

    // ════════════════════════════════════════════════════
    // FLOW 1 - Milk + Cream
    // ════════════════════════════════════════════════════

    public function get_milk_cream( WP_REST_Request $r ): WP_REST_Response {
        if ($e = $this->validate_loc_date($r)) return $e;
        if ($e = $this->check_location_access($this->uid(), (int)$r['location_id'])) return $e;
        try {
            $rows = $this->db()->get_results($this->db()->prepare(
                "SELECT m.*, l.name AS location_name
                   FROM wp_mf_3_dp_milk_cream_production m
                   JOIN wp_mf_3_dp_locations l ON l.id = m.location_id
                  WHERE m.location_id=%d AND m.entry_date=%s ORDER BY m.created_at DESC",
                (int)$r['location_id'], $r['entry_date']
            ), ARRAY_A);
            $this->check_db('get_milk_cream');
            return $this->ok($rows);
        } catch (\Exception $e) { return $this->exc('get_milk_cream', $e); }
    }

    public function save_milk_cream( WP_REST_Request $r ): WP_REST_Response {
        if ($e = $this->check_location_access($this->uid(), (int)$r->get_param('location_id'))) return $e;
        try {
            $db        = $this->db();
            $loc       = (int) $r['location_id'];
            $is_purchase = (int)($r->get_param('input_ff_milk_kg') ?? 0) > 0;
            $milk_usage  = $r->get_param('milk_usage'); // array for processing

            if ($is_purchase) {
                // ── Purchase path (unchanged) ──
                foreach (['input_snf','input_fat'] as $f) {
                    $v = $r->get_param($f);
                    if ($v === null || $v === '') return $this->err("$f is required.");
                    if ((float)$v >= 10)          return $this->err("$f must be less than 10.");
                }
                foreach (['location_id','input_ff_milk_kg'] as $f) {
                    if (!ctype_digit((string)$r->get_param($f)))
                        return $this->err("$f is required and must be a positive integer.");
                }
                $data = [
                    'location_id'           => $loc,
                    'vendor_id'             => $r->get_param('vendor_id') ? (int)$r->get_param('vendor_id') : null,
                    'entry_date'            => $r['entry_date'],
                    'input_ff_milk_kg'      => (int) $r['input_ff_milk_kg'],
                    'input_snf'             => $this->d1($r['input_snf']),
                    'input_fat'             => $this->d1($r['input_fat']),
                    'input_rate'            => $this->d2($r['input_rate']),
                    'input_ff_milk_used_kg' => 0,
                    'output_skim_milk_kg'   => 0,
                    'output_skim_snf'       => '0.0',
                    'output_cream_kg'       => 0,
                    'output_cream_fat'      => '0.0',
                    'created_by'            => $this->uid(),
                ];
                if ($db->insert('wp_mf_3_dp_milk_cream_production', $data) === false) {
                    $this->log_db('save_milk_cream', $db->last_error);
                    return $this->err('Database error saving milk/cream record.', 500);
                }
                $id = $db->insert_id;
                $this->audit('wp_mf_3_dp_milk_cream_production', $id, 'INSERT', null, $data, $loc);
                return $this->ok(['id' => $id], 201);
            }

            // ── Processing path (with milk_usage vendor picks) ──
            foreach (['output_skim_snf','output_cream_fat'] as $f) {
                $v = $r->get_param($f);
                if ($v === null || $v === '') return $this->err("$f is required.");
                if ((float)$v >= 10)          return $this->err("$f must be less than 10.");
            }
            foreach (['output_skim_milk_kg','output_cream_kg'] as $f) {
                if (!ctype_digit((string)$r->get_param($f)))
                    return $this->err("$f is required and must be a positive integer.");
            }
            if (empty($milk_usage) || !is_array($milk_usage))
                return $this->err('milk_usage array is required for processing.');

            // Validate vendor availability
            $total_used = 0;
            foreach ($milk_usage as $mu) {
                if (empty($mu['vendor_id']) || empty($mu['ff_milk_kg']))
                    return $this->err('Each milk_usage entry needs vendor_id and ff_milk_kg.');
                $avail = $this->vendor_milk_available($loc, (int)$mu['vendor_id']);
                if ((int)$mu['ff_milk_kg'] > $avail)
                    return $this->err("Vendor {$mu['vendor_id']}: requested {$mu['ff_milk_kg']} KG but only {$avail} KG available.");
                $total_used += (int) $mu['ff_milk_kg'];
            }

            $db->query('START TRANSACTION');

            $data = [
                'location_id'           => $loc,
                'vendor_id'             => null,
                'entry_date'            => $r['entry_date'],
                'input_ff_milk_kg'      => 0,
                'input_snf'             => '0.0',
                'input_fat'             => '0.0',
                'input_rate'            => '0.00',
                'input_ff_milk_used_kg' => $total_used,
                'output_skim_milk_kg'   => (int) $r['output_skim_milk_kg'],
                'output_skim_snf'       => $this->d1($r['output_skim_snf']),
                'output_cream_kg'       => (int) $r['output_cream_kg'],
                'output_cream_fat'      => $this->d1($r['output_cream_fat']),
                'created_by'            => $this->uid(),
            ];
            if ($db->insert('wp_mf_3_dp_milk_cream_production', $data) === false) {
                $db->query('ROLLBACK');
                $this->log_db('save_milk_cream.proc', $db->last_error);
                return $this->err('Database error saving processing record.', 500);
            }
            $flow_id = $db->insert_id;
            $this->audit('wp_mf_3_dp_milk_cream_production', $flow_id, 'INSERT', null, $data, $loc);

            foreach ($milk_usage as $mu) {
                $mu_data = [
                    'flow_type'   => 'milk_cream',
                    'flow_id'     => $flow_id,
                    'location_id' => $loc,
                    'entry_date'  => $r['entry_date'],
                    'vendor_id'   => (int) $mu['vendor_id'],
                    'ff_milk_kg'  => (int) $mu['ff_milk_kg'],
                    'created_by'  => $this->uid(),
                ];
                if ($db->insert('wp_mf_3_dp_milk_usage', $mu_data) === false) {
                    $db->query('ROLLBACK');
                    $this->log_db('save_milk_cream.mu', $db->last_error);
                    return $this->err('Database error saving milk usage.', 500);
                }
                $this->audit('wp_mf_3_dp_milk_usage', $db->insert_id, 'INSERT', null, $mu_data, $loc);
            }

            $db->query('COMMIT');
            return $this->ok(['id' => $flow_id], 201);
        } catch (\Exception $e) { return $this->exc('save_milk_cream', $e); }
    }

    /**
     * Per-vendor available FF Milk = purchased all-time minus consumed all-time via milk_usage.
     */
    private function vendor_milk_available(int $loc, int $vendor_id): int {
        $db = $this->db();
        $purchased = (int) $db->get_var($db->prepare(
            "SELECT COALESCE(SUM(input_ff_milk_kg),0) FROM wp_mf_3_dp_milk_cream_production
              WHERE location_id=%d AND vendor_id=%d AND input_ff_milk_kg > 0", $loc, $vendor_id));
        $consumed = (int) $db->get_var($db->prepare(
            "SELECT COALESCE(SUM(ff_milk_kg),0) FROM wp_mf_3_dp_milk_usage
              WHERE location_id=%d AND vendor_id=%d", $loc, $vendor_id));
        return $purchased - $consumed;
    }

    // ════════════════════════════════════════════════════
    // FLOW 2 - Cream to Butter + Ghee
    // ════════════════════════════════════════════════════

    public function get_cream_bg( WP_REST_Request $r ): WP_REST_Response {
        if ($e = $this->validate_loc_date($r)) return $e;
        if ($e = $this->check_location_access($this->uid(), (int)$r['location_id'])) return $e;
        try {
            $rows = $this->db()->get_results($this->db()->prepare(
                "SELECT c.*, l.name AS location_name
                   FROM wp_mf_3_dp_cream_butter_ghee c
                   JOIN wp_mf_3_dp_locations l ON l.id = c.location_id
                  WHERE c.location_id=%d AND c.entry_date=%s ORDER BY c.created_at DESC",
                (int)$r['location_id'], $r['entry_date']
            ), ARRAY_A);
            $this->check_db('get_cream_bg');
            return $this->ok($rows);
        } catch (\Exception $e) { return $this->exc('get_cream_bg', $e); }
    }

    // save_cream_input — input section (cream received from vendor)
    public function save_cream_input( WP_REST_Request $r ): WP_REST_Response {
        if ($e = $this->check_location_access($this->uid(), (int)$r->get_param('location_id'))) return $e;
        try {
            if ($r->get_param('input_fat') !== null && (float)$r->get_param('input_fat') >= 10)
                return $this->err('input_fat must be less than 10.');
            foreach (['location_id','input_cream_kg'] as $f) {
                if (!ctype_digit((string)$r->get_param($f)))
                    return $this->err("$f is required and must be a positive integer.");
            }
            $db   = $this->db();
            $data = [
                'location_id'        => (int)   $r['location_id'],
                'vendor_id'          => $r->get_param('vendor_id') ? (int)$r->get_param('vendor_id') : null,
                'entry_date'         =>          $r['entry_date'],
                'input_cream_kg'     => (int)   $r['input_cream_kg'],
                'input_fat'          => $this->d1($r['input_fat'] ?? 0),
                'input_rate'         => $this->d2($r['input_rate'] ?? 0),
                'input_cream_used_kg'=> 0,
                'output_butter_kg'   => 0,
                'output_butter_fat'  => 0,
                'output_ghee_kg'     => 0,
                'created_by'         => $this->uid(),
            ];
            if ($db->insert('wp_mf_3_dp_cream_butter_ghee', $data) === false) {
                $this->log_db('save_cream_input', $db->last_error);
                return $this->err('Database error saving cream input record.', 500);
            }
            $id = $db->insert_id;
            $this->audit('wp_mf_3_dp_cream_butter_ghee', $id, 'INSERT', null, $data, (int)$data['location_id']);
            return $this->ok(['id' => $id], 201);
        } catch (\Exception $e) { return $this->exc('save_cream_input', $e); }
    }

    // save_cream_bg — output section (cream used, butter + ghee produced)
    public function save_cream_bg( WP_REST_Request $r ): WP_REST_Response {
        if ($e = $this->check_location_access($this->uid(), (int)$r->get_param('location_id'))) return $e;
        try {
            if ((float)$r->get_param('output_butter_fat') >= 10)
                return $this->err('output_butter_fat must be less than 10.');
            foreach (['location_id','input_cream_used_kg','output_butter_kg','output_ghee_kg'] as $f) {
                if (!ctype_digit((string)$r->get_param($f)))
                    return $this->err("$f is required and must be a positive integer.");
            }
            $db   = $this->db();
            $data = [
                'location_id'        => (int)  $r['location_id'],
                'entry_date'         =>         $r['entry_date'],
                'input_cream_kg'     => 0,
                'input_fat'          => 0,
                'input_rate'         => 0,
                'input_cream_used_kg'=> (int)  $r['input_cream_used_kg'],
                'output_butter_kg'   => (int)  $r['output_butter_kg'],
                'output_butter_fat'  => $this->d1($r['output_butter_fat']),
                'output_ghee_kg'     => (int)  $r['output_ghee_kg'],
                'created_by'         => $this->uid(),
            ];
            if ($db->insert('wp_mf_3_dp_cream_butter_ghee', $data) === false) {
                $this->log_db('save_cream_bg', $db->last_error);
                return $this->err('Database error saving cream/butter/ghee record.', 500);
            }
            $id = $db->insert_id;
            $this->audit('wp_mf_3_dp_cream_butter_ghee', $id, 'INSERT', null, $data, (int)$data['location_id']);
            return $this->ok(['id' => $id], 201);
        } catch (\Exception $e) { return $this->exc('save_cream_bg', $e); }
    }

    // ════════════════════════════════════════════════════
    // FLOW 3 - Butter to Ghee
    // ════════════════════════════════════════════════════

    public function get_butter_ghee( WP_REST_Request $r ): WP_REST_Response {
        if ($e = $this->validate_loc_date($r)) return $e;
        if ($e = $this->check_location_access($this->uid(), (int)$r['location_id'])) return $e;
        try {
            $rows = $this->db()->get_results($this->db()->prepare(
                "SELECT b.*, l.name AS location_name
                   FROM wp_mf_3_dp_butter_ghee b
                   JOIN wp_mf_3_dp_locations l ON l.id = b.location_id
                  WHERE b.location_id=%d AND b.entry_date=%s ORDER BY b.created_at DESC",
                (int)$r['location_id'], $r['entry_date']
            ), ARRAY_A);
            $this->check_db('get_butter_ghee');
            return $this->ok($rows);
        } catch (\Exception $e) { return $this->exc('get_butter_ghee', $e); }
    }

    // save_butter_input — input section (butter received from vendor)
    public function save_butter_input( WP_REST_Request $r ): WP_REST_Response {
        if ($e = $this->check_location_access($this->uid(), (int)$r->get_param('location_id'))) return $e;
        try {
            if ($r->get_param('input_fat') !== null && (float)$r->get_param('input_fat') >= 10)
                return $this->err('input_fat must be less than 10.');
            foreach (['location_id','input_butter_kg'] as $f) {
                if (!ctype_digit((string)$r->get_param($f)))
                    return $this->err("$f is required and must be a positive integer.");
            }
            $db   = $this->db();
            $data = [
                'location_id'          => (int)   $r['location_id'],
                'vendor_id'            => $r->get_param('vendor_id') ? (int)$r->get_param('vendor_id') : null,
                'entry_date'           =>          $r['entry_date'],
                'input_butter_kg'      => (int)   $r['input_butter_kg'],
                'input_fat'            => $this->d1($r['input_fat'] ?? 0),
                'input_rate'           => $this->d2($r['input_rate'] ?? 0),
                'input_butter_used_kg' => 0,
                'output_ghee_kg'       => 0,
                'created_by'           => $this->uid(),
            ];
            if ($db->insert('wp_mf_3_dp_butter_ghee', $data) === false) {
                $this->log_db('save_butter_input', $db->last_error);
                return $this->err('Database error saving butter input record.', 500);
            }
            $id = $db->insert_id;
            $this->audit('wp_mf_3_dp_butter_ghee', $id, 'INSERT', null, $data, (int)$data['location_id']);
            return $this->ok(['id' => $id], 201);
        } catch (\Exception $e) { return $this->exc('save_butter_input', $e); }
    }

    // save_butter_ghee — output section (butter used, ghee produced)
    public function save_butter_ghee( WP_REST_Request $r ): WP_REST_Response {
        if ($e = $this->check_location_access($this->uid(), (int)$r->get_param('location_id'))) return $e;
        try {
            foreach (['location_id','input_butter_used_kg','output_ghee_kg'] as $f) {
                if (!ctype_digit((string)$r->get_param($f)))
                    return $this->err("$f is required and must be a positive integer.");
            }
            $db   = $this->db();
            $data = [
                'location_id'          => (int) $r['location_id'],
                'entry_date'           =>        $r['entry_date'],
                'input_butter_kg'      => 0,
                'input_fat'            => 0,
                'input_rate'           => 0,
                'input_butter_used_kg' => (int) $r['input_butter_used_kg'],
                'output_ghee_kg'       => (int) $r['output_ghee_kg'],
                'created_by'           => $this->uid(),
            ];
            if ($db->insert('wp_mf_3_dp_butter_ghee', $data) === false) {
                $this->log_db('save_butter_ghee', $db->last_error);
                return $this->err('Database error saving butter/ghee record.', 500);
            }
            $id = $db->insert_id;
            $this->audit('wp_mf_3_dp_butter_ghee', $id, 'INSERT', null, $data, (int)$data['location_id']);
            return $this->ok(['id' => $id], 201);
        } catch (\Exception $e) { return $this->exc('save_butter_ghee', $e); }
    }

    // ════════════════════════════════════════════════════
    // FLOW 4 - Dahi
    // ════════════════════════════════════════════════════

    public function get_dahi( WP_REST_Request $r ): WP_REST_Response {
        if ($e = $this->validate_loc_date($r)) return $e;
        if ($e = $this->check_location_access($this->uid(), (int)$r['location_id'])) return $e;
        try {
            $rows = $this->db()->get_results($this->db()->prepare(
                "SELECT d.*, l.name AS location_name
                   FROM wp_mf_3_dp_dahi_production d
                   JOIN wp_mf_3_dp_locations l ON l.id = d.location_id
                  WHERE d.location_id=%d AND d.entry_date=%s ORDER BY d.created_at DESC",
                (int)$r['location_id'], $r['entry_date']
            ), ARRAY_A);
            $this->check_db('get_dahi');
            return $this->ok($rows);
        } catch (\Exception $e) { return $this->exc('get_dahi', $e); }
    }

    public function save_dahi( WP_REST_Request $r ): WP_REST_Response {
        if ($e = $this->check_location_access($this->uid(), (int)$r->get_param('location_id'))) return $e;
        try {
            $cont = (int) $r->get_param('input_container_count');
            $seal = (int) $r->get_param('input_seal_count');
            $out  = (int) $r->get_param('output_container_count');
            if ($cont <= 0) return $this->err('Container count must be greater than 0.');
            if ($seal !== $cont) return $this->err("Seal count ($seal) must equal container count ($cont).");
            if ($out  !== $cont) return $this->err("Output containers ($out) must match input count ($cont).");
            $db   = $this->db();
            $data = [
                'location_id'            => (int) $r['location_id'],
                'entry_date'             =>        $r['entry_date'],
                'input_smp_bags'         => (int) $r['input_smp_bags'],
                'input_culture_kg'       => $this->d2($r['input_culture_kg']),
                'input_protein_kg'       => $this->d2($r['input_protein_kg']),
                'input_skim_milk_kg'     => (int) $r['input_skim_milk_kg'],
                'input_container_count'  => $cont,
                'input_seal_count'       => $seal,
                'output_container_count' => $out,
                'created_by'             => $this->uid(),
            ];
            if ($db->insert('wp_mf_3_dp_dahi_production', $data) === false) {
                $this->log_db('save_dahi', $db->last_error);
                return $this->err('Database error saving dahi record.', 500);
            }
            $id = $db->insert_id;
            $this->audit('wp_mf_3_dp_dahi_production', $id, 'INSERT', null, $data, (int)$data['location_id']);
            return $this->ok(['id' => $id], 201);
        } catch (\Exception $e) { return $this->exc('save_dahi', $e); }
    }

    // ════════════════════════════════════════════════════
    // CUSTOMERS & VENDORS
    // ════════════════════════════════════════════════════

    public function get_customers( WP_REST_Request $r ): WP_REST_Response {
        try {
            $db   = $this->db();
            $pid  = (int) ($r->get_param('product_id') ?? 0);
            $all  = (int) ($r->get_param('all') ?? 0);  // include inactive for admin
            $active_clause = $all ? '' : 'AND c.is_active=1';
            if ($pid) {
                $rows = $db->get_results($db->prepare(
                    "SELECT c.id, c.name, c.is_active
                       FROM wp_mf_3_dp_customers c
                       JOIN wp_mf_3_dp_customer_products cp ON cp.customer_id = c.id
                      WHERE cp.product_id=%d $active_clause
                      ORDER BY c.name", $pid), ARRAY_A);
            } else {
                $where = $all ? '1=1' : 'is_active=1';
                $rows = $db->get_results(
                    "SELECT id, name, is_active FROM wp_mf_3_dp_customers WHERE $where ORDER BY name",
                    ARRAY_A);
            }
            $this->check_db('get_customers');
            // Attach product_ids and location_ids to each customer
            $all_cp = $db->get_results("SELECT customer_id, product_id FROM wp_mf_3_dp_customer_products", ARRAY_A);
            $cp_map = [];
            foreach ($all_cp as $cp) { $cp_map[(int)$cp['customer_id']][] = (int)$cp['product_id']; }
            $all_cl = $db->get_results("SELECT customer_id, location_id FROM wp_mf_3_dp_customer_location_access", ARRAY_A);
            $cl_map = [];
            foreach ($all_cl as $cl) { $cl_map[(int)$cl['customer_id']][] = (int)$cl['location_id']; }
            foreach ($rows as &$row) {
                $row['product_ids']  = $cp_map[(int)$row['id']] ?? [];
                $row['location_ids'] = $cl_map[(int)$row['id']] ?? [];
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
            $dup = $db->get_var($db->prepare("SELECT COUNT(*) FROM wp_mf_3_dp_customers WHERE name=%s", $name));
            if ($dup) return $this->err('Customer name already exists.');
            $db->insert('wp_mf_3_dp_customers', ['name' => $name, 'is_active' => 1]);
            if ($db->insert_id === 0) { $this->log_db('save_customer', $db->last_error); return $this->err('Database error.', 500); }
            $cid = $db->insert_id;
            foreach ($pids as $pid) { $db->insert('wp_mf_3_dp_customer_products', ['customer_id' => $cid, 'product_id' => (int)$pid]); }
            if (!empty($lids) && is_array($lids)) {
                foreach ($lids as $lid) { $db->insert('wp_mf_3_dp_customer_location_access', ['customer_id' => $cid, 'location_id' => (int)$lid]); }
            }
            $this->audit('wp_mf_3_dp_customers', $cid, 'INSERT', null, ['name' => $name, 'product_ids' => $pids, 'location_ids' => $lids]);
            return $this->ok(['id' => $cid], 201);
        } catch (\Exception $e) { return $this->exc('save_customer', $e); }
    }

    public function update_customer( WP_REST_Request $r ): WP_REST_Response {
        if ($e = $this->check_finance_access($this->uid())) return $e;
        try {
            $db     = $this->db();
            $cid    = (int) $r['id'];
            $name   = trim($r->get_param('name') ?? '');
            $pids   = $r->get_param('product_ids');
            $lids   = $r->get_param('location_ids');
            $active = $r->get_param('is_active');
            if (!$cid) return $this->err('id is required.');
            $old = $db->get_row($db->prepare("SELECT * FROM wp_mf_3_dp_customers WHERE id=%d", $cid), ARRAY_A);
            if (!$old) return $this->err('Customer not found.', 404);
            $updates = [];
            if ($name && $name !== $old['name']) {
                $dup = $db->get_var($db->prepare("SELECT COUNT(*) FROM wp_mf_3_dp_customers WHERE name=%s AND id!=%d", $name, $cid));
                if ($dup) return $this->err('Customer name already exists.');
                $updates['name'] = $name;
            }
            if ($active !== null) { $updates['is_active'] = (int)$active; }
            if (!empty($updates)) { $db->update('wp_mf_3_dp_customers', $updates, ['id' => $cid]); $this->check_db('update_customer'); }
            if ($pids !== null && is_array($pids)) {
                $db->delete('wp_mf_3_dp_customer_products', ['customer_id' => $cid]);
                foreach ($pids as $pid) { $db->insert('wp_mf_3_dp_customer_products', ['customer_id' => $cid, 'product_id' => (int)$pid]); }
            }
            if ($lids !== null && is_array($lids)) {
                $db->delete('wp_mf_3_dp_customer_location_access', ['customer_id' => $cid]);
                foreach ($lids as $lid) { $db->insert('wp_mf_3_dp_customer_location_access', ['customer_id' => $cid, 'location_id' => (int)$lid]); }
            }
            $after = $db->get_row($db->prepare("SELECT * FROM wp_mf_3_dp_customers WHERE id=%d", $cid), ARRAY_A);
            $this->audit('wp_mf_3_dp_customers', $cid, 'UPDATE', $old, $after);
            return $this->ok(['id' => $cid]);
        } catch (\Exception $e) { return $this->exc('update_customer', $e); }
    }

    public function get_vendors( WP_REST_Request $r ): WP_REST_Response {
        try {
            $db     = $this->db();
            $loc_id = (int) ($r->get_param('location_id') ?? 0);
            $all    = (int) ($r->get_param('all') ?? 0);
            if ($loc_id && !$all) {
                $rows = $db->get_results($db->prepare(
                    "SELECT v.id, v.name, v.is_active FROM wp_mf_3_dp_vendors v
                     JOIN wp_mf_3_dp_vendor_location_access vla ON vla.vendor_id = v.id
                     WHERE v.is_active=1 AND vla.location_id = %d ORDER BY v.name", $loc_id), ARRAY_A);
            } else {
                $where = $all ? '1=1' : 'is_active=1';
                $rows = $db->get_results("SELECT id, name, is_active FROM wp_mf_3_dp_vendors WHERE $where ORDER BY name", ARRAY_A);
            }
            $this->check_db('get_vendors');
            // Attach location_ids
            $all_vl = $db->get_results("SELECT vendor_id, location_id FROM wp_mf_3_dp_vendor_location_access", ARRAY_A);
            $vl_map = [];
            foreach ($all_vl as $vl) { $vl_map[(int)$vl['vendor_id']][] = (int)$vl['location_id']; }
            // Attach product_ids
            $all_vp = $db->get_results("SELECT vendor_id, product_id FROM wp_mf_3_dp_vendor_products", ARRAY_A);
            $vp_map = [];
            foreach ($all_vp as $vp) { $vp_map[(int)$vp['vendor_id']][] = (int)$vp['product_id']; }
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
            $dup = $db->get_var($db->prepare("SELECT COUNT(*) FROM wp_mf_3_dp_vendors WHERE name=%s", $name));
            if ($dup) return $this->err('Vendor name already exists.');
            $pids = $r->get_param('product_ids') ?? [];
            $db->insert('wp_mf_3_dp_vendors', ['name' => $name, 'is_active' => 1]);
            if ($db->insert_id === 0) { $this->log_db('save_vendor', $db->last_error); return $this->err('Database error.', 500); }
            $vid = $db->insert_id;
            if (!empty($lids) && is_array($lids)) {
                foreach ($lids as $lid) { $db->insert('wp_mf_3_dp_vendor_location_access', ['vendor_id' => $vid, 'location_id' => (int)$lid]); }
            }
            if (!empty($pids) && is_array($pids)) {
                foreach ($pids as $pid) { $db->insert('wp_mf_3_dp_vendor_products', ['vendor_id' => $vid, 'product_id' => (int)$pid]); }
            }
            $this->audit('wp_mf_3_dp_vendors', $vid, 'INSERT', null, ['name' => $name, 'location_ids' => $lids, 'product_ids' => $pids]);
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
            $old = $db->get_row($db->prepare("SELECT * FROM wp_mf_3_dp_vendors WHERE id=%d", $vid), ARRAY_A);
            if (!$old) return $this->err('Vendor not found.', 404);
            $updates = [];
            if ($name && $name !== $old['name']) {
                $dup = $db->get_var($db->prepare("SELECT COUNT(*) FROM wp_mf_3_dp_vendors WHERE name=%s AND id!=%d", $name, $vid));
                if ($dup) return $this->err('Vendor name already exists.');
                $updates['name'] = $name;
            }
            if ($active !== null) { $updates['is_active'] = (int)$active; }
            if (!empty($updates)) { $db->update('wp_mf_3_dp_vendors', $updates, ['id' => $vid]); $this->check_db('update_vendor'); }
            if ($lids !== null && is_array($lids)) {
                $db->delete('wp_mf_3_dp_vendor_location_access', ['vendor_id' => $vid]);
                foreach ($lids as $lid) { $db->insert('wp_mf_3_dp_vendor_location_access', ['vendor_id' => $vid, 'location_id' => (int)$lid]); }
            }
            $pids = $r->get_param('product_ids');
            if ($pids !== null && is_array($pids)) {
                $db->delete('wp_mf_3_dp_vendor_products', ['vendor_id' => $vid]);
                foreach ($pids as $pid) { $db->insert('wp_mf_3_dp_vendor_products', ['vendor_id' => $vid, 'product_id' => (int)$pid]); }
            }
            $after = $db->get_row($db->prepare("SELECT * FROM wp_mf_3_dp_vendors WHERE id=%d", $vid), ARRAY_A);
            $this->audit('wp_mf_3_dp_vendors', $vid, 'UPDATE', $old, $after);
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
    // SALES
    // ════════════════════════════════════════════════════

    public function get_sales( WP_REST_Request $r ): WP_REST_Response {
        if ($e = $this->validate_loc_date($r)) return $e;
        if ($e = $this->check_location_access($this->uid(), (int)$r['location_id'])) return $e;
        try {
            $db  = $this->db();
            $loc = (int) $r['location_id'];
            $dt  = $r['entry_date'];
            // Return sellable products for dropdown (exclude raw inputs and Dahi)
            $products = $db->get_results(
                "SELECT id, name, unit FROM wp_mf_3_dp_products WHERE is_active=1 AND id NOT IN (6,7,8,9) ORDER BY sort_order", ARRAY_A);
            $this->check_db('get_sales.products');
            $entries = $db->get_results($db->prepare(
                "SELECT s.id, s.product_id, p.name AS product_name,
                        s.customer_id,
                        COALESCE(cu.name, s.customer_name, '') AS customer_name,
                        s.quantity_kg, s.rate,
                        (s.quantity_kg * s.rate) AS total
                   FROM wp_mf_3_dp_sales s
                   JOIN wp_mf_3_dp_products p ON p.id = s.product_id
                   LEFT JOIN wp_mf_3_dp_customers cu ON cu.id = s.customer_id
                  WHERE s.location_id=%d AND s.entry_date=%s
                  ORDER BY p.sort_order, customer_name",
                $loc, $dt
            ), ARRAY_A);
            $this->check_db('get_sales.entries');
            return $this->ok([
                'location_id' => $loc,
                'entry_date'  => $dt,
                'products'    => $products,
                'entries'     => $entries ?? [],
            ]);
        } catch (\Exception $e) { return $this->exc('get_sales', $e); }
    }

    // Save a single sale entry (one customer, one product, one day)
    public function save_sale( WP_REST_Request $r ): WP_REST_Response {
        try {
            $db          = $this->db();
            $loc         = (int)   ($r->get_param('location_id')  ?? 0);
            $dt          = trim($r->get_param('entry_date')        ?? '');
            $pid         = (int)   ($r->get_param('product_id')   ?? 0);
            $customer_id = (int)   ($r->get_param('customer_id')  ?? 0);
            $qty         = (int)   ($r->get_param('quantity_kg')  ?? 0);
            $rate        = (float) ($r->get_param('rate')         ?? 0);
            if (!$loc)                                        return $this->err('location_id is required.');
            if (!preg_match('/^\d{4}-\d{2}-\d{2}$/', $dt))  return $this->err('entry_date must be YYYY-MM-DD.');
            if (!$pid)                                        return $this->err('product_id is required.');
            if (!$customer_id)                                return $this->err('customer_id is required.');
            if ($qty <= 0)                                    return $this->err('quantity_kg must be > 0.');
            if ($rate < 0)                                    return $this->err('rate must be >= 0.');
            if ($e = $this->check_location_access($this->uid(), $loc)) return $e;
            // Resolve customer name for denormalised storage
            $cust_name = $db->get_var($db->prepare(
                "SELECT name FROM wp_mf_3_dp_customers WHERE id=%d AND is_active=1",
                $customer_id
            ));
            if (!$cust_name) return $this->err('Customer not found.');
            // Check for existing row (UNIQUE on location_id, product_id, entry_date, customer_id)
            $existing = $db->get_row($db->prepare(
                "SELECT * FROM wp_mf_3_dp_sales WHERE location_id=%d AND product_id=%d AND entry_date=%s AND customer_id=%d",
                $loc, $pid, $dt, $customer_id
            ), ARRAY_A);

            if ($existing) {
                // Update: add qty, use new rate
                $old_qty  = (int) $existing['quantity_kg'];
                $new_qty  = $old_qty + $qty;
                $new_rate = $rate;
                $id       = (int) $existing['id'];
                $result   = $db->update('wp_mf_3_dp_sales', [
                    'quantity_kg' => $new_qty,
                    'rate'        => $new_rate,
                    'updated_by'  => $this->uid(),
                ], ['id' => $id]);
                if ($result === false) {
                    $this->log_db('save_sale.update', $db->last_error);
                    return $this->err('Database error updating sale.', 500);
                }
                $after = $db->get_row($db->prepare("SELECT * FROM wp_mf_3_dp_sales WHERE id=%d", $id), ARRAY_A);
                $this->audit('wp_mf_3_dp_sales', $id, 'UPDATE', $existing, $after, $loc);
                return $this->ok(['id' => $id, 'merged' => true], 200);
            }

            $data = [
                'location_id'   => $loc,
                'product_id'    => $pid,
                'entry_date'    => $dt,
                'customer_id'   => $customer_id,
                'customer_name' => $cust_name,
                'quantity_kg'   => $qty,
                'rate'          => $rate,
                'created_by'    => $this->uid(),
                'updated_by'    => $this->uid(),
            ];
            if ($db->insert('wp_mf_3_dp_sales', $data) === false) {
                $this->log_db('save_sale', $db->last_error);
                return $this->err('Database error saving sale.', 500);
            }
            $id = $db->insert_id;
            $this->audit('wp_mf_3_dp_sales', $id, 'INSERT', null, $data, $loc);
            return $this->ok(['id' => $id], 201);
        } catch (\Exception $e) { return $this->exc('save_sale', $e); }
    }

    // Delete a single sale entry by id
    public function delete_sale( WP_REST_Request $r ): WP_REST_Response {
        try {
            $db = $this->db();
            $id = (int) $r['id'];
            if (!$id) return $this->err('id is required.');
            $row = $db->get_row($db->prepare(
                "SELECT * FROM wp_mf_3_dp_sales WHERE id=%d", $id
            ), ARRAY_A);
            if (!$row) return $this->err('Sale not found.', 404);
            if ($e = $this->check_location_access($this->uid(), (int)$row['location_id'])) return $e;
            $db->delete('wp_mf_3_dp_sales', ['id' => $id]);
            $this->audit('wp_mf_3_dp_sales', $id, 'DELETE', $row, null, (int)$row['location_id']);
            return $this->ok(['deleted_id' => $id]);
        } catch (\Exception $e) { return $this->exc('delete_sale', $e); }
    }

    // ════════════════════════════════════════════════════
    // SALES REPORT  — daily aggregated sales by product
    // ════════════════════════════════════════════════════

    public function get_sales_report( WP_REST_Request $r ): WP_REST_Response {
        if ($e = $this->check_location_access($this->uid(), (int)$r['location_id'])) return $e;
        try {
            $db   = $this->db();
            $loc  = (int) $r['location_id'];
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

            // Aggregate: SUM(qty) and SUM(qty*rate) per day per product
            $rows = $db->get_results($db->prepare(
                "SELECT entry_date,
                        product_id,
                        SUM(quantity_kg)        AS qty_kg,
                        SUM(quantity_kg * rate) AS total_value
                   FROM wp_mf_3_dp_sales
                  WHERE location_id = %d
                    AND entry_date BETWEEN %s AND %s
                  GROUP BY entry_date, product_id
                  ORDER BY entry_date DESC, product_id",
                $loc, $from, $to
            ), ARRAY_A);
            $this->check_db('sales_report.rows');

            // Pivot: build one row per date with a cell per product
            $by_date = [];
            foreach ($rows as $row) {
                $d   = $row['entry_date'];
                $pid = (int) $row['product_id'];
                if (!isset($by_date[$d])) $by_date[$d] = [];
                $by_date[$d][$pid] = [
                    'qty_kg'      => (int)   $row['qty_kg'],
                    'total_value' => (float) $row['total_value'],
                ];
            }

            // Build ordered date rows — only dates that have at least one sale
            $report = [];
            foreach ($by_date as $date => $cells) {
                $row_total = 0;
                $products  = [];
                foreach ($col_order as $pid) {
                    $cell = $cells[$pid] ?? null;
                    $row_total += $cell['total_value'] ?? 0;
                    $products[$pid] = $cell; // null = no sale that day
                }
                $report[] = [
                    'date'      => $date,
                    'products'  => $products,
                    'row_total' => round($row_total, 2),
                ];
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
        if ($e = $this->check_location_access($this->uid(), (int)$r['location_id'])) return $e;
        try {
            $db   = $this->db();
            $loc  = (int) $r['location_id'];
            $from = $r['from'] ?? date('Y-m-d', strtotime('-29 days'));
            $to   = $r['to']   ?? date('Y-m-d');

            $rows = [];

            // FF Milk purchases (input_ff_milk_kg > 0)
            $ff = $db->get_results($db->prepare(
                "SELECT m.entry_date,
                        COALESCE(v.name, 'Unknown Vendor') AS vendor,
                        'FF Milk'        AS product,
                        m.input_ff_milk_kg AS quantity_kg,
                        m.input_fat      AS fat,
                        m.input_rate     AS rate,
                        (m.input_ff_milk_kg * m.input_rate) AS amount
                   FROM wp_mf_3_dp_milk_cream_production m
                   LEFT JOIN wp_mf_3_dp_vendors v ON v.id = m.vendor_id
                  WHERE m.location_id = %d
                    AND m.entry_date BETWEEN %s AND %s
                    AND m.input_ff_milk_kg > 0
                  ORDER BY m.entry_date DESC, vendor",
                $loc, $from, $to
            ), ARRAY_A);
            $this->check_db('vendor_report.ff_milk');
            $rows = array_merge($rows, $ff ?? []);

            // Cream purchases (input_cream_kg > 0)
            $cream = $db->get_results($db->prepare(
                "SELECT c.entry_date,
                        COALESCE(v.name, 'Unknown Vendor') AS vendor,
                        'Cream'          AS product,
                        c.input_cream_kg AS quantity_kg,
                        c.input_fat      AS fat,
                        c.input_rate     AS rate,
                        (c.input_cream_kg * c.input_rate) AS amount
                   FROM wp_mf_3_dp_cream_butter_ghee c
                   LEFT JOIN wp_mf_3_dp_vendors v ON v.id = c.vendor_id
                  WHERE c.location_id = %d
                    AND c.entry_date BETWEEN %s AND %s
                    AND c.input_cream_kg > 0
                  ORDER BY c.entry_date DESC, vendor",
                $loc, $from, $to
            ), ARRAY_A);
            $this->check_db('vendor_report.cream');
            $rows = array_merge($rows, $cream ?? []);

            // Butter purchases (input_butter_kg > 0)
            $butter = $db->get_results($db->prepare(
                "SELECT b.entry_date,
                        COALESCE(v.name, 'Unknown Vendor') AS vendor,
                        'Butter'          AS product,
                        b.input_butter_kg AS quantity_kg,
                        b.input_fat       AS fat,
                        b.input_rate      AS rate,
                        (b.input_butter_kg * b.input_rate) AS amount
                   FROM wp_mf_3_dp_butter_ghee b
                   LEFT JOIN wp_mf_3_dp_vendors v ON v.id = b.vendor_id
                  WHERE b.location_id = %d
                    AND b.entry_date BETWEEN %s AND %s
                    AND b.input_butter_kg > 0
                  ORDER BY b.entry_date DESC, vendor",
                $loc, $from, $to
            ), ARRAY_A);
            $this->check_db('vendor_report.butter');
            $rows = array_merge($rows, $butter ?? []);

            // Sort combined rows by date desc, then vendor
            usort($rows, fn($a, $b) =>
                strcmp($b['entry_date'], $a['entry_date']) ?: strcmp($a['vendor'], $b['vendor'])
            );

            // Grand totals
            $total_qty    = array_sum(array_column($rows, 'quantity_kg'));
            $total_amount = array_sum(array_column($rows, 'amount'));

            return $this->ok([
                'location_id'  => $loc,
                'from'         => $from,
                'to'           => $to,
                'rows'         => $rows,
                'total_qty'    => (int)   $total_qty,
                'total_amount' => (float) $total_amount,
            ]);
        } catch (\Exception $e) { return $this->exc('get_vendor_purchase_report', $e); }
    }


    // ════════════════════════════════════════════════════
    // FLOW 5 - SMP / Protein / Culture Purchase
    // ════════════════════════════════════════════════════

    public function save_smp_purchase( WP_REST_Request $r ): WP_REST_Response {
        if ($e = $this->check_location_access($this->uid(), (int)$r->get_param('location_id'))) return $e;
        try {
            $loc        = (int) $r['location_id'];
            $entry_date = $r['entry_date'];
            $smp         = $this->d2($r->get_param('smp_bags')     ?? 0);
            $protein     = $this->d2($r->get_param('protein_kg')   ?? 0);
            $culture     = $this->d2($r->get_param('culture_kg')   ?? 0);
            $smp_rate     = $this->d2($r->get_param('smp_rate')     ?? 0);
            $protein_rate = $this->d2($r->get_param('protein_rate') ?? 0);
            $culture_rate = $this->d2($r->get_param('culture_rate') ?? 0);

            if ($smp <= 0 && $protein <= 0 && $culture <= 0) {
                return $this->err('At least one of SMP, Protein, or Culture must be non-zero.');
            }

            $db  = $this->db();
            $uid = $this->uid();
            $saved = [];

            if ($smp > 0) {
                $data = ['location_id'=>$loc,'entry_date'=>$entry_date,
                         'product_id'=>7,'quantity'=>$smp,'rate'=>$smp_rate,'created_by'=>$uid];
                if ($db->insert('wp_mf_3_dp_ingredient_purchase', $data) === false) {
                    $this->log_db('save_smp_purchase.smp', $db->last_error);
                    return $this->err('Database error saving SMP.', 500);
                }
                $this->audit('wp_mf_3_dp_ingredient_purchase', $db->insert_id, 'INSERT', null, $data, $loc);
                $saved[] = 'SMP';
            }
            if ($protein > 0) {
                $data = ['location_id'=>$loc,'entry_date'=>$entry_date,
                         'product_id'=>8,'quantity'=>$protein,'rate'=>$protein_rate,'created_by'=>$uid];
                if ($db->insert('wp_mf_3_dp_ingredient_purchase', $data) === false) {
                    $this->log_db('save_smp_purchase.protein', $db->last_error);
                    return $this->err('Database error saving Protein.', 500);
                }
                $this->audit('wp_mf_3_dp_ingredient_purchase', $db->insert_id, 'INSERT', null, $data, $loc);
                $saved[] = 'Protein';
            }
            if ($culture > 0) {
                $data = ['location_id'=>$loc,'entry_date'=>$entry_date,
                         'product_id'=>9,'quantity'=>$culture,'rate'=>$culture_rate,'created_by'=>$uid];
                if ($db->insert('wp_mf_3_dp_ingredient_purchase', $data) === false) {
                    $this->log_db('save_smp_purchase.culture', $db->last_error);
                    return $this->err('Database error saving Culture.', 500);
                }
                $this->audit('wp_mf_3_dp_ingredient_purchase', $db->insert_id, 'INSERT', null, $data, $loc);
                $saved[] = 'Culture';
            }

            return $this->ok(['saved' => $saved], 201);
        } catch (\Exception $e) { return $this->exc('save_smp_purchase', $e); }
    }

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
            // Stock movements — positives add, negatives reduce.
            // Each UNION ALL row is one movement type for one product.
            $prod_rows = $db->get_results($db->prepare(
                $this->stock_movements_sql(),
                $loc,$from,$to,
                $loc,$from,$to,
                $loc,$from,$to,
                $loc,$from,$to,
                $loc,$from,$to,
                $loc,$from,$to,
                $loc,$from,$to,
                $loc,$from,$to,
                $loc,$from,$to,
                $loc,$from,$to,
                $loc,$from,$to,
                $loc,$from,$to,
                $loc,$from,$to,
                $loc,$from,$to,
                $loc,$from,$to,
                $loc,$from,$to,
                $loc,$from,$to,
                $loc,$from,$to,
                $loc,$from,$to,
                $loc,$from,$to,
                $loc,$from,$to,
                $loc,$from,$to
            ), ARRAY_A);
            $this->check_db('get_stock.production');
            $sales_rows = $db->get_results($db->prepare(
                "SELECT entry_date,product_id,SUM(quantity_kg) AS qty FROM wp_mf_3_dp_sales WHERE location_id=%d AND entry_date BETWEEN %s AND %s GROUP BY entry_date,product_id",
                $loc,$from,$to
            ), ARRAY_A);
            $this->check_db('get_stock.sales');
            // Step 1: collect daily movements keyed by date + product
            $daily = [];
            foreach ($prod_rows  as $row) $daily[$row['entry_date']][$row['product_id']] = ($daily[$row['entry_date']][$row['product_id']] ?? 0) + (int)$row['qty'];
            foreach ($sales_rows as $row) $daily[$row['entry_date']][$row['product_id']] = ($daily[$row['entry_date']][$row['product_id']] ?? 0) - (int)$row['qty'];

            // Step 2: walk every day in the window and carry the running
            // cumulative balance forward. A day with no activity keeps the
            // same stock as the previous day rather than showing zero.
            $dates   = [];
            $running = []; // product_id => cumulative balance
            foreach ($products as $p) $running[$p['id']] = 0;

            for ($ts = strtotime($from); $ts <= strtotime($to); $ts += 86400) {
                $d = date('Y-m-d', $ts);
                // Apply today's movements (if any) to the running totals
                foreach ($products as $p) {
                    $running[$p['id']] += $daily[$d][$p['id']] ?? 0;
                }
                $stocks = [];
                foreach ($products as $p) $stocks[$p['id']] = $running[$p['id']];
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

            $rows = $db->get_results($db->prepare(
                "SELECT m.id, m.entry_date,
                        m.input_ff_milk_used_kg,
                        m.output_skim_milk_kg,
                        m.output_cream_kg,
                        ROUND((m.output_skim_milk_kg + m.output_cream_kg) / m.input_ff_milk_used_kg * 100, 2) AS ratio,
                        COALESCE(v.name, '') AS vendor_name,
                        m.created_by,
                        m.created_at
                   FROM wp_mf_3_dp_milk_cream_production m
                   LEFT JOIN wp_mf_3_dp_vendors v ON v.id = m.vendor_id
                  WHERE m.location_id = %d
                    AND m.input_ff_milk_used_kg > 0
                  ORDER BY m.entry_date DESC, m.created_at DESC",
                $loc
            ), ARRAY_A);
            $this->check_db('get_anomalies');

            $user_ids = array_unique(array_filter(array_column($rows, 'created_by')));
            $names    = $this->resolve_first_names($user_ids);

            foreach ($rows as &$row) {
                $row['ratio']        = (float) $row['ratio'];
                $row['is_anomalous'] = $row['ratio'] < 105;
                $row['user_name']    = $names[$row['created_by']] ?? 'Unknown';
            }
            unset($row);

            return $this->ok(['rows' => $rows]);
        } catch (\Exception $e) { return $this->exc('get_anomalies', $e); }
    }

    // ════════════════════════════════════════════════════
    // VENDOR PAYMENTS & LEDGER  (finance only)
    // ════════════════════════════════════════════════════

    public function save_vendor_payment( WP_REST_Request $r ): WP_REST_Response {
        if ($e = $this->check_finance_access($this->uid())) return $e;
        try {
            $db        = $this->db();
            $vendor_id = (int) $r->get_param('vendor_id');
            $date      = sanitize_text_field($r->get_param('payment_date') ?? '');
            $amount    = (float) $r->get_param('amount');
            $method    = sanitize_text_field($r->get_param('method') ?? 'Cash');
            $note      = sanitize_text_field($r->get_param('note') ?? '');

            if (!$vendor_id) return $this->err('vendor_id is required.');
            if (!preg_match('/^\d{4}-\d{2}-\d{2}$/', $date)) return $this->err('payment_date must be YYYY-MM-DD.');
            if ($amount <= 0) return $this->err('amount must be greater than zero.');
            $allowed_methods = ['Cash', 'Bank Transfer', 'UPI', 'Cheque'];
            if (!in_array($method, $allowed_methods, true)) return $this->err('method must be one of: ' . implode(', ', $allowed_methods));

            // Verify vendor exists
            $v = $db->get_var($db->prepare("SELECT id FROM wp_mf_3_dp_vendors WHERE id=%d", $vendor_id));
            $this->check_db('save_vendor_payment.vendor_check');
            if (!$v) return $this->err('Vendor not found.', 404);

            $data = [
                'vendor_id'    => $vendor_id,
                'payment_date' => $date,
                'amount'       => $this->d2($amount),
                'method'       => $method,
                'note'         => $note ?: null,
                'created_by'   => $this->uid(),
            ];
            if ($db->insert('wp_mf_3_dp_vendor_payments', $data) === false) {
                $this->log_db('save_vendor_payment', $db->last_error);
                return $this->err('Database error.', 500);
            }
            $this->audit('wp_mf_3_dp_vendor_payments', $db->insert_id, 'INSERT', null, $data);
            return $this->ok(['id' => $db->insert_id], 201);
        } catch (\Exception $e) { return $this->exc('save_vendor_payment', $e); }
    }

    public function get_vendor_ledger( WP_REST_Request $r ): WP_REST_Response {
        if ($e = $this->check_finance_access($this->uid())) return $e;
        try {
            $db     = $this->db();
            $from   = sanitize_text_field($r->get_param('from') ?? date('Y-m-d', strtotime('-90 days')));
            $to     = sanitize_text_field($r->get_param('to')   ?? date('Y-m-d'));
            $loc_id = (int) ($r->get_param('location_id') ?? 0);

            // Vendor list — optionally filtered by location assignment
            if ($loc_id) {
                $vendors = $db->get_results($db->prepare(
                    "SELECT v.id, v.name FROM wp_mf_3_dp_vendors v
                     JOIN wp_mf_3_dp_vendor_location_access vla ON vla.vendor_id = v.id
                     WHERE v.is_active=1 AND vla.location_id = %d ORDER BY v.name", $loc_id), ARRAY_A);
            } else {
                $vendors = $db->get_results(
                    "SELECT id, name FROM wp_mf_3_dp_vendors WHERE is_active=1 ORDER BY name", ARRAY_A);
            }
            $this->check_db('vendor_ledger.vendors');

            // Purchases from 3 production tables — optionally filtered by location
            $loc_where_mcp = $loc_id ? $db->prepare(" AND location_id = %d", $loc_id) : '';
            $loc_where_cbg = $loc_where_mcp;
            $loc_where_bg  = $loc_where_mcp;

            $purchase_sql = $db->prepare("
                SELECT vendor_id, SUM(amount) AS total FROM (
                    SELECT vendor_id, ROUND(input_ff_milk_kg * input_rate, 2) AS amount
                      FROM wp_mf_3_dp_milk_cream_production
                     WHERE vendor_id IS NOT NULL AND input_ff_milk_kg > 0
                       AND entry_date BETWEEN %s AND %s $loc_where_mcp
                    UNION ALL
                    SELECT vendor_id, ROUND(input_cream_kg * input_rate, 2) AS amount
                      FROM wp_mf_3_dp_cream_butter_ghee
                     WHERE vendor_id IS NOT NULL AND input_cream_kg > 0
                       AND entry_date BETWEEN %s AND %s $loc_where_cbg
                    UNION ALL
                    SELECT vendor_id, ROUND(input_butter_kg * input_rate, 2) AS amount
                      FROM wp_mf_3_dp_butter_ghee
                     WHERE vendor_id IS NOT NULL AND input_butter_kg > 0
                       AND entry_date BETWEEN %s AND %s $loc_where_bg
                ) AS purchases GROUP BY vendor_id
            ", $from, $to, $from, $to, $from, $to);
            $purchase_rows = $db->get_results($purchase_sql, ARRAY_A);
            $this->check_db('vendor_ledger.purchases');

            $purchases = [];
            foreach ($purchase_rows as $row) $purchases[(int)$row['vendor_id']] = (float) $row['total'];

            // Payments — always unfiltered (global)
            $payment_rows = $db->get_results($db->prepare("
                SELECT vendor_id, SUM(amount) AS total
                  FROM wp_mf_3_dp_vendor_payments
                 WHERE payment_date BETWEEN %s AND %s
                 GROUP BY vendor_id
            ", $from, $to), ARRAY_A);
            $this->check_db('vendor_ledger.payments');

            $payments = [];
            foreach ($payment_rows as $row) $payments[(int)$row['vendor_id']] = (float) $row['total'];

            $result = [];
            foreach ($vendors as $v) {
                $vid  = (int) $v['id'];
                $tp   = $purchases[$vid] ?? 0.0;
                $tpay = $payments[$vid]  ?? 0.0;
                if ($tp == 0 && $tpay == 0) continue; // skip vendors with no activity
                $result[] = [
                    'vendor_id'       => $vid,
                    'vendor_name'     => $v['name'],
                    'total_purchases' => round($tp, 2),
                    'total_payments'  => round($tpay, 2),
                    'balance_due'     => round($tp - $tpay, 2),
                ];
            }
            // Sort by balance_due descending
            usort($result, fn($a, $b) => $b['balance_due'] <=> $a['balance_due']);

            return $this->ok(['vendors' => $result, 'from' => $from, 'to' => $to]);
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

            // vendor_id=0 means all vendors
            $vendor_name = 'All Vendors';
            if ($vendor_id) {
                $vendor = $db->get_row($db->prepare(
                    "SELECT id, name FROM wp_mf_3_dp_vendors WHERE id=%d", $vendor_id), ARRAY_A);
                $this->check_db('vendor_ledger_detail.vendor_check');
                if (!$vendor) return $this->err('Vendor not found.', 404);
                $vendor_name = $vendor['name'];
            }

            // Build vendor filter
            $vend_m = $vendor_id ? $db->prepare(" AND m.vendor_id = %d", $vendor_id) : '';
            $vend_c = $vendor_id ? $db->prepare(" AND c.vendor_id = %d", $vendor_id) : '';
            $vend_b = $vendor_id ? $db->prepare(" AND b.vendor_id = %d", $vendor_id) : '';
            $vend_p = $vendor_id ? $db->prepare(" AND vendor_id = %d", $vendor_id) : '';

            // Optional location filter for purchase transactions
            $loc_where_m = $loc_id ? $db->prepare(" AND m.location_id = %d", $loc_id) : '';
            $loc_where_c = $loc_id ? $db->prepare(" AND c.location_id = %d", $loc_id) : '';
            $loc_where_b = $loc_id ? $db->prepare(" AND b.location_id = %d", $loc_id) : '';

            // Purchase transactions — include vendor_name
            $purchases = $db->get_results($db->prepare("
                SELECT 'purchase' AS type, m.entry_date AS date, v.name AS vendor_name,
                       'FF Milk' AS product,
                       m.input_ff_milk_kg AS quantity, m.input_rate AS rate,
                       ROUND(m.input_ff_milk_kg * m.input_rate, 2) AS amount,
                       l.name AS location_name
                  FROM wp_mf_3_dp_milk_cream_production m
                  JOIN wp_mf_3_dp_locations l ON l.id = m.location_id
                  LEFT JOIN wp_mf_3_dp_vendors v ON v.id = m.vendor_id
                 WHERE m.input_ff_milk_kg > 0
                   AND m.entry_date BETWEEN %s AND %s $vend_m $loc_where_m
                UNION ALL
                SELECT 'purchase' AS type, c.entry_date AS date, v.name AS vendor_name,
                       'Cream' AS product,
                       c.input_cream_kg AS quantity, c.input_rate AS rate,
                       ROUND(c.input_cream_kg * c.input_rate, 2) AS amount,
                       l.name AS location_name
                  FROM wp_mf_3_dp_cream_butter_ghee c
                  JOIN wp_mf_3_dp_locations l ON l.id = c.location_id
                  LEFT JOIN wp_mf_3_dp_vendors v ON v.id = c.vendor_id
                 WHERE c.input_cream_kg > 0
                   AND c.entry_date BETWEEN %s AND %s $vend_c $loc_where_c
                UNION ALL
                SELECT 'purchase' AS type, b.entry_date AS date, v.name AS vendor_name,
                       'Butter' AS product,
                       b.input_butter_kg AS quantity, b.input_rate AS rate,
                       ROUND(b.input_butter_kg * b.input_rate, 2) AS amount,
                       l.name AS location_name
                  FROM wp_mf_3_dp_butter_ghee b
                  JOIN wp_mf_3_dp_locations l ON l.id = b.location_id
                  LEFT JOIN wp_mf_3_dp_vendors v ON v.id = b.vendor_id
                 WHERE b.input_butter_kg > 0
                   AND b.entry_date BETWEEN %s AND %s $vend_b $loc_where_b
                ORDER BY date DESC
            ", $from, $to, $from, $to, $from, $to), ARRAY_A);
            $this->check_db('vendor_ledger_detail.purchases');

            // Payment transactions — include vendor_name
            $payment_rows = $db->get_results($db->prepare("
                SELECT 'payment' AS type, p.payment_date AS date, p.amount, p.method, p.note,
                       p.created_by, v.name AS vendor_name
                  FROM wp_mf_3_dp_vendor_payments p
                  LEFT JOIN wp_mf_3_dp_vendors v ON v.id = p.vendor_id
                 WHERE p.payment_date BETWEEN %s AND %s $vend_p
                 ORDER BY p.payment_date DESC
            ", $from, $to), ARRAY_A);
            $this->check_db('vendor_ledger_detail.payments');

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

            // Vendors list for dropdown (only those with activity)
            $vendor_list = $db->get_results("
                SELECT DISTINCT v.id, v.name FROM wp_mf_3_dp_vendors v
                WHERE v.is_active = 1 ORDER BY v.name", ARRAY_A);
            $this->check_db('vendor_ledger_detail.vendor_list');

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
            "SELECT id, name FROM wp_mf_3_dp_vendors WHERE is_active=1 ORDER BY name", ARRAY_A) ?? [];

        // Load current assignments
        $access_rows = $db->get_results(
            "SELECT vendor_id, location_id FROM wp_mf_3_dp_vendor_location_access", ARRAY_A) ?? [];
        $access = [];
        foreach ($access_rows as $row) {
            $access[(int)$row['vendor_id']][] = (int) $row['location_id'];
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
            "SELECT id, name FROM wp_mf_3_dp_vendors WHERE is_active=1", ARRAY_A) ?? [];

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
            $db->delete('wp_mf_3_dp_vendor_location_access', ['vendor_id' => $vid]);
            $locs = array_map('intval', $vloc_input[$vid] ?? []);
            foreach ($locs as $lid) {
                $db->insert('wp_mf_3_dp_vendor_location_access', [
                    'vendor_id'   => $vid,
                    'location_id' => $lid,
                ]);
            }
        }

        $this->log("Vendor locations saved by admin user ID " . get_current_user_id());

        wp_redirect(admin_url('admin.php?page=dairy-vendor-locations&saved=1'));
        exit;
    }

    // ════════════════════════════════════════════════════
    // MADHUSUDAN SALE
    // ════════════════════════════════════════════════════

    public function save_madhusudan_sale( WP_REST_Request $r ): WP_REST_Response {
        if ($e = $this->check_location_access($this->uid(), (int)$r->get_param('location_id'))) return $e;
        try {
            $db         = $this->db();
            $loc        = (int) $r['location_id'];
            $milk_usage = $r->get_param('milk_usage');
            $sale_rate  = (float) $r->get_param('sale_rate');

            if ($sale_rate <= 0)
                return $this->err('sale_rate must be greater than 0.');
            if (empty($milk_usage) || !is_array($milk_usage))
                return $this->err('milk_usage array is required.');

            // Validate vendor availability
            $total_used = 0;
            foreach ($milk_usage as $mu) {
                if (empty($mu['vendor_id']) || empty($mu['ff_milk_kg']))
                    return $this->err('Each milk_usage entry needs vendor_id and ff_milk_kg.');
                $avail = $this->vendor_milk_available($loc, (int)$mu['vendor_id']);
                if ((int)$mu['ff_milk_kg'] > $avail)
                    return $this->err("Vendor {$mu['vendor_id']}: requested {$mu['ff_milk_kg']} KG but only {$avail} KG available.");
                $total_used += (int) $mu['ff_milk_kg'];
            }

            $db->query('START TRANSACTION');

            $data = [
                'location_id'      => $loc,
                'entry_date'       => $r['entry_date'],
                'total_ff_milk_kg' => $total_used,
                'sale_rate'        => $this->d2($sale_rate),
                'created_by'       => $this->uid(),
            ];
            if ($db->insert('wp_mf_3_dp_madhusudan_sale', $data) === false) {
                $db->query('ROLLBACK');
                $this->log_db('save_madhusudan_sale', $db->last_error);
                return $this->err('Database error saving madhusudan sale.', 500);
            }
            $sale_id = $db->insert_id;
            $this->audit('wp_mf_3_dp_madhusudan_sale', $sale_id, 'INSERT', null, $data, $loc);

            foreach ($milk_usage as $mu) {
                $mu_data = [
                    'flow_type'   => 'madhusudan',
                    'flow_id'     => $sale_id,
                    'location_id' => $loc,
                    'entry_date'  => $r['entry_date'],
                    'vendor_id'   => (int) $mu['vendor_id'],
                    'ff_milk_kg'  => (int) $mu['ff_milk_kg'],
                    'created_by'  => $this->uid(),
                ];
                if ($db->insert('wp_mf_3_dp_milk_usage', $mu_data) === false) {
                    $db->query('ROLLBACK');
                    $this->log_db('save_madhusudan_sale.mu', $db->last_error);
                    return $this->err('Database error saving milk usage.', 500);
                }
                $this->audit('wp_mf_3_dp_milk_usage', $db->insert_id, 'INSERT', null, $mu_data, $loc);
            }

            $db->query('COMMIT');
            return $this->ok(['id' => $sale_id], 201);
        } catch (\Exception $e) { return $this->exc('save_madhusudan_sale', $e); }
    }

    public function get_madhusudan_sales( WP_REST_Request $r ): WP_REST_Response {
        if ($e = $this->validate_loc_date($r)) return $e;
        if ($e = $this->check_location_access($this->uid(), (int)$r['location_id'])) return $e;
        try {
            $rows = $this->db()->get_results($this->db()->prepare(
                "SELECT ms.*, l.name AS location_name
                   FROM wp_mf_3_dp_madhusudan_sale ms
                   JOIN wp_mf_3_dp_locations l ON l.id = ms.location_id
                  WHERE ms.location_id=%d AND ms.entry_date=%s ORDER BY ms.created_at DESC",
                (int)$r['location_id'], $r['entry_date']
            ), ARRAY_A);
            $this->check_db('get_madhusudan_sales');
            return $this->ok($rows);
        } catch (\Exception $e) { return $this->exc('get_madhusudan_sales', $e); }
    }

    public function get_madhusudan_pnl( WP_REST_Request $r ): WP_REST_Response {
        if ($e = $this->validate_loc($r)) return $e;
        if ($e = $this->check_location_access($this->uid(), (int)$r['location_id'])) return $e;
        try {
            $db  = $this->db();
            $loc = (int) $r['location_id'];

            $sales = $db->get_results($db->prepare(
                "SELECT id, entry_date, total_ff_milk_kg, sale_rate
                   FROM wp_mf_3_dp_madhusudan_sale
                  WHERE location_id=%d ORDER BY entry_date DESC, id DESC", $loc
            ), ARRAY_A);
            $this->check_db('get_madhusudan_pnl.sales');

            $rows = [];
            $grand_total_kg      = 0;
            $grand_total_revenue = 0.0;
            $grand_total_cost    = 0.0;

            foreach (($sales ?? []) as $s) {
                $sale_id = (int) $s['id'];
                $total_kg  = (int) $s['total_ff_milk_kg'];
                $rate      = (float) $s['sale_rate'];
                $revenue   = $total_kg * $rate;

                // Get milk_usage rows for this sale
                $usages = $db->get_results($db->prepare(
                    "SELECT vendor_id, ff_milk_kg FROM wp_mf_3_dp_milk_usage
                      WHERE flow_type='madhusudan' AND flow_id=%d AND location_id=%d",
                    $sale_id, $loc
                ), ARRAY_A);
                $this->check_db('get_madhusudan_pnl.usage');

                // Compute cost: per-vendor weighted average rate from milk_cream_production
                $cost = 0.0;
                foreach (($usages ?? []) as $u) {
                    $vid = (int) $u['vendor_id'];
                    $kg  = (int) $u['ff_milk_kg'];
                    $avg_rate = (float) $db->get_var($db->prepare(
                        "SELECT CASE WHEN SUM(input_ff_milk_kg) > 0
                                THEN SUM(input_ff_milk_kg * input_rate) / SUM(input_ff_milk_kg)
                                ELSE 0 END
                           FROM wp_mf_3_dp_milk_cream_production
                          WHERE vendor_id=%d AND location_id=%d AND input_ff_milk_kg > 0",
                        $vid, $loc
                    ));
                    $this->check_db('get_madhusudan_pnl.avg_rate');
                    $cost += $kg * $avg_rate;
                }

                $profit = $revenue - $cost;

                $rows[] = [
                    'id'               => $sale_id,
                    'entry_date'       => $s['entry_date'],
                    'total_ff_milk_kg' => $total_kg,
                    'sale_rate'        => $this->d2($rate),
                    'revenue'          => $this->d2($revenue),
                    'cost'             => $this->d2($cost),
                    'profit'           => $this->d2($profit),
                ];

                $grand_total_kg      += $total_kg;
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

    // ════════════════════════════════════════════════════
    // CURD PRODUCTION
    // ════════════════════════════════════════════════════

    public function save_curd_production( WP_REST_Request $r ): WP_REST_Response {
        if ($e = $this->check_location_access($this->uid(), (int)$r->get_param('location_id'))) return $e;
        try {
            $db         = $this->db();
            $loc        = (int) $r['location_id'];
            $milk_usage = $r->get_param('milk_usage');
            if (!is_array($milk_usage) || empty($milk_usage)) return $this->err('milk_usage is required.');

            // Validate milk availability per vendor
            foreach ($milk_usage as $mu) {
                $vid = (int) $mu['vendor_id'];
                $qty = (int) $mu['ff_milk_kg'];
                $avail = $this->vendor_milk_available($loc, $vid);
                if ($qty > $avail) return $this->err("Vendor $vid: only $avail KG available, requested $qty.");
            }

            $total_milk = 0;
            foreach ($milk_usage as $mu) $total_milk += (int) $mu['ff_milk_kg'];

            $db->query('START TRANSACTION');

            $data = [
                'location_id'       => $loc,
                'entry_date'        => $r['entry_date'],
                'output_cream_kg'   => (int) $r['output_cream_kg'],
                'output_cream_fat'  => $this->d1($r['output_cream_fat']),
                'output_curd_matka' => (int) $r['output_curd_matka'],
                'created_by'        => $this->uid(),
            ];
            if ($db->insert('wp_mf_3_dp_curd_production', $data) === false) {
                $db->query('ROLLBACK');
                $this->log_db('save_curd_production', $db->last_error);
                return $this->err('Database error saving curd production.', 500);
            }
            $prod_id = $db->insert_id;
            $this->audit('wp_mf_3_dp_curd_production', $prod_id, 'INSERT', null, $data, $loc);

            foreach ($milk_usage as $mu) {
                $mu_data = [
                    'flow_type'   => 'curd',
                    'flow_id'     => $prod_id,
                    'location_id' => $loc,
                    'entry_date'  => $r['entry_date'],
                    'vendor_id'   => (int) $mu['vendor_id'],
                    'ff_milk_kg'  => (int) $mu['ff_milk_kg'],
                ];
                if ($db->insert('wp_mf_3_dp_milk_usage', $mu_data) === false) {
                    $db->query('ROLLBACK');
                    $this->log_db('save_curd_production.mu', $db->last_error);
                    return $this->err('Database error saving milk usage.', 500);
                }
                $this->audit('wp_mf_3_dp_milk_usage', $db->insert_id, 'INSERT', null, $mu_data, $loc);
            }

            $db->query('COMMIT');
            return $this->ok(['id' => $prod_id], 201);
        } catch (\Exception $e) { return $this->exc('save_curd_production', $e); }
    }

    public function get_curd_productions( WP_REST_Request $r ): WP_REST_Response {
        if ($e = $this->validate_loc_date($r)) return $e;
        if ($e = $this->check_location_access($this->uid(), (int)$r['location_id'])) return $e;
        try {
            $rows = $this->db()->get_results($this->db()->prepare(
                "SELECT cp.*, l.name AS location_name
                   FROM wp_mf_3_dp_curd_production cp
                   JOIN wp_mf_3_dp_locations l ON l.id = cp.location_id
                  WHERE cp.location_id=%d AND cp.entry_date=%s ORDER BY cp.created_at DESC",
                (int)$r['location_id'], $r['entry_date']
            ), ARRAY_A);
            $this->check_db('get_curd_productions');
            return $this->ok($rows);
        } catch (\Exception $e) { return $this->exc('get_curd_productions', $e); }
    }

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

            // ── Sales per day (includes madhusudan) ──
            $sales_q = "SELECT entry_date AS d, ROUND(SUM(quantity_kg * rate), 2) AS amt
                          FROM wp_mf_3_dp_sales
                         WHERE entry_date BETWEEN %s AND %s $loc_cond
                         GROUP BY entry_date";
            $sales = $db->get_results($db->prepare($sales_q, $from, $to), ARRAY_A);
            $this->check_db('cashflow.sales');

            $mad_q = "SELECT entry_date AS d, ROUND(SUM(total_ff_milk_kg * sale_rate), 2) AS amt
                        FROM wp_mf_3_dp_madhusudan_sale
                       WHERE entry_date BETWEEN %s AND %s $loc_cond
                       GROUP BY entry_date";
            $mad = $db->get_results($db->prepare($mad_q, $from, $to), ARRAY_A);
            $this->check_db('cashflow.madhusudan');

            // ── Purchases per day (FF Milk + Cream + Butter + Ingredients) ──
            $purch_ff = "SELECT entry_date AS d, ROUND(SUM(input_ff_milk_kg * input_rate), 2) AS amt
                           FROM wp_mf_3_dp_milk_cream_production
                          WHERE input_ff_milk_kg > 0 AND entry_date BETWEEN %s AND %s $loc_cond
                          GROUP BY entry_date";
            $pff = $db->get_results($db->prepare($purch_ff, $from, $to), ARRAY_A);
            $this->check_db('cashflow.purch_ff');

            $purch_cr = "SELECT entry_date AS d, ROUND(SUM(input_cream_kg * input_rate), 2) AS amt
                           FROM wp_mf_3_dp_cream_butter_ghee
                          WHERE input_cream_kg > 0 AND entry_date BETWEEN %s AND %s $loc_cond
                          GROUP BY entry_date";
            $pcr = $db->get_results($db->prepare($purch_cr, $from, $to), ARRAY_A);
            $this->check_db('cashflow.purch_cr');

            $purch_bt = "SELECT entry_date AS d, ROUND(SUM(input_butter_kg * input_rate), 2) AS amt
                           FROM wp_mf_3_dp_butter_ghee
                          WHERE input_butter_kg > 0 AND entry_date BETWEEN %s AND %s $loc_cond
                          GROUP BY entry_date";
            $pbt = $db->get_results($db->prepare($purch_bt, $from, $to), ARRAY_A);
            $this->check_db('cashflow.purch_bt');

            $purch_in = "SELECT entry_date AS d, ROUND(SUM(quantity * rate), 2) AS amt
                           FROM wp_mf_3_dp_ingredient_purchase
                          WHERE entry_date BETWEEN %s AND %s $loc_cond
                          GROUP BY entry_date";
            $pin = $db->get_results($db->prepare($purch_in, $from, $to), ARRAY_A);
            $this->check_db('cashflow.purch_in');

            // ── Vendor payments per day ──
            $pay_cond = $loc ? '' : ''; // payments are global, not per-location
            $pay_q = "SELECT payment_date AS d, ROUND(SUM(amount), 2) AS amt
                        FROM wp_mf_3_dp_vendor_payments
                       WHERE payment_date BETWEEN %s AND %s
                       GROUP BY payment_date";
            $pay = $db->get_results($db->prepare($pay_q, $from, $to), ARRAY_A);
            $this->check_db('cashflow.payments');

            // ── Merge into daily map ──
            $days = [];
            $cur = new \DateTime($from);
            $end = new \DateTime($to);
            while ($cur <= $end) {
                $days[$cur->format('Y-m-d')] = ['sales' => 0, 'purchases' => 0, 'payments' => 0];
                $cur->modify('+1 day');
            }
            foreach ($sales as $r2) { $days[$r2['d']]['sales'] += (float)$r2['amt']; }
            foreach ($mad   as $r2) { $days[$r2['d']]['sales'] += (float)$r2['amt']; }
            foreach ($pff   as $r2) { $days[$r2['d']]['purchases'] += (float)$r2['amt']; }
            foreach ($pcr   as $r2) { $days[$r2['d']]['purchases'] += (float)$r2['amt']; }
            foreach ($pbt   as $r2) { $days[$r2['d']]['purchases'] += (float)$r2['amt']; }
            foreach ($pin   as $r2) { $days[$r2['d']]['purchases'] += (float)$r2['amt']; }
            foreach ($pay   as $r2) { $days[$r2['d']]['payments']  += (float)$r2['amt']; }

            // ── Build rows with beginning/end cash ──
            $rows = [];
            $cash = 0; // beginning cash starts at 0
            foreach ($days as $date => $v) {
                $beg = round($cash, 2);
                $end_cash = round($beg + $v['sales'] - $v['payments'], 2);
                $rows[] = [
                    'date'           => $date,
                    'beginning_cash' => $beg,
                    'sales'          => round($v['sales'], 2),
                    'purchases'      => round($v['purchases'], 2),
                    'payments'       => round($v['payments'], 2),
                    'end_cash'       => $end_cash,
                ];
                $cash = $end_cash;
            }

            return $this->ok([
                'from' => $from,
                'to'   => $to,
                'rows' => $rows,
            ]);
        } catch (\Exception $e) { return $this->exc('get_cashflow_report', $e); }
    }

    // ════════════════════════════════════════════════════
    // SALES LEDGER (flat transaction list with customer filter)
    // ════════════════════════════════════════════════════

    public function get_sales_ledger( WP_REST_Request $r ): WP_REST_Response {
        if ($e = $this->check_location_access($this->uid(), (int)$r['location_id'])) return $e;
        try {
            $db   = $this->db();
            $loc  = (int) $r['location_id'];
            $from = $r->get_param('from') ?: date('Y-m-d', strtotime('-29 days'));
            $to   = $r->get_param('to')   ?: date('Y-m-d');
            $cid  = (int) ($r->get_param('customer_id') ?? 0);

            $cust_cond = $cid ? $db->prepare(' AND s.customer_id = %d', $cid) : '';

            $rows = $db->get_results($db->prepare(
                "SELECT s.id, s.entry_date, c.name AS customer_name,
                        p.name AS product_name, p.unit,
                        s.quantity_kg, s.rate,
                        ROUND(s.quantity_kg * s.rate, 2) AS total
                   FROM wp_mf_3_dp_sales s
                   JOIN wp_mf_3_dp_customers c ON c.id = s.customer_id
                   JOIN wp_mf_3_dp_products p ON p.id = s.product_id
                  WHERE s.location_id = %d
                    AND s.entry_date BETWEEN %s AND %s
                    $cust_cond
                  ORDER BY s.entry_date DESC, c.name, p.name",
                $loc, $from, $to
            ), ARRAY_A);
            $this->check_db('get_sales_ledger');

            // ── Customers list for dropdown ──
            $customers = $db->get_results($db->prepare(
                "SELECT DISTINCT c.id, c.name
                   FROM wp_mf_3_dp_sales s
                   JOIN wp_mf_3_dp_customers c ON c.id = s.customer_id
                  WHERE s.location_id = %d AND s.entry_date BETWEEN %s AND %s
                  ORDER BY c.name",
                $loc, $from, $to
            ), ARRAY_A);
            $this->check_db('get_sales_ledger.customers');

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
        if ($e = $this->check_location_access($this->uid(), (int)$r['location_id'])) return $e;
        try {
            $db   = $this->db();
            $loc  = (int) $r['location_id'];
            // Optional single-date filter for Production page inline entries
            $single_date = $r->get_param('entry_date');
            if ($single_date && preg_match('/^\d{4}-\d{2}-\d{2}$/', $single_date)) {
                $from = $single_date;
                $to   = $single_date;
                $days = 1;
            } else {
                $days = (int) get_option('dairy_transaction_days', 7);
                $days = max(1, min(90, $days));
                $from = date('Y-m-d', strtotime("-{$days} days"));
                $to   = date('Y-m-d');
            }
            $this->log("prod_tx START: loc=$loc days=$days from=$from to=$to");

            // ── FF Milk Purchase & Processing ──────────────────────
            $milk = $db->get_results($db->prepare(
                "SELECT m.id, m.entry_date, m.created_at, m.created_by,
                        m.vendor_id, v.name AS vendor_name,
                        m.input_ff_milk_kg, m.input_snf, m.input_fat, m.input_rate,
                        m.input_ff_milk_used_kg,
                        m.output_skim_milk_kg, m.output_skim_snf,
                        m.output_cream_kg, m.output_cream_fat
                   FROM wp_mf_3_dp_milk_cream_production m
                   LEFT JOIN wp_mf_3_dp_vendors v ON v.id = m.vendor_id
                  WHERE m.location_id = %d AND m.entry_date BETWEEN %s AND %s
                  ORDER BY m.entry_date DESC, m.created_at DESC",
                $loc, $from, $to
            ), ARRAY_A);
            $this->check_db('prod_tx.milk');
            $this->log('prod_tx.milk count=' . count($milk ?? []));

            // ── Cream Purchase & Cream → Butter/Ghee ──────────────
            $cream = $db->get_results($db->prepare(
                "SELECT c.id, c.entry_date, c.created_at, c.created_by,
                        c.vendor_id, v.name AS vendor_name,
                        c.input_cream_kg, c.input_fat, c.input_rate,
                        c.input_cream_used_kg,
                        c.output_butter_kg, c.output_butter_fat, c.output_ghee_kg
                   FROM wp_mf_3_dp_cream_butter_ghee c
                   LEFT JOIN wp_mf_3_dp_vendors v ON v.id = c.vendor_id
                  WHERE c.location_id = %d AND c.entry_date BETWEEN %s AND %s
                  ORDER BY c.entry_date DESC, c.created_at DESC",
                $loc, $from, $to
            ), ARRAY_A);
            $this->check_db('prod_tx.cream');
            $this->log('prod_tx.cream count=' . count($cream ?? []));

            // ── Butter Purchase & Butter → Ghee ───────────────────
            $butter = $db->get_results($db->prepare(
                "SELECT b.id, b.entry_date, b.created_at, b.created_by,
                        b.vendor_id, v.name AS vendor_name,
                        b.input_butter_kg, b.input_fat, b.input_rate,
                        b.input_butter_used_kg, b.output_ghee_kg
                   FROM wp_mf_3_dp_butter_ghee b
                   LEFT JOIN wp_mf_3_dp_vendors v ON v.id = b.vendor_id
                  WHERE b.location_id = %d AND b.entry_date BETWEEN %s AND %s
                  ORDER BY b.entry_date DESC, b.created_at DESC",
                $loc, $from, $to
            ), ARRAY_A);
            $this->check_db('prod_tx.butter');
            $this->log('prod_tx.butter count=' . count($butter ?? []));

            // ── Dahi Production ────────────────────────────────────
            $dahi = $db->get_results($db->prepare(
                "SELECT id, entry_date, created_at, created_by,
                        input_smp_bags, input_culture_kg, input_protein_kg,
                        input_skim_milk_kg, input_container_count,
                        input_seal_count, output_container_count
                   FROM wp_mf_3_dp_dahi_production
                  WHERE location_id = %d AND entry_date BETWEEN %s AND %s
                  ORDER BY entry_date DESC, created_at DESC",
                $loc, $from, $to
            ), ARRAY_A);
            $this->check_db('prod_tx.dahi');
            $this->log('prod_tx.dahi count=' . count($dahi ?? []));

            // ── SMP / Protein / Culture Purchase ──────────────────
            $ingredients = $db->get_results($db->prepare(
                "SELECT i.id, i.entry_date, i.created_at, i.created_by,
                        i.product_id, p.name AS product_name, i.quantity,
                        IFNULL(i.rate, 0) AS rate
                   FROM wp_mf_3_dp_ingredient_purchase i
                   JOIN wp_mf_3_dp_products p ON p.id = i.product_id
                  WHERE i.location_id = %d AND i.entry_date BETWEEN %s AND %s
                  ORDER BY i.entry_date DESC, i.created_at DESC",
                $loc, $from, $to
            ), ARRAY_A);
            $this->check_db('prod_tx.ingredients');
            $this->log('prod_tx.ingredients count=' . count($ingredients ?? []));
            if (!empty($db->last_error)) $this->log('prod_tx.ingredients DB ERROR: ' . $db->last_error);
            // Log first row for inspection
            if (!empty($ingredients)) $this->log('prod_tx.ingredients first=' . wp_json_encode($ingredients[0]));
            else {
                // Log raw count directly from DB to isolate query vs location issue
                $raw_count = $db->get_var("SELECT COUNT(*) FROM wp_mf_3_dp_ingredient_purchase");
                $loc_count = $db->get_var($db->prepare("SELECT COUNT(*) FROM wp_mf_3_dp_ingredient_purchase WHERE location_id=%d", $loc));
                $date_count = $db->get_var($db->prepare("SELECT COUNT(*) FROM wp_mf_3_dp_ingredient_purchase WHERE location_id=%d AND entry_date BETWEEN %s AND %s", $loc, $from, $to));
                $this->log("prod_tx.ingredients diagnostic: total=$raw_count loc_match=$loc_count date_match=$date_count");
            }

            // ── Pouch Production ─────────────────────────────────
            $pouch = $db->get_results($db->prepare(
                "SELECT pp.id, pp.entry_date, pp.created_at, pp.created_by,
                        pp.output_cream_kg, pp.output_cream_fat,
                        COALESCE((SELECT SUM(mu.ff_milk_kg) FROM wp_mf_3_dp_milk_usage mu
                                  WHERE mu.flow_type='pouch' AND mu.flow_id=pp.id), 0) AS total_ff_milk_kg
                   FROM wp_mf_3_dp_pouch_production pp
                  WHERE pp.location_id = %d AND pp.entry_date BETWEEN %s AND %s
                  ORDER BY pp.entry_date DESC, pp.created_at DESC",
                $loc, $from, $to
            ), ARRAY_A);
            $this->check_db('prod_tx.pouch');

            // ── Curd Production ──────────────────────────────────────
            $curd = $db->get_results($db->prepare(
                "SELECT cp.id, cp.entry_date, cp.created_at, cp.created_by,
                        cp.output_cream_kg, cp.output_cream_fat, cp.output_curd_matka,
                        COALESCE((SELECT SUM(mu.ff_milk_kg) FROM wp_mf_3_dp_milk_usage mu
                                  WHERE mu.flow_type='curd' AND mu.flow_id=cp.id), 0) AS total_ff_milk_kg
                   FROM wp_mf_3_dp_curd_production cp
                  WHERE cp.location_id = %d AND cp.entry_date BETWEEN %s AND %s
                  ORDER BY cp.entry_date DESC, cp.created_at DESC",
                $loc, $from, $to
            ), ARRAY_A);
            $this->check_db('prod_tx.curd');

            // ── Madhusudan Sale ──────────────────────────────────────
            $madhusudan = $db->get_results($db->prepare(
                "SELECT ms.id, ms.entry_date, ms.created_at, ms.created_by,
                        ms.total_ff_milk_kg, ms.sale_rate
                   FROM wp_mf_3_dp_madhusudan_sale ms
                  WHERE ms.location_id = %d AND ms.entry_date BETWEEN %s AND %s
                  ORDER BY ms.entry_date DESC, ms.created_at DESC",
                $loc, $from, $to
            ), ARRAY_A);
            $this->check_db('prod_tx.madhusudan');

            // ── Resolve user first names ───────────────────────────
            $user_ids = array_unique(array_filter(array_merge(
                array_column($milk,   'created_by'),
                array_column($cream,  'created_by'),
                array_column($butter, 'created_by'),
                array_column($dahi,        'created_by'),
                array_column($ingredients, 'created_by'),
                array_column($pouch,       'created_by'),
                array_column($curd ?? [],  'created_by'),
                array_column($madhusudan ?? [], 'created_by'),
            )));
            $names = $this->resolve_first_names($user_ids);

            // ── Tag rows with type + user name ────────────────────
            $rows = [];
            foreach ($milk as $row) {
                $type = ((int)$row['input_ff_milk_kg'] > 0)
                    ? 'FF Milk Purchase' : 'FF Milk Processing';
                $rows[] = array_merge($row, [
                    'type'      => $type,
                    'user_name' => $names[$row['created_by']] ?? 'Unknown',
                ]);
            }
            foreach ($cream as $row) {
                $type = ((int)$row['input_cream_kg'] > 0)
                    ? 'Cream Purchase' : 'Cream Processing';
                $rows[] = array_merge($row, [
                    'type'      => $type,
                    'user_name' => $names[$row['created_by']] ?? 'Unknown',
                ]);
            }
            foreach ($butter as $row) {
                $type = ((int)$row['input_butter_kg'] > 0)
                    ? 'Butter Purchase' : 'Butter Processing';
                $rows[] = array_merge($row, [
                    'type'      => $type,
                    'user_name' => $names[$row['created_by']] ?? 'Unknown',
                ]);
            }
            foreach ($dahi as $row) {
                $rows[] = array_merge($row, [
                    'type'      => 'Dahi Production',
                    'user_name' => $names[$row['created_by']] ?? 'Unknown',
                ]);
            }
            foreach ($ingredients as $row) {
                $rows[] = array_merge($row, [
                    'type'      => 'Ingredient Purchase',
                    'user_name' => $names[$row['created_by']] ?? 'Unknown',
                ]);
            }
            foreach ($pouch as $row) {
                $rows[] = array_merge($row, [
                    'type'      => 'Pouch Production',
                    'user_name' => $names[$row['created_by']] ?? 'Unknown',
                ]);
            }
            foreach ($curd ?? [] as $row) {
                $rows[] = array_merge($row, [
                    'type'      => 'Curd Production',
                    'user_name' => $names[$row['created_by']] ?? 'Unknown',
                ]);
            }
            foreach ($madhusudan ?? [] as $row) {
                $rows[] = array_merge($row, [
                    'type'      => 'Madhusudan Sale',
                    'user_name' => $names[$row['created_by']] ?? 'Unknown',
                ]);
            }

            // Sort combined list: date desc, then created_at desc
            usort($rows, function($a, $b) {
                $d = strcmp($b['entry_date'], $a['entry_date']);
                return $d !== 0 ? $d : strcmp($b['created_at'], $a['created_at']);
            });

            $this->log('prod_tx TOTAL rows=' . count($rows));
            return $this->ok([
                'days' => $days,
                'from' => $from,
                'to'   => $to,
                'rows' => $rows,
            ]);
        } catch (\Exception $e) { return $this->exc('get_production_transactions', $e); }
    }

    // ════════════════════════════════════════════════════
    // SALES TRANSACTIONS — all sales for last N days
    // ════════════════════════════════════════════════════

    public function get_sales_transactions( WP_REST_Request $r ): WP_REST_Response {
        if ($e = $this->check_location_access($this->uid(), (int)$r['location_id'])) return $e;
        try {
            $db   = $this->db();
            $loc  = (int) $r['location_id'];
            $days = (int) get_option('dairy_transaction_days', 7);
            $days = max(1, min(90, $days));
            $from = date('Y-m-d', strtotime("-{$days} days"));
            $to   = date('Y-m-d');

            $rows = $db->get_results($db->prepare(
                "SELECT s.id, s.entry_date, s.quantity_kg, s.rate,
                        ROUND(s.quantity_kg * s.rate, 2) AS total,
                        s.created_at, s.created_by,
                        p.name AS product_name,
                        c.name AS customer_name
                   FROM wp_mf_3_dp_sales s
                   JOIN wp_mf_3_dp_products  p ON p.id = s.product_id
                   JOIN wp_mf_3_dp_customers c ON c.id = s.customer_id
                  WHERE s.location_id = %d
                    AND s.entry_date BETWEEN %s AND %s
                  ORDER BY s.entry_date DESC, s.created_at DESC",
                $loc, $from, $to
            ), ARRAY_A);
            $this->check_db('sales_tx');

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

            // 1. Sales total — all time, all locations
            $sales_total = (float) $db->get_var(
                "SELECT COALESCE(SUM(quantity_kg * rate), 0) FROM wp_mf_3_dp_sales"
            );
            $this->check_db('funds_report.sales');

            // 2. Stock value — latest day stock per location × estimated rates
            $rates_rows = $db->get_results(
                "SELECT product_id, rate FROM wp_mf_3_dp_estimated_rates", ARRAY_A);
            $this->check_db('funds_report.rates');
            $rates = [];
            foreach ($rates_rows as $rw) $rates[(int)$rw['product_id']] = (float)$rw['rate'];

            $locations = $db->get_results(
                "SELECT id FROM wp_mf_3_dp_locations WHERE is_active=1", ARRAY_A);
            $this->check_db('funds_report.locations');

            $products = $db->get_results(
                "SELECT id FROM wp_mf_3_dp_products WHERE is_active=1 ORDER BY sort_order", ARRAY_A);
            $this->check_db('funds_report.products');

            $from = date('Y-m-d', strtotime('-29 days'));
            $to   = date('Y-m-d');
            $stock_value = 0.0;

            foreach ($locations as $loc_row) {
                $loc = (int) $loc_row['id'];

                // Reuse shared stock movement SQL
                $prod_rows = $db->get_results($db->prepare(
                    $this->stock_movements_sql(),
                    $loc,$from,$to, $loc,$from,$to, $loc,$from,$to, $loc,$from,$to,
                    $loc,$from,$to, $loc,$from,$to, $loc,$from,$to, $loc,$from,$to,
                    $loc,$from,$to, $loc,$from,$to, $loc,$from,$to, $loc,$from,$to,
                    $loc,$from,$to, $loc,$from,$to, $loc,$from,$to, $loc,$from,$to,
                    $loc,$from,$to, $loc,$from,$to, $loc,$from,$to, $loc,$from,$to,
                    $loc,$from,$to, $loc,$from,$to
                ), ARRAY_A);
                $this->check_db("funds_report.stock_loc_$loc");

                $sales_rows = $db->get_results($db->prepare(
                    "SELECT entry_date, product_id, SUM(quantity_kg) AS qty FROM wp_mf_3_dp_sales WHERE location_id=%d AND entry_date BETWEEN %s AND %s GROUP BY entry_date, product_id",
                    $loc, $from, $to
                ), ARRAY_A);
                $this->check_db("funds_report.sales_loc_$loc");

                // Build daily movements
                $daily = [];
                foreach ($prod_rows  as $row) $daily[$row['entry_date']][$row['product_id']] = ($daily[$row['entry_date']][$row['product_id']] ?? 0) + (int)$row['qty'];
                foreach ($sales_rows as $row) $daily[$row['entry_date']][$row['product_id']] = ($daily[$row['entry_date']][$row['product_id']] ?? 0) - (int)$row['qty'];

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

            // 3. Total vendor due — all-time purchases minus all-time payments
            $total_purchases = (float) $db->get_var("
                SELECT COALESCE(SUM(amount), 0) FROM (
                    SELECT ROUND(input_ff_milk_kg * input_rate, 2) AS amount
                      FROM wp_mf_3_dp_milk_cream_production
                     WHERE vendor_id IS NOT NULL AND input_ff_milk_kg > 0
                    UNION ALL
                    SELECT ROUND(input_cream_kg * input_rate, 2) AS amount
                      FROM wp_mf_3_dp_cream_butter_ghee
                     WHERE vendor_id IS NOT NULL AND input_cream_kg > 0
                    UNION ALL
                    SELECT ROUND(input_butter_kg * input_rate, 2) AS amount
                      FROM wp_mf_3_dp_butter_ghee
                     WHERE vendor_id IS NOT NULL AND input_butter_kg > 0
                ) AS all_purchases
            ");
            $this->check_db('funds_report.purchases');

            $total_payments = (float) $db->get_var(
                "SELECT COALESCE(SUM(amount), 0) FROM wp_mf_3_dp_vendor_payments"
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
    // SHARED STOCK MOVEMENTS SQL
    // ════════════════════════════════════════════════════

    /**
     * Returns the UNION ALL SQL for all stock movements.
     * Requires 22 sets of ($loc,$from,$to) parameters.
     */
    private function stock_movements_sql(): string {
        return "
            -- FF Milk received (+)
            SELECT entry_date, 1 AS product_id, CAST(input_ff_milk_kg AS SIGNED) AS qty
              FROM wp_mf_3_dp_milk_cream_production WHERE location_id=%d AND entry_date BETWEEN %s AND %s
            -- FF Milk consumed via milk_usage (all flows) (-)
            UNION ALL SELECT entry_date, 1, -CAST(ff_milk_kg AS SIGNED)
              FROM wp_mf_3_dp_milk_usage WHERE location_id=%d AND entry_date BETWEEN %s AND %s
            -- Skim Milk produced (+)
            UNION ALL SELECT entry_date, 2, CAST(output_skim_milk_kg AS SIGNED)
              FROM wp_mf_3_dp_milk_cream_production WHERE location_id=%d AND entry_date BETWEEN %s AND %s
            -- Cream produced in Flow1 (+)
            UNION ALL SELECT entry_date, 3, CAST(output_cream_kg AS SIGNED)
              FROM wp_mf_3_dp_milk_cream_production WHERE location_id=%d AND entry_date BETWEEN %s AND %s
            -- Cream produced in Flow5 Pouch (+)
            UNION ALL SELECT entry_date, 3, CAST(output_cream_kg AS SIGNED)
              FROM wp_mf_3_dp_pouch_production WHERE location_id=%d AND entry_date BETWEEN %s AND %s
            -- Cream consumed in Flow2 (-)
            UNION ALL SELECT entry_date, 3, -CAST(input_cream_used_kg AS SIGNED)
              FROM wp_mf_3_dp_cream_butter_ghee WHERE location_id=%d AND entry_date BETWEEN %s AND %s
            -- Butter produced in Flow2 (+)
            UNION ALL SELECT entry_date, 4, CAST(output_butter_kg AS SIGNED)
              FROM wp_mf_3_dp_cream_butter_ghee WHERE location_id=%d AND entry_date BETWEEN %s AND %s
            -- Butter consumed in Flow3 (-)
            UNION ALL SELECT entry_date, 4, -CAST(input_butter_used_kg AS SIGNED)
              FROM wp_mf_3_dp_butter_ghee WHERE location_id=%d AND entry_date BETWEEN %s AND %s
            -- Ghee produced in Flow2 (+)
            UNION ALL SELECT entry_date, 5, CAST(output_ghee_kg AS SIGNED)
              FROM wp_mf_3_dp_cream_butter_ghee WHERE location_id=%d AND entry_date BETWEEN %s AND %s
            -- Ghee produced in Flow3 (+)
            UNION ALL SELECT entry_date, 5, CAST(output_ghee_kg AS SIGNED)
              FROM wp_mf_3_dp_butter_ghee WHERE location_id=%d AND entry_date BETWEEN %s AND %s
            -- Skim Milk consumed by Dahi (-)
            UNION ALL SELECT entry_date, 2, -CAST(input_skim_milk_kg AS SIGNED)
              FROM wp_mf_3_dp_dahi_production WHERE location_id=%d AND entry_date BETWEEN %s AND %s
            -- Dahi containers produced (+)
            UNION ALL SELECT entry_date, 6, CAST(output_container_count AS SIGNED)
              FROM wp_mf_3_dp_dahi_production WHERE location_id=%d AND entry_date BETWEEN %s AND %s
            -- SMP purchased (+)
            UNION ALL SELECT entry_date, 7, CAST(quantity AS SIGNED)
              FROM wp_mf_3_dp_ingredient_purchase WHERE product_id=7 AND location_id=%d AND entry_date BETWEEN %s AND %s
            -- SMP consumed by Dahi (-)
            UNION ALL SELECT entry_date, 7, -CAST(input_smp_bags AS SIGNED)
              FROM wp_mf_3_dp_dahi_production WHERE location_id=%d AND entry_date BETWEEN %s AND %s
            -- Protein purchased (+)
            UNION ALL SELECT entry_date, 8, CAST(quantity AS SIGNED)
              FROM wp_mf_3_dp_ingredient_purchase WHERE product_id=8 AND location_id=%d AND entry_date BETWEEN %s AND %s
            -- Protein consumed by Dahi (-)
            UNION ALL SELECT entry_date, 8, -CAST(input_protein_kg AS SIGNED)
              FROM wp_mf_3_dp_dahi_production WHERE location_id=%d AND entry_date BETWEEN %s AND %s
            -- Culture purchased (+)
            UNION ALL SELECT entry_date, 9, CAST(quantity AS SIGNED)
              FROM wp_mf_3_dp_ingredient_purchase WHERE product_id=9 AND location_id=%d AND entry_date BETWEEN %s AND %s
            -- Culture consumed by Dahi (-)
            UNION ALL SELECT entry_date, 9, -CAST(input_culture_kg AS SIGNED)
              FROM wp_mf_3_dp_dahi_production WHERE location_id=%d AND entry_date BETWEEN %s AND %s
            -- Cream produced in Curd flow (+)
            UNION ALL SELECT entry_date, 3, CAST(output_cream_kg AS SIGNED)
              FROM wp_mf_3_dp_curd_production WHERE location_id=%d AND entry_date BETWEEN %s AND %s
            -- Curd produced (+)
            UNION ALL SELECT entry_date, 10, CAST(output_curd_matka AS SIGNED)
              FROM wp_mf_3_dp_curd_production WHERE location_id=%d AND entry_date BETWEEN %s AND %s
        ";
    }

    // ════════════════════════════════════════════════════
    // MILK AVAILABILITY — per-vendor available FF Milk
    // ════════════════════════════════════════════════════

    public function get_milk_availability( WP_REST_Request $r ): WP_REST_Response {
        if ($e = $this->validate_loc($r)) return $e;
        if ($e = $this->check_location_access($this->uid(), (int)$r['location_id'])) return $e;
        try {
            $db  = $this->db();
            $loc = (int) $r['location_id'];
            $as_of = $r['as_of'] ?? null;

            // Purchased per vendor — optionally up to a given date
            if ($as_of) {
                $purchased = $db->get_results($db->prepare(
                    "SELECT m.vendor_id, v.name AS vendor_name,
                            COALESCE(SUM(m.input_ff_milk_kg),0) AS purchased
                       FROM wp_mf_3_dp_milk_cream_production m
                       JOIN wp_mf_3_dp_vendors v ON v.id = m.vendor_id
                      WHERE m.location_id=%d AND m.input_ff_milk_kg > 0 AND m.vendor_id IS NOT NULL
                        AND m.entry_date <= %s
                      GROUP BY m.vendor_id, v.name", $loc, $as_of), ARRAY_A);
            } else {
                $purchased = $db->get_results($db->prepare(
                    "SELECT m.vendor_id, v.name AS vendor_name,
                            COALESCE(SUM(m.input_ff_milk_kg),0) AS purchased
                       FROM wp_mf_3_dp_milk_cream_production m
                       JOIN wp_mf_3_dp_vendors v ON v.id = m.vendor_id
                      WHERE m.location_id=%d AND m.input_ff_milk_kg > 0 AND m.vendor_id IS NOT NULL
                      GROUP BY m.vendor_id, v.name", $loc), ARRAY_A);
            }
            $this->check_db('milk_availability.purchased');

            // Consumed per vendor via milk_usage — optionally up to a given date
            if ($as_of) {
                $consumed = $db->get_results($db->prepare(
                    "SELECT mu.vendor_id, COALESCE(SUM(mu.ff_milk_kg),0) AS consumed
                       FROM wp_mf_3_dp_milk_usage mu
                       JOIN wp_mf_3_dp_milk_cream_production m ON m.id = mu.flow_id AND mu.flow_type = 'milk_cream'
                      WHERE mu.location_id=%d AND m.entry_date <= %s
                      GROUP BY mu.vendor_id
                     UNION ALL
                     SELECT mu.vendor_id, COALESCE(SUM(mu.ff_milk_kg),0) AS consumed
                       FROM wp_mf_3_dp_milk_usage mu
                       JOIN wp_mf_3_dp_pouch_production pp ON pp.id = mu.flow_id AND mu.flow_type = 'pouch'
                      WHERE mu.location_id=%d AND pp.entry_date <= %s
                      GROUP BY mu.vendor_id
                     UNION ALL
                     SELECT mu.vendor_id, COALESCE(SUM(mu.ff_milk_kg),0) AS consumed
                       FROM wp_mf_3_dp_milk_usage mu
                       JOIN wp_mf_3_dp_madhusudan_sale ms ON ms.id = mu.flow_id AND mu.flow_type = 'madhusudan'
                      WHERE mu.location_id=%d AND ms.entry_date <= %s
                      GROUP BY mu.vendor_id
                     UNION ALL
                     SELECT mu.vendor_id, COALESCE(SUM(mu.ff_milk_kg),0) AS consumed
                       FROM wp_mf_3_dp_milk_usage mu
                       JOIN wp_mf_3_dp_curd_production cp ON cp.id = mu.flow_id AND mu.flow_type = 'curd'
                      WHERE mu.location_id=%d AND cp.entry_date <= %s
                      GROUP BY mu.vendor_id",
                    $loc, $as_of, $loc, $as_of, $loc, $as_of, $loc, $as_of), ARRAY_A);
            } else {
                $consumed = $db->get_results($db->prepare(
                    "SELECT vendor_id, COALESCE(SUM(ff_milk_kg),0) AS consumed
                       FROM wp_mf_3_dp_milk_usage WHERE location_id=%d
                      GROUP BY vendor_id", $loc), ARRAY_A);
            }
            $this->check_db('milk_availability.consumed');

            $consumed_map = [];
            foreach ($consumed as $c) $consumed_map[(int)$c['vendor_id']] = ($consumed_map[(int)$c['vendor_id']] ?? 0) + (int)$c['consumed'];

            $result = [];
            foreach ($purchased as $p) {
                $vid   = (int) $p['vendor_id'];
                $avail = (int) $p['purchased'] - ($consumed_map[$vid] ?? 0);
                if ($avail > 0) {
                    $result[] = [
                        'vendor_id'    => $vid,
                        'vendor_name'  => $p['vendor_name'],
                        'available_kg' => $avail,
                    ];
                }
            }
            return $this->ok($result);
        } catch (\Exception $e) { return $this->exc('get_milk_availability', $e); }
    }

    // ════════════════════════════════════════════════════
    // POUCH TYPES CRUD
    // ════════════════════════════════════════════════════

    public function get_pouch_types(): WP_REST_Response {
        try {
            $rows = $this->db()->get_results(
                "SELECT id, name, milk_per_pouch, pouches_per_crate, is_active FROM wp_mf_3_dp_pouch_types ORDER BY name",
                ARRAY_A);
            $this->check_db('get_pouch_types');
            return $this->ok($rows ?? []);
        } catch (\Exception $e) { return $this->exc('get_pouch_types', $e); }
    }

    public function save_pouch_type( WP_REST_Request $r ): WP_REST_Response {
        try {
            $name  = trim($r->get_param('name') ?? '');
            $milk  = (float) ($r->get_param('milk_per_pouch') ?? 0);
            $ppc   = (int)   ($r->get_param('pouches_per_crate') ?? 12);
            if (empty($name)) return $this->err('name is required.');
            if ($milk <= 0)   return $this->err('milk_per_pouch must be > 0.');
            if ($ppc  <= 0)   return $this->err('pouches_per_crate must be > 0.');

            $db   = $this->db();
            $data = [
                'name'             => $name,
                'milk_per_pouch'   => $this->d2($milk),
                'pouches_per_crate'=> $ppc,
            ];
            if ($db->insert('wp_mf_3_dp_pouch_types', $data) === false) {
                $this->log_db('save_pouch_type', $db->last_error);
                return $this->err('Database error (duplicate name?).', 500);
            }
            $id = $db->insert_id;
            $this->audit('wp_mf_3_dp_pouch_types', $id, 'INSERT', null, $data);
            return $this->ok(['id' => $id], 201);
        } catch (\Exception $e) { return $this->exc('save_pouch_type', $e); }
    }

    public function update_pouch_type( WP_REST_Request $r ): WP_REST_Response {
        try {
            $id = (int) $r['id'];
            if (!$id) return $this->err('id is required.');
            $db = $this->db();
            $old = $db->get_row($db->prepare(
                "SELECT * FROM wp_mf_3_dp_pouch_types WHERE id=%d", $id), ARRAY_A);
            if (!$old) return $this->err('Pouch type not found.', 404);

            $name   = trim($r->get_param('name') ?? $old['name']);
            $milk   = $r->get_param('milk_per_pouch') !== null ? (float)$r->get_param('milk_per_pouch') : (float)$old['milk_per_pouch'];
            $ppc    = $r->get_param('pouches_per_crate') !== null ? (int)$r->get_param('pouches_per_crate') : (int)$old['pouches_per_crate'];
            $active = $r->get_param('is_active') !== null ? (int)$r->get_param('is_active') : (int)$old['is_active'];

            $data = [
                'name'              => $name,
                'milk_per_pouch'    => $this->d2($milk),
                'pouches_per_crate' => $ppc,
                'is_active'         => $active,
            ];
            $db->update('wp_mf_3_dp_pouch_types', $data, ['id' => $id]);
            $this->check_db('update_pouch_type');
            $new = $db->get_row($db->prepare(
                "SELECT * FROM wp_mf_3_dp_pouch_types WHERE id=%d", $id), ARRAY_A);
            $this->audit('wp_mf_3_dp_pouch_types', $id, 'UPDATE', $old, $new);
            return $this->ok(['id' => $id]);
        } catch (\Exception $e) { return $this->exc('update_pouch_type', $e); }
    }

    // ════════════════════════════════════════════════════
    // FLOW 5 - FF Milk → Cream + Pouches
    // ════════════════════════════════════════════════════

    public function get_pouch_production( WP_REST_Request $r ): WP_REST_Response {
        if ($e = $this->validate_loc_date($r)) return $e;
        if ($e = $this->check_location_access($this->uid(), (int)$r['location_id'])) return $e;
        try {
            $db  = $this->db();
            $loc = (int) $r['location_id'];
            $dt  = $r['entry_date'];
            $rows = $db->get_results($db->prepare(
                "SELECT pp.*, l.name AS location_name
                   FROM wp_mf_3_dp_pouch_production pp
                   JOIN wp_mf_3_dp_locations l ON l.id = pp.location_id
                  WHERE pp.location_id=%d AND pp.entry_date=%s
                  ORDER BY pp.created_at DESC", $loc, $dt), ARRAY_A);
            $this->check_db('get_pouch_production');

            // Attach lines and milk_usage to each row
            foreach ($rows as &$row) {
                $pid = (int) $row['id'];
                $row['lines'] = $db->get_results($db->prepare(
                    "SELECT ppl.pouch_type_id, pt.name AS pouch_type_name,
                            pt.milk_per_pouch, pt.pouches_per_crate, ppl.crate_count
                       FROM wp_mf_3_dp_pouch_production_lines ppl
                       JOIN wp_mf_3_dp_pouch_types pt ON pt.id = ppl.pouch_type_id
                      WHERE ppl.pouch_production_id=%d", $pid), ARRAY_A);
                $row['milk_usage'] = $db->get_results($db->prepare(
                    "SELECT mu.vendor_id, v.name AS vendor_name, mu.ff_milk_kg
                       FROM wp_mf_3_dp_milk_usage mu
                       JOIN wp_mf_3_dp_vendors v ON v.id = mu.vendor_id
                      WHERE mu.flow_type='pouch' AND mu.flow_id=%d", $pid), ARRAY_A);
            }
            unset($row);
            return $this->ok($rows);
        } catch (\Exception $e) { return $this->exc('get_pouch_production', $e); }
    }

    public function save_pouch_production( WP_REST_Request $r ): WP_REST_Response {
        if ($e = $this->check_location_access($this->uid(), (int)$r->get_param('location_id'))) return $e;
        try {
            $db         = $this->db();
            $loc        = (int) $r['location_id'];
            $milk_usage = $r->get_param('milk_usage');
            $pouch_lines= $r->get_param('pouch_lines');

            if (empty($milk_usage) || !is_array($milk_usage))
                return $this->err('milk_usage array is required.');
            if (empty($pouch_lines) || !is_array($pouch_lines))
                return $this->err('pouch_lines array is required.');

            // Validate cream output
            $cream_fat = $r->get_param('output_cream_fat');
            if ($cream_fat !== null && (float)$cream_fat >= 10)
                return $this->err('output_cream_fat must be < 10.');

            // Validate vendor availability
            $total_milk = 0;
            foreach ($milk_usage as $mu) {
                if (empty($mu['vendor_id']) || empty($mu['ff_milk_kg']))
                    return $this->err('Each milk_usage entry needs vendor_id and ff_milk_kg.');
                $avail = $this->vendor_milk_available($loc, (int)$mu['vendor_id']);
                if ((int)$mu['ff_milk_kg'] > $avail)
                    return $this->err("Vendor {$mu['vendor_id']}: requested {$mu['ff_milk_kg']} KG but only {$avail} KG available.");
                $total_milk += (int) $mu['ff_milk_kg'];
            }

            $db->query('START TRANSACTION');

            // Insert pouch_production header
            $data = [
                'location_id'      => $loc,
                'entry_date'       => $r['entry_date'],
                'output_cream_kg'  => (int) ($r->get_param('output_cream_kg') ?? 0),
                'output_cream_fat' => $this->d1($cream_fat ?? 0),
                'created_by'       => $this->uid(),
            ];
            if ($db->insert('wp_mf_3_dp_pouch_production', $data) === false) {
                $db->query('ROLLBACK');
                $this->log_db('save_pouch_production', $db->last_error);
                return $this->err('Database error saving pouch production.', 500);
            }
            $pp_id = $db->insert_id;
            $this->audit('wp_mf_3_dp_pouch_production', $pp_id, 'INSERT', null, $data, $loc);

            // Insert pouch lines
            foreach ($pouch_lines as $line) {
                $line_data = [
                    'pouch_production_id' => $pp_id,
                    'pouch_type_id'       => (int) $line['pouch_type_id'],
                    'crate_count'         => (int) $line['crate_count'],
                ];
                if ($db->insert('wp_mf_3_dp_pouch_production_lines', $line_data) === false) {
                    $db->query('ROLLBACK');
                    $this->log_db('save_pouch_production.line', $db->last_error);
                    return $this->err('Database error saving pouch line.', 500);
                }
                $this->audit('wp_mf_3_dp_pouch_production_lines', $db->insert_id, 'INSERT', null, $line_data, $loc);
            }

            // Insert milk_usage rows
            foreach ($milk_usage as $mu) {
                $mu_data = [
                    'flow_type'   => 'pouch',
                    'flow_id'     => $pp_id,
                    'location_id' => $loc,
                    'entry_date'  => $r['entry_date'],
                    'vendor_id'   => (int) $mu['vendor_id'],
                    'ff_milk_kg'  => (int) $mu['ff_milk_kg'],
                    'created_by'  => $this->uid(),
                ];
                if ($db->insert('wp_mf_3_dp_milk_usage', $mu_data) === false) {
                    $db->query('ROLLBACK');
                    $this->log_db('save_pouch_production.mu', $db->last_error);
                    return $this->err('Database error saving milk usage.', 500);
                }
                $this->audit('wp_mf_3_dp_milk_usage', $db->insert_id, 'INSERT', null, $mu_data, $loc);
            }

            $db->query('COMMIT');
            return $this->ok(['id' => $pp_id], 201);
        } catch (\Exception $e) { return $this->exc('save_pouch_production', $e); }
    }

    // ════════════════════════════════════════════════════
    // POUCH STOCK — per-type balance
    // ════════════════════════════════════════════════════

    public function get_pouch_stock( WP_REST_Request $r ): WP_REST_Response {
        if ($e = $this->validate_loc($r)) return $e;
        if ($e = $this->check_location_access($this->uid(), (int)$r['location_id'])) return $e;
        try {
            $db  = $this->db();
            $loc = (int) $r['location_id'];
            $rows = $db->get_results($db->prepare(
                "SELECT pt.id AS pouch_type_id, pt.name, pt.milk_per_pouch, pt.pouches_per_crate,
                        COALESCE(SUM(ppl.crate_count), 0) AS crate_count
                   FROM wp_mf_3_dp_pouch_types pt
                   LEFT JOIN wp_mf_3_dp_pouch_production_lines ppl
                        ON ppl.pouch_type_id = pt.id
                   LEFT JOIN wp_mf_3_dp_pouch_production pp
                        ON pp.id = ppl.pouch_production_id AND pp.location_id = %d
                  WHERE pt.is_active = 1
                  GROUP BY pt.id, pt.name, pt.milk_per_pouch, pt.pouches_per_crate
                  ORDER BY pt.name", $loc), ARRAY_A);
            $this->check_db('get_pouch_stock');
            return $this->ok($rows ?? []);
        } catch (\Exception $e) { return $this->exc('get_pouch_stock', $e); }
    }

    public function get_pouch_rates(): WP_REST_Response {
        try {
            $rows = $this->db()->get_results(
                "SELECT pr.pouch_type_id, pt.name, pr.rate_per_crate
                   FROM wp_mf_3_dp_pouch_rates pr
                   JOIN wp_mf_3_dp_pouch_types pt ON pt.id = pr.pouch_type_id
                  WHERE pt.is_active = 1
                  ORDER BY pt.name", ARRAY_A);
            $this->check_db('get_pouch_rates');
            return $this->ok($rows ?? []);
        } catch (\Exception $e) { return $this->exc('get_pouch_rates', $e); }
    }

    public function save_pouch_rates( WP_REST_Request $r ): WP_REST_Response {
        try {
            $rates = $r->get_param('rates');
            if (!is_array($rates) || empty($rates)) return $this->err('rates array is required.');
            $db = $this->db();
            foreach ($rates as $rate) {
                $ptid = (int) ($rate['pouch_type_id'] ?? 0);
                $rpc  = $this->d2($rate['rate_per_crate'] ?? 0);
                if ($ptid <= 0) continue;
                $old = $db->get_row($db->prepare(
                    "SELECT * FROM wp_mf_3_dp_pouch_rates WHERE pouch_type_id=%d", $ptid), ARRAY_A);
                $db->query($db->prepare(
                    "INSERT INTO wp_mf_3_dp_pouch_rates (pouch_type_id, rate_per_crate)
                     VALUES (%d, %s) ON DUPLICATE KEY UPDATE rate_per_crate = VALUES(rate_per_crate)",
                    $ptid, $rpc));
                $this->check_db('save_pouch_rates');
                $new = $db->get_row($db->prepare(
                    "SELECT * FROM wp_mf_3_dp_pouch_rates WHERE pouch_type_id=%d", $ptid), ARRAY_A);
                $action = $old ? 'UPDATE' : 'INSERT';
                $this->audit('wp_mf_3_dp_pouch_rates', $ptid, $action, $old, $new);
            }
            return $this->ok(['saved' => count($rates)]);
        } catch (\Exception $e) { return $this->exc('save_pouch_rates', $e); }
    }

    public function get_pouch_pnl( WP_REST_Request $r ): WP_REST_Response {
        if ($e = $this->validate_loc($r)) return $e;
        if ($e = $this->check_location_access($this->uid(), (int)$r['location_id'])) return $e;
        try {
            $db  = $this->db();
            $loc = (int) $r['location_id'];

            // Get all pouch productions for this location
            $prods = $db->get_results($db->prepare(
                "SELECT id, entry_date, created_at
                   FROM wp_mf_3_dp_pouch_production
                  WHERE location_id = %d
                  ORDER BY entry_date DESC, id DESC", $loc), ARRAY_A);
            $this->check_db('pouch_pnl.prods');

            // Get pouch rates
            $rate_rows = $db->get_results(
                "SELECT pouch_type_id, rate_per_crate FROM wp_mf_3_dp_pouch_rates", ARRAY_A);
            $this->check_db('pouch_pnl.rates');
            $rates = [];
            foreach ($rate_rows as $rr) $rates[(int)$rr['pouch_type_id']] = (float)$rr['rate_per_crate'];

            // Get pouch type info
            $pt_rows = $db->get_results(
                "SELECT id, name, milk_per_pouch, pouches_per_crate FROM wp_mf_3_dp_pouch_types", ARRAY_A);
            $pts = [];
            foreach ($pt_rows as $p) $pts[(int)$p['id']] = $p;

            $rows = [];
            $grand_revenue = 0.0;
            $grand_cost    = 0.0;
            $grand_crates  = 0;

            foreach (($prods ?? []) as $prod) {
                $pp_id = (int) $prod['id'];

                // Get pouch lines
                $lines = $db->get_results($db->prepare(
                    "SELECT pouch_type_id, crate_count FROM wp_mf_3_dp_pouch_production_lines
                      WHERE pouch_production_id = %d", $pp_id), ARRAY_A);
                $this->check_db('pouch_pnl.lines');

                // Calculate revenue per line
                $revenue = 0.0;
                $total_crates = 0;
                $line_details = [];
                foreach (($lines ?? []) as $ln) {
                    $ptid   = (int) $ln['pouch_type_id'];
                    $crates = (int) $ln['crate_count'];
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

                // Get milk usage for cost calculation
                $usages = $db->get_results($db->prepare(
                    "SELECT vendor_id, ff_milk_kg FROM wp_mf_3_dp_milk_usage
                      WHERE flow_type='pouch' AND flow_id=%d AND location_id=%d",
                    $pp_id, $loc), ARRAY_A);
                $this->check_db('pouch_pnl.usage');

                $cost = 0.0;
                foreach (($usages ?? []) as $u) {
                    $vid = (int) $u['vendor_id'];
                    $kg  = (int) $u['ff_milk_kg'];
                    $avg_rate = (float) $db->get_var($db->prepare(
                        "SELECT CASE WHEN SUM(input_ff_milk_kg) > 0
                                THEN SUM(input_ff_milk_kg * input_rate) / SUM(input_ff_milk_kg)
                                ELSE 0 END
                           FROM wp_mf_3_dp_milk_cream_production
                          WHERE vendor_id=%d AND location_id=%d AND input_ff_milk_kg > 0",
                        $vid, $loc));
                    $this->check_db('pouch_pnl.avg_rate');
                    $cost += $kg * $avg_rate;
                }

                $profit = $revenue - $cost;
                $rows[] = [
                    'id'           => $pp_id,
                    'entry_date'   => $prod['entry_date'],
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