#!/bin/bash

# Example curl commands to add hero banners
# Copy and modify these commands as needed

API_URL="http://localhost:8080/api"
AUTH_TOKEN="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VyX2lkIjoiNjk2YTA4ZmFmNzI0NzRkNzE3Njc1ZjExIiwiZW1haWwiOiJhZG1pbkBybG9jby5jb20iLCJyb2xlIjoiYWRtaW4iLCJleHAiOjE3NjkyNzE3NTYsImlhdCI6MTc2OTE4NTM1Nn0.aVZaPDb63EYeyOWDKRpNlxUiGvBqm_Xaq-WG-YzeoZg"

echo "=========================================="
echo "Hero Banner Configuration Examples"
echo "=========================================="
echo ""

# Example 1: Fashion/Luxury Banner
echo "Example 1: Fashion/Luxury Banner"
echo "-----------------------------------"
cat << 'EOF'
curl -X PUT "http://localhost:8080/api/admin/configuration" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -d '{
    "homepage": {
      "hero": {
        "enabled": true,
        "heading": "Timeless Elegance Redefined",
        "subheading": "Discover our curated collection of luxury fashion pieces",
        "primaryButtonText": "Shop Collection",
        "primaryButtonLink": "/shop",
        "backgroundImage": "https://images.unsplash.com/photo-1441986300917-64674bd600d8?w=1920&q=80",
        "style": "fullscreen"
      }
    }
  }'
EOF
echo ""
echo ""

# Example 2: Summer Collection Banner
echo "Example 2: Summer Collection Banner"
echo "-----------------------------------"
cat << 'EOF'
curl -X PUT "http://localhost:8080/api/admin/configuration" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -d '{
    "homepage": {
      "hero": {
        "enabled": true,
        "heading": "Summer Collection 2026",
        "subheading": "Fresh styles for the season ahead",
        "primaryButtonText": "Shop Now",
        "primaryButtonLink": "/all-products",
        "backgroundImage": "https://images.unsplash.com/photo-1469334031218-e382a71b716b?w=1920&q=80",
        "style": "fullscreen"
      }
    }
  }'
EOF
echo ""
echo ""

# Example 3: Sale Banner
echo "Example 3: Sale Banner"
echo "-----------------------------------"
cat << 'EOF'
curl -X PUT "http://localhost:8080/api/admin/configuration" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -d '{
    "homepage": {
      "hero": {
        "enabled": true,
        "heading": "End of Season Sale",
        "subheading": "Up to 50% off selected items",
        "primaryButtonText": "Shop Sale",
        "primaryButtonLink": "/sale",
        "backgroundImage": "https://images.unsplash.com/photo-1445205170230-053b83016050?w=1920&q=80",
        "style": "fullscreen"
      }
    }
  }'
EOF
echo ""
echo ""

# Example 4: New Arrivals Banner
echo "Example 4: New Arrivals Banner"
echo "-----------------------------------"
cat << 'EOF'
curl -X PUT "http://localhost:8080/api/admin/configuration" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -d '{
    "homepage": {
      "hero": {
        "enabled": true,
        "heading": "Just Landed",
        "subheading": "Discover our latest collection. Fresh styles for the modern wardrobe.",
        "primaryButtonText": "View New Arrivals",
        "primaryButtonLink": "/new-arrivals",
        "backgroundImage": "https://images.unsplash.com/photo-1490481651871-ab68de25d43d?w=1920&q=80",
        "style": "fullscreen"
      }
    }
  }'
EOF
echo ""
echo ""

echo "=========================================="
echo "Note: Replace YOUR_TOKEN with your actual auth token"
echo "You can also use the script: ./add_hero_banner.sh <image_url> [heading] [subheading] [button_text] [button_link]"
echo "=========================================="
