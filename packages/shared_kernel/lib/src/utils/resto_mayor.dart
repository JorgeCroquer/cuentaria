List<BigInt> repartirRestoMayor(BigInt total, List<double> weights) {
  if (weights.isEmpty) {
    return [];
  }

  if (total.isNegative) {
    throw ArgumentError('El total debe ser mayor o igual a 0');
  }

  if (weights.any((w) => w < 0)) {
    throw ArgumentError('Los pesos deben ser mayores o iguales a 0');
  }

  if (weights.length == 1) {
    return [total];
  }

  double sumWeights = weights.fold(0.0, (sum, w) => sum + w);

  // Si todos los pesos son 0, distribuimos equitativamente (peso 1.0 para todos)
  List<double> actualWeights = weights;
  if (sumWeights == 0.0) {
    actualWeights = List.filled(weights.length, 1.0);
    sumWeights = weights.length.toDouble();
  }

  // Calculamos la parte entera de cada distribución
  final List<int> intParts = [];
  final List<double> remainders = [];

  for (int i = 0; i < actualWeights.length; i++) {
    final weight = actualWeights[i];
    final exactValue = (total.toDouble() * weight) / sumWeights;
    final intPart = exactValue.floor();
    intParts.add(intPart);
    remainders.add(exactValue - intPart);
  }

  final int sumIntParts = intParts.fold(0, (sum, val) => sum + val);
  final int missing = total.toInt() - sumIntParts;

  // Guardamos los índices originales para poder ordenarlos por resto
  final List<int> indices = List.generate(actualWeights.length, (i) => i);

  // Ordenamos los índices por el tamaño del residuo (descendente)
  // En caso de empate, se respeta el orden original (índice menor primero)
  indices.sort((a, b) {
    final int cmp = remainders[b].compareTo(remainders[a]);
    if (cmp != 0) return cmp;
    return a.compareTo(b);
  });

  // Distribuimos el faltante
  for (int i = 0; i < missing; i++) {
    intParts[indices[i]] += 1;
  }

  return intParts.map((val) => BigInt.from(val)).toList();
}
