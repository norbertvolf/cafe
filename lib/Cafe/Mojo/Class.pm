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
	$def->{dbh} = $self->root->app->dbh if ( ! exists($def->{dbh}) );
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
		#Primary key exists do download from database
		if ( scalar( $self->pkc ) ) {
			#Prepare query to fetch data from pgsql database
			my $query = "SELECT * FROM " . $self->entity . " WHERE " . join(" AND ",  map { "$_->{key} = ?" } $self->pkc );
			$self->debug("$query (". join (',', $self->pkv) . ")") if ( $self->root->app->mode('development') );
			#Execute query
			my $sth = $self->dbh->prepare($query);
			$sth->execute($self->pkv);
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
			#$self->{root}->set_local_locale() if ( ! $unlocalized);
			$data->{$key} = defined($data->{$key}) ? $self->{$key}->strftime("%x") : undef;
			#$self->{root}->restore_local_locale() if (! $unlocalized);
		} elsif ( $self->{$key} && $self->definition->{columns}->{$key}->{type} == Cafe::Class::DB_NUMERIC ) {
			#Format numeric attributes
			#$self->{root}->set_local_locale() if ( ! $unlocalized);
			if ( exists($self->definition->{columns}->{$key}->{format}) ) {
				$data->{$key} = sprintf("$self->definition->{columns}->{$key}->{format}", $self->{$key});
			} else {
				$data->{$key} = sprintf("%.2f", $self->{$key});
			}
			#$self->{root}->restore_local_locale() if (! $unlocalized);
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
	$data->{global}->{message} = $self->root->app->message; 
	return($data);
}
#}}}
#{{{columns
=head3 columns

Return sorted (by pos) columns as array

=cut 
sub columns {
	my $self = shift;
	my $def = scalar(@_) ? shift : $self->definition;
	return(sort { ( defined($a->{position}) ? $a->{position} : 0 )  <=> ( defined($b->{position}) ? $b->{position} : 0 ) } map { $def->{columns}->{$_}->{key} = $_;$def->{columns}->{$_} } keys(%{$def->{columns}}));
}
#}}}
#{{{entity
=head3 C<entity>

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
	$self->debug("$query (". join (',', @params) . ")") if ( $self->root->app->mode('development') );
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
#{{{ save
=head3 save

Save to database instance of Cafe::Mojo::Class. Class must 
contain $self->{_definition}->{entity}. For new identifier 
you must define   $self->{_definition}->{sequence}.
You must also define columns see SYNOPSIS.

If memcached_servers option is defined in apache configuration
save method also save data to memcached server

=cut 
sub save {
	my $self = shift;
	if ( exists($self->definition->{columns}->{stateuser}) && $self->root->user) {
		$self->stateuser(defined($self->root->user->iduser) ? $self->root->user->iduser : 0);
	}

	#Set last modified time
	if ( exists($self->definition->{columns}->{statestamp}) ) {
		$self->{statestamp} = localtime();
	}

	#Set state bits 
	if ( $self->definition->{columns}->{state} ) {
		$self->state(0) unless ( defined($self->state) );
		if ( ($self->state & 1) == 0 ) {
			$self->state($self->state | 1);
		} elsif( ($self->state & 1) == 1 && ($self->state & 2) == 0 ) {
			$self->state($self->state | 2);
		}
	}

	#Check save needs 
	if ( $self->definition && $self->entity && scalar($self->columns) && scalar($self->pk()) ) {
		if ( scalar($self->pkc) ==  1 && scalar( grep { defined } $self->pkv ) == 0 && $self->sequence ) { 
			#Prepare INSERT for entities with sequence and single primary key
			#Find next primary key value
			my $sth = $self->dbh->prepare(q(SELECT nextval(?) as id));
			$sth->execute($self->sequence);
			if ( my $row = $sth->fetchrow_hashref() ) {
				my $col = ($self->pkc)[0]->{key};
				eval{$self->$col($row->{id})};
				$self->debug("New sequence value from " . $self->sequence . " = $row->{id}") if ( $self->root->app->mode('development') );
			} else {
				$self->die("Cant fetch next value from sequence "  . $self->sequence, __LINE__);
			}
			#Pripravime sql dotaz
			my $query = "INSERT INTO " . $self->entity . "(" . join(", ", map { $_->{key} } $self->columns) . ") VALUES (" . join(", ", map { "?" } $self->columns) . ")";
			$sth = $self->dbh->prepare($query);
			$self->root->set_locale("C");
			$sth->execute();
			$self->root->restore_locale();
		} elsif ( scalar($self->pkc) == 1 && scalar( grep { defined } $self->pkv ) == 0 ) {
			#Prepare UPDATE query for single primary keys
			my $query = "UPDATE " . $self->entity . " SET " . join(" = ?,", map { $_->{key} } $self->attrc) . " = ? WHERE " . join(" = ?,", map { $_->{key} } $self->pkc) . " = ?";
			$self->debug("$query (". join (',', $self->attrv, $self->pkv) . ")") if ( $self->root->app->mode('development') );
			my $sth = $self->dbh->prepare($query);
			$self->root->app->set_locale;
			$sth->execute($self->attrv, $self->pkv);
			$self->root->app->restore_locale;
		} else {
			$self->die("Not defined save method for this combination of primary keys", __LINE__);
		}
	} else {
		$self->die("Not all needs for saving record to database.", __LINE__);
	}
}
#}}}
#{{{ pkc
=head3 pkc

Return list of primary keys columns

=cut
sub pkc {
	my $self = shift;
	$self->{_pkc} = [ grep { defined($_->{primary_key}) && $_->{primary_key} == 1 } $self->columns ] unless ( defined($self->{_pkc}) );
	return(@{$self->{_pkc}});
}
#}}}
#{{{ pkv
=head3 pkv

Return list of primary keys values

=cut
sub pkv {
	my $self = shift;
	$self->{_pkv} = [ map { my $col = $_->{key};eval{$self->$col}; } $self->pkc ];
	return(@{$self->{_pkv}});
}
#}}}
#{{{ attrc
=head3 attrc

Return list of attribute columns (no primary keys columns)

=cut
sub attrc {
	my $self = shift;
	$self->{_attrc} = [ grep { ! $_->{primary_key} } $self->columns ] unless ( defined($self->{_attrc}) );
	return(@{$self->{_attrc}});
}
#}}}
#{{{ attrv
=head3 attrv

Return list of attribute values (no primary keys values)

=cut
sub attrv {
	my $self = shift;
	$self->{_attrv} = [ map { my $col = $_->{key};eval{$self->$col}; } $self->attrc ];
	return(@{$self->{_attrv}});
}
#}}}
#{{{ sequence
=head3 sequence

Return name sequence in column definiton (if is defined more than one sequences return first sequence)

=cut
sub sequence {
	my $self = shift;
	my @sec = grep { $_->{sequence} } $self->pkc;
	if ( scalar(@sec) ) {
		return($sec[0]->{sequence});
	} else {
		$self->die("Sequence is not defined", __LINE__);
	}
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
