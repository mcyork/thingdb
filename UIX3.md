# UIX3: A Unified Plan for UI/UX Refinement

## 1. Core Philosophy

This plan synthesizes the user's vision in `UIX.md` with the technical framework from `UIX2.md`. The guiding principles are:

- **Clarity and Simplicity:** Reduce visual clutter. Every element should have a clear purpose.
- **Consistency:** A unified design language across all pages for navigation, actions, and information display.
- **Mobile-First, Desktop-Friendly:** Ensure a seamless experience on phones while scaling gracefully to larger screens.
- **Template-Only Changes:** All modifications will be contained within HTML, CSS, and JavaScript files, preserving the Python backend.

---

## 2. Global Design System

We will implement a system of CSS custom properties (variables) in `base.html` for easy maintenance and consistency. This is inspired by `UIX2.md` but with a softer, "less jarring" palette as requested in `UIX.md`.

### 2.1. Color Palette

```css
:root {
    --primary-color: #007bff;
    --primary-hover: #0056b3;
    --secondary-color: #6c757d;
    --background-light: #f8f9fa;
    --background-white: #ffffff;
    --text-dark: #212529;
    --text-medium: #495057;
    --text-light: #6c757d;
    --border-color: #dee2e6;
    --shadow-color: rgba(0, 0, 0, 0.1);
    --success-color: #28a745;
    --danger-color: #dc3545;
    --warning-color: #ffc107;
}
```

### 2.2. Typography & Spacing

We will use a consistent typography and spacing scale as outlined in `UIX2.md` to create a harmonious visual rhythm.

---

## 3. Key Component Redesigns

### 3.1. Unified Navigation Header

- **Problem:** Many pages (`system_status`, `remote_access`, etc.) lack navigation.
- **Solution:** A consistent header will be implemented on all sub-pages. It will contain:
    - A **Back Button (Icon)**: A subtle `←` icon that uses `history.back()` for simple backward navigation.
    - The **Page Title**.
- This replaces the "big, black, and ugly" back buttons and provides context.

### 3.2. Breadcrumb Navigation

- **For `item.html`:** To address the need for hierarchical navigation, breadcrumbs will be implemented at the top of the item view, showing the path from Home to the current item.
- **The Back Button on `item.html`:** The header's back button will still perform a simple `history.back()`. The breadcrumbs will be the primary method for hierarchical navigation. *The request to make the back button itself hierarchical is a potential Flask code change and will be deferred as per instructions.*

### 3.3. Button System

- **Problem:** Buttons are "too big" and "in your face".
- **Solution:** A new, softer button system will be created.
    - **Primary Actions:** Subtle, solid-color buttons.
    - **Secondary Actions:** Ghost buttons (transparent background, colored border) for less critical actions like "Cancel".
    - **Destructive Actions:** Clearly marked but not overly aggressive styling for "Delete".
- This will be applied globally for consistency.

---

## 4. Page-Specific Refactoring Plan

### 4.1. `admin.html` (High Priority)

- **Redesign:** The page will be restructured with a tabbed sub-navigation (`System`, `Database`, `Packages`, `Access`). This directly addresses the "cleaner, with sub-navigation" request.
- **Layout:** Within each tab, tools will be organized into clean, card-based components, replacing the current grid of large buttons.

### 4.2. `db_stats.html` (High Priority)

- **Problem:** "Way too airy".
- **Solution:** The layout will be redesigned to be a compact, responsive grid of "stat cards". Each card will clearly display a single statistic (e.g., Total Items), making the information much more scannable and less spread out.

### 4.3. `home.html`

- **Item List:** The current list/tree view toggle is a great feature. We will make the **Tree View the default** to better handle a large number of items from the start.
- **Top Links:** The `System Status`, `Admin`, etc., links will be redesigned into a cleaner, more intuitive "Action Grid" directly below the search/scan bar.
- **Search:** The search bar will remain the primary focus.

### 4.4. `item.html`

- **Navigation:** Implement the breadcrumb trail.
- **Layout:** Redesign action buttons (`Move Item`, `Add Photo`) to be less intrusive, using the new button system. The overall layout above the fold will be preserved.
- **Image Controls:** The image controls will be redesigned to be cleaner and more intuitive.

### 4.5. `system_status.html` & `remote_access.html`

- **Solution:** These pages will receive the new Unified Navigation Header, immediately solving the lack of navigation. The content layout will be slightly adjusted for better spacing and consistency.

---

## 5. Implementation Strategy

1.  **Phase 1: Foundation (`base.html`)**
    - Read `src/templates/base.html` and inject the new global CSS variables and base styles.
    - Create the CSS for the new component library (buttons, cards, headers).

2.  **Phase 2: High-Impact Pages (`admin.html`, `db_stats.html`)**
    - Refactor `admin.html` with the new tabbed navigation and card layout.
    - Refactor `db_stats.html` with the compact stat card grid.

3.  **Phase 3: Core Experience (`home.html`, `item.html`)**
    - Update `home.html` to default to the tree view and add the new action grid.
    - Update `item.html` with breadcrumbs and the refined button styles.

4.  **Phase 4: Consistency Pass**
    - Apply the unified header to `system_status.html`, `remote_access.html`, and any other pages that need it.
    - Perform a final review to ensure all pages adhere to the new design system.
