#!perl -T

use Test::More tests => 9;

BEGIN {
	use_ok( 'Cafe::Application' );
	use_ok( 'Cafe::Base' );
	use_ok( 'Cafe::Class' );
	use_ok( 'Cafe::Filters' );
	use_ok( 'Cafe::Listing' );
	use_ok( 'Cafe::NamedQuery' );
	use_ok( 'Cafe::Path' );
	use_ok( 'Cafe::Script' );
}

diag( "Testing Cafe::Application $Cafe::Application::VERSION, Perl $], $^X" );
