#!/bin/bash

# Script to add/update hero section background image using the configuration API
# Usage: ./add_hero_banner.sh [image_url] [heading] [subheading] [button_text] [button_link]

API_URL="http://localhost:8081/api"
COOKIE_FILE=$(mktemp)
trap "rm -f $COOKIE_FILE" EXIT

# Login as admin and save auth cookie
echo "Logging in as admin..."
LOGIN_RESP=$(curl -s -c "$COOKIE_FILE" -X POST "${API_URL}/auth/login" \
    -H "Content-Type: application/json" \
    -d '{"email":"admin@rloco.com","password":"admin123"}')
if echo "$LOGIN_RESP" | jq -e '.error' >/dev/null 2>&1; then
    echo "Login failed: $(echo "$LOGIN_RESP" | jq -r '.error')"
    exit 1
fi
echo "Logged in successfully."
echo ""

# Get parameters
IMAGE_URL="${1:-https://images.unsplash.com/photo-1441986300917-64674bd600d8?w=1920&q=80}"
HEADING="${2:-Timeless Elegance Redefined}"
SUBHEADING="${3:-Discover our curated collection of luxury fashion pieces}"
BUTTON_TEXT="${4:-Shop Collection}"
BUTTON_LINK="${5:-/shop}"

echo "Fetching current configuration..."

# Get current configuration (using cookie)
CURRENT_CONFIG=$(curl -s -b "$COOKIE_FILE" "${API_URL}/admin/configuration")

if [ -z "$CURRENT_CONFIG" ] || echo "$CURRENT_CONFIG" | jq -e '.error' > /dev/null 2>&1; then
    echo "Error: Failed to fetch current configuration"
    echo "$CURRENT_CONFIG"
    exit 1
fi

echo "Updating hero section with new banner..."

# Update the homepage.hero section with new banner image
UPDATED_CONFIG=$(echo "$CURRENT_CONFIG" | jq --arg img "$IMAGE_URL" \
    --arg heading "$HEADING" \
    --arg subheading "$SUBHEADING" \
    --arg buttonText "$BUTTON_TEXT" \
    --arg buttonLink "$BUTTON_LINK" '
    .homepage.hero.backgroundImage = $img |
    .homepage.hero.heading = $heading |
    .homepage.hero.subheading = $subheading |
    .homepage.hero.primaryButtonText = $buttonText |
    .homepage.hero.primaryButtonLink = $buttonLink |
    .homepage.hero.enabled = true |
    .homepage.hero.style = "fullscreen"
')

# Save the updated configuration (using cookie)
RESPONSE=$(curl -s -X PUT "${API_URL}/admin/configuration" \
    -b "$COOKIE_FILE" \
    -H "Content-Type: application/json" \
    -d "$UPDATED_CONFIG")

if echo "$RESPONSE" | jq -e '.error' > /dev/null 2>&1; then
    echo "✗ Error updating configuration:"
    echo "$RESPONSE" | jq '.'
    exit 1
fi

echo "✓ Hero banner updated successfully!"
echo ""
echo "Updated hero section:"
echo "  Image URL: $IMAGE_URL"
echo "  Heading: $HEADING"
echo "  Subheading: $SUBHEADING"
echo "  Button Text: $BUTTON_TEXT"
echo "  Button Link: $BUTTON_LINK"
echo ""
echo "The hero section will now display this banner image."
