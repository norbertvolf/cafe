package Mojolicious::Cafe::Base;

use Mojo::Base -base;
use Validation::Class::Simple;
use DateTime;
use Scalar::Util qw(weaken);

use constant {
	DB_VARCHAR => 0,
	DB_INT     => 1,
	DB_DATE    => 2,
	DB_NUMERIC => 3,
	DB_ARRAY   => 4,
	DB_INT8    => 6,
};

has loaded  => 0;
has okay    => 0;
has message => 0;
has changed => 0;    #If somenody change any attribute via getter/setter change to 1
has 'definition';
has 'c';

sub new {            #Create new instance of Cafe::Mojo::Class
	my $class = shift;
	my $c    = shift;
	my $def   = shift;
	my $self  = $class->SUPER::new();

	#Weaken reference to prevent memory leaks
	weaken($c);

	$self->c($c);

	#Add dbh from controller if not exists
	$def->{dbh} = $self->c->app->dbh if ( !exists( $def->{dbh} ) );

	#Set definition of instance if check of defintion is ok
	#Check end set definition die if there is some error
	$self->definition( $self->check($def) );

	#Set default values
	$self->defaults;

	#TODO Generate getters/setters from columns

	return ($self);
}

sub check {    #Check definiton, passed as paramaters
	my $self = shift;
	my $def  = shift;

	#Is $definition present
	Mojo::Exception->throw("Error in class " . ref($self). ". Definition is not pass as parameter.") if ( !defined($def) );
	Mojo::Exception->throw("Error in class " . ref($self). ". Columns definitions must be HASH.\n\n" . $self->c->app->dumper($def) )
	  if ( !( ref( $def->{columns} ) eq 'HASH' ) );

	for ( keys( %{ $def->{columns} } ) ) {
		Mojo::Exception->throw("Error in class " . ref($self). ". Column '$_' definitions must be HASH.\n\n" . $self->c->app->dumper( $def->{columns} ) )
		  if ( !( ref( $def->{columns}->{$_} ) eq 'HASH' ) );
	}

	return ($def);
}

sub columns {    #Return sorted (by pos) columns as array
	my $self = shift;
	my $def = scalar(@_) ? shift : $self->definition;
	my @columns =
	  sort { ( $a->{position} || 0 ) <=> ( $b->{position} || 0 ) }
	  map { $def->{columns}->{$_}->{key} = $_; $def->{columns}->{$_} } keys( %{ $def->{columns} } );
	return ( wantarray ? @columns : \@columns );
}

sub dbh {        #Return dbh from definition
	return ( shift->definition->{dbh} );
}

sub dump {       #Return string with dumped data
	my $self = shift;
	return (
		ref($self) . "::dump = \n{\n  " . join(
			"\n  ",
			map {
				eval { "$_ => " . ( $self->$_ // '' ) }
			  } map {
				$_->{key}
			  } $self->columns
		  )
		  . "\n};"
	);
}

sub hash {    #Returns formated values by hash based on definition of columns
	my $self = shift;
	my $data = {};

	foreach my $key ( sort( keys( %{ $self->definition->{columns} } ) ) ) {
		if ( $self->$key && $self->definition->{columns}->{$key}->{type} == DB_DATE ) {

			#Format datetime attributes
			my $pattern = $self->c->locale eq 'en_US.UTF-8' ? "\%m\/\%d\/\%Y" : "%x";
			$data->{$key} = defined( $self->$key ) ? $self->$key->strftime($pattern) : undef;
		} elsif ( $self->$key && $self->definition->{columns}->{$key}->{type} == DB_NUMERIC ) {

			#Format numeric attributes
			if ( exists( $self->definition->{columns}->{$key}->{format} ) ) {
				$data->{$key} = sprintf( "$self->definition->{columns}->{$key}->{format}", $self->$key );
			} else {
				$data->{$key} = sprintf( "%.2f", $self->$key );
			}
		} elsif ( defined( $self->$key ) ) {
			$data->{$key} = $self->$key;
		} else {
			$data->{$key} = undef;
		}
	}
	return ($data);
}

sub errors {    #Returns hash of errors
	my $self   = shift;
	my $errors = [];

	foreach my $key ( sort( keys( %{ $self->definition->{columns} } ) ) ) {
		if ( exists( $self->definition->{columns}->{$key}->{invalid} ) ) {
			push(
				@{$errors},
				{
					label => $self->definition->{columns}->{$key}->{label} // $key,
					error => $self->definition->{columns}->{$key}->{error}
					  // sprintf( $self->c->app->__('Invalid %s field'), $self->definition->{columns}->{$key}->{label} // $key ),
					key => $key,
				}
			);
		}
	}
	return ($errors);
}

sub validate {    #Return validate based on actual definition
	my $self    = shift;
	my $params  = shift;
	my $columns = $self->definition->{columns};
	my %params;
	my $errors = 0;

	$self->c->app->log->debug( "Validate input params for class " . ref($self) . "\n" . $self->c->app->dumper($params) );

	#Pass parameters to validator
	$self->validator->set_params_hash($params);
	foreach my $key ( keys( %{$params} ) ) {

		#Validate all simple columns with directive rule
		if (   exists( $columns->{$key} )
			&& ref( $columns->{$key} ) eq 'HASH'
			&& $columns->{$key}->{type} != DB_ARRAY
			&& $self->definition->{columns}->{$key}->{rule} )
		{
			if ( $self->validator->validate($key) ) {

				#Copy value to instance of class by setter
				if ( $columns->{$key}->{type} == DB_DATE ) {
					$self->$key( $self->func_parse_date( $params->{$key} ) );
				} elsif ( $columns->{$key}->{type} == DB_INT && defined( $params->{$key} ) ) {
					$self->$key( $params->{$key} + 0 );
				} elsif ( $columns->{$key}->{type} == DB_NUMERIC && defined( $params->{$key} ) ) {
					$self->$key( $params->{$key} + 0 );
				} else {
					$self->$key( $params->{$key} );
				}
			} else {

				#Set error value
				$columns->{$key}->{invalid} = 1;
				$errors++;
			}
		} elsif ( exists( $columns->{$key} )
			&& ref( $columns->{$key} ) eq 'HASH'
			&& $columns->{$key}->{type} == DB_ARRAY
			&& $self->definition->{columns}->{$key}->{rule} )
		{
			$self->$key( $params->{$key} );
		} elsif ( exists( $columns->{$key} ) && ref( $columns->{$key} ) eq 'HASH' && !$self->definition->{columns}->{$key}->{rule} ) {
			$self->c->app->log->debug(qq(You have tried validate key "$key" without rule parameter in definition !!!));
		}
	}

	return ( !$errors );
}

sub validator {    #Create, memoize and return validator for actual class
	my $self = shift;

	#Create validators
	my %fields;

	#Set up validators for simple type columns (ignory array type)
	my %columns =
	  map { $_ => $self->definition->{columns}->{$_} }
	  grep { $self->definition->{columns}->{$_}->{type} != DB_ARRAY } keys( %{ $self->definition->{columns} } );

	#Is validator memoized
	if ( !$self->c->app->validator( ref($self) ) ) {
		foreach my $key ( keys(%columns) ) {
			if ( $columns{$key}->{rule} ) {

				#Create validator from attributes where rule directive is true
				$fields{$key} = {};
				$columns{$key}->{filters} = 'trim' if ( !$columns{$key}->{filters} );
				if ( $columns{$key}->{type} == DB_DATE ) {
					$columns{$key}->{validation} = func_validate_date( $self->c->locale ) if ( !$columns{$key}->{validation} );
				} elsif ( $columns{$key}->{type} == DB_INT ) {
					$columns{$key}->{pattern} = qr/^\d+$/ if ( !$columns{$key}->{pattern} );
				} elsif ( $columns{$key}->{type} == DB_NUMERIC ) {
					$columns{$key}->{pattern} = qr/^[+-]{0,1}\d+[.,]{0,1}\d*$/ if ( !$columns{$key}->{pattern} );
				}

				#Copy permitted directives to Validatioin::Class definition
				foreach my $directive ( 'pattern', 'required', 'label', 'error', 'errors', 'validation', 'max_length', 'filters' ) {
					$fields{$key}->{$directive} = $columns{$key}->{$directive} if ( defined( $columns{$key}->{$directive} ) );
				}
			}
		}
		$self->c->app->validator( ref($self), Validation::Class::Simple->new( fields => \%fields ) );
	}
	return ( $self->c->app->validator( ref($self) ) );
}

sub AUTOLOAD {    #Default method to handle columns and autoloaders from definition
	my $self = shift;

	#Dig number or parameters
	my $numofprm = scalar(@_);
	my $param    = shift;
	my $method   = our $AUTOLOAD;

	Mojo::Exception->throw("Mojolicious::Cafe::Class::AUTLOADER") if ( !ref($self) );

	#If not defined DESTROY method and this method is invocated finish method
	return if ( $method =~ /::DESTROY$/ );

	#Check and run method
	if ( $method =~ /::([^:]+)$/ ) {
		my $method = $1;
		if ( exists( $self->definition->{columns}->{$method} ) ) {

			#Set property if param is defined
			if (
				$numofprm
				&& (   ( defined( $self->{"_$method"} ) && !defined($param) )
					|| ( !defined( $self->{"_$method"} ) && defined($param) )
					|| ( defined( $self->{"_$method"} ) && defined($param) && !( $self->{"_$method"} eq $param ) ) )
			  )
			{
				$self->{"_$method"} = $param;
				$self->changed(1);
			}

			#If is invocated method with name defined as column return value of this column
			return ( $self->{"_$method"} );
		} elsif ( exists( $self->definition->{autoloaders}->{$method} ) ) {

			#If is invocated method is defined as autoloader load method
			my $autoloader = $self->definition->{autoloaders}->{$method};

			#Create instance
			if ( !defined( $self->{"_$autoloader"} ) ) {
				my $obj;

				#Prepare destination class
				eval("require $autoloader->{class}");
				Mojo::Exception->throw("Cafe::Class::AUTLOADER: $@") if ($@);
				eval( '$obj = new ' . $autoloader->{class} . '($self->c);' );
				Mojo::Exception->throw("Cafe::Class::AUTLOADER: $@") if ($@);
				if ( exists( $autoloader->{params} ) && ref( $autoloader->{params} ) eq 'HASH' ) {
					foreach my $key ( keys( %{ $autoloader->{params} } ) ) {

						#Clean up destination property name
						$key =~ s/^\s*(\w+)\s*$/$1/;

						#Set param value as value or as value returned from anonymous
						#function passed as param (anonymous function can return
						#anything what you want
						if ( ref( $autoloader->{params}->{$key} ) eq 'CODE' ) {
							eval("\$obj->$key(&{\$autoloader->{params}->{\$key}}(\$self));");
							Mojo::Exception->throw("Cafe::Class::AUTLOADER: $@") if ($@);
						} else {
							my $method = $autoloader->{params}->{$key};
							eval { $obj->$key( $self->$method ); };
							Mojo::Exception->throw("Cafe::Class::AUTLOADER: $@") if ($@);
						}
					}
				}
				$obj->load();
				$self->{"_$autoloader"} = $obj;
			}
			return ( $self->{"_$autoloader"} );
		} else {
			Mojo::Exception->throw( "Method $method is not defined.\n" . $self->c->app->caller );
		}
	}
}

#Protected methods

sub defaults {    #Set default columns values
	my $self = shift;

	#Set default values
	foreach my $col ( $self->columns ) {
		eval("\$self->$col->{key}(\$col->{default});") if ( exists( $col->{default} ) );
	}
}

sub func_validate_date {    #Return function to validate date
	my $locale = shift;
	my $retval = sub {
		my ( $self, $this_field, $all_params ) = @_;
		my $year;
		my $month;
		my $day;

		if ( $this_field->{value} =~ m!^((?:19|20)\d\d)[- /.]([1-9]|0[1-9]|1[012])[- /.]([1-9]|0[1-9]|[12][0-9]|3[01])! ) {
			$year  = $1;
			$month = $2;
			$day   = $3;
		} elsif ( $locale eq 'en_US.UTF-8'
			&& $this_field->{value} =~ m!^([1-9]|0[1-9]|1[012])[- /.]{0,1}([1-9]|0[1-9]|[12][0-9]|3[01])[- /.]{0,1}((?:19|20)\d\d)! )
		{
			$year  = $3;
			$month = $1;
			$day   = $2;
		} elsif ( $this_field->{value} =~ m!^([1-9]|0[1-9]|[12][0-9]|3[01])[- /.]{0,1}([1-9]|0[1-9]|1[012])[- /.]{0,1}((?:19|20)\d\d)! ) {
			$year  = $3;
			$month = $2;
			$day   = $1;
		}
		if ($year) {

			# At this point, $1 holds the year, $2 the month and $3 the day of the date entered
			if ( $day == 31 and ( $month == 4 or $month == 6 or $month == 9 or $month == 11 ) ) {
				return 0;    # 31st of a month with 30 days
			} elsif ( $day >= 30 and $month == 2 ) {
				return 0;    # February 30th or 31st
			} elsif ( $month == 2 and $day == 29 and not( $year % 4 == 0 and ( $year % 100 != 0 or $year % 400 == 0 ) ) ) {
				return 0;    # February 29th outside a leap year
			} else {
				return 1;    # Valid date
			}
		} else {
			return 0;        # Not a date
		}
	};
	return ($retval);
}

sub func_parse_date {        #Return datetime
	my $self  = shift;
	my $value = shift;
	my $date;
	if ( $value =~ m!^((?:19|20)\d\d)[- /.]([1-9]|0[1-9]|1[012])[- /.]([1-9]|0[1-9]|[12][0-9]|3[01])! ) {
		$date = DateTime->new(
			year   => $1,
			month  => $2,
			day    => $3,
			locale => $self->c->locale,
		);
	} elsif ( $self->c->locale eq 'en_US.UTF-8'
		&& $value =~ m!^([1-9]|0[1-9]|1[012])[- /.]{0,1}([1-9]|0[1-9]|[12][0-9]|3[01])[- /.]{0,1}((?:19|20)\d\d)! )
	{
		$date = DateTime->new(
			year   => $3,
			month  => $1,
			day    => $2,
			locale => $self->c->locale,
		);
	} elsif ( $value =~ m!^([1-9]|0[1-9]|[12][0-9]|3[01])[- /.]([1-9]|0[1-9]|1[012])[- /.]((?:19|20)\d\d)! ) {
		$date = DateTime->new(
			year   => $3,
			month  => $2,
			day    => $1,
			locale => $self->c->locale,
		);
	} elsif ( !defined($value) || $value eq '' ) {
		$date = undef;
	} else {
		Mojo::Exception->throw("Bad date format");
	}

	return ($date);
}

sub func_parse_pg_date {    #Return datetime
	my $self  = shift;
	my $value = shift;
	my $date;
	if ( $value && $value =~ /(\d{4})-(\d{2})-(\d{2})[ T](\d{2}):(\d{2}):(\d{2})(?:\.\d+|)([+-]\d{2})/ ) {
		$date = DateTime->new(
			year      => $1,
			month     => $2,
			day       => $3,
			hour      => $4,
			minute    => $5,
			second    => $6,
			locale    => $self->c->locale,
			time_zone => $7 . "00",
		);
	} elsif ( $value && $value =~ /(\d{4})-(\d{2})-(\d{2})/ ) {
		$date = DateTime->new(
			year   => $1,
			month  => $2,
			day    => $3,
			locale => $self->c->locale,
		);
	} elsif ( !defined($value) || $value eq '' ) {
		$date = undef;
	} else {
		Mojo::Exception->throw("Bad postgresql date format");
	}
	return ($date);
}

sub func_validate_array {    #Validate array passed as parameter
	my $retval = sub {
		my ( $self, $this_field, $all_params ) = @_;

		if ( ref( $this_field->{value} ) eq 'ARRAY' ) {
			return (1);
		} else {
			return 0;        # Not a array
		}
	};
	return ($retval);
}

1;

__END__
{{{ POD
=head1 NAME

Mojolicious::Cafe::Base - base class to build Postgresql Web applications

=head1 AUTOLOADERS DIRECTIVES

Autoloaders means automatically created method which return instances of 
classes defined via autoloaders direcvtive. 

=head2 autoloaders

Contanin hash of hashes with autoloader definition. Key of child hash is
the name of the autoloader (method).

	autoloaders => {
		territories => {
			class => "Chain::Territory::Active",
		},
		langs => {
			class => "Cms::Banner::Lang::List",
			params => {
				idbanner => 'idbanner',
			},
		},
		test => {
			class => 'Test::Item',
			params => {,
				iduser => sub { my $self = shift; return $self->iduser; },',
			},
		},

	},

=head2 class

Name of class for instancing.

=head2 params

Hash of parameters. Key is attribute from instance of class defined
in C<class> parameter. Values is name of attribute from actual instance or
value is anonymous function which return required value.

=head1 COLUMN DIRECTIVES

Directives originally from Mojolicious::Cafe

=head2 type

Type of attribute si constant defined as method in Mojolicious::Cafe::Controller

=over

=item DB_INT - integer

=item DB_NUMERIC - numeric fixed-length value

=item DB_VARCHAR - character values

=item DB_DATE - date value as instance of DateTime

=back

C<type =E<gt> $app->DB_INT>

=head2 primary_key

Define primary_key. The primary_key must be defined to save record.

C<primary_key =E<gt> 1>

=head2 sequence

Sequence is name of sequence to fetch new identifier from databbase 
sequence.

C<sequence =E<gt> 'cms.idbanner' >

=head2 rule

If rule is defined and true attribute is validated and passwd to instance.

C<rule =E<gt> 1>

=head2 default

Default value passed to attribute.

C<default =E<gt> 'Default Value'>

=head2 position

Method columns returns array sorted by the position parameters.

C<position =E<gt> 1>

=head2 required

Define if undef is permitted for attribute.  Label directive is 
inherited from Validation::Class. See the Validation::Class
documentation.

C<required =E<gt> 1>

C<required =E<gt> 0>

Directives below are inherited from Validation::Class. Directives below are 
passed to Validation::Class only.

=head2 label

B<label> directive is inherited from Validation::Class. See the Validation::Class
documentation.

C<label =E<gt> 'User Password'>

=head2 error/errors

B<error> directive is inherited from Validation::Class. See the Validation::Class
documentation.

C<error =E<gt> 'Password invalid.'>

=head2 validation

B<validation> directive is inherited from Validation::Class. See the Validation::Class
documentation.

C<validation =E<gt> sub { my ($self, $field, $other) = @_; return $field-E<gt>{value} eq 'pass' ? 1 : 0; }>


=head2 max_length

B<max_length> directive is inherited from Validation::Class. See the Validation::Class
documentation.

C<max_length =E<gt> 10>

=head2 pattern

B<pattern> directive is inherited from Validation::Class. See the Validation::Class
documentation.

C<max_length =E<gt> 10>

=head1 METHODS

=head2 dump

B<dump> Return string with dumped data, usable for testing.

C<my $json = $banner->dump>

=cut
}}}
