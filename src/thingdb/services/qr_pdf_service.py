"""
QR Code PDF Generation Service
Generates PDF sheets with QR codes for inventory items
"""
import uuid
import io
import os
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
    
    def generate_item_label(self, item_data, breadcrumbs=None, photos=None, tags=None):
        """
        Generate a comprehensive half-page item label
        Uses full letter page (8.5" x 11") but content in top half only
        This prevents printer scaling issues
        
        item_data: dict with 'guid', 'item_name', 'description', 'label_number'
        breadcrumbs: list of parent names for location trail
        photos: list of image file paths (up to 3)
        tags: list of category names
        """
        # Create PDF in memory (FULL letter page to prevent scaling)
        pdf_buffer = io.BytesIO()
        c = canvas.Canvas(pdf_buffer, pagesize=letter)
        
        # Layout parameters
        margin = 0.3 * inch
        qr_size = 2 * inch
        
        # Work in top half only (5.5" of the 11" page)
        label_top = self.page_height  # 11"
        label_bottom = self.page_height / 2  # 5.5" (middle of page)
        
        # QR code in upper right
        qr_x = self.page_width - margin - qr_size
        qr_y = label_top - margin - qr_size
        qr_image = self.create_qr_code_image(item_data['guid'])
        c.drawImage(ImageReader(qr_image), qr_x, qr_y, 
                   width=qr_size, height=qr_size)
        
        # Item number (BIG and prominent - upper left if exists)
        current_y = label_top - margin - 0.2 * inch
        if item_data.get('label_number'):
            c.setFont("Helvetica-Bold", 48)
            item_num_text = f"#{item_data['label_number']}"
            c.drawString(margin, current_y - 0.5 * inch, item_num_text)
            current_y -= 0.7 * inch
        
        # Item name (large, bold)
        c.setFont("Helvetica-Bold", 18)
        item_name = item_data.get('item_name', 'Untitled Item')
        # Wrap long names
        if len(item_name) > 40:
            item_name = item_name[:37] + "..."
        c.drawString(margin, current_y, item_name)
        current_y -= 0.25 * inch
        
        # Breadcrumb trail (location)
        if breadcrumbs and len(breadcrumbs) > 0:
            c.setFont("Helvetica", 10)
            location_text = "📍 Location: " + " → ".join(breadcrumbs)
            if len(location_text) > 90:
                location_text = location_text[:87] + "..."
            c.drawString(margin, current_y, location_text)
            current_y -= 0.3 * inch
        
        # Description (wrapped)
        if item_data.get('description'):
            c.setFont("Helvetica", 10)
            desc = item_data['description']
            # Simple word wrapping
            max_width = self.page_width - 2 * margin - (qr_size + 0.2 * inch)  # Leave space for QR
            words = desc.split()
            lines = []
            current_line = ""
            
            for word in words:
                test_line = current_line + word + " "
                if c.stringWidth(test_line, "Helvetica", 10) < max_width:
                    current_line = test_line
                else:
                    if current_line:
                        lines.append(current_line.strip())
                    current_line = word + " "
            if current_line:
                lines.append(current_line.strip())
            
            # Draw up to 4 lines of description
            for line in lines[:4]:
                c.drawString(margin, current_y, line)
                current_y -= 0.15 * inch
            
            if len(lines) > 4:
                c.drawString(margin, current_y, "...")
                current_y -= 0.15 * inch
            
            current_y -= 0.1 * inch
        
        # Photos (up to 3 thumbnails, 1" each)
        if photos and len(photos) > 0:
            photo_size = 1 * inch
            photo_y = current_y - photo_size
            
            for i, photo_path in enumerate(photos[:3]):
                if photo_path and os.path.exists(photo_path):
                    try:
                        photo_x = margin + i * (photo_size + 0.1 * inch)
                        c.drawImage(photo_path, photo_x, photo_y, 
                                  width=photo_size, height=photo_size, 
                                  preserveAspectRatio=True, mask='auto')
                    except:
                        pass  # Skip if image can't be loaded
            
            current_y = photo_y - 0.2 * inch
        
        # Tags at bottom
        if tags and len(tags) > 0:
            c.setFont("Helvetica", 9)
            tags_text = "🏷️ " + " • ".join([f"#{tag}" for tag in tags[:8]])
            if len(tags_text) > 100:
                tags_text = tags_text[:97] + "..."
            c.drawString(margin, current_y, tags_text)
            current_y -= 0.2 * inch
        
        # GUID at bottom
        c.setFont("Helvetica", 8)
        guid_text = f"GUID: {self.get_guid_display(item_data['guid'])} • {item_data['guid']}"
        c.drawString(margin, margin, guid_text)
        
        # Save PDF
        c.save()
        pdf_buffer.seek(0)
        
        return pdf_buffer


# Global service instance
qr_pdf_service = QRPDFService()
