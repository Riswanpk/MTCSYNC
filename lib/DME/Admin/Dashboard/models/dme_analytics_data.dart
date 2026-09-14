class DmeAnalyticsSummary {
  final int uniqueCustomersVisited;
  final int newCustomersCreated;
  final int completedRemindersCount;
  final Map<int, int> salesByBranch;
  final Map<int, int> salesByCategory;
  final Map<int, int> salesByType;

  const DmeAnalyticsSummary({
    this.uniqueCustomersVisited = 0,
    this.newCustomersCreated = 0,
    this.completedRemindersCount = 0,
    this.salesByBranch = const {},
    this.salesByCategory = const {},
    this.salesByType = const {},
  });

  factory DmeAnalyticsSummary.empty() {
    return const DmeAnalyticsSummary();
  }
}
