$(document).ready(function()
{
    $('.delete-button').click(function(event)
    {
        event.preventDefault();
        $.post("/__rpc_esn_subs", {action:'delsub', subid:$(this).attr("subid"), auth_token:$(this).attr("auth_token")});
        $(this).closest('tr').remove();
    });
}
);

