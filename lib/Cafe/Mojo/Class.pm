package Cafe::Mojo::Class;

use Mojo::Base 'Cafe::Mojo::Object';

has loaded => 0;
has exists => 0;
has okay => 0;
has message => 0;
has 'definition';

use Cafe::Class;
use Time::Piece;
use Data::Dumper;

#{{{ new
=head3 new

Create new instance of Cafe::Mojo::Class

=cut 
sub new {
	my $class = shift;
	my $root = shift;
	my $definition = shift;

	my $self = $class->SUPER::new($root); 
	$self->definition($self->check($definition));	
	return($self);
}
#}}}
#{{{now
=head3 now

Return Time::Piece actual time

=cut 
sub now {
	my ($self) = @_;
	my $now = localtime();
	return($now);
}
#}}}
#{{{check
=head3 C<check>

Check definiton, passed as paramatere

=cut 
sub check {
	my $self = shift;
	my $def = shift;
	#Is $definition present
	$self->die("Definition is not pass as parameter.", __LINE__) if ( ! defined($def) ); 
	#Exists primary key 
	$self->die("Not defined primary key.", __LINE__) if ( ! scalar(grep { defined($_->{primary_key}) && $_->{primary_key} == 1 } $self->columns($def)) );
	#Exists entity key
	$self->die("Not defined entity.", __LINE__) if ( ! exists($def->{entity}) || ! defined($def->{entity}) ) ;
	#Add dbh from root if not exists
	$def->{dbh} = $self->root->dbh if ( ! exists($def->{dbh}) );
	return($def);
}
#}}}
#{{{ load
=head3 C<load>

Load class data from database or from memcached server 
if memcached_servers is defined in apache configuration.

You can pass parameters thru HASH passed as parameter 
array. 


Load data directly from database 

$obj->load(force => 1);


=cut
sub load {
	my $self = shift;
	my %params = @_;

	if ( ! $self->loaded || $params{force} ) {
		#Find primary key columns
		my @pkc =  grep { defined($_->{primary_key}) && $_->{primary_key} == 1 } $self->columns;

		#Primary key exists do download from database
		if ( scalar( @pkc ) ) {
			#Prepare parameters for query
			my @pkv =  map { my $col = $_->{key};eval{$self->$col}; } @pkc;
			#Prepare query to fetch data from pgsql database
			my $query = "SELECT * FROM " . $self->entity . " WHERE " . join(" AND ",  map { "$_->{key} = ?" } @pkc );
			$self->debug("$query (". join (',', @pkv) . ")") if ( $self->root->mode('development') );
			#Execute query
			my $sth = $self->dbh->prepare($query);
			$sth->execute(@pkv);
			$self->loaded(1);
			if ( my $row = $sth->fetchrow_hashref() ) {
				#Fill instance from model
				map { eval { $self->$_($row->{$_}) } } map { $_->{key} } $self->columns;
				#Set record as exists
				$self->exists(1);
			}
		}
	}
	return($self);
}
#}}}
#{{{ hash
=head3 gethash

Returns formated values by hash based on definition of columns

=cut
sub hash {
	my ($self, $unlocalized) = @_;
	my $data = {};

	foreach my $key (sort(keys(%{$self->definition->{columns}}))) {
		if ( $self->{$key} && $self->definition->{columns}->{$key}->{type} == Cafe::Class::DB_DATE ) {
			#Format datetime attributes
			$self->{root}->set_local_locale() if ( ! $unlocalized);
			$data->{$key} = defined($data->{$key}) ? $self->{$key}->strftime("%x") : undef;
			$self->{root}->restore_local_locale() if (! $unlocalized);
		} elsif ( $self->{$key} && $self->definition->{columns}->{$key}->{type} == Cafe::Class::DB_NUMERIC ) {
			#Format numeric attributes
			$self->{root}->set_local_locale() if ( ! $unlocalized);
			if ( exists($self->definition->{columns}->{$key}->{format}) ) {
				$data->{$key} = sprintf("$self->definition->{columns}->{$key}->{format}", $self->{$key});
			} else {
				$data->{$key} = sprintf("%.2f", $self->{$key});
			}
			$self->{root}->restore_local_locale() if (! $unlocalized);
		} elsif ( defined($self->{$key}) )  {
			$data->{$key} = "$self->{$key}";
		} else {
			$data->{$key} = undef;
		}
	}

	foreach my $key (sort(keys(%{$self->definition->{autoloaders}}))) {
		if ( exists( $self->definition->{autoloaders}->{$key}->{show} ) ) {
			eval(qq(\$data->{$key} = \$self->$key()->$self->definition->{autoloaders}->{$key}->{show}));
		}
	}

	$data->{message} = $self->message;
	$data->{okay} = $self->okay;
	$data->{global} = {}; 
	$data->{global}->{message} = $self->root->message; 
	return($data);
}
#}}}
#{{{columns
=head3 C<columns>

Return sorted (by pos) columns as array

=cut 
sub columns {
	my $self = shift;
	my $def = scalar(@_) ? shift : $self->definition;
	return(sort { ( defined($a->{position}) ? $a->{position} : 0 )  <=> ( defined($b->{position}) ? $b->{position} : 0 ) } map { $def->{columns}->{$_}->{key} = $_;$def->{columns}->{$_} } keys(%{$def->{columns}}));
}
#}}}
#{{{eniity
=head3 C<eniity>

Return entity name from definition

=cut 
sub entity {
	return(shift->definition->{entity});
}
#}}}
#{{{dbh
=head3 C<dbh>

Return dbh from definition

=cut 
sub dbh {
	return(shift->definition->{dbh});
}
#}}}
#{{{ search
=head3 C<search>

Try search record from database based on parameters
passed as hash

	$obj->search(route => '/information/transport');

=cut
sub search {
	my $self = shift;
	my %params = @_;

	#Prepare query to fetch data from pgsql database
	my @params = map { $params{$_} } keys(%params);
	my $query = "SELECT * FROM " . $self->entity . " WHERE " . join(" AND ",  map { "$_ = ?" } keys(%params) );
	$self->debug("$query (". join (',', @params) . ")") if ( $self->root->mode('development') );
	#Execute query
	my $sth = $self->dbh->prepare($query);
	$sth->execute(@params);
	$self->loaded(1);
	if ( my $row = $sth->fetchrow_hashref() ) {
		#Fill instance from model
		map { eval { $self->$_($row->{$_}) } } map { $_->{key} } $self->columns;
		#Set record as exists
		$self->exists(1);
	}
	return($self);
}
#}}}
#{{{AUTOLOAD
=head3 AUTOLOAD

Autoloader to handle columns and autoloaders from 
definition

=cut 
sub AUTOLOAD {
	my $self = shift;

	#Dig number or parameters
	my $numofprm = scalar(@_);
	my $param = shift;
	my $method = our $AUTOLOAD;

	$self->die("Cafe::Class::AUTLOADER", " $self is not object.", __LINE__) if ( ! ref( $self ) );
	
	#If not defined DESTROY method and this method is invocated finish method
	return if ( $method =~ /::DESTROY$/ );

	#Check and run method
	if ( $method =~ /::([^:]+)$/ ) {
		my $method = $1;
		if ( exists($self->definition->{columns}->{$method}) ) {
			#Set property if param is defined
			$self->{"_$method"} = $param if ( $numofprm );
			#If is invocated method with name defined as column return value of this column
			return($self->{"_$method"});
		} else {
			$self->die("Method $method is not defined", __LINE__);
		}
	}
}
#}}}

1;
