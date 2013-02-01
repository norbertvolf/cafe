package Mojolicious::Cafe::Plugin::Locale;

use Mojo::Base 'Mojolicious::Plugin';

sub register {
	my ( $self, $app, $args ) = @_;

    #Default session key is auth_data
    my $default_locale = $args->{default_locale} || $ENV{LANG};

	$app->helper(
		locale => sub {
            my $c = shift;
            if ( $c->req->headers->accept_language ) {
                my %lang = ( $c->req->headers->accept_language =~ /([a-z]{1,8}(?:-[a-z]{1,8})?)\s*(?:;\s*q\s*=\s*(1|0\.[0-9]+))?/ig );
                my @lang = sort { ( $a // 1 ) cmp $b } keys %lang;
                return($lang[0]) if ( scalar(@lang) );
            }
            return($default_locale);
        }
	);


}

1;
