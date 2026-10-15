import SwiftUI
import AppKit

struct NewProjectView: View {
    @ObservedObject var model: Workspace
    @Environment(\.dismiss) private var dismiss
    @State private var name = "my-infra"
    @State private var parent = FileManager.default.homeDirectoryForCurrentUser
    @State private var environments: Set<String> = ["dev"]
    @State private var region = "ap-southeast-3"
    @State private var profile = ""
    @State private var s3 = false
    @State private var bucket = ""
    @State private var backendRegion = "ap-southeast-3"
    var valid: Bool { name.range(of: "^[a-zA-Z][a-zA-Z0-9_-]*$", options: .regularExpression) != nil && !environments.isEmpty && !region.isEmpty && (!s3 || (!bucket.isEmpty && !backendRegion.isEmpty)) }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New Terraform project").font(.title2).fontWeight(.semibold)
            Form {
                Section("1 · Project folder") {
                    TextField("Project name", text: $name)
                    HStack { Text(parent.path).font(.caption).lineLimit(1).truncationMode(.middle); Spacer(); Button("Choose location…") { let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true; if panel.runModal() == .OK, let url = panel.url { parent = url } } }
                    Text("Creates \(name) inside this folder. Existing folders must be empty.").font(.caption).foregroundStyle(.secondary)
                }
                Section("2 · Environments & AWS") {
                    HStack { ForEach(["dev", "staging", "prod"], id: \.self) { env in Toggle(env, isOn: Binding(get: { environments.contains(env) }, set: { if $0 { environments.insert(env) } else { environments.remove(env) } })).toggleStyle(.checkbox) } }
                    TextField("AWS region", text: $region)
                    TextField("AWS profile · optional", text: $profile)
                    Text("Use an existing AWS CLI profile. Leave blank for the default credential chain.").font(.caption).foregroundStyle(.secondary)
                }
                Section("3 · Terraform state") {
                    Toggle("Use an existing S3 state bucket", isOn: $s3)
                    if s3 { TextField("Bucket name", text: $bucket); TextField("Backend region", text: $backendRegion); Text("Each environment gets its own state key. The bucket must already exist.").font(.caption).foregroundStyle(.secondary) }
                    else { Text("Local state, separate for each environment.").font(.caption).foregroundStyle(.secondary) }
                }
            }.formStyle(.grouped)
            HStack { Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction); Spacer(); Button("Create workspace") { model.create(name: name, root: parent.appendingPathComponent(name), environments: environments.sorted(), region: region, profile: profile, bucket: s3 ? bucket : "", backendRegion: backendRegion) }.buttonStyle(.borderedProminent).disabled(!valid || FileManager.default.fileExists(atPath: parent.appendingPathComponent(name).path)).keyboardShortcut(.defaultAction) }
            if FileManager.default.fileExists(atPath: parent.appendingPathComponent(name).path) { Text("That folder already exists. Open it as a project or choose a different name.").font(.caption).foregroundStyle(.orange) }
        }.padding(24).frame(width: 600, height: 620)
    }
}
struct AddResourceView: View {
    @ObservedObject var model: Workspace
    @State private var key = ""
    var kind: String { model.addKind ?? "instances" }
    var collection: String { ["application", "network"].contains(kind) ? "load_balancers" : kind }
    var valid: Bool { key.range(of: "^[a-zA-Z][a-zA-Z0-9_-]*$", options: .regularExpression) != nil && !model.keys(collection).contains(key) }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(kind == "instances" ? "Add EC2 instance" : (kind == "security_groups" ? "Add security group" : (kind == "application" ? "Add Application Load Balancer" : "Add Network Load Balancer"))).font(.title2)
            Text("Choose a stable Terraform resource key. Configure its AWS name in the editor.").foregroundStyle(.secondary)
            TextField("Resource key, e.g. web_primary", text: $key).textFieldStyle(.roundedBorder)
            if model.keys(collection).contains(key) { Text("That resource key already exists.").foregroundStyle(.orange) }
            HStack { Button("Cancel") { model.addKind = nil }.keyboardShortcut(.cancelAction); Spacer(); Button("Add resource") { model.add(kind: kind, key: key) }.buttonStyle(.borderedProminent).disabled(!valid).keyboardShortcut(.defaultAction) }
        }.padding(24).frame(width: 440)
    }
}
struct EnvironmentEditor: View {
    @ObservedObject var model: Workspace
    var path: [String] { ["environments", model.environment] }
    var body: some View {
        Form {
            Section { Text("Environment settings").font(.title2).fontWeight(.semibold); Text("Shared values for all resources in \(model.environment).").foregroundStyle(.secondary) }
            Section("AWS context") { TextField("Region", text: model.text(model.valuesPath + ["aws_region"])); TextField("Profile · optional", text: model.text(model.valuesPath + ["aws_profile"], optional: true)); Text("Existing AWS CLI profiles are used for resource browsing and by Terraform.").font(.caption).foregroundStyle(.secondary) }
            Section("State backend") {
                let backend = model.document.at(path + ["backend"])
                Text(backend["type"].text == "s3" ? "S3 · \(backend["bucket"].text)" : "Local state")
                if backend["type"].text == "s3" { Text("Key: " + backend["key"].text).font(.caption); Text("Region: " + backend["region"].text).font(.caption) }
                Text("The backend was selected when this project was created. Existing backends require an explicit Terraform migration.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Default tags · all managed resources") { TagsEditor(model: model, path: model.valuesPath + ["tags"]) }
            Section("Next step") { Text("Add EC2, security groups, or an ALB/NLB from the sidebar. Review Terraform before writing files.").foregroundStyle(.secondary); Button("Add EC2 instance…") { model.addKind = "instances" } }
        }.formStyle(.grouped)
    }
}
struct ReviewView: View {
    @ObservedObject var model: Workspace
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack { VStack(alignment: .leading, spacing: 5) { Text("Review Terraform files").font(.title2).fontWeight(.semibold); Text("Generation preview · This is not a Terraform deployment plan.").font(.caption).foregroundStyle(.secondary) }; Spacer(); Button("Generate files") { model.generate() }.buttonStyle(.borderedProminent).disabled(model.preview == .null || model.busy) }
            if model.preview == .null {
                Text("Review your current configuration to validate inputs and preview file changes.").foregroundStyle(.secondary)
                Button("Validate & preview") { model.review() }
                Spacer()
            } else {
                HSplitView {
                    List(selection: $model.previewFile) { ForEach(model.preview["changes"].array, id: \.self) { file in HStack { Text(file["action"].text).font(.caption).foregroundStyle(file["action"].text == "unchanged" ? Color.secondary : Color.accentColor); Text(file["path"].text).font(.caption) }.tag(file["path"].text) } }.frame(minWidth: 200, idealWidth: 240, maxWidth: 290)
                    ScrollView([.vertical, .horizontal]) { Text(model.preview["files"][model.previewFile].text).font(.system(.body, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(12) }.background(Color(nsColor: .textBackgroundColor))
                }
                Text("Output: " + (model.root?.path ?? "")).font(.caption).textSelection(.enabled)
                Text("Inputs go to terraform.tfvars. Generated modules use references to express resource dependencies. Manual changes are protected by the Rust engine.").font(.caption).foregroundStyle(.secondary)
            }
        }.padding(20)
    }
}
struct DiscoveryView: View {
    @ObservedObject var model: Workspace
    @State private var search = ""
    @State private var selected: Set<String> = []
    var items: [JSONValue] { model.discoveryItems.filter { search.isEmpty || $0["label"].text.localizedCaseInsensitiveContains(search) || $0["id"].text.localizedCaseInsensitiveContains(search) } }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(model.discoveryKind == "subnets" ? "Choose existing subnet" : (model.discoveryKind == "images" ? "Choose AMI" : "Choose existing security groups")).font(.title2)
            Text("\(model.values["aws_region"].text) · \(model.values["aws_profile"].text.isEmpty ? "Default credential chain" : model.values["aws_profile"].text)").font(.caption).foregroundStyle(.secondary)
            TextField("Search name or resource ID", text: $search).textFieldStyle(.roundedBorder)
            if model.busy { ProgressView("Reading AWS resources…").frame(maxWidth: .infinity, maxHeight: .infinity) }
            else if let error = model.discoveryError { Text(error).foregroundStyle(.orange).textSelection(.enabled).frame(maxHeight: .infinity) }
            else if items.isEmpty { Text("No matching resources found. You can enter an ID directly in the form.").foregroundStyle(.secondary).frame(maxHeight: .infinity) }
            else {
                List(items, id: \.self) { item in
                    Button { let id = item["id"].text; if model.discoveryMultiple { if selected.contains(id) { selected.remove(id) } else { selected.insert(id) } } else { selected = [id] } } label: {
                        HStack { Image(systemName: selected.contains(item["id"].text) ? "checkmark.circle.fill" : "circle"); VStack(alignment: .leading) { Text(item["label"].text); Text(item["id"].text).font(.caption).foregroundStyle(.secondary) }; Spacer() }
                    }.buttonStyle(.plain)
                }
            }
            if model.discoveryKind == "images" { Text("AMI browser shows Amazon Linux 2023 candidates. Enter custom AMI IDs directly.").font(.caption).foregroundStyle(.secondary) }
            HStack { Button("Cancel") { model.cancel(); model.discoveryKind = nil }.keyboardShortcut(.cancelAction); Spacer(); Button("Use selection") { model.set(model.discoveryMultiple ? .array(selected.sorted().map(JSONValue.string)) : .string(selected.first ?? ""), path: model.discoveryPath); model.discoveryKind = nil }.buttonStyle(.borderedProminent).disabled(selected.isEmpty || model.busy) }
        }.padding(24).frame(width: 600, height: 500).onAppear {
            let current = model.document.at(model.discoveryPath)
            selected = model.discoveryMultiple ? Set(current.array.map(\.text)) : (current.text.isEmpty ? [] : [current.text])
        }
    }
}
