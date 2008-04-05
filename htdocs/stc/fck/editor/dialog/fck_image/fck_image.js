/*
 * FCKeditor - The text editor for internet
 * Copyright (C) 2003-2005 Frederico Caldeira Knabben
 * 
 * Licensed under the terms of the GNU Lesser General Public License:
 * 		http://www.opensource.org/licenses/lgpl-license.php
 * 
 * For further information visit:
 * 		http://www.fckeditor.net/
 * 
 * "Support Open Source software. What about a donation today?"
 * 
 * File Name: fck_image.js
 * 	Scripts related to the Image dialog window (see fck_image.html).
 * 
 * File Authors:
 * 		Frederico Caldeira Knabben (fredck@fckeditor.net)
 */

var oEditor		= window.parent.InnerDialogLoaded() ;
var FCK			= oEditor.FCK ;
var FCKLang		= oEditor.FCKLang ;
var FCKConfig	= oEditor.FCKConfig ;
var FCKDebug	= oEditor.FCKDebug ;

var bImageButton = ( document.location.search.length > 0 && document.location.search.substr(1) == 'ImageButton' ) ;

//#### Dialog Tabs

// Set the dialog tabs.
window.parent.AddTab( 'Info', FCKLang.DlgImgInfoTab ) ;

if ( !bImageButton && !FCKConfig.ImageDlgHideLink )
	window.parent.AddTab( 'Link', FCKLang.DlgImgLinkTab ) ;

if ( FCKConfig.ImageUpload )
	window.parent.AddTab( 'Upload', FCKLang.DlgLnkUpload ) ;

if ( FCKConfig.ImagePhotobucket)
	window.parent.AddTab( 'Photobucket', 'Photobucket' ) ;

if ( !FCKConfig.ImageDlgHideAdvanced )
	window.parent.AddTab( 'Advanced', FCKLang.DlgAdvancedTag ) ;

// Function called when a dialog tag is selected.
function OnDialogTabChange( tabCode )
{
	ShowE('divInfo'		, ( tabCode == 'Info' ) ) ;
	ShowE('divLink'		, ( tabCode == 'Link' ) ) ;
	ShowE('divUpload'	, ( tabCode == 'Upload' ) ) ;
	ShowE('divPhotobucket'	, ( tabCode == 'Photobucket' ) ) ;
	ShowE('divAdvanced'	, ( tabCode == 'Advanced' ) ) ;
}

// Get the selected image (if available).
var oImage = FCK.Selection.GetSelectedElement() ;

if ( oImage && oImage.tagName != 'IMG' && !( oImage.tagName == 'INPUT' && oImage.type == 'image' ) )
	oImage = null ;

// Get the active link.
var oLink = FCK.Selection.MoveToAncestorNode( 'A' ) ;

var oImageOriginal ;

function UpdateOriginal( resetSize )
{
    	if ( !eImgPreview )
    		return ;
		
	oImageOriginal = document.createElement( 'IMG' ) ;	// new Image() ;

	if ( resetSize )
	{
		oImageOriginal.onload = function()
		{
			this.onload = null ;
			ResetSizes() ;
		}
	}

	oImageOriginal.src = eImgPreview.src ;
}

var bPreviewInitialized ;

window.onload = function()
{
	// Translate the dialog box texts.
	oEditor.FCKLanguageManager.TranslatePage(document) ;

	GetE('btnLockSizes').title = FCKLang.DlgImgLockRatio ;
	GetE('btnResetSize').title = FCKLang.DlgBtnResetSize ;

	// Load the selected element information (if any).
	LoadSelection() ;

	// Show/Hide the "Browse Server" button.
	GetE('tdBrowse').style.display				= FCKConfig.ImageBrowser	? '' : 'none' ;
	GetE('divLnkBrowseServer').style.display	= FCKConfig.LinkBrowser		? '' : 'none' ;

	UpdateOriginal() ;

	// Set the actual uploader URL.
        //	if ( FCKConfig.ImageUpload )
        //		GetE('insobjform').action = FCKConfig.ImageUploadURL ;

	window.parent.SetAutoSize( true ) ;

	// Activate the "OK" button.
	window.parent.SetOkButton( true ) ;
}

function LoadSelection()
{
	if ( ! oImage ) return ;

	var sUrl = GetAttribute( oImage, '_fcksavedurl', '' ) ;
	if ( sUrl.length == 0 )
		sUrl = GetAttribute( oImage, 'src', '' ) ;

	// TODO: Wait stable version and remove the following commented lines.
//	if ( sUrl.startsWith( FCK.BaseUrl ) )
//		sUrl = sUrl.remove( 0, FCK.BaseUrl.length ) ;

	GetE('txtUrl').value    = sUrl ;
	GetE('txtAlt').value    = GetAttribute( oImage, 'alt', '' ) ;
	GetE('txtVSpace').value	= GetAttribute( oImage, 'vspace', '' ) ;
	GetE('txtHSpace').value	= GetAttribute( oImage, 'hspace', '' ) ;
	GetE('txtBorder').value	= GetAttribute( oImage, 'border', '' ) ;
	GetE('cmbAlign').value	= GetAttribute( oImage, 'align', '' ) ;

	var iWidth, iHeight ;

	var regexSize = /^\s*(\d+)px\s*$/i ;
	
	if ( oImage.style.width )
	{
		var aMatch  = oImage.style.width.match( regexSize ) ;
		if ( aMatch )
		{
			iWidth = aMatch[1] ;
			oImage.style.width = '' ;
		}
	}

	if ( oImage.style.height )
	{
		var aMatch  = oImage.style.height.match( regexSize ) ;
		if ( aMatch )
		{
			iHeight = aMatch[1] ;
			oImage.style.height = '' ;
		}
	}

	GetE('txtWidth').value	= iWidth ? iWidth : GetAttribute( oImage, "width", '' ) ;
	GetE('txtHeight').value	= iHeight ? iHeight : GetAttribute( oImage, "height", '' ) ;

	// Get Advances Attributes
	GetE('txtAttId').value			= oImage.id ;
	GetE('cmbAttLangDir').value		= oImage.dir ;
	GetE('txtAttLangCode').value	= oImage.lang ;
	GetE('txtAttTitle').value		= oImage.title ;
	GetE('txtAttClasses').value		= oImage.getAttribute('class',2) || '' ;
	GetE('txtLongDesc').value		= oImage.longDesc ;

	if ( oEditor.FCKBrowserInfo.IsIE )
		GetE('txtAttStyle').value	= oImage.style.cssText ;
	else
		GetE('txtAttStyle').value	= oImage.getAttribute('style',2) ;

	if ( oLink )
	{
		var sUrl = GetAttribute( oLink, '_fcksavedurl', '' ) ;
		if ( sUrl.length == 0 )
			sUrl = oLink.getAttribute('href',2) ;
	
		GetE('txtLnkUrl').value		= sUrl ;
	}

	UpdatePreview() ;
}

//#### The OK button was hit.
function Ok()
{
	if ( GetE('txtUrl').value.length == 0 )
	{
		window.parent.SetSelectedTab( 'Info' ) ;
		GetE('txtUrl').focus() ;

		alert( FCKLang.DlgImgAlertUrl ) ;

		return false ;
	}

	var bHasImage = ( oImage != null ) ;

	if ( bHasImage && bImageButton && oImage.tagName == 'IMG' )
	{
		if ( confirm( 'Do you want to transform the selected image on a image button?' ) )
			oImage = null ;
	}
	else if ( bHasImage && !bImageButton && oImage.tagName == 'INPUT' )
	{
		if ( confirm( 'Do you want to transform the selected image button on a simple image?' ) )
			oImage = null ;
	}
	
	if ( !bHasImage )
	{
		if ( bImageButton )
		{
			oImage = FCK.EditorDocument.createElement( 'INPUT' ) ;
			oImage.type = 'image' ;
			oImage = FCK.InsertElementAndGetIt( oImage ) ;
		}
		else
			oImage = FCK.CreateElement( 'IMG' ) ;
	}
	else
		oEditor.FCKUndo.SaveUndoStep() ;
	
	UpdateImage( oImage ) ;

	var sLnkUrl = GetE('txtLnkUrl').value.trim() ;

	if ( sLnkUrl.length == 0 )
	{
		if ( oLink )
			FCK.ExecuteNamedCommand( 'Unlink' ) ;
	}
	else
	{
		if ( oLink )	// Modifying an existent link.
			oLink.href = sLnkUrl ;
		else			// Creating a new link.
		{
			if ( !bHasImage )
				oEditor.FCKSelection.SelectNode( oImage ) ;

			oLink = oEditor.FCK.CreateLink( sLnkUrl ) ;

			if ( !bHasImage )
			{
				oEditor.FCKSelection.SelectNode( oLink ) ;
				oEditor.FCKSelection.Collapse( false ) ;
			}
		}

		SetAttribute( oLink, '_fcksavedurl', sLnkUrl ) ;
	}

	return true ;
}

function UpdateImage( e, skipId )
{
	e.src = GetE('txtUrl').value ;
	SetAttribute( e, "_fcksavedurl", GetE('txtUrl').value ) ;
	SetAttribute( e, "alt"   , GetE('txtAlt').value ) ;
	SetAttribute( e, "width" , GetE('txtWidth').value ) ;
	SetAttribute( e, "height", GetE('txtHeight').value ) ;
	SetAttribute( e, "vspace", GetE('txtVSpace').value ) ;
	SetAttribute( e, "hspace", GetE('txtHSpace').value ) ;
	SetAttribute( e, "border", GetE('txtBorder').value ) ;
	SetAttribute( e, "align" , GetE('cmbAlign').value ) ;

	// Advances Attributes

	if ( ! skipId )
		SetAttribute( e, 'id', GetE('txtAttId').value ) ;

	SetAttribute( e, 'dir'		, GetE('cmbAttLangDir').value ) ;
	SetAttribute( e, 'lang'		, GetE('txtAttLangCode').value ) ;
	SetAttribute( e, 'title'	, GetE('txtAttTitle').value ) ;
	SetAttribute( e, 'class'	, GetE('txtAttClasses').value ) ;
	SetAttribute( e, 'longDesc'	, GetE('txtLongDesc').value ) ;

	if ( oEditor.FCKBrowserInfo.IsIE )
		e.style.cssText = GetE('txtAttStyle').value ;
	else
		SetAttribute( e, 'style', GetE('txtAttStyle').value ) ;
}

var eImgPreview ;
var eImgPreviewLink ;

function SetPreviewElements( imageElement, linkElement )
{
	eImgPreview = imageElement ;
	eImgPreviewLink = linkElement ;

	UpdatePreview() ;
	UpdateOriginal() ;
	
	bPreviewInitialized = true ;
}

function UpdatePreview()
{
    	if ( !eImgPreview || !eImgPreviewLink )
		return ;

	if ( GetE('txtUrl').value.length == 0 )
		eImgPreviewLink.style.display = 'none' ;
	else
	{
		UpdateImage( eImgPreview, true ) ;

		if ( GetE('txtLnkUrl').value.trim().length > 0 )
			eImgPreviewLink.href = 'javascript:void(null);' ;
		else
			SetAttribute( eImgPreviewLink, 'href', '' ) ;

		eImgPreviewLink.style.display = '' ;
	}
}

var bLockRatio = true ;

function SwitchLock( lockButton )
{
	bLockRatio = !bLockRatio ;
	lockButton.className = bLockRatio ? 'BtnLocked' : 'BtnUnlocked' ;
	lockButton.title = bLockRatio ? 'Lock sizes' : 'Unlock sizes' ;

	if ( bLockRatio )
	{
		if ( GetE('txtWidth').value.length > 0 )
			OnSizeChanged( 'Width', GetE('txtWidth').value ) ;
		else
			OnSizeChanged( 'Height', GetE('txtHeight').value ) ;
	}
}

// Fired when the width or height input texts change
function OnSizeChanged( dimension, value )
{
	// Verifies if the aspect ration has to be mantained
	if ( oImageOriginal && bLockRatio )
	{
		var e = dimension == 'Width' ? GetE('txtHeight') : GetE('txtWidth') ;
		
		if ( value.length == 0 || isNaN( value ) )
		{
			e.value = '' ;
			return ;
		}

		if ( dimension == 'Width' )
			value = value == 0 ? 0 : Math.round( oImageOriginal.height * ( value  / oImageOriginal.width ) ) ;
		else
			value = value == 0 ? 0 : Math.round( oImageOriginal.width  * ( value / oImageOriginal.height ) ) ;

		if ( !isNaN( value ) )
			e.value = value ;
	}

	UpdatePreview() ;
}

// Fired when the Reset Size button is clicked
function ResetSizes()
{
	if ( ! oImageOriginal ) return ;

	GetE('txtWidth').value  = oImageOriginal.width ;
	GetE('txtHeight').value = oImageOriginal.height ;

	UpdatePreview() ;
}

function BrowseServer()
{
	OpenServerBrowser(
		'Image',
		FCKConfig.ImageBrowserURL,
		FCKConfig.ImageBrowserWindowWidth,
		FCKConfig.ImageBrowserWindowHeight ) ;
}

function LnkBrowseServer()
{
	OpenServerBrowser(
		'Link',
		FCKConfig.LinkBrowserURL,
		FCKConfig.LinkBrowserWindowWidth,
		FCKConfig.LinkBrowserWindowHeight ) ;
}

function OpenServerBrowser( type, url, width, height )
{
	sActualBrowser = type ;
	OpenFileBrowser( url, width, height ) ;
}

var sActualBrowser ;

function SetUrl( surl, furl, width, height, alt )
{
	if ( sActualBrowser == 'Link' )
	{
		GetE('txtLnkUrl').value = surl ;
		UpdatePreview() ;
	}
	else
	{
		GetE('txtUrl').value = surl ;
		GetE('txtLnkUrl').value = furl ;
		GetE('txtWidth').value = width ? width : '' ;
		GetE('txtHeight').value = height ? height : '' ;
                GetE('txtBorder').value	= 0;

		if ( alt )
			GetE('txtAlt').value = alt;

		UpdatePreview( ) ;
		UpdateOriginal( ) ;
	}
	
	window.parent.SetSelectedTab( 'Info' ) ;
}

// Insert image functionality -- mostly from imgupload.bml // entry.js // original fck upload functionality
var InObFCK = new Object;

InObFCK.fail = function (msg) {
    alert("FAIL: " + msg);
    return false;
};

var oUploadAllowedExtRegex      = new RegExp( FCKConfig.ImageUploadAllowedExtensions, 'i' ) ;
var oUploadDeniedExtRegex       = new RegExp( FCKConfig.ImageUploadDeniedExtensions, 'i' ) ;

InObFCK.onUpload = function (surl, furl, swidth, sheight) {
    sActualBrowser = '';
    SetUrl ( surl, furl, swidth, sheight );
    GetE('insobjform').reset() ;
};

InObFCK.setupIframeHandlers = function () {
    var el;

    el = GetE("fromfile");
    if (el) el.onfocus = function () { return InObFCK.selectRadio("fromfile"); };
    el = GetE("fromfileentry");
    if (el) el.onclick = el.onfocus = function () { return InObFCK.selectRadio("fromfile"); };
    el = GetE("fromfb");
    if (el) el.onfocus = function () { return InObFCK.selectRadio("fromfb"); };
    el = GetE("btnPrev");
    if (el) el.onclick = InObFCK.onButtonPrevious;

};

InObFCK.selectRadio = function (which) {
    var radio = GetE(which);
    if (! radio) return InObFCK.fail('no radio button');
    radio.checked = true;

    var fromfile = GetE('fromfileentry');
    var submit   = GetE('btnNext');
    if (! submit) return InObFCK.fail('no submit button');

    // clear stuff
    if (which != 'fromfile') {
        var filediv = GetE('filediv');
        filediv.innerHTML = filediv.innerHTML;
    }

    // focus and change next button
    if (which == "fromfile") {
        submit.value = 'Upload';
        fromfile.focus();
    } else {
        submit.value = "Next -->";  // &#x2192 is a right arrow
        //        fromfile.focus();
    }

    return true;
};

InObFCK.onSubmit = function () {
    var fileradio = GetE('fromfile');
    var fbradio   = GetE('fromfb');

    var form = GetE('insobjform');
    var sFile = GetE('fromfileentry').value ;
    if (! form) return InObFCK.fail('no form');

    var div_err = GetE('img_error');
    if (! div_err) return InObFCK.fail('Unable to get error div');

    var setEnc = function (vl) {
        form.encoding = vl;
        if (form.setAttribute) {
            form.setAttribute("enctype", vl);
        }
    };

    if (fileradio && fileradio.checked) {
        if ( sFile.length == 0 )
            {
                alert( 'Please select a file to upload' ) ;
                return false ;
            }

        if ( ( FCKConfig.ImageUploadAllowedExtensions.length > 0 && !oUploadAllowedExtRegex.test( sFile ) ) ||
             ( FCKConfig.ImageUploadDeniedExtensions.length > 0 && oUploadDeniedExtRegex.test( sFile ) ) )
            {
                alert('Please only upload files in the formats of jpg, png, gif or tif.');
                return false;
            }

                form.action = fileaction;
                setEnc("multipart/form-data");
                return true;
    } else {
        if (fbradio && fbradio.checked) {
            InObFCK.fotobilderStepOne();
            return false;
        }
    }

    alert('unknown radio button checked');
    return false;
};

InObFCK.showSelectorPage = function () {
    var div_if = GetE("img_iframe_holder");
    var div_fw = GetE("img_fromwhere");
    div_fw.style.display = "";
    div_if.style.display = "none";
    InObFCK.setPreviousCb(null);

        InObFCK.setTitle('Insert Image');
};

InObFCK.fotobilderStepOne = function () {
    var div_if = GetE("img_iframe_holder");
    var div_fw = GetE("img_fromwhere");
    div_fw.style.display = "none";
    div_if.style.display = "";
    var url = fbroot + "/getgalsrte";

    var titlebar = GetE('insObjTitle');

    var navbar = GetE('insobjNav');

    div_if.innerHTML = "<iframe width='100%' height='100%' id='fbstepframe' src=\"" + url + "\" frameborder='0'></iframe>";
    div_if.style.border = '0px solid';

    InObFCK.setPreviousCb(InObFCK.showSelectorPage);
}


InObFCK.setPreviousCb = function (cb) {
    InObFCK.cbForBtnPrevious = cb;
    GetE("btnPrev").style.display = cb ? "" : "none";
};

// all previous clicks come in here, then we route it to the registered previous handler
InObFCK.onButtonPrevious = function () {
    InObFCK.showNext();

    if (InObFCK.cbForBtnPrevious)
    return InObFCK.cbForBtnPrevious();

    // shouldn't get here, but let's ignore the event (which would do nothing anyway)
    return true;
};

InObFCK.setError = function (errstr) {
    var div_err = GetE('img_error');
    if (! div_err) return false;

    div_err.innerHTML = errstr;
    return true;
};


InObFCK.clearError = function () {
    var div_err = GetE('img_error');
    if (! div_err) return false;

    div_err.innerHTML = '';
    return true;
};

InObFCK.disableNext = function () {
    var next = GetE('btnNext');
    if (! next) return InObFCK.fail('no next button');

    next.disabled = true;

    return true;
};

InObFCK.enableNext = function () {
    var next = GetE('btnNext');
    if (! next) return InObFCK.fail('no next button');

    next.disabled = false;

    return true;
};

InObFCK.hideNext = function () {
    var next = GetE('btnNext');
    if (! next) return InObFCK.fail('no next button');
    next.style.display = 'none'
    return true;
};

InObFCK.showNext = function () {
    var next = GetE('btnNext');
    if (! next) return InObFCK.fail('no next button');
    next.style.display = '';
    return true;
};

InObFCK.setTitle = function (title) {
    var wintitle = GetE('wintitle');
    wintitle.innerHTML = title;
};
