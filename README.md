# JDT VIP Hospitality System

A responsive stadium hospitality web prototype for VIP booth ordering and matchday operations.

## Features in this prototype

- Guest portal: guest name, booth selection, menu, cart and order submission.
- Staff operations: order queue, status updates and service requests.
- Vendor workspace: vendor-specific order filtering and preparation status updates.
- Management dashboard: activity overview, order value, CSV export and demo reset.
- Responsive layout for desktop, tablet and mobile.
- Browser-local demo persistence using localStorage.

## Run locally

No build step is required. Open `index.html` in a modern browser, or serve the folder with any static web server:

```bash
python3 -m http.server 8000
```

Then visit http://localhost:8000.

## Publish with GitHub Pages

1. Open the repository Settings.
2. Select **Pages**.
3. Under **Build and deployment**, choose **Deploy from a branch**.
4. Select branch **main** and folder **/(root)**, then Save.
5. Wait for GitHub Pages to publish the site. The URL will appear in Settings → Pages.

## Important production notes

This is an initial front-end prototype. Data is stored only in the current browser and is not shared between guests, staff or vendors. Before using it at a live stadium, implement:

- A secure backend and shared database.
- Authentication and role-based access for guests, staff, vendors and administrators.
- Server-side order validation and audit logs.
- Real-time updates and push/SMS notifications.
- Payment integration if required, with a compliant payment provider.
- Privacy, security, accessibility and load testing.

The interface is an independent concept prototype and is not an official JDT product or endorsed service.
