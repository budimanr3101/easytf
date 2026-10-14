import SwiftUI

struct TagsEditor: View {
    @ObservedObject var model: Workspace
    let path: [String]
    @State private var key = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ForEach(model.document.at(path).object.keys.sorted(), id: \.self) { name in
                HStack { Text(name).font(.system(.callout, design: .monospaced)).frame(width: 130, alignment: .leading); TextField("Value", text: model.text(path + [name])).textFieldStyle(.roundedBorder); Button { model.remove(path: path + [name]) } label: { Image(systemName: "minus.circle") }.buttonStyle(.borderless).help("Remove tag") }
            }
            HStack { TextField("New tag key", text: $key).textFieldStyle(.roundedBorder); Button("Add tag") { model.set(.string(""), path: path + [key]); key = "" }.disabled(key.isEmpty || model.document.at(path).object[key] != nil) }
        }
    }
}
struct ResourceIDField: View {
    @ObservedObject var model: Workspace
    let title: String
    let kind: String
    let path: [String]
    var body: some View {
        HStack { TextField(title, text: model.text(path)); Button("Browse AWS…") { model.browse(kind: kind, path: path) }.disabled(model.busy) }
    }
}
struct StringListEditor: View {
    @ObservedObject var model: Workspace
    let path: [String]
    @State private var newValue = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(model.document.at(path).array.map(\.text), id: \.self) { value in HStack { Text(value).font(.system(.caption, design: .monospaced)); Spacer(); Button { model.set(.array(model.document.at(path).array.filter { $0.text != value }), path: path) } label: { Image(systemName: "minus.circle") }.buttonStyle(.borderless) } }
            HStack { TextField("Resource ID", text: $newValue).textFieldStyle(.roundedBorder); Button("Add") { model.set(.array(model.document.at(path).array + [.string(newValue)]), path: path); newValue = "" }.disabled(newValue.isEmpty || model.document.at(path).array.contains(.string(newValue))) }
        }
    }
}
struct InstanceEditor: View {
    @ObservedObject var model: Workspace
    let key: String
    @State private var section = "Basics"
    @State private var remove = false
    var path: [String] { model.valuesPath + ["instances", key] }
    var config: [String] { path + ["configuration"] }
    var rootSize: Binding<Int> {
        Binding(get: {
            if let root = model.document.at(config + ["root_block_device"]).array.first, case .number(let size) = root["volume_size"] { return Int(size) }
            return model.integer(path + ["root_volume_gib"], fallback: 20).wrappedValue
        }, set: { size in
            model.set(.number(Double(size)), path: path + ["root_volume_gib"])
            var roots = model.document.at(config + ["root_block_device"]).array
            if !roots.isEmpty { roots[0]["volume_size"] = .number(Double(size)); model.set(.array(roots), path: config + ["root_block_device"]) }
        })
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack { ResourceLabel(title: key, symbol: "server.rack", color: Theme.ec2).font(.title2).fontWeight(.semibold); Spacer(); Button { remove = true } label: { Image(systemName: "trash") }.help("Remove EC2 resource") }.padding(20).background(Theme.ec2.opacity(0.06))
            Picker("Section", selection: $section) { ForEach(["Basics", "Networking", "Access", "Storage", "Tags", "Advanced"], id: \.self) { Text($0).tag($0) } }.pickerStyle(.segmented).padding(.horizontal, 20).padding(.bottom, 12)
            Form {
                if section == "Basics" {
                    Section("Required settings") {
                        TextField("AWS instance name", text: model.text(path + ["name"]))
                        ResourceIDField(model: model, title: "AMI ID", kind: "images", path: path + ["ami_id"])
                        TextField("Instance type", text: model.text(path + ["instance_type"]))
                        Text("Choose an AMI and instance type compatible with the same CPU architecture.").font(.caption).foregroundStyle(.secondary)
                    }
                } else if section == "Networking" {
                    Section("Existing subnet") { ResourceIDField(model: model, title: "Subnet ID", kind: "subnets", path: path + ["subnet_id"]); Toggle("Associate a public IP", isOn: model.bool(path + ["associate_public_ip"])) }
                    Section("Security groups managed in this environment") {
                        if model.keys("security_groups").isEmpty { Text("Add a security group from the sidebar, or select existing groups below.").foregroundStyle(.secondary) }
                        ForEach(model.keys("security_groups"), id: \.self) { sg in
                            Toggle(sg, isOn: Binding(get: { model.document.at(path + ["security_group_keys"]).array.contains(.string(sg)) }, set: { selected in let old = model.document.at(path + ["security_group_keys"]).array.filter { $0 != .string(sg) }; model.set(.array(selected ? old + [.string(sg)] : old), path: path + ["security_group_keys"]) })).toggleStyle(.checkbox)
                        }
                    }
                    Section("Existing security groups") {
                        StringListEditor(model: model, path: path + ["existing_security_group_ids"])
                        Button("Browse AWS security groups…") { model.browse(kind: "security-groups", path: path + ["existing_security_group_ids"], multiple: true) }.disabled(model.document.at(path + ["subnet_id"]).text.isEmpty)
                        Text("AWS browsing filters groups to the selected subnet's VPC. Select at least one existing or managed group.").font(.caption).foregroundStyle(.secondary)
                    }
                } else if section == "Access" {
                    Section("Optional · SSH and IAM") {
                        TextField("Existing key pair name", text: model.text(config + ["key_name"], optional: true))
                        TextField("Existing IAM instance profile", text: model.text(config + ["iam_instance_profile"], optional: true))
                        TextField("Existing IAM role name", text: model.text(config + ["instance_role"], optional: true))
                        Text("Choose either an instance profile or a role. A role name creates a managed instance profile referencing that existing role.").font(.caption).foregroundStyle(.secondary)
                    }
                    Section("Optional · Instance protection") { Toggle("Detailed monitoring", isOn: model.bool(config + ["monitoring"])); Toggle("Prevent API termination", isOn: model.bool(config + ["disable_api_termination"])) }
                } else if section == "Storage" {
                    Section("Root volume") { Stepper("Size: \(rootSize.wrappedValue) GiB", value: rootSize, in: 1...16384); Text("Additional root volume settings can be edited under Advanced.").font(.caption).foregroundStyle(.secondary) }
                    Section("Optional · Additional EBS volumes") { EBSListEditor(model: model, path: config + ["ebs_block_device"]) }
                } else if section == "Tags" {
                    Section("Resource tag overrides") { TagsEditor(model: model, path: path + ["tags"]); Text("Environment tags are inherited. Only add keys that are specific to this resource or override a default.").font(.caption).foregroundStyle(.secondary) }
                } else {
                    Section("Optional · Complete EC2 configuration") { ConfigurationEditor(model: model, path: config) }
                }
            }.formStyle(.grouped)
        }.confirmationDialog("Remove EC2 resource '\(key)'?", isPresented: $remove, titleVisibility: .visible) { Button("Remove resource", role: .destructive) { model.delete(kind: "instances", key: key) } } message: { Text("This changes the configuration only. If the instance was previously deployed, a later Terraform plan may propose destroying it.") }
    }
}
struct SecurityGroupEditor: View {
    @ObservedObject var model: Workspace
    let key: String
    @State private var remove = false
    var path: [String] { model.valuesPath + ["security_groups", key] }
    var body: some View {
        Form {
            Section { HStack { ResourceLabel(title: key, symbol: "checkmark.shield", color: Theme.securityGroup).font(.title2).fontWeight(.semibold); Spacer(); Button { remove = true } label: { Image(systemName: "trash") } } }
            Section("Security group") { TextField("AWS name", text: model.text(path + ["name"])); TextField("Description", text: model.text(path + ["description"])); ResourceIDField(model: model, title: "Existing subnet · VPC lookup", kind: "subnets", path: path + ["subnet_id"]) }
            Section("Ingress · inbound rules") { RulesEditor(model: model, path: path + ["ingress"]) }
            Section("Egress · outbound rules") { RulesEditor(model: model, path: path + ["egress"]) }
            Section("Resource tag overrides") { TagsEditor(model: model, path: path + ["tags"]) }
        }.formStyle(.grouped).confirmationDialog("Remove security group '\(key)'?", isPresented: $remove, titleVisibility: .visible) { Button("Remove resource", role: .destructive) { model.delete(kind: "security_groups", key: key) } } message: { Text("Groups referenced by EC2 instances or load balancers must be unlinked first.") }
    }
}
struct RulesEditor: View {
    @ObservedObject var model: Workspace
    let path: [String]
    @State private var newKey = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(model.document.at(path).object.keys.sorted(), id: \.self) { key in
                VStack(alignment: .leading, spacing: 9) {
                    HStack { Text(key).fontWeight(.medium); Spacer(); Button { model.remove(path: path + [key]) } label: { Image(systemName: "minus.circle") }.buttonStyle(.borderless) }
                    HStack(spacing: 8) {
                        Picker("Protocol", selection: Binding(get: { model.document.at(path + [key, "protocol"]).text }, set: { protocolValue in model.set(.string(protocolValue), path: path + [key, "protocol"]); if protocolValue == "-1" { model.set(.null, path: path + [key, "from_port"]); model.set(.null, path: path + [key, "to_port"]) } else if model.document.at(path + [key, "from_port"]) == .null { model.set(.number(443), path: path + [key, "from_port"]); model.set(.number(443), path: path + [key, "to_port"]) } })) { Text("TCP").tag("tcp"); Text("UDP").tag("udp"); Text("All traffic").tag("-1") }.labelsHidden().frame(width: 100)
                        if model.document.at(path + [key, "protocol"]).text != "-1" {
                            TextField("From", value: model.integer(path + [key, "from_port"]), format: .number.grouping(.never)).textFieldStyle(.roundedBorder).frame(width: 55).help("From port")
                            Text("–").foregroundStyle(.secondary)
                            TextField("To", value: model.integer(path + [key, "to_port"]), format: .number.grouping(.never)).textFieldStyle(.roundedBorder).frame(width: 55).help("To port")
                        }
                        TextField("IPv4 CIDR", text: model.text(path + [key, "cidr_ipv4"])).textFieldStyle(.roundedBorder).help("IPv4 CIDR")
                    }
                    TextField("Description", text: model.text(path + [key, "description"]))
                }
                Divider()
            }
            HStack { TextField("Rule key, e.g. https", text: $newKey).textFieldStyle(.roundedBorder); Button("Add rule") { model.set(.object(["protocol": .string("tcp"), "from_port": .number(443), "to_port": .number(443), "cidr_ipv4": .string("10.0.0.0/16"), "description": .string("Allow application traffic")]), path: path + [newKey]); newKey = "" }.disabled(newKey.range(of: "^[a-zA-Z][a-zA-Z0-9_-]*$", options: .regularExpression) == nil || model.document.at(path).object[newKey] != nil) }
        }
    }
}
struct EBSListEditor: View {
    @ObservedObject var model: Workspace
    let path: [String]
    func binding(_ index: Int, _ key: String) -> Binding<String> {
        Binding(get: { let a = model.document.at(path).array; return index < a.count ? a[index][key].text : "" }, set: { value in var a = model.document.at(path).array; guard index < a.count else { return }; a[index][key] = .string(value); model.set(.array(a), path: path) })
    }
    func size(_ index: Int) -> Binding<Int> {
        Binding(get: { let a = model.document.at(path).array; return index < a.count ? Int(a[index]["volume_size"].number) : 0 }, set: { value in var a = model.document.at(path).array; guard index < a.count else { return }; a[index]["volume_size"] = .number(Double(value)); model.set(.array(a), path: path) })
    }
    func flag(_ index: Int, _ key: String) -> Binding<Bool> {
        Binding(get: { let a = model.document.at(path).array; return index < a.count ? a[index][key].bool : false }, set: { value in var a = model.document.at(path).array; guard index < a.count else { return }; a[index][key] = .bool(value); model.set(.array(a), path: path) })
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(model.document.at(path).array.indices, id: \.self) { index in
                VStack(alignment: .leading, spacing: 8) {
                    HStack { Text("Volume \(index + 1)").fontWeight(.medium); Spacer(); Button { var a = model.document.at(path).array; a.remove(at: index); model.set(.array(a), path: path) } label: { Image(systemName: "minus.circle") }.buttonStyle(.borderless) }
                    TextField("Device, e.g. /dev/sdf", text: binding(index, "device_name"))
                    Picker("Type", selection: binding(index, "volume_type")) { ForEach(["gp3", "gp2", "io1", "io2", "st1", "sc1", "standard"], id: \.self) { Text($0).tag($0) } }
                    TextField("Size · GiB", value: size(index), format: .number)
                    HStack { Toggle("Encrypted", isOn: flag(index, "encrypted")).toggleStyle(.checkbox); Toggle("Delete with instance", isOn: flag(index, "delete_on_termination")).toggleStyle(.checkbox) }
                    Text("Additional settings and per-volume tags are preserved and available in Advanced.").font(.caption).foregroundStyle(.secondary)
                }; Divider()
            }
            Button("Add EBS volume") { model.set(.array(model.document.at(path).array + [.object(["device_name": .string(""), "volume_size": .number(20), "volume_type": .string("gp3"), "encrypted": .bool(true), "delete_on_termination": .bool(true)])]), path: path) }
        }
    }
}
struct ConfigurationEditor: View {
    @ObservedObject var model: Workspace
    let path: [String]
    @State private var text = ""
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Edit the optional configuration object. The Rust engine validates the same EC2 schema used by the CLI, including metadata, placement, user data, ENIs, launch templates, root disk options, and Spot settings.").font(.callout).foregroundStyle(.secondary)
            TextEditor(text: $text).font(.system(.body, design: .monospaced)).frame(minHeight: 300).border(Color.secondary.opacity(0.25))
            Button("Save optional settings") {
                do { let value = try JSONValue.parse(text); guard case .object = value else { throw EngineError(message: "Configuration must be a JSON object.") }; model.set(value, path: path); error = nil }
                catch { self.error = "Invalid JSON object. Check commas, quotes, and brackets." }
            }.buttonStyle(.bordered)
            if text != model.document.at(path).pretty() { Text("Click Save optional settings before reviewing Terraform.").font(.caption).foregroundStyle(.orange) }
            if let error = error { Text(error).font(.caption).foregroundStyle(.orange) }
        }.onAppear { text = model.document.at(path).pretty() }
    }
}
