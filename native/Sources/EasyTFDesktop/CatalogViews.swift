import SwiftUI

struct ResourceCatalogView: View {
    @ObservedObject var model: Workspace
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var selected: String?
    @State private var key = ""
    var categories: [String] { Set(model.catalog.map(\.category)).sorted() }
    var definition: CatalogDefinition? { model.catalog.first { $0.id == selected } }
    var valid: Bool { definition != nil && key.range(of: "^[a-zA-Z][a-zA-Z0-9_-]*$", options: .regularExpression) != nil && !model.keys("managed_resources").contains(key) }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("AWS resource catalog").font(.title2).fontWeight(.semibold)
            Text("RDS, Aurora, EKS, storage, networking, IAM, DNS, and edge · AWS provider 6.68.0").font(.caption).foregroundStyle(.secondary)
            TextField("Search resource or category", text: $query).textFieldStyle(.roundedBorder)
            HSplitView {
                List(selection: $selected) {
                    ForEach(categories, id: \.self) { category in
                        let definitions = model.catalog.filter { $0.category == category && (query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) || $0.id.localizedCaseInsensitiveContains(query) || category.localizedCaseInsensitiveContains(query)) }
                        if !definitions.isEmpty { Section(category) { ForEach(definitions) { Text($0.title).tag($0.id) } } }
                    }
                }.frame(minWidth: 240, idealWidth: 270)
                VStack(alignment: .leading, spacing: 14) {
                    if let definition = definition {
                        Text(definition.title).font(.title3).fontWeight(.semibold)
                        Text(definition.id).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                        Text("Create a resource key, configure required fields, then link inputs to other resources or enter existing AWS values.").font(.callout).foregroundStyle(.secondary)
                        TextField("Resource key, e.g. database", text: $key).textFieldStyle(.roundedBorder)
                        if model.keys("managed_resources").contains(key) { Text("That resource key already exists.").font(.caption).foregroundStyle(.orange) }
                        if ["aws_db_instance", "aws_rds_cluster"].contains(definition.id) { Text("Defaults use AWS-managed master credentials, encrypted storage, and deletion protection. No database password is stored in tfvars.").font(.caption).foregroundStyle(.secondary) }
                        if definition.category == "Kubernetes" { Text("Configure cluster IAM access explicitly. Managed node groups and Fargate profiles are separate resources that link to the cluster.").font(.caption).foregroundStyle(.secondary) }
                        Spacer()
                    } else { Text("Choose a resource to configure.").foregroundStyle(.secondary); Spacer() }
                }.padding(16).frame(minWidth: 260)
            }
            HStack { Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction); Spacer(); Button("Add resource") { if let definition = definition { model.addCatalog(definition, key: key) } }.buttonStyle(.borderedProminent).disabled(!valid).keyboardShortcut(.defaultAction) }
        }.padding(24).frame(width: 760, height: 570).onAppear { query = model.catalogFilter }
    }
}
struct CatalogResourceEditor: View {
    @ObservedObject var model: Workspace
    let key: String
    @State private var remove = false
    var path: [String] { model.valuesPath + ["managed_resources", key] }
    var definition: CatalogDefinition? { model.catalog.first { $0.id == model.document.at(path + ["kind"]).text } }
    var body: some View {
        VStack(spacing: 0) {
            HStack { ResourceLabel(title: key, symbol: "shippingbox", color: Theme.loadBalancer).font(.title2).fontWeight(.semibold); Spacer(); Button { remove = true } label: { Image(systemName: "trash") } }.padding(20).background(Theme.loadBalancer.opacity(0.06))
            if let definition = definition {
                Form {
                    if definition.id == "aws_iam_role" {
                        Section("AWS service trust") {
                            Picker("Trust service", selection: Binding(get: {
                                let text = model.document.at(path + ["configuration", "assume_role_policy"]).text
                                return (try? JSONValue.parse(text))?["Statement"].array.first?["Principal"]["Service"].text ?? ""
                            }, set: { service in
                                guard !service.isEmpty else { return }
                                let policy: JSONValue = .object(["Version": .string("2012-10-17"), "Statement": .array([.object(["Effect": .string("Allow"), "Principal": .object(["Service": .string(service)]), "Action": .string("sts:AssumeRole")])])])
                                model.set(.string(policy.pretty()), path: path + ["configuration", "assume_role_policy"])
                            })) {
                                Text("Custom / existing policy").tag("")
                                Text("EC2 / EKS managed nodes").tag("ec2.amazonaws.com")
                                Text("EKS cluster").tag("eks.amazonaws.com")
                                Text("EKS Fargate pods").tag("eks-fargate-pods.amazonaws.com")
                                Text("Lambda").tag("lambda.amazonaws.com")
                                Text("RDS").tag("rds.amazonaws.com")
                            }
                            Text("Choosing a service replaces the trust policy below. Keep Custom for policies with account principals or additional conditions.").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Section(definition.title) {
                        Text("Required fields are shown first. Add optional settings as needed; link IDs, ARNs, or names instead of copying Terraform outputs.").font(.caption).foregroundStyle(.secondary)
                        CatalogObjectEditor(model: model, resourceKey: key, schema: definition.schema, path: path + ["configuration"], relative: [])
                    }
                    Section("Additional creation dependencies") {
                        Text("References create dependencies automatically. Use explicit dependencies for prerequisites such as IAM policy attachments before an EKS cluster or node group.").font(.caption).foregroundStyle(.secondary)
                        ForEach(model.keys("managed_resources").filter { $0 != key }, id: \.self) { other in
                            Toggle(other, isOn: Binding(get: { model.document.at(path + ["depends_on"]).array.contains(.string(other)) }, set: { enabled in let old = model.document.at(path + ["depends_on"]).array.filter { $0 != .string(other) }; model.set(.array(enabled ? old + [.string(other)] : old), path: path + ["depends_on"]) })).toggleStyle(.checkbox)
                        }
                    }
                    if definition.schema["properties"].object["tags"] != nil { Section("Resource tag overrides") { TagsEditor(model: model, path: path + ["tags"]) } }
                    Section("Available outputs") { Text(definition.outputs.keys.sorted().joined(separator: ", ")).font(.system(.caption, design: .monospaced)).textSelection(.enabled); Text("Choose this resource and an output from another field's Link… picker. Terraform resolves the value after creation.").font(.caption).foregroundStyle(.secondary) }
                }.formStyle(.grouped)
            } else { Text("Resource schema unavailable. Reopen using the matching EasyTF engine.").padding(); Spacer() }
        }.confirmationDialog("Remove resource '\(key)'?", isPresented: $remove, titleVisibility: .visible) { Button("Remove resource", role: .destructive) { model.delete(kind: "managed_resources", key: key) } } message: { Text("References must be unlinked first. A later Terraform plan may propose destroying previously deployed infrastructure.") }
    }
}
struct CatalogObjectEditor: View {
    @ObservedObject var model: Workspace
    let resourceKey: String
    let schema: JSONValue
    let path: [String]
    let relative: [String]
    @State private var optionalKey = ""
    var properties: [String: JSONValue] { schema["properties"].object.filter { $0.key != "tags" || !relative.isEmpty } }
    var visible: [String] { properties.keys.filter { properties[$0]?["required"].bool == true || model.document.at(path).object[$0] != nil }.sorted { let a = properties[$0]?["required"].bool ?? false; let b = properties[$1]?["required"].bool ?? false; return a != b ? a : $0 < $1 } }
    var optional: [String] { properties.keys.filter { !visible.contains($0) }.sorted() }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(visible, id: \.self) { field in
                CatalogFieldEditor(model: model, resourceKey: resourceKey, name: field, schema: properties[field]!, path: path + [field], relative: relative + [field])
            }
            if !optional.isEmpty {
                HStack {
                    Picker("Optional setting", selection: $optionalKey) { Text("Choose a setting…").tag(""); ForEach(optional, id: \.self) { Text($0.replacingOccurrences(of: "_", with: " ")).tag($0) } }
                    Button("Add") { if let node = properties[optionalKey] { model.set(.blank(for: node), path: path + [optionalKey]); optionalKey = "" } }.disabled(optionalKey.isEmpty)
                }
            }
        }
    }
}
struct CatalogFieldEditor: View {
    @ObservedObject var model: Workspace
    let resourceKey: String
    let name: String
    let schema: JSONValue
    let path: [String]
    let relative: [String]
    var allowLinks = true
    @State private var showReferences = false
    @State private var mapKey = ""
    var kind: String { schema["kind"].text }
    var pointer: String { "/" + relative.joined(separator: "/") }
    var linksPath: [String] { model.valuesPath + ["managed_resources", resourceKey, "links", pointer] }
    var links: [JSONValue] { model.document.at(linksPath).array }
    var linkable: Bool { allowLinks && (kind == "string" || (kind == "list" && schema["element"]["kind"].text == "string")) }
    var title: String { name.replacingOccurrences(of: "_", with: " ").capitalized }
    var body: some View {
        AnyView(VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(title).font(.callout).fontWeight(.medium)
                Text(schema["required"].bool ? "Required" : "Optional").font(.caption2).foregroundStyle(.secondary)
                Spacer()
                if linkable { Button(links.isEmpty ? "Link…" : "Edit links…") { showReferences = true }.font(.caption) }
                if !schema["required"].bool { Button { model.removeCatalogValue(resourceKey: resourceKey, path: path, relative: relative) } label: { Image(systemName: "minus.circle") }.buttonStyle(.borderless).help("Unset this optional setting") }
            }
            if !schema["help"].text.isEmpty { Text(schema["help"].text).font(.caption).foregroundStyle(.secondary).lineLimit(3).help(schema["help"].text) }
            if !links.isEmpty { Text(links.map { $0["resource_key"].text + "." + $0["output"].text }.joined(separator: ", ")).font(.system(.caption, design: .monospaced)).foregroundStyle(Theme.loadBalancer) }
            input.disabled(kind != "list" && !links.isEmpty)
            Divider()
        }.sheet(isPresented: $showReferences) { CatalogReferencesView(model: model, resourceKey: resourceKey, linksPath: linksPath, multiple: kind == "list", expectedKind: kind == "list" ? schema["element"]["kind"].text : kind) })
    }
    @ViewBuilder var input: some View {
        switch kind {
        case "string":
            if name.contains("policy") || name.contains("user_data") {
                TextEditor(text: model.text(path)).font(.system(.caption, design: .monospaced)).frame(minHeight: 100).border(Color.secondary.opacity(0.2))
            } else { TextField(title, text: model.text(path)).textFieldStyle(.roundedBorder) }
        case "bool": Toggle(title, isOn: model.bool(path)).toggleStyle(.checkbox).labelsHidden().accessibilityLabel(title)
        case "number": TextField(title, value: Binding(get: { model.document.at(path).number }, set: { model.set(.number($0), path: path) }), format: .number.grouping(.never)).textFieldStyle(.roundedBorder)
        case "object": CatalogObjectEditor(model: model, resourceKey: resourceKey, schema: schema, path: path, relative: relative).padding(.leading, 10)
        case "list":
            VStack(alignment: .leading, spacing: 10) {
                ForEach(model.document.at(path).array.indices, id: \.self) { index in
                    HStack(alignment: .top) {
                        CatalogFieldEditor(model: model, resourceKey: resourceKey, name: "Item \(index + 1)", schema: schema["element"], path: path + [String(index)], relative: relative + [String(index)], allowLinks: false)
                        Button { model.removeCatalogValue(resourceKey: resourceKey, path: path + [String(index)], relative: relative + [String(index)]) } label: { Image(systemName: "trash") }.buttonStyle(.borderless)
                    }
                }
                Button("Add item / block") { model.set(.array(model.document.at(path).array + [.blank(for: schema["element"])]), path: path) }
            }.padding(.leading, 10)
        case "map":
            VStack(alignment: .leading, spacing: 9) {
                ForEach(model.document.at(path).object.keys.sorted(), id: \.self) { key in CatalogFieldEditor(model: model, resourceKey: resourceKey, name: key, schema: schema["element"], path: path + [key], relative: relative + [key], allowLinks: false) }
                HStack { TextField("New key", text: $mapKey).textFieldStyle(.roundedBorder); Button("Add entry") { model.set(.blank(for: schema["element"]), path: path + [mapKey]); mapKey = "" }.disabled(mapKey.isEmpty || model.document.at(path).object[mapKey] != nil) }
            }.padding(.leading, 10)
        default: Text("Unsupported schema field").foregroundStyle(.orange)
        }
    }
}
struct CatalogReferencesView: View {
    @ObservedObject var model: Workspace
    let resourceKey: String
    let linksPath: [String]
    let multiple: Bool
    let expectedKind: String
    @Environment(\.dismiss) private var dismiss
    @State private var selected: Set<String> = []
    @State private var query = ""
    var candidates: [(id: String, key: String, output: String)] {
        var result: [(String,String,String)] = []
        for key in model.keys("managed_resources") where key != resourceKey {
            let kind = model.values["managed_resources"][key]["kind"].text
            if let definition = model.catalog.first(where: { $0.id == kind }) {
                for output in definition.outputs.keys.sorted() where definition.outputs[output]?.text == expectedKind { result.append((key + "#" + output,key,output)) }
            }
        }
        if expectedKind == "string" {
            for (collection,prefix,outputs) in [("instances","ec2:",["id","private_ip","public_ip"]),("security_groups","sg:",["id","vpc_id"]),("load_balancers","lb:",["arn","dns_name","zone_id"])] {
                for key in model.keys(collection) { for output in outputs { result.append((prefix + key + "#" + output,prefix + key,output)) } }
            }
        }
        return result.filter { query.isEmpty || ($0.1 + " " + $0.2).localizedCaseInsensitiveContains(query) }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Link a Terraform output").font(.title2)
            Text(multiple ? "Select one or more outputs. Literal entries in this list are retained." : "Select one output. It replaces the literal value while linked.").font(.caption).foregroundStyle(.secondary)
            TextField("Search resource or output", text: $query).textFieldStyle(.roundedBorder)
            List(candidates, id: \.id) { candidate in
                Button {
                    if multiple { if selected.contains(candidate.id) { selected.remove(candidate.id) } else { selected.insert(candidate.id) } }
                    else { selected = [candidate.id] }
                } label: { HStack { Image(systemName: selected.contains(candidate.id) ? "checkmark.circle.fill" : "circle"); Text(candidate.key); Spacer(); Text(candidate.output).foregroundStyle(.secondary) } }.buttonStyle(.plain)
            }
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Clear links") { model.remove(path: linksPath); dismiss() }
                Spacer()
                Button("Use selected outputs") {
                    let references = selected.sorted().compactMap { item -> JSONValue? in
                        let parts = item.split(separator: "#", maxSplits: 1).map(String.init); guard parts.count == 2 else { return nil }
                        return .object(["resource_key": .string(parts[0]), "output": .string(parts[1])])
                    }
                    model.set(.array(references), path: linksPath); dismiss()
                }.buttonStyle(.borderedProminent).disabled(selected.isEmpty)
            }
        }.padding(24).frame(width: 600, height: 480).onAppear { selected = Set(model.document.at(linksPath).array.map { $0["resource_key"].text + "#" + $0["output"].text }) }
    }
}
