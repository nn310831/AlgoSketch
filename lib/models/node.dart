import 'package:equatable/equatable.dart';

class Node extends Equatable {
  final String id;
  final String? value;
  final double centerX;
  final double centerY;
  final double radius;

  const Node({
    required this.id,
    this.value,
    required this.centerX,
    required this.centerY,
    required this.radius,
  });

  Node copyWith({
    String? id,
    String? value,
    double? centerX,
    double? centerY,
    double? radius,
  }) {
    return Node(
      id: id ?? this.id,
      value: value ?? this.value, // 若遇到需要清空 value 的情形，這裡的簡單寫法無法指定 null，但多數更新場景夠用
      centerX: centerX ?? this.centerX,
      centerY: centerY ?? this.centerY,
      radius: radius ?? this.radius,
    );
  }

  @override
  List<Object?> get props => [id, value, centerX, centerY, radius];
}
