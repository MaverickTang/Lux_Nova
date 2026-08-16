//
//  VortexLoadingView.swift
//  Mindflow
//

import SwiftUI

// MARK: - 等待大模型 Loading 特效：3D点阵黑洞吸积盘 (小黑核 + 大扩散 + 锐利星点)
struct VortexLoadingView: View {
    @State private var particles: [VortexParticle] = VortexLoadingView.generateParticles(count: 3000)

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let elapsed = timeline.date.timeIntervalSinceReferenceDate
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                
                // 1. 【核心修改】大幅缩小中心黑核的半径
                let baseRadius = min(size.width, size.height) * 0.25

                context.blendMode = .plusLighter

                let tiltAngle: Double = .pi * 0.36
                let cosTilt = cos(tiltAngle)
                let sinTilt = sin(tiltAngle)

                for p in particles {
                    let currentAngle = p.angle + elapsed * p.angularSpeed
                    
                    let freq: Double = 4.0
                    let noise = sin(currentAngle * freq + elapsed * 1.5 + p.noisePhase) * (5.0 + p.radiusOffset * 0.05)
                    
                    let r = baseRadius + p.radiusOffset + noise

                    let x0 = cos(currentAngle) * r
                    let y0 = p.yOffset
                    let z0 = sin(currentAngle) * r

                    let rx = x0
                    let ry = y0 * cosTilt - z0 * sinTilt
                    let rz = y0 * sinTilt + z0 * cosTilt

                    let focalLength: Double = 800.0
                    let perspectiveScale = focalLength / (focalLength + rz)
                    let screenX = center.x + rx * perspectiveScale
                    let screenY = center.y + ry * perspectiveScale

                    // 因为扩散范围变大了，放宽 Z 轴深度剔除范围
                    let maxZ = baseRadius + 400.0
                    let depthFactor = (rz + maxZ) / (2 * maxZ)
                    
                    if depthFactor > 0.85 { continue }

                    // 调整能量计算范围，适应更大的扩散盘
                    let radialEnergy = 1.0 - min(p.radiusOffset / 150.0, 1.0)
                    let densityClump = pow(radialEnergy, 2.0)

                    // 2. 【核心修改】解决模糊：让点变得更小、更紧凑，恢复 TDParticleSphere 的锐利感
                    let sizeBase = max(0.4, (1.0 - depthFactor))
                    let dotSize = sizeBase * 1.0 + min(densityClump * 2.5, 3.0)

                    let alphaBase = (1.0 - (depthFactor / 0.85))
                    let sinePulse = pow(sin(elapsed * p.flickerSpeed + p.noisePhase), 2)
                    
                    // 3. 【核心修改】提高最低亮度，防止暗部粒子糊成一团灰影
                    let flicker = 0.6 + 0.7 * sinePulse
                    let opacity = min(max(alphaBase * (0.2 + densityClump), 0.1), 1.0) * flicker

                    let isCore = min(densityClump * 1.5, 1.0)
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

                // 配合缩小的内圈，重新调整中心深渊遮罩
                context.drawLayer { ctx in
                    ctx.blendMode = .normal
                    ctx.translateBy(x: center.x, y: center.y)
                    ctx.scaleBy(x: 1.0, y: cosTilt)
                    
                    let maskGradient = Gradient(colors: [
                        Color.black.opacity(1.0),
                        Color.black.opacity(1.0),
                        Color.black.opacity(0.8),
                        Color.black.opacity(0.0)
                    ])
                    
                    ctx.fill(
                        Path(ellipseIn: CGRect(
                            x: -baseRadius * 1.1,
                            y: -baseRadius * 1.1,
                            width: baseRadius * 2.2,
                            height: baseRadius * 2.2
                        )),
                        with: .radialGradient(maskGradient, center: .zero, startRadius: baseRadius * 0.2, endRadius: baseRadius * 1.0)
                    )
                }
            }
        }
    }

    private static func generateParticles(count: Int) -> [VortexParticle] {
        return (0..<count).map { _ in
            let angle = Double.random(in: 0...(2 * .pi))
            
            // 4. 【核心修改】扩大粒子扩散范围
            // 降低集中的指数（从 3.5 降到 2.5），让更多粉尘逸出内环
            let distribution = pow(Double.random(in: 0...1), 2.0)
            // 大幅提升最大偏移量（从 180.0 提升到 350.0），创造出更庞大的星系感
            let radiusOffset = distribution * 500.0
            
            let speedBase = 0.15 + (1.0 / max(radiusOffset, 5.0)) * 5.0
            let angularSpeed = speedBase * Double.random(in: 0.7...1.3)
            
            // 增加 Y 轴维度的厚度扰动，让庞大的外围星云显得更立体
            let yOffset = Double.random(in: -1...1) * (2.0 + distribution * 30.0)

            return VortexParticle(
                angle: angle,
                radiusOffset: radiusOffset,
                angularSpeed: angularSpeed,
                noisePhase: Double.random(in: 0...1000),
                yOffset: yOffset,
                flickerSpeed: Double.random(in: 1.0...3.5)
            )
        }
    }
}

// 数据结构保持不变
struct VortexParticle {
    let angle: Double
    let radiusOffset: Double
    let angularSpeed: Double
    let noisePhase: Double
    let yOffset: Double
    let flickerSpeed: Double
}
