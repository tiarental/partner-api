<?php
defined( 'WP_UNINSTALL_PLUGIN' ) || exit;
delete_option( 'trb_settings' );
delete_option( 'trb_last_sync' );
delete_option( 'trb_last_webhook' );
delete_option( 'trb_last_event' );
delete_option( 'trb_sync_count' );
delete_option( 'trb_sync_error' );
delete_transient( 'trb_catalog' );
