<?php
defined( 'ABSPATH' ) || exit;

final class TRB_REST {
	public static function init(): void {
		add_action( 'rest_api_init', array( __CLASS__, 'routes' ) );
	}

	public static function routes(): void {
		register_rest_route( 'tiarental/v1', '/cars', array( 'methods' => 'GET', 'callback' => array( __CLASS__, 'cars' ), 'permission_callback' => '__return_true' ) );
		register_rest_route( 'tiarental/v1', '/bookings', array( 'methods' => 'POST', 'callback' => array( __CLASS__, 'booking' ), 'permission_callback' => '__return_true' ) );
		register_rest_route( 'tiarental/v1', '/webhook', array( 'methods' => 'POST', 'callback' => array( __CLASS__, 'webhook' ), 'permission_callback' => '__return_true' ) );
		register_rest_route( 'tiarental/v1', '/blocks', array( 'methods' => 'POST', 'callback' => array( __CLASS__, 'block' ), 'permission_callback' => static fn() => current_user_can( 'manage_options' ) ) );
		register_rest_route( 'tiarental/v1', '/bookings/(?P<id>[0-9a-f-]{36})/cancel', array( 'methods' => 'POST', 'callback' => array( __CLASS__, 'cancel' ), 'permission_callback' => static fn() => current_user_can( 'manage_options' ) ) );
	}

	private static function rate_limit( string $bucket, int $limit ): bool {
		$ip  = sanitize_text_field( (string) ( $_SERVER['REMOTE_ADDR'] ?? 'unknown' ) );
		$key = 'trb_rl_' . md5( $bucket . '|' . $ip );
		$n   = (int) get_transient( $key );
		if ( $n >= $limit ) {
			return false;
		}
		set_transient( $key, $n + 1, HOUR_IN_SECONDS );
		return true;
	}

	private static function upstream( $value ) {
		if ( is_wp_error( $value ) ) {
			$data   = $value->get_error_data();
			$status = is_array( $data ) ? (int) ( $data['status'] ?? 502 ) : 502;
			return new WP_REST_Response( array( 'error' => array( 'code' => $value->get_error_code(), 'message' => $value->get_error_message() ) ), $status );
		}
		return rest_ensure_response( $value );
	}

	public static function cars( WP_REST_Request $request ) {
		$query = array();
		foreach ( array( 'pickup_at', 'dropoff_at', 'pickup_location', 'dropoff_location', 'category', 'transmission' ) as $key ) {
			$query[ $key ] = sanitize_text_field( (string) $request->get_param( $key ) );
		}
		$query['limit'] = min( 100, max( 1, absint( $request->get_param( 'limit' ) ?: 50 ) ) );
		return self::upstream( TRB_API::request( 'GET', '/cars', array(), $query ) );
	}

	public static function booking( WP_REST_Request $request ) {
		if ( ! self::rate_limit( 'booking', 10 ) ) {
			return new WP_Error( 'rate_limited', __( 'Too many booking attempts. Try again later.', 'tiarental-booking' ), array( 'status' => 429 ) );
		}
		$params = (array) $request->get_json_params();
		if ( ! empty( $params['website'] ) ) {
			return new WP_Error( 'invalid_request', __( 'Invalid form submission.', 'tiarental-booking' ), array( 'status' => 422 ) );
		}
		$customer    = is_array( $params['customer'] ?? null ) ? $params['customer'] : array();
		$idempotency = sanitize_text_field( (string) ( $params['idempotency_key'] ?? wp_generate_uuid4() ) );
		$body     = array(
			'car_id'                => sanitize_text_field( (string) ( $params['car_id'] ?? '' ) ),
			'pickup_at'              => sanitize_text_field( (string) ( $params['pickup_at'] ?? '' ) ),
			'dropoff_at'             => sanitize_text_field( (string) ( $params['dropoff_at'] ?? '' ) ),
			'pickup_location'        => sanitize_text_field( (string) ( $params['pickup_location'] ?? '' ) ),
			'dropoff_location'       => sanitize_text_field( (string) ( $params['dropoff_location'] ?? '' ) ),
			'booking_mode'           => 'instant' === ( $params['booking_mode'] ?? '' ) ? 'instant' : 'request',
			'external_reference'     => 'wp_' . substr( preg_replace( '/[^A-Za-z0-9_-]/', '', $idempotency ), 0, 180 ),
			'cross_border_countries' => array_map( 'sanitize_text_field', array_slice( (array) ( $params['cross_border_countries'] ?? array() ), 0, 20 ) ),
			'customer'               => array(
				'first_name'    => sanitize_text_field( (string) ( $customer['first_name'] ?? '' ) ),
				'last_name'     => sanitize_text_field( (string) ( $customer['last_name'] ?? '' ) ),
				'email'         => sanitize_email( (string) ( $customer['email'] ?? '' ) ),
				'phone'         => sanitize_text_field( (string) ( $customer['phone'] ?? '' ) ),
				'age'           => absint( $customer['age'] ?? 0 ),
				'driving_years' => absint( $customer['driving_years'] ?? 0 ),
				'country'       => sanitize_text_field( (string) ( $customer['country'] ?? '' ) ),
				'notes'         => sanitize_textarea_field( (string) ( $customer['notes'] ?? '' ) ),
			),
		);
		return self::upstream( TRB_API::request( 'POST', '/bookings', $body, array(), $idempotency ) );
	}

	public static function block( WP_REST_Request $request ) {
		$params = (array) $request->get_json_params();
		$body   = array(
			'car_id'            => sanitize_text_field( (string) ( $params['car_id'] ?? '' ) ),
			'start_at'          => sanitize_text_field( (string) ( $params['start_at'] ?? '' ) ),
			'end_at'            => sanitize_text_field( (string) ( $params['end_at'] ?? '' ) ),
			'type'              => 'external_booking' === ( $params['type'] ?? '' ) ? 'external_booking' : 'manual_block',
			'external_reference'=> sanitize_text_field( (string) ( $params['external_reference'] ?? 'wordpress-manual' ) ),
		);
		return self::upstream( TRB_API::request( 'POST', '/availability/blocks', $body, array(), sanitize_text_field( (string) ( $params['idempotency_key'] ?? wp_generate_uuid4() ) ) ) );
	}

	public static function cancel( WP_REST_Request $request ) {
		$body = (array) $request->get_json_params();
		return self::upstream( TRB_API::request( 'POST', '/bookings/' . sanitize_text_field( (string) $request['id'] ) . '/cancel', array( 'reason' => sanitize_text_field( (string) ( $body['reason'] ?? 'Cancelled in WordPress' ) ) ), array(), sanitize_text_field( (string) ( $body['idempotency_key'] ?? wp_generate_uuid4() ) ) ) );
	}

	public static function webhook( WP_REST_Request $request ) {
		$settings  = TRB_API::settings();
		$secret    = TRB_Crypto::decrypt( (string) ( $settings['webhook_secret'] ?? '' ) );
		$signature = (string) $request->get_header( 'x-tiarental-signature' );
		$event_id  = sanitize_text_field( (string) $request->get_header( 'x-tiarental-event-id' ) );
		if ( '' === $secret || ! preg_match( '/^t=(\d+),v1=([a-f0-9]{64})$/', $signature, $matches ) || abs( time() - (int) $matches[1] ) > 300 ) {
			return new WP_Error( 'invalid_signature', __( 'Invalid webhook signature.', 'tiarental-booking' ), array( 'status' => 401 ) );
		}
		$expected = hash_hmac( 'sha256', $matches[1] . '.' . $request->get_body(), $secret );
		if ( ! hash_equals( $expected, $matches[2] ) ) {
			return new WP_Error( 'invalid_signature', __( 'Invalid webhook signature.', 'tiarental-booking' ), array( 'status' => 401 ) );
		}
		if ( '' !== $event_id && get_transient( 'trb_event_' . md5( $event_id ) ) ) {
			return rest_ensure_response( array( 'received' => true, 'duplicate' => true ) );
		}
		if ( '' !== $event_id ) {
			set_transient( 'trb_event_' . md5( $event_id ), 1, 7 * DAY_IN_SECONDS );
		}
		delete_transient( 'trb_catalog' );
		update_option( 'trb_last_webhook', current_time( 'mysql', true ), false );
		update_option( 'trb_last_event', sanitize_text_field( (string) $request->get_header( 'x-tiarental-event' ) ), false );
		return rest_ensure_response( array( 'received' => true ) );
	}
}
