double? computeBmi(num? heightCm, num? weightKg) {
  final height = heightCm?.toDouble();
  final weight = weightKg?.toDouble();
  if (height == null || weight == null || height <= 0 || weight <= 0) return null;
  return weight / ((height / 100) * (height / 100));
}

String bmiBandLabel(double bmi) {
  if (bmi < 18.5) return 'Underweight';
  if (bmi < 25) return 'Normal';
  if (bmi < 30) return 'Overweight';
  return 'Obese';
}

Map<String, dynamic>? summarizeBmi(num? heightCm, num? weightKg) {
  final value = computeBmi(heightCm, weightKg);
  if (value == null) return null;
  return {
    'bmi': double.parse(value.toStringAsFixed(1)),
    'band_label': bmiBandLabel(value),
    'height_cm': heightCm,
    'weight_kg': weightKg,
  };
}
