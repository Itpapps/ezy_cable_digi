/// A dropdown option for the Create-Complaint screen (category or employee).
/// [id] 0 represents the "Select" placeholder (Android prepends it).
class ComplaintOption {
  final int id;
  final String name;
  const ComplaintOption(this.id, this.name);

  static const ComplaintOption select = ComplaintOption(0, 'Select');

  @override
  bool operator ==(Object other) =>
      other is ComplaintOption && other.id == id && other.name == name;

  @override
  int get hashCode => Object.hash(id, name);
}
