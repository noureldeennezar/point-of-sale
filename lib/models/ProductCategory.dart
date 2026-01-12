class ProductCategory {
  final String categoryCode;
  final String categoryName;
  final String mainGroup;

  ProductCategory({
    required this.categoryCode,
    required this.categoryName,
    required this.mainGroup,
  });

  Map<String, dynamic> toMap() {
    return {
      'category_code': categoryCode,
      'category_name': categoryName,
      'main_group': mainGroup,
    };
  }

  factory ProductCategory.fromMap(Map<String, dynamic> map) {
    return ProductCategory(
      categoryCode: map['category_code'] as String? ?? '',
      categoryName: map['category_name'] as String? ?? '',
      mainGroup: map['main_group'] as String? ?? '',
    );
  }
}
