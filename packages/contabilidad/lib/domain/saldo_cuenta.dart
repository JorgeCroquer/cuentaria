import 'package:equatable/equatable.dart';
import 'package:shared_kernel/shared_kernel.dart';

class SaldoCuenta extends Equatable {
  final Money native;
  final int usd;

  const SaldoCuenta({required this.native, required this.usd});

  @override
  List<Object?> get props => [native, usd];
}
