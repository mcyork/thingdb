"""
Package Verification Service
Handles certificate validation and package verification for the update system
"""
import os
import json
import hashlib
import tempfile
import tarfile
from pathlib import Path
from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import padding
from cryptography.exceptions import InvalidSignature
import logging

logger = logging.getLogger(__name__)

class PackageVerificationService:
    """Service for verifying update packages and their signatures"""
    
    def __init__(self, cert_chain_path=None, allow_unsigned=False):
        """
        Initialize the verification service
        
        Args:
            cert_chain_path: Path to the certificate chain file
            allow_unsigned: Whether to allow unsigned packages (for testing)
        """
        self.cert_chain_path = cert_chain_path or self._get_default_cert_path()
        self.allow_unsigned = allow_unsigned
        self.cert_chain = None
        self._load_certificate_chain()
    
    def _get_default_cert_path(self):
        """Get the default certificate chain path"""
        # Look for certificate chain in the project root
        project_root = Path(__file__).parent.parent.parent
        return project_root / "signing-certs-and-root" / "certificate-chain.crt"
    
    def _load_certificate_chain(self):
        """Load the certificate chain from file"""
        try:
            if not os.path.exists(self.cert_chain_path):
                logger.warning(f"Certificate chain not found at {self.cert_chain_path}")
                if not self.allow_unsigned:
                    raise FileNotFoundError(f"Certificate chain not found: {self.cert_chain_path}")
                return
            
            with open(self.cert_chain_path, 'rb') as f:
                cert_data = f.read()
            
            # Parse the certificate chain (concatenated certificates)
            self.cert_chain = []
            cert_pem_start = b"-----BEGIN CERTIFICATE-----"
            cert_pem_end = b"-----END CERTIFICATE-----"
            
            start = 0
            while True:
                start_pos = cert_data.find(cert_pem_start, start)
                if start_pos == -1:
                    break
                
                end_pos = cert_data.find(cert_pem_end, start_pos)
                if end_pos == -1:
                    break
                
                cert_pem = cert_data[start_pos:end_pos + len(cert_pem_end)]
                cert = x509.load_pem_x509_certificate(cert_pem)
                self.cert_chain.append(cert)
                
                start = end_pos + len(cert_pem_end)
            
            logger.info(f"Loaded {len(self.cert_chain)} certificates from chain")
            
        except Exception as e:
            logger.error(f"Failed to load certificate chain: {e}")
            if not self.allow_unsigned:
                raise
    
    def verify_package_signature(self, package_path, signature_path):
        """
        Verify the signature of a package
        
        Args:
            package_path: Path to the package file
            signature_path: Path to the signature file
            
        Returns:
            tuple: (is_valid, error_message)
        """
        try:
            if not os.path.exists(package_path):
                return False, f"Package file not found: {package_path}"
            
            if not os.path.exists(signature_path):
                return False, f"Signature file not found: {signature_path}"
            
            if not self.cert_chain:
                if self.allow_unsigned:
                    logger.warning("No certificate chain loaded, allowing unsigned package")
                    return True, "Unsigned package allowed"
                return False, "No certificate chain available for verification"
            
            # Read the package and signature
            with open(package_path, 'rb') as f:
                package_data = f.read()
            
            with open(signature_path, 'rb') as f:
                signature_data = f.read()
            
            # For OpenSSL dgst signatures, we need to verify against the raw data, not the hash
            # Try to verify with each certificate in the chain (try intermediate first)
            for i, cert in enumerate(reversed(self.cert_chain)):
                try:
                    logger.info(f"Trying certificate {i}: {cert.subject}")
                    # Get the public key from the certificate
                    public_key = cert.public_key()
                    
                    # Verify the signature (OpenSSL dgst creates signatures of the data, not the hash)
                    public_key.verify(
                        signature_data,
                        package_data,
                        padding.PKCS1v15(),
                        hashes.SHA256()
                    )
                    
                    logger.info(f"Package signature verified with certificate: {cert.subject}")
                    return True, "Signature verified successfully"
                    
                except InvalidSignature as e:
                    logger.warning(f"Invalid signature with certificate {cert.subject}: {e}")
                    continue
                except Exception as e:
                    logger.warning(f"Verification failed with certificate {cert.subject}: {e}")
                    continue
            
            return False, "Signature verification failed with all certificates in chain"
            
        except Exception as e:
            logger.error(f"Package verification error: {e}")
            return False, f"Verification error: {str(e)}"
    
    def verify_package_manifest(self, manifest_path):
        """
        Verify the package manifest
        
        Args:
            manifest_path: Path to the manifest file
            
        Returns:
            tuple: (is_valid, manifest_data, error_message)
        """
        try:
            if not os.path.exists(manifest_path):
                return False, None, f"Manifest file not found: {manifest_path}"
            
            with open(manifest_path, 'r') as f:
                manifest_data = json.load(f)
            
            # Validate required fields
            required_fields = ['version', 'package_hash', 'rollback_safe', 'restarts_expected']
            for field in required_fields:
                if field not in manifest_data:
                    return False, None, f"Missing required field in manifest: {field}"
            
            # Validate package hash if package exists
            package_name = manifest_data.get('package_name', '')
            if package_name:
                package_path = os.path.join(os.path.dirname(manifest_path), f"{package_name}.tar.gz")
                if os.path.exists(package_path):
                    with open(package_path, 'rb') as f:
                        package_data = f.read()
                    
                    calculated_hash = hashlib.sha256(package_data).hexdigest()
                    if calculated_hash != manifest_data['package_hash']:
                        return False, None, "Package hash mismatch in manifest"
            
            return True, manifest_data, "Manifest verified successfully"
            
        except json.JSONDecodeError as e:
            return False, None, f"Invalid JSON in manifest: {e}"
        except Exception as e:
            logger.error(f"Manifest verification error: {e}")
            return False, None, f"Manifest verification error: {str(e)}"
    
    def extract_package(self, package_path, extract_to=None):
        """
        Extract a package to a temporary or specified directory
        
        Args:
            package_path: Path to the package file
            extract_to: Directory to extract to (if None, uses temp directory)
            
        Returns:
            tuple: (extract_path, error_message)
        """
        try:
            if extract_to is None:
                extract_to = tempfile.mkdtemp(prefix="inventory_update_")
            
            with tarfile.open(package_path, 'r:gz') as tar:
                tar.extractall(extract_to)
            
            logger.info(f"Package extracted to: {extract_to}")
            return extract_to, None
            
        except Exception as e:
            logger.error(f"Package extraction error: {e}")
            return None, f"Extraction error: {str(e)}"
    
    def verify_complete_package(self, bundle_path):
        """
        Verify a complete package bundle (package + signature + manifest)
        
        Args:
            bundle_path: Path to the bundle file
            
        Returns:
            dict: Verification result with status and details
        """
        result = {
            'valid': False,
            'package_path': None,
            'signature_path': None,
            'manifest_path': None,
            'manifest_data': None,
            'errors': [],
            'warnings': []
        }
        
        try:
            # Extract the bundle
            extract_path, error = self.extract_package(bundle_path)
            if error:
                result['errors'].append(f"Bundle extraction failed: {error}")
                return result
            
            result['extract_path'] = extract_path
            
            # Look for package files
            package_files = []
            signature_files = []
            manifest_files = []
            
            for root, dirs, files in os.walk(extract_path):
                for file in files:
                    if file.endswith('.tar.gz') and not file.endswith('-bundle.tar.gz'):
                        package_files.append(os.path.join(root, file))
                    elif file.endswith('.sig'):
                        signature_files.append(os.path.join(root, file))
                    elif file.endswith('-manifest.json'):
                        manifest_files.append(os.path.join(root, file))
            
            if not package_files:
                result['errors'].append("No package file found in bundle")
                return result
            
            if not signature_files:
                result['errors'].append("No signature file found in bundle")
                return result
            
            if not manifest_files:
                result['errors'].append("No manifest file found in bundle")
                return result
            
            result['package_path'] = package_files[0]
            result['signature_path'] = signature_files[0]
            result['manifest_path'] = manifest_files[0]
            
            # Verify manifest
            manifest_valid, manifest_data, manifest_error = self.verify_package_manifest(result['manifest_path'])
            if not manifest_valid:
                result['errors'].append(f"Manifest verification failed: {manifest_error}")
                return result
            
            result['manifest_data'] = manifest_data
            
            # Verify signature
            signature_valid, signature_error = self.verify_package_signature(
                result['package_path'], 
                result['signature_path']
            )
            
            if not signature_valid:
                result['errors'].append(f"Signature verification failed: {signature_error}")
                return result
            
            result['valid'] = True
            result['warnings'].append("Package verification completed successfully")
            
        except Exception as e:
            logger.error(f"Complete package verification error: {e}")
            result['errors'].append(f"Verification error: {str(e)}")
        
        return result
