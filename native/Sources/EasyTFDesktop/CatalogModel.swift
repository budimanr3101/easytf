import Foundation

struct CatalogDefinition: Identifiable {
    let id: String
    let value: JSONValue
    var title: String { value["title"].text }
    var category: String { value["category"].text }
    var schema: JSONValue { value["schema"] }
    var outputs: [String: JSONValue] { value["outputs"].object }
    func configuration(key: String) -> JSONValue {
        var result = value["defaults"]
        if case .object = result {} else { result = .object([:]) }
        let name = key.replacingOccurrences(of: "_", with: "-")
        for field in ["name", "identifier", "cluster_identifier", "node_group_name", "fargate_profile_name"] where schema["properties"].object[field] != nil {
            if field == "name" || field == "identifier" || field == "cluster_identifier" || field == "node_group_name" || field == "fargate_profile_name" { if !(id == "aws_rds_cluster_instance" && field == "cluster_identifier") { result[field] = .string(name) } }
        }
        if id == "aws_db_instance" || id == "aws_rds_cluster" { result["final_snapshot_identifier"] = .string(name + "-final") }
        if id == "aws_iam_role" {
            result["assume_role_policy"] = .string("{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Principal\":{\"Service\":\"ec2.amazonaws.com\"},\"Action\":\"sts:AssumeRole\"}]}")
        }
        return result
    }
}
extension JSONValue {
    static func blank(for schema: JSONValue) -> JSONValue {
        switch schema["kind"].text {
        case "object": return .object([:])
        case "list": return .array([])
        case "map": return .object([:])
        case "bool": return .bool(false)
        case "number": return .number(0)
        default: return .string("")
        }
    }
}
