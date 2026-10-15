import XCTest
import Darwin
@testable import EasyTFDesktop
final class CatalogTests: XCTestCase {
    func testNestedArrayEditsAndStaleIndicesDoNotReplaceCollections() throws {
        var value = try JSONValue.parse(#"{"vpc_config":[{"subnet_ids":["subnet-a"]}]}"#)
        value.set(.string("subnet-b"), at: ["vpc_config","0","subnet_ids","0"])
        XCTAssertEqual(value.at(["vpc_config","0","subnet_ids","0"]).text,"subnet-b")
        value.set(.string("stale"), at: ["vpc_config","8"])
        value.remove(at: ["vpc_config","8"])
        XCTAssertEqual(value["vpc_config"].array.count,1)
        XCTAssertEqual(try JSONValue.parse(value.pretty()),value)
    }
    func testCatalogFormsAndNestedReferenceRemoval() async throws {
        guard ProcessInfo.processInfo.environment["EASYTF_DESKTOP_ENGINE"] != nil else { throw XCTSkip("Rust bridge path required") }
        let response = try Engine.call(.object(["operation": .string("catalog")]), cancellation: EngineCancellation())
        let definitions = response["resources"].object.map { CatalogDefinition(id: $0.key,value: $0.value) }
        XCTAssertEqual(definitions.count,43)
        XCTAssertTrue(definitions.contains { $0.id == "aws_rds_cluster_instance" })
        XCTAssertTrue(definitions.contains { $0.id == "aws_eks_fargate_profile" })
        for kind in ["aws_db_instance","aws_rds_cluster"] {
            let definition = try XCTUnwrap(definitions.first { $0.id == kind })
            XCTAssertTrue(definition.configuration(key: "db")["manage_master_user_password"].bool)
            XCTAssertNil(definition.schema["properties"].object["password"])
            XCTAssertNil(definition.schema["properties"].object["master_password"])
        }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let previous = ProcessInfo.processInfo.environment["EASYTF_DESKTOP_STATE_DIR"]
        setenv("EASYTF_DESKTOP_STATE_DIR",folder.path,1)
        defer { if let previous = previous { setenv("EASYTF_DESKTOP_STATE_DIR",previous,1) } else { unsetenv("EASYTF_DESKTOP_STATE_DIR") }; try? FileManager.default.removeItem(at: folder) }
        await MainActor.run {
            let model = Workspace(loadCatalog: false); model.catalog = definitions
            model.create(name: "catalog",root: folder.appendingPathComponent("infra"),environments: ["dev"],region: "ap-southeast-3",profile: "",bucket: "",backendRegion: "ap-southeast-3")
            model.addCatalog(definitions.first { $0.id == "aws_vpc" }!,key: "vpc")
            model.addCatalog(definitions.first { $0.id == "aws_eks_cluster" }!,key: "cluster")
            let base = model.valuesPath + ["managed_resources","cluster"]
            model.set(.array([.object([:]),.object([:])]),path: base + ["configuration","vpc_config"])
            let ref: JSONValue = .array([.object(["resource_key": .string("vpc"),"output": .string("id")])])
            model.set(ref,path: base + ["links","/vpc_config/0/subnet_ids"])
            model.set(ref,path: base + ["links","/vpc_config/1/subnet_ids"])
            model.delete(kind: "managed_resources",key: "vpc")
            XCTAssertTrue(model.keys("managed_resources").contains("vpc"))
            model.removeCatalogValue(resourceKey: "cluster",path: base + ["configuration","vpc_config","0"],relative: ["vpc_config","0"])
            XCTAssertEqual(model.document.at(base + ["links","/vpc_config/0/subnet_ids"]),ref)
            XCTAssertNil(model.document.at(base + ["links"]).object["/vpc_config/1/subnet_ids"])
            model.removeCatalogValue(resourceKey: "cluster",path: base + ["configuration","vpc_config"],relative: ["vpc_config"])
            XCTAssertEqual(model.document.at(base + ["links"]).object.count,0)
            model.delete(kind: "managed_resources",key: "vpc")
            XCTAssertFalse(model.keys("managed_resources").contains("vpc"))
        }
    }
}
