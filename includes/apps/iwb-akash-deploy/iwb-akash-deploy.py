#!/usr/bin/env python3
"""
iwb-akash-deploy.py
Deploy ComfyUI instances to Akash Network for n8n workflows

This script handles:
1. Wallet restoration from Storj
2. Balance checking and cost estimation
3. ComfyUI deployment to Akash
4. API credential generation
5. Cleanup and notifications

Usage: python3 iwb-akash-deploy.py [options]
"""

import os
import sys
import json
import subprocess
import time
import re
import secrets
import string
import argparse
from datetime import datetime, timedelta
from typing import Dict, Optional, Tuple
import logging
import yaml

# Configuration
AKASH_WALLET_NAME = os.getenv('COMPOSE_PROJECT_NAME', 'iwb') + 'akashwallet'
AKASH_KEYRING_BACKEND = 'test'
AKASH_NODE = 'https://rpc.akashnet.net:443'
AKASH_CHAIN_ID = 'akashnet-2'
AKASH_WALLET_RESTORE_SCRIPT = '/var/setup/scripts/akash-wallet-restore.sh'

# ComfyUI deployment configuration
COMFYUI_IMAGE = 'ghcr.io/yownas/comfyui:main'
COMFYUI_PORT = 8188
DEPLOYMENT_MINUTES = 60  # Minimum deployment time in minutes
ESTIMATED_COST_PER_HOUR = 0.5  # Estimated AKT per hour for GPU deployment

class AkashDeployer:
    def __init__(self):
        self.logger = self._setup_logging()
        self.wallet_address = None
        self.balance_uakt = 0
        self.custom_manifest: Optional[str] = None

    def _setup_logging(self) -> logging.Logger:
        """Setup logging configuration"""
        logging.basicConfig(
            level=logging.INFO,
            format='%(asctime)s - %(levelname)s - %(message)s',
            handlers=[
                logging.FileHandler('./iwb-akash-deploy.log'),
                logging.StreamHandler(sys.stdout)
            ]
        )
        return logging.getLogger(__name__)

    def run_command(self, cmd: list, timeout: int = 30, env: Optional[dict] = None) -> Tuple[str, str, int]:
        """Run a shell command and return stdout, stderr, returncode"""
        try:
            result = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                timeout=timeout,
                env=env
            )
            return result.stdout, result.stderr, result.returncode
        except subprocess.TimeoutExpired:
            return "", "Command timed out", -1

    def restore_wallet(self) -> bool:
        """Restore Akash wallet from Storj backup"""
        self.logger.info("Restoring Akash wallet from Storj...")

        # Check if wallet restore script exists (for local testing)
        if not os.path.exists(AKASH_WALLET_RESTORE_SCRIPT):
            self.logger.error(f"Wallet restore script not found: {AKASH_WALLET_RESTORE_SCRIPT}")
            return False

        # First check if wallet already exists
        stdout, stderr, returncode = self.run_command([
            AKASH_WALLET_RESTORE_SCRIPT, 'info'
        ], timeout=30)

        if returncode == 0:
            try:
                result = json.loads(stdout)
                if result.get('status') == 'active':
                    self.wallet_address = result.get('address')
                    self.balance_uakt = int(result.get('balance_uakt', 0))
                    self.logger.info(f"Wallet already exists: {self.wallet_address}")
                    return True
            except json.JSONDecodeError:
                pass

        # If wallet doesn't exist, try direct restoration approach
        self.logger.info("Wallet not found in keyring, attempting direct restore...")
        
        # Try calling the restoration functionality directly, bypassing the wrapper script
        # This is a more robust approach that doesn't depend on the full setup-env.sh
        success = self._restore_wallet_direct()
        
        if success:
            # Verify the wallet was restored by checking again
            stdout, stderr, returncode = self.run_command([
                AKASH_WALLET_RESTORE_SCRIPT, 'info'
            ], timeout=30)
            
            if returncode == 0:
                try:
                    result = json.loads(stdout)
                    if result.get('status') == 'active':
                        self.wallet_address = result.get('address')
                        self.balance_uakt = int(result.get('balance_uakt', 0))
                        self.logger.info(f"Wallet restored: {self.wallet_address}")
                        return True
                except json.JSONDecodeError:
                    pass
        
        self.logger.error("Failed to restore wallet using direct approach")
        return False

    def _restore_wallet_direct(self) -> bool:
        """Direct wallet restoration bypassing setup-env.sh dependencies"""
        try:
            # Set up the required environment for Storj operations
            storj_bucket = os.getenv('IWB_STORJ_WPOPS_BUCKET')
            domain = os.getenv('IWB_DOMAIN')
            project_name = os.getenv('COMPOSE_PROJECT_NAME', 'iwb')
            
            if not storj_bucket or not domain:
                self.logger.error("Missing required environment variables for Storj access")
                return False
            
            # Define paths and names
            backup_filename = f"{domain}_akash_latest.tar.gz"
            storj_path = f"sj://{storj_bucket}/IWBDPP/akash/latest/{backup_filename}"
            temp_dir = "/tmp/iwb-akash-restore"
            backup_file = f"{temp_dir}/{backup_filename}"
            
            # Create temp directory
            os.makedirs(temp_dir, exist_ok=True)
            
            # Download from Storj using uplink
            self.logger.info(f"Downloading wallet backup from Storj: {storj_path}")
            stdout, stderr, returncode = self.run_command([
                'uplink', 'cp', storj_path, backup_file
            ], timeout=60)
            
            if returncode != 0:
                self.logger.error(f"Failed to download from Storj: {stderr}")
                return False
            
            if not os.path.exists(backup_file):
                self.logger.error(f"Backup file not found after download: {backup_file}")
                return False
            
            # Extract the backup
            extract_dir = f"{temp_dir}/extracted"
            os.makedirs(extract_dir, exist_ok=True)
            
            stdout, stderr, returncode = self.run_command([
                'tar', '-xzf', backup_file, '-C', extract_dir
            ], timeout=30)
            
            if returncode != 0:
                self.logger.error(f"Failed to extract backup: {stderr}")
                return False
            
            # Look for the wallet backup JSON
            wallet_backup_file = f"{extract_dir}/{project_name}_akash-deploy-backup.json"
            if not os.path.exists(wallet_backup_file):
                self.logger.error(f"Wallet backup JSON not found: {wallet_backup_file}")
                return False
            
            # Read wallet information
            with open(wallet_backup_file, 'r') as f:
                wallet_data = json.load(f)
            
            wallet_name = wallet_data.get('walletName')
            mnemonic = wallet_data.get('mnemonic')
            
            if not wallet_name or not mnemonic:
                self.logger.error("Invalid wallet backup data")
                return False
            
            # Restore wallet using provider-services
            self.logger.info(f"Restoring wallet to keyring: {wallet_name}")
            
            # Use echo to pipe the mnemonic to the provider-services command
            restore_cmd = f'echo "{mnemonic}" | provider-services keys add "{wallet_name}" --recover --keyring-backend test --interactive=false'
            
            stdout, stderr, returncode = self.run_command([
                'bash', '-c', restore_cmd
            ], timeout=30)
            
            if returncode != 0:
                self.logger.error(f"Failed to restore wallet to keyring: {stderr}")
                return False
            
            # Cleanup temp files
            self.run_command(['rm', '-rf', temp_dir], timeout=10)
            
            self.logger.info("Wallet restored successfully using direct method")
            return True
            
        except Exception as e:
            self.logger.error(f"Direct wallet restoration failed: {e}")
            return False

    def get_wallet_balance(self) -> int:
        """Get current wallet balance in uakt"""
        if not self.wallet_address:
            return 0

        cmd = [
            'provider-services', 'query', 'bank', 'balances', self.wallet_address,
            '--node', AKASH_NODE,
            '--chain-id', AKASH_CHAIN_ID,
            '--output', 'json'
        ]

        stdout, stderr, returncode = self.run_command(cmd, timeout=30)

        if returncode != 0:
            self.logger.error(f"Failed to get balance: {stderr}")
            return 0

        try:
            data = json.loads(stdout)
            for balance in data.get('balances', []):
                if balance.get('denom') == 'uakt':
                    return int(balance.get('amount', 0))
        except json.JSONDecodeError:
            self.logger.error(f"Invalid JSON response from balance query: {stdout}")

        return 0

    def estimate_costs(self, duration_hours: float) -> Dict:
        """Estimate deployment costs"""
        akt_needed = duration_hours * ESTIMATED_COST_PER_HOUR
        uakt_needed = int(akt_needed * 1000000)  # Convert to uakt

        current_balance_akt = self.balance_uakt / 1000000

        return {
            'estimated_cost_uakt': uakt_needed,
            'estimated_cost_akt': akt_needed,
            'current_balance_uakt': self.balance_uakt,
            'current_balance_akt': current_balance_akt,
            'sufficient_funds': self.balance_uakt >= uakt_needed,
            'estimated_runtime_hours': duration_hours
        }

    def check_deployment_feasibility(self) -> Dict:
        """Check if deployment is feasible based on balance and requirements"""
        # Update balance
        self.balance_uakt = self.get_wallet_balance()

        # Estimate minimum cost for deployment
        min_costs = self.estimate_costs(DEPLOYMENT_MINUTES / 60)

        # Check if we have enough for minimum deployment + buffer
        buffer_hours = 1  # 1 hour buffer
        buffer_costs = self.estimate_costs(buffer_hours)

        return {
            'min_deployment': min_costs,
            'with_buffer': buffer_costs,
            'can_deploy': buffer_costs['sufficient_funds']
        }

    def create_deployment_manifest(self, api_credentials: Optional[Dict] = None, custom_yaml: Optional[str] = None) -> str:
        """Create Akash deployment manifest for ComfyUI"""
        if custom_yaml:
            # Use provided custom YAML
            self.logger.info("Using custom deployment manifest")
            manifest_content = custom_yaml
        else:
            # Use default template
            template_path = os.path.join(os.path.dirname(__file__), 'comfyui-deployment-template.yaml')
            try:
                with open(template_path, 'r') as f:
                    manifest_content = f.read()
            except FileNotFoundError:
                self.logger.error(f"Deployment template not found: {template_path}")
                return ""

        # If API credentials provided, inject them into the manifest
        if api_credentials:
            username = api_credentials.get('username', 'comfyui')
            password = api_credentials.get('password', 'default_password')
            api_key = api_credentials.get('api_key', 'default_api_key')
            manifest_content = manifest_content.replace('${COMFYUI_USERNAME}', username)
            manifest_content = manifest_content.replace('${COMFYUI_PASSWORD}', password)
            manifest_content = manifest_content.replace('${COMFYUI_API_KEY}', api_key)
        else:
            # Generate secure defaults
            default_creds = self.generate_api_credentials()
            manifest_content = manifest_content.replace('${COMFYUI_USERNAME}', default_creds['username'])
            manifest_content = manifest_content.replace('${COMFYUI_PASSWORD}', default_creds['password'])
            manifest_content = manifest_content.replace('${COMFYUI_API_KEY}', default_creds['api_key'])

        return manifest_content

    def deploy_to_akash(self) -> Optional[Dict]:
        """Deploy ComfyUI to Akash Network with complete workflow"""
        self.logger.info("Starting Akash deployment...")

        # Create deployment manifest
        # Generate API credentials first to inject into manifest
        temp_credentials = self.generate_api_credentials()
        manifest = self.create_deployment_manifest(temp_credentials, self.custom_manifest)

        # Write manifest to temporary file
        manifest_path = '/tmp/comfyui-deployment.yaml'
        with open(manifest_path, 'w') as f:
            f.write(manifest)

        try:
            # Step 1: Create deployment
            self.logger.info("Creating deployment...")
            cmd_create = [
                'provider-services', 'tx', 'deployment', 'create', manifest_path,
                '--from', AKASH_WALLET_NAME,
                '--node', AKASH_NODE,
                '--chain-id', AKASH_CHAIN_ID,
                '--gas', 'auto',
                '--gas-adjustment', '1.5',
                '--yes'
            ]

            stdout, stderr, returncode = self.run_command(cmd_create, timeout=120)

            if returncode != 0:
                self.logger.error(f"Deployment creation failed: {stderr}")
                return None

            # Extract deployment sequence from output
            deployment_info = self._parse_deployment_output(stdout)

            if not deployment_info:
                self.logger.error("Could not parse deployment information")
                return None

            self.logger.info(f"Deployment created with dseq: {deployment_info['dseq']}")

            # Step 2: Wait for bids
            self.logger.info("Waiting for bids...")
            bids = self._wait_for_bids(deployment_info)

            if not bids:
                self.logger.error("No bids received for deployment")
                return None

            # Step 3: Select best bid
            selected_bid = self._select_best_bid(bids)

            if not selected_bid:
                self.logger.error("Could not select a suitable bid")
                return None

            self.logger.info(f"Selected bid from provider: {selected_bid['provider']}")

            # Step 4: Create lease (accept bid)
            self.logger.info("Creating lease...")
            lease_info = self._create_lease(deployment_info, selected_bid)

            if not lease_info:
                self.logger.error("Failed to create lease")
                return None

            # Step 5: Wait for deployment to be active and get service URL
            self.logger.info("Waiting for deployment to become active...")
            deployment_status = self._wait_for_deployment_ready(deployment_info)

            if not deployment_status:
                self.logger.error("Deployment did not become ready")
                return None

            # Step 6: Check container logs for ComfyUI readiness
            self.logger.info("Checking ComfyUI container logs...")
            comfyui_ready = self._check_comfyui_readiness(deployment_info, deployment_status, temp_credentials)

            if not comfyui_ready:
                self.logger.error("ComfyUI is not ready")
                return None

            # Step 7: Use the same API credentials that were injected into the manifest
            api_credentials = temp_credentials.copy()
            service_url = self._construct_service_url(deployment_status)
            api_credentials['api_url'] = f"{service_url}:{COMFYUI_PORT}"

            return {
                'deployment': deployment_info,
                'lease': lease_info,
                'status': deployment_status,
                'api_credentials': api_credentials,
                'service_url': service_url,
                'comfyui_url': f"{service_url}:{COMFYUI_PORT}"
            }

        finally:
            # Clean up manifest file
            if os.path.exists(manifest_path):
                os.remove(manifest_path)

    def _parse_deployment_output(self, output: str) -> Optional[Dict]:
        """Parse deployment creation output to extract dseq"""
        # Look for deployment sequence in the output
        # provider-services typically outputs something like:
        # "deployment created with dseq: 12345"
        import re

        dseq_match = re.search(r'dseq[:\s]+(\d+)', output, re.IGNORECASE)
        if dseq_match:
            return {
                'dseq': dseq_match.group(1),
                'owner': self.wallet_address
            }

        # Fallback: look for any number that might be dseq
        numbers = re.findall(r'\b(\d{4,})\b', output)
        if numbers:
            return {
                'dseq': numbers[0],
                'owner': self.wallet_address
            }

        self.logger.warning(f"Could not parse dseq from output: {output}")
        return None

    def _wait_for_lease(self, deployment_info: Dict, timeout: int = 300) -> Optional[Dict]:
        """Wait for deployment lease to become active"""
        start_time = time.time()

        while time.time() - start_time < timeout:
            # Query leases
            cmd = [
                'provider-services', 'query', 'deployment', 'leases',
                deployment_info['dseq'],
                '--owner', deployment_info['owner'],
                '--node', AKASH_NODE,
                '--output', 'json'
            ]

            stdout, stderr, returncode = self.run_command(cmd, timeout=30)

            if returncode == 0:
                try:
                    data = json.loads(stdout)
                    leases = data.get('leases', [])

                    if leases:
                        lease = leases[0]
                        if lease.get('state') == 'active':
                            return lease

                except json.JSONDecodeError:
                    pass

            time.sleep(10)

        return None

    def _wait_for_bids(self, deployment_info: Dict, timeout: int = 300) -> Optional[list]:
        """Wait for bids to be received for the deployment"""
        start_time = time.time()
        self.logger.info("Waiting for bids...")

        while time.time() - start_time < timeout:
            # Query bids
            cmd = [
                'provider-services', 'query', 'market', 'bid', 'list',
                '--dseq', deployment_info['dseq'],
                '--owner', deployment_info['owner'],
                '--node', AKASH_NODE,
                '--output', 'json'
            ]

            stdout, stderr, returncode = self.run_command(cmd, timeout=30)

            if returncode == 0:
                try:
                    data = json.loads(stdout)
                    bids = data.get('bids', [])

                    if bids:
                        self.logger.info(f"Received {len(bids)} bids")
                        return bids

                except json.JSONDecodeError:
                    pass

            time.sleep(5)

        return None

    def _select_best_bid(self, bids: list) -> Optional[Dict]:
        """Select the best bid based on location, reputation, and cost"""
        if not bids:
            return None

        # Filter for US-based providers (trustworthy ones)
        us_providers = []
        trusted_providers = [
            'akash1provider',  # Add known trustworthy providers here
            'akash1trusted',
            # Add more as discovered
        ]

        for bid in bids:
            provider = bid.get('bid', {}).get('bid_id', {}).get('provider', '')

            # Check if provider is in US region (this is a simplified check)
            # In practice, you'd query provider attributes
            if any(trusted in provider.lower() for trusted in ['us', 'united', 'america']) or \
               provider in trusted_providers:
                us_providers.append(bid)

        if not us_providers:
            # If no US providers, use any available
            us_providers = bids

        # Sort by price (lowest first)
        us_providers.sort(key=lambda x: float(x.get('bid', {}).get('price', {}).get('amount', '0')))

        # Return the cheapest option
        return us_providers[0] if us_providers else None

    def _create_lease(self, deployment_info: Dict, bid: Dict) -> Optional[Dict]:
        """Create a lease by accepting the selected bid"""
        provider = bid.get('bid', {}).get('bid_id', {}).get('provider', '')
        dseq = deployment_info['dseq']
        gseq = bid.get('bid', {}).get('bid_id', {}).get('gseq', '1')
        oseq = bid.get('bid', {}).get('bid_id', {}).get('oseq', '1')

        self.logger.info(f"Creating lease with provider: {provider}")

        cmd = [
            'provider-services', 'tx', 'market', 'lease', 'create',
            '--dseq', dseq,
            '--gseq', gseq,
            '--oseq', oseq,
            '--provider', provider,
            '--from', AKASH_WALLET_NAME,
            '--node', AKASH_NODE,
            '--chain-id', AKASH_CHAIN_ID,
            '--gas', 'auto',
            '--gas-adjustment', '1.5',
            '--yes'
        ]

        stdout, stderr, returncode = self.run_command(cmd, timeout=120)

        if returncode != 0:
            self.logger.error(f"Lease creation failed: {stderr}")
            return None

        # Return lease information
        return {
            'provider': provider,
            'dseq': dseq,
            'gseq': gseq,
            'oseq': oseq,
            'status': 'created'
        }

    def _wait_for_deployment_ready(self, deployment_info: Dict, timeout: int = 600) -> Optional[Dict]:
        """Wait for deployment to be ready and get service information"""
        start_time = time.time()
        self.logger.info("Waiting for deployment to be ready...")

        while time.time() - start_time < timeout:
            # Query deployment status
            cmd = [
                'provider-services', 'query', 'deployment', 'status',
                deployment_info['dseq'],
                '--owner', deployment_info['owner'],
                '--node', AKASH_NODE,
                '--output', 'json'
            ]

            stdout, stderr, returncode = self.run_command(cmd, timeout=30)

            if returncode == 0:
                try:
                    data = json.loads(stdout)
                    services = data.get('services', {})

                    # Check if services are running
                    if services:
                        service_info = services.get('comfyui', {})
                        if service_info.get('available') == 1:
                            self.logger.info("Deployment is ready!")
                            return data

                except json.JSONDecodeError:
                    pass

            time.sleep(10)

        return None

    def _check_comfyui_readiness(self, deployment_info: Dict, deployment_status: Dict, api_credentials: Optional[Dict] = None, timeout: int = 300) -> bool:
        """Check ComfyUI container logs and API endpoint to ensure it's ready"""
        start_time = time.time()
        self.logger.info("Checking ComfyUI readiness...")

        service_url = self._construct_service_url(deployment_status)
        api_url = f"{service_url}:{COMFYUI_PORT}"

        while time.time() - start_time < timeout:
            # First check: Container logs
            cmd = [
                'provider-services', 'lease', 'logs',
                '--dseq', deployment_info['dseq'],
                '--owner', deployment_info['owner'],
                '--follow=false',
                '--tail=50'
            ]

            stdout, stderr, returncode = self.run_command(cmd, timeout=30)

            if returncode == 0:
                logs = stdout.lower()

                # Check for ComfyUI startup indicators specific to your watchdog script
                comfyui_started = any(indicator in logs for indicator in [
                    'starting comfyui via watchdog',
                    'starting comfyui',
                    'listening on 0.0.0.0:8188',
                    'starting server',
                    'model loaded',
                    'web ui listening',
                    'gpu:',  # From your nvidia-smi output
                    'vram:',
                    'comfyui exited'  # Indicates it was running
                ])

                if comfyui_started:
                    self.logger.info("ComfyUI appears to be started, checking API...")
                    
                    # Second check: API endpoint availability
                    if self._test_comfyui_api(api_url, api_credentials):
                        self.logger.info("ComfyUI API is ready and responding")
                        return True
                    else:
                        self.logger.info("ComfyUI started but API not yet ready, continuing to wait...")

                # Check for common error patterns
                if any(error in logs for error in ['error', 'failed', 'exception', 'traceback']):
                    self.logger.warning(f"Potential issues in logs: {logs[-200:]}")

            time.sleep(15)

        self.logger.warning("ComfyUI readiness check timed out")
        return False

    def _test_comfyui_api(self, api_url: str, api_credentials: Optional[Dict] = None) -> bool:
        """Test if ComfyUI API is responding"""
        try:
            import requests
            
            # Try to access the API info endpoint
            test_url = f"{api_url}/api/v1/system_stats"
            headers = {}
            
            if api_credentials and api_credentials.get('api_key'):
                headers['Authorization'] = f"Bearer {api_credentials['api_key']}"
            
            # Use a short timeout for quick checks
            response = requests.get(test_url, headers=headers, timeout=5)
            
            if response.status_code in [200, 401]:  # 401 means API is running but auth failed
                self.logger.info(f"ComfyUI API responding (status: {response.status_code})")
                return True
            else:
                self.logger.debug(f"ComfyUI API check failed with status: {response.status_code}")
                return False
                
        except ImportError:
            # If requests not available, fall back to curl
            return self._test_comfyui_api_curl(api_url, api_credentials)
        except Exception as e:
            self.logger.debug(f"API test failed: {e}")
            return False

    def _test_comfyui_api_curl(self, api_url: str, api_credentials: Optional[Dict] = None) -> bool:
        """Test ComfyUI API using curl as fallback"""
        try:
            test_url = f"{api_url}/api/v1/system_stats"
            cmd = ['curl', '-s', '-o', '/dev/null', '-w', '%{http_code}', test_url]
            
            if api_credentials and api_credentials.get('api_key'):
                cmd.extend(['-H', f"Authorization: Bearer {api_credentials['api_key']}"])
            
            stdout, stderr, returncode = self.run_command(cmd, timeout=10)
            
            if returncode == 0:
                status_code = stdout.strip()
                if status_code in ['200', '401']:  # API is responding
                    self.logger.info(f"ComfyUI API responding (curl status: {status_code})")
                    return True
            
            return False
            
        except Exception as e:
            self.logger.debug(f"Curl API test failed: {e}")
            return False
        return False

    def _construct_service_url(self, deployment_status: Dict) -> str:
        """Construct the service URL from deployment status"""
        try:
            services = deployment_status.get('services', {})
            comfyui_service = services.get('comfyui', {})

            # Get the forwarded ports
            forwarded_ports = comfyui_service.get('forwarded_ports', {})

            if forwarded_ports:
                # Get the external IP/port
                for port_info in forwarded_ports.values():
                    external_ip = port_info.get('external_ip', '')
                    external_port = port_info.get('external_port', '')

                    if external_ip and external_port:
                        return f"http://{external_ip}:{external_port}"

            # Fallback: try to get from lease info
            lease_info = deployment_status.get('lease', {})
            if lease_info:
                provider = lease_info.get('lease_id', {}).get('provider', '')
                # This would need more complex logic to get the actual service URL
                # For now, return a placeholder
                return f"http://service-{provider[:10]}.akash.network"

        except Exception as e:
            self.logger.error(f"Error constructing service URL: {e}")

        return "http://comfyui-service.akash.network"

    def generate_api_credentials(self, service_url: str = "") -> Dict:
        """Generate API credentials for ComfyUI with enhanced security"""
        # Generate random username (more readable format)
        username = 'comfyui_' + ''.join(secrets.choice(string.ascii_lowercase + string.digits) for _ in range(12))
        
        # Generate secure password (avoid problematic characters for shell/env)
        password = ''.join(secrets.choice(string.ascii_letters + string.digits + '-_') for _ in range(20))
        
        # Generate API key for token-based authentication
        api_key = 'cwb_' + ''.join(secrets.choice(string.ascii_letters + string.digits) for _ in range(32))

        api_url = f"{service_url}:{COMFYUI_PORT}" if service_url else f"http://<deployment-url>:{COMFYUI_PORT}"

        return {
            'username': username,
            'password': password,
            'api_key': api_key,
            'api_url': api_url,
            'auth_header': f'Bearer {api_key}',  # For API requests
            'basic_auth': f'{username}:{password}'  # For web interface
        }

    def send_notification_email(self, subject: str, body: str):
        """Send notification email"""
        try:
            # Use mail command
            mail_from = os.getenv('IWB_MAIL_USER', 'admin') + '@' + os.getenv('IWB_DOMAIN', 'localhost')
            mail_to = mail_from

            cmd = ['mail', '-s', subject, '-r', mail_from, mail_to]
            result = subprocess.run(cmd, input=body, text=True, timeout=30)

            if result.returncode == 0:
                self.logger.info("Notification email sent successfully")
            else:
                self.logger.error("Failed to send notification email")

        except Exception as e:
            self.logger.error(f"Error sending email: {e}")

    def cleanup_wallet(self):
        """Clean up wallet from keyring"""
        self.logger.info("Cleaning up wallet from keyring...")

        # Check if wallet restore script exists (for local testing)
        if not os.path.exists(AKASH_WALLET_RESTORE_SCRIPT):
            self.logger.warning(f"Wallet cleanup script not found: {AKASH_WALLET_RESTORE_SCRIPT}")
            return

        stdout, stderr, returncode = self.run_command([
            AKASH_WALLET_RESTORE_SCRIPT, 'cleanup'
        ], timeout=30)

        if returncode == 0:
            try:
                result = json.loads(stdout)
                self.logger.info(f"Wallet cleanup: {result.get('message', 'Success')}")
            except json.JSONDecodeError:
                self.logger.info("Wallet cleaned up successfully")
        else:
            self.logger.error(f"Failed to cleanup wallet: stdout='{stdout}', stderr='{stderr}', returncode={returncode}")

    def run(self) -> Dict:
        """Main deployment workflow"""
        result = {
            'success': False,
            'message': '',
            'deployment_info': None,
            'api_credentials': None
        }

        try:
            # Step 1: Restore wallet
            if not self.restore_wallet():
                result['message'] = 'Failed to restore wallet'
                return result

            # Step 2: Check deployment feasibility
            feasibility = self.check_deployment_feasibility()

            if not feasibility['can_deploy']:
                result['message'] = f'Insufficient funds for deployment. Need {feasibility["with_buffer"]["estimated_cost_akt"]:.2f} AKT, have {feasibility["with_buffer"]["current_balance_akt"]:.2f} AKT'

                # Send notification email
                subject = f'Akash Deployment Failed - Insufficient Funds ({os.getenv("IWB_DOMAIN", "localhost")})'
                body = f"""
Insufficient AKT balance for ComfyUI deployment.

Current Balance: {feasibility["with_buffer"]["current_balance_akt"]:.2f} AKT
Required (with buffer): {feasibility["with_buffer"]["estimated_cost_akt"]:.2f} AKT

Please fund the wallet: {self.wallet_address}

– IWB DPP System
"""
                self.send_notification_email(subject, body)
                return result

            # Step 3: Deploy to Akash
            deployment_result = self.deploy_to_akash()

            if not deployment_result:
                result['message'] = 'Deployment to Akash failed'
                return result

            # Step 4: Prepare success result
            result['success'] = True
            result['message'] = 'ComfyUI deployment successful'
            result['deployment_info'] = deployment_result
            result['api_credentials'] = deployment_result.get('api_credentials', {})

            # Send success notification
            subject = f'ComfyUI Deployment Successful ({os.getenv("IWB_DOMAIN", "localhost")})'
            body = f"""
ComfyUI has been successfully deployed to Akash Network.

Deployment Details:
- Provider: {deployment_result.get('lease', {}).get('provider', 'N/A')}
- Service URL: {deployment_result.get('comfyui_url', 'N/A')}
- API URL: {deployment_result.get('api_credentials', {}).get('api_url', 'N/A')}
- Username: {deployment_result.get('api_credentials', {}).get('username', 'N/A')}
- Password: {deployment_result.get('api_credentials', {}).get('password', 'N/A')}

Remaining Balance: {feasibility["with_buffer"]["current_balance_akt"] - feasibility["with_buffer"]["estimated_cost_akt"]:.2f} AKT

– IWB DPP System
"""
            self.send_notification_email(subject, body)

        except Exception as e:
            self.logger.error(f"Deployment error: {e}")
            result['message'] = f'Deployment error: {str(e)}'

        finally:
            # Always cleanup wallet
            self.cleanup_wallet()

        return result


    def dry_run(self) -> Dict:
        """Validate configuration and show what would be deployed without actually deploying"""
        result = {
            'success': True,
            'message': 'Dry run completed successfully',
            'validation_results': {},
            'deployment_preview': {}
        }
        
        manifest_path = None  # Initialize to track for cleanup

        try:
            # Step 1: Validate custom manifest if provided (same as before)
            if self.custom_manifest:
                try:
                    # First validate YAML syntax
                    manifest_data = yaml.safe_load(self.custom_manifest)
                    result['validation_results']['yaml_valid'] = True
                    result['validation_results']['yaml_structure'] = 'Valid Akash deployment manifest'
                    
                    # Generate credentials and apply them to the custom manifest
                    api_creds = self.generate_api_credentials()
                    processed_manifest = self.create_deployment_manifest(api_creds, self.custom_manifest)
                    result['deployment_preview']['manifest'] = processed_manifest
                    
                except yaml.YAMLError as e:
                    result['success'] = False
                    result['message'] = f'Invalid YAML manifest: {e}'
                    result['validation_results']['yaml_valid'] = False
                    result['validation_results']['yaml_error'] = str(e)
                    return result
            else:
                # Use default template with credentials
                result['validation_results']['yaml_valid'] = True
                result['validation_results']['yaml_structure'] = 'Using default ComfyUI template'
                api_creds = self.generate_api_credentials()
                processed_manifest = self.create_deployment_manifest(api_creds)
                result['deployment_preview']['manifest'] = processed_manifest

            # Step 2: Actually test wallet restoration functionality
            self.logger.info("Testing wallet restoration functionality...")
            wallet_restored = self.restore_wallet()
            
            if wallet_restored:
                result['validation_results']['wallet_setup'] = 'Wallet restored successfully'
                result['validation_results']['wallet_address'] = self.wallet_address
                result['validation_results']['wallet_balance_uakt'] = self.balance_uakt
                result['validation_results']['wallet_balance_akt'] = self.balance_uakt / 1000000
                
                # Step 3: Get updated balance and estimate costs
                self.logger.info("Checking actual wallet balance...")
                # Update balance in case it changed since restoration
                updated_balance = self.get_wallet_balance()
                if updated_balance > 0:  # Only update if we got a valid balance
                    self.balance_uakt = updated_balance
                
                feasibility = self.check_deployment_feasibility()
                result['deployment_preview']['cost_estimate'] = feasibility.get('with_buffer', {})
                result['validation_results']['deployment_feasible'] = feasibility['can_deploy']
                
            else:
                result['validation_results']['wallet_setup'] = 'Wallet restoration failed'
                # Don't fail the entire dry-run if wallet fails, just note it
                result['validation_results']['deployment_feasible'] = False

            # Step 4: Use the same API credentials that were generated above
            result['deployment_preview']['api_credentials'] = {
                'username': api_creds['username'],
                'password': api_creds['password'],  # Show full password in dry-run
                'api_key': api_creds['api_key'],
                'api_url_pattern': 'https://<provider-ip>:<port>/api'
            }

            result['message'] = 'Configuration validated successfully. Ready for deployment.'

        except Exception as e:
            self.logger.error(f"Dry run error: {e}")
            result['success'] = False
            result['message'] = f'Dry run error: {str(e)}'
        
        finally:
            # Clean up temporary manifest file
            if manifest_path and os.path.exists(manifest_path):
                os.remove(manifest_path)
            
            # Always cleanup wallet keys after dry run
            self.logger.info("Cleaning up wallet keys after dry run...")
            self.cleanup_wallet()

        return result


def main():
    """Main entry point"""
    parser = argparse.ArgumentParser(description='Deploy ComfyUI to Akash Network')
    parser.add_argument('--yaml', '-y', type=str, help='Custom deployment YAML manifest')
    parser.add_argument('--yaml-file', '-f', type=str, help='Path to YAML file containing deployment manifest')
    parser.add_argument('--dry-run', '-d', action='store_true', help='Validate configuration and show what would be deployed without actually deploying')

    args = parser.parse_args()

    # Get custom manifest from arguments
    custom_manifest = None
    if args.yaml:
        custom_manifest = args.yaml
    elif args.yaml_file:
        try:
            with open(args.yaml_file, 'r') as f:
                custom_manifest = f.read()
        except FileNotFoundError:
            print(json.dumps({
                'success': False,
                'message': f'YAML file not found: {args.yaml_file}'
            }))
            sys.exit(1)
        except Exception as e:
            print(json.dumps({
                'success': False,
                'message': f'Error reading YAML file: {e}'
            }))
            sys.exit(1)

    deployer = AkashDeployer()
    deployer.custom_manifest = custom_manifest

    # Run deployment or dry-run
    if args.dry_run:
        result = deployer.dry_run()
    else:
        result = deployer.run()

    # Output result as JSON for n8n consumption
    print(json.dumps(result, indent=2))

    # Exit with appropriate code
    sys.exit(0 if result['success'] else 1)


if __name__ == '__main__':
    main()
