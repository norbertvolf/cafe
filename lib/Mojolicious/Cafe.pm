package Mojolicious::Cafe;
use utf8;

use Mojo::Base 'Mojolicious';
use Digest::SHA qw(sha1_base64);
use File::Basename;

#Definie configuraion files paths TODO (use dynamic way)
use constant CONFIG_FILE => "/etc/caramel.conf";
use constant CONFIG_DIR => "/etc/caramel.d";

#Property to keep config hash
has('vconfig');

#{{{ startup
sub startup {
	my $self = shift;

	#Setup configuration
	$self->setup_config;
	$self->secret($self->config->{secret});

	#Setup plugins
	#I add condition for routing (see over in routes)
	$self->plugin('Mojolicious::Cafe::Plugin::Locale::Messages');
	#We are using DateTime class to work with times instead of Time::Piece
	#See helpers provided in plugin in in POD and source code
	$self->plugin('Mojolicious::Cafe::Plugin::DateTime');
	#SMS is send via drivers defined as caramel plugins
	#Caramel sms driver plugin must define sendsms helper
	$self->plugin($self->config->{sms_driver} // 'Mojolicious::Cafe::Plugin::SMS::Test');

	#Use static root on www instead of public
	$self->app->static->paths([join "/", $self->app->home->to_string, "www"]);

	#Make sessions valid to end of user session
	$self->sessions->default_expiration(0);

	$self->hook(before_dispatch => sub {
		my $c = shift;
		#Check database connection
		$c->dbh(check => 1);
		#Fetch session hash from Memcache
		if ( defined($c->session->{_sessionid}) ) {
			$c->tmp($c->memd->get(join("|", "sessionid", $c->session->{_sessionid})) // {});
		} else {
			$c->session->{_sessionid} = sha1_base64(join("",  rand(), $c->config->{secret}));
		}
	});
	$self->hook(after_dispatch => sub {
		my $c = shift;
		#Check database connection
		$c->dbh(check => 1);
		#Workaround about forgot transactions. Fire query to force transaction
		$c->dbh->do("SELECT 'Keep alive connection'");
		#Save tmp hash to memcache
		$c->memd->set(join("|", "sessionid", $c->session->{_sessionid}), $c->tmp);
	});

}
#}}}
#{{{ setup_config
#TODO: Cele prepsat, tak aby nacetl hash sam a pak ho pastnul
#napral do Mojoicious::Plugin::Configu
sub setup_config {
	my $self = shift;

	my $inc = sub {
		my $test = shift;
		$test +- 1;
	};


	if ( -e CONFIG_FILE ) {
		#Read default config file and set configuration to config property
		my %config;
		my $config = $self->plugin('Config', { file => CONFIG_FILE });
		#TODO Create config test 

		#Set default parameters for configuration
		$config->{url_backend} = $config->{url_backend} // '/backend';
		$config->{user_pwgen_length} = $config->{user_pwgen_length} // 12;

		#Read vhost config files
		opendir(my $dh, CONFIG_DIR) || Mojo::Exception->throw("Can not open config directory " . CONFIG_DIR . ": $!");
		foreach my $config_file ( grep { /\.conf$/ && -f CONFIG_DIR . "/$_" } readdir($dh) ) {
			my $vhost_config = $self->plugin('Config', { file => CONFIG_DIR . "/$config_file"  });
			#Join vhost configuration to global configuration hash
			if ( exists($vhost_config->{server_name}) ) {
				$config{$vhost_config->{server_name}} = {(%{$vhost_config}, %{$config})};
			} else {
				$self->log->wanr("There is no parameter server_name in configuration file $config_file");
			}
		}
		closedir $dh;

		#Set global configuration hash to config plugin and to config property
		$self->vconfig(\%config);
	} else {
		Mojo::Exception->throw("Configuration file ". CONFIG_FILE . " not found");
	}
}
#}}}
#{{{ validator
#Return set/get validators by class name
sub validator {
	my $self = shift;
	my $class = shift;

	#class parameter is required
	Mojo::Exception->throw("\$class parameter missing") if ( ! $class ); 

	#Create validator hash
	$self->{_validators} = {} if ( ! ref($self->{_validators}) eq 'HASH' );

	#Initialize validator
	$self->{_validators}->{$class} = undef if ( ! exists($self->{_validators}->{$class}) );

	#Set validator
	$self->{_validators}->{$class} = shift if ( ! defined($self->{_validators}->{$class}) && scalar(@_));

	return($self->{_validators}->{$class});
}
#}}}

1;

__END__
#{{{ pod
=head1 NAME

Cafe - Duct tape for Cafe Applications

=head1 DESCRIPTION

Caramel provides a runtime environment for Caramel application
framework. It provides all the basic tools and helpers needed to write
Caramel web applications. Caramel is based on Mojolicious.

=head1 ATTRIBUTES

L<Caramel> implements the following attributes.

=head2 C<config>

  my $secret = $app->config->{secret};

The configuration parameters  of Caramel,

=head1 METHODS

L<Caramel> inherits all methods from L<Mojolicious> and implements the following
new ones.

=head2 C<startup>

Is automatically fireed when application is started. Prepare all Caramel
needs (as a database connectivity, secret key ...).

=head2 C<setup_config>

Read configuration of Caramel application from /etc/caramel.conf (default
configuration ) and from /etc/caramel.d/* per instance configuration.

  $app->setup_config;

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>. L<https://caramel.bata.eu/foswiki/bin/view/>.

=cut
#}}}
