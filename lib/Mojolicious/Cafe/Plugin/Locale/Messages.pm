package Mojolicious::Cafe::Plugin::Locale::Messages;

use utf8;
use Mojo::Base 'Mojolicious::Plugin';
use Locale::Messages qw (:locale_h :libintl_h);
use Encode;

sub register {
	my ($self, $app) = @_;

	$app->helper(
		__ => sub {
			my $c = shift; 
			my $msgid = shift;
			my $retval = decode('utf-8', gettext($msgid));
			return($retval);
		}
	);
}

1;
