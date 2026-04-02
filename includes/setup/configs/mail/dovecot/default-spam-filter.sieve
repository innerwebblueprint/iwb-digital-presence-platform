require ["fileinto"];

# File spam-tagged mail into Junk before user-managed filters run.
if header :contains "X-Spam" "Yes" {
  fileinto "Junk";
  stop;
}

if header :contains "X-Spam-Status" "Yes" {
  fileinto "Junk";
  stop;
}
