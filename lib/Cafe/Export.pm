package Cafe::Export;
use strict;
use utf8;

use DBI;
use Sys::Syslog;
use URI;

sub new {
# {{{
	my ($self, $root, $parent, $definition) = @_;
	my ($instance) = {}; 
	bless($instance);

	if ( $definition ) {
		$instance->{definition} = $definition;
	} else {
		die "Definition not found";
	}

	if ( $instance->{definition}->{source} ) {
		if ( $instance->{definition}->{source}->{connection} ) {
			$instance->{definition}->{source}->{dbh} = DBI->connect(@{$instance->{definition}->{source}->{connection}}) or $root->error("$!");
		}
		if ( exists($instance->{definition}->{source}->{before}) ) {
			foreach my $query (@{$instance->{definition}->{source}->{before}}) {
				$instance->{definition}->{source}->{dbh}->do($query);
			}
		}
		if ( !exists($instance->{definition}->{source}->{autocommit}) ){
			$instance->{definition}->{source}->{autocommit} = 1;
		}
	}

	if ( $instance->{definition}->{destination} ) {
		if ( $instance->{definition}->{destination}->{connection} ) {
			$instance->{definition}->{destination}->{dbh} = DBI->connect(@{$instance->{definition}->{destination}->{connection}}) or $root->error("$!");
		}
		if ( exists($instance->{definition}->{destination}->{before}) ) {
			foreach my $query (@{$instance->{definition}->{destination}->{before}}) {
				$instance->{definition}->{destination}->{dbh}->do($query);
			}
		}
		if ( !exists($instance->{definition}->{destination}->{autocommit}) ){
			$instance->{definition}->{destination}->{autocommit} = 1;
		}
	}

	#Save reference to instance of Apache::Script class
	$instance->{root} = $root;

	return $instance;
# }}}
}

sub export {
# {{{
        my ($self) = @_;

        foreach my $table (@{$self->{definition}->{tables}}) {
		if ( ! $table->{disabled} ) {
			$self->{root}->log("Exporting $table->{desc}\n");

			if ( $self->{definition}->{destination} ) {
				if ( ! $self->{definition}->{destination}->{autocommit} ) {
					$self->{definition}->{destination}->{dbh}->begin_work();
				}
			}
	
			$self->export_query($table);

			if ( $self->{definition}->{destination} ) {
				if ( ! $self->{definition}->{destination}->{autocommit} ) {
					$self->{definition}->{destination}->{dbh}->commit();
				}
			}
		}
        }
# }}}
}

sub export_query {
# {{{
	my ( $self, $table ) = @_;
	my ($sth, $last, $sth_update, $sth_delete, $sth_del_log);
	my $cnt = 0;
	my $sth_insert;
	my @to_arr = ();
	my @param_arr = ();

	#Execute qyery for source data
	$sth = $self->{definition}->{source}->{dbh}->prepare($table->{from}->{def});
	$sth->execute() or die "$! (SQL: $table->{from}->{def})";

	#Define queries for destination table if is defined
	if ( exists($table->{to}) ) {
		#Define insert query
		foreach my $field (@{$table->{to}->{fields}}) {
			push(@to_arr, $field);
			push(@param_arr, "?");
		}

		my $sql = "INSERT INTO $table->{to}->{def} (" . join(",", @to_arr) . ") VALUES ("  . join(",", @param_arr) . ")";
		$sth_insert = $self->{definition}->{destination}->{dbh}->prepare($sql);

		#Define update query
		if ( exists($table->{operation})) {
			@to_arr = ();
			foreach my $field (@{$table->{to}->{fields}}) { push(@to_arr, "$field = ?"); }
			$sql = "UPDATE $table->{to}->{def} SET " . join(",", @to_arr) . " WHERE $table->{operation}->{column_destination_primary_key} = ?";
			$sth_update = $self->{definition}->{destination}->{dbh}->prepare($sql);
		}

		#Define delete query
		if ( exists($table->{operation})) {
			$sql = "DELETE FROM $table->{to}->{def} WHERE $table->{operation}->{column_destination_primary_key} = ?";
			$sth_delete = $self->{definition}->{destination}->{dbh}->prepare($sql);
		}
	}

	if ( $self->{definition}->{destination}->{autocommit} )	{ 
		$self->{definition}->{destination}->{dbh}->begin_work();
	};
	if ( $self->{definition}->{source}->{autocommit} )	{ 
		$self->{definition}->{source}->{dbh}->begin_work();
	};

	#Truncate full copy tables
	if ( 	! $table->{from}->{use_last_key} 
		&& exists($table->{to})
		&& ! exists($table->{operation})
		&& ! $table->{notruncate}
	) {
		$self->{definition}->{destination}->{dbh}->do("TRUNCATE $table->{to}->{def}");
	}

	#Run before event
	if ( $table->{before} ) {
		&{$table->{before}}($self);
	}

	#Copy data to destination table
	while ( my $row = $sth->fetchrow_hashref() ) {
		if ( $table->{listing} && $table->{listing} > 0 ) {
			if ( ++$cnt  % $table->{listing} == 0 ) {
				$self->{root}->log("$cnt rows replicated " . ( exists($table->{to}) ? "to $table->{to}->{def}" : "by $table->{desc}" ) . ".\n");
			}
		}

		@param_arr = ();
		
		if ( $table->{from}->{event} ) {
			&{$table->{from}->{event}}($self, $row);
		}

		foreach my $field (@{$table->{from}->{fields}}) {
			if ( ref($field) eq "HASH") { 
				my $text;
				if ( $field->{event} ) {
					$text = &{$field->{event}}($self, $row->{$field->{column}});
				}
				push(@param_arr, $text);
			} elsif ($field) { 
				push(@param_arr, $row->{$field});
			} else {
				push(@param_arr, undef);
			}
		}

		if ( exists($table->{operation}) && exists($table->{to}) ) {
			if ( ( $row->{$table->{operation}->{column_source_operation}} & 1 ) == 1 ) {
				$sth_insert->execute(@param_arr) or die "$!";
			}
			if ( ( $row->{$table->{operation}->{column_source_operation}} & 2 ) == 2 ) {
				push(@param_arr, $row->{$table->{operation}->{column_source_primary_key}});
				$sth_update->execute(@param_arr) or die "$!";
			}
			if ( ( $row->{$table->{operation}->{column_source_operation}} & 4 ) == 4 ) {
				$sth_delete->execute($row->{$table->{operation}->{column_source_primary_key}}) or die "$!";
			}
			$self->{definition}->{source}->{dbh}->do("
				DELETE FROM $table->{operation}->{table_log} 
					WHERE $table->{operation}->{column_log_id} = $row->{$table->{operation}->{column_source_primary_key}}
						AND $table->{operation}->{column_log_name} = '$table->{operation}->{table_source}'
			")  or die "$!";
		} elsif( exists($table->{to}) )  {
			$sth_insert->execute(@param_arr) or die "$!";
		}

		#Remember last primary key value
		if ( $table->{from}->{use_last_key} ) {
			$last->{new_value} = $row->{$last->{column_name}};
		}
	}
	#Save last key value to definition table
	if ( $table->{from}->{use_last_key} && exists($last->{new_value}) ) {
		$self->{root}->log("Save new last value for for key $last->{column_name} and value $last->{new_value}.\n");
		$self->last($table->{from}->{use_last_key}, $last->{new_value});
	}
	
	#Run after event
	if ( $table->{after} ) {
		&{$table->{after}}($self);
	}

	if ( $table->{listing} && $table->{listing} > 0 ) {
		$self->{root}->log("Done $table->{desc} with $cnt rows.\n");
	}

	if ( $self->{definition}->{destination}->{autocommit} ){
		$self->{definition}->{destination}->{dbh}->commit();
	};
	if ( $self->{definition}->{source}->{autocommit} ){
		$self->{definition}->{source}->{dbh}->commit();
	};
# }}}
}

sub last {
# {{{
	my ( $self, $idlast_key_value, $newvalue ) = @_;
	my $retval;

	if (  defined( $newvalue ) ) {
		$retval = $newvalue;
		$self->{root}->{dbh}->do("UPDATE schema.last_key_values SET last_value = ? WHERE idlast_key_value = ?", undef, $newvalue, $idlast_key_value) or 
			die "Error with save newlast value to database: @!";
	}

	my $sth = $self->{root}->{dbh}->prepare(q(
		SELECT  
			last_value,
			idlast_key_value,
			table_name,
			column_name
			FROM schema.last_key_values 
			WHERE idlast_key_value = ?
	));
	$sth->execute($idlast_key_value);
	if ( my $row = $sth->fetchrow_hashref() ) {
		$retval = $row;
	}
	$sth->finish();

	if ( ! defined($retval) ) { die "Error with get last_key_value" } 

	return($retval);
# }}}
}

sub DESTROY {
	my ($self) = @_;
}

1;

__END__


=head1 NAME

Cafe::Export - module is used for script inside My Framework

=head1 SYNOPSIS

use Cafe::Export;

my $definition = {
	source => {
		connection => ['dbi:Pg:dbname=databaze;host=mujhost', 'uzivatel', 'heslo'],
		before => [
			q(SET client_encoding = 'UTF-8')
		],
	},
	destination => {
		connection => ['dbi:mysql:database=databaze', 'uzivatel', 'heslo'],
	},
	tables => [
		{ 	
			desc	=> 'Import of st_prijem',
			disabled => 0,
			from    => {
				def => q(
					SELECT 
						idprijem,
						value,
						amount,
						desc
						FROM st_prijem
				),
				event => sub {
					my ($self, $row) = @_;
					$row->{idprijem} = $row->{idprijem} * 100;
				}
				fields => [
					'idprijem',
					{
						name => 'value',
						event => sub {
							my ($self, $text) = @_;
							$text = "new_value";
							return($text);
						}
					},
					'amount',
					'desc'
				]
			},
			to => {
				def => 'mirror.st_prijem',
				fields => [
					'idprijem',
					'value',
					'amount.,
					'desc'
				]
			}
		},
	]
};

my $script = new Apache::Script("Iris::Application", "/var/www/perl/", "dbi:Pg:dbname=bata;host=klinger.hcbr.bata.cz", 'robot', 'Laexee0e');
my $export = new Apache::Export($script, $script, $definition);
$export->export();

=head1 FUNCTIONS

=over 8

=item last KEY, NEWVALUE

return last value from framework database, if NEWVALUE is defined method set new value

=back
