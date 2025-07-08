class Payment {
  final String paymentType; // 'Cash' or 'Credit Card'
  final double amount;
  final bool isSuccessful;
  final DateTime date;
  final String? cardNumber; // Only for Credit Card payments

  Payment({
    required this.paymentType,
    required this.amount,
    this.isSuccessful = false,
    this.cardNumber,
    DateTime? date,
  }) : date = date ?? DateTime.now();
}
