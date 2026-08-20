int? imageCachePixelDimension(double logicalPixels, double devicePixelRatio) {
  if (!logicalPixels.isFinite || logicalPixels <= 0) return null;
  if (!devicePixelRatio.isFinite || devicePixelRatio <= 0) return null;
  return (logicalPixels * devicePixelRatio).ceil();
}
