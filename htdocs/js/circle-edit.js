previewOn = 0;
lastFriend = 0;

function setFriend (curfriend)
{
    lastFriend = curfriend;
}

function togglePreview()
{
   if (previewOn==0 || winPreview.closed) {
       winPreview = window.open("", "preview", "toolbar=0,location=0,directories=0,status=0,menubar=0,scrollbars=0,resizable=0,copyhistory=0,width=400,height=270");
       previewOn = 1;
       updatePreview();
   } else {
       winPreview.close();
       previewOn = 0;
   }
}

function updatePreview () {

    if (previewOn == 0 || winPreview.closed) { return; }

    frm = document.editFriends;

    dropdown = frm["editfriend_add_"+lastFriend+"_fg"]
    if (!dropdown) {
        winPreview.close();
        previewOn = 0;
        alert('You have not added any friends to preview');
        return;
    }
    fg_color = dropdown.options[dropdown.selectedIndex].value;
    fg_color_text = dropdown.options[dropdown.selectedIndex].text;

    dropdown = frm["editfriend_add_"+lastFriend+"_bg"]
    bg_color = dropdown.options[dropdown.selectedIndex].value;
    bg_color_text = dropdown.options[dropdown.selectedIndex].text;

    user_name = frm["editfriend_add_"+lastFriend+"_user"].value;
    if (user_name.length==0) { user_name = "username"; }

    d = winPreview.document;
    d.open();
    d.write("<html><head><title>$ejs{'mrcolor'}</title></head><body bgcolor='#ffffff' text='#000000'>");
    d.write("<b><font face='Trebuchet MS, Arial, Helvetica' size='4' color='#000066'><i>$ejs{'viewer'}</i></font></b><hr />");
    d.write("<br /><table summary='' width='350' align='center' cellpadding='5'><tr valign='middle'>");
    d.write("<td width='80%'><b><font face='Arial, Helvetica' size='2'>");
    d.write("$ejs{'textcolor'}&nbsp; <font color='#000066'>" + fg_color_text);
    d.write("</font></b><br /></td><td width='20%' bgcolor=" + fg_color + ">&nbsp;</td>");
    d.write("</tr><tr><td width='80%'><b><font face='Arial, Helvetica' size='2'>");
    d.write("$ejs{'bgcolor'}&nbsp; <font color='#000066'>" + bg_color_text + "");
    d.write("</font></b><br></td><td width='20%' bgcolor=" + bg_color + ">&nbsp;</td>");
    d.write("</tr><tr><td><br /></tr><tr><td colspan='3' bgcolor=" + bg_color + "><font color=" + fg_color + ">");
    d.write("<b>" + user_name + "</b></td></tr></table><br />");
    d.write("<hr><form><div align='center'><input type='button' value='$ejs{'btn.close'}' onClick='self.close();'></div></form>");
    d.write("</body></html>");
    d.close();
}
