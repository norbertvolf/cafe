package Mojolicious::Cafe::SQL::Query;

use Mojo::Base 'Mojo::Base';

has 'columns';
has 'from_clause';
has 'where_clause';
has 'groupby_clause';
has 'orderby_clause';
has 'limit_clause';

sub new {    #Create new instance of Mojolicious::Cafe::Listing
	my $class = shift;
	my $self  = $class->SUPER::new();
	$self->query(shift);
	return ($self);
}

sub parameters {    #Return parameters from query
	my $self  = shift;
	my $query = $self->query;
	my @parameters;
	while ( $query =~ s/@(\w+)/?/ ) {
		push( @parameters, $1 );
	}
	return (@parameters);
}

sub query {         #Set, generate and return query from tokens
	my $self = shift;
	if ( scalar(@_) ) {
		$self->{_query} = shift;
		$self->parse();
		$self->{_orig_where_clause} = $self->where_clause;
	}

	#Generate query from clauses
	my @query;
	push( @query, 'SELECT', $self->columns, 'FROM', $self->from_clause );
	if ( $self->where_clause ) {
		push( @query, 'WHERE', $self->where_clause, );
	}
	if ( $self->groupby_clause ) {
		push( @query, 'GROUP BY', $self->groupby_clause, );
	}
	if ( $self->orderby_clause ) {
		push( @query, 'ORDER BY', $self->orderby_clause, );
	}
	if ( $self->limit_clause ) {
		push( @query, 'LIMIT', $self->limit_clause, );
	}
	return ( join( ' ', @query ) );
}

sub fullfeatured {    #Alias for query
	my $self = shift;
	return ( $self->query );
}

sub pretty {          #Return formatted query
	my $self = shift;
	my $indent = shift // "";

	#Generate query from clauses
	my @query;
	push( @query, $indent . "SELECT", $self->columns );

	my $from_clause = $self->from_clause;
	$from_clause =~ s/(LEFT JOIN|RIGHT JOIN|CROSS JOIN|INNER JOIN|JOIN)/\n$indent\t\t$1/g;
	push( @query, "\n$indent\tFROM", $from_clause );
	if ( $self->where_clause ) {
		my $where_clause = $self->where_clause;
		$where_clause =~ s/(AND)/\n$indent\t\t$1/g;
		push( @query, "\n$indent\tWHERE", $where_clause );
	}
	if ( $self->groupby_clause ) {
		push( @query, "\n$indent\tGROUP BY", $self->groupby_clause, );
	}
	if ( $self->orderby_clause ) {
		push( @query, "\n$indent\tORDER BY", $self->orderby_clause, );
	}
	if ( $self->limit_clause ) {
		push( @query, "\n$indent\tLIMIT", $self->limit_clause, );
	}
	return ( join( ' ', @query ) );
}

sub placeholdered {    #Return query where variables are converted to to placeholders
	my $self  = shift;
	my $query = $self->query;
	$query =~ s/@\w+/?/g;
	return ($query);
}

sub orig_where_clause {    #Return original where clause to combine where clause from query and dynamically prepare where clause
	return ( shift->{_orig_where_clause} );
}

sub counter {              #Generate and return query to compute number of rows
	my $self = shift;

	#Generate query from clauses
	my @query;
	if ( $self->groupby_clause ) {
		push( @query, 'SELECT COUNT(*) AS cnt FROM ( SELECT 1 FROM', $self->from_clause );
		if ( $self->where_clause ) {
			push( @query, 'WHERE', $self->where_clause, );
		}
		if ( $self->groupby_clause ) {
			push( @query, 'GROUP BY', $self->groupby_clause, );
		}
		push( @query, ' ) x' );
	} else {
		push( @query, 'SELECT COUNT(*) AS cnt FROM', $self->from_clause );
		if ( $self->where_clause ) {
			push( @query, 'WHERE', $self->where_clause );
		}
	}
	return ( join( ' ', @query ) );
}

sub counter_pretty {    #Return formatted query for counter
	my $self = shift;
	my $indent = shift // "";

	#Generate query from clauses
	my @query;
	if ( $self->groupby_clause ) {
		push( @query, $indent . "SELECT COUNT(*) FROM ( " );
		push( @query, $indent . "\tSELECT 1 " );
		my $from_clause = $self->from_clause;
		$from_clause =~ s/(LEFT JOIN|RIGHT JOIN|CROSS JOIN|INNER JOIN|JOIN)/\n$indent\t\t\t$1/g;
		push( @query, "\n$indent\t\tFROM", $from_clause );
		if ( $self->where_clause ) {
			my $where_clause = $self->where_clause;
			$where_clause =~ s/(AND)/\n$indent\t\t\t$1/g;
			push( @query, "\n$indent\t\tWHERE", $where_clause );
		}
		if ( $self->groupby_clause ) {
			push( @query, "\n$indent\t\tGROUP BY", $self->groupby_clause, );
		}
		push( @query, $indent . "\t) x" );
	} else {
		push( @query, $indent, "SELECT COUNT(*) AS cnt" );
		my $from_clause = $self->from_clause;
		$from_clause =~ s/(LEFT JOIN|RIGHT JOIN|CROSS JOIN|INNER JOIN|JOIN)/\n$indent\t\t$1/g;
		push( @query, "\n$indent\tFROM", $from_clause );
		if ( $self->where_clause ) {
			my $where_clause = $self->where_clause;
			$where_clause =~ s/(AND)/\n$indent\t\t$1/g;
			push( @query, "\n$indent\tWHERE", $where_clause );
		}
	}
	return ( join( ' ', @query ) );
}

sub counter_placeholdered {    #Return counter query where variables are converted to to placeholders
	my $self  = shift;
	my $query = $self->counter;
	$query =~ s/@\w+/?/g;
	return ($query);
}

sub counter_parameters {       #Return parameters from counter query
	my $self  = shift;
	my $query = $self->counter;
	my @parameters;
	while ( $query =~ s/@(\w+)/?/ ) {
		push( @parameters, $1 );
	}
	return (@parameters);
}

sub parse {                    #Parse query and fill clause attributes
	my $self = shift;
	my $str  = $self->cleanupquery( $self->{_query} );
	$str =~ s/^SELECT (.+)$/$1/i;
	if ( $str =~ s/^(.+) LIMIT (.+)$/$1/i ) {
		$self->limit_clause( $2 // '' );
	}
	if ( $str =~ s/^(.+) ORDER BY (.+)$/$1/i ) {
		$self->orderby_clause( $2 // '' );
	}
	if ( $str =~ s/^(.+) GROUP BY (.+)$/$1/i ) {
		$self->groupby_clause( $2 // '' );
	}
	if ( $str =~ s/^(.+?) WHERE (.+)$/$1/i ) {
		$self->where_clause( $2 // '' );
	}
	if ( $str =~ s/^(.+?) FROM (.+)$/$1/i ) {
		$self->from_clause( $2 // '' );
	}
	$self->columns($str);
}

sub cleanupquery {    #Remove all EOLs and whitespace chains
	my $self = shift;
	my $str  = shift;
	$str =~ s/--[^\n]+\n/ /g;
	$str =~ s/\n/ /g;
	$str =~ s/^\s+//;
	$str =~ s/\s+/ /g;
	return ($str);
}
1;

__END__

=head1 NAME

Mojolicious::Cafe::SQL::Query - 'parse' SQL query. Provide utilities for 
Mojolicious::Cafe::List* classes SQL query .

=head1 CLAUSES

=head2 columns

Return column clause (list of columns passed after SELECT keyword)

=head2 from_clause

Return FROM clause

=head2 where_clause

Return WHERE clause

=head2 groupby_clause

Return GROUP BY clause

=head2 orderby_clause

Return ORDER BY clause

=head2 limit_clause

Return LIMIT/OFFSET clause

=head1 METHODS

Mojolicious::Cafe::SQL::Query inherites all methods from Mojo::Base 
and implements the following new ones.

=head2 parse

B<parse> divide the query to clauses.
