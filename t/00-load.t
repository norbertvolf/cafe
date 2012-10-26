#/usr/bin/perl -T

use Test::More tests => 11;

BEGIN {
	use_ok('Mojolicious::Cafe::Base');
	use_ok('Mojolicious::Cafe::Base');
	use_ok('Mojolicious::Cafe::Class::Versioned');
	use_ok('Mojolicious::Cafe::Class');
	use_ok('Mojolicious::Cafe::Controller');
	use_ok('Mojolicious::Cafe::List::View');
	use_ok('Mojolicious::Cafe::List');
	use_ok('Mojolicious::Cafe::Plugin::Locale::Messages');
	use_ok('Mojolicious::Cafe::Plugin::DateTime');
	use_ok('Mojolicious::Cafe::Plugin::CAuth');
	use_ok('Mojolicious::Cafe::SQL::Query');

}

diag("Testing Mojolicious::Cafe, Perl $], $^X");
