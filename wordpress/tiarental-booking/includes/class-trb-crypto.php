<?php
defined( 'ABSPATH' ) || exit;

final class TRB_Crypto {
	private static function key(): string {
		return hash( 'sha256', wp_salt( 'auth' ), true );
	}

	public static function encrypt( string $plain ): string {
		if ( '' === $plain ) {
			return '';
		}
		if ( function_exists( 'sodium_crypto_secretbox' ) ) {
			$nonce  = random_bytes( SODIUM_CRYPTO_SECRETBOX_NONCEBYTES );
			$cipher = sodium_crypto_secretbox( $plain, $nonce, self::key() );
			return 's1:' . base64_encode( $nonce . $cipher ); // phpcs:ignore WordPress.PHP.DiscouragedPHPFunctions.obfuscation_base64_encode
		}
		if ( function_exists( 'openssl_encrypt' ) ) {
			$iv     = random_bytes( 12 );
			$tag    = '';
			$cipher = openssl_encrypt( $plain, 'aes-256-gcm', self::key(), OPENSSL_RAW_DATA, $iv, $tag );
			if ( false !== $cipher ) {
				return 'o1:' . base64_encode( $iv . $tag . $cipher ); // phpcs:ignore WordPress.PHP.DiscouragedPHPFunctions.obfuscation_base64_encode
			}
		}
		return '';
	}

	public static function decrypt( string $encoded ): string {
		if ( '' === $encoded || strlen( $encoded ) < 4 ) {
			return '';
		}
		$raw = base64_decode( substr( $encoded, 3 ), true ); // phpcs:ignore WordPress.PHP.DiscouragedPHPFunctions.obfuscation_base64_decode
		if ( false === $raw ) {
			return '';
		}
		if ( str_starts_with( $encoded, 's1:' ) && function_exists( 'sodium_crypto_secretbox_open' ) ) {
			$nonce = substr( $raw, 0, SODIUM_CRYPTO_SECRETBOX_NONCEBYTES );
			$plain = sodium_crypto_secretbox_open( substr( $raw, SODIUM_CRYPTO_SECRETBOX_NONCEBYTES ), $nonce, self::key() );
			return false === $plain ? '' : $plain;
		}
		if ( str_starts_with( $encoded, 'o1:' ) && function_exists( 'openssl_decrypt' ) ) {
			$plain = openssl_decrypt( substr( $raw, 28 ), 'aes-256-gcm', self::key(), OPENSSL_RAW_DATA, substr( $raw, 0, 12 ), substr( $raw, 12, 16 ) );
			return false === $plain ? '' : $plain;
		}
		return '';
	}
}
