package Mojolicious::Cafe::Plugin::Auth;

use Mojo::Base 'Mojolicious::Plugin';

#Napsat testy
# * Co kdyz jdu z app a neni spusteny web server
# * Ruzne kombinace vstupnich parametru.

sub register {
	my ( $self, $app, $args ) = @_;

	$args ||= {};

	die __PACKAGE__, ": missing 'load_user' subroutine ref in parameters\n"
	  unless $args->{load_user} && ref( $args->{load_user} ) eq 'CODE';
	die __PACKAGE__, ": missing 'validate_user' subroutine ref in parameters\n"
	  unless $args->{validate_user} && ref( $args->{validate_user} ) eq 'CODE';

    #Default session key is auth_data
    my $session_key = $args->{session_key} || 'auth_data';
	my $load_user_cb     = $args->{load_user};
	my $validate_user_cb = $args->{validate_user};
	my $our_stash_key    = $args->{session_key} || 'auth_data';
	my $login_redirect   = $args->{login_redirect} || '/login';

    if ( ! $args->{login_redirect} ) {
        die __PACKAGE__, ": missing 'login_redirect' array ref or string in parameters\n"
    } elsif ( ref($args->{login_redirect}) eq 'ARRAY' ) {
        $login_redirect   = $args->{login_redirect};
    } elsif ( ! ref($args->{login_redirect}) ) {
        $login_redirect   = [ $args->{login_redirect} ];
    } else {
        die __PACKAGE__, ": bad type of parameter 'login_redirect' it must by array ref for 'redirect_to' or name of route string\n"
    }

	my $load_user_priv    = sub {
        my $c = shift;
        my $user;
        if ( $user = $c->stash($our_stash_key) ) {
            return ($user);
        } elsif ( my $uid = $c->session($session_key) ) {
            $user->{user} = $load_user_cb->( $c, $uid );
            $user->{authenticated} = 1;
            $c->stash( $our_stash_key => $user );
            return ($user);
        } else {
            $user = $load_user_cb->($c);
            $user->{authenticated} = 0;
            $c->stash( $our_stash_key => $user );
            return ($user);
        }
    };

	$app->helper(
		user => sub { return (&$load_user_priv(shift)->{user}); }
	);

	$app->helper(
		is_user_authenticated => sub {&$load_user_priv(shift)->{authenticated}}
	);

	$app->routes->add_condition(
		auth => sub {
            my $r = shift;
            my $c = shift;
            my $captures = shift;
            my $required = 1;
            $required = shift if ( scalar(@_) );

            if ( $required && ! &$load_user_priv($c)->{authenticated} ) {
                $c->redirect_to($login_redirect);
                return(0);
            } else {
                return(1);
            }
		}
	);

	$app->helper(
		authenticate => sub {
			my ( $c, $user, $pass, $extradata ) = @_;
			if ( my $uid = $validate_user_cb->( $c, $user, $pass, $extradata ) ) {
				$c->session( $session_key => $uid );

				# Clear stash to force reload of any already loaded user object
				delete $c->stash->{$our_stash_key};
				return &$load_user_priv(shift)->{authenticated};
			}
		}
	);

	$app->helper(
		deauthenticate => sub {
			my $c = shift;
			delete $c->stash->{$our_stash_key};
			delete $c->session->{$session_key};
		}
	);
}

1;
