import AppKit
import CoreImage
import SceneKit

let source = URL(fileURLWithPath: CommandLine.arguments[1])
let output = URL(fileURLWithPath: CommandLine.arguments[2])
let scene = try SCNScene(url: source)
var parts: [SCNNode] = []
scene.rootNode.enumerateChildNodes { node, _ in if node.geometry != nil { parts.append(node) } }
func centreX(_ node: SCNNode) -> Float {
    let (lo, hi) = node.boundingBox
    return Float(node.convertPosition(SCNVector3((lo.x + hi.x) / 2, (lo.y + hi.y) / 2, (lo.z + hi.z) / 2), to: nil).x)
}
let sorted = parts.sorted { centreX($0) < centreX($1) }
var groups: [[SCNNode]] = []
for node in sorted {
    if let last = groups.last?.last, centreX(node) - centreX(last) < 0.25 { groups[groups.count - 1].append(node) } else { groups.append([node]) }
}
print("parts", parts.count, "people", groups.count, groups.map(\.count))

let renderer = SCNRenderer(device: MTLCreateSystemDefaultDevice(), options: nil)
renderer.scene = scene
scene.background.contents = NSColor.clear
let key = SCNNode(); key.light = SCNLight(); key.light!.type = .directional; key.light!.intensity = 900; key.light!.color = NSColor(red: 1, green: 0.82, blue: 0.62, alpha: 1)
key.eulerAngles = SCNVector3(-1.0, 0.25, 0); scene.rootNode.addChildNode(key)
let fill = SCNNode(); fill.light = SCNLight(); fill.light!.type = .ambient; fill.light!.intensity = 260; fill.light!.color = NSColor(red: 0.8, green: 0.7, blue: 0.6, alpha: 1); scene.rootNode.addChildNode(fill)
let camera = SCNNode(); camera.camera = SCNCamera(); camera.camera!.usesOrthographicProjection = true
scene.rootNode.addChildNode(camera); renderer.pointOfView = camera
let context = CIContext()
for (index, group) in groups.enumerated() {
    for node in parts { node.isHidden = !group.contains(node) }
    var lo = SIMD3<Float>(repeating: .infinity), hi = SIMD3<Float>(repeating: -.infinity)
    for node in group {
        let (a, b) = node.boundingBox
        for corner in [a, b] {
            let w = node.convertPosition(corner, to: nil)
            lo = simd_min(lo, [Float(w.x), Float(w.y), Float(w.z)]); hi = simd_max(hi, [Float(w.x), Float(w.y), Float(w.z)])
        }
    }
    let centre = (lo + hi) / 2, height = hi.y - lo.y
    camera.position = SCNVector3(centre.x, centre.y + 0.15, centre.z + 4)
    camera.look(at: SCNVector3(centre.x, centre.y, centre.z))
    camera.camera!.orthographicScale = Double(height * 0.55)
    let size = CGSize(width: 320, height: 440)
    let image = renderer.snapshot(atTime: 0, with: size, antialiasingMode: .multisampling4X)
    let ci = CIImage(cgImage: image.cgImage(forProposedRect: nil, context: nil, hints: nil)!)
    let blurred = ci.clampedToExtent().applyingGaussianBlur(sigma: 1.4).cropped(to: ci.extent)
    let cg = context.createCGImage(blurred, from: ci.extent)!
    let rep = NSBitmapImageRep(cgImage: cg)
    try rep.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("person-\(index).png"))
}
