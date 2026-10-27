public enum CorrectionTiming {
    public static func allowsAutomaticReplacement(
        atBoundary: Bool, insertedBoundary: String, markedLength: Int?
    ) -> Bool {
        atBoundary && insertedBoundary.contains(where: \.isWhitespace) && markedLength == 0
    }
}
