// validation.js
// Adds a JSON Schema validator to the products collection in threadhaus.
// Run with: docker exec -i threadhaus-mongo mongosh \
//   --username <user> --password <pass> --authenticationDatabase admin threadhaus \
//   < validation.js

// Apply the validator to the existing products collection
db.runCommand({
  collMod: "products",
  validator: {
    $jsonSchema: {
      bsonType: "object",
      required: ["name", "category_path", "base_price", "variants"],
      properties: {
        name: {
          bsonType: "string",
          description: "product name is required"
        },
        category_path: {
          bsonType: "array",
          minItems: 1,
          description: "category_path must be a non-empty array"
        },
        base_price: {
          bsonType: ["double", "decimal", "int", "long"],
          minimum: 0,
          description: "base_price must be >= 0"
        },
        variants: {
          bsonType: "array",
          description: "variants must be an array",
          items: {
            bsonType: "object",
            required: ["sku", "size", "colour", "price", "stock_qty"],
            properties: {
              sku:       { bsonType: "string" },
              size:      { bsonType: "string" },
              colour:    { bsonType: "string" },
              price:     { bsonType: ["double","decimal","int","long"], minimum: 0 },
              stock_qty: { bsonType: "int", minimum: 0,
                           description: "stock_qty must be an integer >= 0" }
            }
          }
        }
      }
    }
  },
  validationLevel: "strict",
  validationAction: "error"
});

print("Validator applied to products collection.");

// --- Validation test ---
// Try inserting a product with stock_qty: -1. Must be rejected.
print("\nAttempting to insert an invalid product (stock_qty: -1)...");
try {
  db.products.insertOne({
    product_id: 99999,
    name: "Test Invalid Product",
    category_path: ["Men", "Men Tops"],
    base_price: 5000.0,
    description: "This insert should fail",
    variants: [
      {
        variant_id: 99999,
        sku: "TH-INVALID-001",
        size: "M",
        colour: "Black",
        price: 5000.0,
        stock_qty: -1
      }
    ],
    rating_summary: { average: 0, count: 0 }
  });
  print("ERROR: Insert succeeded — validator is NOT working.");
} catch (e) {
  print("Insert correctly rejected.");
  print("Error code: " + e.codeName);
  print("Error: " + e.message.substring(0, 250));
}

print("\nValidation test complete.");
