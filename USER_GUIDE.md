# ThingDB User Guide

Welcome to ThingDB! This guide will help you get the most out it.

Don't let the examples of adding items and stuff limit your imagination. Anything that you want to type into ThingDB you can type it. It's a hierarchical storage system essentially. You can move things about when you change their position or location in real life or simply how you think about them.



---

## Getting Started

After installing ThingDB, visit `https://YOUR_IP:5000` in your web browser. You'll see your inventory home page with a search bar and a ➕ button to add new items.

---

## Adding Items

### Creating a New Item

1. Click the **➕ button** in the top right corner
2. Confirm you want to create a new item
3. You'll be taken to the item detail page where you can:
   - **Name your item** - Click on the title to edit it
   - **Add a description** - This is where the magic happens! (More on this below)
   - **Upload photos** - Click the camera icon or drag and drop images
   - **Generate a QR code** - Click "Generate QR Code" to create a label

### Item Details

Each item can have:

- **Name** - A short title (e.g., "Box of Old Clothes", "Bedroom Closet")
- **Description** - Detailed information about the item
- **Photos** - Multiple images per item
- **QR Code** - Unique identifier that links to this item
- **Parent Item** - The location or container this item belongs to
- **Child Items** - Items nested inside this item

### Items Can Be Places or Things(or anything)

**Important:** An item doesn't have to be a physical object. It can be:

- **A place** - "Bedroom Closet", "Garage Shelf 2", "Storage Unit A"
- **A container** - "Box of Old Clothes", "Toolbox", "Filing Cabinet"
- **A thing** - "Vintage Camera", "Camping Stove", "Laptop"
- **Anything** - "Vacations you plan to take" There's no limit to what you can come up with.

This flexibility lets you organize your inventory hierarchically. For example:

```
Bedroom Closet (place)
  └── Box of Old Clothes (container)
      └── Vintage Jacket (thing)
          └── Buttons Collection (thing)
```

---

## Organizing Your Inventory

### Moving Items in the Hierarchy

To organize items into a tree structure:

1. Open an item's detail page
2. Scroll down to the **"Move Item"** section
3. Search for the destination item (parent)
4. Click **"Move Here"** to place this item inside the destination

**Example Workflow:**
- You have a "Bedroom Closet" item
- You create a "Box of Old Clothes" item
- On the "Box of Old Clothes" page, use "Move Item" to place it inside "Bedroom Closet"
- Now "Box of Old Clothes" appears as a child of "Bedroom Closet"

### Creating Nested Structures

You can nest items as deeply as you need:

1. Create a location item (e.g., "Bedroom Closet")
2. Create container items and move them into the location
3. Create item details and move them into containers
4. Keep nesting as needed

**Real-World Example:**
```
Garage (place)
  └── Shelf 2 (place)
      └── Toolbox (container)
          └── Screwdriver Set (thing)
              └── Phillips Head #2 (thing)
```

---

## QR Codes

### Printing QR Codes (to use as stickers or labels)

1. Go to **Admin Panel** → **Printing** tab
2. Click **"Generate QR Code PDF"**
3. Print a PDF of never used QR codes and attach labels to your items
- You can print as many as you want, and they'll all be unique.

### Printing an item's unique QR code

1. At the bottom of any item page, you'll see a QR code and labels drop-down
2. Click **"Download Full Item Label"**
- Or "Download PNG" or "Download PDF" to get just the QR code.
3. Print a PDF of the item's unique QR code and attach labels to your item

### Scanning QR Codes

You can scan QR codes in two ways:

#### Option 1: Create a New Item from QR Code

1. Click the **📷 camera button** in the header (or use the search bar)
2. Scan a QR code
3. If the item doesn't exist, you'll be prompted to create it
4. Fill in the item details

#### Option 2: Link QR Code to Existing Item

1. Scan a QR code (using the camera button or search bar)
2. If the item already exists, you'll be taken to that item
3. Otherwise, you get a choice of linking it or creating a new item
- The scanned QR code is automatically linked to the item

### Multiple QR Codes Per Item

**Key Feature:** Items can have multiple QR codes! This is useful when:

- You have a QR code on the front of a box and another on the back
- You want to add a QR code to an item that already has one
- You're reorganizing and need new labels

**How it works:**
- When you scan any QR code linked to an item, you'll always see the same item
- All QR codes point to the same base item
- You can add new QR codes by scanning them and linking them to existing items

---

## Writing Great Descriptions

### Why Descriptions Matter

ThingDB uses **semantic search** powered by AI. The more detail you put in descriptions, the better your search results will be.

**Good Description:**
```
Vintage 1980s denim jacket with metal buttons. 
Size medium, blue wash, slight fading on sleeves. 
Purchased at thrift store in 2023. 
Has small tear on left pocket. 
Perfect for casual wear or costume.
```

**Poor Description:**
```
Jacket
```

### What to Include

When writing descriptions, think about:

- **What it is** - Type, brand, model
- **Physical characteristics** - Size, color, condition, materials
- **Where it came from** - Purchase location, date, source
- **What it's used for** - Purpose, use cases
- **Related items** - What goes with it, what it's part of
- **Any unique details** - Scratches, modifications, history

### Using Speech-to-Text

**Pro Tip:** Use a speech-to-text app to quickly add detailed descriptions without typing!

**Recommended Tools for Speech-to-Text:**
- **Wispr Flow** - Excellent for long-form descriptions


**Workflow:**
1. Open the item detail page
2. Click in the description field
3. Use your phone or computer's speech-to-text
4. Speak naturally about the item
5. Edit and refine the text
6. Save

This dramatically reduces friction and lets you capture more context about each item.

---

## Searching Your Inventory

### Semantic Search

ThingDB's semantic search understands meaning, not just keywords.

**Try searching for:**
- "camping gear" → Finds tents, stoves, sleeping bags
- "things that need batteries" → Finds electronics, flashlights, toys
- "vintage clothing" → Finds old jackets, retro items
- "tools for woodworking" → Finds saws, hammers, chisels

**Tips for Better Search:**
- Use natural language - search like you're asking a question
- Be descriptive - "red camping equipment" is better than "red"
- Think about context - "items in the garage" works if you've organized by location

### Traditional Search

You can also search by exact text matches:
- Item names
- Keywords in descriptions
- Label numbers

### View Modes

Toggle between **List View** and **Tree View** to see your inventory:
- **List View** - Flat list of all items
- **Tree View** - Hierarchical organization showing parent-child relationships

---

## Best Practices

I've already poisoned your mind. Verbose text that you speak into your browser. Don't type, waste of time.. That's it. Just have fun.

---

## Common Workflows

### Adding a New Item to an Existing Location

1. Click ➕ to create new item
2. Name it (e.g., "Vintage Camera")
3. Add description using speech-to-text
4. Upload photos
5. Scroll to "Move Item" section
6. Search for the location (e.g., "Bedroom Closet")
7. Click "Move Here"
8. Generate and print QR code

### Organizing a Box of Items

1. Create "Box of Old Clothes" item
2. Move it into "Bedroom Closet"
3. For each item in the box:
   - Create item (e.g., "Vintage Jacket")
   - Add detailed description
   - Move it into "Box of Old Clothes"
   - Print QR code and attach to item

### Finding Something You Forgot About

1. Use semantic search
2. Try different phrasings:
   - "red clothing"
   - "winter gear"
   - "things I bought last year"
3. Check Tree View to see where items are located
4. Scan QR codes to verify you found the right item

### Auditing Your Inventory

1. Go to a location (e.g., "Garage")
2. Switch to Tree View
3. Scan QR codes of items you see
4. Verify they're in the right place
5. Move items if needed
6. Add descriptions to items that are missing details

---

## Tips & Tricks

### Quick Item Creation

- Use the search bar to quickly scan QR codes
- If item doesn't exist, you'll be prompted to create it
- This is faster than clicking ➕ for every item

### Keyboard Shortcuts

- **Search bar** - Start typing to search
- **Enter** - Submit search or create item
- **Escape** - Close modals

### Mobile-Friendly

ThingDB works great on phones and tablets:
- Scan QR codes with your phone's camera
- Use speech-to-text on mobile for descriptions
- Touch-friendly interface

### Backup Before Big Changes

Before reorganizing large sections:
1. Go to **Admin Panel** → **Backup & Restore**
2. Create a backup
3. Make your changes
4. If something goes wrong, restore from backup

**Always before upgrading the software, make a backup.**

---

## Getting Help

- **Admin Panel** - Access system settings and tools
- **GitHub Issues** - Report bugs or request features
- **GitHub Discussions** - Ask questions and share tips

---

## Summary

ThingDB is most powerful when you:

1. ✅ **Create detailed descriptions** - Use speech-to-text to make this easy
2. ✅ **Organize hierarchically** - Use locations, containers, and items (or anything)
3. ✅ **Print QR codes** - Label everything for easy scanning later.
4. ✅ **Use semantic search** - Find items by meaning, not just keywords
5. ✅ **Organize as you go** - Don't let items pile up unorganized

**Remember:** Items can be places, containers, or things (or anything). Use this flexibility to create a system that matches how you think about your stuff!

---

**Happy Organizing!** 📦

