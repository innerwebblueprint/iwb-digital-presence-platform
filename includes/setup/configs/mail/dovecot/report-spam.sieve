require ["vnd.dovecot.pipe", "copy"];

# Learn messages copied or moved into Junk as spam while keeping the user's
# mailbox action intact.
pipe :copy "learn-spam.sh";
