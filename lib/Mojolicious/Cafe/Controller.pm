package Mojolicious::Cafe::Controller;

use utf8;

use Mojo::Base 'Mojolicious::Controller';

use Mojo::Exception;
use DBI;
use Cache::Memcached;
use Schema::User;

#{{{ vhost
#Return actual served host
sub vhost {
	my $self = shift;
	#TODO implementuj vhost aliases
	return($self->req->url->base->host);
}
#}}}
#{{{ config
#Return hash with configurationi parameter
#for actual vhost
sub config {
	my $self = shift;
	die "There is no configuration for " . $self->vhost if ( ! exists( $self->app->config->{$self->vhost} ) );
	return($self->app->config->{$self->vhost});
}
#}}}
#{{{ dbh
#Return instance of DBI class. The class
#is used as interface between database
#and Caramel application. The instance 
#is created per vhost.
sub dbh {
	my $self = shift;
	my %params = @_ if ( scalar(@_ ) && ( scalar(@_ ) % 2 ) == 0 );

	if ( ! exists( $self->config->{_dbh} ) ) {
		$self->app->log->warn("Connecting to database...");
		$self->config->{_dbh} = DBI->connect($self->config->{dbi_dsn}, $self->config->{dbi_user}, $self->config->{dbi_pass}, $self->config->{dbi_attr}) 
	} elsif ( ! $self->config->{_dbh}->ping ) {
		$self->app->log->warn("Database connection has disconnected. Trying to reconnect...");
		$self->config->{_dbh}->disconnect;
		$self->config->{_dbh} = DBI->connect($self->config->{dbi_dsn}, $self->config->{dbi_user}, $self->config->{dbi_pass}, $self->config->{dbi_attr}) 
	} elsif ( $params{check} && $self->config->{_dbh}->ping > 1 ) {
		$self->app->log->warn('Database connection is dirty. Cleanup..');
		$self->config->{_dbh}->disconnect ;
		$self->config->{_dbh} = DBI->connect($self->config->{dbi_dsn}, $self->config->{dbi_user}, $self->config->{dbi_pass}, $self->config->{dbi_attr}) 
	}
	return($self->config->{_dbh});
}
#}}}
#{{{  memd
#Return instance of Cache::Memcached class
#The class encapsulates client API  for 
#memcached. The instance created is per 
#vhost.
sub memd {
	my $self = shift;
	if ( ! $self->config->{_memd} ) {
		$self->config->{_memd}->{namespace} = $self->vhost if ( ! $self->config->{memcached}->{namespace} );
		$self->config->{_memd} = new Cache::Memcached (
			$self->config->{memcached}
		);
	}
	return($self->config->{_memd});
}
#}}}
#{{{ constants
#Redefine Cafe::Class constants as methods
sub DB_VARCHAR { return( 0 ); }
sub DB_INT { return( 1 ); }
sub DB_DATE { return( 2 ); }
sub DB_NUMERIC { return( 3 ); }
sub DB_FMTCHAR { return( 4 ); }
sub DB_INT8 { return( 6 ); }
sub DB_NULL { return( 7 ); }
sub DB_NOTNULL { return( 8 ); }
sub DB_DATETIMETZ { return( 9 ); }
sub CAFE_TTL { return( 3 ); }
sub OK { return( 1 ); }
sub NOK { return( 0 ); }
#}}}

1;

__END__
#{{{ pod
=head1 NAME

Mojolicious::Cafe::Controller - controller

=head1 DESCRIPTION

Caramel provides a runtime environment for Caramel application
framework. It provides all the basic tools and helpers needed to write
Caramel web applications. Caramel is based on Mojolicious.

=head1 METHODS

L<Caramel> inherits all methods from L<Mojolicious::Controllers> and 
implements the following new ones.


=head2 C<config>

  my $secret = $app->config->{secret};

The configuration parameters  of Caramel, The configuration is depends
on actual virtual hosts.


=head2 C<dbh>

  my $sth = $app->dbh->prepare(q(SELECT * FROM table));

Return DBI object for communicat with database. Database handlers
is depend on virtual host.

=head2 C<memd>

Return instance of Cache::Memcached. The instance handlers
is depend on virtual host.

  my $cached_value = $app->memd->get("my_key");

=head2 C<vhost>

Return actual vhost as string.


=head2 C<user>

Return actual logged user

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>. L<https://caramel.bata.eu/foswiki/bin/view/>.

=cut
#}}}
