"""
Printing Service for Inventory Management System
Handles local printing on Raspberry Pi using CUPS
"""
import os
import tempfile
import subprocess
import qrcode
from PIL import Image, ImageDraw, ImageFont
from datetime import datetime
from typing import List, Dict, Optional
import logging

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


class PrintingService:
    """Service for handling all printing operations"""
    
    def __init__(self):
        self.default_printer = self._get_default_printer()
        self.font_path = self._find_system_font()
        
    def _get_default_printer(self) -> Optional[str]:
        """Get the default printer name"""
        try:
            result = subprocess.run(
                ['lpstat', '-d'], 
                capture_output=True, text=True, timeout=10
            )
            if (result.returncode == 0 and 
                'system default destination:' in result.stdout):
                # Extract printer name from output like 
                # "system default destination: HP_LaserJet"
                lines = result.stdout.strip().split('\n')
                for line in lines:
                    if 'system default destination:' in line:
                        return line.split(':')[1].strip()
            return None
        except (subprocess.TimeoutExpired, subprocess.CalledProcessError, 
                FileNotFoundError):
            logger.warning("Could not determine default printer")
            return None
    
    def _find_system_font(self) -> str:
        """Find a suitable system font for printing"""
        font_paths = [
            '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
            '/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf',
            '/System/Library/Fonts/Helvetica.ttc',  # macOS
            '/usr/share/fonts/truetype/ubuntu/Ubuntu-R.ttf'
        ]
        
        for path in font_paths:
            if os.path.exists(path):
                return path
        
        # Fallback to default
        return None
    
    def get_available_printers(self) -> List[Dict[str, str]]:
        """Get list of available printers"""
        try:
            result = subprocess.run(['lpstat', '-p'], 
                                  capture_output=True, text=True, timeout=10)
            printers = []
            
            if result.returncode == 0:
                lines = result.stdout.strip().split('\n')
                for line in lines:
                    if line.startswith('printer'):
                        # Parse line like "printer HP_LaserJet is idle.  enabled since Mon 01 Jan 2024 12:00:00 PM"
                        parts = line.split()
                        if len(parts) >= 3:
                            name = parts[1]
                            status = ' '.join(parts[2:])
                            printers.append({
                                'name': name,
                                'status': status,
                                'is_default': name == self.default_printer
                            })
            
            return printers
        except (subprocess.TimeoutExpired, subprocess.CalledProcessError, FileNotFoundError):
            logger.error("Failed to get printer list")
            return []
    
    def print_inventory_list(self, items: List[Dict], printer_name: Optional[str] = None) -> bool:
        """Print a formatted inventory list"""
        try:
            # Generate HTML content
            html_content = self._generate_inventory_list_html(items)
            
            # Create temporary file
            with tempfile.NamedTemporaryFile(mode='w', suffix='.html', delete=False) as f:
                f.write(html_content)
                temp_file = f.name
            
            # Print the file
            success = self._print_file(temp_file, printer_name, "Inventory List")
            
            # Clean up
            os.unlink(temp_file)
            
            return success
        except Exception as e:
            logger.error(f"Failed to print inventory list: {e}")
            return False
    
    def print_qr_codes(self, items: List[Dict], printer_name: Optional[str] = None) -> bool:
        """Print QR codes for items"""
        try:
            # Generate QR code images
            qr_images = []
            for item in items:
                qr_img = self._generate_qr_code(item['guid'], item.get('item_name', ''))
                qr_images.append(qr_img)
            
            # Create combined image for printing
            combined_image = self._combine_qr_codes(qr_images)
            
            # Save to temporary file
            with tempfile.NamedTemporaryFile(suffix='.png', delete=False) as f:
                combined_image.save(f.name, 'PNG')
                temp_file = f.name
            
            # Print the file
            success = self._print_file(temp_file, printer_name, "QR Codes")
            
            # Clean up
            os.unlink(temp_file)
            
            return success
        except Exception as e:
            logger.error(f"Failed to print QR codes: {e}")
            return False
    
    def print_item_details(self, item: Dict, printer_name: Optional[str] = None) -> bool:
        """Print detailed information for a specific item"""
        try:
            # Generate HTML content
            html_content = self._generate_item_details_html(item)
            
            # Create temporary file
            with tempfile.NamedTemporaryFile(mode='w', suffix='.html', delete=False) as f:
                f.write(html_content)
                temp_file = f.name
            
            # Print the file
            success = self._print_file(temp_file, printer_name, f"Item: {item.get('item_name', 'Unknown')}")
            
            # Clean up
            os.unlink(temp_file)
            
            return success
        except Exception as e:
            logger.error(f"Failed to print item details: {e}")
            return False
    
    def _generate_qr_code(self, guid: str, item_name: str) -> Image.Image:
        """Generate QR code image for an item"""
        # Create QR code
        qr = qrcode.QRCode(
            version=1,
            error_correction=qrcode.constants.ERROR_CORRECT_L,
            box_size=10,
            border=4,
        )
        qr.add_data(guid)
        qr.make(fit=True)
        
        # Create QR code image
        qr_img = qr.make_image(fill_color="black", back_color="white")
        
        # Add text label below QR code
        label_img = Image.new('RGB', (qr_img.width, qr_img.height + 40), 'white')
        label_img.paste(qr_img, (0, 0))
        
        # Add text
        draw = ImageDraw.Draw(label_img)
        if self.font_path:
            try:
                font = ImageFont.truetype(self.font_path, 12)
            except:
                font = ImageFont.load_default()
        else:
            font = ImageFont.load_default()
        
        # Draw item name
        text = item_name[:20] + "..." if len(item_name) > 20 else item_name
        text_bbox = draw.textbbox((0, 0), text, font=font)
        text_width = text_bbox[2] - text_bbox[0]
        text_x = (label_img.width - text_width) // 2
        draw.text((text_x, qr_img.height + 5), text, fill='black', font=font)
        
        # Draw GUID
        guid_short = guid[:8] + "..."
        guid_bbox = draw.textbbox((0, 0), guid_short, font=font)
        guid_width = guid_bbox[2] - guid_bbox[0]
        guid_x = (label_img.width - guid_width) // 2
        draw.text((guid_x, qr_img.height + 20), guid_short, fill='gray', font=font)
        
        return label_img
    
    def _combine_qr_codes(self, qr_images: List[Image.Image]) -> Image.Image:
        """Combine multiple QR codes into a single image for printing"""
        if not qr_images:
            return Image.new('RGB', (400, 400), 'white')
        
        # Calculate layout (3 columns)
        cols = 3
        rows = (len(qr_images) + cols - 1) // cols
        
        # Get dimensions
        qr_width, qr_height = qr_images[0].size
        margin = 20
        
        # Create combined image
        combined_width = cols * qr_width + (cols + 1) * margin
        combined_height = rows * qr_height + (rows + 1) * margin
        
        combined_img = Image.new('RGB', (combined_width, combined_height), 'white')
        
        # Place QR codes
        for i, qr_img in enumerate(qr_images):
            row = i // cols
            col = i % cols
            
            x = margin + col * (qr_width + margin)
            y = margin + row * (qr_height + margin)
            
            combined_img.paste(qr_img, (x, y))
        
        return combined_img
    
    def _generate_inventory_list_html(self, items: List[Dict]) -> str:
        """Generate HTML for inventory list printing"""
        html = f"""
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="UTF-8">
            <title>Inventory List</title>
            <style>
                body {{ font-family: Arial, sans-serif; margin: 20px; }}
                .header {{ text-align: center; margin-bottom: 30px; }}
                .header h1 {{ margin: 0; color: #333; }}
                .header .date {{ color: #666; margin-top: 5px; }}
                table {{ width: 100%; border-collapse: collapse; margin-top: 20px; }}
                th, td {{ border: 1px solid #ddd; padding: 8px; text-align: left; }}
                th {{ background-color: #f5f5f5; font-weight: bold; }}
                .item-name {{ font-weight: bold; }}
                .item-guid {{ font-family: monospace; font-size: 12px; color: #666; }}
                .item-date {{ font-size: 12px; color: #999; }}
                .summary {{ margin-top: 20px; padding: 10px; background-color: #f9f9f9; }}
            </style>
        </head>
        <body>
            <div class="header">
                <h1>Inventory List</h1>
                <div class="date">Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}</div>
            </div>
            
            <table>
                <thead>
                    <tr>
                        <th>#</th>
                        <th>Name</th>
                        <th>Description</th>
                        <th>Created</th>
                        <th>Images</th>
                    </tr>
                </thead>
                <tbody>
        """
        
        for i, item in enumerate(items, 1):
            html += f"""
                    <tr>
                        <td>{item.get('label_number', i)}</td>
                        <td class="item-name">{item.get('item_name', 'Unnamed Item')}</td>
                        <td>{item.get('description', '')[:50]}{'...' if len(item.get('description', '')) > 50 else ''}</td>
                        <td class="item-date">{item.get('created_date', '')[:10] if item.get('created_date') else ''}</td>
                        <td>{item.get('image_count', 0)}</td>
                    </tr>
            """
        
        html += f"""
                </tbody>
            </table>
            
            <div class="summary">
                <strong>Total Items:</strong> {len(items)}
            </div>
        </body>
        </html>
        """
        
        return html
    
    def _generate_item_details_html(self, item: Dict) -> str:
        """Generate HTML for item details printing"""
        html = f"""
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="UTF-8">
            <title>Item Details - {item.get('item_name', 'Unknown')}</title>
            <style>
                body {{ font-family: Arial, sans-serif; margin: 20px; }}
                .header {{ text-align: center; margin-bottom: 30px; }}
                .header h1 {{ margin: 0; color: #333; }}
                .item-info {{ margin-bottom: 20px; }}
                .info-row {{ margin-bottom: 10px; }}
                .label {{ font-weight: bold; color: #666; }}
                .value {{ margin-left: 10px; }}
                .guid {{ font-family: monospace; background-color: #f5f5f5; padding: 5px; }}
                .description {{ margin-top: 15px; padding: 10px; background-color: #f9f9f9; border-left: 4px solid #007bff; }}
                .qr-section {{ text-align: center; margin-top: 30px; }}
                .qr-note {{ font-size: 12px; color: #666; margin-top: 10px; }}
            </style>
        </head>
        <body>
            <div class="header">
                <h1>Item Details</h1>
            </div>
            
            <div class="item-info">
                <div class="info-row">
                    <span class="label">Name:</span>
                    <span class="value">{item.get('item_name', 'Unnamed Item')}</span>
                </div>
                
                <div class="info-row">
                    <span class="label">Label #:</span>
                    <span class="value">{item.get('label_number', 'N/A')}</span>
                </div>
                
                <div class="info-row">
                    <span class="label">GUID:</span>
                    <span class="value guid">{item.get('guid', 'N/A')}</span>
                </div>
                
                <div class="info-row">
                    <span class="label">Created:</span>
                    <span class="value">{item.get('created_date', 'N/A')}</span>
                </div>
                
                <div class="info-row">
                    <span class="label">Images:</span>
                    <span class="value">{item.get('image_count', 0)}</span>
                </div>
            </div>
            
            {f'<div class="description"><strong>Description:</strong><br>{item.get("description", "")}</div>' if item.get("description") else ""}
            
            <div class="qr-section">
                <h3>QR Code</h3>
                <div class="qr-note">
                    Scan this QR code to view this item in the inventory system
                </div>
            </div>
        </body>
        </html>
        """
        
        return html
    
    def _print_file(self, file_path: str, printer_name: Optional[str] = None, job_name: str = "Print Job") -> bool:
        """Print a file using CUPS"""
        try:
            printer = printer_name or self.default_printer
            if not printer:
                logger.error("No printer specified and no default printer found")
                return False
            
            # Build lp command
            cmd = ['lp', '-d', printer, '-t', job_name, file_path]
            
            # Execute print command
            result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
            
            if result.returncode == 0:
                logger.info(f"Successfully sent print job '{job_name}' to printer '{printer}'")
                return True
            else:
                logger.error(f"Print command failed: {result.stderr}")
                return False
                
        except subprocess.TimeoutExpired:
            logger.error("Print command timed out")
            return False
        except Exception as e:
            logger.error(f"Print error: {e}")
            return False
    
    def test_printer_connection(self, printer_name: Optional[str] = None) -> Dict[str, any]:
        """Test printer connection and return status"""
        try:
            printer = printer_name or self.default_printer
            if not printer:
                return {
                    'success': False,
                    'error': 'No printer specified and no default printer found'
                }
            
            # Test printer status
            result = subprocess.run(['lpstat', '-p', printer], 
                                  capture_output=True, text=True, timeout=10)
            
            if result.returncode == 0:
                return {
                    'success': True,
                    'printer': printer,
                    'status': result.stdout.strip()
                }
            else:
                return {
                    'success': False,
                    'error': f'Printer {printer} not found or not accessible'
                }
                
        except Exception as e:
            return {
                'success': False,
                'error': f'Printer test failed: {str(e)}'
            }
