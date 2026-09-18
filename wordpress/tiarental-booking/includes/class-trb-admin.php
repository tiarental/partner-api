<?php
defined( 'ABSPATH' ) || exit;

final class TRB_Admin {
	public static function init(): void {
		add_action( 'admin_menu', array( __CLASS__, 'menu' ) );
		add_action( 'admin_enqueue_scripts', array( __CLASS__, 'assets' ) );
		foreach ( array( 'save', 'test', 'sync', 'webhook', 'block', 'cancel', 'disconnect' ) as $action ) {
			add_action( 'admin_post_trb_' . $action, array( __CLASS__, 'handle_' . $action ) );
		}
	}

	public static function menu(): void {
		add_menu_page( 'TIARENTAL', 'TIARENTAL', 'manage_options', 'tiarental-booking', array( __CLASS__, 'page' ), 'dashicons-calendar-alt', 58 );
	}

	public static function assets( string $hook ): void {
		if ( 'toplevel_page_tiarental-booking' !== $hook ) {
			return;
		}
		wp_enqueue_style( 'trb-admin', TRB_URL . 'assets/admin.css', array(), TRB_VERSION );
	}

	private static function guard( string $action ): void {
		if ( ! current_user_can( 'manage_options' ) ) {
			wp_die( esc_html__( 'You are not allowed to manage this integration.', 'tiarental-booking' ) );
		}
		check_admin_referer( 'trb_' . $action );
	}

	private static function flash( string $message, string $type = 'success' ): void {
		set_transient( 'trb_notice_' . get_current_user_id(), array( 'message' => $message, 'type' => $type ), MINUTE_IN_SECONDS );
		wp_safe_redirect( admin_url( 'admin.php?page=tiarental-booking' ) );
		exit;
	}

	private static function api_error( $result ): string {
		return is_wp_error( $result ) ? $result->get_error_message() : __( 'The request could not be completed.', 'tiarental-booking' );
	}

	public static function handle_save(): void {
		self::guard( 'save' );
		$current     = TRB_API::settings();
		$environment = 'test' === ( $_POST['environment'] ?? '' ) ? 'test' : 'live';
		$api_url     = untrailingslashit( esc_url_raw( wp_unslash( (string) ( $_POST['api_url'] ?? '' ) ) ) );
		$key         = trim( sanitize_text_field( wp_unslash( (string) ( $_POST['api_key'] ?? '' ) ) ) );
		if ( ! wp_http_validate_url( $api_url ) || ( 'https' !== wp_parse_url( $api_url, PHP_URL_SCHEME ) && 'production' === wp_get_environment_type() ) ) {
			self::flash( __( 'Enter a valid HTTPS Partner API URL.', 'tiarental-booking' ), 'error' );
		}
		if ( '' !== $key && ! preg_match( '/^tr_' . $environment . '_[A-Za-z0-9_-]{32,}$/', $key ) ) {
			self::flash( __( 'The API key format does not match the selected environment.', 'tiarental-booking' ), 'error' );
		}
		$current['environment'] = $environment;
		$current['api_url']     = $api_url;
		if ( '' !== $key ) {
			$encrypted = TRB_Crypto::encrypt( $key );
			if ( '' === $encrypted ) {
				self::flash( __( 'This server cannot securely encrypt the API key.', 'tiarental-booking' ), 'error' );
			}
			$current['api_key']    = $encrypted;
			$current['key_masked'] = substr( $key, 0, 12 ) . '••••••••••••';
			unset( $current['vendor'], $current['app'], $current['webhook_secret'], $current['webhook_id'] );
		}
		update_option( 'trb_settings', $current, false );
		delete_transient( 'trb_catalog' );
		self::flash( __( 'Connection settings saved. Use “Test connection” to verify them.', 'tiarental-booking' ) );
	}

	public static function handle_test(): void {
		self::guard( 'test' );
		$result = TRB_API::request( 'GET', '/me' );
		if ( is_wp_error( $result ) ) {
			self::flash( self::api_error( $result ), 'error' );
		}
		$data                 = (array) ( $result['data'] ?? array() );
		$settings             = TRB_API::settings();
		$settings['vendor']   = (array) ( $data['vendor'] ?? array() );
		$settings['app']      = (array) ( $data['partner_app'] ?? array() );
		$settings['connected_at'] = gmdate( 'c' );
		update_option( 'trb_settings', $settings, false );
		self::flash( sprintf( __( 'Connected to TIARENTAL as %s.', 'tiarental-booking' ), sanitize_text_field( (string) ( $settings['vendor']['name'] ?? '' ) ) ) );
	}

	public static function handle_sync(): void {
		self::guard( 'sync' );
		$result = TRB_API::request( 'GET', '/cars', array(), array( 'limit' => 100 ) );
		if ( is_wp_error( $result ) ) {
			update_option( 'trb_sync_error', $result->get_error_message(), false );
			self::flash( self::api_error( $result ), 'error' );
		}
		$cars = is_array( $result['data'] ?? null ) ? $result['data'] : array();
		set_transient( 'trb_catalog', $cars, 15 * MINUTE_IN_SECONDS );
		update_option( 'trb_last_sync', gmdate( 'c' ), false );
		update_option( 'trb_sync_count', count( $cars ), false );
		delete_option( 'trb_sync_error' );
		self::flash( sprintf( __( 'Synchronization completed: %d cars.', 'tiarental-booking' ), count( $cars ) ) );
	}

	public static function handle_webhook(): void {
		self::guard( 'webhook' );
		$callback = rest_url( 'tiarental/v1/webhook' );
		$result   = TRB_API::request(
			'POST',
			'/webhooks',
			array(
				'url'    => $callback,
				'events' => array( 'booking.created', 'booking.confirmed', 'booking.rejected', 'booking.cancelled', 'booking.modified', 'availability.blocked', 'availability.unblocked', 'car.updated', 'price.updated' ),
			)
		);
		if ( is_wp_error( $result ) ) {
			self::flash( self::api_error( $result ), 'error' );
		}
		$data      = (array) ( $result['data'] ?? array() );
		$secret    = (string) ( $data['secret'] ?? '' );
		$encrypted = TRB_Crypto::encrypt( $secret );
		if ( '' === $secret || '' === $encrypted ) {
			self::flash( __( 'Webhook was created but its secret could not be stored securely. Delete it in TIARENTAL and retry.', 'tiarental-booking' ), 'error' );
		}
		$settings                   = TRB_API::settings();
		$settings['webhook_id']     = sanitize_text_field( (string) ( $data['id'] ?? '' ) );
		$settings['webhook_secret'] = $encrypted;
		$settings['webhook_url']    = esc_url_raw( $callback );
		update_option( 'trb_settings', $settings, false );
		self::flash( __( 'Signed webhook connected.', 'tiarental-booking' ) );
	}

	private static function utc_iso( string $value ): string {
		$date = DateTimeImmutable::createFromFormat( 'Y-m-d\\TH:i', $value, wp_timezone() );
		return $date ? $date->setTimezone( new DateTimeZone( 'UTC' ) )->format( 'c' ) : '';
	}

	public static function handle_block(): void {
		self::guard( 'block' );
		$start = self::utc_iso( sanitize_text_field( wp_unslash( (string) ( $_POST['start_at'] ?? '' ) ) ) );
		$end   = self::utc_iso( sanitize_text_field( wp_unslash( (string) ( $_POST['end_at'] ?? '' ) ) );
		$result = TRB_API::request(
			'POST',
			'/availability/blocks',
			array(
				'car_id'            => sanitize_text_field( wp_unslash( (string) ( $_POST['car_id'] ?? '' ) ) ),
				'start_at'          => $start,
				'end_at'            => $end,
				'type'              => 'external_booking' === ( $_POST['type'] ?? '' ) ? 'external_booking' : 'manual_block',
				'external_reference'=> sanitize_text_field( wp_unslash( (string) ( $_POST['reason'] ?? 'WordPress manual block' ) ) ),
			),
			array(),
			wp_generate_uuid4()
		);
		if ( is_wp_error( $result ) ) {
			self::flash( self::api_error( $result ), 'error' );
		}
		delete_transient( 'trb_catalog' );
		self::flash( __( 'Dates blocked in TIARENTAL.', 'tiarental-booking' ) );
	}

	public static function handle_cancel(): void {
		self::guard( 'cancel' );
		$id = sanitize_text_field( wp_unslash( (string) ( $_POST['booking_id'] ?? '' ) ) );
		if ( ! preg_match( '/^[0-9a-f-]{36}$/i', $id ) ) {
			self::flash( __( 'Enter a valid booking UUID.', 'tiarental-booking' ), 'error' );
		}
		$result = TRB_API::request( 'POST', '/bookings/' . $id . '/cancel', array( 'reason' => sanitize_text_field( wp_unslash( (string) ( $_POST['reason'] ?? 'Cancelled in WordPress' ) ) ) ), array(), wp_generate_uuid4() );
		if ( is_wp_error( $result ) ) {
			self::flash( self::api_error( $result ), 'error' );
		}
		self::flash( __( 'Booking cancelled in TIARENTAL.', 'tiarental-booking' ) );
	}

	public static function handle_disconnect(): void {
		self::guard( 'disconnect' );
		update_option( 'trb_settings', array( 'environment' => 'live', 'api_url' => 'https://api.tiarental.com/v1' ), false );
		delete_transient( 'trb_catalog' );
		self::flash( __( 'Local TIARENTAL credentials removed. Revoke the API key in the TIARENTAL Vendor Dashboard too.', 'tiarental-booking' ) );
	}

	private static function form_button( string $action, string $label, string $class = 'button' ): void {
		?>
		<form method="post" action="<?php echo esc_url( admin_url( 'admin-post.php' ) ); ?>">
			<input type="hidden" name="action" value="<?php echo esc_attr( 'trb_' . $action ); ?>">
			<?php wp_nonce_field( 'trb_' . $action ); ?>
			<button class="<?php echo esc_attr( $class ); ?>" type="submit"><?php echo esc_html( $label ); ?></button>
		</form>
		<?php
	}

	private static function catalog(): array {
		$cars = get_transient( 'trb_catalog' );
		return is_array( $cars ) ? $cars : array();
	}

	public static function page(): void {
		if ( ! current_user_can( 'manage_options' ) ) {
			return;
		}
		$settings = TRB_API::settings();
		$vendor   = (array) ( $settings['vendor'] ?? array() );
		$app      = (array) ( $settings['app'] ?? array() );
		$notice   = get_transient( 'trb_notice_' . get_current_user_id() );
		delete_transient( 'trb_notice_' . get_current_user_id() );
		$connected = TRB_API::configured() && ! empty( $vendor['id'] );
		$cars      = self::catalog();
		?>
		<div class="wrap trb-admin"><h1>TIARENTAL Booking</h1>
		<?php if ( is_array( $notice ) ) : ?><div class="notice notice-<?php echo esc_attr( 'error' === $notice['type'] ? 'error' : 'success' ); ?> is-dismissible"><p><?php echo esc_html( $notice['message'] ); ?></p></div><?php endif; ?>
		<section class="trb-health"><h2><?php esc_html_e( 'Connection health', 'tiarental-booking' ); ?></h2><div class="trb-health-grid">
			<div><b><?php echo $connected ? '✓' : '⚠'; ?></b><span>API</span><strong><?php echo esc_html( $connected ? __( 'Connected', 'tiarental-booking' ) : __( 'Not verified', 'tiarental-booking' ) ); ?></strong></div>
			<div><b>↻</b><span><?php esc_html_e( 'Last successful sync', 'tiarental-booking' ); ?></span><strong><?php echo esc_html( (string) get_option( 'trb_last_sync', __( 'Never', 'tiarental-booking' ) ) ); ?></strong></div>
			<div><b>⇄</b><span><?php esc_html_e( 'Last webhook', 'tiarental-booking' ); ?></span><strong><?php echo esc_html( (string) get_option( 'trb_last_webhook', __( 'Never', 'tiarental-booking' ) ) ); ?></strong></div>
			<div><b><?php echo esc_html( (string) get_option( 'trb_sync_count', 0 ) ); ?></b><span><?php esc_html_e( 'Cars', 'tiarental-booking' ); ?></span><strong><?php echo esc_html( (string) get_option( 'trb_sync_error', __( 'Synchronized', 'tiarental-booking' ) ) ); ?></strong></div>
		</div><div class="trb-actions"><?php self::form_button( 'test', __( 'Test connection', 'tiarental-booking' ), 'button button-primary' ); self::form_button( 'sync', __( 'Sync now', 'tiarental-booking' ) ); self::form_button( 'webhook', __( 'Connect webhook', 'tiarental-booking' ) ); ?></div></section>

		<section class="trb-card"><h2><?php esc_html_e( 'Connection settings', 'tiarental-booking' ); ?></h2>
		<?php if ( $connected ) : ?><p class="trb-connected">✓ <?php echo esc_html( (string) ( $vendor['name'] ?? '' ) ); ?> · <?php echo esc_html( (string) ( $app['name'] ?? 'WordPress' ) ); ?></p><?php endif; ?>
		<form method="post" action="<?php echo esc_url( admin_url( 'admin-post.php' ) ); ?>"><input type="hidden" name="action" value="trb_save"><?php wp_nonce_field( 'trb_save' ); ?>
			<label><?php esc_html_e( 'Environment', 'tiarental-booking' ); ?><select name="environment"><option value="live" <?php selected( $settings['environment'] ?? 'live', 'live' ); ?>>Live</option><option value="test" <?php selected( $settings['environment'] ?? '', 'test' ); ?>>Test</option></select></label>
			<label><?php esc_html_e( 'Partner API URL', 'tiarental-booking' ); ?><input type="url" name="api_url" required value="<?php echo esc_attr( (string) ( $settings['api_url'] ?? 'https://api.tiarental.com/v1' ) ); ?>"></label>
			<label><?php esc_html_e( 'API key', 'tiarental-booking' ); ?><input type="password" name="api_key" autocomplete="new-password" placeholder="<?php echo esc_attr( (string) ( $settings['key_masked'] ?? 'tr_live_…' ) ); ?>"><small><?php esc_html_e( 'Leave blank to keep the encrypted key already saved.', 'tiarental-booking' ); ?></small></label>
			<?php submit_button( __( 'Save settings', 'tiarental-booking' ) ); ?>
		</form></section>

		<section class="trb-card"><h2><?php esc_html_e( 'Manual availability block', 'tiarental-booking' ); ?></h2><p><?php esc_html_e( 'Blocks are written to TIARENTAL, which remains the source of truth.', 'tiarental-booking' ); ?></p>
		<form class="trb-grid-form" method="post" action="<?php echo esc_url( admin_url( 'admin-post.php' ) ); ?>"><input type="hidden" name="action" value="trb_block"><?php wp_nonce_field( 'trb_block' ); ?>
			<label><?php esc_html_e( 'Car', 'tiarental-booking' ); ?><select name="car_id" required><option value=""><?php esc_html_e( 'Select car', 'tiarental-booking' ); ?></option><?php foreach ( $cars as $car ) : ?><option value="<?php echo esc_attr( (string) ( $car['id'] ?? '' ) ); ?>"><?php echo esc_html( trim( (string) ( $car['brand'] ?? '' ) . ' ' . (string) ( $car['model'] ?? '' ) ) ); ?></option><?php endforeach; ?></select></label>
			<label><?php esc_html_e( 'Start', 'tiarental-booking' ); ?><input type="datetime-local" name="start_at" required></label><label><?php esc_html_e( 'End', 'tiarental-booking' ); ?><input type="datetime-local" name="end_at" required></label>
			<label><?php esc_html_e( 'Type', 'tiarental-booking' ); ?><select name="type"><option value="manual_block"><?php esc_html_e( 'Manual block', 'tiarental-booking' ); ?></option><option value="external_booking"><?php esc_html_e( 'Direct/offline booking', 'tiarental-booking' ); ?></option></select></label>
			<label class="wide"><?php esc_html_e( 'Reason / reference', 'tiarental-booking' ); ?><input type="text" name="reason" maxlength="200" value="Direct customer"></label><button class="button button-primary" type="submit"><?php esc_html_e( 'Block dates', 'tiarental-booking' ); ?></button>
		</form><?php if ( ! $cars ) : ?><p class="description"><?php esc_html_e( 'Run Sync now to load the car selector.', 'tiarental-booking' ); ?></p><?php endif; ?></section>

		<section class="trb-card"><h2><?php esc_html_e( 'Cancel a WordPress booking', 'tiarental-booking' ); ?></h2><form class="trb-grid-form" method="post" action="<?php echo esc_url( admin_url( 'admin-post.php' ) ); ?>"><input type="hidden" name="action" value="trb_cancel"><?php wp_nonce_field( 'trb_cancel' ); ?><label><?php esc_html_e( 'Booking UUID', 'tiarental-booking' ); ?><input name="booking_id" required pattern="[0-9a-fA-F-]{36}"></label><label class="wide"><?php esc_html_e( 'Reason', 'tiarental-booking' ); ?><input name="reason" required maxlength="500" value="Cancelled by vendor in WordPress"></label><button class="button" type="submit"><?php esc_html_e( 'Cancel booking', 'tiarental-booking' ); ?></button></form></section>

		<section class="trb-card trb-danger"><h2><?php esc_html_e( 'Disconnect locally', 'tiarental-booking' ); ?></h2><p><?php esc_html_e( 'This removes the key and webhook secret from WordPress. Revoke the key in the TIARENTAL Vendor Dashboard as well.', 'tiarental-booking' ); ?></p><?php self::form_button( 'disconnect', __( 'Remove local credentials', 'tiarental-booking' ) ); ?></section>
		</div>
		<?php
	}
}
