$(document).on('click', '.entry-content img, .comment-content img', function(e){
    if ( ! $(e.target).is('a img, .poll-response img') ) {
        $(e.target).toggleClass('expanded');
    }
});
