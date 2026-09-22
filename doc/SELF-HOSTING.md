# Service configuration for small self-hosted sites

Dreamwidth can use SMTP and local task files without AWS. This setup is intended
for low-volume, single-host sites; use SQS when scaling workers. These
settings do not change the existing devcontainer or AWS production defaults.
They are service configuration, not a complete deployment recipe.

Keep site configuration in `ext/local/etc/config-local.pl` and credentials in
`ext/local/etc/config-private.pl`, using the examples in `etc/`. Keep private
configuration out of version control and readable only by the service operator.
Restart web and worker processes after changing configuration.

## Task queue

In `config-local.pl` (inside the existing `LJ` package):

```perl
$IS_DEV_SERVER = 0;
$TASK_QUEUE_BACKEND = 'localdisk';
$TASK_QUEUE_LOCAL_PATH = "$HOME/var/taskqueue"; # optional; this is the default
```

Do not enable development mode on a public site. It enables development-only
behavior, including user impersonation. Also leave `LJ_IS_DEV_SERVER` unset.

Without an explicit backend, selection is unchanged: configured `%SQS` wins;
otherwise a dev server uses local disk. A non-dev server without either an
explicit localdisk selection or SQS configuration fails with setup instructions.
`$TASK_QUEUE_BACKEND = 'sqs'` explicitly selects SQS. Selecting `localdisk` takes
precedence even if `%SQS` is present; switching backends does not migrate pending
jobs. Drain the old queue with its workers before switching producers.

LocalDisk requirements and limitations:

- Run **one consumer per task type across the entire site**, on one host. Multiple
  task types can run simultaneously, but two consumers of the same type can
  execute the same job. This backend has no claim leases or concurrent-consumer
  protection.
- Web processes and workers must see the same persistent queue directory and
  have permission to create, read, and delete files there. A missing directory
  is created at initialization. Do not expose it through the web server.
- Messages are published after their complete contents are written. This is not
  a power-loss durability guarantee. Back up persistent data and monitor disk
  space, worker logs, and queue growth.
- Failed tasks remain queued, without retry backoff, a retry limit, or a
  dead-letter queue. Persistent failures require operator attention. A crash
  after executing a task but before deleting its file can repeat its effects.
- This setting does not replace the separate TheSchwartz database used by legacy
  workers. Keep that configuration where those workers are enabled.

## Outgoing email

Queue selection and email delivery are independent. SQS is a job queue; SES is
an email provider. Any compatible SMTP relay can deliver queued email, including
SES, regardless of the queue backend.

In `config-private.pl`:

```perl
%SMTP_SERVER = (
    hostname => 'smtp.example.org',
    port     => 587,
    username => 'YOUR_SMTP_USERNAME',
    password => 'YOUR_SMTP_PASSWORD',
);
```

STARTTLS is required by default. If TLS negotiation fails, the worker fails the
attempt before authentication or delivery. Supply both credentials or omit both
for an unauthenticated relay. `plaintext => 1` disables STARTTLS explicitly; use
it only with a trusted local relay or development mail catcher. This client uses
STARTTLS, not implicit TLS on port 465.

Run `bin/worker/dw-send-email` under a supervisor that restarts it even after a
successful exit: the worker periodically exits to reclaim memory. The production
worker container's `startup-prod.sh` already provides this restart loop for the
worker command it receives.

Alternatively, `bin/worker-manager` reads `etc/workers.conf` through the site-local
file resolver. To use that manager, copy `etc/workers.conf` to
`ext/local/etc/workers.conf`, add `dw-send-email: 1` under `all:`, and run
`bin/worker-manager --debug` in the foreground under your supervisor. Restart the
manager after configuration changes. Editing `workers.conf` has no effect unless
you run `worker-manager`; the devcontainer does not start it automatically.

Choose one method so a local queue has only one consumer per task type. Enable
the other workers required by the features you use as well.

Configure the site's sender addresses and `$DOMAIN_EMAIL` for your provider.
The old `%EMAIL_VIA_SES` hash remains supported when `%SMTP_SERVER` is unset;
legacy scalar `$SMTP_SERVER` and `$MAIL_TO_THESCHWARTZ` settings do not configure
the current sender. SES configuration-set headers remain opt-in through
`$SES_CONFIGURATION_SET`. Incoming mail and SES event processing are separate
features and are not configured by these settings.

## Blob storage

For S3-compatible storage, in `config-private.pl`:

```perl
@BLOBSTORES = (
    s3 => {
        bucket     => 'site-media',
        region     => 'us-east-1', # use the region expected by your provider
        endpoint   => 'https://storage.example.org',
        access_key => 'YOUR_ACCESS_KEY',
        secret_key => 'YOUR_SECRET_KEY',
        prefix     => undef,
    },
);
```

Create the bucket separately and grant the service object read, write, delete,
and HEAD permissions. The endpoint must be reachable by both web and worker
processes. The installed Perl Paws S3 client uses path-style requests
(`endpoint/bucket/key`); no AWS CLI endpoint environment variable is needed.
Compatibility with a specific provider still needs a store/read/delete check.
Use HTTPS unless the endpoint is on a trusted local network.

`bucket_name` is accepted as an alias for `bucket`; if both are supplied, they
must agree. Explicit access and secret keys must be provided together. An
optional `session_token` supports explicit temporary credentials, which the
operator must refresh. With keys omitted or both `undef`, Paws retains its normal
credential discovery, including AWS environment/container/instance credentials.
Omit `endpoint` for normal AWS S3. Prefixes and object naming are unchanged;
changing a bucket or prefix does not migrate existing objects.

Local blob storage remains available through `localdisk => { path => ... }` in
`@BLOBSTORES`. Blob storage and the local task queue are separate systems;
selecting either does not select the other.

## Diagnostics

Run from `$LJHOME` in the service environment:

```sh
perl bin/checkconfig.pl --only=services
perl bin/checkconfig.pl
```

Service checks validate queue selection, required SQS settings, an existing
local queue directory's permissions, SMTP settings, and S3 configuration. They
report missing SMTP configuration and remind you to run the mail worker. They
do not send mail, contact S3, create queues, or verify that workers are alive.
A missing queue directory is created by the queue backend, not the diagnostic.

After setup, verify delivery to a mailbox you control and upload, view, and
delete a test image. Check worker logs for failures. The configuration checker
cannot verify provider credentials, network access, or delivery end to end.
