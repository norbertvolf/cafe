package Cafe::Class;

use strict;
use warnings;
use utf8;
use base qw(Cafe::Object);

use Scalar::Util qw(weaken);
use constant {
	DB_VARCHAR  => 0,
	DB_INT   => 1,
	DB_DATE  => 2,
	DB_NUMERIC  => 3,
	DB_FMTCHAR   => 4,
	DB_INT8   => 6,
	DB_NULL  => 7,
	DB_NOTNULL  => 8,
	DB_FULLTEXT  => 10,
	DB_DATETIMETZ  => 9, #2008-08-11 13:30:00.9990+0200
	CAFE_TTL => 300,
	NOTRANSLATE => 1,
	OK => 1,
	NOK => 0,
};
use POSIX;
use Time::Piece;
use Encode;

#{{{ pod
=head1 NAME

Cafe::Class - Method for implementation bussines logic

=head1 SYNOPSIS

	package Iris::Catalog::Article;
	use utf8;
	use warings;
	use strict;
	use base qw(Cafe::Class);

	sub new {
		my ($self, $root, $parent, $idetiquetteorder) = @_;
		my ($instance) = $self->SUPER::new(
			$root, 
			$parent,
			{
				dbh => undef, #Database handler used by instance, if handler is not defined, class use $root->{dbh}
				name => 'complaints.complaints', #Name of table with persisted instance
				ttl => 300, #Number of seconds used as time to live for memcached values, default value is 300
				form => {
					url => '?type=json',
					method_get => 'device_get',
					method_set => 'device_set',
					method_del => 'device_del',
					method_del_caption => 'Do you want delete device?',
					method_del_url => '?method=device_search',
					caption_edit => 'Edit',
					caption_save => 'Save',
					caption_cancel => 'Cancel',
					caption_delete => 'Delete',
				},
				columns => {
					idcomplaint => {
						type => Cafe::Class::DB_INT, #Definition of input type
						null => Cafe::Class::DB_NULL, #Definition of null value acceptance
						primary_key => 1, #Define column as part of primary key
						sequence => 'complaints.idcomplaint', #Define sequence for artifical primary keys
						rule => 1, #Enable column as possible to input from user


						label => 'Identifier', #Getstring value to generate label on html
						position => 1, #Position inside generated form
					},
					idarticle => {
						type => Cafe::Class::DB_INT,
						null => Cafe::Class::DB_NULL,
						rule => 1,

						label => 'Device Type',
						input => 'select', #Type of widget used in form (defined in Record and TableRecord javascript classes - "text", "select", "checkbox", "area")
						position => 3,
						select => { #Definition of combobox
							autoloader => 'devicetype', #Autoloader to search description by identifier

							#Name of column in listing with description of identifier
							#also used in autoloader 
							description => 'description', 	

							#Identifier (key) from list	
							identifier => 'iddevicetype',

							#Method for fetch list from server via JSON RPC
							method => 'devicetypes_get',
						},

						#CSS styling via inline style, for field 
						style => {
							input => 'width:18em;',
							table => 'text-align:left',
						},
					},
					price => {
						type => Cafe::Class::DB_NUMERIC,
						null => Cafe::Class::DB_NULL,
						rule => 1,

						label => 'Device Price',
						input => 'text', #Type of widget used in form (defined in Record and TableRecord javascript classes - "text", "select", "checkbox", "area")
						position => 4,
						#CSS styling via inline style, for field 
						style => {
							input => 'width:8em;',
							table => 'text-align:right',
						},
					},
					firstname => {
						type => Cafe::Class::DB_VARCHAR,
						null => Cafe::Class::DB_NULL,
						opts => 30,
						rule => 1,
					},
					lastname => {
						type => Cafe::Class::DB_VARCHAR,
						null => Cafe::Class::DB_NULL,
						opts => 30,
						rule => 1,
					},
					'zip' => {
						type => Cafe::Class::DB_FMTCHAR,
						null => Cafe::Class::DB_NULL,
						opts => '^([0-9]{5})$',
						rule => 1,
					},
					startdate => {
						type => Cafe::Class::DB_DATE,
						null => Cafe::Class::DB_NOTNULL,
						rule => 1,
					},
				},
				autoloaders => {
					article => {
						class => 'Iris::Catalog::Article',
						id => 'idarticle',
					},
					attachements => {
						class => 'Complaints::Complaint::Attachements',
						id => 'idcomplaint',
						shadow => '_attachements'
					},
					sales => {
						class => 'Complaints::Complaint::Sales',
						ref => '$self->articlenumber(),fromdate',
						id => 'article,fromdate',
					},
				},
			}
		);
	}

=head1 PROPERTIES

=head2 definition

Definition hash describe persistence data of used by descendant of Cafe::Class.

=head3 autoloaders

Array of hash which contains definitions for create instance of other class connected thru some keys to class. 

=over

=item class - name of destination class (Example: class => 'Complaints::Complaint::Sales')

=item ref - properties from source class, comma separated string with name of columns in source class, you can 
also use any method from base class by starting $self-> ().(Example: ref => '$self->articlenumber(),fromdate')

=item id - properties from destination class, comma separated string with name of columns in destination class
(Example: id => 'article,fromdate').

=item shadow - autoloader automatically create hidden property in source class which contains
instance of destination class with name created from last word in name of destination class (for exemaple _sales), 
you can change this name by this property. (Example: shadow => '_my_sales')

=back 


=head3 Using memcached server

AF2 is possible to use memcached server. You need set memcached_server 
option in apache configureation to enable memcaching:

	PerlSetVar memcached_servers "127.0.0.1:11211"

=cut

=head1 METHODS
#}}}
#{{{ new
#{{{
=head2 new()

Constructor of Cafe::Class. You can send parameters
as one HASH or as four unnamed parameters. Return instance Cafe::Class

=head4 Parameters

=over 

=item $root 

Is root instance of Cafe::Application. 

=item $parent

Can be same as root or can be parent class based on Cafe::Class. 

=item $dbh 

Is alternative dbh used before Cafe::Application->{dbh} 

=item $definition 

Column is reference of hash for define properties of class . (for structure of definition see above)

=back 

=cut
#}}}
sub new {
	my ($self, $root, $parent, @params) = @_;
	my $instance = $self->SUPER::new(); 

	#Set defalut values
	$instance->{message} = "";
	$instance->{_loaded} = 0;
	$instance->{_ok} = OK;
	$instance->{_definition} = {};
	$instance->{root} = $root;
	$instance->{parent} = $parent;

	#Weaken circular references
	if ( ref($instance->{root}) ) { weaken($instance->{root}); }
	if ( ref($instance->{parent}) ) { weaken($instance->{parent}); }

	#Third argument is HASH it means you put all definitions thru this HASH
	if ( ref($params[0]) eq "HASH" ) {
		$instance->{_definition} = $params[0];
		$instance->{dbh} = defined($instance->{_definition}->{dbh}) ? $instance->{_definition}->{dbh} : $root->dbh;
	} else {
		$instance->die("Cafe::Class::new",  "Error in definition of $self definition send as parameter in construction is not hash reference.", __LINE__);
	}
	
	if ( exists($instance->{_definition}->{columns}) ) {
		#Set default values
		foreach my $key (sort(keys(%{$instance->{_definition}->{columns}}))) {
			$instance->{$key} = $instance->{_definition}->{columns}->{$key}->{default} if ( defined($instance->{_definition}->{columns}->{$key}->{default}) );
			$instance->{_definition}->{columns}->{$key}->{translate} = 1 if ( ! defined($instance->{_definition}->{columns}->{$key}->{translate}) );
		}
		#Rich url_base
		foreach my $key (sort(keys(%{$instance->{_definition}->{columns}}))) {
			my $column = $instance->{_definition}->{columns}->{$key};
			$column->{url}->{prefix} = $root->rich_uri($column->{url}->{prefix}) if ( exists($column->{url}) );
			$column->{select}->{method} = $root->rich_uri($column->{select}->{method}) if ( exists($column->{select}) && exists($column->{select}->{method}));
		}
	}
	if ( exists($instance->{_definition}->{autoloaders}) ) {
		#Enable translate as default
		foreach my $key (sort(keys(%{$instance->{_definition}->{autoloaders}}))) {
			$instance->{_definition}->{autoloaders}->{$key}->{translate} = 1 if ( ! defined($instance->{_definition}->{autoloaders}->{$key}->{translate}) );
		}
	}

	if ( exists($instance->{_definition}->{form}) ) {
		my $form = $instance->{_definition}->{form};
		$form->{method_del_url} = $root->rich_uri($form->{method_del_url});
		$form->{method_get} = $root->rich_uri($form->{method_get});
		$form->{method_set} = $root->rich_uri($form->{method_set});
		$form->{method_del} = $root->rich_uri($form->{method_del});
	}

	if ( $root && $root->{user} ) { 
		$instance->{stateuser} = $root->{user}->iduser(); 
	}
	$instance->{state} = 0;
	$instance->{statestamp} = localtime();

	if ( ! defined($instance->{_definition}->{ttl}) ) {
		$instance->{_definition}->{ttl} = CAFE_TTL;
	}

	return $instance;
}
#}}}
#{{{ default_session
=head2 default_session()

Load value to property $name from seession. If not exists value in session 
set value to property from $value parameter.

=cut
sub default_session {
	my ($self, $name, $value) = @_;
	if ( exists($self->{root}->{session}->{ref($self)}->{$name}) ) {
		if ( exists($self->{_definition}->{columns}->{$name}) && $self->{_definition}->{columns}->{$name}->{type} && $self->{_definition}->{columns}->{$name}->{type} == DB_DATE ) {
			if ( defined($self->{root}->{session}->{ref($self)}->{$name}) ) {
				$self->{$name} = gmtime($self->{root}->{session}->{ref($self)}->{$name});
			}
		} else {
			$self->{$name} = $self->{root}->{session}->{ref($self)}->{$name};
		}
	} else {
		$self->{$name} = $value;
	}
}
#}}}
#{{{ definition
=head2 definition

Return hash of definition.	

=cut
sub definition {
	my ($self) = @_;
	return($self->{_definition});
}
#}}}
#{{{ load
=head2 load

Load class data from database or from memcached server 
if memcached_servers is defined in apache configuration.

=cut
sub load {
	my ($self, $force) = @_;
	my ($sth, $row, $key);

	#Try memcache if possible
	if ( $self->primary_defined() && (! $self->{_loaded}) && (! $force) && $self->root()->memd() ) {
		if ( $self->is_primary_values() ) {
			#Prepare key for memcached
			my $key = $self->{_definition}->{name} . join('|',@{$self->primary_values()});

			$self->{root}->set_local_locale("C");
			my $values = $self->root()->memd()->get($key);
			$self->{root}->restore_local_locale();

			if ( $values )  {
				$self->{_loaded} = 1;
				#Prepare list of values needed by to save by memcache
				foreach $key (sort(keys(%{$self->{_definition}->{columns}}))) {
					if ( defined($row->{$key}) && 
						( 
							$self->{_definition}->{columns}->{$key}->{type} == DB_INT 
							|| $self->{_definition}->{columns}->{$key}->{type} == DB_INT8
							|| $self->{_definition}->{columns}->{$key}->{type} == DB_NUMERIC
						)
					) {
						$row->{$key} = $row->{$key} + 0;
					} elsif ( $self->{_definition}->{columns}->{$key}->{type} == DB_DATE && defined($values->{$key})) {
						$self->{$key} = $self->to_time_piece($values->{$key});
					} elsif ( $self->{_definition}->{columns}->{$key}->{type} == DB_DATETIMETZ && defined($values->{$key})) {
						$self->{$key} = $self->to_time_piece($values->{$key});
					} else {
						$self->{$key} = $values->{$key};
					}
				}
				return;
			}
		}
	}

	#Read data from db
	if ( $self->primary_defined() && ! $self->{_loaded} || $force ) {
		if ( $self->{_definition} ) {
			my $columns = join (",", map { $_ = ( $_ =~ /^to$/i ) ? '"' . $_ . '"' : $_ } sort(keys(%{$self->{_definition}->{columns}})));
			my $sql = "SELECT $columns FROM $self->{_definition}->{name} WHERE " . $self->primary_where();
			$sth = $self->{dbh}->prepare($sql);
			$self->{root}->set_local_locale("C");
			$sth->execute( @{$self->primary_values()} ) or die "AF error " . __FILE__ . " line " . __LINE__ . ": $_ - ($sql)";
			$self->{root}->restore_local_locale();
		} else {
			die "AF error " . __FILE__ . " line " . __LINE__ . ": I cannot construct query."
		}

		if ($row = $sth->fetchrow_hashref() ) {
			$self->{_loaded} = 1;
			foreach my $key ( keys(%{$row}) ) {
				if ( 
					$self->{_definition}->{columns}->{$key}->{type} == DB_INT 
					|| $self->{_definition}->{columns}->{$key}->{type} == DB_INT8 
					|| $self->{_definition}->{columns}->{$key}->{type} == DB_NUMERIC 
				) {
					if ( defined($row->{$key}) && $row->{$key} ) {
						$row->{$key} = $row->{$key} + 0;
					}
				} elsif ( $self->{_definition}->{columns}->{$key}->{type} == DB_DATE ) {
					$row->{$key} = $self->to_time_piece($row->{$key});
				} elsif ( $self->{_definition}->{columns}->{$key}->{type} == DB_DATETIMETZ ) {
					$row->{$key} = $self->to_time_piece($row->{$key});
				}
				$self->{$key} = $row->{$key};
			}
		}
		
		$sth->finish();
		
		#Save loaded data to cache
		$self->savetocache();	
	}
}
#}}}
#{{{ save
=head2 save()

Save to database instance of Cafe::Class. Class must 
contain $self->{_definition}->{name}. For new identifier 
you must define   $self->{_definition}->{sequence}.
You must also define columns see SYNOPSIS.

If memcached_servers option is defined in apache configuration
save method also save data to memcached server

=cut 
sub save {
	my ($self) = @_;
	my ($sql, $row, $sth, $column, $key, @values);
	
	#Pokud se v defintions vyskytuji pole
	#statestamp, state a stateuser tak se naplni 
	#tak aby se to nemuselo delat rucne
	if ( $self->{_definition}->{columns}->{stateuser} && $self->{root}->{user}) {
		$self->{stateuser} = $self->{root}->{user}->iduser();
	}

	#Datum posledni upravy nastavime na aktualni cas
	if ( $self->{_definition}->{columns}->{statestamp} ) {
		$self->{statestamp} = localtime();
	}

	#A nastavime si state tak aby odpovidal 
	if ( $self->{_definition}->{columns}->{state} ) {
		if ( ! defined($self->{state}) ) {
			$self->{state} = 0;
		}
		if ( ($self->{state} & 1) == 0 ) {
			$self->{state} = $self->{state} | 1;
		} elsif( ($self->{state} & 1) == 1 && ($self->{state} & 2) == 0 ) {
			$self->{state} = $self->{state} | 2;
		}
	}

	#Pokud mame definice podkladove tabulky tak muzeme provest generovani 
	#dotazu a vlastni ulozeni do databaze
	if (
			$self->{_definition} && 
			$self->{_definition}->{name} && 
			$self->{_definition}->{columns} &&
			scalar(@{$self->primary_keys()})
		) {
		if ( $self->save_type() == 1 ) { # Kdyz zname primarni klic updatujeme
			#Pripravime sql dotaz
			$sql = "UPDATE $self->{_definition}->{name} SET ";
			$sql .= join (" = ?,", map { $_ = ( $_ =~ /^to$/i ) ? '"' . $_ . '"' : $_ } sort(keys(%{$self->{_definition}->{columns}}))) . " = ? ";
			$sql .= "WHERE " . $self->primary_where();
			
			#Pripravime seznam hodnot, ktere predame dotazu
			foreach $key (sort(keys(%{$self->{_definition}->{columns}}))) {
				my $value = $self->{$key};
				push(@values,  $value);
			}
			#Jako posledni pridame hodnutu prmarniho klice
			push(@values,  @{$self->primary_values()});

			$sth = $self->{dbh}->prepare($sql);

			$self->{root}->set_local_locale("C");
			$self->{dbh}->do($sql, undef, @values) or die "AF error " . __FILE__ . " line " . __LINE__ . ": execute error on $sql with parameters " . join(",", @values);	
			$self->{root}->restore_local_locale();

		} elsif ( $self->save_type() == 2 ) { # Jinak provedeme insert
			#Zjistime novou hodnotu primarniho klice
			$self->nextval();
			#Pripravime sql dotaz
			$sql = "INSERT INTO $self->{_definition}->{name} (";
			$sql .= join (", ", map { $_ = ( $_ =~ /^to$/i ) ? '"' . $_ . '"' : $_ } sort(keys(%{$self->{_definition}->{columns}})));
			$sql .= ") VALUES (";
			foreach $key (sort(keys(%{$self->{_definition}->{columns}}))) {
				$sql .= " ?,";
			}
			$sql =~ s/,$//;
			$sql .= ")";
			#Pripravime seznam hodnot, ktere predame dotazu
			foreach $key (sort(keys(%{$self->{_definition}->{columns}}))) {
				if ( $self->{_definition}->{columns}->{$key}->{type} == DB_DATE && $self->{$key}) {
					my $value = $self->{$key}->datetime();
					push(@values,  $value);
				} else {
					my $value = $self->{$key};
					push(@values,  $value);
				}
			}
			$self->{root}->set_local_locale("C");
			if ( ! $self->{dbh}->do($sql, undef, @values) ) {
				for ( my $i = 0; $i < scalar(@values); $i++ ) {
					$values[$i] = defined($values[$i]) ? $values[$i] : "undef";
				}
				die "AF error " . __FILE__ . " line " . __LINE__ . ": execute error on $sql with parameters " . join(",", @values);	
			}
			$self->{root}->restore_local_locale();
		}
		#Ukladame data do memcached, je-li to povoleno
		$self->savetocache();	
	}
}
#}}}
#{{{ settocache
=head2 settocache()

Save data to memcached server

Method has no parameters

=cut
sub savetocache {
	my ($self) = @_;
	use vars qw($memcached_error);

	if ( $self->root()->memd() && $self->is_primary_values() ) {
		#Prepare list of values needed by to save by memcache
		my $values = {};
		foreach my $key (sort(keys(%{$self->{_definition}->{columns}}))) {
			my $value;
			if ( $self->{_definition}->{columns}->{$key}->{type} == DB_DATE && defined($self->{$key}) && ref($self->{$key}) eq "Time::Piece" ) {
				$value = $self->{$key}->datetime;
			} elsif ( $self->{_definition}->{columns}->{$key}->{type} == DB_DATETIMETZ && defined($self->{$key})) {
				$value = $self->{$key}->datetime;
			} else {
				$value = $self->{$key};
			}
			$values->{$key} = $value;
		}
		#Prepare key for memcached
		my $key = $self->{_definition}->{name} . join('|',@{$self->primary_values()});

		$self->{root}->set_local_locale("C");
		my $retval = $self->root()->memd()->set($key, $values, $self->definition()->{ttl});
		$self->{root}->restore_local_locale();

		if ( $retval == 0 && ! $memcached_error) {
			$memcached_error = 1;
			print(STDERR "AF warning " . __FILE__ . " line " . __LINE__ . " Error write data to memcached server.\n");	
		}
	}
}
#}}}
#{{{ nextval
#Pro primarni klic vygeneruje hodnotu ze sekvence
sub nextval {
	my ($self) = @_;
	my ($sql);
	#Najdeme primarni klic a pokud ma sekvenci tak generujeme klic
	if ( $self->save_type() == 2 ) {
		my $primary_key = $self->primary_key();
		if ( 
			$primary_key && 
			$self->{_definition}->{columns}->{$primary_key}->{sequence}
		) {
			$sql = "SELECT nextval(?) as id";
			#Je zapnute debugovani tak vypisujeme parametry a sql dotaz
			my $sth = $self->{dbh}->prepare($sql);
			$self->{root}->set_local_locale("C");
			$sth->execute( $self->{_definition}->{columns}->{$primary_key}->{sequence} ) or die "AF error " . __FILE__ . " line " . __LINE__ . ": $!";
			$self->{root}->restore_local_locale();
			if (my $row = $sth->fetchrow_hashref() ) {
				#Ulozime novou hodnotu ze sequence jako hodnotu primarniho klice
				$self->{$primary_key} = $row->{id};
			}
			$sth->finish();
		}
	} else {
		die "AF error " . __FILE__ . " line " . __LINE__ . ": You set nextval only on simple primary-key is defined.";
	}
}
#}}}
#{{{ primary_key
#Vraci primarnich klicu
sub primary_key {
	my ($self) = @_;

	foreach my $key (sort(keys(%{$self->{_definition}->{columns}}))) {
		if ( $self->{_definition}->{columns}->{$key}->{primary_key}) {
			return($key);
		}
	}
	return(undef);
}
#}}}
#{{{ primary_keys
#Vraci primarnich klicu
sub primary_keys {
	my ($self) = @_;
	if ( ! defined($self->{_primary_keys}) ) {
		$self->{_primary_keys} = [];
		foreach my $key (sort(keys(%{$self->{_definition}->{columns}}))) {
			if ( $self->{_definition}->{columns}->{$key}->{primary_key}) {
				push(@{$self->{_primary_keys}}, $key);
			}
		}
	}

	return($self->{_primary_keys});
}
#}}}
#{{{ primary_defined
#Vraci zda je definovan jednoduchy klic
sub primary_defined {
	my ($self) = @_;
	my $retval = 1;

	if ( scalar( @{$self->primary_keys()} ) ) { 
		foreach my $key (@{$self->primary_keys()}) {
			if ( !defined( $self->{$key} ) ) {
				$retval = 0;
			}
		}
	} else {
		$retval = 0;
	}

	return($retval);
}
#}}}
#{{{ primary_where
#Vraci podminku where
sub primary_where {
	my ($self) = @_;
	if ( ! defined($self->{primary_where}) ) {
		my @primary_where = ();
		foreach my $key (@{$self->primary_keys()}) {
			push(@primary_where, "$key = ?");
		}
		$self->{primary_where} = join(" AND ", @primary_where);
	}
	return($self->{primary_where});
}
#}}}
#{{{ primary_values
#Vraci hodnoty primarniho klice 
sub primary_values {
	my ($self) = @_;
	if ( ! defined($self->{primary_values}) ) {
		$self->{primary_values} = [];
		foreach my $key (@{$self->primary_keys()}) {
			my $value = $self->{$key};
			push(@{$self->{primary_values}},  $value);
		}
	}
	return($self->{primary_values});
}
#}}}
#{{{ save_type
#Vrací jakým způsobem se má ukládat na základe primárního klíče, jestli to je update  nebo insert
sub save_type {
	my ($self) = @_;
	my ($sql, $sth, $row,$retval, $key);
	my @primary_keys = @{$self->primary_keys()};
	if ( scalar(@primary_keys) == 0 ) {#Neni definovany primarni klic => s tim nejde vubec pracovat
		$self->die("Cafe::Class::save_type",  "Save record without PRIMARY KEY definition is not possible", __LINE__);
	} elsif ( scalar(@primary_keys) == 1 ) {#Jednoduchy primarni klic jednoducha varianta
		$key = $self->primary_keys()->[0];

		my $sequence = exists($self->definition->{columns}->{$key}->{sequence});
		if ( ! defined($self->{$key}) && $sequence ) {
			#Pouze jeden klic a hodnote neni zadane hodnotu klice ziskame ze sequecne a provedem insert
			$retval = 2;
		} elsif ( ! defined($self->{$key}) && ! $sequence ) {
			#Pouze jeden klic a hodnota neni zadana chyba
			$self->die("Cafe::Class::save_type",  "If you want write record with simple primary key withou sequence column of primary key must by definded", __LINE__);
		} elsif ( defined($self->{$key}) &&  $sequence) {
			#Pouze jeden klic a hodnota je zadana a existuje sequnce -> delamu update
			$retval = 1;
		} elsif ( defined($self->{$key}) &&  !$sequence) {
			#Pouze jeden klic a hodnota je zadana a neexistuje sequnce -> zjistime jestli zaznam existuje
			#Zkontrolujeme jestli existuje zaznam se slozenym primarnim klicem v databazi
			$sql = "SELECT * FROM $self->{_definition}->{name} WHERE " . $self->primary_where();
			$sth = $self->{dbh}->prepare($sql);
			$self->{root}->set_local_locale("C");
			$sth->execute( @{$self->primary_values()} ) or die "AF error " . __FILE__ . " line " . __LINE__ . ": $_";
			$self->{root}->restore_local_locale();
			if ($row = $sth->fetchrow_hashref() ) {#Zaznam je v databazi budeme provadet update 
				$retval = 1;
			} else { #Zaznam neni v databazi provedeme insert
				$retval = 2;
			}
			$sth->finish();
		}
		return($retval);
	} elsif ( scalar(@primary_keys) > 1 ) { #Slozeny primarni klic
		#Kontrola, ze jsou vyplneny vsechny sloupce primarniho klice
		foreach $key (@{$self->primary_keys()}) {
			$self->die("Cafe::Class::save_type", "If you want write record with not-simple primary key every columns of primary key must by definded", __LINE__) if ( ! defined($self->{$key}) );
		}
		#Zkontrolujeme jestli existuje zaznam se slozenym primarnim klicem v databazi
		$sql = "SELECT * FROM $self->{_definition}->{name} WHERE " . $self->primary_where();
		#Je zapnute debugovani tak vypisujeme parametry a sql dotaz
		$sth = $self->{dbh}->prepare($sql);
		$self->{root}->set_local_locale("C");
		$sth->execute( @{$self->primary_values()} ) or die "AF error " . __FILE__ . " line " . __LINE__ . ": $_";
		$self->{root}->restore_local_locale();
		if ($row = $sth->fetchrow_hashref() ) {#Zaznam je v databazi budeme provadet update 
			$retval = 1;
		} else { #Zaznam neni v databazi provedeme insert
			$retval = 2;
		}
		$sth->finish();
		return($retval);
	}
}
#}}}
#{{{ rules
=head2 rules

Check each value from content by _definition hash from class. Values with 
keys not defined in _definition is ignored.

Parameter $content is contains values to check and parse. If $content is not
defined method try load content from HTTP request byt Apache2::Request class.

=cut
sub rules {
	my ($self, $content, $unlocalized) = @_;
	my ($key);

	$content = [%{$self->{root}->{request}->param()}] if ( ! $content && $self->{root}->{request} && $self->{root}->{request}->param() ) ;

	foreach $key ( @{$self->primary_keys()} ) {
		if ( $self->definition->{columns}->{$key}->{rule} ) {
			$content->{$key} = Encode::decode("utf-8", $content->{$key});
			$self->parseproperty($content->{$key}, $key, $unlocalized);
		}
	}

	if ( $self->primary_defined() && $self->okay ) {
		#Kdyz se upravuje na zaklade ulozeneho zaznamu tak ho nejdriv nacti
		$self->load(1);
	}

	#Projdeme vsechny vlastnosti tridy a kdyz se ma 
	#dana vlastnost kontrolvat (definice rule) a existuje
	#tak provedeme kontrolu
	foreach $key (sort(keys(%{$self->{_definition}->{columns}}))) {
		if ( 
			$self->{_definition}->{columns}->{$key}->{rule} && exists($content->{$key})
		) {
			$content->{$key} = Encode::decode("utf-8", $content->{$key});
			$self->parseproperty($content->{$key}, $key, $unlocalized);
		}
	}

	#If state have set bit no.2 (2^2) record will be mark se deleted
	if ( $content->{state} && ( ($content->{state} & 4) == 4 ) ) {
		$self->delete();
	}
	return($self->okay);
}
#}}}
#{{{ parseproperty
=head2 parseproperty

Check and parse value from outside of application. If value is not valid set msgid.
If value is valid save the value to property with $destination key. All parameter
to use form checking and parsing is stored in _definition hash.

=cut
sub parseproperty {
	my ($self, $value, $destination, $unlocalized) = @_;
	my $column = $self->{_definition}->{columns}->{$destination}; 
	my $orig = $value;
	$column->{ok} = 1;

	if ( ( ! defined($value) || $value eq "") ) {
		if ( $column->{null} ==  DB_NULL ) {
			#If null allowed and property is null
			$value = undef;
		} else {
			#else fire error message
			$self->root->set_local_locale();
			$column->{message} = sprintf($self->root->getstring('Field "%s" cannot be left blank'), $self->root->getstring($column->{label}));
			$self->root->restore_local_locale();
			$column->{ok} = 0;
		}
	} else {
		if ( $column->{type} == DB_VARCHAR || $column->{type} == DB_FULLTEXT ) {
			# Now we will get internal server error instead of wrong behavior
			$self->die("Cafe::Class::parseproperty", "You have to define opts value when using DB_VARCHAR type!", __LINE__) if ( ! defined($column->{opts}) );
			#Check varchar values. If length of varchar value has zero AF consider value for NULL
			$column->{ok} = 0 if ( length($value) > $column->{opts} || ( length($value) == 0 && $column->{null} !=  DB_NULL ) );
			$column->{changed}= 1 if ( 
				( ! defined( $column->{$destination} ) && defined($value) ) ||
				( defined( $column->{$destination} ) && ! defined($value) ) ||
				( defined( $column->{$destination} ) && defined($value) && ! $column->{$destination} eq $value )
			);
		} elsif ( $column->{type} == DB_FMTCHAR ) {
			#Check varchar values
			$column->{ok} = 0 if ( ! $value =~ /$column->{opts}/ );
			$column->{changed}= 1 if ( 
				( ! defined( $column->{$destination} ) && defined($value) ) ||
				( defined( $column->{$destination} ) && ! defined($value) ) ||
				( defined( $column->{$destination} ) && defined($value) && ! $column->{$destination} eq $value )
			);
		} elsif ( ( $column->{type} == DB_INT || $column->{type} == DB_INT8 ) ) {
			#Check integer values
			if ( ($value =~ /^\s*(-{0,1}\d+)\s*$/) ) {
				$value = $1;
			} else {
				$column->{ok} = 0
			}
			$column->{changed}= 1 if ( 
				( ! defined( $column->{$destination} ) && defined($value) ) ||
				( defined( $column->{$destination} ) && ! defined($value) ) ||
				( defined( $column->{$destination} ) && defined($value) && $column->{$destination} != $value )
			);
		} elsif ( $column->{type} == DB_DATE ) {
			#Check datetime values
			$self->{root}->set_local_locale() if ( ! $unlocalized);
			$value = Time::Piece->strptime("$value", "%x");
			$column->{ok} = 0 if ( $@ );
			$self->{root}->restore_local_locale() if (! $unlocalized);
			$column->{changed}= 1 if ( 
				( ! defined( $column->{$destination} ) && defined($value) ) ||
				( defined( $column->{$destination} ) && ! defined($value) ) ||
				( defined( $column->{$destination} ) && defined($value) && $column->{$destination} != $value )
			);
		} elsif ( $column->{type} == DB_DATETIMETZ) {
			#Check datetime values
			$self->{root}->set_local_locale() if ( ! $unlocalized);
			eval { $value = Time::Piece->strptime("$value", "%F %T%z"); }; #2008-08-11 13:32:00+0200
			$column->{ok} = 0 if ( $@ );
			$self->{root}->restore_local_locale() if (! $unlocalized);
			$column->{changed}= 1 if ( 
				( ! defined( $column->{$destination} ) && defined($value) ) ||
				( defined( $column->{$destination} ) && ! defined($value) ) ||
				( defined( $column->{$destination} ) && defined($value) && $column->{$destination} != $value )
			);
		} elsif ( $column->{type} == DB_NUMERIC && defined($value)) {
			#Check numeric values
			$self->{root}->set_local_locale() if ( ! $unlocalized);
			my $lconv = POSIX::localeconv();
			$value =~ s/ //g;
			if ( $lconv->{decimal_point} && ! ( $lconv->{decimal_point} eq '.' ) ) {
				$value =~ s/\./$lconv->{decimal_point}/g;
			}
			my ($num, $n_unparsed) = POSIX::strtod($value);
			$self->{root}->restore_local_locale() if (! $unlocalized);

			if ( $value eq '' && $n_unparsed != 0 ) {
				$column->{ok} = 0;
			} else {
				$value = $num;
			}
			$column->{changed}= 1 if ( 
				( ! defined( $column->{$destination} ) && defined($value) ) ||
				( defined( $column->{$destination} ) && ! defined($value) ) ||
				( defined( $column->{$destination} ) && defined($value) && $column->{$destination} != $value )
			);
		}

		if ( ! $column->{ok} ) {
			$self->{root}->set_local_locale();
			$column->{message} = sprintf($self->root->getstring('Field "%s" is missing'), $self->root->getstring($column->{label}));
			$self->{root}->restore_local_locale();
		}
	}

	if ( $column->{ok} ) { 
		$self->{$destination} = $value;
	} else {
		$self->{$destination} = $orig;

		$self->message($column->{message}, NOTRANSLATE);
		$self->okay($column->{ok}) if ( ! $self->okay );
	}

	#Save value to session if session memory is enabled
	if ( $column->{default_session} ) {
		$self->{root}->{session}->{ref($self)} = {} if ( ! defined($self->{root}->{session}->{ref($self)}) );

		if ( $column->{type} == DB_DATE && ref($self->{$destination}) eq "Time::Piece") {
			$self->{root}->{session}->{ref($self)}->{$destination} = $self->{$destination}->epoch();
		} else {
			$self->{root}->{session}->{ref($self)}->{$destination} = $self->{$destination};
		}
	}

	return($column->{ok});
}
#}}}
#{{{ rulekey
#V metode GET z prohlizece hleda 
#primarni klic a v pripade uspechu
#ho ulozi do vlastnosti primarniho klice
sub rulekey {
	my ( $self, $content ) = @_;
	if ( ! $content && $self->{root}->{request} && $self->{root}->{request}->param() ) {
		my %content = %{$self->{root}->{request}->param()};
		$content = \%content;
	}
	foreach my $key (@{$self->primary_keys()}) {
		$self->parseproperty($content->{$key}, $key);
	}
	return(! $self->{msgid});
}
#}}}
#{{{ to_time_piece
=head2 to_time_piece

Convert string with date in %Y-%m-%d %H:%M:%S
format to instance of Time::Piece class.

=head4 Parameters

=over

=item $value

input string with date and time

=back 

=cut 
sub to_time_piece {
	my ( $self, $value ) = @_;

	$value = $self->{root}->to_time_piece($value);

	return($value);
}
#}}}
#{{{ dump
sub dump {
	my ($self, @params) = @_;
	if (scalar(@params))  {
		$self->{root}->dump(@params);
	} else {
		$self->{root}->dump($self->gethash(1));
	}
}
#}}}
#{{{ delete
#Oznaci zaznam jako smazaný
sub delete {
	my ($self) = @_;
	if ( exists( $self->{_definition}->{columns}->{state} ) ) {
		$self->{state} = $self->{state} | 4;
		$self->save();
	} else {
		$self->die("Cafe::Class::delete", "For mask as deleted you need state column defined", __LINE__);
	}
}
#}}}
#{{{ is_deleted
sub is_deleted {
	my ($self) = @_;
	
	if ( ($self->{state} & 4) == 4 ) {
		return(1);
	} else {
		return(0);
	}
}
#}}}
#{{{ gethash
=head2 gethash

Returns formated values by hash based on definition of columns

=cut
sub gethash() {
	my ($self, $unlocalized) = @_;
	my $data = {};

	foreach my $key (sort(keys(%{$self->{_definition}->{columns}}))) {
		if ( $self->{$key} && $self->{_definition}->{columns}->{$key}->{type} == DB_DATE ) {
			if (! $unlocalized) {
				$self->{root}->set_local_locale();
			}
			$data->{$key} = defined($data->{$key}) ? $self->{$key}->strftime("%x") : undef;
			if (! $unlocalized) {
				$self->{root}->restore_local_locale();
			}
		} elsif ( $self->{$key} && $self->{_definition}->{columns}->{$key}->{type} == DB_NUMERIC ) {
			if (! $unlocalized) {
				$self->{root}->set_local_locale();
			}
			if ( exists($self->{_definition}->{columns}->{$key}->{format}) ) {
				$data->{$key} = sprintf("$self->{_definition}->{columns}->{$key}->{format}", $self->{$key});
			} else {
				$data->{$key} = sprintf("%.2f", $self->{$key});
			}
			if (! $unlocalized) {
				$self->{root}->restore_local_locale();
			}
		} elsif ( defined($self->{$key}) )  {
			$data->{$key} = "$self->{$key}";
		} else {
			$data->{$key} = undef;
		}
	}

	foreach my $key (sort(keys(%{$self->{_definition}->{autoloaders}}))) {
		if ( exists( $self->{_definition}->{autoloaders}->{$key}->{show} ) ) {
			eval(qq(\$data->{$key} = \$self->$key()->$self->{_definition}->{autoloaders}->{$key}->{show}));
			
		}
	}

	$data->{message} = $self->message;
	$data->{okay} = $self->okay;
	$data->{stateusername} = $self->state_username;
	$data->{state_username} = $self->state_username;
	$data->{global} = {}; 
	$data->{global}->{message} = $self->root->message; 

	return($data);
}
#}}}
#{{{ state_username
=head2 state_username

Return name of user

=cut
sub state_username {
	my ($self) = @_;
	if ( $self->state_user() ) {
		return($self->state_user()->signature() ? $self->state_user()->signature() : $self->state_user()->username());
	}
}
#}}}
#{{{ state_user
=head2 state_user

Return instance of user information class defined in apache configuration file

=cut
sub state_user {
	my ($self) = @_;
	if ( ! $self->{_state_user} && $self->{stateuser} && $self->{_definition}->{columns}->{stateuser} ) {
		#Load user class
		eval("require " . $self->{root}->dir_config("class_user")) or die "AF error " . __FILE__ . " line " . __LINE__ . ": $!";
		eval('$self->{_state_user} = new ' . $self->{root}->dir_config("class_user") . '($self->{root}, $self, $self->{stateuser});') or die "AF error " . __FILE__ . " line " . __LINE__ . ": $@";
	}
	return($self->{_state_user});
}
#}}}
#{{{session
=head2  session

Return reference to session information for class

=cut
sub session {
	my ($self) = @_;
	#Aby se zapsala do session po zmenach z command
	if ( ! defined($self->{root}->{session}->{ref($self)}) ) {
		$self->{root}->{session}->{ref($self)} = {};
	}
	return($self->{root}->{session}->{ref($self)});
}
#}}}
#{{{AUTOLOAD
=head2 Method AUTOLOAD

Autoloader to handle columns and autoloaders 
from _definition

=cut 
sub AUTOLOAD {
	my $self = shift;
	my $param = shift;
	my $name = our $AUTOLOAD;

	if ( ! ref( $self ) ) {
		$self->die("Cafe::Class::AUTLOADER", " $self is not object.", __LINE__);
	}
	
	#If not defined DESTROY method and this method is invocated finish method
	if ( $name =~ /::DESTROY$/ ) {
		return();
	}
	#Check and get method name
	if ( $name =~ /::([^:]+)$/ ) {
		my $method = $1;
		if ( exists($self->{_definition}->{columns}->{$method}) ) {
			#Set property if param is defined
			$self->{$method} = $param if ( defined($param) );
			#If is invocated method with name defined as column return value of this column
			return($self->{$method});
		} elsif ( exists($self->{_definition}->{autoloaders}->{$method} ) ) {
			#If is invocated method is defined as autoloader load method
			my $autoloader = $self->{_definition}->{autoloaders}->{$method};
			#Check shadow variable definition
			if ( ! exists($autoloader->{shadow}) )  { $autoloader->{shadow} = "_$method"; } 
			#Create instance 
			if ( (! defined($self->{$autoloader->{shadow}}))) {
				my $obj;
				eval("require $autoloader->{class}") or $self->die("Cafe::Class::AUTLOADER", "$@", __LINE__);
				eval('$obj = new ' . $autoloader->{class} . '($self->{root}, $self);') or $self->die("Cafe::Class::AUTLOADER", "$@ (Creating class $autoloader->{class}", __LINE__);
				if ( exists($autoloader->{id}) &&  exists($autoloader->{ref}) ) {
					my @id = split(/,/, $autoloader->{id});
					my @ref = split(/,/, $autoloader->{ref});

					$self->die("Cafe::Class::AUTLOADER", "Definition for autoloader $method contains different keys for id and ref arrays.", __LINE__) if ( scalar(@id) != scalar(@ref) );

					for(my $i = 0; $i < scalar(@id); $i++)  {
						$id[$i] =~ s/^ //g;
						$ref[$i] =~ s/^ //g;
						$id[$i] =~ s/ $//g;
						$ref[$i] =~ s/ $//g;

						if ( $ref[$i] =~ /('[^']+'|\d+)/ ) {
							my $destination = '$obj->{$id[$i]}';
							my $source = $1;
							eval("$destination = $source") or $self->die("Cafe::Class::AUTLOADER", "bad AUTOLOAD assignment \$obj->{$id[$i]} = $1 with error : $!", __LINE__);
						} elsif ( $ref[$i] =~ /\$self->/ ) {
							my $destination = '$obj->{$id[$i]}';
							my $source = $ref[$i];
							eval("$destination = $source") or $self->die("Cafe::Class::AUTLOADER", "bad AUTOLOAD assignment \$obj->{$id[$i]} = \$self->{$ref[$i]} with error : $!", __LINE__);
						} else {
							$obj->{$id[$i]} = $self->{$ref[$i]};
						}


					}
				} elsif ( exists($autoloader->{id}) ) {
					foreach my $id (map { s/ //g; $_} split(/,/, $autoloader->{id})) {
						eval('$obj->{$id} = $self->{$id}');
					}
				}
				$obj->load();
				$self->{$autoloader->{shadow}} = $obj;
			}
			return($self->{$autoloader->{shadow}});
		} elsif ( ! ($method =~ "^_") && exists($self->{$method}) ) {
			return($self->{$method});
		} else {
			$self->die("Cafe::Class::AUTLOADER", " Method $name is not defined", __LINE__);
		}
	}
}
#}}}
#{{{now
=head2 Method now

Return Time::Piece actual time

=cut 
sub now {
	my ($self) = @_;
	my $now = localtime();
	return($now);
}
#}}}
#{{{is_primary_values
=head2 Method is_primary_values

Return 0 if not defined any primary value.

=cut 
sub is_primary_values {
	my ($self) = @_;
	my $is_def = 1;
	foreach my $value (@{$self->primary_values()}) {
		if ( ! defined($value) ) { $is_def = 0; }
	}
	return($is_def);
}
#}}}
#{{{columns
=head2 Method columns

Return array of columns from definitions sorted by 
index parameter in column items

=cut 
sub columns {
	my ($self) = @_;
	my @columns;
	foreach my $key (keys(%{$self->definition->{columns}})) {
		if ( defined($self->definition->{columns}->{$key}->{position}) ) {
			$self->definition->{columns}->{$key}->{key} = $key;
			push(@columns, $self->definition->{columns}->{$key});		
		}
	}
	foreach my $key (keys(%{$self->definition->{autoloaders}})) {
		if ( defined($self->definition->{autoloaders}->{$key}->{position}) ) {
			$self->definition->{autoloaders}->{$key}->{key} = $key;
			push(@columns, $self->definition->{autoloaders}->{$key});		
		}
	}
	@columns = sort { $a->{position} <=> $b->{position} } @columns;
	return(\@columns);
}
#}}}
#{{{identifier
=head2 Method identifier

Return string identify class

=cut 
sub identifier {
	my ($self, $identifier) = @_;
	$self->{_identifier} = $identifier if ( $identifier );
	if ( ! defined($self->{_identifier}) ) {
		if ( ref($self) =~ /([a-zA-Z_]+)$/ ) {
			$self->{_identifier} = lc($1);
		}
		$self->{_identifier} = join("_", $self->{_identifier}, grep( defined($_), @{$self->primary_values()} ) ) if ( scalar( grep( defined($_), @{$self->primary_values()}) ) );
	}
	return($self->{_identifier});
}
#}}}
#{{{get_index
=head2 get_index
	return object index in Listing::list array
=cut
sub get_index {
	my ($self) = @_;
	
	my $index = 0;
	foreach my $obj(@{$self->{parent}->{list}}) {
		if ( $obj == $self ) {
			return $index;
		}
		$index++;
	}
}
#}}}
#{{{status_is
=head2 status_is
	return status containing value
=cut
sub status_is {
	my ($self, $value, $column) = @_;
	if ( ! $column ) {
		$column = $self->{status};
	}
	return ( (($column + 0) & $value) == $value);
}
#}}}
#{{{status_add
=head2 status_add
	adding selected bit into status
=cut
sub status_add {
	my ($self, $value, $column) = @_;
	if ( ! $column ) {
		$column = 'status';
	}
	$self->{$column} = $self->{$column} | $value;
}
#}}}
#{{{status_remove
=head2 status_remove
	removing selected bit from status
=cut
sub status_remove {
	my ($self, $value, $column) = @_;
	if ( ! $column ) {
		$column = 'status';
	}
	$self->{$column} = $self->{$column} & ~$value;
}
#}}}
#{{{loaded
=head2 loaded
	return status of load ( if record not loaded from persitent area  return undef else return <> 0)
=cut
sub loaded {
	my ($self) = @_;
	return($self->{_loaded});
}
#}}}
#{{{okay
=head2 okay
	return status parameter parsing
=cut
sub okay {
	my ($self, $ok) = @_;
	$self->{_ok} = $ok if ( defined($ok) );
	return($self->{_ok});
}
#}}}
#{{{message
=head2 message
	get/set global/local message of instance
=cut
sub message {
	my ($self, $message, $notranslate) = @_;
	if ( defined($message) ) {
		if ( $notranslate ) {
			$self->{_message} = $message;
		} else {
			$self->root->set_local_locale();
			$self->{_message} = $self->root->getstring($message);
			$self->root->restore_local_locale();
		}
		$self->root->message($message, $notranslate);
	}
	return($self->{_message});
}
#}}}

1;
