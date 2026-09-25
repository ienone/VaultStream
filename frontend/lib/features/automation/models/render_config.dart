typedef RenderConfig = Map<String, dynamic>;

extension RenderConfigX on RenderConfig {
  Map<String, dynamic> toJson() => Map<String, dynamic>.from(this);
}
