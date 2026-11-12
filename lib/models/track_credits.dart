/// 曲目制作人员（「查看制作人员」）：按角色分组的参与者 + 版权来源。
///
/// 分组名与角色名由 Spotify 按请求的 Accept-Language 本地化（如「作曲和作词」「混音工程师」）。
class TrackCredits {
  final String trackName;
  final List<CreditGroup> groups;

  /// 版权 / 发行来源（如唱片公司）。
  final List<String> sources;

  const TrackCredits({required this.trackName, this.groups = const [], this.sources = const []});

  bool get isEmpty => groups.isEmpty && sources.isEmpty;
}

/// 一个角色分组（如「表演者」「制作兼工程」），保持接口返回的顺序。
class CreditGroup {
  final String name;
  final List<CreditPerson> people;

  const CreditGroup({required this.name, required this.people});
}

/// 分组内的一位参与者；同一人在同组的多个角色合并为 [roles]。
class CreditPerson {
  final String name;
  final List<String> roles;

  /// 在 Spotify 上有艺人页时为艺人 id（可点击进入），否则为空。
  final String artistId;

  const CreditPerson({required this.name, required this.roles, this.artistId = ''});

  bool get hasArtistPage => artistId.isNotEmpty;
}
