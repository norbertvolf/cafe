package Mojolicious::Cafe::Base;

use Mojo::Base -base;

has loaded => 0;
has okay => 0;
has message => 0;
has 'definition';
has 'c';

#{{{ new
=head3 new

Create new instance of Cafe::Mojo::Class

=cut 
sub new {
	my $class = shift;
	my $c = shift;
	my $def = shift;
	my $self = $class->SUPER::new();

	$self->c($c);
	#Add dbh from controller if not exists
	$def->{dbh} = $self->c->dbh if ( ! exists($def->{dbh}) );
	#Set definition of instance if check of defintion is ok
        #Check end set definition die if there is some error
	$self->definition($self->check($def));	
	#Set default values
	$self->defaults;
	#TODO Generate getters/setters from columns

	return($self);
}
#}}}
#{{{check
=head3 C<check>

Check definiton, passed as paramaters

=cut 
sub check {
	my $self = shift;
	my $def = shift;
	#Is $definition present
	Mojo::Exception->throw("Definition is not pass as parameter.") if ( ! defined($def) ); 
	return($def);
}
#}}}
#{{{columns
=head3 columns

Return sorted (by pos) columns as array

=cut 
sub columns {
	my $self = shift;
	my $def = scalar(@_) ? shift : $self->definition;
	my @columns = sort { ( defined($a->{position}) ? $a->{position} : 0 )  <=> ( defined($b->{position}) ? $b->{position} : 0 ) } map { $def->{columns}->{$_}->{key} = $_;$def->{columns}->{$_} } keys(%{$def->{columns}});
	return(wantarray ? @columns : \@columns);
}
#}}}
#{{{dbh
=head3 C<dbh>

Return dbh from definition

=cut 
sub dbh { return(shift->definition->{dbh} ); }
#}}}
#{{{ dump
=head3 dump

Return string with dumped data

=cut
sub dump {
	my $self = shift;
	return(ref($self) . "::dump = {\n  " . join( "\n  ",  map { eval { "$_ => " . ($self->$_ // '') } } map { $_->{key} } $self->columns) . "\n};" );
}
#}}}
#{{{ root
=head3 root

Return root class for back compatibility
root class is  controller now (property *c*)

=cut
sub root {
	return(shift->c);
}
#}}}
#{{{AUTOLOAD
=head3 AUTOLOAD

Autoloader to handle columns and autoloaders from 
definition

=cut 
sub AUTOLOAD {
	my $self = shift;

	#Dig number or parameters
	my $numofprm = scalar(@_);
	my $param = shift;
	my $method = our $AUTOLOAD;

	Mojo::Exception->throw("Mojolicious::Cafe::Class::AUTLOADER") if ( ! ref( $self ) );
	
	#If not defined DESTROY method and this method is invocated finish method
	return if ( $method =~ /::DESTROY$/ );

	#Check and run method
	if ( $method =~ /::([^:]+)$/ ) {
		my $method = $1;
		if ( exists($self->definition->{columns}->{$method}) ) {
			#Set property if param is defined
			$self->{"_$method"} = $param if ( $numofprm );
			#If is invocated method with name defined as column return value of this column
			return($self->{"_$method"});
		} elsif ( exists($self->definition->{autoloaders}->{$method} ) ) {
			#If is invocated method is defined as autoloader load method
			my $autoloader = $self->definition->{autoloaders}->{$method};
			#Create instance 
			if ( ! defined($self->{"_$autoloader"}) ) {
				my $obj;
				#Prepare destination class
				eval("require $autoloader->{class}"); 
				Mojo::Exception->throw("Cafe::Class::AUTLOADER: $@") if ($@);
				eval('$obj = new ' . $autoloader->{class} . '($self->c);');
				Mojo::Exception->throw("Cafe::Class::AUTLOADER: $@") if ($@);
				if ( exists($autoloader->{params}) && ref( $autoloader->{params} ) eq 'HASH') {
					foreach my $key ( keys(%{$autoloader->{params}}) ) {
						#Clean up destination property name
						$key =~ s/^\s*(\w+)\s*$/$1/;

						#Set param value as value or as value returned from anonymous 
						#function passed as param (anonymous function can return
						#anything what you want
						if ( ref($autoloader->{params}->{$key}) eq 'CODE') {
							eval("\$obj->$key(&{\$autoloader->{params}->{\$key}}(\$self));");
							Mojo::Exception->throw("Cafe::Class::AUTLOADER: $@") if ($@);
						} else {
							eval("\$obj->$key(\$autoloader->{params}->{\$key});");
							Mojo::Exception->throw("Cafe::Class::AUTLOADER: $@") if ($@);
						}
					}
				}
				$obj->load();
				$self->{"_$autoloader"} = $obj;
			}
			return($self->{"_$autoloader"});
		} else {
			Mojo::Exception->throw("Method $method is not defined");
		}
	}
}
#}}}

#Private methods
#{{{ defaults
=head3 C<defaults>

Set default columns values

=cut 
sub defaults {
	my $self = shift;

	#Set default values
	foreach my $col ( $self->columns ) {
		eval("\$self->$col->{key}(\$col->{default});") if ( exists($col->{default} ) );
	}
}
#}}}

1;
