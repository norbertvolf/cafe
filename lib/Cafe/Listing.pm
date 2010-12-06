package Cafe::Listing;
use strict;
use warnings;
use utf8;
use constant {
	NEXT        =>  1,
	PREV        =>  2,
	LAST        =>  3,
	FIRST       =>  4,
	PAGE        =>  5,
	PAGESIZE   =>  18,
};
use base qw(Cafe::Class);
use DBD::Pg qw(:pg_types);
use Cafe::NamedQuery;
use Cafe::Class;
use Carp;

#{{{ new
=head1 NAME

Cafe::Listing - Method for implementation listing pages

=head2 DEFINITIONS

You can pass definition as hash as parameter to constructor.

Example:

my $definition = {
	{
		query => q(
			SELECT DISTINCT
				cd.iddirective,
				mu.signature,
				cd.fromdate,
				cd.statestamp
				FROM chain.directives cd
					LEFT JOIN schema.users mu
						ON cd.stateuser = mu.iduser
					LEFT JOIN chain.directivecontents dc
						ON dc.iddirective = cd.iddirective
				WHERE 
					lower(cd.iddirective::varchar || dc.subject || dc.content || coalesce(mu.signature, mu.username, '')) LIKE '%' 
					AND (cd.state & 4 = 0)
			LIMIT @limit OFFSET @offset
		),
		querycount => q(
			SELECT 
				count(*) as count
				FROM (
					SELECT DISTINCT
						cd.iddirective,
						cd.fromdate,
						cd.state,
						cd.stateuser,
						coalesce(mu.signature, mu.username, '') as stateusername
						FROM chain.directives cd
							LEFT JOIN schema.users mu
								ON cd.stateuser = mu.iduser
							LEFT JOIN chain.directivecontents dc
								ON dc.iddirective = cd.iddirective
						WHERE 
							lower(cd.iddirective::varchar || dc.subject || dc.content || coalesce(mu.signature, mu.username
							AND (cd.state & 4 = 0)
				) x
		),
		orderby => [
			{ 
				'ascending' => 'DESC',
				'column' => 'cd.iddirective'
			}
		],
		columns => {
			fulltext => {
				type => Cafe::Class::DB_VARCHAR,
				null => Cafe::Class::DB_NOTNULL,
				rule => 1,
				opts => 60,
				default_session => 1,
			},
		}
	}
};



=head3 DEFINITION STRUCTURE

=over

=item query - contanins query used by Cafe::Listing to 
		fetch data from database. This string is 
		converted to Cafe::NamedQuery during 
		inicialization of Cafe::Listing. This
		parameter is mandatory.

=item querycount - contanins query used by Cafe::Listing 
		to fetch information about number of rows, 
		which will be fetched by query. This string is 
		converted to Cafe::NamedQuery during 
		inicialization of Cafe::Listing. This
		parameter is not mandatory. It this parameter
		not defined or parameter query don't use
		LIMIT clause than Cafe::Listing cannot
		use perpage feature.

=item columns - This parameter contains definition of columns
		used for filtering. It will be used also for
		definition of auto-template listing in the 
		future. Definition is in Cafe::Class man
		page or in example or source in code now().

=item orderby - This parameter contains default order by
		definition.

=back

=cut

=head2 new()

Create instance of Cafe::Listing. Parameter $root is 
root instance of Cafe::Application. Parameter $parent
can be same as root or can be parent class based on
Cafe::Class. $dbh is alternative dbh used before
Cafe::Application->{dbh}.

=cut
sub new {
	my ($self, $root, $parent, @params) = @_;
	my $instance;


	if ( ref($params[0]) eq "HASH" ) {
		#Class listing don't use memcached default
		if ( ! exists($params[0]->{ttl}) ) {
			$params[0]->{ttl} = 0;
		}
		$instance = $self->SUPER::new($root, $parent, $params[0]); 
		bless($instance);
		
		#Add page position definitions
		if ( ! exists( $instance->{_definition}->{columns}->{perpage}) ) {
			$instance->{_definition}->{columns}->{perpage} =  {
				type => Cafe::Class::DB_INT,
				msgid => 1024,
				null => Cafe::Class::DB_NULL,
				rule => 1,
				default_session => 1,
				default => 25
			};
		}

		if ( ! exists( $instance->{_definition}->{columns}->{position}) ) {
			$instance->{_definition}->{columns}->{position} =  {
				type => Cafe::Class::DB_INT,
				msgid => 1025,
				null => Cafe::Class::DB_NULL,
				rule => 1,
				default_session => 1,
				default => 0
			};
		}
		$instance->queryinit();
	}

	$instance->{pages} = [];
	$instance->{list} = [];
	$instance->{_count} = undef;
	$instance->{more} = 0;

	return $instance;
}
#}}}

#{{{ is_filter
=head2 is_filter

Return 1 if listing need filter section or 0 if listing doesn't need
filter section.

=cut
sub is_filter {
	my ($self) = @_;
	my $cnt = 0;
	if ( $self->columns() ) {
		$cnt = grep { $_->{rule} } @{$self->columns()};	
	}
	return($cnt);
};
#}}}

#{{{ is_pager
=head2 is_pager

Return 1 if listing need pager or 0 if listing doesn't need
pager.

=cut
sub is_pager {
	my ($self) = @_;

	return(1) if exists($self->definition->{querycount});
	return(0);
};
#}}}

#{{{ queryinit
=head2 queryinit

Initialize NamedQuery, dbh. It suppose $query to be a hash with 
{ query=>, querycount=>, orderby=> } keys. Query is required, 
other ones are optional

=head3 Parameters

=over 

=item $query - string with SQL command

=item $dbh - DBI database handle

=back 

=cut
sub queryinit {
	my ($self, $query, $dbh) = @_;

	if ( ! defined($query) ) {
		$query = $self->{_definition}
	}

	if ( ! defined($dbh) ) {
		$dbh = exists($self->{_definition}->{dbh}) ? $self->{_definition}->{dbh} : $self->dbh();
	}

	if ( exists($query->{query}) ) {
		$self->{query} = new Cafe::NamedQuery($dbh, $query->{query});
	} else {
		die "AF error " . __FILE__ . " line " . __LINE__ . ": query parameter must be defined for Cafe::Listing class.";
	}

	if ( exists($query->{querycount}) ) {
		$self->{querycount} = new Cafe::NamedQuery($dbh, $query->{querycount});
	}

	if ( exists($query->{orderby}) && ref($query->{orderby}) eq "ARRAY" ) {
		$self->{orderby} = $query->{orderby};
	} elsif ( ! exists($self->{orderby}) ) {
		$self->{orderby} = [];
	}
};
#}}}

#{{{ rules
#Tahle metoda je schopna pocitat pozici na seznamu
#stranek. Vola se s potomka, takze potomek nemusi 
#vypocitavat parametry perpage a position
sub rules {
	my ( $self, $content ) = @_;
	my ( $retval) = 0;
	my (%content);
	my ( $perpage, $position );

	if ( ! $content ) {
		if ( $self->{root}->{request}->param() ) {
			my %content = %{$self->{root}->{request}->param()};
			$content = \%content;
		}
	}

	#Rules for special page variables from client
	if ( $content->{command} ) {
		$self->{_position_command} = $content->{command} + 0;
	}

	#Doplnit v pripade neexistence predani parametru z klienta parametry
	#ze session
	my $key;
	foreach $key (keys(%{$self->{_definition}->{columns}})) {
		if ( ! exists( $content->{$key} ) && $self->{_definition}->{columns}->{$key}->{default_session} ) {
			$self->default_session($key, $self->{_definition}->{columns}->{$key}->{default});
		}
	}
	
	$self->default_session("orderby", $self->{orderby});

	#Udelat nad columns kontrolu spravnosti a zapsat do sessions
	$self->SUPER::rules($content);
	#Parse orderby commands from client
	if ( exists($content->{orderby}) ) {
		my $orderby = $content->{orderby};
		#Check order by items
		my @orderby;
		my @orderby_pre = split(/,/, $orderby);
		foreach  $orderby (@orderby_pre) {
			if ( $orderby =~ /^\s*([A-Za-z0-9._]+)\s*$/) { push(@orderby, { column => $1, ascending => 'ASC' } ); }
		}

		#Copy to class property and compare with old order by to ascending
		for (my $i = 0 ; $i < scalar(@orderby); $i++ ) {
			if (
				ref($self->{orderby}->[$i]) eq "HASH"
				&& defined($self->{orderby}->[$i]->{column})
				&& $orderby[$i]->{column} eq $self->{orderby}->[$i]->{column}
			) {
				if ( $self->{orderby}->[$i]->{ascending} eq 'ASC' ) {
					$orderby[$i]->{ascending} = 'DESC';
				} else {
					$orderby[$i]->{ascending} = 'ASC';
				}
			}
		}
		$self->{orderby} = \@orderby;
	}

	#Save orderby to session
	if ( ! defined($self->{root}->{session}->{ref($self)}) ) {
		$self->{root}->{session}->{ref($self)} = {};
	}
	$self->{root}->{session}->{ref($self)}->{orderby} = $self->{orderby};

	return(!$self->{msgid});
}
#}}}

#{{{ count
=item count
Return count of sql rows (if querycount is defined) or 
count of $self->{list} array
=cut
sub count {
	my ($self) = @_;
	my ($sth, $row, $key);
	#Pokud neni definovany querycount, vse se ignoruje  a fce vraci undef

	if ( ! defined($self->{"_count"}) && defined($self->{"querycount"}) ) {

		#Try load count from memcache if possible
		if ( $self->definition->{ttl} && $self->definition->{ttl} > 0 && $self->root()->memd() ) {
			#Load data from memcache
			$self->{root}->set_local_locale("C");
			$self->{"_count"} = $self->root()->memd()->get($self->key_count);
			$self->{root}->restore_local_locale();
		}

		#We cannot fetch data from memcached, we must fetch data from database	
		if ( ! defined($self->{"_count"}) )  {
			$self->prepare_parameters();
			$self->{querycount}->bind_params($self->{params});
			$self->{querycount}->sth()->{pg_server_prepare} = 0;
			$self->{querycount}->sth()->execute() or die "AF error " . __FILE__ . " line " . __LINE__ . ": $!";

			if ( $row = $self->{querycount}->sth()->fetchrow_arrayref() ){
				#Vysledek je ocekavany v prvni polozce
				$self->{"_count"} = $row->[0];
			}
			$self->{querycount}->sth()->finish();

			if ( $self->definition->{ttl} && $self->definition->{ttl} > 0 && $self->root()->memd() ) {
				#Save data to memcache
				$self->{root}->set_local_locale("C");
				my $retval = $self->root()->memd()->set($self->key_count, $self->{"_count"}, $self->definition()->{ttl});
				$self->{root}->restore_local_locale();

				if ( $retval == 0 ) {
					print(STDERR "AF warning " . __FILE__ . " line " . __LINE__ . "Error write data to memcached server.");	
				}
			}
		}
	} elsif ( ! defined($self->{"querycount"}) ) {
		$self->{"_count"} = scalar(@{$self->{list}}) + 1;
	}
	return($self->{"_count"});
}
#}}}

#{{{ prepare_parameters
sub prepare_parameters {
	my ($self) = @_;
#Pripravi seznam parametru pro dotaz (pouzijeme pojmenovane parametry)
	foreach my $key ( keys(%{$self->{_definition}->{columns}}) ) {
		my $column = $self->{_definition}->{columns}->{$key};
		if ( $column->{type} && $column->{type} == Cafe::Class::DB_DATE ) {
			$self->{params}->{$key} = { "value" => $self->{$key} ? $self->{$key}->datetime() : undef , type => { pg_type => PG_VARCHAR } };
		} elsif ( $column->{type} && $column->{type} == Cafe::Class::DB_INT ) {
			$self->{params}->{$key} = { "value" => $self->{$key}, type => { pg_type => PG_INT4 } };
		} elsif ( $column->{type} && $column->{type} == Cafe::Class::DB_INT8 ) {
			$self->{params}->{$key} = { "value" => $self->{$key}, type => { pg_type => PG_INT8 } };
		} else {
			$self->{params}->{$key} = { "value" => $self->{$key}, type => { pg_type => PG_VARCHAR } };
		}

		if ( $column->{prepare} && ref($column->{prepare}) eq "CODE" ) {
			$self->{params}->{$key}->{value} = &{$column->{prepare}}($self->{params}->{$key}->{value});
		}
	}
}
#}}}

#{{{ load
=head2 load

Load persistent data from databases by query defined
in class.

=head3 Parameters

=over 

=item $force - if is defineda and true (!=0) ignore preloaded data

=back 

=cut
sub load {
	my ($self, $force) = @_;
	my ($sth, $row, $key);
	my @dates;
	my $values;
	use vars qw($memcached_error);

	#Call position to compute actual position and save actual position to session
	$self->position();

	if ( ! $self->{_loaded} || $force ) {
		#Prapare load parameters and initialize date converting array
		$self->prepare_parameters();
		if ( ! $self->{perpage} ) { $self->{perpage} = 25; }
		if ( ! defined($self->{position}) ) { $self->{position} = 0; }

		#Search Cafe::Class::DB_DATE columns for Time::Piece converting
		foreach my $key ( keys(%{$self->definition->{columns}}) ) {
			if ( $self->definition->{columns}->{$key}->{type} && $self->definition->{columns}->{$key}->{type} == Cafe::Class::DB_DATE ) {
				push(@dates, $key);
			}
		}

		#Try load list from memcache if possible
		if ( $self->definition->{ttl} && $self->definition->{ttl} > 0 && (! $force) && $self->root()->memd() ) {
			#Load data from memcache
			$self->{root}->set_local_locale("C");
			$values = $self->root()->memd()->get($self->key);
			$self->{root}->restore_local_locale();
		}

		#Load data from database
		if ( ! defined($values) || $force ) {
			$self->{params}->{limit} = { value => int($self->{perpage}), type => { pg_type => PG_INT4 } };
			$self->{params}->{offset} = { value => int($self->{position} * $self->{perpage}), type => { pg_type => PG_INT4 }  };

			#Nacteme data do vlastnosti list
			$self->{query}->orderby($self->{orderby});
			$self->{query}->bind_params($self->{params});

			$self->{query}->sth()->{pg_server_prepare} = 0;
			$self->dbh->{RaiseError} = 1; 
			$self->{query}->sth()->execute() or die "AF error " . __FILE__ . " line " . __LINE__ . "\n\nError: $! (Class: " . ref($self) . " \n\nSQL Command: $self->{query}->{query}->{sql})\n\n";
			$self->dbh->{RaiseError} = 0; 

			$values = [];
			while ( $row = $self->{query}->sth()->fetchrow_hashref() ){
				push(@{$values}, $row);
			}
			$self->{query}->sth()->finish();

			#If ttl is defined save data to memcache
			if ( $self->definition->{ttl} && $self->definition->{ttl} > 0 && $self->root()->memd() ) {
				#Save data to memcache
				$self->{root}->set_local_locale("C");
				my $retval = $self->root()->memd()->set($self->key, $values, $self->definition()->{ttl});
				$self->{root}->restore_local_locale();

				if ( $retval == 0 && ! $memcached_error) {
					$memcached_error = 1;
					print(STDERR "AF warning " . __FILE__ . " line " . __LINE__ . " Error write data to memcached server.\n");	
				}
			}
		}

		if ( $values ) {
			$self->{_loaded} = 1;
			if ( scalar(@dates) ) {
				foreach my $row (@{$values}) {
					map { $row->{$_} = $self->to_time_piece($row->{$_}) } @dates;
				}
			}
			$self->{list} = $values;
		}
	}

	return($self->{list});
}
#}}}

#{{{ maxpage
sub maxpage {
	my ($self) = @_;
	if ( defined( $self->count() ) ) {
		if ( ! $self->{perpage} ) { $self->{perpage} = 25; }
		return(int($self->count() / $self->{perpage}));
	} else {
		return(0);
	}
}
#}}}

#{{{ more
sub more {
	my ($self) = @_;
	if ( $self->maxpage()  > PAGESIZE ) {
		return(1);
	} else {
		return(0);
	}
}
#}}}

#{{{ lastpagevisible
#Vracti 1 kdyz je v pages videt posledni strankg
sub lastpagevisible {
	my ($self) = @_;
	if ( $self->{position} > ($self->maxpage() - int(PAGESIZE / 2)) ) {
		return(1);
	} else {
		return(0);
	}
}
#}}}

#{{{ firstpagevisible
#Vracti 0 kdyz je v pages videt posledni strankg
sub firstpagevisible {
	my ($self) = @_;
	if ( $self->{position}  < int(PAGESIZE / 2) ) {
		return(1);
	} else {
		return(0);
	}
}
#}}}

#{{{ pages
sub pages {
	my ($self) = @_;
	my ($i, $startpage, $endpage);

		#Definujeme stranku na ktere budeme zacinat
		if ( $self->{"position"} < int(PAGESIZE / 2) ) {
			$startpage = 0;
		} else {
			$startpage = $self->{"position"} - int(PAGESIZE / 2);
		}

		#Definujeme stranku na ktere budeme koncit
		if ( ($startpage + PAGESIZE) > $self->maxpage() ) {
			$endpage = $self->maxpage();
		} else {
			$endpage = $startpage + PAGESIZE;
		}

	for ( $i = $startpage; $i <= $endpage; $i++) {
		$self->{pages}->[$i - $startpage]->{index} = $i;
		$self->{pages}->[$i - $startpage]->{start} = $i * $self->{perpage} + 1;
		$self->{pages}->[$i - $startpage]->{end} = ($i + 1) * $self->{perpage} < $self->count() ? ($i + 1) * $self->{perpage} : $self->count();
	}

	return($self->{pages});
}
#}}}

#{{{ gethash
=head2 gethash

Create hash by definition in definitions hash. 
List can by converted to arrays, or alsu to hash.
If parameter $array_enabled <> 0 then 

=cut

sub gethash() {
	my ($self, $unlocalized) = @_;
	my $data = $self->SUPER::gethash($unlocalized);
	if ( $self->{list} ) {
		$data->{list} = [];
		foreach my $item ( @{ $self->{list} } ) {
			if ( ref( $item ) eq "HASH" ) {
				push(@{$data->{list}}, $item);
			} else {
				push(@{$data->{list}}, $item->gethash($unlocalized));
			}
		}
	}
	return($data);
}
#}}}

#{{{ save
=item Method save
Save all objects in list
=cut
sub save {
    my ($self) = @_;

	#Save all items
	foreach my $item (@{$self->{list}} ) {
		$item->save();
	}

	#Remove deleted items from list
	for(my $i = 0; $i < scalar(@{$self->{list}} ); $i++) {
		if ( $self->{list}->[$i]->{state} && ($self->{list}->[$i]->{state} & 4) == 4 )  {
			splice(@{$self->{list}}, $i, 1);
			$i--;
		}
	}
}
#}}}

#{{{ getbyproperty
=head2 Method getbyproperty

Return element defined by id

=head3 Parameters

=over 

=item $property - name of column from $self->{list}

=item value - value of property

=back 

=cut
sub getbyproperty {
	my ($self, $property, $value) = @_;

	foreach my $item ( @{$self->{list}} ) {
		if ( $item->{$property} eq $value ) {
			return ( $item );
		}
	}
}
#}}}

#{{{ col
=head2 Method col

Return array based on one column from $self->{list}

=head3 Parameters

=over 

=item $col - name of column from $self->{list}

=item return array created from $self->{list} (array of hashes)

=back 

=cut 
sub col {
    my ($self, $col) = @_;
	my $list = [];
	foreach my $row (@{$self->{list}}) {
		push(@{$list}, $row->{$col});
	}
	return($list);
}
#}}}

#{{{ key
=head2 Method key

Return unique key for instance of Cafe::Listing. Key is derived from
definition column containing parameter rule => 1. This key is used for
save list to memcached server.

=cut 
sub key {
	my ($self) = @_;
	#Prepare key for memcached
	my @key = (ref($self));
	push(@key, 'WHERE');
	foreach my $key (keys(%{$self->definition->{columns}})) {
		if ( $self->definition->{columns}->{$key}->{rule} ) {
			push(@key, $key);
			if ( $self->definition->{columns}->{$key}->{type} && $self->definition->{columns}->{$key}->{type} == Cafe::Class::DB_DATE ) {
				push(@key, defined($self->{$key}) ? $self->{$key}->datetime() : "undef");
			} else {
				push(@key, defined($self->{$key}) ? $self->{$key} : "undef");
			}
		}
	}
	
	push(@key, 'ORDERBY');

	foreach my $order (@{$self->{orderby}}) {
		push(@key, $order->{column});
		push(@key, $order->{ascending});
	}
	return(join("|" , @key));
}
#}}}

#{{{ key_count
=head2 Method key_count

Return unique key for instance of Cafe::Listing without order by 
and position recognition. This key is used for storing and gettign 
information about count.

=cut 
sub key_count {
	my ($self) = @_;
	#Prepare key for memcached
	my @key = (ref($self));
	push(@key, 'COUNT');
	push(@key, 'WHERE');
	foreach my $key (keys(%{$self->definition->{columns}})) {
		if ( 
			$self->definition->{columns}->{$key}->{rule} && $key ne "position" && $key ne "perpage"
		) {
			push(@key, $key);
			if ( $self->definition->{columns}->{$key}->{type} && $self->definition->{columns}->{$key}->{type} == Cafe::Class::DB_DATE ) {
				push(@key, defined($self->{$key}) ? $self->{$key}->datetime() : "undef");
			} else {
				push(@key, defined($self->{$key}) ? $self->{$key} : "undef");
			}
		}
	}
	return(join("|" , @key));
}
#}}}

#{{{ position
=head2 Method position

Return actual position for pager

=cut 
sub position {
	my ($self) = @_;

	my $changed;

	if ( $self->{_position_command} ) {
		if ( $self->{_position_command} && $self->{_position_command} == PREV ) {
			$self->{position} = $self->{position} - 1;
			$changed = 1;
		} elsif ( $self->{_position_command} && $self->{_position_command} == NEXT ) {
			$self->{position} = $self->{position} + 1;
			$changed = 1;
		} elsif ( $self->{_position_command} && $self->{_position_command} == FIRST ) {
			$self->{position} = 0;
			$changed = 1;
		} elsif ( $self->{_position_command} && $self->{_position_command} == LAST ) {
			$self->{position} = $self->maxpage();
			$changed = 1;
		}
		
		#Clean command for prevent other operations
		$self->{_position_command} = undef;
	}

	
	
	if ( ! defined($self->{position}) || $self->{position} < 0 ) {
		$self->{position} = 0;
		$changed = 1;
	}

	if ( $self->{position} > 0 && $self->{position} > $self->maxpage() ) {
		$self->{position} = $self->maxpage();
		$changed = 1;
	}

	if ( $changed ) {
		#Save positions to session
		if ( ! defined($self->{root}->{session}->{ref($self)}) ) {
			$self->{root}->{session}->{ref($self)} = {};
		}
		$self->{root}->{session}->{ref($self)}->{position} = $self->{position};
		$self->{root}->{session}->{ref($self)}->{perpage} = $self->{perpage};
	}

	return($self->{position});
}
#}}}

#{{{ clear_cache
=head2 clear_cache

Clear data saved to cache

=cut
sub clear_cache {
	my ($self) = @_;

	if ( $self->definition->{ttl} && $self->definition->{ttl} > 0 && $self->root()->memd() ) {
		#Clear data in memcache
		$self->root()->memd()->delete($self->key);
		$self->root()->memd()->delete($self->key_count);
	}

	return($self->{list});
}
#}}}

#{{{ check
=head2 check
	check instances in list
=cut
sub check {
	my ($self) = @_;

	foreach my $item (@{$self->{list}} ) {
		if ( ! $item->check() ) {
			return 0;
		}
	}

	return 1;
}
#}}}

#{{{ primary_values
=head2 primary_values

	Return primary values of row (row is passed as first parameter)

=cut
sub primary_values {
	my ($self, $row) = @_;
	my @primary_values;
	foreach my $key (@{$self->primary_keys()}) {
		my $value = $row->{$key};
		push(@primary_values,  $value);
	}
	return(\@primary_values);
}
#}}}

#{{{ summaries
=head2 summaries

Prepare summeries by definitions and return summReturn array of summaries defined in columns definition
by key sum (true).

=cut
sub summaries {
	my ($self) = @_;
	my @summaries;
	
	if ( ! defined($self->{_issummaries}) ) {
		foreach my $key ( keys(%{$self->definition->{columns}}) ) {
			if ( $self->definition->{columns}->{$key}->{summary} ) {
				die "Summary of dates is impossible" if ( $self->definition->{columns}->{$key}->{type} == Cafe::Class::DB_DATE );
				$self->definition->{columns}->{$key}->{sum} = 0;
				push(@summaries, $key);
			}
		}

		if ( scalar(@summaries) ) {
			foreach my $row ( @{$self->{list}} ) {
				foreach my $key ( @summaries ) {
					$self->definition->{columns}->{$key}->{sum} += $row->{$key};
				}
			}
		}

		foreach my $key ( @summaries ) {
			if ( ref($self->definition->{columns}->{$key}->{summary}) eq "CODE" ) {
				&{$self->definition->{columns}->{$key}->{summary}}($self->definition, $key);
			}
		}

		$self->{_issummaries} = scalar(@summaries);
	}
	return($self->{_issummaries});
}
#}}}

#{{{ url
=head2 url

Return url based on definition.

=over Parameters

=item $row - reference to row with url parameter values

=item $column - name of column to find url definition

=back

=cut
sub url {
	my $self = shift;
	my $column = shift;
	my $row = shift;
	my $url;

	
	if ( $row && $column) {
		if ( exists( $self->definition()->{columns}->{$column}) ) {
			$url = $self->definition->{columns}->{$column}->{url}->{prefix};
			$url .= ( $url =~ /\?/ ? "&" : "?" );
			$url .= join("&", map { "$_=$row->{$_}"} @{$self->definition->{columns}->{$column}->{url}->{params}});
		} else {
			die "Column with url parameters is not defined";
		}
	}
	return($url);
}
#}}}


sub DESTROY {
	my ($self) = @_;
}

1;
