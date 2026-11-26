/// Represents a cleanable cache/temp category in the Linux environment.
class CleanupCategory {
  final String id;
  final String title;
  final String subtitle;
  final List<String> paths;
  final int sizeKb;
  final bool defaultSelected;
  final bool isAptClean;
  final bool isTmpClean;

  const CleanupCategory({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.paths,
    this.sizeKb = 0,
    this.defaultSelected = true,
    this.isAptClean = false,
    this.isTmpClean = false,
  });

  CleanupCategory copyWith({int? sizeKb}) {
    return CleanupCategory(
      id: id,
      title: title,
      subtitle: subtitle,
      paths: paths,
      sizeKb: sizeKb ?? this.sizeKb,
      defaultSelected: defaultSelected,
      isAptClean: isAptClean,
      isTmpClean: isTmpClean,
    );
  }
}
