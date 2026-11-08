// queries.js — ThreadHaus MongoDB queries
// Portfolio 4: NoSQL Design and Comparison
// Run with: docker exec -i threadhaus-mongo mongosh \
//   --username <user> --password <pass> --authenticationDatabase admin threadhaus \
//   < queries.js

print("=== M1: Catalogue search ===");
print("Business question: In-stock variants of products in the Men parent category,");
print("size M, colour Black, ordered by price ascending.");
print("PostgreSQL equivalent: Q1 from Portfolio 2.");

db.products.aggregate([
  { $match: {
      category_path: "Men",
      variants: { $elemMatch: { size: "M", colour: "Black", stock_qty: { $gt: 0 } } }
  }},
  { $unwind: "$variants" },
  { $match: { "variants.size": "M", "variants.colour": "Black", "variants.stock_qty": { $gt: 0 } } },
  { $project: {
      _id: 0, product_id: 1, name: 1, brand: 1,
      sku: "$variants.sku", size: "$variants.size", colour: "$variants.colour",
      price: "$variants.price", stock_qty: "$variants.stock_qty"
  }},
  { $sort: { price: 1 } },
  { $limit: 10 }
]).forEach(doc => print(JSON.stringify(doc)));

print("\n=== M2: Product page ===");
print("Business question: Fetch one product with all variants in a single read.");
print("Parameters: product_id = 1");

const p = db.products.findOne({ product_id: 1 }, { _id: 0 });
if (p) {
  print("name: " + p.name + "  brand: " + p.brand + "  base_price: " + p.base_price);
  print("category_path: " + JSON.stringify(p.category_path));
  print("rating: avg=" + p.rating_summary.average + " count=" + p.rating_summary.count);
  print("variants (" + p.variants.length + "):");
  p.variants.forEach(v => print("  " + JSON.stringify(v)));
}

print("\n=== M3: Top rated products ===");
print("Business question: Top 20 products with at least 5 reviews, ordered by average rating.");
print("PostgreSQL equivalent: Q6 from Portfolio 2. Uses embedded rating_summary.");

db.products.find(
  { "rating_summary.count": { $gte: 5 } },
  { _id: 0, product_id: 1, name: 1, brand: 1, rating_summary: 1 }
)
.sort({ "rating_summary.average": -1, "rating_summary.count": -1 })
.limit(20)
.forEach(doc => print(JSON.stringify(doc)));

print("\n=== M4: Stock value per category ===");
print("Business question: Total stock value (price * stock_qty) grouped by top-level category.");

db.products.aggregate([
  { $unwind: "$variants" },
  { $group: {
      _id: { $arrayElemAt: ["$category_path", 0] },
      total_stock_value: { $sum: { $multiply: ["$variants.price", "$variants.stock_qty"] } },
      total_units: { $sum: "$variants.stock_qty" }
  }},
  { $sort: { total_stock_value: -1 } },
  { $project: {
      _id: 0,
      category: "$_id",
      total_stock_value: { $round: ["$total_stock_value", 2] },
      total_units: 1
  }}
]).forEach(doc => print(JSON.stringify(doc)));

print("\n=== M5: Text search ===");
print("Business question: Find products whose name or description contains 'Kaftan'.");
print("Requires a text index (created in indexes.js). Creating inline for this run.");

db.products.createIndex({ name: "text", description: "text" });

db.products.find(
  { $text: { $search: "Kaftan" } },
  { _id: 0, product_id: 1, name: 1, brand: 1, score: { $meta: "textScore" } }
)
.sort({ score: { $meta: "textScore" } })
.limit(10)
.forEach(doc => print(JSON.stringify(doc)));
