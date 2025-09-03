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

# ComfyUI deployment configuration
COMFYUI_PORT = 8188
DEPLOYMENT_MINUTES = 60  # Minimum deployment time in minutes
ESTIMATED_COST_PER_HOUR = 0.5  # Estimated AKT per hour for GPU deployment

class AkashDeployer:
    def __init__(self):
        self.logger = self._setup_logging()
        self.wallet_address = None
        self.wallet_mnemonic = None  # Store mnemonic when available from backup
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

        # First check if wallet already exists in keyring
        if self._check_wallet_exists():
            self.logger.info(f"Wallet already exists: {self.wallet_address}")
            return True

        # If wallet doesn't exist, try direct restoration approach
        self.logger.info("Wallet not found in keyring, attempting direct restore...")
        
        # Try calling the restoration functionality directly
        success = self._restore_wallet_direct()
        
        if success:
            # Verify the wallet was restored by checking again
            if self._check_wallet_exists():
                self.logger.info(f"Wallet restored: {self.wallet_address}")
                return True
        
        self.logger.error("Failed to restore wallet using direct approach")
        return False

    def _check_wallet_exists(self) -> bool:
        """Check if wallet exists in keyring and get its details"""
        try:
            # List keys to see if wallet exists
            cmd = [
                'provider-services', 'keys', 'list',
                '--keyring-backend', AKASH_KEYRING_BACKEND,
                '--output', 'json'
            ]
            
            stdout, stderr, returncode = self.run_command(cmd, timeout=30)
            
            if returncode == 0:
                try:
                    keys_data = json.loads(stdout)
                    for key in keys_data:
                        if key.get('name') == AKASH_WALLET_NAME:
                            self.wallet_address = key.get('address')
                            # Get balance
                            self.balance_uakt = self.get_wallet_balance()
                            return True
                except json.JSONDecodeError:
                    pass
                    
            return False
            
        except Exception as e:
            self.logger.error(f"Error checking wallet existence: {e}")
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
            
            # Store the mnemonic for future unified backups
            self.wallet_mnemonic = mnemonic
            self.logger.info("Mnemonic captured from backup for future use")
            
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
            
            # Get the wallet address for certificate operations
            self.wallet_address = wallet_data.get('address')
            if not self.wallet_address:
                # If not in backup, query from keyring
                self._update_wallet_address_from_keyring()
            
            # Restore certificates if they exist in the backup
            # Certificate should be named as walletaddress.pem and included in the same backup
            self._restore_certificates_from_backup(extract_dir, project_name)
            
            # Cleanup temp files
            self.run_command(['rm', '-rf', temp_dir], timeout=10)
            
            self.logger.info("Wallet restored successfully using direct method")
            return True
            
        except Exception as e:
            self.logger.error(f"Direct wallet restoration failed: {e}")
            return False

    def _update_wallet_address_from_keyring(self) -> bool:
        """Get wallet address from keyring when not available in backup"""
        try:
            cmd = [
                'provider-services', 'keys', 'show', AKASH_WALLET_NAME,
                '--keyring-backend', AKASH_KEYRING_BACKEND,
                '--address'
            ]
            
            stdout, stderr, returncode = self.run_command(cmd, timeout=30)
            
            if returncode == 0:
                self.wallet_address = stdout.strip()
                self.logger.info(f"Retrieved wallet address from keyring: {self.wallet_address}")
                return True
            else:
                self.logger.error(f"Failed to get wallet address from keyring: {stderr}")
                return False
                
        except Exception as e:
            self.logger.error(f"Error getting wallet address from keyring: {e}")
            return False

    def _restore_certificates_from_backup(self, extract_dir: str, project_name: str) -> bool:
        """Restore Akash certificates from backup if available"""
        try:
            # Certificate is named after the wallet address
            if not self.wallet_address:
                self.logger.error("Cannot restore certificate without wallet address")
                return False
                
            cert_filename = f"{self.wallet_address}.pem"
            cert_file = f"{extract_dir}/{cert_filename}"
            
            if os.path.exists(cert_file):
                # Create certificate directory (Akash stores certs in ~/.akash)
                cert_dir = os.path.expanduser("~/.akash")
                os.makedirs(cert_dir, exist_ok=True)
                
                # Copy certificate with proper naming
                import shutil
                dest_cert = f"{cert_dir}/{cert_filename}"
                shutil.copy2(cert_file, dest_cert)
                
                # Set proper permissions
                os.chmod(dest_cert, 0o600)
                
                self.logger.info(f"Akash certificate restored: {cert_filename}")
                return True
            else:
                self.logger.warning(f"No certificate found in backup: {cert_filename}")
                return self._generate_akash_certificate()
                
        except Exception as e:
            self.logger.error(f"Failed to restore certificate: {e}")
            return self._generate_akash_certificate()

    def _generate_akash_certificate(self) -> bool:
        """Generate and publish Akash certificate (handles both new generation and existing cert publication)"""
        try:
            if not self.wallet_address:
                self.logger.error("Cannot generate certificate without wallet address")
                return False
            
            # Create certificate directory
            cert_dir = os.path.expanduser("~/.akash")
            os.makedirs(cert_dir, exist_ok=True)
            cert_filename = f"{self.wallet_address}.pem"
            cert_path = f"{cert_dir}/{cert_filename}"
            
            # Check if certificate already exists locally
            cert_exists_locally = os.path.exists(cert_path)
            
            if cert_exists_locally:
                self.logger.info("Certificate exists locally - checking blockchain publication...")
                # Check if already published on blockchain
                if self._check_certificate_published():
                    self.logger.info("Certificate already published on blockchain - all good!")
                    return True
                else:
                    self.logger.info("Certificate not published - publishing to blockchain...")
                    return self._publish_existing_certificate()
            
            # Certificate doesn't exist locally - need to generate it
            self.logger.info("Generating new Akash certificate...")
            
            # Step 1: Generate certificate locally using provider-services
            cmd_generate = [
                'provider-services', 'tx', 'cert', 'generate', 'client',
                '--from', AKASH_WALLET_NAME,
                '--node', AKASH_NODE,
                '--chain-id', AKASH_CHAIN_ID,
                '--keyring-backend', AKASH_KEYRING_BACKEND,
                '--gas', 'auto',
                '--gas-adjustment', '1.5',
                '--yes'
            ]
            
            stdout, stderr, returncode = self.run_command(cmd_generate, timeout=60)
            
            if returncode != 0:
                self.logger.error(f"Certificate generation failed: {stderr}")
                # Check for overwrite error - this is okay, proceed to publish
                if 'cannot overwrite certificate' in stderr.lower():
                    self.logger.info("Certificate already exists locally - proceeding to publish step")
                else:
                    self.logger.error("Certificate generation failed for unknown reason")
                    return False
                    return False
            
            # Step 2: Publish certificate to blockchain
            self.logger.info("Publishing certificate to Akash blockchain...") # This requires AKT to pay for the transaction
            if not self._publish_existing_certificate():
                return False
            
            # Verify the certificate file exists locally
            if os.path.exists(cert_path):
                self.logger.info(f"Akash certificate ready: {cert_filename}")
                
                # After successful certificate generation + publication, create a unified backup
                # This is critical because we now have both wallet + certificate
                self._create_unified_backup()
                return True
            else:
                self.logger.error(f"Certificate file not found after generation: {cert_path}")
                return False
                
        except Exception as e:
            self.logger.error(f"Certificate generation failed: {e}")
            return False

    def _create_unified_backup(self) -> bool:
        """Create unified backup containing both wallet mnemonic and certificate"""
        try:
            if not self.wallet_address:
                self.logger.error("Cannot create backup without wallet address")
                return False
            
            self.logger.info("Creating unified Akash backup (wallet + certificate)...")
            
            # Get wallet mnemonic (should always be available from container startup)
            mnemonic = self._extract_wallet_mnemonic()
            if not mnemonic:
                self.logger.error("Cannot create backup without mnemonic")
                return False
            
            # Prepare backup data
            storj_bucket = os.getenv('IWB_STORJ_WPOPS_BUCKET')
            domain = os.getenv('IWB_DOMAIN')
            project_name = os.getenv('COMPOSE_PROJECT_NAME', 'iwb')
            
            if not storj_bucket or not domain:
                self.logger.error("Missing Storj configuration for backup")
                return False
            
            # Create temporary backup directory
            temp_dir = "/tmp/iwb-akash-backup"
            os.makedirs(temp_dir, exist_ok=True)
            
            try:
                # 1. Create wallet backup JSON
                backup_file = f"{temp_dir}/{project_name}_akash-deploy-backup.json"
                wallet_data = {
                    "walletName": AKASH_WALLET_NAME,
                    "mnemonic": mnemonic,
                    "address": self.wallet_address,
                    "createdAt": datetime.utcnow().isoformat() + "Z",
                    "network": "akash",
                    "chainId": AKASH_CHAIN_ID
                }
                
                with open(backup_file, 'w') as f:
                    json.dump(wallet_data, f, indent=2)
                
                # 2. Copy certificate if it exists
                cert_dir = os.path.expanduser("~/.akash")
                cert_filename = f"{self.wallet_address}.pem"
                cert_source = f"{cert_dir}/{cert_filename}"
                
                if os.path.exists(cert_source):
                    cert_dest = f"{temp_dir}/{cert_filename}"
                    import shutil
                    shutil.copy2(cert_source, cert_dest)
                    self.logger.info(f"Certificate included in backup: {cert_filename}")
                else:
                    self.logger.warning(f"Certificate not found for backup: {cert_source}")
                
                # 3. Create tar.gz archive (same format as existing backup system)
                archive_name = f"{domain}_akash_latest.tar.gz"
                archive_path = f"/tmp/{archive_name}"
                
                stdout, stderr, returncode = self.run_command([
                    'tar', '-czf', archive_path, '-C', temp_dir, '.'
                ], timeout=30)
                
                if returncode != 0:
                    self.logger.error(f"Failed to create backup archive: {stderr}")
                    return False
                
                # 4. Upload to Storj
                storj_path = f"sj://{storj_bucket}/IWBDPP/akash/latest/{archive_name}"
                stdout, stderr, returncode = self.run_command([
                    'uplink', 'cp', archive_path, storj_path
                ], timeout=60)
                
                if returncode == 0:
                    self.logger.info(f"Unified Akash backup uploaded successfully: {storj_path}")
                    success = True
                else:
                    self.logger.error(f"Failed to upload backup to Storj: {stderr}")
                    success = False
                
                # 5. Cleanup temp files
                self.run_command(['rm', '-rf', temp_dir], timeout=10)
                self.run_command(['rm', '-f', archive_path], timeout=10)
                
                return success
                
            except Exception as e:
                # Cleanup on error
                self.run_command(['rm', '-rf', temp_dir], timeout=10)
                raise e
                
        except Exception as e:
            self.logger.error(f"Unified backup creation failed: {e}")
            return False

    def _extract_wallet_mnemonic(self) -> str:
        """Get wallet mnemonic for backup purposes"""
        if self.wallet_mnemonic:
            return self.wallet_mnemonic
        
        # This should not happen if container startup worked correctly
        self.logger.error("No mnemonic available - this indicates a container startup issue")
        return ""

    def _load_mnemonic_from_backup(self) -> bool:
        """Load mnemonic from existing backup if wallet already in keyring"""
        try:
            storj_bucket = os.getenv('IWB_STORJ_WPOPS_BUCKET')
            domain = os.getenv('IWB_DOMAIN')
            project_name = os.getenv('COMPOSE_PROJECT_NAME', 'iwb')
            
            if not storj_bucket or not domain:
                self.logger.warning("Cannot load mnemonic - missing Storj configuration")
                return False
            
            # Download and extract backup to get mnemonic
            backup_filename = f"{domain}_akash_latest.tar.gz"
            storj_path = f"sj://{storj_bucket}/IWBDPP/akash/latest/{backup_filename}"
            temp_dir = "/tmp/iwb-mnemonic-load"
            backup_file = f"{temp_dir}/{backup_filename}"
            
            os.makedirs(temp_dir, exist_ok=True)
            
            # Download backup
            stdout, stderr, returncode = self.run_command([
                'uplink', 'cp', storj_path, backup_file
            ], timeout=30)
            
            if returncode != 0:
                self.logger.warning(f"Could not download backup for mnemonic: {stderr}")
                return False
            
            # Extract and read mnemonic
            extract_dir = f"{temp_dir}/extracted"
            os.makedirs(extract_dir, exist_ok=True)
            
            self.run_command(['tar', '-xzf', backup_file, '-C', extract_dir], timeout=10)
            
            wallet_backup_file = f"{extract_dir}/{project_name}_akash-deploy-backup.json"
            if os.path.exists(wallet_backup_file):
                with open(wallet_backup_file, 'r') as f:
                    wallet_data = json.load(f)
                    mnemonic = wallet_data.get('mnemonic', '')
                    if mnemonic:
                        self.wallet_mnemonic = mnemonic
                        self.logger.info("Mnemonic loaded from existing backup")
                        
            # Cleanup
            self.run_command(['rm', '-rf', temp_dir], timeout=10)
            return True
            
        except Exception as e:
            self.logger.warning(f"Could not load mnemonic from backup: {e}")
            return False

    def setup_wallet(self) -> bool:
        """Setup wallet - restore from existing backup (wallet + mnemonic always exist)"""
        try:
            # First check if we already have a wallet in keyring
            if self._check_wallet_exists():
                self.logger.info(f"Using existing wallet: {AKASH_WALLET_NAME}")
                # We still need the mnemonic for unified backups, so try to get it from backup
                self._load_mnemonic_from_backup()
            else:
                # Restore from backup (wallet + mnemonic created at container startup)
                if not self.restore_wallet():
                    self.logger.error("No wallet found and backup restoration failed")
                    self.logger.error("Wallet should have been created at container startup")
                    return False
                self.logger.info("Wallet restored from backup")
            
            # Now check certificate - generate/publish if needed
            if not self._check_certificate_exists():
                self.logger.info("No certificate found - attempting to generate and publish one")
                
                # Try to generate certificate 
                if not self._generate_akash_certificate():
                    self.logger.error("Certificate generation failed")
                    return False
                
                self.logger.info("Certificate generated and published successfully")
            
            return True
            
        except Exception as e:
            self.logger.error(f"Wallet setup failed: {e}")
            return False

    def _check_certificate_exists(self) -> bool:
        """Check if Akash certificate exists for current wallet"""
        if not self.wallet_address:
            self.logger.error("Cannot check certificate without wallet address")
            return False
            
        cert_dir = os.path.expanduser("~/.akash")
        cert_filename = f"{self.wallet_address}.pem"
        cert_path = f"{cert_dir}/{cert_filename}"
        
        exists = os.path.exists(cert_path)
        if exists:
            self.logger.info(f"Found existing certificate: {cert_filename}")
        else:
            self.logger.info(f"No certificate found for wallet: {self.wallet_address}")
            
        return exists

    def _check_certificate_published(self) -> bool:
        """Check if certificate is published on Akash blockchain"""
        try:
            if not self.wallet_address:
                return False
                
            self.logger.info("Checking if certificate is published on blockchain...")
            
            # Query certificate from blockchain
            cmd = [
                'provider-services', 'query', 'cert', 'list',
                '--owner', self.wallet_address,
                '--node', AKASH_NODE,
                '--chain-id', AKASH_CHAIN_ID,
                '--output', 'json'
            ]
            
            stdout, stderr, returncode = self.run_command(cmd, timeout=30)
            
            if returncode != 0:
                self.logger.warning(f"Failed to query certificate from blockchain: {stderr}")
                return False
            
            try:
                data = json.loads(stdout)
                certificates = data.get('certificates', [])
                
                if certificates:
                    self.logger.info(f"Found {len(certificates)} certificate(s) published on blockchain")
                    return True
                else:
                    self.logger.info("No certificates found on blockchain for this wallet")
                    return False
                    
            except json.JSONDecodeError:
                self.logger.warning(f"Invalid JSON response from certificate query: {stdout}")
                return False
                
        except Exception as e:
            self.logger.error(f"Error checking certificate publication: {e}")
            return False

    def _publish_existing_certificate(self) -> bool:
        """Publish existing local certificate to blockchain"""
        try:
            if not self.wallet_address:
                self.logger.error("Cannot publish certificate without wallet address")
                return False
                
            self.logger.info("Publishing existing certificate to Akash blockchain...")
            
            cmd_publish = [
                'provider-services', 'tx', 'cert', 'publish', 'client',
                '--from', AKASH_WALLET_NAME,
                '--node', AKASH_NODE,
                '--chain-id', AKASH_CHAIN_ID,
                '--keyring-backend', AKASH_KEYRING_BACKEND,
                '--gas', 'auto',
                '--gas-adjustment', '1.5',
                '--yes'
            ]
            
            stdout, stderr, returncode = self.run_command(cmd_publish, timeout=60)
            
            if returncode != 0:
                self.logger.error(f"Certificate publication failed: {stderr}")
                # Check if already published
                if 'certificate exists' in stderr.lower() or 'already exists' in stderr.lower():
                    self.logger.info("Certificate already published to blockchain - this is fine")
                    return True
                elif 'insufficient' in stderr.lower():
                    self.logger.error("Certificate publication failed due to insufficient AKT balance")
                    self.logger.error("Fund the wallet with AKT and try again")
                    return False
                else:
                    return False
            else:
                self.logger.info("Certificate successfully published to blockchain")
                
                # Send certificate publication confirmation email
                self._send_certificate_publication_email(stdout)
                return True
                
        except Exception as e:
            self.logger.error(f"Failed to publish certificate: {e}")
            return False

    def _send_certificate_publication_email(self, tx_output: str) -> None:
        """Send email notification when certificate is published to blockchain"""
        try:
            # Extract transaction hash from output
            tx_hash = self._extract_transaction_hash(tx_output)
            
            # Get current balance for context
            current_balance_akt = self.balance_uakt / 1000000
            
            # Get Storj backup path for certificate location
            storj_bucket = os.getenv('IWB_STORJ_WPOPS_BUCKET', 'unknown-bucket')
            domain = os.getenv('IWB_DOMAIN', 'localhost')
            storj_backup_path = f"sj://{storj_bucket}/IWBDPP/akash/latest/{domain}_akash_latest.tar.gz"
            
            subject = f'Akash Certificate Published Successfully ({domain})'
            body = f"""
🎉 Akash Network Certificate Published Successfully!

Your Akash certificate has been successfully published to the blockchain. This is a one-time setup that enables your wallet to deploy services on the Akash Network.

Certificate Details:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
• Wallet Address: {self.wallet_address}
• Wallet Name: {AKASH_WALLET_NAME}
• Chain ID: {AKASH_CHAIN_ID}
• Certificate Status: Published to Blockchain ✅
• Certificate Backup: {storj_backup_path}
• Certificate Filename: {self.wallet_address}.pem

Transaction Details:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
• Transaction Hash: {tx_hash}
• Network: Akash Network (akashnet-2)
• Explorer: https://www.mintscan.io/akash/tx/{tx_hash}

Wallet Status:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
• Current AKT Balance: {current_balance_akt:.6f} AKT
• Ready for Deployments: Yes ✅

Important Notes:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✅ This certificate is valid indefinitely and only needs to be published once
✅ Your wallet can now create deployments on the Akash Network
✅ Certificate + wallet backed up to Storj (permanent storage)
⚠️  Local certificate files are ephemeral (restored from Storj only as needed)
⚠️  Your wallet mnemonic is stored securely in your Storj encrypted storage for account recovery

Storage Information:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
• Permanent Backup: Storj encrypted storage
• Backup Contents: Wallet mnemonic + Certificate (.pem)
• Restoration: Automatic on container startup

Next Steps:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
• You can now deploy ComfyUI instances to Akash
• Ensure sufficient AKT balance for deployment operations
• Monitor deployments through n8n workflows

– IWB Digital Presence Platform
System Timestamp: {datetime.utcnow().isoformat()}Z
"""
            
            self.send_notification_email(subject, body)
            self.logger.info("Certificate publication confirmation email sent")
            
        except Exception as e:
            self.logger.warning(f"Failed to send certificate publication email: {e}")

    def _extract_transaction_hash(self, tx_output: str) -> str:
        """Extract transaction hash from provider-services output"""
        try:
            # Look for transaction hash in the output
            # provider-services typically outputs JSON or includes txhash field
            import re
            
            # Try to find txhash in JSON response
            if 'txhash' in tx_output.lower():
                # Look for txhash field in JSON or plain text
                hash_match = re.search(r'"?txhash"?\s*:?\s*"?([A-Fa-f0-9]{64})"?', tx_output, re.IGNORECASE)
                if hash_match:
                    return hash_match.group(1)
            
            # Fallback: look for any 64-character hex string (typical transaction hash)
            hash_match = re.search(r'\b([A-Fa-f0-9]{64})\b', tx_output)
            if hash_match:
                return hash_match.group(1)
            
            # If no hash found, return a truncated output for reference
            return tx_output[:100] + "..." if len(tx_output) > 100 else tx_output
            
        except Exception as e:
            self.logger.warning(f"Failed to extract transaction hash: {e}")
            return "Unable to extract transaction hash"

    def _backup_certificate_to_storj(self, cert_path: str, cert_filename: str) -> bool:
        """Back up the certificate to Storj as part of the unified Akash backup"""
        try:
            # The certificate should be backed up along with the wallet in the existing
            # iwb-backup.sh akash snapshot process. For now, we'll document this need.
            self.logger.info("Certificate should be included in next 'iwb-backup.sh akash snapshot'")
            self.logger.info(f"Certificate location: {cert_path}")
            
            # TODO: Integrate with the unified backup system 
            # The certificate needs to be included in the tar.gz backup that also
            # contains the {project_name}_akash-deploy-backup.json file
            
            return True
                
        except Exception as e:
            self.logger.error(f"Certificate backup failed: {e}")
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
            'sufficient_akt': self.balance_uakt >= uakt_needed,
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
            'can_deploy': buffer_costs['sufficient_akt']
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

        # Certificate should already be handled by setup_wallet() from run()
        # But double-check in case this method is called directly
        if not self._check_certificate_exists():
            self.logger.error("No certificate found - this should have been handled by setup_wallet()")
            return None

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

            # Store provider in deployment_info for later use
            deployment_info['provider'] = lease_info['provider']

            # Step 5: Send manifest to provider
            self.logger.info("Sending manifest to provider...")
            manifest_sent = self._send_manifest_to_provider(deployment_info, lease_info, manifest_path)
            
            if not manifest_sent:
                self.logger.error("Failed to send manifest to provider")
                return None

            # Step 6: Wait for deployment to be active and get service URL
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
            'akash1365yvmc4s7awdyj3n2sav7xfx76adc6dnmlx63',  # Known good provider
            'akash18qa2a2ltfyvkyj0ggj3hkvuj6twzyumuaru9s4',  # Another known provider
        ]

        for bid in bids:
            bid_data = bid.get('bid', {})
            bid_id = bid_data.get('bid_id', {})
            provider = bid_id.get('provider', '')

            # Check if provider is trusted or appears to be US-based
            is_trusted = provider in trusted_providers
            
            # Simple heuristic check for US providers (this is basic and should be improved)
            is_likely_us = any(indicator in provider.lower() for indicator in ['us', 'america', 'usa'])
            
            if is_trusted or is_likely_us:
                us_providers.append(bid)

        if not us_providers:
            # If no US providers, use any available but log a warning
            self.logger.warning("No US or trusted providers found, selecting from all available bids")
            us_providers = bids

        # Sort by price (lowest first) - need to handle the nested structure properly
        def get_bid_amount(bid):
            try:
                return float(bid.get('bid', {}).get('price', {}).get('amount', '999999999'))
            except (ValueError, TypeError):
                return 999999999  # Put invalid bids at the end

        us_providers.sort(key=get_bid_amount)

        # Return the cheapest option
        selected = us_providers[0] if us_providers else None
        if selected:
            price = selected.get('bid', {}).get('price', {}).get('amount', 'unknown')
            provider = selected.get('bid', {}).get('bid_id', {}).get('provider', 'unknown')
            self.logger.info(f"Selected provider {provider[:20]}... with price {price} uakt")
        
        return selected

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

    def _send_manifest_to_provider(self, deployment_info: Dict, lease_info: Dict, manifest_path: str) -> bool:
        """Send the deployment manifest to the selected provider"""
        try:
            cmd = [
                'provider-services', 'send-manifest',
                manifest_path,
                '--dseq', deployment_info['dseq'],
                '--provider', lease_info['provider'],
                '--from', AKASH_WALLET_NAME,
                '--node', AKASH_NODE,
                '--chain-id', AKASH_CHAIN_ID,
                '--keyring-backend', AKASH_KEYRING_BACKEND,
                '--gas', 'auto',
                '--gas-adjustment', '1.5',
                '--yes'
            ]

            stdout, stderr, returncode = self.run_command(cmd, timeout=120)

            if returncode != 0:
                self.logger.error(f"Failed to send manifest: {stderr}")
                return False

            self.logger.info("Manifest sent to provider successfully")
            return True

        except Exception as e:
            self.logger.error(f"Error sending manifest to provider: {e}")
            return False

    def _wait_for_deployment_ready(self, deployment_info: Dict, timeout: int = 600) -> Optional[Dict]:
        """Wait for deployment to be ready and get service information"""
        start_time = time.time()
        self.logger.info("Waiting for deployment to be ready...")

        while time.time() - start_time < timeout:
            # Query deployment status using lease-status command
            cmd = [
                'provider-services', 'lease-status',
                '--dseq', deployment_info['dseq'],
                '--from', AKASH_WALLET_NAME,
                '--provider', deployment_info.get('provider', ''),
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
                        # Look for any service that's available
                        for service_name, service_info in services.items():
                            if service_info.get('available') >= 1:
                                self.logger.info(f"Deployment is ready! Service {service_name} available")
                                return data

                except json.JSONDecodeError as e:
                    self.logger.debug(f"Failed to parse deployment status JSON: {e}")

            # Also try the generic query approach as fallback
            cmd_fallback = [
                'provider-services', 'query', 'deployment', 'get',
                '--dseq', deployment_info['dseq'],
                '--owner', deployment_info['owner'],
                '--node', AKASH_NODE,
                '--output', 'json'
            ]

            stdout, stderr, returncode = self.run_command(cmd_fallback, timeout=30)
            if returncode == 0:
                try:
                    data = json.loads(stdout)
                    state = data.get('deployment', {}).get('state')
                    if state == 'active':
                        self.logger.info("Deployment is active!")
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
        """Clean up wallet from keyring and certificates"""
        self.logger.info("Cleaning up wallet from keyring and certificates...")

        try:
            # Clean up certificates first
            self._cleanup_certificates()
            
            # Delete the wallet from keyring using provider-services
            cmd = [
                'provider-services', 'keys', 'delete', AKASH_WALLET_NAME,
                '--keyring-backend', AKASH_KEYRING_BACKEND,
                '--yes'
            ]
            
            stdout, stderr, returncode = self.run_command(cmd, timeout=30)

            if returncode == 0:
                self.logger.info("Wallet cleaned up successfully")
            else:
                # Check if the error is just that the key doesn't exist
                if 'not found' in stderr.lower() or 'does not exist' in stderr.lower():
                    self.logger.info("Wallet was not in keyring (already clean)")
                else:
                    self.logger.error(f"Failed to cleanup wallet: {stderr}")
                    
        except Exception as e:
            self.logger.error(f"Error during wallet cleanup: {e}")

    def _cleanup_certificates(self):
        """Clean up Akash certificates"""
        try:
            if self.wallet_address:
                cert_dir = os.path.expanduser("~/.akash")
                cert_file = f"{cert_dir}/{self.wallet_address}.pem"
                
                if os.path.exists(cert_file):
                    os.remove(cert_file)
                    self.logger.info(f"Certificate cleaned up: {self.wallet_address}.pem")
                
        except Exception as e:
            self.logger.error(f"Error cleaning up certificates: {e}")

    def run(self) -> Dict:
        """Main deployment workflow"""
        result = {
            'success': False,
            'message': '',
            'deployment_info': None,
            'api_credentials': None
        }

        try:
            # Step 1: Setup wallet (handles restore + certificate setup)
            if not self.setup_wallet():
                result['message'] = 'Failed to setup wallet'
                return result

            # Step 2: Check deployment feasibility
            feasibility = self.check_deployment_feasibility()

            if not feasibility['can_deploy']:
                result['message'] = f'Insufficient AKT for deployment. Need {feasibility["with_buffer"]["estimated_cost_akt"]:.2f} AKT, have {feasibility["with_buffer"]["current_balance_akt"]:.2f} AKT'

                # Send notification email
                subject = f'Akash Deployment Failed - Insufficient AKT ({os.getenv("IWB_DOMAIN", "localhost")})'
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
