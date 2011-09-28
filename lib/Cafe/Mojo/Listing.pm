package Cafe::Mojo::Listing;

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

use Mojo::Base 'Cafe::Mojo::Class';
use DBD::Pg qw(:pg_types);
use Carp;

#{{{ new
=head1 NAME

Cafe::Listing - Method for implementation listing pages

=head1 SYNOPSIS

 package Schema::Device::Search;
 use base qw(Cafe::Listing);

 sub new {
	my ($self, $root, $parent) = @_;
	my ($instance) = $self->SUPER::new(
		$root,
		$parent,
		{
			title => 'Device Search',
			query => q(
				SELECT
					d.iddevice,
					d.serialnumber,
					d.devicename,
					CASE WHEN p.hostname IS NOT NULL AND p.hostname <> '' THEN p.hostname || '.' || n.domainname ELSE '' END as hostname,
					p.address,
					n.public_host,
					n.netaddress,
					s.idstore,
					CASE WHEN s.storename IS NOT NULL THEN s.storename ELSE dp.departmentname END as departmentname,
					CASE WHEN s.storenumber IS NOT NULL THEN s.storenumber::varchar ELSE dp.departmentnumber END as departmentnumber,
					dt.description as devicetype,
					dpv.value as property
					FROM schema.devices d
						LEFT JOIN schema.deviceplaces p
							ON d.iddevice = p.iddevice
						LEFT JOIN schema.networks n
							ON p.idnetwork = n.idnetwork
						LEFT JOIN chain.stores s
							ON n.idstore = s.idstore
						LEFT JOIN schema.department dp
							ON p.iddepartment = dp.iddepartment
						LEFT JOIN schema.devicetypes dt
							ON dt.iddevicetype = d.iddevicetype
						LEFT JOIN schema.device_property_value dpv
							ON d.iddevice = dpv.iddevice 
								AND dpv.iddeviceproperty = @iddeviceproperty
					WHERE d.state & 4 = 0 
						AND ( d.serialnumber ilike  '%' || @serialnumber || '%'  OR @serialnumber IS NULL ) 
						AND ( @search IS NULL OR to_tsvector( coalesce(d.devicename , '')
							|| ' ' || coalesce(s.storename , '')
							|| ' ' || coalesce(s.storenumber::varchar , '')
							|| ' ' || coalesce(dp.departmentname , '')
							|| ' ' || coalesce(dp.departmentnumber::varchar , '')
							|| ' ' || coalesce(s.city , '')
							|| ' ' || coalesce(n.domainname, '')
							|| ' ' || coalesce(dt.description , '')
						) @@ to_tsquery('cs', @search) )
					LIMIT @limit OFFSET @offset

			),
			querycount => q(
				SELECT
					count(*)
					FROM schema.devices d
						LEFT JOIN schema.deviceplaces p
							ON d.iddevice = p.iddevice
						LEFT JOIN schema.networks n
							ON p.idnetwork = n.idnetwork
						LEFT JOIN chain.stores s
							ON n.idstore = s.idstore
						LEFT JOIN schema.department dp
							ON p.iddepartment = dp.iddepartment
						LEFT JOIN schema.devicetypes dt
							ON dt.iddevicetype = d.iddevicetype
						LEFT JOIN schema.device_property_value dpv
							ON d.iddevice = dpv.iddevice 
								AND dpv.iddeviceproperty = @iddeviceproperty
					WHERE d.state & 4 = 0 
						AND ( d.serialnumber ilike  '%' || @serialnumber || '%'  OR @serialnumber IS NULL ) 
						AND ( @search IS NULL OR to_tsvector( coalesce(d.devicename , '')
							|| ' ' || coalesce(s.storename , '')
							|| ' ' || coalesce(s.storenumber::varchar , '')
							|| ' ' || coalesce(dp.departmentname , '')
							|| ' ' || coalesce(dp.departmentnumber::varchar , '')
							|| ' ' || coalesce(s.city , '')
							|| ' ' || coalesce(n.domainname, '')
							|| ' ' || coalesce(dt.description , '')
						) @@ to_tsquery('cs', @search) )
			),
			columns => {
				search => {
					type => Cafe::Class::DB_VARCHAR,
					null => Cafe::Class::DB_NULL,
					opts => 255,

					msgid => 1,
					default_session => 1,
					rule => 1,
					onlyfilter => 1,

					position => 1,
					label => 'Search',
					style => {
						input => '20em',
					}
				},
				serialnumber => {
					type => Cafe::Class::DB_VARCHAR,
					null => Cafe::Class::DB_NULL,
					opts => 255,

					msgid => 1,
					rule => 1,
					default_session => 1,

					position => 2,
					label => 'Serial Number',
					orderby => 'd.serialnumber',
					url => {
						prefix => '/schema2.html?method=device_view',
						params => [
							'iddevice',
						]
					},
					style => {
						input => '20em',
						table => 'text-align:left;',
					}
				},
				iddeviceproperty => {
					type => Cafe::Class::DB_INT,
					null => Cafe::Class::DB_NULL,

					msgid => 3,
					default_session => 1,
					rule => 1,
					onlyfilter => 1,

					position => 3,
					label => 'Property',
					input => 'select',
                                        select => {
                                                autoloader => 'properties',
                                                description => 'fullname',
                                                identifier => 'iddeviceproperty',
                                        },
					style => {
						input => '20em',
					}
				},
				devicename => {
					type => Cafe::Class::DB_VARCHAR,
					position => 4,
					label => 'Device Name',
					orderby => 'd.devicename',
					style => {
						table => 'text-align:left;',
					}
				},
				devicetype => {
					type => Cafe::Class::DB_VARCHAR,
					position => 5,
					label => 'Device Type',
					orderby => 'dt.description',
					style => {
						table => 'text-align:left;',
					}
				},
				departmentnumber => {
					type => Cafe::Class::DB_VARCHAR,
					position => 6,
					label => 'Department Number',
					orderby => 'dp.departmentnumber',
					url => {
						prefix => '?method=store_view',
						params => [
							'idstore',
						]
					},
				},
				departmentname => {
					type => Cafe::Class::DB_VARCHAR,
					position => 7,
					label => 'Department Name',
					orderby => 'dp.departmentname',
					url => {
						prefix => '?method=store_view',
						params => [
							'idstore',
						]
					},
					style => {
						table => 'text-align:left;',
					}
				},
				hostname => {
					type => Cafe::Class::DB_VARCHAR,
					position => 8,
					label => 'Hostname',
					orderby => 'p.hostname',
					style => {
						table => 'text-align:left;',
					}
				},
				address => {
					type => Cafe::Class::DB_VARCHAR,
					position => 9,
					label => 'IP Address',
					orderby => 'p.address',
				},
				property => {
					type => Cafe::Class::DB_VARCHAR,
					position => 10,
					label => 'Property',
					orderby => 'dpv.value',
					style => {
						table => 'text-align:left;',
					}
				},
			},
			autoloaders => {
				properties => {
					class => 'Schema::Device::Properties',
				},
			},
		}
	);

	bless($instance);

	return $instance;
 }

=over 

=item C<query>

contanins query used by Cafe::Listing to 
fetch data from database. This string is 
converted to Cafe::NamedQuery during 
inicialization of Cafe::Listing. This
parameter is mandatory.

=item C<querycount>

contanins query used by Cafe::Listing 
to fetch information about number of rows, 
which will be fetched by query. This string is 
converted to Cafe::NamedQuery during 
inicialization of Cafe::Listing. This
parameter is not mandatory. It this parameter
not defined or parameter query don't use
LIMIT clause than Cafe::Listing cannot
use perpage feature.

=item C<columns>

This parameter contains definition of columns
used for filtering. It will be used also for
definition of auto-template listing in the 
future. 

B<Definition>

=over

=item column key 

Name of column normally attribute name from database or filter field used in query/querycount.

=over

=item type

Type of column from Cafe::Class

=item position

Position of column in filter form on header of table 

=item label

Key to translations used as field name in filter form on header of table

=item orderby

Definiton of order by used by click on header of table

=item url

Definiton url used for click from rows

=item style

CSS style of row cell or field

=item formatcbk

Callback function called from template to formate value

=back

=back

  departmentname => {
    type => Cafe::Class::DB_VARCHAR,
    position => 7,
    label => 'Department Name',
    orderby => 'dp.departmentname',
    url => {
      prefix => '/schema2.html?method=store_view',
      nobaseurl => 1,
      params => [
        'idstore',
      ]
    },
    style => {
      table => 'text-align:left;',
    }
  },


=item orderby 

This parameter contains default order by
definition.

=back

=head1 METHODS

=head3 C<new>

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
				null => Cafe::Class::DB_NULL,
				rule => 1,
				default_session => 1,
				default => 25
			};
		}

		if ( ! exists( $instance->{_definition}->{columns}->{position}) ) {
			$instance->{_definition}->{columns}->{position} =  {
				type => Cafe::Class::DB_INT,
				null => Cafe::Class::DB_NULL,
				rule => 1,
				default_session => 1,
				default => 0
			};
		}

		#Order by
		if ( exists($instance->{_definition}->{orderby}) && ref($instance->{_definition}->{orderby}) eq "ARRAY" ) {
			$instance->{orderby} = $instance->{_definition}->{orderby};
		} elsif ( ! exists($instance->{orderby}) ) {
			$instance->{orderby} = [];
		}
	}

	$instance->{pages} = [];
	$instance->{list} = [];
	$instance->{_count} = undef;
	$instance->{more} = 0;

	return $instance;
}
#}}}
#{{{ is_filter
=head3 C<is_filter>

Return 1 if listing need filter section or 0 if listing doesn't need
filter section.

=cut
sub is_filter {
	my ($self) = @_;
	my $cnt = 0;
	$cnt = scalar(grep { $_->{rule} } @{$self->columns()}) if ( $self->columns() );
	return($cnt);
};
#}}}
#{{{ is_pager
=head3 C<is_pager>

Return 1 if listing need pager or 0 if listing doesn't need
pager.

=cut
sub is_pager {
	my ($self) = @_;

	return(1) if exists($self->definition->{querycount});
	return(0);
};
#}}}
#{{{ rules
#Tahle metoda je schopna pocitat pozici na seznamu
#stranek. Vola se s potomka, takze potomek nemusi 
#vypocitavat parametry perpage a position
sub rules {
	my ( $self, $content ) = @_;
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
	my $retval = $self->SUPER::rules($content);

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

	return($retval);
}
#}}}
#{{{ count
=head3 C<count>

Return count of sql rows (if querycount is defined) or 
count of $self->{list} array

=cut
sub count {
	my ($self) = @_;
	my ($sth, $row, $key);
	#Pokud neni definovany querycount, vse se ignoruje  a fce vraci undef

	if ( ! defined($self->{"_count"}) && exists($self->definition->{querycount}) ) {

		#Try load count from memcache if possible
		if ( $self->root()->memd() ) {
			#Load data from memcache
			$self->{root}->set_local_locale("C");
			$self->{"_count"} = $self->root()->memd()->get($self->key_count);
			$self->{root}->restore_local_locale();
		}

		#We cannot fetch data from memcached, we must fetch data from database	
		if ( ! defined($self->{"_count"}) )  {
			my $querycount = new Cafe::NamedQuery($self->dbh, $self->definition->{querycount});
			$self->prepare_parameters();
			$querycount->bind_params($self->{params});
			$querycount->sth()->{pg_server_prepare} = 0;
			$querycount->sth()->execute() or die "AF error " . __FILE__ . " line " . __LINE__ . ": $!";

			if ( $row = $querycount->sth()->fetchrow_arrayref() ){
				#Vysledek je ocekavany v prvni polozce
				$self->{"_count"} = $row->[0];
			}
			$querycount->sth()->finish();

			#
			if ( $self->root()->memd() ) {
				#Save data to memcache - a tam zapiseme vzdycky, count neni tak dulezity, aby nemohl byt cache, ale pokud neni implicitni, dame kratke ttl 1 min
				my $ttl = $self->definition()->{ttl} ? $self->definition()->{ttl} : 300;
				$self->{root}->set_local_locale("C");
				my $retval = $self->root()->memd()->set($self->key_count, $self->{"_count"}, $ttl);
				$self->{root}->restore_local_locale();

				if ( $retval == 0 ) {
					print(STDERR "AF warning " . __FILE__ . " line " . __LINE__ . "Error write data to memcached server.");	
				}
			}
		}
	} elsif ( ! defined($self->definition->{querycount}) ) {
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
			my $value;
			eval("\$value = \$self->$key()");
			$self->{params}->{$key} = { "value" => ref($value) eq "Time::Piece" ? $value->datetime() : undef , type => { pg_type => PG_VARCHAR } };
		} elsif ( $column->{type} && $column->{type} == Cafe::Class::DB_INT ) {
			$self->{params}->{$key} = { type => { pg_type => PG_INT4 } };
			if ( $key eq 'position' ) {
				#Prevent recursion duting calll position -> maxpage -> count -> prepare_parameters
				$self->{params}->{$key}->{value} = $self->{position};
			} else {
				eval("\$self->{params}->{$key}->{value} = \$self->$key()");
			}
		} elsif ( $column->{type} && $column->{type} == Cafe::Class::DB_INT8 ) {
			$self->{params}->{$key} = { type => { pg_type => PG_INT8 } };
			eval("\$self->{params}->{$key}->{value} = \$self->$key()");
		} elsif ( $column->{type} && $column->{type} == Cafe::Class::DB_FULLTEXT ) {
			my $value;
			eval("\$value = \$self->$key()");
			$value =~ s/ /+/g if ($value);
			$self->{params}->{$key} = { "value" => $value, type => { pg_type => PG_VARCHAR } };
		} else {
			$self->{params}->{$key} = { "value" => $self->{$key}, type => { pg_type => PG_VARCHAR } };
			eval("\$self->{params}->{$key}->{value} = \$self->$key()");
		}

		if ( $column->{paramcbk} && ref($column->{paramcbk}) eq "CODE" ) {
			$self->{params}->{$key}->{value} = &{$column->{paramcbk}}($self->{params}->{$key}->{value});
		}
	}
}
#}}}
#{{{ load
=head3 C<load>

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
			my $query;
			if ( exists($self->definition->{query}) ) {
				$query = new Cafe::NamedQuery($self->dbh, $self->definition()->{query});
			} else {
				$self->die("Cafe::Listing::load",  "Value for key \"query\" in definition doesn't exist.", __LINE__);
			}

			$query->orderby($self->{orderby});
			$query->bind_params($self->{params});

			$query->sth()->{pg_server_prepare} = 0;

			eval { $query->sth()->execute() };
			if ($@) {
				print(STDERR "\n-- SQL Query --\n$query->{query}->{sql}\n-- SQL Error --\n$@");
				$self->die("Cafe::Listing::load",  "SQL Query error see above", __LINE__);
			}

			$values = [];
			while ( $row = $query->sth()->fetchrow_hashref() ) {
				push(@{$values}, $row);
			}
			$query->sth()->finish();

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
=head3 C<gethash>

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
=head3 C<Method save>

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
#{{{ col
=head3 C<col>

Return reference to array based on one column 
from $self->list $obj->col('idarticle');

=cut 
sub col {
	my $self = shift;
	my $col = shift;

	my @list = map { $_->{$col} } @{$self->list};

	return wantarray ? @list : \@list;
}
#}}}
#{{{ key
=head3 C<key>

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
=head3 C<key_count>

Return unique key for instance of Cafe::Mojo::Listing without order 
by and position recognition. This key is used for storing and gettign 
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
				push(@key, defined($self->{$key}) && ref($self->{$key}) eq "Time::Piece"  ? $self->{$key}->datetime() : "undef");
			} else {
				push(@key, defined($self->{$key}) ? $self->{$key} : "undef");
			}
		}
	}
	return(join("|" , @key));
}
#}}}
#{{{ position
=head3 C<position>

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
=head3 C<clear_cache>

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
#{{{ primary_values
=head3 C<primary_values>

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
=head3 C<summaries>

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
=head3 C<url>

Return url based on definition.

=over

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
			$url .= join("&", map { "$_=" . ($row->{$_} // "")} @{$self->definition->{columns}->{$column}->{url}->{params}});
		} else {
			die "Column with url parameters is not defined";
		}
	}
	return($url);
}
#}}}
#{{{identifier
=head3 C<identifier>

Method returning string which identify class

=cut 
sub identifier {
	my ($self, $identifier) = @_;
	if ( $identifier ) {
		$self->SUPER::identifier($identifier);
	} else {
		$identifier = lc(ref($self));
		$identifier =~ s/:://g;
		$self->SUPER::identifier($identifier);
	}
	return($self->SUPER::identifier);
}
#}}}
#{{{ list
=head3 C<list>

Getter/setter for list of records

=cut
sub list {
	my $self = shift;
	my $list = shift;
	$self->{list} = $list if ( defined($list) && ref($list) eq 'ARRAY');
	return($self->{list});
}
#}}}
#{{{ find
=head3 C<find>

Return element where property value is same as parameter

$obj->find("idarticle", 12345);

=over 

=item First parameter means property - name of column from $self->list

=item Second parameter means value - value for condition

=back 

=cut
sub find {
	my ($self, $property, $value) = @_;
	my @arr = grep { $_->{$property} eq $value } @{$self->{list}};
	return( $arr[0] ) if ( scalar(@arr) == 1 );
	return( \@arr ) if ( scalar(@arr) > 1 );
}
#}}}

1;
