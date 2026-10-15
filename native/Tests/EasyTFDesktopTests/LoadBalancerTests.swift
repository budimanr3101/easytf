import XCTest
import Darwin
@testable import EasyTFDesktop

final class LoadBalancerTests: XCTestCase {
    func testProtocolTransitionsKeepHealthSettingsAndClearInapplicableTLSFields() {
        var health = LoadBalancerConfiguration.targetGroup(network: true)["health_check"]
        health["interval"] = .number(60)
        health = LoadBalancerConfiguration.healthProtocol("HTTPS", health: health)
        XCTAssertEqual(health["path"].text, "/")
        XCTAssertEqual(health["matcher"].text, "200")
        XCTAssertEqual(health["interval"].number, 60)
        health = LoadBalancerConfiguration.healthProtocol("TCP", health: health)
        XCTAssertEqual(health["path"], .null)
        XCTAssertEqual(health["matcher"], .null)
        var listener = LoadBalancerConfiguration.listener(network: false, target: "web")
        listener["certificate_arn"] = .string("arn:fixture")
        listener["ssl_policy"] = .string("fixture")
        listener = LoadBalancerConfiguration.listenerProtocol("HTTP", listener: listener)
        XCTAssertEqual(listener["certificate_arn"], .null)
        XCTAssertEqual(listener["ssl_policy"], .null)
        XCTAssertEqual(listener["target_group_key"].text, "web")
    }
    func testDeletingLinkedResourcesRequiresUnlinkingFirst() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let previous = ProcessInfo.processInfo.environment["EASYTF_DESKTOP_STATE_DIR"]
        setenv("EASYTF_DESKTOP_STATE_DIR", folder.path, 1)
        defer { if let previous = previous { setenv("EASYTF_DESKTOP_STATE_DIR", previous, 1) } else { unsetenv("EASYTF_DESKTOP_STATE_DIR") }; try? FileManager.default.removeItem(at: folder) }
        await MainActor.run {
            let model = Workspace()
            model.create(name: "infra", root: folder.appendingPathComponent("infra"), environments: ["dev"], region: "ap-southeast-3", profile: "", bucket: "", backendRegion: "ap-southeast-3")
            model.add(kind: "instances", key: "web")
            model.add(kind: "security_groups", key: "shared")
            model.add(kind: "application", key: "frontend")
            let lb = model.valuesPath + ["load_balancers", "frontend"]
            model.set(.array([.string("web")]), path: lb + ["target_groups", "web", "instance_keys"])
            model.set(.array([.string("shared")]), path: lb + ["security_group_keys"])
            model.delete(kind: "instances", key: "web")
            XCTAssertTrue(model.keys("instances").contains("web"))
            XCTAssertNotNil(model.error)
            model.delete(kind: "security_groups", key: "shared")
            XCTAssertTrue(model.keys("security_groups").contains("shared"))
            model.removeTargetGroup(loadBalancer: "frontend", key: "web")
            XCTAssertNotNil(model.document.at(lb + ["target_groups"]).object["web"])
            model.remove(path: lb + ["listeners", "frontend"])
            model.removeTargetGroup(loadBalancer: "frontend", key: "web")
            XCTAssertNil(model.document.at(lb + ["target_groups"]).object["web"])
            model.delete(kind: "load_balancers", key: "frontend")
            XCTAssertFalse(model.keys("load_balancers").contains("frontend"))
            XCTAssertTrue(model.keys("instances").contains("web"))
            XCTAssertTrue(model.keys("security_groups").contains("shared"))
        }
    }
    func testNativeCreatedALBAndNLBGenerateThroughRustEngine() throws {
        guard ProcessInfo.processInfo.environment["EASYTF_DESKTOP_ENGINE"] != nil else { throw XCTSkip("Set EASYTF_DESKTOP_ENGINE to the Rust bridge binary for this integration test.") }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        var env = JSONValue.environment(name: "dev", project: "infra", region: "ap-southeast-3", profile: "", backend: .object(["type": .string("local")]))
        env["values"]["instances"]["web"] = .object(["name": .string("web-dev"), "ami_id": .string("ami-0123456789abcdef0"), "instance_type": .string("t3.micro"), "subnet_id": .string("subnet-0123456789abcdef0"), "existing_security_group_ids": .array([.string("sg-0123456789abcdef0")]), "root_volume_gib": .number(20)])
        var alb = LoadBalancerConfiguration.make(name: "frontend", network: false)
        alb["subnet_ids"] = .array([.string("subnet-0123456789abcdef0"), .string("subnet-11111111111111111")])
        alb["existing_security_group_ids"] = .array([.string("sg-0123456789abcdef0")])
        alb["target_groups"]["web"]["instance_keys"] = .array([.string("web")])
        alb["listeners"]["frontend"]["protocol"] = .string("HTTPS")
        alb["listeners"]["frontend"]["port"] = .number(443)
        alb["listeners"]["frontend"]["certificate_arn"] = .string("arn:aws:acm:ap-southeast-3:123456789012:certificate/11111111-1111-1111-1111-111111111111")
        var nlb = LoadBalancerConfiguration.make(name: "private", network: true)
        nlb["internal"] = .bool(true)
        nlb["subnet_ids"] = .array([.string("subnet-0123456789abcdef0")])
        nlb["target_groups"]["web"]["target_type"] = .string("ip")
        nlb["target_groups"]["web"]["instance_keys"] = .array([.string("web")])
        nlb["target_groups"]["web"]["existing_target_ids"] = .array([.string("10.0.1.5")])
        env["values"]["load_balancers"] = .object(["alb": alb, "nlb": nlb])
        let document: JSONValue = .object(["name": .string("infra"), "environments": .object(["dev": env])])
        let result = try Engine.call(.object(["operation": .string("publish"), "root": .string(root.path), "project": document]), cancellation: EngineCancellation())
        XCTAssertFalse(result["terraform_applied"].bool)
        let main = try String(contentsOf: root.appendingPathComponent("environments/dev/main.tf"))
        XCTAssertTrue(main.contains("module.instances[key].id"))
        XCTAssertTrue(main.contains("module.instances[key].private_ip"))
        let opened = try Engine.call(.object(["operation": .string("open"), "root": .string(root.path)]), cancellation: EngineCancellation())
        XCTAssertEqual(opened["project"]["environments"]["dev"]["values"]["load_balancers"]["alb"], alb)
        XCTAssertEqual(opened["project"]["environments"]["dev"]["values"]["load_balancers"]["nlb"], nlb)
        var broken = document
        broken["environments"]["dev"]["values"]["load_balancers"]["alb"]["listeners"]["frontend"]["target_group_key"] = .string("missing")
        XCTAssertThrowsError(try Engine.call(.object(["operation": .string("preview"), "root": .string(root.path), "project": broken]), cancellation: EngineCancellation()))
        var shortSubnets = document
        shortSubnets["environments"]["dev"]["values"]["load_balancers"]["alb"]["subnet_ids"] = .array([.string("subnet-0123456789abcdef0")])
        XCTAssertThrowsError(try Engine.call(.object(["operation": .string("preview"), "root": .string(root.path), "project": shortSubnets]), cancellation: EngineCancellation()))
    }
}
