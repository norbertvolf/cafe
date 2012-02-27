package Mojolicious::Cafe::Plugin::DateTime;

use Mojo::Base 'Mojolicious::Plugin';
use DateTime;

sub register {
	my ($self, $app) = @_;
	$app->helper( 
		cnow => sub {
			return(DateTime->now);
		}

	);
}

1;
