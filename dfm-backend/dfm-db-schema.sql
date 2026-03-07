-- Dairy Farm Management — Schema + Sample Data
-- Compatible with MariaDB 10.6+ / MySQL 8.0+
-- Database: bitnami_wordpress (or your WordPress database)
--
-- SETUP:
--   1. Import this file into your WordPress database
--   2. Install the dairy-production-api and dairy-jwt-auth plugins
--   3. Sample data assigns all access to user_id 1 (your WordPress admin)
--   4. To add more users, create them in WordPress and add rows to
--      user_location_access and user_flags

SET NAMES utf8mb4;
SET FOREIGN_KEY_CHECKS = 0;

-- ============================================================
-- SCHEMA
-- ============================================================

DROP TABLE IF EXISTS `wp_mf_3_dp_vendor_payments`;
DROP TABLE IF EXISTS `wp_mf_3_dp_vendor_location_access`;
DROP TABLE IF EXISTS `wp_mf_3_dp_audit_log`;
DROP TABLE IF EXISTS `wp_mf_3_dp_estimated_rates`;
DROP TABLE IF EXISTS `wp_mf_3_dp_ingredient_purchase`;
DROP TABLE IF EXISTS `wp_mf_3_dp_sales`;
DROP TABLE IF EXISTS `wp_mf_3_dp_dahi_production`;
DROP TABLE IF EXISTS `wp_mf_3_dp_butter_ghee`;
DROP TABLE IF EXISTS `wp_mf_3_dp_cream_butter_ghee`;
DROP TABLE IF EXISTS `wp_mf_3_dp_milk_cream_production`;
DROP TABLE IF EXISTS `wp_mf_3_dp_user_flags`;
DROP TABLE IF EXISTS `wp_mf_3_dp_user_location_access`;
DROP TABLE IF EXISTS `wp_mf_3_dp_vendors`;
DROP TABLE IF EXISTS `wp_mf_3_dp_customers`;
DROP TABLE IF EXISTS `wp_mf_3_dp_products`;
DROP TABLE IF EXISTS `wp_mf_3_dp_locations`;

-- Locations
CREATE TABLE `wp_mf_3_dp_locations` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `name` varchar(100) NOT NULL,
  `code` varchar(20) NOT NULL,
  `is_active` tinyint(1) NOT NULL DEFAULT 1,
  `created_at` timestamp NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`id`),
  UNIQUE KEY `code` (`code`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Products (fixed IDs 1-9)
CREATE TABLE `wp_mf_3_dp_products` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `name` varchar(100) NOT NULL,
  `unit` varchar(20) NOT NULL DEFAULT 'KG',
  `sort_order` tinyint(3) unsigned NOT NULL DEFAULT 0,
  `is_active` tinyint(1) NOT NULL DEFAULT 1,
  `created_at` timestamp NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Customers
CREATE TABLE `wp_mf_3_dp_customers` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `name` varchar(100) NOT NULL,
  `is_active` tinyint(1) NOT NULL DEFAULT 1,
  `created_at` timestamp NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_customer_name` (`name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Vendors
CREATE TABLE `wp_mf_3_dp_vendors` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `name` varchar(100) NOT NULL,
  `is_active` tinyint(1) NOT NULL DEFAULT 1,
  `created_at` timestamp NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_vendor_name` (`name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- User → Location access
CREATE TABLE `wp_mf_3_dp_user_location_access` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `user_id` bigint(20) unsigned NOT NULL,
  `location_id` int(10) unsigned NOT NULL,
  `created_at` timestamp NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_user_location` (`user_id`,`location_id`),
  KEY `fk_ula_loc` (`location_id`),
  CONSTRAINT `fk_ula_loc` FOREIGN KEY (`location_id`) REFERENCES `wp_mf_3_dp_locations` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- User flags (user_id is PK, no auto-increment id)
CREATE TABLE `wp_mf_3_dp_user_flags` (
  `user_id` bigint(20) unsigned NOT NULL,
  `can_finance` tinyint(1) NOT NULL DEFAULT 0,
  `can_anomaly` tinyint(1) NOT NULL DEFAULT 0,
  `updated_at` timestamp NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`user_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Flow 1: FF Milk → Skim Milk + Cream
CREATE TABLE `wp_mf_3_dp_milk_cream_production` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `location_id` int(10) unsigned NOT NULL,
  `vendor_id` int(10) unsigned DEFAULT NULL,
  `entry_date` date NOT NULL,
  `input_ff_milk_kg` int(10) unsigned NOT NULL,
  `input_snf` decimal(4,1) NOT NULL,
  `input_fat` decimal(4,1) NOT NULL,
  `input_rate` decimal(10,2) NOT NULL,
  `output_skim_milk_kg` int(10) unsigned NOT NULL,
  `output_skim_snf` decimal(4,1) NOT NULL,
  `output_cream_kg` int(10) unsigned NOT NULL,
  `output_cream_fat` decimal(4,1) NOT NULL,
  `input_ff_milk_used_kg` int(10) unsigned NOT NULL DEFAULT 0,
  `created_by` bigint(20) unsigned NOT NULL,
  `created_at` timestamp NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`id`),
  KEY `idx_mcp_loc_date` (`location_id`,`entry_date`),
  CONSTRAINT `fk_mcp_loc` FOREIGN KEY (`location_id`) REFERENCES `wp_mf_3_dp_locations` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Flow 2: Cream → Butter + Ghee
CREATE TABLE `wp_mf_3_dp_cream_butter_ghee` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `location_id` int(10) unsigned NOT NULL,
  `vendor_id` int(10) unsigned DEFAULT NULL,
  `entry_date` date NOT NULL,
  `input_cream_kg` int(10) unsigned NOT NULL,
  `input_fat` decimal(4,1) NOT NULL DEFAULT 0.0,
  `input_rate` decimal(10,2) NOT NULL DEFAULT 0.00,
  `input_cream_used_kg` int(10) unsigned NOT NULL DEFAULT 0,
  `output_butter_kg` int(10) unsigned NOT NULL,
  `output_butter_fat` decimal(4,1) NOT NULL,
  `output_ghee_kg` int(10) unsigned NOT NULL,
  `created_by` bigint(20) unsigned NOT NULL,
  `created_at` timestamp NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`id`),
  KEY `idx_cbg_loc_date` (`location_id`,`entry_date`),
  CONSTRAINT `fk_cbg_loc` FOREIGN KEY (`location_id`) REFERENCES `wp_mf_3_dp_locations` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Flow 3: Butter → Ghee
CREATE TABLE `wp_mf_3_dp_butter_ghee` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `location_id` int(10) unsigned NOT NULL,
  `vendor_id` int(10) unsigned DEFAULT NULL,
  `entry_date` date NOT NULL,
  `input_butter_kg` int(10) unsigned NOT NULL,
  `input_fat` decimal(4,1) NOT NULL DEFAULT 0.0,
  `input_rate` decimal(10,2) NOT NULL DEFAULT 0.00,
  `input_butter_used_kg` int(10) unsigned NOT NULL DEFAULT 0,
  `output_ghee_kg` int(10) unsigned NOT NULL,
  `created_by` bigint(20) unsigned NOT NULL,
  `created_at` timestamp NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`id`),
  KEY `idx_bg_loc_date` (`location_id`,`entry_date`),
  CONSTRAINT `fk_bg_loc` FOREIGN KEY (`location_id`) REFERENCES `wp_mf_3_dp_locations` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Flow 4: Dahi production
CREATE TABLE `wp_mf_3_dp_dahi_production` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `location_id` int(10) unsigned NOT NULL,
  `entry_date` date NOT NULL,
  `input_smp_bags` int(10) unsigned NOT NULL,
  `input_culture_kg` decimal(10,2) NOT NULL,
  `input_protein_kg` decimal(10,2) NOT NULL,
  `input_skim_milk_kg` int(10) unsigned NOT NULL,
  `input_container_count` int(10) unsigned NOT NULL,
  `input_seal_count` int(10) unsigned NOT NULL,
  `output_container_count` int(10) unsigned NOT NULL,
  `created_by` bigint(20) unsigned NOT NULL,
  `created_at` timestamp NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`id`),
  KEY `idx_dp_loc_date` (`location_id`,`entry_date`),
  CONSTRAINT `fk_dp_loc` FOREIGN KEY (`location_id`) REFERENCES `wp_mf_3_dp_locations` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Sales
CREATE TABLE `wp_mf_3_dp_sales` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `location_id` int(10) unsigned NOT NULL,
  `product_id` int(10) unsigned NOT NULL,
  `entry_date` date NOT NULL,
  `customer_id` int(10) unsigned DEFAULT NULL,
  `customer_name` varchar(100) NOT NULL DEFAULT '',
  `quantity_kg` int(10) unsigned NOT NULL,
  `rate` decimal(10,2) NOT NULL,
  `created_by` bigint(20) unsigned NOT NULL,
  `updated_by` bigint(20) unsigned NOT NULL,
  `created_at` timestamp NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_sales_loc_prod_date_cust` (`location_id`,`product_id`,`entry_date`,`customer_id`),
  KEY `fk_sales_prod` (`product_id`),
  KEY `idx_sales_loc_date` (`location_id`,`entry_date`),
  CONSTRAINT `fk_sales_loc` FOREIGN KEY (`location_id`) REFERENCES `wp_mf_3_dp_locations` (`id`),
  CONSTRAINT `fk_sales_prod` FOREIGN KEY (`product_id`) REFERENCES `wp_mf_3_dp_products` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Ingredient purchases (SMP, Protein, Culture)
CREATE TABLE `wp_mf_3_dp_ingredient_purchase` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `location_id` int(10) unsigned NOT NULL,
  `entry_date` date NOT NULL,
  `product_id` tinyint(3) unsigned NOT NULL COMMENT '7=SMP, 8=Protein, 9=Culture',
  `quantity` decimal(10,2) NOT NULL DEFAULT 0.00,
  `created_by` bigint(20) unsigned DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT current_timestamp(),
  `rate` decimal(10,2) NOT NULL DEFAULT 0.00,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Estimated rates (finance only)
CREATE TABLE `wp_mf_3_dp_estimated_rates` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `product_id` int(10) unsigned NOT NULL,
  `rate` decimal(10,2) NOT NULL DEFAULT 0.00,
  `updated_by` bigint(20) unsigned NOT NULL,
  `updated_at` timestamp NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`id`),
  UNIQUE KEY `product_id` (`product_id`),
  CONSTRAINT `fk_er_prod` FOREIGN KEY (`product_id`) REFERENCES `wp_mf_3_dp_products` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Audit log
CREATE TABLE `wp_mf_3_dp_audit_log` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `table_name` varchar(100) NOT NULL,
  `record_id` int(10) unsigned NOT NULL,
  `action` enum('INSERT','UPDATE','DELETE') NOT NULL,
  `old_data` longtext CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL CHECK (json_valid(`old_data`)),
  `new_data` longtext CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL CHECK (json_valid(`new_data`)),
  `user_id` bigint(20) unsigned NOT NULL,
  `user_name` varchar(100) NOT NULL,
  `ip_address` varchar(45) DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`),
  KEY `idx_audit_tbl` (`table_name`,`record_id`),
  KEY `idx_audit_user` (`user_id`,`created_at`),
  KEY `idx_audit_dt` (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Vendor → Location access
CREATE TABLE `wp_mf_3_dp_vendor_location_access` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `vendor_id` int(10) unsigned NOT NULL,
  `location_id` int(10) unsigned NOT NULL,
  `created_at` timestamp NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_vendor_location` (`vendor_id`,`location_id`),
  KEY `idx_vla_loc` (`location_id`),
  CONSTRAINT `fk_vla_loc` FOREIGN KEY (`location_id`) REFERENCES `wp_mf_3_dp_locations` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Vendor payments
CREATE TABLE `wp_mf_3_dp_vendor_payments` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `vendor_id` int(10) unsigned NOT NULL,
  `payment_date` date NOT NULL,
  `amount` decimal(12,2) NOT NULL,
  `method` varchar(20) NOT NULL DEFAULT 'Cash',
  `note` varchar(255) DEFAULT NULL,
  `created_by` bigint(20) unsigned NOT NULL,
  `created_at` timestamp NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`),
  KEY `idx_vp_vendor` (`vendor_id`),
  KEY `idx_vp_date` (`payment_date`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ============================================================
-- SAMPLE DATA
-- ============================================================

-- Locations (Bijnor→Mathura, Laksar→Haridwar)
INSERT INTO `wp_mf_3_dp_locations` (`id`, `name`, `code`) VALUES
(1, 'Mathura',   'MATHURA'),
(2, 'Haridwar',  'HARIDWAR'),
(3, 'Test',      'TEST');

-- Products (fixed IDs — never change)
INSERT INTO `wp_mf_3_dp_products` (`id`, `name`, `unit`, `sort_order`) VALUES
(1, 'FF Milk',   'KG',   1),
(2, 'Skim Milk', 'KG',   2),
(3, 'Cream',     'KG',   3),
(4, 'Butter',    'KG',   4),
(5, 'Ghee',      'KG',   5),
(6, 'Dahi',      'pcs',  6),
(7, 'SMP',       'Bags', 7),
(8, 'Protein',   'KG',   8),
(9, 'Culture',   'KG',   9);

-- Customers
INSERT INTO `wp_mf_3_dp_customers` (`id`, `name`) VALUES
(1, 'Nandi'),
(2, 'Jyoti'),
(3, 'Ajay'),
(4, 'Malik'),
(5, 'Madhu'),
(6, 'Ahmed'),
(7, 'Khana'),
(8, 'Hindustan Provisions');

-- Vendors
INSERT INTO `wp_mf_3_dp_vendors` (`id`, `name`) VALUES
(1, 'Anand Milk Suppliers'),
(2, 'Brijesh Farm'),
(3, 'Chaudhary Dairy Farm'),
(4, 'Dev Milk Products'),
(5, 'Farmgate Supplies'),
(6, 'Green Valley Dairy'),
(7, 'Haryana Milk Co.'),
(8, 'Indian Creamery');

-- User access: user_id 1 (your WP admin) gets all locations + finance + anomaly
INSERT INTO `wp_mf_3_dp_user_location_access` (`user_id`, `location_id`) VALUES
(1, 1), (1, 2), (1, 3);

INSERT INTO `wp_mf_3_dp_user_flags` (`user_id`, `can_finance`, `can_anomaly`) VALUES
(1, 1, 1);

-- Estimated rates (INR per KG)
INSERT INTO `wp_mf_3_dp_estimated_rates` (`product_id`, `rate`, `updated_by`) VALUES
(1, 54.50,  1),
(2, 31.00,  1),
(3, 275.00, 1),
(4, 480.00, 1),
(5, 600.00, 1);

-- Sample production: FF Milk purchases + processing (location 3 = Test)
INSERT INTO `wp_mf_3_dp_milk_cream_production`
  (`location_id`, `vendor_id`, `entry_date`, `input_ff_milk_kg`, `input_snf`, `input_fat`, `input_rate`,
   `output_skim_milk_kg`, `output_skim_snf`, `output_cream_kg`, `output_cream_fat`, `input_ff_milk_used_kg`, `created_by`)
VALUES
  (3, 1,    '2026-02-28', 2580, 8.5, 5.6, 56.40,    0, 0.0,   0, 0.0, 0,    1),
  (3, NULL, '2026-02-28',    0, 0.0, 0.0,  0.00, 2380, 8.5, 240, 5.5, 2500, 1),
  (3, 1,    '2026-03-01', 2960, 8.8, 5.6, 53.60,    0, 0.0,   0, 0.0, 0,    1),
  (3, NULL, '2026-03-01',    0, 0.0, 0.0,  0.00, 2980, 8.4, 156, 5.6, 3040, 1),
  (3, 3,    '2026-02-24', 2580, 8.6, 5.6, 56.50,    0, 0.0,   0, 0.0, 0,    1);

-- Sample production: Cream → Butter + Ghee
INSERT INTO `wp_mf_3_dp_cream_butter_ghee`
  (`location_id`, `vendor_id`, `entry_date`, `input_cream_kg`, `input_fat`, `input_rate`,
   `input_cream_used_kg`, `output_butter_kg`, `output_butter_fat`, `output_ghee_kg`, `created_by`)
VALUES
  (3, NULL, '2026-02-28', 0, 0.0, 0.00, 200, 40, 5.6,  98, 1),
  (3, NULL, '2026-03-01', 0, 0.0, 0.00, 180,  0, 0.0, 102, 1),
  (3, NULL, '2026-03-01', 0, 0.0, 0.00, 200,  0, 0.0, 125, 1);

-- Sample production: Dahi
INSERT INTO `wp_mf_3_dp_dahi_production`
  (`location_id`, `entry_date`, `input_smp_bags`, `input_culture_kg`, `input_protein_kg`,
   `input_skim_milk_kg`, `input_container_count`, `input_seal_count`, `output_container_count`, `created_by`)
VALUES
  (3, '2026-03-01', 6, 1.00, 3.00, 1100, 960, 960, 960, 1),
  (3, '2026-03-02', 6, 2.00, 1.00, 1100, 918, 918, 918, 1);

-- Sample sales
INSERT INTO `wp_mf_3_dp_sales`
  (`location_id`, `product_id`, `entry_date`, `customer_id`, `customer_name`, `quantity_kg`, `rate`, `created_by`, `updated_by`)
VALUES
  (3, 5, '2026-02-28', 1, 'Nandi',              40, 600.00, 1, 1),
  (3, 2, '2026-03-01', 1, 'Nandi',            2080,  31.00, 1, 1),
  (3, 5, '2026-03-01', 5, 'Madhu',             100, 600.00, 1, 1),
  (3, 1, '2026-03-02', 7, 'Khana',            1000,  32.00, 1, 1),
  (3, 2, '2026-02-26', 2, 'Jyoti',            1000,  31.00, 1, 1);

-- Sample ingredient purchases
INSERT INTO `wp_mf_3_dp_ingredient_purchase`
  (`location_id`, `entry_date`, `product_id`, `quantity`, `rate`, `created_by`)
VALUES
  (3, '2026-03-01', 7, 50.00,   0.00, 1),
  (3, '2026-03-01', 8, 10.00,   0.00, 1),
  (3, '2026-03-01', 9, 10.00,   0.00, 1),
  (3, '2026-03-01', 7, 20.00,   0.00, 1),
  (3, '2026-03-01', 7,  5.00, 850.00, 1);

-- Sample vendor payments
INSERT INTO `wp_mf_3_dp_vendor_payments`
  (`vendor_id`, `payment_date`, `amount`, `method`, `note`, `created_by`)
VALUES
  (1, '2026-03-04', 300000.00, 'Cash', NULL, 1),
  (1, '2026-03-04',  50500.00, 'Cash', NULL, 1),
  (3, '2026-03-04',  20000.00, 'Cash', NULL, 1);

-- Sample audit log entries
INSERT INTO `wp_mf_3_dp_audit_log`
  (`table_name`, `record_id`, `action`, `old_data`, `new_data`, `user_id`, `user_name`, `ip_address`)
VALUES
  ('wp_mf_3_dp_milk_cream_production', 1, 'INSERT', NULL,
   '{"location_id":3,"vendor_id":1,"entry_date":"2026-02-28","input_ff_milk_kg":2580}',
   1, 'admin', '127.0.0.1'),
  ('wp_mf_3_dp_sales', 1, 'INSERT', NULL,
   '{"location_id":3,"product_id":5,"entry_date":"2026-02-28","customer_id":1,"quantity_kg":40}',
   1, 'admin', '127.0.0.1'),
  ('wp_mf_3_dp_estimated_rates', 1, 'UPDATE',
   '{"product_id":1,"rate":"50.00"}', '{"product_id":1,"rate":"54.50"}',
   1, 'admin', '127.0.0.1');

SET FOREIGN_KEY_CHECKS = 1;
