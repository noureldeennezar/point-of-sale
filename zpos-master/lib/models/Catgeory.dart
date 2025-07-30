// TODO Implement this library.

class ItemGroup {
  final String itmGroupCode;
  final String itmGroupName;
  final String mainGroup;

  ItemGroup({
    required this.itmGroupCode,
    required this.itmGroupName,
    required this.mainGroup,
  });

  Map<String, dynamic> toMap() {
    return {
      'itm_group_code': itmGroupCode,
      'itm_group_name': itmGroupName,
      'main_group': mainGroup,
    };
  }
}
