package Syntax::Highlight::Engine::Simple;
use warnings;
use strict;
use Carp;
use UNIVERSAL::require;
#use version;
our $VERSION = '0.03';

### ----------------------------------------------------------------------------
### constractor
### ----------------------------------------------------------------------------
sub new {
	
	my $class = shift;
	my $self =
        bless {type => undef, syntax  => undef, @_}, $class;
	
	$self->setParams(@_);
	
	if ($self->{type}) {
			
		my $class = "Syntax::Highlight::Engine::Simple::". $self->{type};
		
		$class->require or croak $@;
		
		no strict 'refs';
		&{$class. "::setSyntax"}($self);
		
		return $self;
	}
	
	$self->setSyntax();
	
	return $self;
}

### ----------------------------------------------------------------------------
### set params
### ----------------------------------------------------------------------------
sub setParams {
	
	my $self = shift;
	
	my %args = (
		html_escape_code_ref => \&_html_escape,
		@_);

	$self->{html_escape_code_ref} = $args{html_escape_code_ref};
}

### ----------------------------------------------------------------------------
### set syntax
### ----------------------------------------------------------------------------
sub setSyntax {
	
	my $self = shift;
	my %args = (syntax => [], @_);
    
	$self->{syntax} = $args{syntax};
}

### ----------------------------------------------------------------------------
### append syntax
### ----------------------------------------------------------------------------
sub appendSyntax {
	
	my $self = shift;
	my %args = (
		syntax => {
			regexp		=> '',
			class		=> '',
			container	=> undef,
		}, @_);
    
	push(@{$self->{syntax}}, $args{syntax});
}

### ----------------------------------------------------------------------------
### Highlight multi Line
### ----------------------------------------------------------------------------
sub doStr{
	
	my $self = shift;
	my %args = (str => '', tab_width => -1, @_);
	
	defined $args{str} or croak 'doStr method got undefined value';
	
	if ($args{tab_width} > 0) {
		
		my $tabed = '';
		
		foreach my $line (split(/\r\n|\r|\n/, $args{str})) {
			
			$tabed .=
				&_tab2space(str => $line, tab_width => $args{tab_width}). "\n";
		}
		
		$args{str} = $tabed;
	}
	
	return $self->_doLine(str => $args{str});
}

### ----------------------------------------------------------------------------
### Highlight file
### ----------------------------------------------------------------------------
sub doFile {
	
	my $self = shift;
	my %args = (
		file => '',
		tab_width => -1,
		encode => 'utf8',
		@_);
	
	my $str = '';
	
	require 5.005;
	
	open(my $filehandle, '<'. $args{file}) or croak 'File open failed';
	binmode($filehandle, ":encoding($args{encode})");
	
	while (my $line = <$filehandle>) {
		
		if ($args{tab_width} > 0) {
			
			$line = &_tab2space(str => $line, tab_width => $args{tab_width});
		}
		
		$str .= $line;
	}
	
	close($filehandle);
	
	return $self->_doLine(str => $str);
}

### ----------------------------------------------------------------------------
### Highlight single line
### ----------------------------------------------------------------------------
sub _doLine {
	
	my $self = shift;
	my %args = (
		str			=> '', 
		@_);
	
	my $str = $args{str}; $str =~ s/\r\n|\r/\n/g;
	
	$self->{_markup_map} = [];

	### make markup map
	my $size = scalar @{$self->{syntax}};
	for (my $i = 0; $i < $size; $i++) {
		
		my $synatax_ref = $self->{syntax}->[$i];
		$self->_make_map(str => $str, syntax => $synatax_ref, index => $i);
	}
	
	if (! scalar @{$self->{_markup_map}}) {
		
		return $args{str}
	}

	my $outstr = '';
	my @markup_array = $self->_restracture_map();
	my $last_pos = 0;
	
	### Apply the map to string
	foreach my $pos (@markup_array) {
		
		my @record = @$pos;
		
		my $str_left = substr($str, $last_pos, $record[0] - $last_pos);
		
		no strict 'refs';
		$str_left = &{$self->{html_escape_code_ref}}($str_left);
		
		if (defined $record[1]) {
			
			$outstr .=
				$str_left.
				sprintf( "<span class='%s'>", $record[1]->{class});
		} 
		
		else {
			
			$outstr .= $str_left. '</span>';
		}
		
		$last_pos = $record[0];
	}
	
	no strict 'refs';
	$outstr .= &{$self->{html_escape_code_ref}}(substr($str, $last_pos));
	
	return $outstr;
}

### ----------------------------------------------------------------------------
### Make markup map
### ---------------------------------------------
### | open_pos  | close_pos | syntax_ref | index
### | open_pos  | close_pos | syntax_ref | index
### | open_pos  | close_pos | syntax_ref | index
### ---------------------------------------------
### ----------------------------------------------------------------------------
sub _make_map {
	
	no warnings; ### Avoid Deep Recursion warning
	
	my $self = shift;
	my %args = (str => '', pos => 0, syntax => '', @_);
	
	my $map_ref = $self->{_markup_map};
	
	my @scraps =
		split(/$args{syntax}->{regexp}/, $args{str}, 2);

	if ((scalar @scraps) >= 2) {
		
		my $rest = pop(@scraps);
		my $ins_pos0 = $args{pos} + length($scraps[0]);
		my $ins_pos1 = $args{pos} + (length($args{str}) - length($rest));
		
		### Add markup position
        push(
            @$map_ref, [
                $ins_pos0,
                $ins_pos1,
                $args{syntax},
				$args{index},
            ]
        );
		
		### Recurseion for rest
		$self->_make_map(%args, str => $rest, pos => $ins_pos1);
	}
	
	### Follow up process
	elsif (@$map_ref) {
		
		@$map_ref =
			sort {
				${$a}[0] <=> ${$b}[0] or
				${$b}[1] <=> ${$a}[1] or
				${$a}[3] <=> ${$b}[3]
			} @$map_ref;
	}

	return;
}

### ----------------------------------------------------------------------------
### restracture the map data into following format
### --------------------
### | open_pos  | class 
### | close_pos |       
### | open_pos  | class 
### | close_pos |       
### --------------------
### ----------------------------------------------------------------------------
sub _restracture_map {
	
	my $self = shift;
	my $map_ref = $self->{_markup_map};
	my @out_array;
	my $_max_close_pos = 0;
	
	REGLOOP: for (my $i = 0; $i < scalar @$map_ref; $i++) {
		
		my $allowed_container = $$map_ref[$i]->[2]->{container};
		my $ok = 1;
		
		### Remove illigal overlap
		if ($i > 1 and
			$$map_ref[$i]->[0] < $$map_ref[$i - 1]->[1] and 
			$$map_ref[$i]->[1] > $$map_ref[$i - 1]->[1]) {
			
			$ok = 0;
		}
		
		### entry without allow-array never can be a daughter
		### entry with allow-array must have mother at least
		elsif (! $allowed_container and $_max_close_pos >= $$map_ref[$i]->[1] or
			$allowed_container and $_max_close_pos < $$map_ref[$i]->[1]) {
			
			$ok = 0;
		}
		
		elsif ($allowed_container) {
			
			$ok = 0;
			
			### Search for container
			BACKWARD: for (my $j = $i - 1; $j >= 0; $j--) {
				
				### found
				if ($$map_ref[$j]->[1] >= $$map_ref[$i]->[1]) {
					
					### allowed container?
					if ($$map_ref[$j]->[2]->{class} eq $allowed_container) {
						
						### yes
						$ok = 1;
					}
					
					last BACKWARD;
				}
			}
		}
		
		if (! $ok) {
			
			splice(@$map_ref, $i--, 1);
			next REGLOOP;
		}
		
		if ($_max_close_pos < $$map_ref[$i]->[1]) {
			
			$_max_close_pos = $$map_ref[$i]->[1];
		}
		
		### no-class records won't be marked up
		### but being evaluated for Embracement control of others
		if (! $$map_ref[$i]->[2]->{class}) {
			
			next REGLOOP;
		}
		
		push(
			@out_array,
			[$$map_ref[$i]->[0], $$map_ref[$i]->[2]],
			[$$map_ref[$i]->[1]]
		);
	}
	
	return sort {$a->[0] <=> $b->[0]} @out_array;
}

### ----------------------------------------------------------------------------
### Return map for debug
### ----------------------------------------------------------------------------
sub _ret_map {
	
	#return shift->{_markup_map};
}

### ----------------------------------------------------------------------------
### replace tabs to spaces
### ----------------------------------------------------------------------------
sub _tab2space {
	
	no warnings; ### Avoid Deep Recursion warning
	
	my %args = (str => '', tab_width => 4, @_);
	my @scraps = split(/\t/, $args{str}, 2);
	
	if (scalar @scraps == 2) {
		
		my $num = $args{tab_width} - (length($scraps[0]) % $args{tab_width});
		my $right_str = &_tab2space(%args, str => $scraps[1]);
		
		return ($scraps[0]. ' ' x $num. $right_str);
	}
	
	return $args{str};
}

### ----------------------------------------------------------------------------
### convert array to regexp
### ----------------------------------------------------------------------------
sub array2regexp {
	
    my $self = shift;
	
	return sprintf('\\b(?:%s)\\b', join('|', @_));
}

### ----------------------------------------------------------------------------
### convert array to regexp
### ----------------------------------------------------------------------------
sub getClassNames {
	
	return map {${$_}{class}} @{shift->{syntax}}
}

### ----------------------------------------------------------------------------
### HTML escape
### ----------------------------------------------------------------------------
sub _html_escape {
	
	my ($str) = @_;
	
	$str =~ s/&/&amp;/g;
	$str =~ s/</&lt;/g;
	$str =~ s/>/&gt;/g;
	
	return $str;
}

1; # Magic true value required at end of module
__END__

=head1 NAME

Syntax::Highlight::Engine::Simple - Simple Syntax Highlight Engine

=head1 VERSION

This document describes Syntax::Highlight::Engine::Simple version 0.0.1

=head1 SYNOPSIS

	use Syntax::Highlight::Engine::Simple;
	
	# Constractor
	$highlight = Syntax::Highlight::Engine::Simple->new(%hash);
	
	# Parameter configuration
	$highlight->setParams(%hash);
	
	# Syntax definision and addition
	$highlight->setSyntax(%hash);
	$highlight->appendSyntax(%hash);
	
	# Perse
	$highlight->doFile(%hash);
	$highlight->doStr(%hash);
	
	# Utilities
	$highlight->array2regexp(%hash);
	$highlight->getClassNames(%hash);

=head1 DESCRIPTION

This is a Syntax highlight Engine.

Advantages are as follows.

=over

=item Simple

Provides you a simple interface for syntax definition by packing the
complicated part of rules into regular expression.

=item Fast

This works much Faster than Text::VimColor or Syntax::Highlight::Engine::Kate.

=item Pure Perl

=back

Here is a working example of This module.

http://jamadam.com/dev/cpan/demo/Syntax/Highlight/Engine/Simple/

=head1 INTERFACE 

=head2 new

=over

=item type

File type. This argument causes specific sub class to be loaded.

=item syntax

With this argument, you can assign rules in constractor.

=back

=head2 setParams

=over

=item html_escape_code_ref

HTML escape code ref. Default subroutine escapes 3 charactors '&', '<' and '>'.

=back

=head2 setSyntax

Set the rules for highlight. It calles for a argument I<syntax> in array.

=over

	$highlighter->setSyntax(
	    syntax => [
                {
                    class => 'quote',
                    regexp => "'.*?'",
                    container => 'tag',
                },
                {
                    class => 'wquote',
                    regexp => '".*?"',
                    container => 'tag',
                },
	    ]
	);

=back

The array can contain rules in hash which is consists of 3 keys, I<class>,
I<regexp> and I<container>.

=over

=item class

This appears to the output SPAN tag. 

=item regexp

Regular expression to be highlighted.

=item container

A class name of allowed container. This restricts the regexp to stand only in
the classes. This parameter also works to ease the regulation some time. The
highlighting rules doesn't stand in any container in default. This parameter
eliminates it.

=back

=head2 appendSyntax

Append syntax by giving a hash.

=over

	$highlighter->setSyntax(
	    syntax => {
	        class => 'quote',
	        regexp => "'.*?'",
	        container => 'tag',
	    }
	);

=back

=head2 doStr

Highlighting strings.

	$highlighter->doStr(
	    str => $str,
	    tab_width => 4
	);

=over

=item str

String.

=item tab_width

Tab width for tab-space conversion. -1 for disable it. -1 is the defult.

=back

=head2 doFile

Highlighting files.

	$highlighter->doStr(
	    str => $str,
	    tab_width => 4,
	    encode => 'utf8'
	);

=over

=item file

File name.

=item tab_width

Tab width for tab-space conversion. -1 for disable it. -1 is the defult.

=item encode

Set the encode of file. utf8 is the default.

=back

=head2 array2regexp

This is a utility method for converting string array to regular expression.

=over

=back

=head2 getClassNames

Returns the class names in array.

=over

=back

=head1 DIAGNOSTICS

=over

=item C<< doStr method got undefined value >>

=item C<< File open failed >>

=back

=head1 CONFIGURATION AND ENVIRONMENT

Syntax::Highlight::Engine::Simple requires no configuration files or
environment variables. Specific language syntax can be defined with
sub classes and loaded in constractor if you give it the type argument.

=head1 DEPENDENCIES

=over

=item L<UNIVERSAL::require>

=item L<encoding>

=back

=head1 INCOMPATIBILITIES

None reported.

=head1 BUGS AND LIMITATIONS

No bugs have been reported.

Please report any bugs or feature requests to
C<bug-syntax-highlight-engine-Simple@rt.cpan.org>, or through the web
interface at L<http://rt.cpan.org>.

=head1 SEE ALSO

=over

=item L<Syntax::Highlight::Engine::Simple::HTML>

=item L<Syntax::Highlight::Engine::Simple::Perl>

=back

=head1 AUTHOR

Sugama Keita  C<< <sugama@jamadam.com> >>


=head1 LICENCE AND COPYRIGHT

Copyright (c) 2008, Sugama Keita C<< <sugama@jamadam.com> >>. All rights
reserved.

This module is free software; you can redistribute it and/or
modify it under the same terms as Perl itself. See I<perlartistic>.


=head1 DISCLAIMER OF WARRANTY

BECAUSE THIS SOFTWARE IS LICENSED FREE OF CHARGE, THERE IS NO WARRANTY
FOR THE SOFTWARE, TO THE EXTENT PERMITTED BY APPLICABLE LAW. EXCEPT WHEN
OTHERWISE STATED IN WRITING THE COPYRIGHT HOLDERS AND/OR OTHER PARTIES
PROVIDE THE SOFTWARE "AS IS" WITHOUT WARRANTY OF ANY KIND, EITHER
EXPRESSED OR IMPLIED, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE. THE
ENTIRE RISK AS TO THE QUALITY AND PERFORMANCE OF THE SOFTWARE IS WITH
YOU. SHOULD THE SOFTWARE PROVE DEFECTIVE, YOU ASSUME THE COST OF ALL
NECESSARY SERVICING, REPAIR, OR CORRECTION.

IN NO EVENT UNLESS REQUIRED BY APPLICABLE LAW OR AGREED TO IN WRITING
WILL ANY COPYRIGHT HOLDER, OR ANY OTHER PARTY WHO MAY MODIFY AND/OR
REDISTRIBUTE THE SOFTWARE AS PERMITTED BY THE ABOVE LICENCE, BE
LIABLE TO YOU FOR DAMAGES, INCLUDING ANY GENERAL, SPECIAL, INCIDENTAL,
OR CONSEQUENTIAL DAMAGES ARISING OUT OF THE USE OR INABILITY TO USE
THE SOFTWARE (INCLUDING BUT NOT LIMITED TO LOSS OF DATA OR DATA BEING
RENDERED INACCURATE OR LOSSES SUSTAINED BY YOU OR THIRD PARTIES OR A
FAILURE OF THE SOFTWARE TO OPERATE WITH ANY OTHER SOFTWARE), EVEN IF
SUCH HOLDER OR OTHER PARTY HAS BEEN ADVISED OF THE POSSIBILITY OF
SUCH DAMAGES.

=cut
