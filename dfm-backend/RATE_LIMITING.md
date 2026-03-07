# Dairy App — Rate Limiting & Lockout Reference

## 1. Back-off Logic

The plugin tracks failed login attempts **per IP address** using WordPress
transients (stored in the `wp_options` table). No external cache or cron job
is required — everything is self-contained.

### Thresholds

| Stage | Trigger | Lockout duration |
|---|---|---|
| **Soft lockout** | 5 consecutive failures from one IP | 15 minutes |
| **Hard lockout** | 10 consecutive failures from one IP | 24 hours |

Thresholds are defined as constants near the top of `dairy-jwt-auth.php`:

```php
const RL_MAX_ATTEMPTS  = 5;        // failures before soft lockout
const RL_LOCKOUT_1     = 15 * 60;  // 15 minutes (seconds)
const RL_MAX_ATTEMPTS2 = 10;       // failures before hard lockout
const RL_LOCKOUT_2     = 24 * 3600; // 24 hours (seconds)
```

To tighten or loosen the policy, edit these four constants and re-upload the
plugin file. No other changes needed.

### Attempt window

Failed attempts accumulate within a rolling `RL_WINDOW` period. A successful
login **immediately clears** the attempt counter and any active lockout for
that IP — so a legitimate user who fat-fingered their password is unblocked
the moment they log in correctly.

### What the client receives during a lockout

```json
HTTP 429
{
  "success": false,
  "message": "Too many failed login attempts. Please try again in 14 minute(s)."
}
```

The remaining minutes are calculated in real time from the transient expiry,
so the message stays accurate across retries.

### IP detection

The plugin resolves the client IP from (in order):

1. `HTTP_CF_CONNECTING_IP` — Cloudflare
2. `HTTP_X_FORWARDED_FOR` — reverse proxy / load balancer (first IP in list)
3. `REMOTE_ADDR` — direct connection

If you are behind a trusted proxy, make sure it forwards the real client IP
in one of the headers above; otherwise all users will share the same IP and
one bad actor can lock out everyone.

---

## 2. Lockout Override & Reset Procedures

### Option A — WordPress Admin UI (recommended)

A dedicated admin page is built into the plugin:

**WordPress Admin → Users → Dairy Login Security**

The page shows two tables:

- **Active Lockouts** — IPs currently blocked, with their lockout tier
  (15 min or 24 h) and a *Clear Lockout* button per row.
- **Failed Attempt Counts** — IPs that have failures but are not yet locked
  out, with a *Clear* button per row.

At the bottom, a **Clear All Lockouts & Attempts** button wipes every record
in one click.

> Only WordPress users with the `manage_options` capability (Administrators)
> can access this page. All actions are nonce-protected.

---

### Option B — WP-CLI (command line, no browser needed)

Useful when locked out of the admin itself or during automated testing.

**Clear one IP (you need the MD5 hash of the IP address):**

```bash
# Get the hash first
php -r "echo md5('203.0.113.42');"
# → e.g. a1b2c3d4e5f6...

wp transient delete dairy_rl_lockout_a1b2c3d4e5f6...
wp transient delete dairy_rl_attempts_a1b2c3d4e5f6...
```

**Clear everything in one command:**

```bash
wp db query "DELETE FROM wp_options
  WHERE option_name LIKE '_transient_dairy_rl_%'
     OR option_name LIKE '_transient_timeout_dairy_rl_%';"
```

> Replace `wp_options` with your actual table prefix if it differs
> (e.g. `dairy_options`). Check `wp-config.php` for `$table_prefix`.

---

### Option C — phpMyAdmin / direct DB (no CLI access)

1. Open phpMyAdmin and select your WordPress database.
2. Run the following SQL:

```sql
DELETE FROM wp_options
WHERE option_name LIKE '_transient_dairy_rl_%'
   OR option_name LIKE '_transient_timeout_dairy_rl_%';
```

This removes all attempt counters and lockouts in one query.

---

### Option D — Wait it out

| Lockout tier | Clears automatically after |
|---|---|
| Soft lockout | 15 minutes |
| Hard lockout | 24 hours |

No admin intervention needed if time permits.

---

## 3. DDoS / Sustained Attack Notes

### What the current back-off protects against

- Credential stuffing from a single IP
- Slow brute-force from a single IP
- Accidental self-lockout (fat-fingered password)

### What it does NOT protect against

- **Distributed attacks** — hundreds of IPs each sending a small number of
  requests will never hit the per-IP threshold.
- **Application-layer floods** — high-volume unauthenticated POST requests to
  `/auth/login` will still reach PHP/WordPress even if they are rejected
  quickly. Under extreme volume this can exhaust PHP workers.

### Recommended additional layers for production

| Layer | Tool / approach |
|---|---|
| **Web Application Firewall** | Cloudflare (free tier sufficient), or Apache `mod_evasive` |
| **Nginx/Apache rate limiting** | `limit_req_zone` in Nginx; `mod_ratelimit` in Apache |
| **Fail2Ban** | Parse `/var/log/apache2/error.log` for `[Dairy JWT] rate_limit` entries and ban at the firewall level |
| **CAPTCHA on repeated failures** | Add a CAPTCHA challenge after 3 failures (requires Flutter + backend changes) |

### Suggested Fail2Ban filter

Create `/etc/fail2ban/filter.d/dairy-jwt.conf`:

```ini
[Definition]
failregex = \[Dairy JWT\] rate_limit: IP <HOST> is locked out
ignoreregex =
```

Create `/etc/fail2ban/jail.d/dairy-jwt.conf`:

```ini
[dairy-jwt]
enabled  = true
filter   = dairy-jwt
logpath  = /var/log/apache2/error.log
maxretry = 1
bantime  = 3600
findtime = 600
```

This bans at the firewall/OS level any IP that the plugin has already
soft-locked, adding a hard network-level block on top of the application-level
one.

---

## 4. Quick Reference

```
Soft lockout  →  5 bad attempts   →  15 min block  →  HTTP 429
Hard lockout  →  10 bad attempts  →  24 hr block   →  HTTP 429
Successful login at any point     →  counter reset, lockout lifted

Admin UI   →  WP Admin > Users > Dairy Login Security
WP-CLI     →  wp transient delete dairy_rl_lockout_<hash>
             wp transient delete dairy_rl_attempts_<hash>
DB (SQL)   →  DELETE FROM wp_options WHERE option_name LIKE '_transient_dairy_rl_%'
              OR option_name LIKE '_transient_timeout_dairy_rl_%'
Auto-clear →  waits for transient TTL (15 min or 24 h)
```
