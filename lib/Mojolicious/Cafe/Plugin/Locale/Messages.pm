package Mojolicious::Cafe::Plugin::Locale::Messages;

use utf8;
use Mojo::Base 'Mojolicious::Plugin';
use Locale::Messages qw (:locale_h :libintl_h);
use Encode;

sub register {
	my ($self, $app) = @_;

	textdomain("caramel");
	bindtextdomain(caramel => join("/", $app->home->to_string, "locale"));

	$app->helper(
		__ => sub {
			my $c = shift; 
			my $msgid = shift;
			return(decode('utf-8', gettext($msgid)));
		}
	);
}

1;
