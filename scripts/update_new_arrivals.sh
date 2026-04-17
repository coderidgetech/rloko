#!/bin/bash

# API Configuration
API_URL="http://localhost:8080/api"
AUTH_TOKEN="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VyX2lkIjoiNjk2YTA4ZmFmNzI0NzRkNzE3Njc1ZjExIiwiZW1haWwiOiJhZG1pbkBybG9jby5jb20iLCJyb2xlIjoiYWRtaW4iLCJleHAiOjE3NjkyNzE3NTYsImlhdCI6MTc2OTE4NTM1Nn0.aVZaPDb63EYeyOWDKRpNlxUiGvBqm_Xaq-WG-YzeoZg"

echo "Fetching products to mark as new arrivals..."

# Get first 20 products
PRODUCTS=$(curl -s "${API_URL}/products?limit=20" -H "Authorization: Bearer ${AUTH_TOKEN}")

# Extract product IDs (first 10 products)
PRODUCT_IDS=$(echo "$PRODUCTS" | jq -r '.products[0:10] | .[] | .id')

echo "Updating products to mark as new arrivals..."

# Update each product to have new_arrival: true
for PRODUCT_ID in $PRODUCT_IDS; do
    echo "Updating product: $PRODUCT_ID"
    curl -X PUT "${API_URL}/products/${PRODUCT_ID}" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer ${AUTH_TOKEN}" \
        -d "{\"new_arrival\": true}" \
        -s > /dev/null
done

echo "Done! Updated 10 products to be new arrivals."
echo "Verifying..."
curl -s "${API_URL}/products/new-arrivals?limit=20" | jq 'length'
