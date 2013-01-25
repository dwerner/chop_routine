chop_routine
============

perl script for chopping apart BBj programs into subroutines

 For chopping routines out of existing bbj programs
 this is helpful when trying to untangle spaghetti code.
 
 - recursively parses a bbj program from LABEL: to RETURN - keeping in mind scope.
 - numbered line programs not supported currently.

 example useage: perl chop_routine.pl <program name> <routine_name>

 Author and Copyright: Daniel Werner danwerner(at)gmail(dot)com - Oct 2009

     This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program.  If not, see <http://www.gnu.org/licenses/>
