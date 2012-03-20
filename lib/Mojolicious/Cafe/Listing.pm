package Mojolicious::Cafe::Listing;

use Mojo::Base 'Mojolicious::Cafe::Base';
use DBD::Pg qw(:pg_types);
use Scalar::Util qw(looks_like_number);


has 'limit';
has 'offset';

#{{{ new
=head3 new

Create new instance of Mojolicious::Cafe::Listing

=cut 
sub new {
	my $class = shift;
	my $c = shift;
	my $definition = shift;
	my $self = $class->SUPER::new($c, $definition);

	#Initialize list as empty refarray
	$self->list([]);

	return($self);
}
#}}}
#{{{check
=head3 C<check>

Check definiton, passed as paramaters

=cut 
sub check {
	my $self = shift;
	my $def = shift;
	#Check tests from base
	$self->SUPER::check($def);
	#Exists primary key 
	Mojo::Exception->throw("Not defined query.") if ( ! defined($def->{query}) );
	return($def);
}
#}}}
#{{{ load
=head3 C<load>

Load persistent data from databases by query defined
in class.

B<parameters>

=over 

=item $force - if $force = 1 ignore data loaded by instance, if $force
               = 2 delete memcached and load data from database

=back 

=cut
sub load {
	my ($self, $force) = @_;
	if ( ! $self->loaded || $force ) {
		#TODO:Implementovat test jestli jsou data v Cache
		$self->c->app->log->debug("Query:\n" . $self->query_compiled) if ( $self->root->app->mode('development') );
		my $sth = $self->dbh->prepare($self->query_compiled);
		$sth->execute($self->query_params());
		$self->list($sth->fetchall_arrayref({}));
		#TODO:Implementovat ulozeni do memcache

		#Convert DB_DATE columns to DateTime instances
		$self->convert_timestamps;
	}
	return($self->list);
}
#}}}
#{{{ list
=head3 C<list>

Getter/setter for list of records

=cut
sub list {
	my $self = shift;
	if ( scalar(@_) ) {
		$self->{_list} = shift;
		Mojo::Exception->throw("List is not array reference.") if ( ! ref($self->{_list}) eq 'ARRAY' ); 
	}
	return(wantarray ? @{$self->{_list}} : $self->{_list});
}
#}}}
#{{{ private convert_timestamps
=head3 C<convert_timestamps>

Convert timestamp/date postgresql columns in list to Datetime class.

=cut
sub convert_timestamps {
	my $self = shift;

	my @cdt = map { $_->{key} } grep { $_->{type} == $self->c->DB_DATE } $self->columns;

	foreach my $r ( $self->list ) {
		map {
			if ( defined($r->{$_}) ) {
				if ( $r->{$_} =~ /(\d{4})-(\d{2})-(\d{2})[ T](\d{2}):(\d{2}):(\d{2})([+-]\d{2})/ ) {
					$r->{$_} = DateTime->new( 
						year   => $1,
						month  => $2,
						day    => $3,
						hour   => $4,
						minute => $5,
						second => $6,
						locale => $self->c->user->locale,
					);
				} elsif ( $r->{$_} =~ /(\d{4})-(\d{2})-(\d{2})/ ) {
					$r->{$_} = DateTime->new( 
						year   => $1,
						month  => $2,
						day    => $3,
						locale => $self->c->user->locale,
					);
				}
			}
		} @cdt;
	}
}
#}}}
#{{{ private query_compiled
=head3 C<query_compiled>

Remove parameters and dynamically used SQL keywords
from query

=cut
sub query_compiled {
	my $self = shift;

	#Convert to anonymous placeholders
	my $query = $self->definition->{query};	
	$query =~ s/@\w+/?/g;

	#Add limit and offset
	if ( defined($self->limit) && looks_like_number($self->limit) ) {
		$query =~ s/LIMIT\s+\d+//i;
		$query =~ s/OFFSET\s+\d+//i;
		$query = join(' ', $query, "LIMIT", $self->limit);
		$query = join(' ', $query, "OFFSET", $self->offset) if ( defined($self->offset) && looks_like_number($self->offset) );

	}
	return($query);
}
#}}}
#{{{ private query_params
=head3 C<query_params

Prepare params for compiled query 

=cut
sub query_params {
	my $self = shift;

	my @params;
	my $query = $self->definition->{query};	
	while ( $query =~ s/@(\w+)/?/ ) {
		my $param;
		eval("\$param = \$self->$1;");
		push(@params, $param);
	}
	$self->c->app->log->debug("Query parameters:\n" . $self->c->app->dumper(\@params)) if ( $self->root->app->mode('development') );
	return(@params);
}
#}}}
#{{{ dump
=head3 dump

Return string with dumped data

=cut
sub dump {
	my $self = shift;
	my $dump = "\n" . $self->SUPER::dump . "\n\nlist = [\n";
	foreach my $r (  $self->list ) { 
		my $part = '';
		if ( ref($r) && ( ref($r) eq 'HASH' || ref($r) eq 'ARRAY' || ref($r) eq 'SCALAR') ) {
			$part = $self->c->app->dumper($r) . "\n";
		} elsif( ref($r) ) {
			$part = $r->dump . "\n";
		}
		$part =~ s/^/  /mg;
		$dump .= $part;
	}
	$dump .= "]\n\n";
	return($dump);
}
#}}}

1;

__END__
