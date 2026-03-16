import simd

/// Unprojects a 2D pixel coordinate + depth value into a 3D camera-space position
/// using the camera's intrinsic matrix.
///
/// - Parameters:
///   - point: Pixel coordinate (px, py) in the image.
///   - depth: Depth value in meters at the given pixel.
///   - intrinsics: Camera intrinsic matrix (`simd_float3x3`, column-major).
///     - `fx = intrinsics.columns.0.x`
///     - `fy = intrinsics.columns.1.y`
///     - `cx = intrinsics.columns.2.x`
///     - `cy = intrinsics.columns.2.y`
/// - Returns: 3D position in camera space (x, y, z) where z = depth.
public func unproject(point: SIMD2<Float>, depth: Float, intrinsics: simd_float3x3) -> SIMD3<Float> {
    let fx = intrinsics.columns.0.x
    let fy = intrinsics.columns.1.y
    let cx = intrinsics.columns.2.x
    let cy = intrinsics.columns.2.y

    let x = (point.x - cx) * depth / fx
    let y = (point.y - cy) * depth / fy
    let z = depth

    return SIMD3<Float>(x, y, z)
}
