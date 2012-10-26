package Mojolicious::Cafe;
use utf8;

use Mojolicious::Cafe::Controller;
use Mojo::Base 'Mojolicious';
use Digest::SHA qw(sha1_base64);

#{{{ startup
sub startup {
	my $self = shift;

	#Setup plugins
	$self->plugin('Mojolicious::Cafe::Plugin::Locale::Messages');
	$self->plugin('Mojolicious::Cafe::Plugin::DateTime');
	#$self->plugin('Mojolicious::Cafe::Plugin::CAuth');
	

	#Make sessions valid to end of user session
	$self->sessions->default_expiration(0);

	#Controller class is our own controller
	$self->controller_class('Mojolicious::Cafe::Controller');

	$self->hook(before_dispatch => sub {
		my $c = shift;
		#Check database connection
		$c->dbh(check => 1);
		#Fetch session hash from Memcache
		if ( defined($c->session->{_sessionid}) ) {
			$c->tmp($c->memd->get(join("|", "sessionid", $c->session->{_sessionid})) // {});
		} else {
			$c->session->{_sessionid} = sha1_base64(join("",  rand(), $c->config->{secret} // ''));
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
#{{{ dbh
sub dbh {
	my $self = shift;
	
	my %params = @_ if ( scalar(@_) && ( scalar(@_) % 2 ) == 0 );

	 my $config = $self->plugin('Config');
	 $self->log->debug($self->dumper($config));

	if ( !exists( $self->{_dbh} ) ) {
		$self->log->warn("Connecting to database...");
		$self->{_dbh} =
		  DBI->connect( $self->config->{dbi_dsn}, $self->config->{dbi_user}, $self->config->{dbi_pass}, $self->config->{dbi_attr} );
	}
	else {
		my $ping = $self->{_dbh}->ping;
		if ( !$ping ) {
			$self->log->warn("Database connection has disconnected. Trying to reconnect...");
			$self->{_dbh}->disconnect;
			$self->{_dbh} =
			  DBI->connect( $self->config->{dbi_dsn}, $self->config->{dbi_user}, $self->config->{dbi_pass}, $self->config->{dbi_attr} );
		}
		elsif ( $params{check} && $ping > 1 ) {
			$self->log->warn('Database connection is dirty. Cleanup..');
			$self->{_dbh}->disconnect;
			$self->{_dbh} =
			  DBI->connect( $self->config->{dbi_dsn}, $self->config->{dbi_user}, $self->config->{dbi_pass}, $self->config->{dbi_attr} );
		}
	}
	return ( $self->app->{_dbh} );
}
#}}}

1;

__END__
