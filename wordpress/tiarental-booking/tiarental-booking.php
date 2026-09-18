<?php
/**
 * Plugin Name: TIARENTAL Booking
 * Plugin URI: https://tiarental.com
 * Description: Connects a rental company's WordPress site to the vendor-scoped TIARENTAL Partner API.
 * Version: 1.0.0
 * Requires at least: 6.4
 * Requires PHP: 8.1
 * Author: TIARENTAL
 * License: GPL-2.0-or-later
 * Text Domain: tiarental-booking
 */

defined( 'ABSPATH' ) || exit;

define( 'TRB_VERSION', '1.0.0' );
define( 'TRB_FILE', __FILE__ );
define( 'TRB_DIR', plugin_dir_path( __FILE__ ) );
define( 'TRB_URL', plugin_dir_url( __FILE__ ) );

require_once TRB_DIR . 'includes/class-trb-crypto.php';
require_once TRB_DIR . 'includes/class-trb-api.php';
require_once TRB_DIR . 'includes/class-trb-rest.php';
require_once TRB_DIR . 'includes/class-trb-admin.php';
require_once TRB_DIR . 'includes/class-trb-shortcode.php';

register_activation_hook(
	__FILE__,
	static function () {
		if ( version_compare( PHP_VERSION, '8.1', '<' ) ) {
			deactivate_plugins( plugin_basename( __FILE__ ) );
			wp_die( esc_html__( 'TIARENTAL Booking requires PHP 8.1 or newer.', 'tiarental-booking' ) );
		}
		add_option(
			'trb_settings',
			array(
				'environment' => 'live',
				'api_url'     => 'https://api.tiarental.com/v1',
			),
			'',
			false
		);
	}
);

add_action(
	'plugins_loaded',
	static function () {
		load_plugin_textdomain( 'tiarental-booking', false, dirname( plugin_basename( __FILE__ ) ) . '/languages' );
		TRB_REST::init();
		TRB_Admin::init();
		TRB_Shortcode::init();
	}
);
