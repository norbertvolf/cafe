package Mojolicious::Cafe;
use utf8;

use Mojo::Base 'Mojolicious';

use File::Basename;
use POSIX qw(strftime locale_h setlocale LC_ALL);

#Definie configuraion files paths TODO (use dynamic way)
use constant CONFIG_FILE => "/etc/caramel.conf";
use constant CONFIG_DIR => "/etc/caramel.d";

#Property to keep config hash
has('config');

#{{{ startup
sub startup {
	my $self = shift;

	#Setup configuration
	$self->setup_config;
	$self->secret($self->config->{secret});

	#Setup plugins
	#I add condition for routing (see over in routes)
	$self->plugin('Mojolicious::Cafe::Plugin::Locale::Messages');
	#CAuth add condition for routing (see over in routes)
	$self->plugin('Mojolicious::Cafe::Plugin::CAuth');
	#We are using DateTime class to work with times instead of Time::Piece
	#See helpers provided in plugin in in POD and source code
	$self->plugin('Mojolicious::Cafe::Plugin::DateTime');
	#SMS is send via drivers defined as caramel plugins
	#Caramel sms driver plugin must define sendsms helper
	$self->plugin($self->config->{sms_driver} // 'Mojolicious::Cafe::Plugin::SMS::Test');

	#Use static root on www instead of public
	$self->app->static->paths([join "/", $self->app->home->to_string, "www"]);

	#Add hook before dispatch any request to check database handler
	$self->hook(before_dispatch => sub {
		my $c = shift;
		#Check dbh connection before first connect;
		$c->dbh(check => 1);
	});

	#Make sessions valid to end of user session
	$self->sessions->default_expiration(0);
}
#}}}
#{{{ restore_locale
=head3 restore_locale

Restore_locale locale from LIFO

$c->app->restore_locale;

=cut
sub restore_locale {
	my ( $self ) = shift;

	$self->{_local_locale} = [] if ( ! defined($self->{_local_locale}) );
	if ( scalar(@{$self->{_local_locale}}) ) {
		pop(@{$self->{_local_locale}});
		setlocale( LC_ALL, $self->{_local_locale}->[scalar(@{$self->{_local_locale}}) - 1]) if ( scalar(@{$self->{_local_locale}}) );
	} else {
		die "Locale array is empty, when I want restore locale.";
	}   
}
#}}}
#{{{ set_locale
=heade set_locale

Set locale and save original locale to LIFO. If $locale
is not defined use "C".

$c->app->set_locale('cs_CZ.UTF-8');

=cut
sub set_locale {
	my $self = shift;
	my $locale = shift;

	$locale = "C" unless ( $locale );
	$self->{_local_locale} = [] unless ( $self->{_local_locale} );
	$ENV{LANG}=$locale;
	#setlocale( POSIX::LC_ALL, $locale );
	push ( @{$self->{_local_locale}}, $locale );
}
#}}}
#{{{ setup_config
=head2 setup_config

TODO: Cele prepsat, tak aby nacetl hash sam a pak ho pastnul
napral do Mojoicious::Plugin::Configu

=cut
sub setup_config {
	my $self = shift;

	my $inc = sub {
		my $test = shift;
		$test +- 1;
	};


	if ( -e CONFIG_FILE ) {
		#Read default config file and set configuration to config property
		my %config;
		$self->log->debug(CONFIG_FILE);
		my $config = $self->plugin('Config', { file => CONFIG_FILE });
		#TODO Create config test 

		#Set default parameters for configuration
		$config->{url_backend} = $config->{url_backend} // '/backend';
		$config->{user_pwgen_length} = $config->{user_pwgen_length} // 12;

		#Read vhost config files
		opendir(my $dh, CONFIG_DIR) || die "Can not open config directory " . CONFIG_DIR . ": $!";
		foreach my $config_file ( grep { /\.conf$/ && -f CONFIG_DIR . "/$_" } readdir($dh) ) {
			my $vhost_config = $self->plugin('Config', { file => CONFIG_DIR . "/$config_file" , default => $config });
			#Join vhost configuration to global configuration hash
			if ( exists($vhost_config->{server_name}) ) {
				$config{$vhost_config->{server_name}} = $vhost_config;
			} else {
				$self->log->wanr("There is no parameter server_name in configuration file $config_file");
			}
		}
		closedir $dh;

		#Set global configuration hash to config plugin and to config property
		$self->config($self->plugin('Config', { file => CONFIG_FILE , default => \%config }));
	} else {
		die "Configuration file ". CONFIG_FILE . " not found";
	}
}
#}}}

1;

__END__
#{{{ pod
=head1 NAME

Caramel - Duct tape for Caramel Application

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

=head2 C<set_locale>

Set locale to use different than actual locale and save actual to FIFO queue. 

  $app->set_locale("cs_CZ");

=head2 C<restore_locale>

Restore original locale from FIFO queue replaced by function set_locale.

  $app->restore_locale;

=head2 C<setup_config>

Read configuration of Caramel application from /etc/caramel.conf (default
configuration ) and from /etc/caramel.d/* per instance configuration.

  $app->setup_config;

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>. L<https://caramel.bata.eu/foswiki/bin/view/>.

=cut
#}}}
