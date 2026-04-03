require ["fileinto", "mailbox"];

# File spam-tagged mail into Junk before user-managed filters run.
if header :contains "X-Spam" "Yes" {
  if mailboxexists "INBOX/Junk" {
    fileinto "INBOX/Junk";
  } else {
    fileinto "Junk";
  }
  stop;
}

if header :contains "X-Spam-Status" "Yes" {
  if mailboxexists "INBOX/Junk" {
    fileinto "INBOX/Junk";
  } else {
    fileinto "Junk";
  }
  stop;
}
