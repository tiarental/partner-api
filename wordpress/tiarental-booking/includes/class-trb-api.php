<?php
defined( 'ABSPATH' ) || exit;

final class TRB_API {
	public static function settings(): array {
		$value = get_option( 'trb_settings', array() );
		return is_array( $value ) ? $value : array();
	}

	public static function api_key(): string {
		$settings = self::settings();
		return TRB_Crypto::decrypt( (string) ( $settings['api_key'] ?? '' ) );
	}

	public static function base_url(): string {
		$settings = self::settings();
		return untrailingslashit( (string) ( $settings['api_url'] ?? 'https://api.tiarental.com/v1' ) );
	}

	public static function configured(): bool {
		return (bool) preg_match( '/^tr_(test|live)_[A-Za-z0-9_-]{32,}$/', self::api_key() );
	}

	public static function request( string $method, string $path, array $body = array(), array $query = array(), string $idempotency_key = '' ) {
		$key = self::api_key();
		if ( '' === $key ) {
			return new WP_Error( 'trb_not_connected', __( 'TIARENTAL API key is not configured.', 'tiarental-booking' ) );
		}
		$url = self::base_url() . '/' . ltrim( $path, '/' );
		if ( $query ) {
			$url = add_query_arg( array_filter( $query, static fn( $value ) => null !== $value && '' !== $value ), $url );
		}
		$args = array(
			'method'      => strtoupper( $method ),
			'timeout'     => 15,
			'redirection' => 0,
			'headers'     => array(
				'Authorization' => 'Bearer ' . $key,
				'Accept'        => 'application/json',
				'User-Agent'    => 'TIARENTAL-WordPress/' . TRB_VERSION . '; ' . home_url( '/' ),
			),
		);
		if ( $body || in_array( strtoupper( $method ), array( 'POST', 'PATCH', 'PUT' ), true ) ) {
			$args['headers']['Content-Type'] = 'application/json';
			$args['body']                    = wp_json_encode( $body );
		}
		if ( '' !== $idempotency_key ) {
			$args['headers']['Idempotency-Key'] = sanitize_text_field( $idempotency_key );
		}
		$response = wp_safe_remote_request( $url, $args );
		if ( is_wp_error( $response ) ) {
			return $response;
		}
		$status  = (int) wp_remote_retrieve_response_code( $response );
		$decoded = json_decode( wp_remote_retrieve_body( $response ), true );
		if ( ! is_array( $decoded ) ) {
			return new WP_Error( 'trb_invalid_response', __( 'TIARENTAL returned an invalid response.', 'tiarental-booking' ), array( 'status' => 502 ) );
		}
		if ( $status < 200 || $status >= 300 ) {
			$error = is_array( $decoded['error'] ?? null ) ? $decoded['error'] : array();
			return new WP_Error(
				sanitize_key( (string) ( $error['code'] ?? 'trb_api_error' ) ),
				sanitize_text_field( (string) ( $error['message'] ?? __( 'TIARENTAL API request failed.', 'tiarental-booking' ) ) ),
				array( 'status' => $status, 'request_id' => sanitize_text_field( (string) ( $error['request_id'] ?? '' ) ) )
			);
		}
		return $decoded;
	}
}
