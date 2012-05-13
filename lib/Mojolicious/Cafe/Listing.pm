package Mojolicious::Cafe::Listing;

use Mojo::Base 'Mojolicious::Cafe::Base';
use DBD::Pg qw(:pg_types);
use Scalar::Util qw(looks_like_number);
use Encode;


has 'limit';
has 'offset';

#{{{ new
#Create new instance of Mojolicious::Cafe::Listing
sub new {
	my $class = shift;
	my $c = shift;
	my $definition = shift;
	my $self = $class->SUPER::new($c, $definition);
	$self->default_from_session();

	#Initialize list as empty refarray
	$self->list([]);

	return($self);
}
#}}}
#{{{check
#Check definiton, passed as paramaters
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
#Load persistent data from databases by query defined
#in class.
sub load {
	my ($self, $force) = @_;
	if ( ! $self->loaded || $force ) {
		$self->c->app->log->debug("Query:\n" . $self->query_compiled);
		my $sth = $self->dbh->prepare($self->query_compiled);
		$sth->execute($self->query_params());
		$self->list($sth->fetchall_arrayref({}));

		#Normalize rows
		foreach my $r ( $self->list ) {
			#Convert timestamp from databaze to Datetime
			map { $r->{$_} = $self->func_parse_pg_date($r->{$_}); } map { $_->{key} } grep { $_->{type} == $self->c->DB_DATE } $self->columns;
			map { $r->{$_} = decode("utf-8", $r->{$_}); } map { $_->{key} } grep { $_->{type} == $self->c->DB_VARCHAR } $self->columns;
		}
	}
	return($self->list);
}
#}}}
#{{{ list
#Getter/setter for list of records
sub list {
	my $self = shift;
	if ( scalar(@_) ) {
		$self->{_list} = shift;
		Mojo::Exception->throw("List is not array reference.") if ( ! ref($self->{_list}) eq 'ARRAY' ); 
	}
	return(wantarray ? @{$self->{_list}} : $self->{_list});
}
#}}}
#{{{ push
#add new value to list 
sub push {
	my $self = shift;
	Mojo::Exception->throw("You must pass some value to push them to the list.") if ( ! scalar(@_) ); 
	push( @{$self->{_list}}, shift);
}
#}}}
#{{{ hash
#Returns formated values by hash based on definition of columns
sub hash {
	my ($self, $unlocalized) = @_;
	my $data = $self->SUPER::hash;
	my @list = map {
		my $val;
		if ( ref($_) eq "HASH") {
			$val = $_;
			#Use user defined formating function
			foreach my $key ( map { $_->{key} } grep { $_->{format} } $self->columns ) {
				$val->{$key} = &{$self->definition->{columns}->{$key}->{format}}($val->{$key});
			}
			#Convert timestamps to locale date format
			foreach my $key ( map { $_->{key} } grep { $_->{type} == $self->c->DB_DATE && ! exists($_->{format}) } $self->columns ) {
				$val->{$key} = defined($val->{$key}) ? $val->{$key}->strftime("%x") : undef ;
			}
		} elsif ( ref($_) eq "ARRAY") {
			$val = $_;
		} elsif ( ! ( ref($_) eq "" ) ) {
			$val = $_->hash;
		}
		$val;
	} $self->list;
	$data->{list} =  \@list;
	return($data);
}
#}}}
#{{{ dump
#Return string with dumped data
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
#{{{ search
#Return array with items corresponding, with parameters 
#passed as hash
#ex.: $self->search(articlenumber => '3334422')
sub search {
	my $self = shift;
	my %hash = @_;
	my $equals = 0;
	my @arr;

	foreach my $r (  $self->list ) {
		if ( ref($r) eq 'HASH' ) {
			$equals = grep { ( ( defined($r->{$_}) &&  defined($hash{$_}) && $r->{$_} eq $hash{$_} ) || ( ! defined($r->{$_}) &&  ! defined($hash{$_}) ) ) } keys(%hash);
		} else {
			$equals = grep { ( ( defined($r->$_) &&  defined($hash{$_}) && $r->$_ eq $hash{$_} ) || ( ! defined($r->$_) &&  ! defined($hash{$_}) ) ) } keys(%hash);
		}
		CORE::push(@arr, $r) if ( $equals == scalar(keys(%hash)) );
	}
	return(@arr);
}
#}}}
#{{{ tmp
#return
sub tmp {
	my $self = shift;

	$self->c->tmp->{ref($self)} = {} if ( ! $self->c->tmp->{ref($self)} );
	return($self->c->tmp->{ref($self)});
}
#}}}
#{{{ validate
#Overload Mojolicious::Cafe::Base::validate to keep session columns
sub validate {
	my $self = shift;
	my $params = shift;
	$self->debug($params);
	my $retval = $self->SUPER::validate($params);
	foreach my $key ( map { $_->{key} } grep { $_->{session}; } $self->columns ) {
		$self->tmp->{$key} = $self->$key;
	}
	return($retval);
}
#}}}

#{{{ private query_compiled
#Remove parameters and dynamically used SQL keywords
#from query
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
#Prepare params for compiled query 
sub query_params {
	my $self = shift;

	my @params;
	my $query = $self->definition->{query};	
	while ( $query =~ s/@(\w+)/?/ ) {
		my $param;
		eval("\$param = \$self->$1;");
		CORE::push(@params, $self->$1);
	}
	$self->c->app->log->debug("Query parameters:\n" . $self->c->app->dumper(\@params)) if ( scalar(@params) ); 
	return(@params);
}
#}}}
#{{{ private default_from_session
#Set default values from previous session
sub default_from_session {
	my $self = shift;
	foreach my $key ( map { $_->{key} } grep { $_->{session}; } $self->columns ) {
		if ( exists($self->tmp->{$key}) ) {
			$self->$key($self->tmp->{$key});	
		}
	}
}
#}}}

1;

__END__

=head1 NAME

Mojolicious::Cafe::Base - base class to build Postgresql Web applications


=head1 DIRECTIVES

Mojolicious::Cafe::Listing inherites all directivs from Mojolicious::Cafe::Base and implements the following new ones.

=head2 session

If B<session> is true keep column value in session for filter usage. 

C<session =E<gt> 1>

=head2 format

B<format> is anonymous function to re

C<format =E<gt> sub { my $value = shift; return( sprintf('%03d', $value) ) }>

=head1 METHODS

Mojolicious::Cafe::Listing inherites all methods from Mojolicious::Cafe::Base and implements the following new ones.

=head2 tmp

B<tmp> return temporary hash to keep values in session structure. The tmp hash is uniques per class (not per instance).
Internally is set default values from session for filters.

C<$self->tmp->{key} = 100;>
C<my $value = $self->tmp->{key};>
