#!/bin/bash

echo "Testing where-is-my-friends plugin routes..."

# Test the main route
echo "Testing /where-is-my-friends route..."
curl -s -o /dev/null -w "%{http_code}" http://localhost:3000/where-is-my-friends

echo ""

# Test API routes
echo "Testing API routes..."
echo "GET /where-is-my-friends (API):"
curl -s -o /dev/null -w "%{http_code}" http://localhost:3000/where-is-my-friends

echo ""

echo "Route test completed. Check the HTTP status codes above."
echo "200 = Success, 404 = Not Found, 500 = Server Error" 