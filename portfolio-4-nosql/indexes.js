// indexes.js — ThreadHaus MongoDB indexes for Portfolio 4
// Run with: docker cp indexes.js threadhaus-mongo:/tmp/ && \
//   docker exec threadhaus-mongo mongosh --username <user> --password <pass> \
//   --authenticationDatabase admin threadhaus /tmp/indexes.js
//
// Note: MongoDB cannot create a compound multikey index with two array fields
// (category_path and variants.*). Separate indexes are used instead.

print("=== Creating indexes ===");

// M1: index on category_path (array) for the category filter
// MongoDB will use this for the $match on category_path before $unwind.
db.products.createIndex(
  { "category_path": 1 },
  { name: "idx_category_path" }
);
print("idx_category_path created");

// M1: multikey index on variant fields for the $elemMatch filter after $unwind
db.products.createIndex(
  { "variants.size": 1, "variants.colour": 1, "variants.stock_qty": 1, "variants.price": 1 },
  { name: "idx_variants_search" }
);
print("idx_variants_search created");

// M3: index for top-rated products query (sort on embedded rating_summary)
db.products.createIndex(
  { "rating_summary.average": -1, "rating_summary.count": -1 },
  { name: "idx_rating_summary" }
);
print("idx_rating_summary created");

// M5: text index on name and description
db.products.createIndex(
  { name: "text", description: "text" },
  { name: "idx_text_search" }
);
print("idx_text_search created");

print("All indexes created.");
print(JSON.stringify(db.products.getIndexes().map(i => ({ name: i.name, key: i.key }))));
