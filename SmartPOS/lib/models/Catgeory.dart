class Category {
  final String categoryCode;
  final String categoryName;
  final String mainGroup;

  Category({
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

  factory Category.fromMap(Map<String, dynamic> map) {
    return Category(
      categoryCode: map['category_code'] as String? ?? '',
      categoryName: map['category_name'] as String? ?? '',
      mainGroup: map['main_group'] as String? ?? '',
    );
  }
}
