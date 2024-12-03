var selectedGroup = 0;

 function eraseList (list)
 {
     while (list.length) {
         list.options[0] = null;
     }
 }
 
 function groupClicked ()
 {
     var selIndex;

     var form = document.fg;
     var grouplist = form.list_groups;
     var inlist = form.list_in;
     var outlist = form.list_out;
     
     // figure out what they clicked, and bring their focus up to first free blank

     selIndex = grouplist.selectedIndex;
     if (selIndex == -1) { return; }
     var groupname = grouplist.options[selIndex].text;

     var newSelGroup = grouplist.options[selIndex].value;
     if (newSelGroup == selectedGroup) { return; }
     selectedGroup = newSelGroup;
     
     // clears the other "not in" and "in" boxes
     eraseList(inlist);
     eraseList(outlist);

     // Work around JS 64-bit lossitude
     var prefix;
     var bitpos;
     if ( selectedGroup >= 31 ) {
         prefix = "editfriend_maskhi_";
         bitpos = selectedGroup - 31;
     } else {
         prefix = "editfriend_masklo_";
         bitpos = selectedGroup;
     }
   
     // iterate over all friends, putting them in one group or the other
     var i;
     for (i=0; i<form.elements.length; i++) {
         var name = form.elements[i].name;
         var mask = form.elements[i].value;
         if ( name.substring(0, prefix.length) == prefix ) {
             var user = name.substring( prefix.length, name.length );

             // see if we remap their display name
             var display = user;
             if (document.getElementById) {
                 display = document.getElementById('nameremap_' + user);
                 if (display) {
                     display = display.value;
                 } else {
                     display = user;
                 }
             }

             var list = mask & ( 1 << bitpos ) ? inlist : outlist;
             var optionName = new Option(display, user, false, false)
                 list.options[list.length] = optionName;
         }
     }
 }

 function moveItems (from, to, bitstatus)
 {
     // Work around JS 64-bit lossitude
     var prefix;
     var bitpos;
     if ( selectedGroup >= 31 ) {
         prefix = "editfriend_maskhi_";
         bitpos = selectedGroup - 31;
     } else {
         prefix = "editfriend_masklo_";
         bitpos = selectedGroup;
     }
   
     var selindex;
     while ((selindex=from.selectedIndex) != -1)
     {
         var i;
         var item = new Option(from.options[selindex].text,
                               from.options[selindex].value,
                               false, true);

         from.options[selindex] = null;
         //to.options[to.options.length] = item;

         // find spot to put new item
         for (i=0; i<to.options.length && to.options[i].text < item.text; i++) { }
         var newindex = i;

         // move everything else down
         for (i=to.options.length; i>newindex; i--) {
                  to.options[i] = new Option(to.options[i-1].text,
                                        to.options[i-1].value,
                                        false,
                                        to.options[i-1].selected);
         }
         to.options[newindex] = item;

         // turn the groupmask bit on or off
         var user = item.value;
         var element = document.fg[prefix+user];
         var mask = element.value;
         if (bitstatus) {
             mask |= ( 1 << bitpos );
         } else {
             mask &= ~( 1 << bitpos );
         }
         element.value = mask;
     }
 }

 function moveIn ()
 {
     if (! selectedGroup) { return; }
     var form = document.fg;
     var inlist = form.list_in;
     var outlist = form.list_out;
     moveItems(document.fg.list_out, document.fg.list_in, true);
 }
 function moveOut ()
 {
     if (! selectedGroup) { return; }
     moveItems(document.fg.list_in, document.fg.list_out, false);
 }

 function moveGroup (dir)
 {
     var list = document.fg.list_groups;
     var selindex = list.selectedIndex;
     if (selindex==-1) { return; }
     var toindex = selindex+dir;
     if (toindex < 0 || toindex >= list.options.length) { return; }
     var selopt = new Option(list.options[selindex].text,
                             list.options[selindex].value,
                             false,
                             list.options[selindex].selected);
     var toopt = new Option(list.options[toindex].text,
                            list.options[toindex].value,
                            false,
                            list.options[toindex].selected);
     list.options[toindex] = selopt;
     list.options[selindex] = toopt;    

     // stupid mozilla necessity:
     list.selectedIndex = toindex;

     setSortOrders();
 }

 function setSortOrders ()
 {
     var list = document.fg.list_groups;

     // set all their sort orders now
     var i;
     for (i=0; i<list.options.length; i++) {
         var item = list.options[i];
         var key = "efg_set_"+item.value+"_sort";
         document.fg[key].value = (i+1)*5;
     }
 }

 function realName (name)
 {
     var rname = name;
     var index = name.lastIndexOf(" $T{'public'}");
     if (index != -1) {
         rname = name.substr(0, index);
     }
     return rname;
 }
    
 function renameGroup ()
 {
     var list = document.fg.list_groups;
     var selindex = list.selectedIndex;
     if (selindex==-1) { return; }
     var item = list.options[selindex];

     var newtext = realName(item.text);
     newtext = prompt("$T{'rename'}", newtext);
     if (newtext==null || newtext == "") { return; }
     if ( newtext.includes( ',' ) ) {
         alert("$T{'comma'}");
         return;
     }

     var gnum = item.value;
     document.fg["efg_set_"+gnum+"_name"].value = newtext;     
     if (document.fg["efg_set_"+gnum+"_public"].value == 1) {
         newtext = newtext + " $T{'public'}";
     }
     item.text = newtext;
 }

 function deleteGroup ()
 {
     var list = document.fg.list_groups;
     var selindex = list.selectedIndex;
     if (selindex==-1) { return; }
     var item = list.options[selindex];

     var conf = confirm("$T{'delete'}");
     if (!conf) { return; }

     // mark it to be deleted later
     var gnum = item.value;
     document.fg["efg_delete_"+gnum].value = "1";
     document.fg["efg_set_"+gnum+"_name"].value = "";

     // Work around JS 64-bit lossitude
     var prefix;
     var bitpos;
     if ( gnum >= 31 ) {
         prefix = "editfriend_maskhi_";
         bitpos = gnum - 31;
     } else {
         prefix = "editfriend_masklo_";
         bitpos = gnum;
     }
   
     // as per the protocol documentation, unset bit on all friends
     var i;
     var form = document.fg;
     for (i=0; i<form.elements.length; i++) {
         var name = form.elements[i].name;
         if (name.substring( 0, prefix.length ) == prefix ) {
             var user = name.substring( prefix, name.length );
             var mask = form.elements[i].value;
             mask &= ~( 1 << bitpos );
             form.elements[i].value = mask;
         }
     }

     // clean up the UI
     list.options[selindex] = null;
     eraseList(document.fg.list_in);
     eraseList(document.fg.list_out);
 }

 function makePublic ()
 {
     var list = document.fg.list_groups;
     var selindex = list.selectedIndex;
     if (selindex==-1) { return; }
     var item = list.options[selindex];

     var name = realName(item.text);
     item.text = name + " $T{'public'}";
   
     var gnum = item.value;
     document.fg["efg_set_"+gnum+"_public"].value = "1";
 }

 function makePrivate ()
 {
     var list = document.fg.list_groups;
     var selindex = list.selectedIndex;
     if (selindex==-1) { return; }
     var item = list.options[selindex];

     var name = realName(item.text);
     item.text = name;     

     var gnum = item.value;
     document.fg["efg_set_"+gnum+"_public"].value = "0";
 }

 function newGroup ()
 {
     var form = document.fg;
     var i;
     var foundg = false;
     for (i=1; i<=60; i++) {
         if (form["efg_delete_"+i].value==1) { continue; }
         if (form["efg_set_"+i+"_name"].value!="") { continue; }
         foundg = true;
         break;	 
     }
     if (! foundg) {
         alert("$T{'max60'}");
         return;
     }
     var gnum = i;
     var groupname = prompt("$T{'newname'}", "");
     if (groupname==null || groupname=="") { return; }
     if ( groupname.includes( ',' ) ) {
         alert("$T{'comma'}");
         return;
     }

     form["efg_set_"+gnum+"_name"].value = groupname;
     var item = new Option(groupname, gnum, false, true);
     var list = form.list_groups;
     list.options[list.options.length] = item;
     list.options.selectedIndex = list.options.length-1;
     setSortOrders();
     groupClicked();
 }