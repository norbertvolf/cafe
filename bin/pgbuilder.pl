#!/usr/bin/perl
#
# Bere ze standrdniho vstupu definici tabulky z psql ziskanou pomoci prikazu \d nazev_tabulky
#
my $counter = 0;
my $position = 0;
my $rownumber = 0;
my $primarykey;
my $schema;
my $table;
my $title;
my $definition = {
	entity => '',
	messages => [],
	columns => [
	],
	autoloaders => {
		test => {
			class => 'Test::Item',
			id => 'iditem',
		},
	},
};

while (<STDIN>) { # like "while(defined($_ = <STDIN>)) {"
	chomp; # like "chomp($_)"
	my $row = $_;

	if ( $row =~ /(Tabulka|Table)\s"([^.]+)\.([^"]+).*/ ) {
		$schema = $2;
		$table = $3;
		$title = join(" ",  map(ucfirst, split(/_/, $table)));
		$definition->{entity} = "$schema.$table";
		$definition->{form}->{method_del_caption} = $definition->{form}->{method_del_caption} . " " . $title . "?";
		$rownumber++;
	} elsif ( $row =~ /\s*-+\+/ ) {
		$rownumber++;
	} elsif ( $row =~ /\s*(\w+)\s+\|\s([^|]+)\|(.*)/ && $rownumber < 2) {
		$rownumber++;
	} elsif ( ($row =~ /^\s*(\w+)\s+\|\s([^|]+)\|(.*)/ | $row =~ /^\s*(\w+)\s+\|\s([^|]+)\|$/) && $rownumber > 2) {
		$counter++;
		my $column = $1;
		my $type = $2;
		my $null = $3;
		my $def = { name => $column };

		push(@{$definition->{columns}}, $def);

		if ( $type =~ /integer/ )  {
			$def->{type} = '$c->DB_INT';
		} elsif ( $type =~ /character/ ) {
			$def->{type} = '$c->DB_VARCHAR';
			if ( $type =~ /(\d+)/ ) {
				$def->{opts} = "$1";
			}
		} elsif ( $type =~ /timestamp|date/ ) {
			$def->{type} = '$c->DB_DATE';
		} elsif ( $type =~ /numeric|float/ ) {
			$def->{type} = '$c->DB_NUMERIC';
		}

		if ( $null =~ /not null/ )  {
			$def->{required} = 1;
		} else {
			$def->{required} = 0;
		}


		if ( $column !~ /^state$|^statestamp$|^stateuser$/ ) {
			push(@{$definition->{messages}}, { name => $counter, value => $table . "_msgid_" . $counter });
			$def->{msgid} = $counter;
			$def->{rule} = "1";
			$position++;
			#Prvni polozku (obvykle PK) jen zobrazit
			$def->{position} = '++$pos';
			if ( $counter > 1 ) {
				$def->{label} = join(" ",  map(ucfirst, split(/_/, $column)));
				$def->{input} = "text";
				$def->{tags} = { input => {} };
				if ( $type =~ /integer/ )  {
					$def->{tags}->{input}->{style} = 'width:4em;';
				} elsif ( $type =~ /character/ ) {
					$def->{tags}->{input}->{style} = "width:$def->{opts}em;";
				} elsif ( $type =~ /timestamp|date/ ) {
					$def->{tags}->{input}->{style} = 'width:8em;';
				} elsif ( $type =~ /numeric|float/ ) {
					$def->{tags}->{input}->{style} = 'width:6em;';
				}
			} else {
				$def->{label} = 'Identifier';
			}
		}

		#Predpokladam ze prvni polozka je primarni klic
		if ( $counter == 1 ) {
			$def->{primary_key} = "1";
			$def->{sequence} = "$schema.$column";
			$def->{required} = 0;
			$primarykey = $column;
		}

	}
}


#Generate translation keys table
my $keys = "=pod\n";
$keys .= ucfirst($title) . "|\n";
$keys .= "$definition->{form}->{method_del_caption}|\n";
foreach my $level1 (@{$definition->{columns}}) {
	if ( exists ($level1->{label}) ) {
		$keys .= ucfirst($level1->{label}) . "|\n";
	}
}
$keys .= "=cut\n";



#Generate name of persistent table
my $output = "{\n";
$output .= "\t\t\ttitle => '" . ucfirst($title) . "',\n";
$output .= "\t\t\tentity => '$definition->{entity}',\n";

#Generate columns of persistent table
$output .= "\t\t\tcolumns => {\n";
foreach my $level1 (@{$definition->{columns}}) {
	$output .= "\t\t\t\t$level1->{name} => {\n";
	$output .= "\t\t\t\t\ttype => $level1->{type},\n";
	if ( exists ($level1->{rule}) ) {
		$output .= "\t\t\t\t\trequired => $level1->{required},\n";
		$output .= "\t\t\t\t\trule => $level1->{rule},\n";
	}
	if ( exists ($level1->{primary_key}) ) {
		$output .= "\t\t\t\t\tprimary_key => $level1->{primary_key},\n";
		$output .= "\t\t\t\t\tsequence => '$level1->{sequence}',\n" if ( exists ($level1->{sequence}) );
	}
	$output .= "\n";

	$output .= "\t\t\t\t},\n";

}
$output .= "\t\t\t},\n";

#Generate autoloader example
$output .= "\t\t\tautoloaders => {\n";
foreach my $level1 (sort(keys(%{$definition->{autoloaders}}))) {
	$output .= "#\t\t\t\t$level1 => {\n";
	$output .= "#\t\t\t\t\tclass => '$definition->{autoloaders}->{$level1}->{class}',\n";
	$output .= "#\t\t\t\t\tparams => {,\n";
	$output .= "#\t\t\t\t\t\tiduser => sub { my \$self = shift; return \$self->iduser; },',\n";
	$output .= "#\t\t\t\t\t},\n";
	$output .= "#\t\t\t\t},\n";
}
$output .= "\t\t\t},\n";
$output .= "\t\t}";

$output ="package " . ucfirst($schema) . "::" . join("::",  map { ucfirst($_) } split('_', $table)) . ";

use utf8;

use Mojo::Base 'Mojolicious::Cafe::Class';
use Scalar::Util;

sub new {
	my (\$class, \$c, \$$primarykey) = \@_;
	my \$pos = 0;
	my \$self = \$class->SUPER::new(
		\$c, 
		$output
	); 
	\$self->$primarykey(\$$primarykey) if ( \$$primarykey );
	\$self->load if ( \$$primarykey );	
	return \$self;
}

1;
";
print("$output\n");
