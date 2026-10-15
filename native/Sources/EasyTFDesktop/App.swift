import SwiftUI
import AppKit

@main struct EasyTFApp: App {
    @StateObject private var model = Workspace()
    @State private var discardAction: String?
    var body: some Scene {
        WindowGroup("EasyTF") {
            WorkspaceView(model: model, newProject: { request("new") }, openProject: { request("open") })
                .frame(minWidth: 980, minHeight: 640).tint(Theme.accent)
                .alert("Discard unsaved changes?", isPresented: Binding(get: { discardAction != nil }, set: { if !$0 { discardAction = nil } })) {
                    Button("Cancel", role: .cancel) { discardAction = nil }
                    Button("Discard changes", role: .destructive) { let action = discardAction; discardAction = nil; execute(action ?? "") }
                } message: { Text("Your edits have not been generated to disk yet.") }
        }.defaultSize(width: 1180, height: 780).commands {
            CommandGroup(replacing: .newItem) {
                Button("New Project…") { request("new") }.keyboardShortcut("n").disabled(model.busy)
                Button("Open Project…") { request("open") }.keyboardShortcut("o").disabled(model.busy)
            }
            CommandGroup(replacing: .saveItem) { Button("Review Terraform") { model.review() }.keyboardShortcut("s").disabled(!model.opened || model.busy) }
        }
    }
    func request(_ action: String) { if model.dirty { discardAction = action } else { execute(action) } }
    func execute(_ action: String) { if action == "new" { model.showNew = true } else { model.chooseProject() } }
}

struct WorkspaceView: View {
    @ObservedObject var model: Workspace
    let newProject: () -> Void
    let openProject: () -> Void
    var body: some View {
        VStack(spacing: 0) {
            if model.opened {
                HSplitView {
                    sidebar.frame(minWidth: 230, idealWidth: 250, maxWidth: 310)
                    VStack(spacing: 0) {
                        HStack {
                            Image(systemName: "square.stack.3d.up.fill").foregroundStyle(Theme.accent)
                            Text(model.title).font(.headline)
                            EnvironmentBadge(name: model.environment)
                            if model.dirty { Text("Edited").font(.caption).foregroundStyle(.secondary) }
                            Spacer()
                            Picker("Environment", selection: $model.environment) { ForEach(model.environments, id: \.self) { Text($0).tag($0) } }.frame(width: 190)
                                .onChange(of: model.environment) { _ in model.selection = "environment" }
                        }.padding(16).background(Theme.environment(model.environment).opacity(0.06))
                        Divider()
                        editor.frame(maxWidth: .infinity, maxHeight: .infinity).disabled(model.busy)
                    }.frame(minWidth: 500)
                    inspector.frame(minWidth: 210, idealWidth: 230, maxWidth: 280)
                }
                Divider()
                HStack {
                    if model.busy { ProgressView().controlSize(.small); Text("Working…"); Button("Cancel") { model.cancel() }.disabled(!model.canCancel) }
                    else { Image(systemName: "doc.text"); Text(model.status.isEmpty ? "Ready" : model.status) }
                    Spacer()
                    Button { if let root = model.root { NSWorkspace.shared.open(root) } } label: { Label("Project folder", systemImage: "folder") }
                }.font(.caption).padding(10)
            } else {
                VStack(alignment: .leading, spacing: 20) {
                    Image(systemName: "square.stack.3d.up.fill").font(.system(size: 44)).foregroundStyle(Color.accentColor)
                    Text("Infrastructure, clearly configured.").font(.largeTitle).fontWeight(.semibold)
                    Text("Build Terraform projects with native forms.\nUse existing AWS resources and keep every environment separate.").font(.title3).foregroundStyle(.secondary)
                    if model.draftAvailable { Button("Resume last workspace") { model.resumeDraft() }.buttonStyle(.borderedProminent) }
                    HStack { Button("New Project…", action: newProject).buttonStyle(.borderedProminent); Button("Open EasyTF Project…", action: openProject) }
                    Text("The same project works in the EasyTF CLI. Generating files does not deploy infrastructure.").font(.callout).foregroundStyle(.secondary)
                }.padding(40).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
        }
        .toolbar {
            ToolbarItemGroup {
                Button(action: newProject) { Label("New project", systemImage: "plus") }.disabled(model.busy)
                Button(action: openProject) { Label("Open project", systemImage: "folder") }.disabled(model.busy)
                if model.opened { Button("Review Terraform") { model.review() }.disabled(model.busy) }
            }
        }
        .sheet(isPresented: $model.showCatalog) { ResourceCatalogView(model: model) }
        .sheet(isPresented: $model.showNew) { NewProjectView(model: model) }
        .sheet(isPresented: Binding(get: { model.addKind != nil }, set: { if !$0 { model.addKind = nil } })) { AddResourceView(model: model) }
        .sheet(isPresented: Binding(get: { model.discoveryKind != nil }, set: { if !$0 { model.cancel(); model.discoveryKind = nil } })) { DiscoveryView(model: model) }
        .alert("EasyTF needs your attention", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) { Button("OK") { model.error = nil } } message: { Text(model.error ?? "") }
    }
    var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                Image(systemName: "square.stack.3d.up.fill").foregroundStyle(Theme.accent)
                Text("PROJECT WORKSPACE").font(.caption).fontWeight(.semibold).foregroundStyle(.secondary)
            }.padding(16)
            List(selection: $model.selection) {
                ResourceLabel(title: "Environment settings", symbol: "slider.horizontal.3", color: Theme.accent).tag("environment")
                Section("EC2 instances") { ForEach(model.keys("instances"), id: \.self) { ResourceLabel(title: $0, symbol: "server.rack", color: Theme.ec2).tag("ec2:" + $0) } }
                Section("Security groups") { ForEach(model.keys("security_groups"), id: \.self) { ResourceLabel(title: $0, symbol: "checkmark.shield", color: Theme.securityGroup).tag("sg:" + $0) } }
                Section("Load balancers") { ForEach(model.keys("load_balancers"), id: \.self) { ResourceLabel(title: $0, symbol: "network", color: Theme.loadBalancer).tag("lb:" + $0) } }
                ForEach(Set(model.catalog.map(\.category)).sorted(), id: \.self) { category in
                    let keys = model.keys("managed_resources").filter { key in model.catalog.first { $0.id == model.values["managed_resources"][key]["kind"].text }?.category == category }
                    if !keys.isEmpty { Section(category) { ForEach(keys, id: \.self) { ResourceLabel(title: $0, symbol: "shippingbox", color: Theme.loadBalancer).tag("managed:" + $0) } } }
                }
                ResourceLabel(title: "Terraform review", symbol: "doc.text.magnifyingglass", color: Theme.accent).tag("review")
            }.listStyle(.sidebar).disabled(model.busy)
            Divider()
            Menu {
                Button("EC2 instance") { model.addKind = "instances" }
                Button("Security group") { model.addKind = "security_groups" }
                Divider()
                Button("Application Load Balancer · ALB") { model.addKind = "application" }
                Button("Network Load Balancer · NLB") { model.addKind = "network" }
                Divider()
                ForEach(Set(model.catalog.map(\.category)).sorted(), id: \.self) { category in
                    Button(category + "…") { model.catalogFilter = category; model.showCatalog = true }
                }
                Divider()
                Button("All AWS resources…") { model.catalogFilter = ""; model.showCatalog = true }
            } label: { Label("Add resource", systemImage: "plus") }.padding(14).disabled(model.busy)
        }
    }
    @ViewBuilder var editor: some View {
        if let selection = model.selection, selection.hasPrefix("ec2:") { InstanceEditor(model: model, key: String(selection.dropFirst(4))).id(model.environment + selection) }
        else if let selection = model.selection, selection.hasPrefix("sg:") { SecurityGroupEditor(model: model, key: String(selection.dropFirst(3))).id(model.environment + selection) }
        else if let selection = model.selection, selection.hasPrefix("lb:") { LoadBalancerEditor(model: model, key: String(selection.dropFirst(3))).id(model.environment + selection) }
        else if let selection = model.selection, selection.hasPrefix("managed:") { CatalogResourceEditor(model: model, key: String(selection.dropFirst(8))).id(model.environment + selection) }
        else if model.selection == "review" { ReviewView(model: model) }
        else { EnvironmentEditor(model: model).id(model.environment) }
    }
    var inspector: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Environment summary").font(.headline)
                EnvironmentBadge(name: model.environment)
                Label(model.values["aws_region"].text, systemImage: "globe")
                Label(model.values["aws_profile"].text.isEmpty ? "Default AWS credentials" : model.values["aws_profile"].text, systemImage: "person.badge.key")
                Divider()
                Label("Inherited tags", systemImage: "tag.fill").font(.headline).foregroundStyle(Theme.securityGroup)
                ForEach(model.values["tags"].object.keys.sorted(), id: \.self) { key in VStack(alignment: .leading) { Text(key).font(.caption).foregroundStyle(.secondary); Text(model.values["tags"][key].text).textSelection(.enabled) } }
                Text("Applied to every managed resource. Resource tags override matching keys.").font(.caption).foregroundStyle(.secondary)
                Divider()
                Label("Dependencies", systemImage: "point.3.connected.trianglepath.dotted").font(.headline).foregroundStyle(Theme.loadBalancer)
                ForEach(model.keys("instances"), id: \.self) { key in
                    VStack(alignment: .leading, spacing: 5) {
                        ResourceLabel(title: key, symbol: "server.rack", color: Theme.ec2).fontWeight(.medium)
                        Text("Subnet: " + model.values["instances"][key]["subnet_id"].text).font(.caption)
                        ForEach(model.values["instances"][key]["security_group_keys"].array.map(\.text), id: \.self) { Text("↳ Security group: " + $0).font(.caption) }
                    }
                }
                ForEach(model.keys("load_balancers"), id: \.self) { key in
                    VStack(alignment: .leading, spacing: 5) {
                        ResourceLabel(title: key, symbol: "network", color: Theme.loadBalancer).fontWeight(.medium)
                        ForEach(model.values["load_balancers"][key]["listeners"].object.keys.sorted(), id: \.self) { listener in
                            Text("↳ Listener " + listener + " → " + model.values["load_balancers"][key]["listeners"][listener]["target_group_key"].text).font(.caption)
                        }
                        ForEach(model.values["load_balancers"][key]["target_groups"].object.keys.sorted(), id: \.self) { group in
                            let targets = model.values["load_balancers"][key]["target_groups"][group]["instance_keys"].array.map(\.text)
                            Text("↳ " + group + " → " + (targets.isEmpty ? "existing / unregistered targets" : targets.joined(separator: ", "))).font(.caption)
                        }
                    }
                }
                Divider()
                Text("Generation only").font(.headline)
                Text("AWS pickers are read-only. Terraform init, plan, and apply are not run by this version.").font(.caption).foregroundStyle(.secondary)
            }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
        }.background(Color(nsColor: .controlBackgroundColor))
    }
}
