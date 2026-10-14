import XCTest
@testable import EasyTFDesktop
final class DocumentTests: XCTestCase {
    func testNestedEditPreservesAdvancedConfiguration() throws {
        var document = try JSONValue.parse(#"{"environments":{"dev":{"values":{"instances":{"web":{"name":"old","configuration":{"instance_role":"AppRole","ebs_block_device":[{"device_name":"/dev/sdf","volume_size":50,"encrypted":true}]}}},"load_balancers":{"alb":{"target_groups":{"app":{"instance_keys":["web"]}}}}}}}}"#)
        let before = document.at(["environments", "dev", "values", "load_balancers"])
        document.set(.string("new"), at: ["environments", "dev", "values", "instances", "web", "name"])
        XCTAssertEqual(document.at(["environments", "dev", "values", "instances", "web", "configuration", "instance_role"]).text, "AppRole")
        XCTAssertEqual(document.at(["environments", "dev", "values", "load_balancers"]), before)
        XCTAssertEqual(try JSONValue.parse(document.pretty()), document)
    }
    func testEnvironmentAndTagRemoval() throws {
        var environment = JSONValue.environment(name: "prod", project: "service", region: "ap-southeast-3", profile: "", backend: .object(["type": .string("local")]))
        XCTAssertEqual(environment["values"]["aws_profile"], .null)
        XCTAssertEqual(environment["values"]["tags"]["env"].text, "prod")
        environment.remove(at: ["values", "tags", "env"])
        XCTAssertNil(environment["values"]["tags"].object["env"])
    }
    func testDraftIsOwnerOnlyAndRestoresBaseline() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("draft.json")
        let draft = try JSONValue.parse(#"{"root":"/tmp/infra","project":{"name":"infra"},"baseline":{"observed":{"terraform.tfvars":"digest"}}}"#)
        try DraftStore.save(draft, to: file)
        XCTAssertEqual(try DraftStore.load(from: file), draft)
        let permissions = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(permissions?.intValue, 0o600)
    }

}
