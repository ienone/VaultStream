typedef RenderConfig = Map<String, dynamic>;

extension RenderConfigX on RenderConfig {
  bool get hasStructureWrapper => this['structure'] is Map;

  Map<String, dynamic> get structure {
    final wrapped = this['structure'];
    if (wrapped is Map) {
      return Map<String, dynamic>.from(wrapped);
    }
    return toJson();
  }

  Map<String, dynamic> toJson() => Map<String, dynamic>.from(this);

  RenderConfig withStructure(Map<String, dynamic> structure) {
    final normalized = Map<String, dynamic>.from(structure);
    if (hasStructureWrapper) {
      return {'structure': normalized};
    }
    return normalized;
  }
}
