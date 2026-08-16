//
//  TDParticleSphere.swift
//  Mindflow
//

import SwiftUI

struct TDParticleSphere: View {
    let isRecording: Bool
    let audioLevel: CGFloat
    let compression: Bool
    let expandGlow: Bool

    @State private var baseParticles: [(x: Double, y: Double, z: Double)] = TDParticleSphere.generateOrganicSphere(count: 5000)

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let elapsed = timeline.date.timeIntervalSinceReferenceDate
                let center = CGPoint(x: size.width / 2, y: size.height / 2)

                let easedLevel = pow(max(0.02, min(audioLevel, 1)), 0.5)
                let baseRadius = min(size.width, size.height) * (isRecording ? 0.4 : 0.4)
                let radius = baseRadius * (1 + easedLevel * 0.15) * (compression ? 0.85 : 1)

                let gradient = Gradient(colors: [
                    Color.black.opacity(isRecording ? 1.0 : 0.85),
                    Color.black.opacity(0.0)
                ])
                context.fill(
                    Path(ellipseIn: CGRect(x: 0, y: 0, width: size.width, height: size.height)),
                    with: .radialGradient(gradient, center: center, startRadius: radius * 0.3, endRadius: radius * 1.5)
                )

                context.blendMode = .plusLighter

                let rotationTime = elapsed * (isRecording ? 0.25 : 0.08)
                let fluidTime = elapsed * (isRecording ? 0.8 : 0.25)
                let flowAmplitude = isRecording ? (0.35 + Double(easedLevel) * 0.6) : 0.25

                let cosY = cos(rotationTime)
                let sinY = sin(rotationTime)
                let cosX = cos(rotationTime * 0.6)
                let sinX = sin(rotationTime * 0.6)

                for particle in baseParticles {
                    let rx = particle.x * cosY + particle.z * sinY
                    var ry = particle.y
                    let rz = -particle.x * sinY + particle.z * cosY

                    let finalY = ry * cosX - rz * sinX
                    let finalZ = ry * sinX + rz * cosX
                    ry = finalY

                    let freq: Double = 2.4
                    let flowX = sin(ry * freq + fluidTime) * cos(finalZ * freq - fluidTime)
                    let flowY = sin(finalZ * freq + fluidTime) * cos(rx * freq - fluidTime)
                    let flowZ = sin(rx * freq + fluidTime) * cos(ry * freq - fluidTime)

                    let turbFreq: Double = 5.2
                    let turbX = sin(ry * turbFreq - fluidTime * 1.5) * 0.2
                    let turbY = sin(finalZ * turbFreq - fluidTime * 1.5) * 0.2
                    let turbZ = sin(rx * turbFreq - fluidTime * 1.5) * 0.2

                    let dx = rx + (flowX + turbX) * flowAmplitude
                    let dy = ry + (flowY + turbY) * flowAmplitude
                    let dz = finalZ + (flowZ + turbZ) * flowAmplitude

                    let length = sqrt(dx * dx + dy * dy + dz * dz)
                    let cx = (dx / length) * radius
                    let cy = (dy / length) * radius
                    let cz = (dz / length) * radius

                    let depthFactor = (cz + radius) / (2 * radius)
                    if depthFactor > 0.55 { continue }

                    let energy = abs(flowX * flowY * flowZ) * 8.0
                    let densityClump = pow(energy, 1.5)

                    let focalLength: Double = 800.0
                    let perspectiveScale = focalLength / (focalLength + cz)
                    let screenX = center.x + cx * perspectiveScale
                    let screenY = center.y + cy * perspectiveScale

                    let sizeBase = max(0.4, (1.0 - depthFactor))
                    let dotSize = sizeBase * (isRecording ? 1 : 1) + min(densityClump * (isRecording ? 3.0 : 2.0), 3.5)
                    let alphaBase = (1.0 - (depthFactor / 0.55))
                    let opacity = min(max(alphaBase * (0.15 + densityClump), 0.1), 0.95) * (isRecording ? 1.0 : 0.85)

                    let isCore = min(densityClump, 1.0)
                    let particleColor = Color(
                        red: 0.3 + 0.7 * isCore,
                        green: 0.7 + 0.3 * isCore,
                        blue: 1.0
                    ).opacity(opacity)

                    let rect = CGRect(
                        x: screenX - dotSize / 2,
                        y: screenY - dotSize / 2,
                        width: dotSize,
                        height: dotSize
                    )
                    var path = Path()
                    path.addEllipse(in: rect)
                    context.fill(path, with: .color(particleColor))
                }
            }
        }
    }

    private static func generateOrganicSphere(count: Int) -> [(Double, Double, Double)] {
        var points: [(Double, Double, Double)] = []
        let phi = .pi * (3.0 - sqrt(5.0))

        for i in 0..<count {
            let y = 1.0 - (Double(i) / Double(count - 1)) * 2.0
            let r = sqrt(1.0 - y * y)
            let theta = phi * Double(i)

            let jitterX = Double.random(in: -0.05...0.05)
            let jitterY = Double.random(in: -0.05...0.05)
            let jitterZ = Double.random(in: -0.05...0.05)

            let x = cos(theta) * r + jitterX
            let z = sin(theta) * r + jitterZ
            let ny = y + jitterY

            let len = sqrt(x * x + ny * ny + z * z)
            points.append((x / len, ny / len, z / len))
        }

        return points
    }
}
