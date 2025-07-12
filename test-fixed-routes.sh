#!/bin/bash

echo "Testing fixed where-is-my-friends plugin routes..."

echo "1. Testing frontend route (should return HTML):"
echo "GET /where-is-my-friends"
curl -s -I http://localhost:4200/where-is-my-friends | head -5

echo ""
echo "2. Testing API route (should return JSON):"
echo "GET /api/where-is-my-friends"
curl -s http://localhost:4200/api/where-is-my-friends | head -3

echo ""
echo "Route test completed!"
echo "Frontend route should return HTML with status 200"
echo "API route should return JSON data" 