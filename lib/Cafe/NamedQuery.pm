package Cafe::NamedQuery;
use utf8;
use strict;
use vars qw($DEBUG);
use DBI qw(:sql_types);
use Data::Dumper;
use POSIX;


sub new {
	my ($self, $dbh, $query) = @_;
	my $instance = bless ({}, ref ($self) || $self);
	$instance->{dbh} = $dbh;
	$instance->{params} = {};
	$instance->{query} = {};
	$instance->{query}->{sql} = $query;

#Prepare sql for DBI
	$instance->{query}->{sql_anon} = $query;
	$instance->{query}->{sql_anon} =~ s/@(\w+)/?/g;
	$instance->{query}->{sth} = $instance->{dbh}->prepare($instance->{query}->{sql_anon}, { pg_server_prepare => 0 }) or die "AF error " . __FILE__ . " line " . __LINE__ . ": $!";

	if ( $DEBUG ) { print(STDERR "AF debug " . __FILE__ . " line " . __LINE__ . ":\n" . Dumper($instance->{query}->{sql_anon})); }

	return($instance);
}

sub bind_params {
#Pripojime parametry k dotazu
	my ($self, $params) = @_;
	my $query_tmp = $self->{query}->{sql};
	$self->{query}->{params} = [];

	while ($query_tmp =~ /@(\w+)/ ) {
		#Add parameter to array
		push(@{$self->{query}->{params}}, { name => $1, value => $params->{$1}->{value}, type => $params->{$1}->{type} });
		$query_tmp =~ s/@(\w+)/?/;
	}

	for( my $i = 0; $i < scalar(@{$self->{query}->{params}});$i++) {
		my $param = $self->{query}->{params}->[$i];
		my $value = $param->{value};

		if ( ref( $value ) eq "Time::Piece" ) {
			$value = $param->{value}->datetime();
		}

		if ( $DEBUG ) { print(STDERR "AF debug " . __FILE__ . " line " . __LINE__ . ":\n" . "Print NamedQuery bind param:" . Dumper($param)); }

		$self->{query}->{sth}->bind_param($i + 1, $param->{value}, $param->{type});
	}
	return($self->{query}->{params});
}

sub orderby {
	my ($self, $orderby) = @_;
			;
	if ( scalar(@{$orderby}) && ! ( $self->{query}->{sql_anon} =~ /ORDER BY/i ) ) {
		my @orderbystr;
		foreach  my $ref (@{$orderby}) {
			push(@orderbystr, $ref->{column} . " " . $ref->{ascending});
		}
		$orderby = join(",", @orderbystr);
		if ( $self->{query}->{sql_anon} =~ /limit/i ) {
			#ANSI SQL limit
			$self->{query}->{sql_anon} =~ s/limit/ORDER BY $orderby LIMIT/i;
		} elsif ( $self->{query}->{sql_anon} =~ /fetch\s+first\s+\d+\s+rows\s+only/i ) {
			#DB2 limit
			$self->{query}->{sql_anon} =~ s/(fetch\s+first\s+\d+\s+rows\s+only)/ORDER BY $orderby $1/i;
		} else {
			$self->{query}->{sql_anon} .= " ORDER BY $orderby";
		}

		$self->{query}->{sth} = $self->{dbh}->prepare($self->{query}->{sql_anon}, { pg_server_prepare => 0 }) or die "AF error " . __FILE__ . " line " . __LINE__ . ": $!";
	}
}


sub sth {
	my ($self) = @_;
	return($self->{query}->{sth});	
}

sub DESTROY {
	my $self = shift;
}

1; #this line is important and will help the module return a true value
__END__

