/* vertigro v1.1 - Automatically grow your textarea vertically.
   Copyright (C) 2009 Paul Pham <http://jquery.aquaron.com/vertigro>

   This program is free software: you can redistribute it and/or modify
   it under the terms of the GNU General Public License as published by
   the Free Software Foundation, either version 3 of the License, or
   (at your option) any later version.

   This program is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
   GNU General Public License for more details.

   You should have received a copy of the GNU General Public License
   along with this program.  If not, see <http://www.gnu.org/licenses/>.
*/
(function($){
   $.fn.vertigro = function($max,$div) {
      return this.filter('textarea').each(function() {
         var grow = function(e) {
            if ($max && $div) {
               if ($(this).val().length > $max && e.which != 8)
                  return false;
               $('#'+$div).html($max-$(this).val().length);
            }
            if (this.clientHeight < this.scrollHeight)
               $(this).height(this.scrollHeight
               + (parseInt($(this).css('lineHeight').replace(/px$/,''))||20)
               + 'px');
         };
         $(this).css('overflow','hidden').keydown(grow).keyup(grow).change(grow);
      });
   };
})(jQuery);
