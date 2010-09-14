package Cafe::Path;

use strict;

sub new {
	my ($self, $packagename, $perl5lib) = @_;
	my ($instance) = {}; bless($instance);

	$instance->{"packagename"} = $packagename;
	$instance->{"perl5lib"} = $perl5lib;
	return $instance;
}

sub gettemplatespaths{
	my ($self, $locale) = @_;
	my (@libpaths, $libpath, $retval, $packagepath, $libpackage);

	@libpaths = split(/:/, $self->{"perl5lib"});
	$packagepath = $self->{"packagename"};
	$packagepath =~ s/::\w+$/\//;

	$libpackage = __PACKAGE__;
	$libpackage =~ s/::\w+$/\//;
    
	if ( $locale ) {
		for $libpath (@libpaths) {
			#Add library paths 
			$retval .= "$libpath/$packagepath/templates/$locale" . ":";
			$retval .= "$libpath/$libpackage/templates/$locale" . ":";
			#Add library paths 
			$retval .= $libpath . "/" . $packagepath . "/templates/:";
			$retval .= $libpath . "/" . $libpackage . "/templates/:";
		}
	} else {
		for $libpath (@libpaths) {
			#Add library paths 
			$retval .= $libpath . "/" . $packagepath . "/templates/:";
			$retval .= $libpath . "/" . $libpackage . "/templates/:";
		}
	}

#Clear return value
	$retval =~ s/\/\//\//g;
	$retval =~ s/:$//g;
	return($retval);
}

sub getqueryspaths{
	my ($self) = @_;
	my (@libpaths, $packagepath, $libpath, $retval, $libpackage);

	@libpaths = split(/:/, $self->{"perl5lib"});
	$packagepath = $self->{"packagename"};

#Change :: from module name to / from filesystem
	$packagepath =~ s/::\w+$/\//;
	$libpackage = __PACKAGE__;
	$libpackage =~ s/::\w+$/\//;

#Join more paths to one sting with : separetor
	for $libpath (@libpaths) {
		$retval .= $libpath . "/" . $packagepath . "/sql/:";
		#Add library paths 
		$retval .= $libpath . "/" . $libpackage . "/sql/:";
		#Add root path
		$retval .= $libpath . "/:";
	}
	#Clear return value
	$retval =~ s/\/\//\//g;
	$retval =~ s/:$//g;
	return($retval);
}

sub DESTROY {
	my ($self) = @_;
}

1;
