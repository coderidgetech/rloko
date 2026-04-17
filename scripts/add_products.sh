#!/bin/bash

# API Configuration
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
    echo "Run backend seed first: MONGODB_URI=mongodb://admin:password@localhost:28017/rloco?authSource=admin go run backend/migrations/seed.go"
    echo "Then activate admin: docker exec rloco-mongodb mongosh --quiet -u admin -p password --authenticationDatabase admin rloco --eval 'db.users.updateOne({email:\"admin@rloco.com\"}, {\$set: {active: true}})'"
    exit 1
fi
echo "Logged in successfully."
echo ""

# Function to create a product
create_product() {
    local name=$1
    local price=$2
    local category=$3
    local gender=$4
    local subcategory=$5
    local description=$6
    local images=$7
    local colors=$8
    local sizes=$9
    local material=${10}
    local featured=${11}
    local on_sale=${12}
    local original_price=${13}

    local stock_json="{\"S\": 10, \"M\": 15, \"L\": 12, \"XL\": 8}"
    if [ "$gender" = "men" ]; then
        stock_json="{\"S\": 10, \"M\": 15, \"L\": 12, \"XL\": 8, \"XXL\": 5}"
    fi

    local sale_json=""
    if [ "$on_sale" = "true" ] && [ -n "$original_price" ]; then
        sale_json="\"on_sale\": true, \"original_price\": $original_price,"
    fi

    local featured_json=""
    if [ "$featured" = "true" ]; then
        featured_json="\"featured\": true,"
    fi

    curl -s -X POST "${API_URL}/products" \
        -b "$COOKIE_FILE" \
        -H "Content-Type: application/json" \
        -d "{
            \"name\": \"$name\",
            \"price\": $price,
            $sale_json
            \"price_inr\": $(echo "$price * 83" | bc),
            \"category\": \"$category\",
            \"subcategory\": \"$subcategory\",
            \"gender\": \"$gender\",
            \"images\": [$images],
            \"colors\": [$colors],
            \"sizes\": [$sizes],
            \"description\": \"$description\",
            \"material\": \"$material\",
            \"stock\": $stock_json,
            $featured_json
            \"new_arrival\": false
        }" | jq '.'
    
    echo ""
    sleep 0.5
}

echo "Adding products for all categories..."
echo "======================================"

# WOMEN'S DRESSES (2 products)
echo "Adding Women's Dresses..."
create_product \
    "Elegant Evening Dress" \
    299.99 \
    "Dresses" \
    "women" \
    "Evening" \
    "A stunning evening dress perfect for special occasions. Features elegant silhouette with premium fabric." \
    "\"https://images.unsplash.com/photo-1595777457583-95e059d581b8?w=800&q=80\", \"https://images.unsplash.com/photo-1515372039744-b8f02a3ae446?w=800&q=80\"" \
    "\"Black\", \"Navy\", \"Burgundy\"" \
    "\"S\", \"M\", \"L\", \"XL\"" \
    "Silk Blend" \
    "true" \
    "true" \
    "399.99"

create_product \
    "Casual Summer Dress" \
    89.99 \
    "Dresses" \
    "women" \
    "Casual" \
    "Comfortable and stylish summer dress made from breathable cotton blend. Perfect for everyday wear." \
    "\"https://images.unsplash.com/photo-1509631179647-0177331693ae?w=800&q=80\", \"https://images.unsplash.com/photo-1515886657613-9f3515b0c78f?w=800&q=80\"" \
    "\"White\", \"Floral\", \"Blue\"" \
    "\"S\", \"M\", \"L\", \"XL\"" \
    "Cotton Blend" \
    "false" \
    "false" \
    ""

# WOMEN'S TOPS (2 products)
echo "Adding Women's Tops..."
create_product \
    "Classic White Blouse" \
    79.99 \
    "Tops" \
    "women" \
    "Blouses" \
    "Timeless white blouse perfect for office or casual wear. Made from premium cotton with elegant details." \
    "\"https://images.unsplash.com/photo-1594633312681-425c7b97ccd1?w=800&q=80\", \"https://images.unsplash.com/photo-1571945153237-4929e783af4a?w=800&q=80\"" \
    "\"White\", \"Ivory\"" \
    "\"S\", \"M\", \"L\", \"XL\"" \
    "Cotton" \
    "true" \
    "false" \
    ""

create_product \
    "Silk Camisole Top" \
    59.99 \
    "Tops" \
    "women" \
    "Camisoles" \
    "Luxurious silk camisole top for layering or standalone wear. Soft and comfortable with elegant finish." \
    "\"https://images.unsplash.com/photo-1594633313593-bab3825d0caf?w=800&q=80\"" \
    "\"Black\", \"Nude\", \"White\"" \
    "\"S\", \"M\", \"L\"" \
    "Silk" \
    "false" \
    "true" \
    "79.99"

# WOMEN'S BOTTOMS (2 products)
echo "Adding Women's Bottoms..."
create_product \
    "High-Waisted Trousers" \
    129.99 \
    "Bottoms" \
    "women" \
    "Pants" \
    "Professional high-waisted trousers with perfect fit. Ideal for office or smart casual occasions." \
    "\"https://images.unsplash.com/photo-1542272604-787c3835535d?w=800&q=80\"" \
    "\"Black\", \"Navy\", \"Gray\"" \
    "\"S\", \"M\", \"L\", \"XL\"" \
    "Wool Blend" \
    "true" \
    "false" \
    ""

create_product \
    "Denim Jeans" \
    99.99 \
    "Bottoms" \
    "women" \
    "Jeans" \
    "Classic fit denim jeans with stretch for comfort. Versatile style that works for any occasion." \
    "\"https://images.unsplash.com/photo-1542272604-787c3835535d?w=800&q=80\"" \
    "\"Blue\", \"Black\", \"White\"" \
    "\"S\", \"M\", \"L\", \"XL\"" \
    "Denim" \
    "false" \
    "true" \
    "129.99"

# WOMEN'S OUTERWEAR (2 products)
echo "Adding Women's Outerwear..."
create_product \
    "Classic Trench Coat" \
    349.99 \
    "Outerwear" \
    "women" \
    "Coats" \
    "Timeless trench coat in premium fabric. Perfect for transitional weather and elegant styling." \
    "\"https://images.unsplash.com/photo-1539533018447-63fcce2678e3?w=800&q=80\"" \
    "\"Beige\", \"Black\", \"Navy\"" \
    "\"S\", \"M\", \"L\", \"XL\"" \
    "Cotton Blend" \
    "true" \
    "false" \
    ""

create_product \
    "Wool Blazer" \
    199.99 \
    "Outerwear" \
    "women" \
    "Blazers" \
    "Structured wool blazer for professional or smart casual looks. Tailored fit with modern details." \
    "\"https://picsum.photos/seed/wool-blazer/800/800\"" \
    "\"Black\", \"Navy\", \"Gray\"" \
    "\"S\", \"M\", \"L\", \"XL\"" \
    "Wool" \
    "false" \
    "true" \
    "249.99"

# WOMEN'S SHOES (2 products)
echo "Adding Women's Shoes..."
create_product \
    "Leather Ankle Boots" \
    179.99 \
    "Shoes" \
    "women" \
    "Boots" \
    "Stylish leather ankle boots with comfortable heel. Perfect for autumn and winter seasons." \
    "\"https://images.unsplash.com/photo-1543163521-1bf539c55dd2?w=800&q=80\"" \
    "\"Black\", \"Brown\", \"Tan\"" \
    "\"6\", \"7\", \"8\", \"9\", \"10\"" \
    "Leather" \
    "true" \
    "false" \
    ""

create_product \
    "Elegant Heels" \
    149.99 \
    "Shoes" \
    "women" \
    "Heels" \
    "Classic high heels for special occasions. Comfortable design with elegant silhouette." \
    "\"https://images.unsplash.com/photo-1543163521-1bf539c55dd2?w=800&q=80\"" \
    "\"Black\", \"Nude\", \"Red\"" \
    "\"6\", \"7\", \"8\", \"9\"" \
    "Leather" \
    "false" \
    "true" \
    "199.99"

# WOMEN'S BAGS (2 products)
echo "Adding Women's Bags..."
create_product \
    "Leather Handbag" \
    249.99 \
    "Bags" \
    "women" \
    "Handbags" \
    "Premium leather handbag with spacious interior. Timeless design perfect for everyday use." \
    "\"https://images.unsplash.com/photo-1584917865442-de89df76afd3?w=800&q=80\"" \
    "\"Black\", \"Brown\", \"Tan\"" \
    "\"One Size\"" \
    "Leather" \
    "true" \
    "false" \
    ""

create_product \
    "Designer Clutch" \
    129.99 \
    "Bags" \
    "women" \
    "Clutches" \
    "Elegant designer clutch for evening events. Compact yet spacious with luxurious finish." \
    "\"https://images.unsplash.com/photo-1590874103328-eac38a683ce7?w=800&q=80\"" \
    "\"Gold\", \"Silver\", \"Black\"" \
    "\"One Size\"" \
    "Synthetic Leather" \
    "false" \
    "true" \
    "179.99"

# WOMEN'S JEWELRY (2 products)
echo "Adding Women's Jewelry..."
create_product \
    "Pearl Necklace" \
    199.99 \
    "Jewelry" \
    "women" \
    "Necklaces" \
    "Classic pearl necklace with elegant design. Perfect for special occasions or everyday elegance." \
    "\"https://images.unsplash.com/photo-1515562141207-7a88fb7ce338?w=800&q=80\"" \
    "\"White\", \"Black\"" \
    "\"One Size\"" \
    "Pearl" \
    "true" \
    "false" \
    ""

create_product \
    "Gold Earrings" \
    89.99 \
    "Jewelry" \
    "women" \
    "Earrings" \
    "Elegant gold-plated earrings with modern design. Versatile style for any occasion." \
    "\"https://picsum.photos/seed/gold-earrings/800/800\"" \
    "\"Gold\", \"Rose Gold\"" \
    "\"One Size\"" \
    "Gold Plated" \
    "false" \
    "true" \
    "129.99"

# MEN'S SHIRTS (2 products)
echo "Adding Men's Shirts..."
create_product \
    "Classic Dress Shirt" \
    89.99 \
    "Shirts" \
    "men" \
    "Dress Shirts" \
    "Premium cotton dress shirt perfect for office or formal occasions. Tailored fit with quality fabric." \
    "\"https://images.unsplash.com/photo-1596755094514-f87e34085b2c?w=800&q=80\"" \
    "\"White\", \"Blue\", \"Gray\"" \
    "\"S\", \"M\", \"L\", \"XL\", \"XXL\"" \
    "Cotton" \
    "true" \
    "false" \
    ""

create_product \
    "Casual Button-Down Shirt" \
    69.99 \
    "Shirts" \
    "men" \
    "Casual Shirts" \
    "Comfortable casual shirt for everyday wear. Relaxed fit with modern style." \
    "\"https://images.unsplash.com/photo-1617127365659-c47fa864d8bc?w=800&q=80\"" \
    "\"Navy\", \"Green\", \"White\"" \
    "\"S\", \"M\", \"L\", \"XL\", \"XXL\"" \
    "Cotton Blend" \
    "false" \
    "true" \
    "89.99"

# MEN'S PANTS (2 products)
echo "Adding Men's Pants..."
create_product \
    "Slim Fit Chinos" \
    99.99 \
    "Pants" \
    "men" \
    "Chinos" \
    "Modern slim fit chinos in premium cotton. Versatile style for smart casual looks." \
    "\"https://images.unsplash.com/photo-1506629082955-511b1aa562c8?w=800&q=80\"" \
    "\"Khaki\", \"Navy\", \"Gray\"" \
    "\"S\", \"M\", \"L\", \"XL\", \"XXL\"" \
    "Cotton" \
    "true" \
    "false" \
    ""

create_product \
    "Classic Denim Jeans" \
    89.99 \
    "Pants" \
    "men" \
    "Jeans" \
    "Classic fit denim jeans with comfortable stretch. Timeless style for everyday wear." \
    "\"https://images.unsplash.com/photo-1542272604-787c3835535d?w=800&q=80\"" \
    "\"Blue\", \"Black\", \"Gray\"" \
    "\"S\", \"M\", \"L\", \"XL\", \"XXL\"" \
    "Denim" \
    "false" \
    "true" \
    "119.99"

# MEN'S OUTERWEAR (2 products)
echo "Adding Men's Outerwear..."
create_product \
    "Wool Overcoat" \
    399.99 \
    "Outerwear" \
    "men" \
    "Coats" \
    "Premium wool overcoat for winter. Classic design with modern tailoring." \
    "\"https://images.unsplash.com/photo-1539533018447-63fcce2678e3?w=800&q=80\"" \
    "\"Black\", \"Navy\", \"Gray\"" \
    "\"S\", \"M\", \"L\", \"XL\", \"XXL\"" \
    "Wool" \
    "true" \
    "false" \
    ""

create_product \
    "Leather Jacket" \
    299.99 \
    "Outerwear" \
    "men" \
    "Jackets" \
    "Classic leather jacket with modern fit. Timeless style for casual wear." \
    "\"https://images.unsplash.com/photo-1551028719-00167b16eac5?w=800&q=80\"" \
    "\"Black\", \"Brown\"" \
    "\"S\", \"M\", \"L\", \"XL\", \"XXL\"" \
    "Leather" \
    "false" \
    "true" \
    "399.99"

# MEN'S SHOES (2 products)
echo "Adding Men's Shoes..."
create_product \
    "Leather Dress Shoes" \
    199.99 \
    "Shoes" \
    "men" \
    "Dress Shoes" \
    "Premium leather dress shoes for formal occasions. Classic oxford style with comfortable fit." \
    "\"https://images.unsplash.com/photo-1549298916-b41d501d3772?w=800&q=80\"" \
    "\"Black\", \"Brown\"" \
    "\"8\", \"9\", \"10\", \"11\", \"12\"" \
    "Leather" \
    "true" \
    "false" \
    ""

create_product \
    "Casual Sneakers" \
    129.99 \
    "Shoes" \
    "men" \
    "Sneakers" \
    "Comfortable casual sneakers for everyday wear. Modern design with quality materials." \
    "\"https://images.unsplash.com/photo-1542291026-7eec264c27ff?w=800&q=80\"" \
    "\"White\", \"Black\", \"Gray\"" \
    "\"8\", \"9\", \"10\", \"11\", \"12\"" \
    "Canvas/Leather" \
    "false" \
    "true" \
    "169.99"

# MEN'S ACCESSORIES (2 products)
echo "Adding Men's Accessories..."
create_product \
    "Leather Belt" \
    59.99 \
    "Accessories" \
    "men" \
    "Belts" \
    "Classic leather belt with modern buckle. Versatile style for any occasion." \
    "\"https://picsum.photos/seed/leather-belt/800/800\"" \
    "\"Black\", \"Brown\", \"Tan\"" \
    "\"S\", \"M\", \"L\", \"XL\"" \
    "Leather" \
    "true" \
    "false" \
    ""

create_product \
    "Leather Wallet" \
    49.99 \
    "Accessories" \
    "men" \
    "Wallets" \
    "Slim leather wallet with card slots and cash compartment. Premium quality and design." \
    "\"https://images.unsplash.com/photo-1627123424574-724758594e93?w=800&q=80\"" \
    "\"Black\", \"Brown\"" \
    "\"One Size\"" \
    "Leather" \
    "false" \
    "true" \
    "69.99"

echo ""
echo "======================================"
echo "All products added successfully!"
echo "Total: 20 products (2 per category)"
