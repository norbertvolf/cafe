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
	name => '',
	messages => [],
	form => {
		url => "?type=json",
		method_get => "",
		method_set => "",
		method_del => "",
		method_del_caption => "Do you want delete",
		method_del_url => "?method=group_search",
		caption_edit => "Edit",
		caption_save => "Save",
		caption_cancel => "Cancel",
		caption_delete => "Delete",
	},
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
		$definition->{name} = "$schema.$table";
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
			$def->{type} = "Cafe::Class::DB_INT";
		} elsif ( $type =~ /character/ ) {
			$def->{type} = "Cafe::Class::DB_VARCHAR";
			if ( $type =~ /(\d+)/ ) {
				$def->{opts} = "$1";
			}
		} elsif ( $type =~ /timestamp|date/ ) {
			$def->{type} = "Cafe::Class::DB_DATE";
		} elsif ( $type =~ /numeric|float/ ) {
			$def->{type} = "Cafe::Class::DB_NUMERIC";
		}

		if ( $null =~ /not null/ )  {
			$def->{null} = "Cafe::Class::DB_NOTNULL";
		} else {
			$def->{null} = "Cafe::Class::DB_NULL";
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
			$def->{null} = "Cafe::Class::DB_NULL";
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
$output .= "\t\t\tname => '$definition->{name}',\n";

#Generate forms
$output .= "\t\t\tform => {\n";
$output .= "\t\t\t\turl => '?type=json',\n";
$output .= "\t\t\t\tmethod_get => '/$schema/$table/get/',\n";
$output .= "\t\t\t\tmethod_set => '/$schema/$table/set/',\n";
$output .= "\t\t\t\tmethod_del => '/$schema/$table/del/',\n";
$output .= "\t\t\t\tmethod_del_caption => '$definition->{form}->{method_del_caption}',\n";
$output .= "\t\t\t\tmethod_del_url => '?method=/$schema/$table/search/',\n";
$output .= "\t\t\t\tcaption_edit => 'Edit',\n";
$output .= "\t\t\t\tcaption_save => 'Save',\n";
$output .= "\t\t\t\tcaption_cancel => 'Cancel',\n";
$output .= "\t\t\t\tcaption_delete => 'Delete',\n";
$output .= "\t\t\t},\n";

#Generate columns of persistent table
$output .= "\t\t\tcolumns => {\n";
foreach my $level1 (@{$definition->{columns}}) {
	$output .= "\t\t\t\t$level1->{name} => {\n";
	$output .= "\t\t\t\t\ttype => $level1->{type},\n";
	$output .= "\t\t\t\t\tnull => $level1->{null},\n";
	if ( exists ($level1->{rule}) ) {
		$output .= "\t\t\t\t\trule => $level1->{rule},\n";
	}
	if ( exists ($level1->{opts}) ) {
		$output .= "\t\t\t\t\topts => $level1->{opts},\n";
	}
	if ( exists ($level1->{primary_key}) ) {
		$output .= "\t\t\t\t\tprimary_key => $level1->{primary_key},\n";
	}
	if ( exists ($level1->{sequence}) ) {
		$output .= "\t\t\t\t\tsequence => '$level1->{sequence}',\n";
	}
	$output .= "\n";
	if ( exists ($level1->{label}) ) {
		$output .= "\t\t\t\t\tlabel => '$level1->{label}',\n";
	}
	if ( exists ($level1->{input}) ) {
		$output .= "\t\t\t\t\tinput => '$level1->{input}',\n";
	}
	if ( exists ($level1->{position}) ) {
		$output .= "\t\t\t\t\tposition => $level1->{position},\n";
	}
	if ( exists ($level1->{tags}) && exists ($level1->{tags}->{input}) && exists($level1->{tags}->{input}->{style}) ) {
		$output .= "\t\t\t\t\ttags => {\n";
		$output .= "\t\t\t\t\t\tinput => { style => '$level1->{tags}->{input}->{style}' },\n";
		$output .= "\t\t\t\t\t},\n";
	}

	$output .= "\t\t\t\t},\n";

}
$output .= "\t\t\t},\n";

#Generate autoloader example
$output .= "\t\t\tautoloaders => {\n";
foreach my $level1 (sort(keys(%{$definition->{autoloaders}}))) {
	$output .= "#\t\t\t\t$level1 => {\n";
	$output .= "#\t\t\t\t\tclass => '$definition->{autoloaders}->{$level1}->{class}',\n";
	$output .= "#\t\t\t\t\tid => '$definition->{autoloaders}->{$level1}->{id}',\n";
	$output .= "#\t\t\t\t\tshadow => '$definition->{autoloaders}->{$level1}->{shadow}',\n";
	$output .= "#\t\t\t\t},\n";
}
$output .= "\t\t\t},\n";
$output .= "\t\t}";

$output ="package " . ucfirst($schema) . "::" . join("::",  map { ucfirst($_) } split('_', $table)) . ";

use utf8;
use warnings;
use strict;
use base qw(Cafe::Class);

sub new {
	my (\$self, \$root, \$parent, \$$primarykey) = \@_;
	my \$pos = 0;
	my (\$instance) = \$self->SUPER::new(
		\$root, 
		\$parent,
		$output
	); 

	bless(\$instance);
	\$instance->$primarykey(\$$primarykey) if ( \$$primarykey );
	\$instance->load() if ( \$$primarykey );	
	return \$instance
}

1;
";
print("$output\n");
