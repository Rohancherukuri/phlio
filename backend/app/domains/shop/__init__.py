"""Phlio Shop domain — universal marketplace + local/quick commerce.

Per Phlio_Final_Product_Blueprint.md section 10: "There is no separate
top-level Phlio Art domain in the current architecture" — Art & Handmade
is one category within Shop, alongside Fashion, Electronics, Home &
Living, and others. This build stage seeds and exercises only the Art &
Handmade category (matching the reference UI's "Phlio Art" screen), but
the domain model (`ShopCategory`, `Product`, `Seller`) is the general
Shop shape from day one so adding a second category later is additive,
not a rewrite.
"""
