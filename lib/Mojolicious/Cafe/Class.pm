package Mojolicious::Cafe::Class;

use Mojo::Base 'Mojolicious::Cafe::Base';

sub new {    #Create new instance of Cafe::Mojo::Class
	my $class      = shift;
	my $c          = shift;
	my $definition = shift;
	my $self       = $class->SUPER::new( $c, $definition );
	return ($self);
}

sub check {    #Check definiton, passed as paramaters
	my $self = shift;
	my $def  = shift;

	#Exists primary key
	Mojo::Exception->throw( "Not defined primary key." . $self->c->app->caller )
	  if ( !scalar( grep { defined( $_->{primary_key} ) && $_->{primary_key} == 1 } $self->columns($def) ) );

	#Exists entity key
	Mojo::Exception->throw("Not defined entity.") if ( !exists( $def->{entity} ) || !defined( $def->{entity} ) );

	#You cant use column named as hash, because there is method named 'hash'
	Mojo::Exception->throw("You cant use column named as hash, because there is method named 'hash'")
	  if ( exists( $def->{columns}->{hash} ) );

	$self->SUPER::check($def);

	return ($def);
}

sub load {    #Load class data from database You can pass parameters thru HASH passed as parameter array.
	my $self = shift;
	if ( !$self->loaded ) {

		#Primary key exists do download from database
		if ( scalar( $self->pkc ) ) {

			#Prepare query to fetch data from pgsql database
			my $query = "SELECT * FROM " . $self->entity . " WHERE " . join( " AND ", map { "$_->{key} = ?" } $self->pkc );
			$self->c->app->log->debug( "$query (" . join( ',', map { $_ // 'NULL' } $self->pkv ) . ")" );

			#Execute query
			my $sth = $self->dbh->prepare($query);
			eval { $sth->execute( $self->pkv ); };
			if ($@) {
				Mojo::Exception->throw( $@ . $self->c->app->caller );
			}
			$self->loaded(1);
			if ( my $row = $sth->fetchrow_hashref() ) {

				#Fill instance from model
				foreach my $key ( keys( %{ $self->definition->{columns} } ) ) {
					if ( $self->definition->{columns}->{$key}->{type} == $self->DB_DATE ) {
						$self->$key( $self->func_parse_pg_date( $row->{$key} ) );
					} else {
						$self->$key( $row->{$key} );
					}
				}

				#Set record as exists
				$self->exists(1);
				$self->changed(0);
			} else {
				$self->exists(0);
			}
		}
	}
	return ($self);
}

sub entity {    #Return entity name from definition
	return ( shift->definition->{entity} );
}

sub search {    #Try search record from database based on parameters passed as hash

	#$obj->search(route => '/information/transport');
	my $self   = shift;
	my %params = @_;

	#Prepare query to fetch data from pgsql database
	my @params = map { $params{$_} } keys(%params);
	my $query =
	    "SELECT "
	  . join( ',', map { $_->{key} } $self->pkc )
	  . " FROM "
	  . $self->entity
	  . " WHERE "
	  . join( " AND ", map { "$_ = ?" } keys(%params) );
	$self->c->app->log->debug( "$query (" . join( ',', @params ) . ")" );

	#Execute query
	my $sth = $self->dbh->prepare($query);
	$sth->execute(@params);
	if ( my $row = $sth->fetchrow_hashref() ) {

		#Hurrrah we have primary key
		map {
			eval { $self->$_( $row->{$_} ) }
		  } map {
			$_->{key}
		  } $self->pkc;
		$self->load();
	}
	return ($self);
}

sub save {    #Save to database instance of Cafe::Mojo::Class. Class must You must also define columns in directives
	my $self = shift;

	#"changed" is up when attributes are changed via getter/setter
	#no change attributes via class hash directly !!!!!!!!! or you
	#must know what happened
	if ( $self->changed ) {
		if ( exists( $self->definition->{columns}->{stateuser} ) ) {
			$self->stateuser( defined( $self->c->iduser ) ? $self->c->iduser : 0 );
		}

		#Set last modified time
		if ( exists( $self->definition->{columns}->{statestamp} ) ) {
			$self->statestamp( $self->c->cnow );
		}

		#Set state bits (setup insert/update bits and remove delete bits
		#Remove delete bits, because if user can save some record, user
		#want see the record in the future
		if ( $self->definition->{columns}->{state} ) {
			$self->state(0) unless ( defined( $self->state ) );
			if ( ( ( $self->state & 1 ) == 0 ) ) {
				$self->state( ( $self->state | 1 ) & ( ~4 ) );
			} else {
				$self->state( ( $self->state | 2 ) & ( ~4 ) );
			}
		}

		#Check save needs
		if ( $self->definition && $self->entity && scalar( $self->columns ) && scalar( $self->pkc() ) ) {

			#Generate new id if possible (just one primary key and sequence exists)
			$self->nextval if ( scalar( $self->pkc ) == 1 && scalar( grep { defined } $self->pkv ) == 0 && $self->sequence );

			if ( scalar( $self->pkc ) == scalar( grep { defined } $self->pkv ) && !$self->exists ) {

				#INSERT record to database
				my $query =
				    "INSERT INTO "
				  . $self->entity . "("
				  . join( ", ", map { $_->{key} } ( $self->pkc, $self->attrc ) )
				  . ") VALUES ("
				  . join( ", ", map { "?" } ( $self->pkc, $self->attrc ) ) . ")";
				$self->c->app->log->debug( "$query (" . join( ',', map { $_ // 'NULL' } $self->pkv, $self->attrv ) . ")" );
				my $sth = $self->dbh->prepare($query);
				eval { $sth->execute( $self->pkv, $self->attrv ); };
				if ($@) {
					Mojo::Exception->throw( "$@" . $self->c->app->caller );
				}
			} elsif (
				scalar( $self->pkc ) == scalar(
					grep {
						defined
					  } $self->pkv
				)
				&& $self->exists
			  )
			{

				#Prepare UPDATE query for single primary keys
				my $query =
				    "UPDATE "
				  . $self->entity . " SET "
				  . join( " , ", map { "$_->{key} = ?" } $self->attrc )
				  . " WHERE "
				  . join( " AND ", map { "$_->{key} = ?" } $self->pkc );
				$self->c->app->log->debug( "$query (" . join( ',', map { $_ // 'NULL' } ( $self->attrv, $self->pkv ) ) . ")" );
				my $sth = $self->dbh->prepare($query);
				$sth->execute( $self->attrv, $self->pkv );
			} else {
				Mojo::Exception->throw( "Not defined all primary key values.\nKeys: "
					  . join( ',', map { $_->{key} } $self->pkc )
					  . "\nValues:"
					  . join( ',', $self->pkv )
					  . $self->c->app->caller );
			}
		} else {
			if ( !$self->definition ) {
				Mojo::Exception->throw("Not usable definition to save object`");
			} elsif ( !$self->entity ) {
				Mojo::Exception->throw("Not defined entity (table). Entity parameter is mandatory to save object.");
			} elsif ( !scalar( $self->columns ) ) {
				Mojo::Exception->throw("There is no column definitions. Columns definition is mandatory to save object.");
			} elsif ( !scalar( $self->pkc ) ) {
				Mojo::Exception->throw("There is no primary key definitions. Primary key definition is mandatory to save object.");
			}
		}
	}
}

sub pkc {    #Return list of primary keys columns
	my $self = shift;
	$self->{_pkc} = [ grep { defined( $_->{primary_key} ) && $_->{primary_key} == 1 } $self->columns ]
	  unless ( defined( $self->{_pkc} ) );
	return ( @{ $self->{_pkc} } );
}

sub pkv {    #Return list of primary keys values
	my $self = shift;
	$self->{_pkv} = [ map { my $col = $_->{key}; $self->$col; } $self->pkc ];
	return ( @{ $self->{_pkv} } );
}

sub attrc {    #Return list of attribute columns (no primary keys columns)
	my $self = shift;
	$self->{_attrc} = [ grep { !$_->{primary_key} } $self->columns ] unless ( defined( $self->{_attrc} ) );
	return ( @{ $self->{_attrc} } );
}

sub attrv {    #Return list of attribute values (no primary keys values)
	my $self = shift;
	$self->{_attrv} = [
		map {
			my $col = $_->{key};
			eval { $self->$col };
		  } $self->attrc
	];
	return ( @{ $self->{_attrv} } );
}

sub sequence {    #Return name sequence in column definiton (if is defined more than one sequences return first sequence)
	my $self = shift;
	my @sec = grep { $_->{sequence} } $self->pkc;
	if ( scalar(@sec) ) {
		return ( $sec[0]->{sequence} );
	}
}

sub validator {    #Overwrite parent method to add directives created from database definition to columns defintion
	my $self = shift;

	#Add max_length directive base on database structure
	if ( !$self->c->app->validator( ref($self) ) ) {
		my %columns = %{ $self->definition->{columns} };
		foreach my $key ( keys(%columns) ) {
			if ( $columns{$key}->{rule} ) {
				if (   $columns{$key}->{type} == $self->DB_VARCHAR
					&& $self->priv_column_info($key)->{TYPE_NAME} eq 'character varying' )
				{
					$columns{$key}->{max_length} = $self->priv_column_info($key)->{COLUMN_SIZE};
				}
			}
		}
	}
	return ( $self->SUPER::validator );
}

sub validate {    #Validate record - first validate primary key and load original record and then use parent validate method
	my $self   = shift;
	my $params = shift;
	if ( ! $self->loaded ) {
		my %pk     = map { $_->{key} => $params->{ $_->{key} } } $self->pkc;
		$self->SUPER::validate( \%pk );
		$self->load;
	}
	return ( $self->SUPER::validate($params) );
}

sub remove {      #If exists column state mark record as deleted If does not exists column state use database DELETE command
	my $self = shift;
	if ( exists( $self->definition->{columns}->{state} ) ) {

		#Prepare UPDATE query to mark record as deleted
		my $query = "UPDATE " . $self->entity . " SET state = state | 4  WHERE " . join( " AND ", map { "$_->{key} = ?" } $self->pkc );
		$self->c->app->log->debug( "$query (" . join( ',', map { $_ // 'NULL' } ( $self->pkv ) ) . ")" );
		my $sth = $self->dbh->prepare($query);
		$sth->execute( $self->pkv );
	} else {

		#Prepare DELETE query to remove record from database
		my $query = "DELETE FROM " . $self->entity . " WHERE " . join( " AND ", map { "$_->{key} = ?" } $self->pkc );
		$self->c->app->log->debug( "$query (" . join( ',', map { $_ // 'NULL' } ( $self->pkv ) ) . ")" );
		my $sth = $self->dbh->prepare($query);
		$sth->execute( $self->pkv );
	}
	return ( $self->SUPER::validator );
}

sub nextval {    #Generate next value from sequence and set sequence to primary key column
	my $self = shift;
	my $sth  = $self->dbh->prepare(q(SELECT nextval(?) as id));
	$sth->execute( $self->sequence ) or Mojo::Exception->throw("$!");
	if ( my $row = $sth->fetchrow_hashref() ) {
		my $col = ( $self->pkc )[0]->{key};
		eval { $self->$col( $row->{id} ) };
		$self->c->app->log->debug( "New sequence value from " . $self->sequence . " = $row->{id}" );
	} else {
		Mojo::Exception->throw( "Cant fetch next value from sequence " . $self->sequence );
	}
}

sub exists {    #If record exists returns 1, if record does not exists return 0, if instance doesn know return undef
	my $self = shift;
	if ( scalar(@_) ) {
		$self->{_exists} = shift;
	}
	if ( !exists( $self->{_exists} ) ) {
		if ( scalar( $self->pkc ) ) {

			#Prepare query to fetch data from pgsql database
			my $query = "SELECT 1 FROM " . $self->entity . " WHERE " . join( " AND ", map { "$_->{key} = ?" } $self->pkc );
			$self->c->app->log->debug( "$query (" . join( ',', $self->pkv ) . ")" );

			#Execute query
			my $sth = $self->dbh->prepare($query);
			$sth->execute( $self->pkv );
			$self->{_exists} = scalar( @{ $sth->fetchall_arrayref() } );
		}
	}
	return ( $self->{_exists} );
}

sub priv_column_info {    #Return column info for column passed as parameter
	my $self   = shift;
	my $column = shift;

	if ( !$self->{_column_info} ) {
		my $table = $self->entity;
		my $schema;
		my $column;
		if ( $table =~ /([^.]+)\.(.*)/ ) {
			$schema = $1;
			$table  = $2;
		}
		my $sth = $self->dbh->column_info( undef, $schema, $table, $column );
		$self->{_column_info} = $sth->fetchall_arrayref( {} );
	}

	my @retval = grep { $_->{COLUMN_NAME} eq $column } @{ $self->{_column_info} };

	if ( scalar(@retval) ) {
		return ( $retval[0] );
	} else {
		Mojo::Exception->throw( "Column '$column' is not exists in database check table '" . $self->entity . "'." . $self->c->caller );
	}
}

1;

__END__
