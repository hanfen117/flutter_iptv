class Channel {
  final String name;
  final String url;
  final String group;
  final String logo;

  Channel({
    required this.name,
    required this.url,
    required this.group,
    this.logo = "",
  });
}
