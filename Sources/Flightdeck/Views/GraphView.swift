import SwiftUI
import SceneKit
import AppKit

/// Power-user view: sessions as nodes, same-project sessions edge-connected,
/// laid out with a plain O(n²) force relaxation — completely adequate at the
/// node counts this app will ever see, no Barnes-Hut/ANE machinery needed.
struct GraphView: View {
    @Environment(DashboardStore.self) private var store
    @Binding var isPresented: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            SceneKitGraph(sessions: Array(store.sessions.values))
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Button {
                        isPresented = false
                    } label: {
                        Text("← Dashboard").font(Theme.mono(11.5))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .glassPanel(cornerRadius: 7)
                    .keyboardShortcut("g", modifiers: [.command, .shift])

                    Text("SESSION GRAPH").font(Theme.mono(11, weight: .semibold)).tracking(0.8).foregroundStyle(Theme.ink3)
                }
                Text("drag to orbit · scroll to zoom · ⌘⇧G to toggle")
                    .font(Theme.ui(11)).foregroundStyle(Theme.ink3)

                if !store.sessions.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(store.sessions.values)) { s in
                            HStack(spacing: 7) {
                                Circle().fill(Theme.colorForProject(s.project)).frame(width: 7, height: 7)
                                Text(s.project).font(Theme.mono(11)).foregroundStyle(Theme.ink2)
                                Text(Formatters.usd(s.costLedger.reduce(0) { $0 + $1.1 }))
                                    .font(Theme.mono(10.5)).foregroundStyle(Theme.ink3)
                            }
                        }
                    }
                    .padding(12)
                    .glassPanel(cornerRadius: 9)
                }
            }
            .padding(18)
        }
        .background(Theme.page)
    }
}

private struct SceneKitGraph: NSViewRepresentable {
    let sessions: [SessionAgg]

    func makeNSView(context: Context) -> SCNView {
        let view = SCNView()
        view.scene = GraphSceneBuilder.build(sessions: sessions)
        view.backgroundColor = NSColor(Theme.page)
        view.allowsCameraControl = true
        view.autoenablesDefaultLighting = true
        view.antialiasingMode = .multisampling4X
        return view
    }

    func updateNSView(_ nsView: SCNView, context: Context) {
        nsView.scene = GraphSceneBuilder.build(sessions: sessions)
    }
}

private enum GraphSceneBuilder {
    static func build(sessions: [SessionAgg]) -> SCNScene {
        let scene = SCNScene()

        var positions = initialShell(for: sessions)
        relax(&positions, sessions: sessions)

        for session in sessions {
            guard let pos = positions[session.id] else { continue }
            let radius: CGFloat = 0.32 + CGFloat(min(session.contextFraction, 1)) * 0.4
            let sphere = SCNSphere(radius: radius)
            let color = NSColor(Theme.colorForProject(session.project))
            sphere.firstMaterial?.diffuse.contents = color
            sphere.firstMaterial?.emission.contents = color
            sphere.firstMaterial?.emission.intensity = session.isActive ? 0.9 : 0.25
            let node = SCNNode(geometry: sphere)
            node.position = pos
            scene.rootNode.addChildNode(node)
        }

        var byProject: [String: [String]] = [:]
        for s in sessions { byProject[s.project, default: []].append(s.id) }
        for (_, ids) in byProject where ids.count > 1 {
            for i in 0..<(ids.count - 1) {
                guard let a = positions[ids[i]], let b = positions[ids[i + 1]] else { continue }
                scene.rootNode.addChildNode(edge(from: a, to: b))
            }
        }

        // Frame the camera from the ACTUAL spread of the computed layout — a fixed
        // distance assumes a compact graph and shows a black screen the moment
        // real data (mostly unconnected sessions) pushes nodes further apart.
        let maxExtent: CGFloat = positions.values
            .map { max(abs($0.x), abs($0.y), abs($0.z)) }
            .max() ?? 5
        let cameraDistance = maxExtent * 2.4 + 6

        let camera = SCNCamera()
        camera.zNear = 0.1
        camera.zFar = Double(cameraDistance * 4 + 50)
        let cameraNode = SCNNode()
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(x: 0, y: 0, z: cameraDistance)
        scene.rootNode.addChildNode(cameraNode)

        return scene
    }

    /// A Fibonacci-sphere seed — spreads N points evenly with no clumping, then
    /// `relax` pulls related sessions together from there.
    private static func initialShell(for sessions: [SessionAgg]) -> [String: SCNVector3] {
        var positions: [String: SCNVector3] = [:]
        let n = max(sessions.count, 1)
        let r: CGFloat = 4.5
        for (i, s) in sessions.enumerated() {
            let phi = acos(1 - 2 * (Double(i) + 0.5) / Double(n))
            let theta = Double.pi * (1 + sqrt(5)) * Double(i)
            let x = CGFloat(sin(phi) * cos(theta)) * r
            let y = CGFloat(sin(phi) * sin(theta)) * r
            let z = CGFloat(cos(phi)) * r
            positions[s.id] = SCNVector3(x: x, y: y, z: z)
        }
        return positions
    }

    private static func relax(_ positions: inout [String: SCNVector3], sessions: [SessionAgg]) {
        let ids = sessions.map(\.id)
        guard ids.count > 1 else { return }

        var byProject: [String: [String]] = [:]
        for s in sessions { byProject[s.project, default: []].append(s.id) }

        for _ in 0..<120 {
            var fx = [String: CGFloat](), fy = [String: CGFloat](), fz = [String: CGFloat]()
            for id in ids { fx[id] = 0; fy[id] = 0; fz[id] = 0 }

            for i in 0..<ids.count {
                for j in (i + 1)..<ids.count {
                    let a = ids[i], b = ids[j]
                    guard let pa = positions[a], let pb = positions[b] else { continue }
                    var dx: CGFloat = pa.x - pb.x
                    var dy: CGFloat = pa.y - pb.y
                    var dz: CGFloat = pa.z - pb.z
                    var distSq: CGFloat = dx * dx + dy * dy + dz * dz
                    if distSq < 0.0001 {
                        dx = CGFloat.random(in: -0.1...0.1)
                        dy = CGFloat.random(in: -0.1...0.1)
                        dz = CGFloat.random(in: -0.1...0.1)
                        distSq = 0.01
                    }
                    let dist: CGFloat = sqrt(distSq)
                    let repulse: CGFloat = 6.0 / distSq
                    let scale: CGFloat = repulse / dist
                    let ox: CGFloat = dx * scale
                    let oy: CGFloat = dy * scale
                    let oz: CGFloat = dz * scale
                    fx[a]! += ox; fy[a]! += oy; fz[a]! += oz
                    fx[b]! -= ox; fy[b]! -= oy; fz[b]! -= oz
                }
            }

            for (_, group) in byProject where group.count > 1 {
                for i in 0..<(group.count - 1) {
                    let a = group[i], b = group[i + 1]
                    guard let pa = positions[a], let pb = positions[b] else { continue }
                    let attract: CGFloat = 0.06
                    let dx: CGFloat = (pb.x - pa.x) * attract
                    let dy: CGFloat = (pb.y - pa.y) * attract
                    let dz: CGFloat = (pb.z - pa.z) * attract
                    fx[a]! += dx; fy[a]! += dy; fz[a]! += dz
                    fx[b]! -= dx; fy[b]! -= dy; fz[b]! -= dz
                }
            }

            // A weak spring back to the origin — without this, sessions that share
            // no project with anything else (the common case) have only repulsion
            // acting on them and drift outward without bound.
            let centering: CGFloat = 0.35
            for id in ids {
                guard let p = positions[id] else { continue }
                fx[id]! -= p.x * centering
                fy[id]! -= p.y * centering
                fz[id]! -= p.z * centering
            }

            for id in ids {
                guard let p = positions[id] else { continue }
                let nx: CGFloat = p.x + fx[id]! * 0.02
                let ny: CGFloat = p.y + fy[id]! * 0.02
                let nz: CGFloat = p.z + fz[id]! * 0.02
                positions[id] = SCNVector3(x: nx, y: ny, z: nz)
            }
        }
    }

    /// SCNCylinder's axis is Y by default — rotate it onto the a→b direction
    /// with a plain cross-product axis-angle (no quaternion math needed).
    private static func edge(from a: SCNVector3, to b: SCNVector3) -> SCNNode {
        let dx: CGFloat = b.x - a.x
        let dy: CGFloat = b.y - a.y
        let dz: CGFloat = b.z - a.z
        let distance: CGFloat = max(sqrt(dx * dx + dy * dy + dz * dz), 0.001)

        let cylinder = SCNCylinder(radius: 0.015, height: distance)
        cylinder.firstMaterial?.diffuse.contents = NSColor(Theme.ink3).withAlphaComponent(0.5)
        cylinder.firstMaterial?.lightingModel = .constant

        let node = SCNNode(geometry: cylinder)
        node.position = SCNVector3(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2, z: (a.z + b.z) / 2)

        let dirX: CGFloat = dx / distance
        let dirY: CGFloat = dy / distance
        let dirZ: CGFloat = dz / distance
        let dot: CGFloat = max(-1, min(1, dirY)) // up·dir where up = (0,1,0)
        let angle: CGFloat = acos(dot)
        if angle > 0.0001 {
            // cross(up, dir) where up = (0,1,0): (up.y*dir.z - up.z*dir.y, up.z*dir.x - up.x*dir.z, up.x*dir.y - up.y*dir.x)
            let axisX: CGFloat = dirZ
            let axisY: CGFloat = 0
            let axisZ: CGFloat = -dirX
            let len: CGFloat = sqrt(axisX * axisX + axisY * axisY + axisZ * axisZ)
            if len > 0.0001 {
                node.rotation = SCNVector4(x: axisX / len, y: axisY / len, z: axisZ / len, w: angle)
            } else {
                node.rotation = SCNVector4(x: 1, y: 0, z: 0, w: CGFloat.pi)
            }
        }
        return node
    }
}
