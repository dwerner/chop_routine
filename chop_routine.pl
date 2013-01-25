#!/usr/bin/perl
#
# For chopping routines out of existing bbj programs
# this is helpful when trying to untangle spaghetti code.
# 
# - recursively parses a bbj program from LABEL: to RETURN - keeping in mind scope.
# - numbered line programs not supported currently.
#
# example useage: perl chop_routine.pl <program name> <routine_name>
#
# Author and Copyright: Daniel Werner danwerner(at)gmail(dot)com - Oct 2009
#
#  	 This program is free software: you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation, either version 3 of the License, or
#    (at your option) any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program.  If not, see <http://www.gnu.org/licenses/>

use strict;
use warnings;
use Data::Dumper;

#chop_routine.pl
my $version = 1;

# open a file and chop out a routine by name
my $routine = $ARGV[1];
# die "no routine given \n" unless $routine;

my $program = $ARGV[0];
die "no filename given to chop from\n" unless $program;

my $open_files_in_editor = 0;
my $open_skeleton = 1;

my $editor = "geany";

my $already_done = $routine . "-<";

# Keywords used to parse the code - add key = key to exclude keywords
my $keywords = {
		"scope_up"				=> 	"if",
		"scope_down"			=> 	"endif",	
		"scope_up_condition"	=>	"then",	
		"start_loop"		=>  	"while", 
		"end_loop"			=>    	"wend", 	
		"start_loop"		=>  	"for",   
		"end_loop_step"     =>		"next",	
		"comment"			=>     	"rem",	
		"scrape_end"		=>  	"return",
		"branch"			=>      "break",	
		"subroutine"		=>      "gosub",	
		"goto" 				=> 		"goto",
		"statement_sep"		=>		";",
		"iolist_reference"	=>		"iol=",
		"iolist_definition"	=> 		"iol:",
		"else" 				=> 		"else",
			"dom"			=> 		"dom",
			"key"   		=> 		"key",
			"not"   		=> 		"not",
			"find"   		=> 		"find",
			"knum"  		=> 		"knum",
			"scrape_end2" 	=> 		"end",
			"scrape_end3" 	=> 		"retry",
			"let"   		=> 		"let",
			"and" 			=> 		"and",
			"read" 			=> 		"read",
			"to" 			=> 		"to",
			"err" 			=> 		"err",
			"write" 		=> 		"write"
};

# The lines in order of the routine that has been scraped from the program specified
my @routine = ();

# All gosubbed routines
my @gosubs = ();
my $all_gosubs = {};

# All iolists referenced by this parent file
my $iolists = {};

#Only iolists referenced by this routine
my $routine_iolists = {};

# Only iolists referenced directly by this routine
my @iolists_referenced = ();
	
# All variables used in this routine (could be globals!)
my $variables = {};

# All static text elements from the file (" quote enclosed text)
my @static_text = ();

my @reads_and_writes = ();

#all labels in parent program
my $all_labels = {};

#map for generated program enter lists
my $routine_enter_lists = {};
my $autogen_called_progs = {};

my @labels =();

my @skeleton = ();

open(FILE, $program) or die "Could not open ".$program.": " .$!;
my @lines = <FILE>; 
close(FILE);


main();

sub main{
	if ($routine) {
		process();
		print "Paths: ".$already_done."\n";
	} else {
		# Scraper doesnt get turned on in this first iteration - so we search 
		# through the program looking for all labels that are reached by gosub 
		process();
		open (RPTFILE, ">subroutines.txt");
		print RPTFILE "Subroutine scrape report\n";
		foreach my $label( keys %{$all_labels} ){
			foreach my $gosub ( keys %{$all_gosubs} ) {
				if ($label eq $gosub){
					$routine = $gosub;
					print RPTFILE $gosub ."\n";
					process();
				}
			}
		# print "Paths: ".$already_done."\n";
		}
		close(RPTFILE);
		writeSkeleton();
	}
}

sub process {
	scanFile();
	processRoutine();
	createChopFile();
}

sub writeSkeleton {
	# so this is a bit of a special case
	# in scanFile, we decide what areas are scraped out into called programs, so here we want to build a skeleton
	# that approximates the original monolithic program, while replacing the bodies of the subroutines scraped out with calls to them
	
	my $shortname = $program ."-SKELETON";
	$shortname =~ s/.bbj//gi;
	$shortname =~ s/://gi;
	open (SKEL, ">".$shortname.".bbj");
	my $rscraper = "OFF";
	my $scope_count = 0;
	
	foreach my $line (@lines){
		if ( $line =~ /^\w+:/i ) {
			if( $line =~ /:/ ){
				my $holder = $`;
				foreach my $routine (keys %{$all_gosubs}){
					if ($routine eq $holder){
						$rscraper = "ON";
						print SKEL "REM Auto-generated subroutine\n";
						print SKEL $routine.":\n";
						my $enterlist = $routine_enter_lists->{$routine};
						$enterlist =~ s/ENTER\s//gi;
						print SKEL "CALL \"".$autogen_called_progs->{$routine}."\",".$enterlist."\n";
						print SKEL "RETURN\n";
						$scope_count = 1;
					}
				}
			}
		}
		
		if ($rscraper eq "OFF") {
			print SKEL $line . "\n";
		} elsif ($rscraper eq "ON") {
			
			#certain keywords up the scope, like IF 
			if ( $line =~ /$keywords->{"scope_up"}\s+/i and $line =~ /$keywords->{"scope_up_condition"}\s+$/i ){
				$scope_count = $scope_count+1;
			} elsif ($scope_count > 0 and $line =~ /$keywords->{"scope_down"}/i){	
				$scope_count = $scope_count-1;
			}
			
			#if theres an endif
			if (($line =~ /^($keywords->{"scrape_end"}|$keywords->{"scrape_end2"}|$keywords->{"scrape_end3"})/i or
				 $line =~ /^\w:\s($keywords->{"scrape_end"}|$keywords->{"scrape_end2"}|$keywords->{"scrape_end3"})$/i) 
				and $scope_count <= 1) {
				$rscraper = "OFF";
			}
		}
		
	}
	close(SKEL);
	print "Skeleton program written to: ".$shortname.".bbj\n";
	
	if ($open_skeleton){
		print "Opening ". $shortname.".bbj in editor.\n";
		system($editor . " " . $shortname.".bbj &");
	}
}

# Ensure that RETURNS don't end the scraping prematurely if they are in any nested scope
sub scanFile {
	my $scraper = "OFF";
	my $routine_scraper = "OFF";
	my $skel_routine = "";
	my $scope_count = 0;
	my $rscope_count = 0;

	$all_labels = {};
	$all_gosubs = {};

	foreach my $line (@lines){

		chomp($line);
		
		# we end up with ALL iolists because of this, but we compare with the routine later
		if ($line =~ /\_$keywords->{"iolist_definition"}/i){
			$iolists->{$`."_IOL"}=$line;
		}	
		
		#list of all labels in program
		if ( $line =~ /^\w+:/i ) {
			if( $line =~ /:/ ){
				$all_labels->{$`}+=1;
			}
		}

		#if there's a gosub, then grab it's routine name
		if ( $line =~ /$keywords->{"subroutine"}\s+/i ){
			$all_gosubs->{$'}+=1;
		}

		if ($routine and $line =~ /$routine:/i) {
			$scope_count = 1;
			$scraper = "ON";
		}

		if ($scraper eq "ON") {
			
			push(@routine, $line);
			#print $line."\n"; 
			
			if ( $line !~ /^\s*$keywords->{"comment"}\s+/i ){
				
				#insert iolists
				foreach my $iolist (keys %{$iolists}){
					if ($line =~ /IOL=/i){
						my $holder = $';
						if ($holder =~ /$iolist/){
							$routine_iolists->{$iolist}+=1;
						}	
					}
				}
				
				if ( $line =~ /$keywords->{"comment"}\s+/i )	{
					$line = $`;
				}
				
				#Labels	
				if ($line =~ /^[A-Za-z]+\w*:/i){
					if ($line =~ /:/i){
						push(@labels, $`);
					}
				}
				#certain keywords up the scope, like IF 
				if ( $line =~ /$keywords->{"scope_up"}\s+/i and $line =~ /$keywords->{"scope_up_condition"}\s+$/i ){
					$scope_count = $scope_count+1;
				} elsif ($scope_count>0 and $line =~ /$keywords->{"scope_down"}/i){	
					$scope_count = $scope_count-1;
				}
				
				#if there's a gosub, then grab it's routine name
				if ( $line =~ /$keywords->{"subroutine"}\s+/i ){
					push (@gosubs, $');
				}
				
				#if theres an endif
				if (($line =~ /^($keywords->{"scrape_end"}|$keywords->{"scrape_end2"}|$keywords->{"scrape_end3"})/i or
					 $line =~ /^\w:\s($keywords->{"scrape_end"}|$keywords->{"scrape_end2"}|$keywords->{"scrape_end3"})$/i) 
					and $scope_count <= 1) {
					$scraper = "OFF";
				}
			} 
		}
	}
}

sub processRoutine {
	my $linecount = 0;
	foreach my $line (@routine){
		my $pline = $line;
		
		$linecount=$linecount+1;
		if ( $pline !~ /^\s*$keywords->{"comment"}\s/i ){

			if ($pline =~ /$keywords->{"comment"}\s+/i)	{
				$pline = $`;
			}

			if ( $pline =~ /\w*$keywords->{"iolist_reference"}=/i ){
				push ( @iolists_referenced, $iolists->{$'} );
			}

			while ($pline =~ /([A-Za-z]+\w*\$|[A-Za-z]+\w*\!|[A-Za-z]+\w*)/gi ){
				my $kw_flag = 0;

				if ($1) {
					my $linematch = $1;
					my $whole_line = $`.$1.$';
					
					foreach my $keyword (values %{$keywords}){
						$kw_flag = 1 if ( $linematch =~ /\b$keyword\b/i );
					}		

					#excludes java method calls from variable list
					$kw_flag = 1 if ($whole_line =~ /$linematch\s*\$*\(+/i);

					foreach my $sub (@gosubs){					
						$kw_flag = 1 if ($sub =~ /$linematch/i);
					}
					
					foreach my $sub (keys %{$iolists}){					
						$kw_flag = 1 if ($sub =~ /$linematch/i);
					}

					if (!$kw_flag){
						if ($whole_line=~/\"$linematch\"/i){
							push(@static_text, "\"".$linematch."\"");
						} elsif ($whole_line=~/$linematch:/i){
							#do nothing on labels
						} elsif ($whole_line=~/$linematch=/i){
							$variables->{$linematch}=$whole_line;
						} elsif ($whole_line=~/=$linematch/i){
							$variables->{$linematch}=$whole_line;
						} else {
							$variables->{$linematch}=$whole_line;
						}
					}
				}
			}

			push ( @reads_and_writes, $pline ) if ( $pline =~ /($keywords->{"read"}\s*\(|$keywords->{"write"}\s*\()/i );
		}	
	}
}


sub createChopFile {
	
	if ($routine =~ /(;|\s)/){
		$routine = $`;
	}
	my $shortname = $program ."-". $routine;
	$shortname =~ s/.bbj//gi;
	$shortname =~ s/://gi;

	my $chopfile = $shortname.".bbj";
	
	open(FILE, ">".$chopfile);
	print FILE "REM $chopfile\n";
	print FILE "REM Subroutine template generated automatically from ".$program." using chop_routine.pl script - v".$version."\n";
	print FILE "REM \n";

	print FILE "REM << Subroutines from parent ".$program." referenced (now comverted as well)>> \n";
	foreach my $sub ( @gosubs ){
		print FILE "REM \t". $sub . "\n";
	}
	print FILE "REM \n";
	print FILE "REM << Reads and Writes >> \n";
	foreach my $fileop ( @reads_and_writes ){
		print FILE "REM \t". $fileop . "\n";
	}
	print FILE "REM \n";

	print FILE "REM < Objects > \n";
	foreach my $variable ( sort keys %{$variables} ){
		print FILE "REM \t". $variable . "\n" if ($variable=~/\!/);
	}
	print FILE "REM \n";
	
	print FILE "REM < Strings > \n";
	foreach my $variable ( sort keys %{$variables} ){
		print FILE "REM \t". $variable . "\n" if ($variable=~/\$/);
	}
	
	print FILE "REM \n";	

	print FILE "REM < Numbers and channels > \n";
	foreach my $variable ( sort keys %{$variables} ){
		print FILE "REM \t". $variable . "\n" if ($variable!~/(\$|\!)/);
	}
	
	print FILE "REM \n";
	print FILE "REM < Static text found > \n";
	foreach my $text ( @static_text ){
		print FILE "REM \t". $text . "\n" if ($text!~/(\$|\!)/);
	}
	
	print FILE "\n\n";
	
	#Generate IOLISTS
	print FILE "REM Auto-generated iolists:\n";
	foreach my $iolist ( keys %{$routine_iolists} ){
		print FILE "REM ".$iolist."\n";
		print FILE $iolists->{$iolist} . "\n\n";
	}
	
	#Generate ENTER list
	print FILE "REM Auto-generated ENTER list\n";
	my $enterlist = "ENTER ";
	foreach my $variable ( sort keys %{$variables} ){
		$enterlist .= $variable . ",";
	}
	
	chop($enterlist); # manually be rid of the last comma
	
	$autogen_called_progs->{$routine} = $chopfile;
	$routine_enter_lists->{$routine} = $enterlist;
	
	print FILE $enterlist."\n";
	print FILE "SETERR ERROR_ROUTINE\n";
	print FILE "GOSUB ".$routine."\n";
	print FILE "EXIT\n\n";

	foreach my $line (@routine){
		print FILE $line."\n";
	}

	print FILE "\n\nREM Automatically push errors up to the calling program.\n";
	print FILE "ERROR_ROUTINE:\n";
	print FILE "if err then throw \"P:\"+pgm(-2)+\"L:\"+tcb(5)+\"M:\"+errmes(-1),err";
	print FILE "RETRY\n";

	close(FILE);
	print "Output from " . $program . " stored in ".$chopfile."\n";
	
	if ($open_files_in_editor){
		print "Opening ". $chopfile . " in editor.\n";
		system($editor . " " . $chopfile . "&");
	}
	
	$already_done .= $routine."->";
	# For each gosub referenced, spider down into that file as well (yes this is recursive)
	foreach my $gosub (@gosubs){
		if ($already_done !~ /$gosub/i){
			
			$routine = $gosub;
			
			@routine = ();
			@gosubs = ();
			$iolists = {};
			$routine_iolists = {};
			@iolists_referenced = ();
			$variables = {};
			@static_text = ();
			@reads_and_writes = ();
			@labels =();
			
			process();
		}
	}
}

