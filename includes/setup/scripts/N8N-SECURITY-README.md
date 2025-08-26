# n8n Security Configuration

## Overview

This container runs n8n as a dedicated `n8n` user (UID 9001) with strict environment isolation for enhanced security. The n8n process has access to only the minimal environment variables needed for operation, preventing access to sensitive credentials.

## Security Features

1. **User Isolation**: n8n runs as user `n8n` (UID 9001) with its own home directory
2. **Environment Isolation**: n8n runs with a clean environment, only specific variables allowed
3. **Limited Sudo**: Only specific commands can be executed with elevated privileges
4. **Command Validation**: The wrapper script validates arguments to prevent injection attacks
5. **Audit Logging**: All command executions are logged to `/var/log/n8n-commands.log`
6. **No Shell Access**: The n8n user cannot escalate to a root shell

## Environment Access

### 🔒 **Protected Variables (n8n CANNOT access these)**:
- `IWB_MYSQL_ROOT_PASSWORD` - Database credentials
- `IWB_STORJ_GRANT` - Storj access tokens
- `IWB_POSTFIXADMIN_SQL_PASSWORD` - Mail system credentials
- All other sensitive environment variables

### ✅ **Allowed Variables (n8n CAN access these)**:
- `IWB_STORJ_WPOPS_BUCKET` - Only the bucket name for operations
- Standard system variables: `HOME`, `PATH`, `N8N_*` configuration

## Allowed Commands

The n8n user has access to these commands:
- `uplink` - Storj network operations (runs as n8n user with n8n's credentials)
- `provider-services` - Akash network operations (runs as root via sudo)

## Usage in n8n Workflows

### Method 1: Direct execution for uplink (simple)
In n8n Execute Command nodes, uplink can be used directly:

```bash
# For uplink commands (no sudo needed)
/usr/local/bin/uplink ls

# For provider-services commands  
sudo /usr/local/bin/provider-services query provider list
```

### Method 2: Using the wrapper script (recommended)
The wrapper script provides additional security validation and logging:

```bash
# For uplink commands
/usr/local/bin/n8n-cmd uplink ls

# For provider-services commands
/usr/local/bin/n8n-cmd provider-services query provider list
```

## Security Features

1. **User Isolation**: n8n runs as user `n8n` (UID 9001) with its own home directory
2. **Limited Sudo**: Only specific commands can be executed with elevated privileges
3. **Command Validation**: The wrapper script validates arguments to prevent injection attacks
4. **Audit Logging**: All command executions are logged to `/var/log/n8n-commands.log`
5. **No Shell Access**: The n8n user cannot escalate to a root shell

## Security Considerations

### Potential Risks
- **Argument Injection**: While the wrapper script provides basic validation, complex argument structures should be carefully reviewed
- **File System Access**: n8n can still read/write files as the n8n user within its permissions
- **Network Access**: n8n maintains full network access for workflow operations

### Recommended Practices
1. **Validate Inputs**: Always validate user inputs in workflows before passing to system commands
2. **Use Wrapper Script**: Prefer the wrapper script over direct sudo for additional security layers
3. **Monitor Logs**: Regularly review `/var/log/n8n-commands.log` for unusual activity
4. **Principle of Least Privilege**: Only execute the minimum commands necessary

## File Locations

- **n8n Home**: `/home/n8n/`
- **n8n Data**: `/var/www/html/n8n/` (symlinked to `/home/n8n/.n8n`)
- **Wrapper Script**: `/usr/local/bin/n8n-cmd`
- **Command Log**: `/var/log/n8n-commands.log`
- **Sudo Config**: `/etc/sudoers.d/n8n`

## Troubleshooting

### Permission Denied Errors
If you get permission denied errors, ensure you're using the correct command format:
```bash
# Correct for uplink
/usr/local/bin/uplink --help
# or
/usr/local/bin/n8n-cmd uplink --help

# Correct for provider-services
sudo /usr/local/bin/provider-services --help
# or
/usr/local/bin/n8n-cmd provider-services --help

# Incorrect
uplink --help  # Command not in PATH for n8n user
```

## Security Testing

### Verify Environment Isolation
Test that sensitive variables are not accessible from n8n:

```bash
# In an n8n Execute Command node, these should return empty/fail:
echo $IWB_MYSQL_ROOT_PASSWORD  # Should be empty
echo $IWB_STORJ_GRANT         # Should be empty
env | grep IWB_               # Should only show IWB_STORJ_WPOPS_BUCKET

# This should work:
echo $IWB_STORJ_WPOPS_BUCKET  # Should show: raywpops
```

### Test Command Restrictions
```bash
# These should work in n8n:
/usr/local/bin/n8n-cmd uplink ls
/usr/local/bin/n8n-cmd provider-services version

# These should fail (no access to other commands):
cat /etc/passwd
mysql -u root  # Should fail - not in PATH
```

### Checking Command Availability
To verify commands are available:
```bash
# Check if commands exist
ls -la /usr/local/bin/uplink
ls -la /usr/local/bin/provider-services

# Check sudo permissions (only provider-services should be listed)
sudo -l
```

### Reviewing Logs
```bash
# View recent command executions
tail -f /var/log/n8n-commands.log

# Check n8n service logs
tail -f /var/log/supervisord/n8n.log
```
