import SwiftUI

struct LoadBalancerEditor: View {
    @ObservedObject var model: Workspace
    let key: String
    @State private var section = "Basics"
    @State private var remove = false
    var path: [String] { model.valuesPath + ["load_balancers", key] }
    var network: Bool { model.document.at(path + ["load_balancer_type"]).text == "network" }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                ResourceLabel(title: key, symbol: "network", color: Theme.loadBalancer).font(.title2).fontWeight(.semibold)
                Text(network ? "NLB" : "ALB").font(.caption).fontWeight(.semibold).foregroundStyle(Theme.loadBalancer)
                Spacer()
                Button { remove = true } label: { Image(systemName: "trash") }.help("Remove load balancer")
            }.padding(20).background(Theme.loadBalancer.opacity(0.07))
            Picker("Section", selection: $section) { ForEach(["Basics", "Networking", "Target groups", "Listeners", "Tags"], id: \.self) { Text($0).tag($0) } }.pickerStyle(.segmented).padding(.horizontal, 20).padding(.bottom, 12)
            if section == "Target groups" { TargetGroupsEditor(model: model, lbKey: key, path: path, network: network) }
            else if section == "Listeners" { ListenersEditor(model: model, path: path, network: network) }
            else {
                Form {
                    if section == "Basics" {
                        Section(network ? "Network Load Balancer" : "Application Load Balancer") {
                            TextField("AWS name", text: model.text(path + ["name"]))
                            Text("Letters, numbers, and hyphens; maximum 32 characters. The resource key remains stable.").font(.caption).foregroundStyle(.secondary)
                            Toggle("Internal load balancer", isOn: model.bool(path + ["internal"]))
                            Toggle("Enable deletion protection", isOn: model.bool(path + ["deletion_protection"]))
                        }
                        Section("Configure the traffic path") {
                            Label("1. Choose subnets and security groups", systemImage: "network")
                            Label("2. Configure target groups and select EC2 targets", systemImage: "server.rack")
                            Label("3. Add listeners that forward to a target group", systemImage: "arrow.triangle.branch")
                            Text("Target attachments reference EC2 IDs or private IPs automatically. No manual output IDs or blanket depends_on are needed.").font(.caption).foregroundStyle(.secondary)
                        }
                    } else if section == "Networking" {
                        Section("Existing subnets") {
                            StringListEditor(model: model, path: path + ["subnet_ids"])
                            Button("Browse AWS subnets…") { model.browse(kind: "subnets", path: path + ["subnet_ids"], multiple: true) }
                            Text(network ? "Choose at least one subnet. All selected subnets must be in the same VPC." : "Choose at least two subnets in different availability zones, in the same VPC.").font(.caption).foregroundStyle(.secondary)
                        }
                        Section(network ? "Optional · Managed security groups" : "Managed security groups") {
                            ProjectLinksEditor(model: model, path: path + ["security_group_keys"], collection: "security_groups")
                        }
                        Section("Existing security groups") {
                            StringListEditor(model: model, path: path + ["existing_security_group_ids"])
                            Button("Browse AWS security groups…") { model.browse(kind: "security-groups", path: path + ["existing_security_group_ids"], multiple: true, subnet: model.document.at(path + ["subnet_ids"]).array.first?.text) }.disabled(model.document.at(path + ["subnet_ids"]).array.isEmpty)
                            Text(network ? "Security groups are optional for NLB. AWS browsing filters to the first selected subnet's VPC." : "ALB requires at least one existing or managed security group. All groups must match the selected subnet VPC.").font(.caption).foregroundStyle(.secondary)
                        }
                    } else {
                        Section("Resource tag overrides") { TagsEditor(model: model, path: path + ["tags"]); Text("Environment tags are inherited by the load balancer, target groups, and attachments. Override individual keys here.").font(.caption).foregroundStyle(.secondary) }
                    }
                }.formStyle(.grouped)
            }
        }.confirmationDialog("Remove load balancer '\(key)'?", isPresented: $remove, titleVisibility: .visible) {
            Button("Remove load balancer", role: .destructive) { model.delete(kind: "load_balancers", key: key) }
        } message: { Text("Its listeners, target groups, and target attachments will also be removed from this configuration. A later Terraform plan may propose destroying previously deployed resources.") }
    }
}
struct ProjectLinksEditor: View {
    @ObservedObject var model: Workspace
    let path: [String]
    let collection: String
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            if model.keys(collection).isEmpty { Text(collection == "instances" ? "Add an EC2 resource in this environment first, or use existing targets below." : "No managed security groups in this environment. Add one from the sidebar or use existing groups.").font(.callout).foregroundStyle(.secondary) }
            ForEach(model.keys(collection), id: \.self) { key in
                Toggle(key, isOn: Binding(get: { model.document.at(path).array.contains(.string(key)) }, set: { selected in
                    let old = model.document.at(path).array.filter { $0 != .string(key) }
                    model.set(.array(selected ? old + [.string(key)] : old), path: path)
                })).toggleStyle(.checkbox)
            }
            let missing = model.document.at(path).array.map(\.text).filter { !model.keys(collection).contains($0) }
            ForEach(missing, id: \.self) { key in Text("Missing resource: " + key).font(.caption).foregroundStyle(.orange) }
        }
    }
}
struct NamedLBChildView: View {
    let title: String
    let existing: [String]
    let save: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var key = ""
    var valid: Bool { key.range(of: "^[a-zA-Z][a-zA-Z0-9_-]*$", options: .regularExpression) != nil && !existing.contains(key) }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title).font(.title2)
            Text("Choose a stable key. Configure its port, protocol, and references in the editor.").foregroundStyle(.secondary)
            TextField("Key, e.g. web", text: $key).textFieldStyle(.roundedBorder)
            if existing.contains(key) { Text("That key already exists.").font(.caption).foregroundStyle(.orange) }
            HStack { Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction); Spacer(); Button("Add") { save(key); dismiss() }.buttonStyle(.borderedProminent).disabled(!valid).keyboardShortcut(.defaultAction) }
        }.padding(24).frame(width: 440)
    }
}
struct TargetGroupsEditor: View {
    @ObservedObject var model: Workspace
    let lbKey: String
    let path: [String]
    let network: Bool
    @State private var selected = ""
    @State private var showAdd = false
    @State private var remove = false
    var keys: [String] { model.document.at(path + ["target_groups"]).object.keys.sorted() }
    var current: String { keys.contains(selected) ? selected : keys.first ?? "" }
    var groupPath: [String] { path + ["target_groups", current] }
    var healthPath: [String] { groupPath + ["health_check"] }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("Target group", selection: Binding(get: { current }, set: { selected = $0 })) { ForEach(keys, id: \.self) { Text($0).tag($0) } }
                Button("Add…") { showAdd = true }
                Button { remove = true } label: { Image(systemName: "minus.circle") }.disabled(current.isEmpty).help("Remove target group")
            }.padding(.horizontal, 20).padding(.vertical, 12)
            if current.isEmpty { Text("Add a target group to define where listener traffic is sent.").foregroundStyle(.secondary).padding(); Spacer() }
            else {
                Form {
                    Section("Backend traffic") {
                        Picker("Protocol", selection: model.text(groupPath + ["protocol"])) { ForEach(network ? ["TCP", "TLS", "UDP", "TCP_UDP"] : ["HTTP", "HTTPS"], id: \.self) { Text($0).tag($0) } }
                        TextField("Target port", value: model.integer(groupPath + ["port"]), format: .number.grouping(.never))
                        Picker("Target type", selection: model.text(groupPath + ["target_type"])) { Text("Instance ID").tag("instance"); Text("IPv4 address").tag("ip") }
                    }
                    Section("Project EC2 targets") {
                        ProjectLinksEditor(model: model, path: groupPath + ["instance_keys"], collection: "instances")
                        Text(model.document.at(groupPath + ["target_type"]).text == "ip" ? "Selected EC2 resources register using their private IP outputs." : "Selected EC2 resources register using their instance ID outputs.").font(.caption).foregroundStyle(.secondary)
                    }
                    Section("Existing targets") {
                        StringListEditor(model: model, path: groupPath + ["existing_target_ids"])
                        Text(model.document.at(groupPath + ["target_type"]).text == "ip" ? "Enter existing IPv4 addresses. Review existing entries if you change target type." : "Enter existing EC2 instance IDs (i-...). Existing instance targets are checked against the load balancer VPC by Terraform.").font(.caption).foregroundStyle(.secondary)
                    }
                    Section("Health check") {
                        Picker("Protocol", selection: Binding(get: { model.document.at(healthPath + ["protocol"]).text }, set: { value in model.set(LoadBalancerConfiguration.healthProtocol(value, health: model.document.at(healthPath)), path: healthPath) })) { ForEach(network ? ["TCP", "HTTP", "HTTPS"] : ["HTTP", "HTTPS"], id: \.self) { Text($0).tag($0) } }
                        TextField("Port · traffic-port or 1–65535", text: model.text(healthPath + ["port"]))
                        if model.document.at(healthPath + ["protocol"]).text != "TCP" {
                            TextField("Path", text: model.text(healthPath + ["path"]))
                            TextField("Success codes · optional", text: model.text(healthPath + ["matcher"], optional: true))
                        }
                        TextField("Interval · seconds", value: model.integer(healthPath + ["interval"]), format: .number.grouping(.never))
                        TextField("Timeout · seconds", value: model.integer(healthPath + ["timeout"]), format: .number.grouping(.never))
                        Stepper("Healthy threshold: \(model.integer(healthPath + ["healthy_threshold"]).wrappedValue)", value: model.integer(healthPath + ["healthy_threshold"]), in: 2...10)
                        Stepper("Unhealthy threshold: \(model.integer(healthPath + ["unhealthy_threshold"]).wrappedValue)", value: model.integer(healthPath + ["unhealthy_threshold"]), in: 2...10)
                        Text("Interval 5–300s, timeout 2–120s and less than interval. TCP health checks omit path and matcher.").font(.caption).foregroundStyle(.secondary)
                    }
                    Section("Target group tag overrides") { TagsEditor(model: model, path: groupPath + ["tags"]) }
                }.formStyle(.grouped).id(current)
            }
        }.sheet(isPresented: $showAdd) { NamedLBChildView(title: "Add target group", existing: keys) { key in model.set(LoadBalancerConfiguration.targetGroup(network: network), path: path + ["target_groups", key]); selected = key } }
            .confirmationDialog("Remove target group '\(current)'?", isPresented: $remove, titleVisibility: .visible) { Button("Remove target group", role: .destructive) { model.removeTargetGroup(loadBalancer: lbKey, key: current) } } message: { Text("Listeners must be unlinked first. This also removes this group's target attachments from the configuration.") }
    }
}
struct ListenersEditor: View {
    @ObservedObject var model: Workspace
    let path: [String]
    let network: Bool
    @State private var selected = ""
    @State private var showAdd = false
    @State private var remove = false
    var keys: [String] { model.document.at(path + ["listeners"]).object.keys.sorted() }
    var groups: [String] { model.document.at(path + ["target_groups"]).object.keys.sorted() }
    var current: String { keys.contains(selected) ? selected : keys.first ?? "" }
    var listenerPath: [String] { path + ["listeners", current] }
    var secure: Bool { ["HTTPS", "TLS"].contains(model.document.at(listenerPath + ["protocol"]).text) }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("Listener", selection: Binding(get: { current }, set: { selected = $0 })) { ForEach(keys, id: \.self) { Text($0).tag($0) } }
                Button("Add…") { showAdd = true }.disabled(groups.isEmpty)
                Button { remove = true } label: { Image(systemName: "minus.circle") }.disabled(current.isEmpty).help("Remove listener")
            }.padding(.horizontal, 20).padding(.vertical, 12)
            if current.isEmpty { Text(groups.isEmpty ? "Create a target group first, then add a listener." : "Add a listener to receive traffic and forward it to a target group.").foregroundStyle(.secondary).padding(); Spacer() }
            else {
                Form {
                    Section("Frontend traffic") {
                        Picker("Protocol", selection: Binding(get: { model.document.at(listenerPath + ["protocol"]).text }, set: { value in model.set(LoadBalancerConfiguration.listenerProtocol(value, listener: model.document.at(listenerPath)), path: listenerPath) })) { ForEach(network ? ["TCP", "TLS", "UDP", "TCP_UDP"] : ["HTTP", "HTTPS"], id: \.self) { Text($0).tag($0) } }
                        TextField("Listen on port", value: model.integer(listenerPath + ["port"]), format: .number.grouping(.never))
                        Picker("Forward to target group", selection: model.text(listenerPath + ["target_group_key"])) {
                            ForEach(groups, id: \.self) { Text($0).tag($0) }
                            let target = model.document.at(listenerPath + ["target_group_key"]).text
                            if !groups.contains(target) { Text("Missing: " + target).tag(target) }
                        }
                        Text("Listener ports must be unique. Review validates listener/target-group protocol compatibility.").font(.caption).foregroundStyle(.secondary)
                    }
                    if secure {
                        Section("Required · TLS certificate") {
                            TextField("Existing certificate ARN", text: model.text(listenerPath + ["certificate_arn"], optional: true))
                            TextField("SSL policy · optional", text: model.text(listenerPath + ["ssl_policy"], optional: true))
                            Text("Use an existing ACM or IAM certificate compatible with the load balancer region. Certificate creation is not part of this resource.").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Section("Traffic path") {
                        let target = model.document.at(listenerPath + ["target_group_key"]).text
                        Text("Listener \(current) → Target group \(target)")
                        Text("Target attachments resolve project EC2 IDs or IPs automatically after Terraform creates them.").font(.caption).foregroundStyle(.secondary)
                    }
                }.formStyle(.grouped).id(current)
            }
        }.sheet(isPresented: $showAdd) { NamedLBChildView(title: "Add listener", existing: keys) { key in model.set(LoadBalancerConfiguration.listener(network: network, target: groups.first ?? ""), path: path + ["listeners", key]); selected = key } }
            .confirmationDialog("Remove listener '\(current)'?", isPresented: $remove, titleVisibility: .visible) { Button("Remove listener", role: .destructive) { model.remove(path: listenerPath) } } message: { Text("A later Terraform plan may remove this listener. At least one listener is required before generating.") }
    }
}
