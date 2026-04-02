require ["vnd.dovecot.pipe", "copy"];

# Learn messages copied or moved out of Junk as ham while keeping the user's
# mailbox action intact.
pipe :copy "learn-ham.sh";
