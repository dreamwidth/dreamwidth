
Expander = function(){
    this.__caller__;    // <a> HTML element from where Expander was called
    this.url;           // full url of thread to be expanded
    this.id;            // id of the thread
    this.onclick;
    this.stored_caller;
    this.iframe;        // iframe, where the thread will be loaded
    this.is_S1;         // bool flag, true == journal is in S1, false == in S2
}
Expander.Collection={};
Expander.make = function(el,url,id,is_S1){
    var local = (new Expander).set({__caller__:el,url:url.replace(/#.*$/,''),id:id,is_S1:!!is_S1});
    local.get();
}

Expander.prototype.set = function(options){
    for(var opt in options){
        this[opt] = options[opt];
    }
    return this;
}

Expander.prototype.getCanvas = function(id,context){
    return context.document.getElementById('cmt'+id);
}

Expander.prototype.parseLJ_cmtinfo = function(context,callback){
    var map={}, node, j;
    var LJ = context.LJ_cmtinfo;
    if(!LJ)return false;
    for(j in LJ){
        if(/^\d*$/.test(j) && (node = this.getCanvas(j,context))){
            map[j] = {info:LJ[j],canvas:node};
            if(typeof callback == 'function'){
                callback(j,map[j]);
            }
        }
    }
    return map;
}

Expander.prototype.loadingStateOn = function(){
    this.stored_caller = this.__caller__.cloneNode(true);
    this.__caller__.setAttribute('already_clicked','already_clicked');
    this.onclick = this.__caller__.onclick;
    this.__caller__.onclick = function(){return false;}
    this.__caller__.style.color = '#ccc';
}

Expander.prototype.loadingStateOff = function(){
    var expand_all = DOM.getElementsByClassName( document, "expand_all" );
    if (expand_all.length > 0) {
      // if all comments have been expanded, remove the expand_all entry
      var LJ = window.LJ_cmtinfo;
      var removeExpandAll = true;
      for (var talkid in LJ) {
        if (LJ[talkid].hasOwnProperty("full") && ! LJ[talkid].full && ! LJ[talkid].deleted && ! LJ[talkid].screened) {
          removeExpandAll = false;
        }
      }

      if (removeExpandAll) {
        for(var i = 0; i < expand_all.length; i++) {
            var ele = expand_all[i];
            ele.parentNode.removeChild(ele);
        }
      }
    }

    if (this.__caller__) {
      // only used on error, or when expand all fails to expand all.
      // in most cases, the <a> element is removed from main window by
      // copying comment from iframe, or above by the removeExpandAll
      // logic, so this code is not executed.
      this.__caller__.removeAttribute('already_clicked','already_clicked');
      if (this.__caller__.parentNode) this.__caller__.parentNode.replaceChild(this.stored_caller,this.__caller__);
    }
    var obj = this;
    // When frame is removed immediately, IE raises an error sometimes
    window.setTimeout(function(){obj.killFrame()},100);
}

Expander.prototype.killFrame = function(){
    document.body.removeChild(this.iframe);
}

Expander.prototype.isFullComment = function(comment){
    return !!Number(comment.info.full);
}

Expander.prototype.killDuplicate = function(comments){
    var comment;
    var id,id_,el,el_;
    for(var j in comments){
        if(!/^\d*$/.test(j))continue;
        el_ = comments[j].canvas;
        id_ = el_.id;
        id = id_.replace(/_$/,'');
        el = document.getElementById(id);
        if(el!=null){
            //in case we have a duplicate;
            el_.parentNode.removeChild(el_);
        }else{
            el_.id = id;
        }
    }
}

Expander.prototype.getS1width = function(canvas){
  var w;
  //TODO:  may be we should should add somie ID to the spacer img instead of searching it
  //yet, this works until we have not changed the spacers url = 'dot.gif');
  var img, imgs, found;
  imgs = canvas.getElementsByTagName('img');
  if(!imgs)return false;
  for(var j=0;j<imgs.length;j++){
    img=imgs[j];
    if(/dot\.gif$/.test(img.src)){
        found = true;
        break;
    }
  }
  if(found&&img.width)return Number(img.width);
  else return false;
}

Expander.prototype.setS1width = function(canvas,w){
  var img, imgs, found;
  imgs = canvas.getElementsByTagName('img');
  if(!imgs)return false;
  for(var j=0;j<imgs.length;j++){
    img=imgs[j];
    if(/dot\.gif$/.test(img.src)){
        found = true;
        break;
    }
  }
  if(found)img.setAttribute('width',w);
}

Expander.prototype.onLoadHandler = function(iframe){
        var doc = iframe.contentDocument || iframe.contentWindow;
        doc = doc.document||doc;
        var obj = this;
        var win = doc.defaultView||doc.parentWindow;
        var comments_intersection={};
        var comments_page = this.parseLJ_cmtinfo(window);
        var comments_iframe = this.parseLJ_cmtinfo(win,function(id,new_comment){
                                    if(id in comments_page){
                                        comments_page[id].canvas.id = comments_page[id].canvas.id+'_';
                                        comments_intersection[id] = comments_page[id];
                                        // copy comment from iframe to main window if
                                        // 1) the comment is collapsed in main window and is full in iframe
                                        // 2) or this is the root comment of this thread (it may be full in
                                        //     main window too, it's copied so that to remove "expand" link from it)
                                        if((!obj.isFullComment(comments_page[id]) && obj.isFullComment(new_comment)) || (id===obj.id)){
                                            var w;
                                            if(obj.is_S1){
                                                w =obj.getS1width(comments_page[id].canvas);
                                            }
                                            comments_page[id].canvas.innerHTML = new_comment.canvas.innerHTML;
                                            if(obj.is_S1 && w!==null){
                                                    obj.setS1width(comments_page[id].canvas,w);
                                            }
                                            //TODO: may be this should be uncommented
                                            //comments_page[id].canvas.className = new_comment.canvas.className;
                                            LJ_cmtinfo[id].full=1;
                                        }
                                    }//if(id in comments_page){
                                });
       this.killDuplicate(comments_intersection);
       this.loadingStateOff();
       if ( typeof ContextualPopup.setup() != "undefined" )
           ContextualPopup.setup();
       return true;
}


//just for debugging
Expander.prototype.toString = function(){
  return '__'+this.id+'__';
}


Expander.prototype.get = function(){
    if(this.__caller__.getAttribute('already_clicked')){
        return false;
    }
    this.loadingStateOn();

    var iframe;
    if(/*@cc_on !@*/0){
        // branch for IE
        Expander.Collection[this.id] = this;
        iframe = document.createElement('<iframe onload="Expander.Collection['+this.id+'].onLoadHandler(this)">');
    }else{
        // branch for all other browsers
        iframe = document.createElement('iframe');
        iframe.onload = function(obj){return function(){
                            obj.onLoadHandler(iframe);
                        }}(this);
    }
    iframe.style.height='1px';
    iframe.style.width='1px';
    iframe.style.display = 'none';
    iframe.src = this.url;
    iframe.id = this.id;
    document.body.appendChild(iframe);
    this.iframe=iframe;
    return true;
}
