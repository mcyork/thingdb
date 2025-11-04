"""
QR Code PDF Generation Service
Generates PDF sheets with QR codes for inventory items
"""
import uuid
import io
import qrcode
from reportlab.pdfgen import canvas
from reportlab.lib.pagesizes import letter
from reportlab.lib.units import inch
# from reportlab.lib.colors import black, white  # Not used
from reportlab.lib.utils import ImageReader


class QRPDFService:
    """Service for generating QR code PDF sheets"""
    
    def __init__(self):
        self.page_width, self.page_height = letter
        self.margin = 0.5 * inch
        self.qr_size = 1.5 * inch
        self.spacing = 0.25 * inch
        self.codes_per_row = 4
        self.rows_per_page = 6
        self.total_codes_per_page = self.codes_per_row * self.rows_per_page
    
    def generate_unique_guid(self):
        """Generate a unique GUID for inventory items"""
        return str(uuid.uuid4()).upper()
    
    def create_qr_code_image(self, guid):
        """Create QR code image from GUID"""
        qr = qrcode.QRCode(
            version=1,
            error_correction=qrcode.constants.ERROR_CORRECT_L,
            box_size=10,
            border=4,
        )
        qr.add_data(guid)
        qr.make(fit=True)
        
        # Create QR code image
        img = qr.make_image(fill_color="black", back_color="white")
        
        # Convert to bytes
        img_bytes = io.BytesIO()
        img.save(img_bytes, format='PNG')
        img_bytes.seek(0)
        
        return img_bytes
    
    def get_guid_display(self, guid):
        """Get last 4 characters of GUID in CA-D8 format"""
        last_four = guid[-4:].upper()
        return f"{last_four[:2]}-{last_four[2:]}"
    
    def calculate_position(self, row, col):
        """Calculate position for QR code (handling bottom-left origin)"""
        # Calculate x position (left to right)
        x = self.margin + col * (self.qr_size + self.spacing)
        
        # Calculate y position (bottom to top - ReportLab uses bottom-left origin)
        # We want to work from top down, so we need to flip the y coordinate
        y_from_top = self.margin + row * (self.qr_size + self.spacing)
        y = self.page_height - y_from_top - self.qr_size
        
        return x, y
    
    def generate_qr_sheet(self):
        """Generate a PDF sheet with QR codes"""
        # Create PDF in memory
        pdf_buffer = io.BytesIO()
        c = canvas.Canvas(pdf_buffer, pagesize=letter)
        
        # Generate unique GUIDs for this sheet
        guids = [self.generate_unique_guid() for _ in range(self.total_codes_per_page)]
        
        # Draw QR codes in grid
        for i, guid in enumerate(guids):
            row = i // self.codes_per_row
            col = i % self.codes_per_row
            
            # Calculate position
            x, y = self.calculate_position(row, col)
            
            # Create QR code image
            qr_image = self.create_qr_code_image(guid)
            
            # Draw QR code
            c.drawImage(ImageReader(qr_image), x, y, 
                       width=self.qr_size, height=self.qr_size)
            
            # Draw label below QR code (last 4 digits + Item # ______)
            label_text = self.get_guid_display(guid) + " Item # ______"
            label_x = x + self.qr_size / 2
            label_y = y - 0.2 * inch
            
            c.setFont("Helvetica-Bold", 10)
            # Center the text manually
            text_width = c.stringWidth(label_text, "Helvetica-Bold", 10)
            c.drawString(label_x - text_width/2, label_y, label_text)
        
        # Add page title
        c.setFont("Helvetica-Bold", 16)
        # Center the title manually
        title_text = "Inventory QR Code Sheet"
        title_width = c.stringWidth(title_text, "Helvetica-Bold", 16)
        c.drawString(self.page_width / 2 - title_width/2, self.page_height - 0.3 * inch, 
                     title_text)
        
        # No footer needed - keep it clean
        
        # Save PDF
        c.save()
        pdf_buffer.seek(0)
        
        return pdf_buffer, guids
    
    def get_pdf_filename(self):
        """Generate filename for PDF download"""
        import datetime
        timestamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
        return f"qr_codes_{timestamp}.pdf"
    
    def generate_single_qr_png(self, guid, item_name=None):
        """Generate a single QR code as PNG image (for display on item page)"""
        # Create QR code with same settings as PDF version
        qr = qrcode.QRCode(
            version=1,
            error_correction=qrcode.constants.ERROR_CORRECT_L,
            box_size=10,
            border=4,
        )
        qr.add_data(guid)
        qr.make(fit=True)
        
        # Create QR code image
        img = qr.make_image(fill_color="black", back_color="white")
        
        # Convert to bytes
        img_bytes = io.BytesIO()
        img.save(img_bytes, format='PNG')
        img_bytes.seek(0)
        
        return img_bytes
    
    def generate_single_qr_pdf(self, guid, item_name=None):
        """Generate a single-item QR code label as PDF (same format as grid)"""
        # Create PDF in memory
        pdf_buffer = io.BytesIO()
        c = canvas.Canvas(pdf_buffer, pagesize=letter)
        
        # Center the QR code on the page
        x = (self.page_width - self.qr_size) / 2
        y = (self.page_height - self.qr_size) / 2
        
        # Create QR code image
        qr_image = self.create_qr_code_image(guid)
        
        # Draw QR code (centered)
        c.drawImage(ImageReader(qr_image), x, y, 
                   width=self.qr_size, height=self.qr_size)
        
        # Draw label below QR code (same format as grid)
        label_text = self.get_guid_display(guid)
        if item_name:
            label_text += f" {item_name}"
        else:
            label_text += " Item # ______"
        
        label_x = x + self.qr_size / 2
        label_y = y - 0.2 * inch
        
        c.setFont("Helvetica-Bold", 10)
        # Center the text
        text_width = c.stringWidth(label_text, "Helvetica-Bold", 10)
        c.drawString(label_x - text_width/2, label_y, label_text)
        
        # Add title at top
        c.setFont("Helvetica-Bold", 16)
        title_text = f"Item QR Code: {item_name}" if item_name else "Item QR Code"
        title_width = c.stringWidth(title_text, "Helvetica-Bold", 16)
        c.drawString(self.page_width / 2 - title_width/2, self.page_height - 0.5 * inch, 
                     title_text)
        
        # Add GUID as footer (for reference)
        c.setFont("Helvetica", 8)
        footer_text = f"GUID: {guid}"
        footer_width = c.stringWidth(footer_text, "Helvetica", 8)
        c.drawString(self.page_width / 2 - footer_width/2, 0.3 * inch, footer_text)
        
        # Save PDF
        c.save()
        pdf_buffer.seek(0)
        
        return pdf_buffer
    
    def generate_hierarchy_qr_sheet(self, items_data):
        """
        Generate multi-page PDF with QR codes for a container and its contents
        items_data: List of dicts with 'guid', 'item_name', 'label_number'
        """
        # Create PDF in memory
        pdf_buffer = io.BytesIO()
        c = canvas.Canvas(pdf_buffer, pagesize=letter)
        
        total_items = len(items_data)
        total_pages = (total_items + self.total_codes_per_page - 1) // self.total_codes_per_page
        
        for page_num in range(total_pages):
            # Calculate items for this page
            start_idx = page_num * self.total_codes_per_page
            end_idx = min(start_idx + self.total_codes_per_page, total_items)
            page_items = items_data[start_idx:end_idx]
            
            # Draw QR codes for this page
            for i, item_data in enumerate(page_items):
                row = i // self.codes_per_row
                col = i % self.codes_per_row
                
                # Calculate position
                x, y = self.calculate_position(row, col)
                
                # Create QR code image
                qr_image = self.create_qr_code_image(item_data['guid'])
                
                # Draw QR code
                c.drawImage(ImageReader(qr_image), x, y, 
                           width=self.qr_size, height=self.qr_size)
                
                # Draw label below QR code
                guid_display = self.get_guid_display(item_data['guid'])
                item_name = item_data.get('item_name', '')
                
                # Format: "XX-XX Item Name" or "XX-XX #123 Item Name" if has label number
                if item_data.get('label_number'):
                    label_text = f"{guid_display} #{item_data['label_number']} {item_name}"
                elif item_name:
                    label_text = f"{guid_display} {item_name}"
                else:
                    label_text = f"{guid_display} Item # ______"
                
                # Truncate if too long (max ~30 chars for grid size)
                if len(label_text) > 30:
                    label_text = label_text[:27] + "..."
                
                label_x = x + self.qr_size / 2
                label_y = y - 0.2 * inch
                
                c.setFont("Helvetica-Bold", 9)  # Slightly smaller for long names
                text_width = c.stringWidth(label_text, "Helvetica-Bold", 9)
                c.drawString(label_x - text_width/2, label_y, label_text)
            
            # Add page title
            c.setFont("Helvetica-Bold", 16)
            if total_pages > 1:
                title_text = f"Container QR Codes - Page {page_num + 1} of {total_pages}"
            else:
                title_text = "Container QR Codes"
            title_width = c.stringWidth(title_text, "Helvetica-Bold", 16)
            c.drawString(self.page_width / 2 - title_width/2, self.page_height - 0.3 * inch, 
                         title_text)
            
            # Add next page if needed
            if page_num < total_pages - 1:
                c.showPage()
        
        # Save PDF
        c.save()
        pdf_buffer.seek(0)
        
        return pdf_buffer


# Global service instance
qr_pdf_service = QRPDFService()
