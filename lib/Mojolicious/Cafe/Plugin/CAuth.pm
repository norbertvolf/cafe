package Mojolicious::Cafe::Plugin::CAuth;

use Mojo::Base 'Mojolicious::Plugin';
use Digest::SHA qw(sha512_base64);
use Apache::Htpasswd;

sub register {
	my ($self, $app) = @_;
	$app->helper( 
		auth => sub {
			my $c = shift; 
			my $username = shift;
			my $password = shift;
			my $rid = shift;
			return(validate_userpass($c, $username, $password));
		}

	);
	$app->helper(
		user => sub {
			my $c = shift; 
			if ( ! $c->{_user} ) {
				my $username = $c->memd->get(join("|", "user_digest", $c->session->{digest}));
				my $class =  $c->config->{user_class};
				eval "require $class;\$c->{_user} = new $class(\$c, \$username)";
				Mojo::Exception->throw($@) if $@;
			}
			return($c->{_user});
		}
	);

	$app->routes->add_condition (
		auth => sub {
			my ($r, $c, $captures, $rid) = @_;

			#Initialize stash values
			$c->stash('wrong', 0);
			$c->stash('username', '');

			#Check credentials
			if ( defined($c->session->{digest}) && $self->validate_digest($c) ) {
				#Digest is valid. User is authenticated via session
				return 1;
	 		} elsif (  defined($c->req->param('username')) && defined($c->req->param('password')) && $self->validate_userpass($c->req->param('username'), $c->req->param('password')) ) {
				#Username/password is valid. User is authenticated via username/password pair
				return 1;
			} else {
				#User is not authenticated render login page
				my $username = $c->req->param('username');
				if ( defined($username) ) {
					#Return username and show bad pass message in login page
					$c->stash('wrong', 1);
					$c->stash('username', $username);
				}
				$c->render(template => 'pages/login'); 
				return undef;
			}
		}
	);
}


#Validate username & password against htpasswd file
#htpasswd file
sub validate_userpass {
	my ($c, $username, $password) = @_;
	my $htpass = new Apache::Htpasswd({passwdFile => $c->config->{htpasswd}, ReadOnly   => 1});
	if ( $htpass->htCheckPassword($username, $password) ) {
		#Set digest to session
		$c->session->{digest} = sha512_base64(join("", $username , $password , $c->config->{secret}));
		#Save user digest to memcache for 7 days
		$c->memd->set(join("|", "user_digest", $c->session->{digest}), $username, 7 * 86400);
		return(1) 
	}
	return;
}

#Validate digest against digest saved in 
#memcached
sub validate_digest {
	my ($self, $c) = @_;
	#Try to found digest in memcached
	my $username = $c->memd->get(join("|", "user_digest", $c->session->{digest}));
	return(1) if ( defined($username) );
	return;
}

1;
