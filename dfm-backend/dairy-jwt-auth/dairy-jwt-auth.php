<?php
/**
 * Plugin Name: Dairy App – JWT Auth
 * Description: JWT login for the Dairy Management mobile app.
 *              Admin creates WP user accounts. App logs in with username + password.
 * Version:     1.0.0
 *
 * ── INSTALL ───────────────────────────────────────────────
 * 1. Copy this folder to:
 *      wp-content/plugins/dairy-jwt-auth/
 *
 * 2. Inside that folder run:
 *      composer require firebase/php-jwt
 *
 * 3. Add to wp-config.php  (generate value at https://api.wordpress.org/secret-key/1.1/salt/):
 *      define('DAIRY_JWT_SECRET', 'paste-at-least-64-random-chars-here');
 *
 * 4. If your server runs Apache, add to .htaccess inside the
 *    <IfModule mod_rewrite.c> block:
 *      RewriteCond %{HTTP:Authorization} ^(.*)
 *      RewriteRule ^(.*) - [E=HTTP_AUTHORIZATION:%1]
 *
 * 5. Activate the plugin in WP Admin → Plugins.
 *
 * ── ENDPOINTS  /wp-json/dairy/v1/ ─────────────────────────
 * POST /auth/login    { username, password }
 *                     → { token, refresh_token, expires_in, user }
 * POST /auth/refresh  { refresh_token }
 *                     → { token, expires_in }
 * POST /auth/logout   Bearer token required
 *                     → { message }
 * GET  /auth/me       Bearer token required
 *                     → { user }
 *
 * ── TOKEN DESIGN ──────────────────────────────────────────
 * Access token  — 8 hours,  sent as  Authorization: Bearer <token>
 * Refresh token — 30 days,  used to silently get a new access token.
 *                 Stored in WP user-meta so logout truly revokes it.
 */

defined('ABSPATH') || exit;

error_log('[Dairy JWT] Plugin loading from: ' . __DIR__);

// ── Built-in JWT (HS256 only) — avoids conflicts with other plugins ──
// We do not use firebase/php-jwt to avoid class conflicts with other
// plugins (google-site-kit, elementskit, digits, etc.) that load their
// own version first. This minimal implementation handles HS256 only.

class Dairy_JWT_Helper {

    public static function encode( array $payload, string $secret ): string {
        $header  = self::b64( json_encode(['typ' => 'JWT', 'alg' => 'HS256']) );
        $body    = self::b64( json_encode($payload) );
        $sig     = self::b64( hash_hmac('sha256', "$header.$body", $secret, true) );
        return "$header.$body.$sig";
    }

    public static function decode( string $token, string $secret ): object {
        $parts = explode('.', $token);
        if ( count($parts) !== 3 ) {
            throw new \UnexpectedValueException('Invalid token structure');
        }
        [$header_b64, $body_b64, $sig_b64] = $parts;

        // Verify algorithm
        $header = json_decode(self::b64d($header_b64));
        if ( ($header->alg ?? '') !== 'HS256' ) {
            throw new \UnexpectedValueException('Algorithm not supported: ' . ($header->alg ?? 'none'));
        }

        // Verify signature
        $expected_sig = self::b64( hash_hmac('sha256', "$header_b64.$body_b64", $secret, true) );
        if ( ! hash_equals($expected_sig, $sig_b64) ) {
            throw new \UnexpectedValueException('Signature verification failed');
        }

        // Decode payload
        $payload = json_decode(self::b64d($body_b64));
        if ( $payload === null ) {
            throw new \UnexpectedValueException('Invalid payload');
        }

        // Check expiry
        $now = time();
        if ( isset($payload->exp) && $payload->exp < $now ) {
            throw new \RuntimeException('Token has expired');
        }

        // Check not-before
        if ( isset($payload->nbf) && $payload->nbf > $now ) {
            throw new \RuntimeException('Token not yet valid');
        }

        return $payload;
    }

    private static function b64( string $data ): string {
        return rtrim(strtr(base64_encode($data), '+/', '-_'), '=');
    }

    private static function b64d( string $data ): string {
        return base64_decode(strtr($data, '-_', '+/') . str_repeat('=', 3 - (3 + strlen($data)) % 4));
    }
}


class Dairy_JWT_Auth {

    const NS               = 'dairy/v1';
    const ACCESS_TTL       = 8  * HOUR_IN_SECONDS;
    const REFRESH_TTL      = 30 * DAY_IN_SECONDS;
    const META_KEY         = '_dairy_refresh_tokens';
    const COOKIE_ACCESS    = 'dairy_access';
    const COOKIE_REFRESH   = 'dairy_refresh';

    // ── Rate limiting ──────────────────────────────────────
    const RL_MAX_ATTEMPTS  = 5;           // attempts before first lockout
    const RL_LOCKOUT_1     = 15 * 60;     // 15 min after 5 failures
    const RL_MAX_ATTEMPTS2 = 10;          // attempts before hard lockout
    const RL_LOCKOUT_2     = 24 * 3600;   // 24 hours after 10 failures
    const RL_WINDOW        = 30 * 60;     // rolling 30-min window for counting

    public function __construct() {
        add_action('rest_api_init', [ $this, 'register_routes' ]);
        add_filter('rest_pre_serve_request', [ $this, 'handle_cors' ], 1, 4);

        // ── Universal JWT authentication ───────────────────────────────────────
        // Hook into WordPress user resolution so that ANY REST endpoint
        // (including the production API's /me) automatically recognises a valid
        // JWT — whether it arrives as an Authorization: Bearer header (mobile)
        // or as the dairy_access httpOnly cookie (web browser).
        // Priority 20 runs after WP's own cookie/nonce auth (priority 10) so we
        // never override a legitimately logged-in WP session.
        add_filter('determine_current_user', [ $this, 'authenticate_from_jwt' ], 20);
        add_action('admin_menu', [ $this, 'register_admin_page' ]);
        add_action('admin_post_dairy_clear_lockout', [ $this, 'handle_clear_lockout' ]);
    }

    // ── CORS for local dev ────────────────────────────────

    public function handle_cors( $served, $result, $request, $server ) {
        $origin = $_SERVER['HTTP_ORIGIN'] ?? '';
        $is_local = (
            str_contains($origin, 'localhost') ||
            str_contains($origin, '127.0.0.1') ||
            str_contains($origin, '::1')
        );
        if ( $is_local && ! empty($origin) ) {
            header('Access-Control-Allow-Origin: ' . $origin);
            header('Access-Control-Allow-Credentials: true');
            header('Access-Control-Allow-Methods: GET, POST, PUT, DELETE, OPTIONS');
            header('Access-Control-Allow-Headers: Authorization, Content-Type, X-Client, X-WP-Nonce');
            error_log('[Dairy JWT] CORS: allowed local origin ' . $origin);
        }
        return $served;
    }

    // ── Routes ────────────────────────────────────────────

    // ── Global JWT authenticator (determine_current_user hook) ────────────────
    //
    // Called by WordPress on every request before permission callbacks run.
    // Resolves the logged-in user from:
    //   1. Authorization: Bearer <token>  header  — mobile app
    //   2. dairy_access httpOnly cookie           — web browser (same-domain)
    //
    // If neither is present, or the token is invalid/expired, we return the
    // original $user_id unchanged so WordPress can fall through to its own
    // cookie/nonce auth.  We never throw — a bad token simply means "not us".
    //
    // Excluded paths (return early):
    //   - Non-REST requests (admin pages, front-end, cron, etc.)
    //   - /auth/login and /auth/refresh — they handle their own auth
    //
    public function authenticate_from_jwt( $user_id ) {
        // Already resolved by a higher-priority authenticator — leave it alone.
        if ( $user_id ) {
            return $user_id;
        }

        // Only act on REST API requests.
        if ( ! defined('REST_REQUEST') || ! REST_REQUEST ) {
            return $user_id;
        }

        // Skip the login / refresh endpoints — they don't need prior auth.
        $uri = $_SERVER['REQUEST_URI'] ?? '';
        if (
            str_contains($uri, '/auth/login')   ||
            str_contains($uri, '/auth/refresh') ||
            str_contains($uri, '/auth/logout')
        ) {
            return $user_id;
        }

        // ── 1. Try Authorization: Bearer header (mobile) ──────────────────────
        $raw_token = '';
        $auth_header = '';

        // Apache sometimes strips the Authorization header; the .htaccess
        // RewriteRule documented at the top of this file fixes that.
        // We check multiple sources for compatibility across hosts.
        if ( function_exists('getallheaders') ) {
            $headers = array_change_key_case( getallheaders(), CASE_LOWER );
            $auth_header = $headers['authorization'] ?? '';
        }
        if ( empty($auth_header) ) {
            $auth_header = $_SERVER['HTTP_AUTHORIZATION'] ?? '';
        }
        if ( empty($auth_header) ) {
            // Some Apache configs pass it as REDIRECT_HTTP_AUTHORIZATION
            $auth_header = $_SERVER['REDIRECT_HTTP_AUTHORIZATION'] ?? '';
        }

        if ( str_starts_with($auth_header, 'Bearer ') ) {
            $raw_token = trim( substr($auth_header, 7) );
        }

        // ── 2. Fall back to httpOnly cookie (web browser, same domain) ────────
        if ( empty($raw_token) && ! empty($_COOKIE[self::COOKIE_ACCESS]) ) {
            $raw_token = sanitize_text_field( $_COOKIE[self::COOKIE_ACCESS] );
        }

        // Nothing to authenticate with.
        if ( empty($raw_token) ) {
            return $user_id;
        }

        // ── Decode and validate ───────────────────────────────────────────────
        try {
            $dec = Dairy_JWT_Helper::decode($raw_token, $this->secret());
        } catch (\Exception $e) {
            // Expired, tampered, or foreign token — not our concern; let WP
            // continue with its own auth (which will also find nothing and
            // ultimately return 0 / not-logged-in for protected endpoints).
            error_log('[Dairy JWT] authenticate_from_jwt: token rejected — ' . $e->getMessage());
            return $user_id;
        }

        if ( ($dec->type ?? '') !== 'access' ) {
            error_log('[Dairy JWT] authenticate_from_jwt: wrong token type — ' . ($dec->type ?? 'none'));
            return $user_id;
        }

        $uid = (int) ($dec->sub ?? 0);
        if ( ! $uid ) {
            return $user_id;
        }

        // Token-version revocation check.
        $current_ver = (int) get_user_meta($uid, '_dairy_token_version', true);
        $token_ver   = (int) ($dec->ver ?? 0);
        if ( $token_ver < $current_ver ) {
            error_log('[Dairy JWT] authenticate_from_jwt: revoked token for user ' . $uid);
            return $user_id;
        }

        error_log('[Dairy JWT] authenticate_from_jwt: authenticated user ID ' . $uid);
        return $uid;
    }

    public function register_routes(): void {
        error_log('[Dairy JWT] Registering routes under namespace: ' . self::NS);
        $open = [ 'permission_callback' => '__return_true' ];
        $auth = [ 'permission_callback' => [ $this, 'require_jwt' ] ];

        register_rest_route(self::NS, '/auth/login', array_merge($open, [
            'methods'  => 'POST',
            'callback' => [ $this, 'login' ],
            'args' => [
                'username' => [ 'required' => true, 'type' => 'string' ],
                'password' => [ 'required' => true, 'type' => 'string' ],
            ],
        ]));

        register_rest_route(self::NS, '/auth/refresh', array_merge($open, [
            'methods'  => 'POST',
            'callback' => [ $this, 'refresh' ],
            'args' => [
                'refresh_token' => [ 'required' => true, 'type' => 'string' ],
            ],
        ]));

        register_rest_route(self::NS, '/auth/cookie-refresh', array_merge($open, [
            'methods'  => 'POST',
            'callback' => [ $this, 'cookie_refresh' ],
        ]));

        register_rest_route(self::NS, '/auth/logout', array_merge($auth, [
            'methods'  => 'POST',
            'callback' => [ $this, 'logout' ],
        ]));

        register_rest_route(self::NS, '/auth/me', array_merge($auth, [
            'methods'  => 'GET',
            'callback' => [ $this, 'me' ],
        ]));
        error_log('[Dairy JWT] Routes registered: /auth/login, /auth/refresh, /auth/cookie-refresh, /auth/logout, /auth/me');
    }

    // ── Login ─────────────────────────────────────────────

    public function login( WP_REST_Request $r ): WP_REST_Response {
        $ip      = $this->get_client_ip();
        $username = sanitize_user( $r['username'] );
        $is_web   = $r->get_header('X-Client') === 'web';
        error_log('[Dairy JWT] Login attempt: user=' . $username . ' ip=' . $ip . ' web=' . ($is_web ? 'true' : 'false'));

        // ── Check rate limit before attempting auth ────────
        $rate_limit_error = $this->check_rate_limit($ip);
        if ( $rate_limit_error !== null ) return $rate_limit_error;

        $user = wp_authenticate( $username, $r['password'] );

        if ( is_wp_error($user) ) {
            error_log('[Dairy JWT] Login failed for: ' . $username . ' — ' . $user->get_error_message());
            $this->record_failure($ip);
            // Generic message — don't reveal if username or password was wrong
            return $this->err('Invalid username or password.', 401);
        }

        $this->record_success($ip);
        error_log('[Dairy JWT] Login success for: ' . $username);

        $access  = $this->make_access($user);
        $refresh = $this->make_refresh($user);

        if ( $is_web ) {
            // Web: store tokens in httpOnly cookies — JS cannot read them
            $this->set_access_cookie($access);
            $this->set_refresh_cookie($refresh);
            // Return user info only — no tokens in response body
            return $this->ok([
                'expires_in' => self::ACCESS_TTL,
                'user'       => $this->user_data($user),
            ]);
        }

        // Mobile: return tokens in body as before
        return $this->ok([
            'token'         => $access,
            'refresh_token' => $refresh,
            'expires_in'    => self::ACCESS_TTL,
            'user'          => $this->user_data($user),
        ]);
    }

    // ── Cookie refresh (web only) ─────────────────────────

    public function cookie_refresh(): WP_REST_Response {
        $refresh_token = $_COOKIE[self::COOKIE_REFRESH] ?? '';
        if ( empty($refresh_token) ) {
            error_log('[Dairy JWT] cookie_refresh: no refresh cookie present');
            return $this->err('No refresh cookie found. Please log in again.', 401);
        }

        try {
            $dec = Dairy_JWT_Helper::decode($refresh_token, $this->secret());
        } catch (\RuntimeException $e) {
            error_log('[Dairy JWT] cookie_refresh: refresh cookie expired — ' . $e->getMessage());
            $this->clear_cookies();
            return $this->err('Session expired. Please log in again.', 401);
        } catch (\Exception $e) {
            error_log('[Dairy JWT] cookie_refresh: invalid refresh cookie — ' . $e->getMessage());
            $this->clear_cookies();
            return $this->err('Invalid session. Please log in again.', 401);
        }

        if ( ($dec->type ?? '') !== 'refresh' ) {
            error_log('[Dairy JWT] cookie_refresh: wrong token type — ' . ($dec->type ?? 'none'));
            return $this->err('Invalid token type.', 401);
        }

        $uid    = (int) $dec->sub;
        $jti    = $dec->jti ?? '';
        $stored = get_user_meta($uid, self::META_KEY, true) ?: [];

        if ( ! in_array($jti, $stored, true) ) {
            error_log('[Dairy JWT] cookie_refresh: JTI revoked for user ID ' . $uid);
            $this->clear_cookies();
            return $this->err('Session revoked. Please log in again.', 401);
        }

        $user = get_userdata($uid);
        if ( ! $user ) {
            error_log('[Dairy JWT] cookie_refresh: user ID ' . $uid . ' not found');
            return $this->err('User not found.', 401);
        }

        $new_access = $this->make_access($user);
        $this->set_access_cookie($new_access);
        return $this->ok(['expires_in' => self::ACCESS_TTL]);
    }

    // ── Refresh ───────────────────────────────────────────

    public function refresh( WP_REST_Request $r ): WP_REST_Response {
        try {
            $dec = Dairy_JWT_Helper::decode($r['refresh_token'], $this->secret());
        } catch (\RuntimeException $e) {
            error_log('[Dairy JWT] refresh: token expired — ' . $e->getMessage());
            return $this->err('Session expired. Please log in again.', 401);
        } catch (\Exception $e) {
            error_log('[Dairy JWT] refresh: invalid token — ' . $e->getMessage());
            return $this->err('Invalid refresh token.', 401);
        }

        if ( ($dec->type ?? '') !== 'refresh' ) {
            error_log('[Dairy JWT] refresh: wrong token type — ' . ($dec->type ?? 'none'));
            return $this->err('Invalid token type.', 401);
        }

        $uid  = (int) $dec->sub;
        $jti  = $dec->jti ?? '';
        $stored = get_user_meta($uid, self::META_KEY, true) ?: [];

        if ( ! in_array($jti, $stored, true) ) {
            error_log('[Dairy JWT] refresh: JTI not found in stored tokens for user ID ' . $uid);
            return $this->err('Session revoked. Please log in again.', 401);
        }

        $user = get_userdata($uid);
        if ( ! $user ) {
            error_log('[Dairy JWT] refresh: user ID ' . $uid . ' not found');
            return $this->err('User not found.', 401);
        }

        return $this->ok([
            'token'      => $this->make_access($user),
            'expires_in' => self::ACCESS_TTL,
        ]);
    }

    // ── Logout ────────────────────────────────────────────

    public function logout(): WP_REST_Response {
        $uid = get_current_user_id();
        error_log('[Dairy JWT] logout: user ID ' . $uid);
        delete_user_meta($uid, self::META_KEY);
        $this->clear_cookies();
        error_log('[Dairy JWT] logout: complete for user ID ' . $uid);
        return $this->ok([ 'message' => 'Logged out successfully.' ]);
    }

    // ── Me ────────────────────────────────────────────────

    public function me(): WP_REST_Response {
        $user = wp_get_current_user();
        error_log('[Dairy JWT] me: called for user ID ' . $user->ID . ' (' . $user->user_login . ')');
        return $this->ok([ 'user' => $this->user_data($user) ]);
    }

    // ── Permission callback (used by all other endpoints) ─

    public function require_jwt( WP_REST_Request $r ) {
        $header = $r->get_header('Authorization') ?? '';

        // Accept token from cookie (web) or Bearer header (mobile)
        if ( str_starts_with($header, 'Bearer ') ) {
            $raw_token = substr($header, 7);
        } elseif ( ! empty($_COOKIE[self::COOKIE_ACCESS]) ) {
            $raw_token = sanitize_text_field($_COOKIE[self::COOKIE_ACCESS]);
        } else {
            error_log('[Dairy JWT] require_jwt: no token in header or cookie. URI=' . ($_SERVER['REQUEST_URI'] ?? ''));
            return new WP_Error('no_token',
                'Authorization required.', ['status' => 401]);
        }

        try {
            $dec = Dairy_JWT_Helper::decode($raw_token, $this->secret());
        } catch (\RuntimeException $e) {
            error_log('[Dairy JWT] require_jwt: token expired — ' . $e->getMessage());
            return new WP_Error('token_expired',
                'Access token expired.', ['status' => 401]);
        } catch (\Exception $e) {
            error_log('[Dairy JWT] require_jwt: invalid token — ' . $e->getMessage());
            return new WP_Error('bad_token',
                'Invalid token.', ['status' => 401]);
        }

        if ( ($dec->type ?? '') !== 'access' ) {
            return new WP_Error('wrong_type',
                'Wrong token type.', ['status' => 401]);
        }

        $user = get_userdata((int) $dec->sub);
        if ( ! $user ) {
            return new WP_Error('no_user',
                'User not found.', ['status' => 401]);
        }

        // Check token version — if admin ran revoke script, version is bumped
        // and all previously issued tokens are immediately invalid
        $current_version = (int) get_user_meta($user->ID, '_dairy_token_version', true);
        $token_version   = (int) ($dec->ver ?? 0);
        if ( $token_version < $current_version ) {
            error_log('[Dairy JWT] require_jwt: token revoked for user ID ' . $user->ID . ' (token_ver=' . $token_version . ' current_ver=' . $current_version . ')');
            return new WP_Error('token_revoked',
                'Your session has been revoked. Please log in again.',
                ['status' => 401]);
        }

        wp_set_current_user($user->ID);
        return true;
    }

    // ── Token builders ────────────────────────────────────

    private function make_access( WP_User $u ): string {
        $now = time();
        $ver = (int) get_user_meta($u->ID, '_dairy_token_version', true);
        return Dairy_JWT_Helper::encode([
            'iss'  => get_site_url(),
            'iat'  => $now,
            'exp'  => $now + self::ACCESS_TTL,
            'sub'  => $u->ID,
            'type' => 'access',
            'ver'  => $ver,
            'user' => $u->user_login,
        ], $this->secret());
    }

    private function make_refresh( WP_User $u ): string {
        $now = time();
        $jti = wp_generate_uuid4();

        $token = Dairy_JWT_Helper::encode([
            'iss'  => get_site_url(),
            'iat'  => $now,
            'exp'  => $now + self::REFRESH_TTL,
            'sub'  => $u->ID,
            'type' => 'refresh',
            'jti'  => $jti,
        ], $this->secret());

        $stored   = get_user_meta($u->ID, self::META_KEY, true) ?: [];
        $stored[] = $jti;
        update_user_meta($u->ID, self::META_KEY,
                         array_slice($stored, -5)); // keep last 5 devices
        return $token;
    }

    private function user_data( WP_User $u ): array {
        return [
            'id'           => $u->ID,
            'username'     => $u->user_login,
            'email'        => $u->user_email,
            'display_name' => $u->display_name,
            'roles'        => $u->roles,
        ];
    }

    // ── Rate limiting ─────────────────────────────────────

    private function get_client_ip(): string {
        foreach (['HTTP_CF_CONNECTING_IP','HTTP_X_FORWARDED_FOR','REMOTE_ADDR'] as $key) {
            if ( ! empty($_SERVER[$key]) ) {
                // X-Forwarded-For can be a comma-separated list — take first
                return trim(explode(',', $_SERVER[$key])[0]);
            }
        }
        return 'unknown';
    }

    private function rl_key_attempts( string $ip ): string {
        return 'dairy_rl_attempts_' . md5($ip);
    }

    private function rl_key_lockout( string $ip ): string {
        return 'dairy_rl_lockout_' . md5($ip);
    }

    private function check_rate_limit( string $ip ): ?WP_REST_Response {
        $lockout_key = $this->rl_key_lockout($ip);
        $lockout     = get_transient($lockout_key);

        if ( $lockout !== false ) {
            $remaining = (int) $lockout;
            $mins      = ceil($remaining / 60);
            error_log('[Dairy JWT] rate_limit: IP ' . $ip . ' is locked out for ' . $mins . ' more minutes');
            return $this->err(
                'Too many failed login attempts. Please try again in ' . $mins . ' minute(s).',
                429
            );
        }
        return null;
    }

    private function record_failure( string $ip ): void {
        $attempts_key = $this->rl_key_attempts($ip);
        $attempts     = (int) get_transient($attempts_key);
        $attempts++;

        // Store attempt count within rolling window
        set_transient($attempts_key, $attempts, self::RL_WINDOW);
        error_log('[Dairy JWT] record_failure: IP ' . $ip . ' attempt #' . $attempts);

        if ( $attempts >= self::RL_MAX_ATTEMPTS2 ) {
            // Hard lockout — 24 hours
            $lockout_key = $this->rl_key_lockout($ip);
            set_transient($lockout_key, self::RL_LOCKOUT_2, self::RL_LOCKOUT_2);
            error_log('[Dairy JWT] record_failure: IP ' . $ip . ' HARD LOCKOUT 24h after ' . $attempts . ' attempts');
        } elseif ( $attempts >= self::RL_MAX_ATTEMPTS ) {
            // Soft lockout — 15 minutes
            $lockout_key = $this->rl_key_lockout($ip);
            set_transient($lockout_key, self::RL_LOCKOUT_1, self::RL_LOCKOUT_1);
            error_log('[Dairy JWT] record_failure: IP ' . $ip . ' SOFT LOCKOUT 15min after ' . $attempts . ' attempts');
        }
    }

    private function record_success( string $ip ): void {
        // Clear attempt counter on successful login
        delete_transient($this->rl_key_attempts($ip));
        delete_transient($this->rl_key_lockout($ip));
        error_log('[Dairy JWT] record_success: IP ' . $ip . ' — attempt counter cleared');
    }

    // ── Cookie helpers ────────────────────────────────────

    private function set_access_cookie( string $token ): void {
        error_log('[Dairy JWT] setting access cookie (expires in ' . self::ACCESS_TTL . 's)');
        $this->set_cookie(self::COOKIE_ACCESS, $token, time() + self::ACCESS_TTL);
    }

    private function set_refresh_cookie( string $token ): void {
        error_log('[Dairy JWT] setting refresh cookie (expires in ' . self::REFRESH_TTL . 's)');
        $this->set_cookie(self::COOKIE_REFRESH, $token, time() + self::REFRESH_TTL);
    }

    private function set_cookie( string $name, string $value, int $expires ): void {
        $secure   = is_ssl();
        $site_url = parse_url(get_site_url());
        $path     = rtrim($site_url['path'] ?? '/', '/') . '/';

        // Use Lax for localhost dev origins, Strict for production
        // This allows cookie to be sent during local Flutter development
        $origin    = $_SERVER['HTTP_ORIGIN'] ?? $_SERVER['HTTP_REFERER'] ?? '';
        $is_local  = (
            str_contains($origin, 'localhost') ||
            str_contains($origin, '127.0.0.1') ||
            str_contains($origin, '::1')
        );
        $samesite  = $is_local ? 'None' : 'Strict';
        // None requires Secure flag — only allow in local dev over http if needed
        $use_secure = $is_local ? false : $secure;

        error_log('[Dairy JWT] set_cookie: name=' . $name . ' samesite=' . $samesite . ' origin=' . $origin);

        setcookie($name, $value, [
            'expires'  => $expires,
            'path'     => $path,
            'secure'   => $use_secure,
            'httponly' => true,
            'samesite' => $samesite,
        ]);
    }

    private function clear_cookies(): void {
        $site_url = parse_url(get_site_url());
        $path     = rtrim($site_url['path'] ?? '/', '/') . '/';
        $origin   = $_SERVER['HTTP_ORIGIN'] ?? $_SERVER['HTTP_REFERER'] ?? '';
        $is_local = str_contains($origin, 'localhost') || str_contains($origin, '127.0.0.1');
        $samesite = $is_local ? 'None' : 'Strict';
        foreach ([self::COOKIE_ACCESS, self::COOKIE_REFRESH] as $name) {
            if ( isset($_COOKIE[$name]) ) {
                setcookie($name, '', [
                    'expires'  => time() - 3600,
                    'path'     => $path,
                    'secure'   => $is_local ? false : is_ssl(),
                    'httponly' => true,
                    'samesite' => $samesite,
                ]);
            }
        }
    }

    private function secret(): string {
        if ( ! defined('DAIRY_JWT_SECRET') || strlen(DAIRY_JWT_SECRET) < 32 ) {
            error_log('[Dairy JWT] WARNING: DAIRY_JWT_SECRET not set or too short — falling back to AUTH_KEY. Set DAIRY_JWT_SECRET in wp-config.php');
        }
        return ( defined('DAIRY_JWT_SECRET') && strlen(DAIRY_JWT_SECRET) >= 32 )
               ? DAIRY_JWT_SECRET
               : AUTH_KEY;
    }

    private function ok( array $data, int $status = 200 ): WP_REST_Response {
        return new WP_REST_Response(['success' => true,  'data'    => $data], $status);
    }

    private function err( string $msg, int $status = 400 ): WP_REST_Response {
        return new WP_REST_Response(['success' => false, 'message' => $msg],  $status);
    }
    // ── Admin page ────────────────────────────────────────────

    public function register_admin_page(): void {
        add_submenu_page(
            'users.php',
            'Dairy Login Security',
            'Dairy Login Security',
            'manage_options',
            'dairy-login-security',
            [ $this, 'render_admin_page' ]
        );
    }

    public function render_admin_page(): void {
        global $wpdb;
        // Fetch all dairy rate limit transients
        $lockouts  = $wpdb->get_results(
            "SELECT option_name, option_value FROM {$wpdb->options}
             WHERE option_name LIKE '_transient_dairy_rl_lockout_%'
             ORDER BY option_name"
        );
        $attempts  = $wpdb->get_results(
            "SELECT option_name, option_value FROM {$wpdb->options}
             WHERE option_name LIKE '_transient_dairy_rl_attempts_%'
             ORDER BY option_name"
        );
        ?>
        <div class='wrap'>
        <h1>Dairy Login Security</h1>
        <h2>Active Lockouts (<?php echo count($lockouts); ?>)</h2>
        <?php if ( empty($lockouts) ): ?>
            <p>No active lockouts.</p>
        <?php else: ?>
            <table class='widefat striped'>
            <thead><tr><th>IP Hash</th><th>Lockout Duration</th><th>Action</th></tr></thead>
            <tbody>
            <?php foreach ( $lockouts as $row ):
                $hash     = str_replace('_transient_dairy_rl_lockout_', '', $row->option_name);
                $duration = (int) $row->option_value >= self::RL_LOCKOUT_2 ? '24 hours' : '15 minutes';
            ?>
            <tr>
                <td><code><?php echo esc_html($hash); ?></code></td>
                <td><?php echo esc_html($duration); ?></td>
                <td>
                    <form method='post' action='<?php echo admin_url('admin-post.php'); ?>'>
                        <?php wp_nonce_field('dairy_clear_lockout'); ?>
                        <input type='hidden' name='action' value='dairy_clear_lockout'>
                        <input type='hidden' name='hash' value='<?php echo esc_attr($hash); ?>'>
                        <button type='submit' class='button button-small'>Clear Lockout</button>
                    </form>
                </td>
            </tr>
            <?php endforeach; ?>
            </tbody></table>
        <?php endif; ?>

        <h2>Failed Attempt Counts (<?php echo count($attempts); ?> IPs)</h2>
        <?php if ( empty($attempts) ): ?>
            <p>No recorded attempts.</p>
        <?php else: ?>
            <table class='widefat striped'>
            <thead><tr><th>IP Hash</th><th>Failed Attempts</th><th>Action</th></tr></thead>
            <tbody>
            <?php foreach ( $attempts as $row ):
                $hash = str_replace('_transient_dairy_rl_attempts_', '', $row->option_name);
            ?>
            <tr>
                <td><code><?php echo esc_html($hash); ?></code></td>
                <td><?php echo esc_html($row->option_value); ?></td>
                <td>
                    <form method='post' action='<?php echo admin_url('admin-post.php'); ?>'>
                        <?php wp_nonce_field('dairy_clear_lockout'); ?>
                        <input type='hidden' name='action' value='dairy_clear_lockout'>
                        <input type='hidden' name='hash' value='<?php echo esc_attr($hash); ?>'>
                        <button type='submit' class='button button-small'>Clear</button>
                    </form>
                </td>
            </tr>
            <?php endforeach; ?>
            </tbody></table>
        <?php endif; ?>

        <h2>Clear All</h2>
        <form method='post' action='<?php echo admin_url('admin-post.php'); ?>'>
            <?php wp_nonce_field('dairy_clear_lockout'); ?>
            <input type='hidden' name='action' value='dairy_clear_lockout'>
            <input type='hidden' name='hash' value='all'>
            <button type='submit' class='button button-primary'>Clear All Lockouts & Attempts</button>
        </form>
        </div>
        <?php
    }

    public function handle_clear_lockout(): void {
        if ( ! current_user_can('manage_options') ) wp_die('Unauthorized');
        check_admin_referer('dairy_clear_lockout');

        $hash = sanitize_text_field($_POST['hash'] ?? '');

        if ( $hash === 'all' ) {
            global $wpdb;
            $wpdb->query(
                "DELETE FROM {$wpdb->options}
                 WHERE option_name LIKE '_transient_dairy_rl_%'
                    OR option_name LIKE '_transient_timeout_dairy_rl_%'"
            );
            error_log('[Dairy JWT] admin cleared ALL lockouts and attempt counters');
        } else {
            delete_transient('dairy_rl_lockout_'  . $hash);
            delete_transient('dairy_rl_attempts_' . $hash);
            error_log('[Dairy JWT] admin cleared lockout for hash: ' . $hash);
        }

        wp_redirect(admin_url('users.php?page=dairy-login-security&cleared=1'));
        exit;
    }

} // end class Dairy_JWT_Auth

error_log('[Dairy JWT] Plugin class instantiated');
new Dairy_JWT_Auth();

