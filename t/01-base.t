#/usr/bin/perl -T

use Test::More tests => 1;

BEGIN {
	use_ok('Mojolicious::Cafe::Base');
}

diag("Testing Mojolicious::Cafe, Perl $], $^X");
