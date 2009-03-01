# test/heartbeat plugin for SPUD statistic gathering system
# written by Mark Smith <junior@danga.com>

# this is mostly a demonstration of how to create a very simple plugin for SPUD.
# more complex examples can be found elsewhere in the plugins directory.

# doesn't matter what package you're in
package TestPlugin;

# called when we're loaded.  here we can do anything necessary to set ourselves
# up if we want.
sub register {
    debug("test plugin registered");
    return 1;
}

# this is called and given the job name as the first parameter and an array ref of
# options passed in as the second parameter.
sub worker {
    my ($job, $options) = @_;

    # test plugin simply loops and once a second sets a "heartbeat"
    while (1) {
        set("test.$job" => 1);
        sleep 1;
    }
}

# calls the registrar in the main program, giving them information about us.  this
# has to be called as main:: or just ::register_plugin because we're in our own
# package and we want to talk to the register function in the main namespace.
main::register_plugin('test', 'TestPlugin', {
    register => \&register,
    worker => \&worker,
});

1;
