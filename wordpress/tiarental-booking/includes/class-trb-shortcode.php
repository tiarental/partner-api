<?php
defined( 'ABSPATH' ) || exit;

final class TRB_Shortcode {
	public static function init(): void {
		add_shortcode( 'tiarental_booking', array( __CLASS__, 'render' ) );
	}

	public static function render(): string {
		wp_enqueue_style( 'trb-booking', TRB_URL . 'assets/booking.css', array(), TRB_VERSION );
		wp_enqueue_script( 'trb-booking', TRB_URL . 'assets/booking.js', array(), TRB_VERSION, true );
		wp_localize_script(
			'trb-booking',
			'TRB_CONFIG',
			array(
				'carsUrl'     => esc_url_raw( rest_url( 'tiarental/v1/cars' ) ),
				'bookingsUrl' => esc_url_raw( rest_url( 'tiarental/v1/bookings' ) ),
				'currency'    => 'EUR',
			)
		);
		$today   = new DateTimeImmutable( 'tomorrow', wp_timezone() );
		$dropoff = $today->modify( '+3 days' );
		$id      = wp_unique_id( 'trb-booking-' );
		ob_start();
		?>
		<div class="trb-widget" id="<?php echo esc_attr( $id ); ?>" data-trb-widget>
			<form class="trb-search" data-trb-search>
				<div class="trb-heading"><span>TIARENTAL</span><h2><?php esc_html_e( 'Find your rental car', 'tiarental-booking' ); ?></h2><p><?php esc_html_e( 'Live cars, pricing and availability from the TIARENTAL Partner API.', 'tiarental-booking' ); ?></p></div>
				<label><?php esc_html_e( 'Pickup location', 'tiarental-booking' ); ?><input name="pickup_location" required maxlength="120" placeholder="Tirana International Airport"></label>
				<label><?php esc_html_e( 'Drop-off location', 'tiarental-booking' ); ?><input name="dropoff_location" required maxlength="120" placeholder="Tirana International Airport"></label>
				<label><?php esc_html_e( 'Pickup date', 'tiarental-booking' ); ?><input type="date" name="pickup_date" min="<?php echo esc_attr( $today->format( 'Y-m-d' ) ); ?>" value="<?php echo esc_attr( $today->format( 'Y-m-d' ) ); ?>" required></label>
				<label><?php esc_html_e( 'Pickup time', 'tiarental-booking' ); ?><input type="time" name="pickup_time" value="10:00" required><small data-trb-time-preview>10:00 AM</small></label>
				<label><?php esc_html_e( 'Drop-off date', 'tiarental-booking' ); ?><input type="date" name="dropoff_date" min="<?php echo esc_attr( $today->format( 'Y-m-d' ) ); ?>" value="<?php echo esc_attr( $dropoff->format( 'Y-m-d' ) ); ?>" required></label>
				<label><?php esc_html_e( 'Drop-off time', 'tiarental-booking' ); ?><input type="time" name="dropoff_time" value="10:00" required><small data-trb-time-preview>10:00 AM</small></label>
				<button type="submit" class="trb-primary"><?php esc_html_e( 'Search cars', 'tiarental-booking' ); ?></button>
			</form>
			<div class="trb-status" data-trb-status aria-live="polite"></div>
			<div class="trb-results" data-trb-results></div>
			<section class="trb-customer" data-trb-customer hidden>
				<header><button type="button" data-trb-back aria-label="<?php esc_attr_e( 'Back to cars', 'tiarental-booking' ); ?>">←</button><div><span><?php esc_html_e( 'Selected vehicle', 'tiarental-booking' ); ?></span><h3 data-trb-selected></h3></div></header>
				<form data-trb-customer-form>
					<input type="text" name="website" tabindex="-1" autocomplete="off" class="trb-honeypot" aria-hidden="true">
					<label><?php esc_html_e( 'First name', 'tiarental-booking' ); ?><input name="first_name" required maxlength="100" autocomplete="given-name"></label>
					<label><?php esc_html_e( 'Last name', 'tiarental-booking' ); ?><input name="last_name" required maxlength="100" autocomplete="family-name"></label>
					<label><?php esc_html_e( 'Email', 'tiarental-booking' ); ?><input type="email" name="email" required maxlength="320" autocomplete="email"></label>
					<label><?php esc_html_e( 'Phone / WhatsApp', 'tiarental-booking' ); ?><input type="tel" name="phone" required minlength="7" maxlength="40" autocomplete="tel"></label>
					<label><?php esc_html_e( 'Driver age', 'tiarental-booking' ); ?><input type="number" name="age" required min="18" max="90" value="25"></label>
					<label><?php esc_html_e( 'Years driving', 'tiarental-booking' ); ?><input type="number" name="driving_years" required min="0" max="72" value="5"></label>
					<label><?php esc_html_e( 'Country', 'tiarental-booking' ); ?><input name="country" maxlength="100" autocomplete="country-name"></label>
					<label class="wide"><?php esc_html_e( 'Notes', 'tiarental-booking' ); ?><textarea name="notes" maxlength="2000" rows="3"></textarea></label>
					<button type="submit" class="trb-primary"><?php esc_html_e( 'Confirm booking request', 'tiarental-booking' ); ?></button>
				</form>
			</section>
		</div>
		<?php
		return (string) ob_get_clean();
	}
}
