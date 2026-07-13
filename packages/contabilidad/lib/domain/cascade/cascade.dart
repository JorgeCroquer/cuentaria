import 'package:equatable/equatable.dart';
import 'cascade_step.dart';

class Cascade extends Equatable {
  final List<CascadeStep> steps;

  Cascade(List<CascadeStep> steps) : steps = List.unmodifiable(steps);

  @override
  List<Object?> get props => [steps];
}
