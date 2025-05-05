<?php
// Docker-style environment variable fallback helper
if (!function_exists('getenv_docker')) {
	function getenv_docker($env, $default) {
		if ($fileEnv = getenv($env . '_FILE')) {
			return rtrim(file_get_contents($fileEnv), "\r\n");
		} elseif (($val = getenv($env)) !== false) {
			return $val;
		} else {
			return $default;
		}
	}
}

// === Database Settings ===
define( 'DB_NAME',     getenv_docker('IWB_WP_MYSQL_DATABASE', 'wordpress') );
define( 'DB_USER',     getenv_docker('IWB_WP_MYSQL_USER', 'iwbuser') );
define( 'DB_PASSWORD', getenv_docker('IWB_WP_MYSQL_PASSWORD', 'insecure') );
define( 'DB_HOST',     getenv_docker('IWB_WP_MYSQL_HOST', 'localhost') );
define( 'DB_CHARSET',  'utf8mb4' );
define( 'DB_COLLATE',  '' );

// === Table Prefix ===
$table_prefix = getenv_docker('IWB_WP_TABLE_PREFIX', 'wp_');

// === Authentication Keys and Salts ===
define( 'AUTH_KEY',         getenv_docker('IWB_WP_AUTH_KEY',         'put your unique phrase here') );
define( 'SECURE_AUTH_KEY',  getenv_docker('IWB_WP_SECURE_AUTH_KEY',  'put your unique phrase here') );
define( 'LOGGED_IN_KEY',    getenv_docker('IWB_WP_LOGGED_IN_KEY',    'put your unique phrase here') );
define( 'NONCE_KEY',        getenv_docker('IWB_WP_NONCE_KEY',        'put your unique phrase here') );
define( 'AUTH_SALT',        getenv_docker('IWB_WP_AUTH_SALT',        'put your unique phrase here') );
define( 'SECURE_AUTH_SALT', getenv_docker('IWB_WP_SECURE_AUTH_SALT', 'put your unique phrase here') );
define( 'LOGGED_IN_SALT',   getenv_docker('IWB_WP_LOGGED_IN_SALT',   'put your unique phrase here') );
define( 'NONCE_SALT',       getenv_docker('IWB_WP_NONCE_SALT',       'put your unique phrase here') );

// === WordPress Site URLs ===
define( 'WP_SITEURL', getenv_docker('IWB_WP_SITEURL', 'http://example.com') );
define( 'WP_HOME',    getenv_docker('IWB_WP_HOME',    'http://example.com') );

// === Debug and Cron ===
define( 'WP_DEBUG', !!getenv_docker('IWB_WP_DEBUG', '') );
define( 'DISABLE_WP_CRON', true ); // We use system cron

// === Reverse Proxy HTTPS Support ===
if (isset($_SERVER['HTTP_X_FORWARDED_PROTO']) && strpos($_SERVER['HTTP_X_FORWARDED_PROTO'], 'https') !== false) {
	$_SERVER['HTTPS'] = 'on';
}

// === Optional Extra Config via ENV ===
if ($configExtra = getenv_docker('IWB_WP_CONFIG_EXTRA', '')) {
	eval($configExtra);
}

// === Final Setup ===
if ( ! defined( 'ABSPATH' ) ) {
	define( 'ABSPATH', __DIR__ . '/' );
}
require_once ABSPATH . 'wp-settings.php';
