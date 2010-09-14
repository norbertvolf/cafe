package Cafe::Filters;
use strict;
use utf8;
use Text::Iconv;
use File::Path;
use File::Spec;
use File::Temp qw/tempdir/;
use Cwd;
use MIME::Base64 qw(encode_base64);
use Encode;
use POSIX;

#-------------------------------------------
#Template toolkit filters

=item Filter html_zipcode
Formating zipcode
=cut

sub  tex_zipcode {
# {{{
	my ($context)  = @_;

	return sub{
		my $text = shift;
		if ( $text =~ /^\s*(\d\d\d)(\d\d)\s*$/) {
			$text = "$1~$2";
		}
		return($text);
	}
# }}}
}

=item Filter shoesize 
Formating shoesize for html
=cut
sub shoesize {
# {{{
	my ($context)  = @_;

	return sub{
		my $text = shift;
		if ( $text =~ /^(\d+),5$/) {
			$text = "$1&#189;";
		} elsif ( $text =~ /^(\d+),0$/) {
			$text = "$1";
		}
		return($text);
	}
# }}}
}

sub article {
# {{{
	my ($context)  = @_;

	return sub{
		my $text = shift;
		if ( $text =~ /^(\d{2})(\d{4})$/) {
			$text = "0$1-$2";
		}
		if ( $text =~ /^(\d{3})(\d{4})$/) {
			$text = "$1-$2";
		}
		if ( $text =~ /^(\d{4})(\d{3})(\d{4})$/) {
			$text = "$1-$2-$3";
		}
		return($text);
	}
# }}}
}


sub location {
# {{{
	my ($context)  = @_;

	return sub{
		my $text = shift;
		if ( $text =~ /^(.{2})(.{3})(.{2})$/) {
			$text = "$1-$2-$3"
		} elsif ( $text =~ /^(.{2})(.{3})$/) {
			$text = "$1-$2"
		}
		return($text);
	}
# }}}
}

sub phonenumber {
# {{{
	my ($context)  = @_;

	return sub{
		my $text = shift;
		if ( $text =~ /^(\+4.{2})(.{3})(.{3})(.{3})$/) {
			$text = "$1&nbsp;$2&nbsp;$3&nbsp;$4";
		};
		return($text);
	}
# }}}
}

sub iso2utf {
# {{{
	my ($context)  = @_;

  return sub {
    my $text = shift;
    my $converter = Text::Iconv->new("ISO-8859-2", "UTF-8");
    return($converter->convert($text));
  }
# }}}
}

sub texclean {
# {{{
	my ($context)  = @_;

	return sub {
		my $text = shift;
		$text =~ s/\\/\\textbackslash /g;
		$text =~ s/\$/\\\$/g;
		$text =~ s/_/\\_/g;
		$text =~ s/&#8222;([^&]+)&#8220;/\\uv{$1}/g;
		$text =~ s/&#8211;/--/g;
		$text =~ s/&#177;/\$\\pm\$/g;
		$text =~ s/°/\$^o\$/g;
		$text =~ s/˚/\$\^\\circ\$/g;
		$text =~ s/&/\\&/g;
		$text =~ s/#/\\#/g;
		$text =~ s/%/\\% /g;
		$text =~ s/§/\\S /;
		$text =~ s/˘/\\v{ }/g;
		$text =~ s/¨/\\"{ }/g;
		$text =~ s/¸/\\c{ }/g;
		$text =~ s/´/\\'{ }/g;
		$text =~ s/ˇ/\\v{ }/g;
		$text =~ s/˛/\\v{ }/g;
		$text =~ s/˝/\\v{ }/g;
		$text =~ s/˙/\\.{ }/g;
		$text =~ s/ß/\\ss/g;
		$text =~ s/ľ/\\'{l}/g;
		$text =~ s/ł/\\l /g;
		$text =~ s/Ł/\\L /g;
		$text =~ s/Ľ/\\'{L}/g;
		$text =~ s/â/\\^{a}/g;
		$text =~ s/ă/\\v{a}/g;
		$text =~ s/Ą/\\c{A}/g;
		$text =~ s/Â/\\^{A}/g;
		$text =~ s/Ă/\\v{A}/g;
		$text =~ s/ą/\\c{a}/g;
		$text =~ s/ç/\\c{c}/g;
		$text =~ s/Ć/\\'{C}/g;
		$text =~ s/Ç/\\c{C}/g;
		$text =~ s/đ/d/g;
		$text =~ s/Đ/D/g;
		$text =~ s/ę/\\c{e}/g;
		$text =~ s/ë/\\"{e}/g;
		$text =~ s/Ę/\\c{E}/g;
		$text =~ s/Ë/\\"{E}/g;
		$text =~ s/ş/\\c{s}/g;
		$text =~ s/Ń/\\'{N}/g;
		$text =~ s/Ó/\\'{O}/g;
		$text =~ s/Ő/\\H{O}/g;
		$text =~ s/Ű/\\H{U}/g;
		$text =~ s/Ŕ/\\'{R}/g;
		$text =~ s/î/\\^{i}/g;
		$text =~ s/Î/\\^{I}/g;
		$text =~ s/Ĺ/\\'{L}/g;
		$text =~ s/ś/\\'{s}/g;
		$text =~ s/Ś/\\'{S}/g;
		$text =~ s/Ş/\\c{S}/g;
		$text =~ s/ţ/\\c{t}/g;
		$text =~ s/Ţ/\\c{T}/g;
		$text =~ s/ć/\\'{c}/g;
		$text =~ s/ź/\\'{z}/g;
		$text =~ s/ż/\\.{z}/g;
		$text =~ s/Ź/\\'{Z}/g;
		$text =~ s/Ż/\\.{Z}/g;
		$text =~ s/ń/\\'{n}/g;
		$text =~ s/ő/\\H{o}/g;
		$text =~ s/ű/\\H{u}/g;
		$text =~ s/µ/\$\\mu\$/g;
		$text =~ s/–/-/g;
		$text =~ s/€/\\euro/g;
		$text =~ s/÷/\$\\div\$/g;
		$text =~ s/\367/\$\\div\$/g;
		$text =~ s/„/"/g;
		$text =~ s/“/"/g;
		$text =~ s/ /~/g;
		$text =~ s/½/\$\\frac{1}{2}\$/g;

		return($text);
	}
# }}}
}

# if cslatextwice ... it calls cslatex twice. It is necessary to call it twice when you need page references to be printed
sub cslatex_filter_factory {
# {{{
    my($context, $output, $options, $cslatextwice) = @_;
	
    $output = lc($output);
    my $fName = "cslatex";
    my($LaTeXPath, $PdfLaTeXPath, $DviPSPath, $PS2PdfPath) = ("/usr/bin/latex", "/usr/bin/pdfcslatex", "/usr/bin/dvips", "/usr/bin/ps2pdf");

    if ( $output eq "ps" || $output eq "dvi" || $output eq "ps2pdf" ) {
        $context->throw($fName,
					"latex not installed (see Template::Config::LATEX_PATH)")
						if ( $LaTeXPath eq "" );
    } else {
        $output = "pdf";
        $LaTeXPath = $PdfLaTeXPath;
        $context->throw($fName,
					"pdflatex not installed (see Template::Config::PDFLATEX_PATH)")
						if ( $LaTeXPath eq "" );
    } 

    if ( $output eq "ps" && $DviPSPath eq "" ) {
        $context->throw($fName,
                "dvips not installed (see Template::Config::DVIPS_PATH)");
    }
    if ( $^O !~ /^(MacOS|os2|VMS)$/i ) {
        return sub {
            local(*FH);
            my $text = shift;
						$text =~ s/&#8211;/--/g;
            my $tmpRootDir = File::Spec->tmpdir();
            my $cnt = 0;
            my($tmpDir, $fileName, $devnull);
            my $texDoc = 'doc';

            do {
                $tmpDir = File::Spec->catdir($tmpRootDir,
                                             "tt2latex$$" . "_$cnt");
                $cnt++;
            } while ( -e $tmpDir );
            mkpath($tmpDir, 0, 0700);
            $context->throw($fName, "can't create temp dir $tmpDir")
                    if ( !-d $tmpDir );
            $fileName = File::Spec->catfile($tmpDir, "$texDoc.tex");
            $devnull  = File::Spec->devnull();
            if ( !open(FH, ">:encoding(UTF-8)", "$fileName") ) {
                rmtree($tmpDir);
                $context->throw($fName, "can't open $fileName for output");
            }
            print(FH $text);
            close(FH);

            # latex must run in tmpDir directory
            my $currDir = cwd();
            if ( !chdir($tmpDir) ) {
                rmtree($tmpDir);
                $context->throw($fName, "can't chdir $tmpDir");
            }
            #
            # We don't need to quote the backslashes on windows, but we
            # do on other OSs
            #
            my $LaTeX_arg = "\\nonstopmode\\input{$texDoc}";
            $LaTeX_arg = "'$LaTeX_arg'" if ( $^O ne 'MSWin32' );
            if ( system("$LaTeXPath $LaTeX_arg"
                   . " 1>$devnull 2>$devnull 0<$devnull") || (defined $cslatextwice && system("$LaTeXPath $LaTeX_arg"
								     . " 1>$devnull 2>$devnull 0<$devnull"))) {

		my $texErrs = "";
                $fileName = File::Spec->catfile($tmpDir, "$texDoc.log");
                if ( open(FH, "<$fileName") ) {
                    my $state = 0;
                    #
                    # Try to extract just the interesting errors from
                    # the verbose log file
                    #
                    while ( <FH> ) {
                        #
                        # TeX errors seems to start with a "!" at the
                        # start of the line, and are followed several
                        # lines later by a line designator of the
                        # form "l.nnn" where nnn is the line number.
                        # We make sure we pick up every /^!/ line, and
                        # the first /^l.\d/ line after each /^!/ line.
                        #
                        if ( /^(!.*)/ ) {
                            $texErrs .= $1 . "\n";
                            $state = 1;
                        }
                        if ( $state == 1 && /^(l\.\d.*)/ ) {
                            $texErrs .= $1 . "\n";
                            $state = 0;
                        }
                    }
                    close(FH);
                } else {
                    $texErrs = "Unable to open $fileName\n";
                }
                my $ok = chdir($currDir);
		rmtree($tmpDir);
                $context->throw($fName, "can't chdir $currDir") if ( !$ok );
                $context->throw($fName, "latex exited with errors:\n$texErrs");
            }

            if ( $output eq "ps" || $output eq "ps2pdf") {
                $fileName = File::Spec->catfile($tmpDir, "$texDoc.dvi");
                if ( system("$DviPSPath  $options $texDoc -o" . " 1>$devnull 2>$devnull 0<$devnull") ) {
                    my $ok = chdir($currDir);
		    rmtree($tmpDir);
                    $context->throw($fName, "can't chdir $currDir") if ( !$ok );
                    $context->throw($fName, "can't run $DviPSPath $fileName");
                }
            }

            if ( $output eq "ps2pdf" ) {
                $fileName = File::Spec->catfile($tmpDir, "$texDoc.ps");
                if ( system("$PS2PdfPath  $texDoc.ps " . " 1>$devnull 2>$devnull 0<$devnull") ) {
                    my $ok = chdir($currDir);
		    rmtree($tmpDir);
                    $context->throw($fName, "can't chdir $currDir") if ( !$ok );
                    $context->throw($fName, "can't run $PS2PdfPath $fileName");
                }
            }

            if ( !chdir($currDir) ) {
                rmtree($tmpDir);
                $context->throw($fName, "can't chdir $currDir");
            }

            my $retStr;
			$output = $output eq "ps2pdf" ? "pdf" : $output;
            $fileName = File::Spec->catfile($tmpDir, "$texDoc.$output");
            if ( open(FH, $fileName) ) {
                local $/ = undef;       # slurp file in one go
                binmode(FH);
                $retStr = <FH>;
                close(FH);
            } else {
                rmtree($tmpDir);
                $context->throw($fName, "Can't open output file $fileName");
            }
	    rmtree($tmpDir);
            return $retStr;
        }
    } else {
        $context->throw("$fName not yet supported on $^O OS."
                      . "  Please contribute code!!");
    }
# }}}
}

=head2 Filter sprintf

Filter provide sprintf funcionality as TT2 filter

=cut
sub sprintf {
# {{{
    my ($context, $format, $use_thousands_sep)  = @_;
    return sub {
        my $number = shift;
	my $formatted;
	if ( defined($number) ) {
		$number =~ s/,/./;
		my @number = map { $number } split(/[^\\]%/, $format);
		$formatted = sprintf($format, @number);
		if ( $use_thousands_sep && defined($number)) {
			my $lconv = POSIX::localeconv();
			if ( $formatted =~ /^(-*\d+)($lconv->{decimal_point})(\d+)(.*)$/ ) {
				my $decimal = $1;
				my $count = int( length($decimal) / 3 );
				my $output = "";
				for(my $i = 0; $i < $count; $i++ ) {
					$output = " " . substr($decimal, -3) . $output;
					$decimal = substr($decimal, 0, length($decimal) - 3);
				}
				$output = ( defined($decimal) ? $decimal : "") . $output;
				$formatted = $output . $2 . $3 . $4;
			} elsif ( $formatted =~ /^(-*\d+)$/ ) {
				my $decimal = $1;
				my $count = int( length($decimal) / 3 );
				my $output = "";
				for(my $i = 0; $i < $count; $i++ ) {
					$output = " " . substr($decimal, -3) . $output;
					$decimal = substr($decimal, 0, length($decimal) - 3);
				}
				$output = ($decimal ? $decimal : "") . $output;
				$formatted = $output;
			}
		}
	}
        return($formatted);
    }
# }}}
}

=head2 Filter utf8_email_header

Convert text to base64

=cut
sub utf8_email_header {
# {{{
	my ($context)  = @_;

	return sub{
		my $text = shift;
		my $eol = '';
		$text = encode_base64(encode("UTF-8", $text), $eol);
		chomp($text);
		$text = '=?UTF-8?B?'.$text.'?=';
		return($text);
	}
# }}}
}


sub hostaddress {
# {{{
	my ($context)  = @_;

	return sub{
		my $text = shift;
		if ( $text =~ /(\d{1,3}).(\d{1,3}).(\d{1,3}).(\d{1,3})/) {
			$text = "$1.$2.$3.$4";
		}
		return($text);
	}
# }}}
}

sub utf2iso {
# {{{
	my ($context)  = @_;

	return sub {
		my $text = shift;
		my $converter = Text::Iconv->new("UTF-8", "ISO-8859-2");
		return($converter->convert($text));
	}
# }}}
}

=head2  Filter csvclean

Covnert char ";" to ","

=cut
sub csvclean {
# {{{
	my ($context)  = @_;

	return sub{
		my $text = shift;
		$text =~ s/;/,/g;
		$text =~ s/\n/ /g;
		$text =~ s/\r/ /g;
		return($text);
	}
# }}}
}
=head2  Filter csvclean

Covnert char ";" to ","

=cut

sub default {
# {{{
	my ($context, $defaultvalue)  = @_;
	return sub {
		my $value = shift;
		return ($value) ? $value : $defaultvalue;
	};
# }}}
}

=head2  Filter perl_decode

Returns value decoded to perl internal encoding (unicode) from $charset

=cut

sub perl_decode {
# {{{
	my ($context, $charset)  = @_;
	return sub {
		my $value = shift;
		my $charset = shift;
		return Encode::decode($charset ? $charset : "utf-8", $value);
	};
# }}}
}

sub perl_encode {
# {{{
	my ($context, $charset)  = @_;
	return sub {
		my $value = shift;
		my $charset = shift;
		return Encode::encode($charset ? $charset : "utf-8", $value);
	};
# }}}
}

=head2 Filter remove_diacritic

Remove diacritic from text

=cut

sub remove_diacritic {
# {{{
	my ($context) = @_;
	return sub {
		my $text = shift;
		$text =~ tr/ŁĽŞŠŻłšşźžżŔÁÂĂÄĹĆÇČÉĘËĚÍÎĎĐŃŇÓÔŐÖŘŮÚŰÜÝŤŢŽŕáâăäĺćçčéęëěíîďđńňóôőöřůúűüýţť\x{fffd}/LLSSZlsszzzRAAAALCCCEEEEIIDDNNOOOORUUUUYTTZraaaalccceeeeiiddnnooooruuuuyttl/;
		return($text);
	};
# }}}
}

=head2  Filter a2ps

Create pdf from text
a2ps --center-title="dispatch note" --right-title="%Q" --left-title="" --header="" --right-footer="" --left-footer="" -1  -o /tmp/aa.ps *.txt
=cut

sub a2ps {
# {{{
	my ($context, $withNewPages, $title, $charsPerLine) = @_;
	return sub {
		my $text = shift;
		my $tmpDir = tempdir("/tmp/dispatchnote-a2ps-XXXXX");
		my $output = "";

		my @fileNames = ();

		if ($withNewPages){
			my @pages = split (/<newpage\/>[\ \t\n]*/,$text);
			my $count = 1;
			foreach my $page (@pages){
				my $filename = File::Spec->catfile($tmpDir, sprintf("page-%02d.txt",$count));
				$count += 1;
				
				open (FH,"> $filename") or die "cannot open $filename: $!";
				print FH $page;
				close (FH);

				push @fileNames, $filename;
			};
		} else {
			my $filename = File::Spec->catfile($tmpDir, "text.txt");
			open (FH, "> $filename") or die "cannot open $filename: $!";
			print FH $text;
			close FH;
			push @fileNames, $filename;
		}
		my $psfile = File::Spec->catfile($tmpDir,"result.ps");
		my $pdffile = File::Spec->catfile($tmpDir,"result.pdf");
		my $cmd = sprintf('a2ps --title="%s" --center-title="%s" --right-title="%Q" --left-title="" --borders=0 --no-header --right-footer="" --left-footer="" --chars-per-line=%d --columns=1 -o "%s" %s 2> /dev/null 1> /dev/null',
				  $title,
				  $title,
				  $charsPerLine,
				  $psfile,
				  join(" ", @fileNames)
		    );
		if( system($cmd) == 0 ){
			$cmd = sprintf("ps2pdf '%s' '%s'",$psfile,$pdffile);
			if( system($cmd) == 0 ){
				if ( open(FH, $pdffile) ) {
					local $/ = undef;       # slurp file in one go
					binmode(FH);
					$output = <FH>;
					close(FH);
				};
			};
		};
		rmtree($tmpDir);
		return $output;
	};
# }}}
};

1;
