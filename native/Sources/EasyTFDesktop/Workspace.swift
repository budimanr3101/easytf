import SwiftUI
import AppKit

@MainActor final class Workspace: ObservableObject {
    @Published var draftAvailable = FileManager.default.fileExists(atPath: DraftStore.file.path)
    @Published var document: JSONValue = .null
    @Published var baseline: JSONValue = .null
    @Published var root: URL?
    @Published var environment = "dev"
    @Published var selection: String? = "environment"
    @Published var busy = false
    @Published var canCancel = true
    @Published var error: String?
    @Published var status = ""
    @Published var dirty = false
    @Published var preview: JSONValue = .null
    @Published var previewFile = ""
    @Published var showNew = false
    @Published var addKind: String?
    @Published var discoveryKind: String?
    @Published var discoveryPath: [String] = []
    @Published var discoveryMultiple = false
    @Published var discoveryItems: [JSONValue] = []
    @Published var discoveryError: String?
    private var cancellation: EngineCancellation?
    init() {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--resume") { resumeDraft(); return }
        if let index = arguments.firstIndex(of: "--project"), index + 1 < arguments.count {
            open(URL(fileURLWithPath: arguments[index + 1]))
        }
    }
    var opened: Bool { root != nil }
    var environments: [String] { document["environments"].object.keys.sorted() }
    var valuesPath: [String] { ["environments", environment, "values"] }
    var values: JSONValue { document.at(valuesPath) }
    var title: String { document["name"].text }
    func keys(_ kind: String) -> [String] { values[kind].object.keys.sorted() }
    func saveDraft() {
        guard let root = root else { return }
        do {
            try DraftStore.save(.object(["project": document, "baseline": baseline, "root": .string(root.path), "environment": .string(environment), "dirty": .bool(dirty)]))
            draftAvailable = true
        } catch { status = "Draft could not be saved. Keep the app open until you generate files." }
    }
    func resumeDraft() {
        do {
            let draft = try DraftStore.load()
            guard case .object = draft["project"], !draft["root"].text.isEmpty else { throw EngineError(message: "The saved draft is incomplete.") }
            document = draft["project"]; baseline = draft["baseline"]; root = URL(fileURLWithPath: draft["root"].text)
            environment = environments.contains(draft["environment"].text) ? draft["environment"].text : environments.first ?? "dev"
            dirty = draft["dirty"].bool; selection = "environment"; preview = .null; status = "Workspace restored · Review before generating"
        } catch { self.error = "The workspace draft could not be restored. Open the project folder instead." }
    }
    func set(_ value: JSONValue, path: [String]) { document.set(value, at: path); dirty = true; preview = .null; status = "Draft saved locally · Review and generate to write Terraform"; saveDraft() }
    func remove(path: [String]) { document.remove(at: path); dirty = true; preview = .null; status = "Draft saved locally · Review and generate to write Terraform"; saveDraft() }
    func text(_ path: [String], optional: Bool = false) -> Binding<String> {
        Binding(get: { self.document.at(path).text }, set: { self.set(optional && $0.isEmpty ? .null : .string($0), path: path) })
    }
    func bool(_ path: [String]) -> Binding<Bool> { Binding(get: { self.document.at(path).bool }, set: { self.set(.bool($0), path: path) }) }
    func integer(_ path: [String], fallback: Int = 0) -> Binding<Int> {
        Binding(get: { if case .number(let n) = self.document.at(path) { return Int(n) }; return fallback }, set: { self.set(.number(Double($0)), path: path) })
    }
    func perform(_ request: JSONValue, finished: @escaping (JSONValue) -> Void, failed: ((String) -> Void)? = nil) {
        guard !busy else { return }
        let token = EngineCancellation(); cancellation = token; busy = true; canCancel = request["operation"].text != "publish"; error = nil
        Task {
            let result = await Task.detached { Result { try Engine.call(request, cancellation: token) } }.value
            busy = false; cancellation = nil
            switch result { case .success(let value): finished(value)
            case .failure(let problem): if let failed = failed { failed(problem.localizedDescription) } else { error = problem.localizedDescription } }
        }
    }
    func cancel() { if canCancel { cancellation?.cancel() } }
    func open(_ url: URL) {
        perform(.object(["operation": .string("open"), "root": .string(url.path)])) { value in
            self.document = value["project"]; self.baseline = value["baseline"]; self.root = url
            self.environment = self.environments.first ?? "dev"; self.selection = "environment"; self.preview = .null; self.dirty = false; self.status = "Project opened"; self.saveDraft()
        }
    }
    func chooseProject() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false
        panel.message = "Choose an EasyTF project folder containing .easytf.toml"; panel.prompt = "Open project"
        if panel.runModal() == .OK, let url = panel.url { open(url) }
    }
    func create(name: String, root: URL, environments: [String], region: String, profile: String, bucket: String, backendRegion: String) {
        var envs: [String: JSONValue] = [:]
        for environment in environments {
            let backend: JSONValue = bucket.isEmpty ? .object(["type": .string("local")]) : .object(["type": .string("s3"), "bucket": .string(bucket), "key": .string("\(name)/\(environment)/terraform.tfstate"), "region": .string(backendRegion), "use_lockfile": .bool(true)])
            envs[environment] = .environment(name: environment, project: name, region: region, profile: profile, backend: backend)
        }
        document = .object(["name": .string(name), "environments": .object(envs)])
        self.root = root; baseline = .null; environment = self.environments.first ?? "dev"; selection = "environment"; dirty = true; preview = .null; status = "Configure resources, then review Terraform"; showNew = false; saveDraft()
    }
    func request(_ operation: String) -> JSONValue { .object(["operation": .string(operation), "root": .string(root?.path ?? ""), "project": document, "baseline": baseline]) }
    func review() {
        perform(request("preview")) { value in self.preview = value; self.previewFile = value["changes"].array.first(where: { $0["action"].text != "unchanged" })?["path"].text ?? "environments/\(self.environment)/terraform.tfvars"; self.selection = "review"; self.status = "Review file changes before generating" }
    }
    func generate() {
        guard preview != .null else { return }
        perform(request("publish")) { value in self.baseline = value["baseline"]; self.dirty = false; self.preview = .null; self.status = "Terraform generated · No infrastructure deployed"; self.selection = "environment"; self.saveDraft() }
    }
    func add(kind: String, key: String) {
        var resource: JSONValue
        if kind == "instances" {
            resource = .object(["name": .string(key + "-" + environment), "ami_id": .string(""), "instance_type": .string("t3.micro"), "subnet_id": .string(""), "existing_security_group_ids": .array([]), "security_group_keys": .array([]), "root_volume_gib": .number(20), "associate_public_ip": .bool(false), "tags": .object([:]), "configuration": .object([:])])
        } else {
            resource = .object(["name": .string(key + "-" + environment), "description": .string("Managed by EasyTF"), "subnet_id": .string(""), "ingress": .object([:]), "egress": .object(["all_ipv4": .object(["protocol": .string("-1"), "from_port": .null, "to_port": .null, "cidr_ipv4": .string("0.0.0.0/0"), "description": .string("Allow outbound IPv4 traffic")])]), "tags": .object([:])])
        }
        set(resource, path: valuesPath + [kind, key]); selection = (kind == "instances" ? "ec2:" : "sg:") + key; addKind = nil
    }
    func delete(kind: String, key: String) {
        if kind == "security_groups" {
            let dependents = ["instances", "load_balancers"].flatMap { collection in values[collection].object.filter { $0.value["security_group_keys"].array.contains(.string(key)) }.map(\.key) }
            if !dependents.isEmpty { error = "This security group is used by: " + dependents.joined(separator: ", "); return }
        } else {
            let dependents = values["load_balancers"].object.filter { $0.value["target_groups"].object.values.contains { $0["instance_keys"].array.contains(.string(key)) } }.map(\.key)
            if !dependents.isEmpty { error = "This EC2 resource is used by load balancers: " + dependents.joined(separator: ", "); return }
        }
        remove(path: valuesPath + [kind, key]); selection = "environment"
    }
    func browse(kind: String, path: [String], multiple: Bool = false) {
        discoveryKind = kind; discoveryPath = path; discoveryMultiple = multiple; discoveryItems = []; discoveryError = nil
        var request: [String: JSONValue] = ["operation": .string("discover"), "kind": .string(kind), "region": values["aws_region"], "profile": values["aws_profile"]]
        if kind == "security-groups" { request["subnet"] = document.at(Array(path.dropLast()) + ["subnet_id"]) }
        perform(.object(request), finished: { self.discoveryItems = $0.array }, failed: { self.discoveryError = $0 })
    }
}
