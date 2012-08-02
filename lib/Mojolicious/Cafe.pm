package Mojolicious::Cafe;
use utf8;

use Mojo::Base 'Mojolicious';
use Digest::SHA qw(sha1_base64);

#{{{ startup
sub startup {
	my $self = shift;

	#Setup plugins
	#I add condition for routing (see over in routes)
	$self->plugin('Mojolicious::Cafe::Plugin::Locale::Messages');
	#We are using DateTime class to work with times instead of Time::Piece
	#See helpers provided in plugin in in POD and source code
	$self->plugin('Mojolicious::Cafe::Plugin::DateTime');

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

1;

__END__
