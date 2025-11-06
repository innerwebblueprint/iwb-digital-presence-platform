#!/usr/bin/env bash
#
# show-passwords.sh - Display auto-generated passwords for the IWB DPP platform
#
# This script reads and displays all auto-generated passwords that were created
# during the first startup of the container.
#

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

STATE_DIR="/var/data/state"

echo ""
echo -e "${BOLD}╔═══════════════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║           IWB DPP - Auto-Generated Passwords                              ║${NC}"
echo -e "${BOLD}╚═══════════════════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Check if state directory exists
if [ ! -d "$STATE_DIR" ]; then
    echo -e "${YELLOW}Warning: State directory $STATE_DIR not found.${NC}"
    echo "Passwords may not have been generated yet. Start the container first."
    exit 1
fi

echo -e "${CYAN}These passwords were auto-generated on first startup and are persisted${NC}"
echo -e "${CYAN}in $STATE_DIR${NC}"
echo ""

# MySQL Root Password
if [ -f "$STATE_DIR/iwb_mysql_root_password.txt" ]; then
    MYSQL_ROOT_PASS=$(cat "$STATE_DIR/iwb_mysql_root_password.txt")
    echo -e "${GREEN}MySQL Root Password:${NC}"
    echo -e "  ${BOLD}$MYSQL_ROOT_PASS${NC}"
    echo ""
else
    echo -e "${YELLOW}MySQL Root Password: Not generated yet${NC}"
    echo ""
fi

# PostfixAdmin SQL Password
if [ -f "$STATE_DIR/iwb_postfixadmin_sql_password.txt" ]; then
    PA_SQL_PASS=$(cat "$STATE_DIR/iwb_postfixadmin_sql_password.txt")
    echo -e "${GREEN}PostfixAdmin Database Password:${NC}"
    echo -e "  ${BOLD}$PA_SQL_PASS${NC}"
    echo ""
else
    echo -e "${YELLOW}PostfixAdmin Database Password: Not generated yet${NC}"
    echo ""
fi

# WordPress MySQL Password
if [ -f "$STATE_DIR/iwb_wp_mysql_password.txt" ]; then
    WP_SQL_PASS=$(cat "$STATE_DIR/iwb_wp_mysql_password.txt")
    echo -e "${GREEN}WordPress Database Password:${NC}"
    echo -e "  ${BOLD}$WP_SQL_PASS${NC}"
    echo ""
else
    echo -e "${YELLOW}WordPress Database Password: Not generated yet${NC}"
    echo ""
fi

# Rspamd Controller Password
if [ -f "$STATE_DIR/iwb_rspamd_controller_password.txt" ]; then
    RSPAMD_PASS=$(cat "$STATE_DIR/iwb_rspamd_controller_password.txt")
    echo -e "${GREEN}Rspamd Web UI Password (normal access):${NC}"
    echo -e "  ${BOLD}$RSPAMD_PASS${NC}"
    echo -e "  ${BLUE}Access at: https://yourdomain.tld/rspamd${NC}"
    echo ""
else
    echo -e "${YELLOW}Rspamd Web UI Password: Not generated yet${NC}"
    echo ""
fi

# Rspamd Enable Password
if [ -f "$STATE_DIR/iwb_rspamd_controller_enable_password.txt" ]; then
    RSPAMD_ENABLE_PASS=$(cat "$STATE_DIR/iwb_rspamd_controller_enable_password.txt")
    echo -e "${GREEN}Rspamd Enable Password (enable/disable modules):${NC}"
    echo -e "  ${BOLD}$RSPAMD_ENABLE_PASS${NC}"
    echo ""
else
    echo -e "${YELLOW}Rspamd Enable Password: Not generated yet${NC}"
    echo ""
fi

echo -e "${BOLD}═══════════════════════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "${CYAN}Notes:${NC}"
echo -e "  - These passwords persist across container restarts"
echo -e "  - They are regenerated only if volumes are cleared (new deployment)"
echo -e "  - Store these securely if you need to access the services manually"
echo -e "  - Password files are located in: $STATE_DIR"
echo ""
